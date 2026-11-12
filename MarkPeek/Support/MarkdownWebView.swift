import SwiftUI
import WebKit

/// Talks to the live preview's web view: zoom, scrolling to headings, find.
@MainActor
final class PreviewController: ObservableObject {
    static let shared = PreviewController()

    private(set) weak var webView: WKWebView?

    @Published var zoom: Double = UserDefaults.standard.object(forKey: "readerZoom") as? Double ?? 1.0 {
        didSet {
            UserDefaults.standard.set(zoom, forKey: "readerZoom")
            webView?.pageZoom = zoom
        }
    }
    @Published var findText = ""
    @Published private(set) var findCount: Int?
    /// Source lines the editor should highlight: the block under the mouse in
    /// either pane, in split view.
    @Published private(set) var editorHighlight: ClosedRange<Int>?
    private var lastEditorLine: Int?

    static let zoomSteps: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    func attach(_ webView: WKWebView) {
        self.webView = webView
        webView.pageZoom = zoom
    }

    // MARK: Zoom

    func zoomIn() { zoom = Self.zoomSteps.first { $0 > zoom + 0.001 } ?? zoom }
    func zoomOut() { zoom = Self.zoomSteps.last { $0 < zoom - 0.001 } ?? zoom }
    func resetZoom() { zoom = 1.0 }

    // MARK: Navigation

    func scroll(toHeading id: String) {
        let js = "(function(){var e=document.getElementById(\(Self.json(id)));if(e){e.scrollIntoView({behavior:'smooth',block:'start'});}})();"
        webView?.evaluateJavaScript(js)
    }

    // MARK: Hover sync (split view)

    private var syncsHover: Bool { DocumentModel.shared.mode == .split }

    /// The mouse moved to `line` in the editor (nil when it left). Highlights
    /// the matching preview block and mirrors its line range in the editor.
    func editorHovered(line: Int?) {
        guard line != lastEditorLine else { return }
        lastEditorLine = line
        guard syncsHover, let webView else { editorHighlight = nil; return }
        webView.evaluateJavaScript("window.__mpHover(\(line ?? 0))") { [weak self] value, _ in
            Task { @MainActor in self?.editorHighlight = Self.lineRange(from: value as? String) }
        }
    }

    /// The mouse is over the preview block covering `range` (nil when none).
    fileprivate func previewHovered(_ range: String?) {
        editorHighlight = syncsHover ? Self.lineRange(from: range) : nil
    }

    // MARK: Layout inset

    /// Space the page leaves free on the left for the editor pane. Applied
    /// inside the page so the web view itself never has to be resized.
    private(set) var leftInset: CGFloat = 0

    func setLeftInset(_ inset: CGFloat, animated: Bool) {
        let rounded = max(0, inset.rounded())
        guard rounded != leftInset || animated else { return }
        leftInset = rounded
        webView?.evaluateJavaScript("window.__mpSetInset && window.__mpSetInset(\(rounded), \(animated))")
    }

    /// Turns the preview's hover tracking on or off; only Split links the panes.
    func syncHover(enabled: Bool) {
        webView?.evaluateJavaScript("window.__mpSetSync && window.__mpSetSync(\(enabled))")
        editorHighlight = nil
        lastEditorLine = nil
    }

    /// Parses a `data-line` value such as `"12-15"`.
    private static func lineRange(from value: String?) -> ClosedRange<Int>? {
        guard let value else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard let first = parts.first else { return nil }
        return first...max(first, parts.last ?? first)
    }

    /// Installed in the preview: reports the block under the mouse and
    /// highlights the block for a line hovered in the editor.
    static let hoverScript = """
    (function () {
      var current = null, enabled = false;
      window.__mpSetSync = function (on) { enabled = !!on; if (!enabled) set(null); };
      window.__mpSetInset = function (px, animate) {
        document.body.style.transition = animate ? 'padding-left 0.35s cubic-bezier(0.2, 0.9, 0.25, 1)' : 'none';
        document.documentElement.style.setProperty('--mp-inset', px + 'px');
      };
      function set(el) {
        if (el === current) return;
        if (current) current.classList.remove('mp-hover');
        current = el;
        if (el) el.classList.add('mp-hover');
      }
      function post(value) {
        try { window.webkit.messageHandlers.sourceHover.postMessage(value); } catch (e) {}
      }
      document.addEventListener('mousemove', function (e) {
        if (!enabled) return;
        var el = e.target && e.target.closest ? e.target.closest('[data-line]') : null;
        if (el === current) return;
        set(el);
        post(el ? el.getAttribute('data-line') : null);
      });
      document.documentElement.addEventListener('mouseleave', function () {
        if (!current) return;
        set(null);
        post(null);
      });
      window.__mpHover = function (line) {
        var best = null, bestSpan = Infinity;
        if (enabled && line > 0) {
          var all = document.querySelectorAll('[data-line]');
          for (var i = 0; i < all.length; i++) {
            var parts = all[i].getAttribute('data-line').split('-');
            var a = parseInt(parts[0], 10), b = parseInt(parts[1] || parts[0], 10);
            if (line < a || line > b) continue;
            if (b - a < bestSpan) { best = all[i]; bestSpan = b - a; }
          }
        }
        set(best);
        return best ? best.getAttribute('data-line') : null;
      };
    })();
    """

    // MARK: Find

    func findNext(backwards: Bool = false) {
        guard !findText.isEmpty, let webView else { return }
        let js = "window.find(\(Self.json(findText)), false, \(backwards), true, false, false, false);"
        webView.evaluateJavaScript(js)
    }

    func updateFindCount() {
        guard !findText.isEmpty, let webView else { findCount = nil; return }
        let js = """
        (function(n){ if(!n) return 0; var t=(document.body.innerText||'').toLowerCase(); n=n.toLowerCase();
          var c=0,i=0; while((i=t.indexOf(n,i))!==-1){c++; i+=n.length;} return c; })(\(Self.json(findText)))
        """
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            Task { @MainActor in self?.findCount = (value as? Int) ?? (value as? Double).map(Int.init) }
        }
    }

    func clearFind() {
        findText = ""
        findCount = nil
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges();")
    }

    private static func json(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [string])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}

/// Displays rendered HTML. Reloads only when the HTML actually changes, keeps
/// the reading position across re-renders of the same document, and opens
/// clicked links in the default browser instead of navigating away.
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    /// Identifies the document; a change resets the remembered scroll position.
    let documentID: String
    let baseURL: URL?
    let appearance: NSAppearance?
    /// The document preview drives zoom, find and hover sync; other
    /// instances (the guide window) stay independent.
    var isMainPreview = true

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let script = WKUserScript(source: PreviewController.hoverScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(context.coordinator, name: "sourceHover")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        if isMainPreview { PreviewController.shared.attach(webView) }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = appearance
        let coordinator = context.coordinator
        guard coordinator.lastHTML != html else { return }
        coordinator.lastHTML = html
        let sameDocument = coordinator.documentID == documentID
        coordinator.documentID = documentID
        let page = insetHTML(html)
        guard sameDocument, coordinator.hasLoaded else {
            coordinator.pendingScrollY = 0
            webView.loadHTMLString(page, baseURL: baseURL)
            return
        }
        // Remember where the reader was, then swap in the new HTML.
        webView.evaluateJavaScript("window.scrollY") { value, _ in
            coordinator.pendingScrollY = (value as? Double) ?? 0
            webView.loadHTMLString(page, baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Bakes the current editor inset into the page so a reload doesn't
    /// flash the content at the wrong position before the script runs.
    private func insetHTML(_ html: String) -> String {
        guard isMainPreview else { return html }
        let inset = Int(PreviewController.shared.leftInset)
        guard inset > 0, let range = html.range(of: "</head>") else { return html }
        return html.replacingCharacters(in: range, with: "<style>:root{--mp-inset:\(inset)px}</style></head>")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML = ""
        var documentID = ""
        var hasLoaded = false
        var pendingScrollY: Double = 0

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "sourceHover" else { return }
            PreviewController.shared.previewHovered(message.body as? String)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoaded = true
            if pendingScrollY > 0 {
                webView.evaluateJavaScript("window.scrollTo(0, \(pendingScrollY))")
                pendingScrollY = 0
            }
            guard webView === PreviewController.shared.webView else { return }
            PreviewController.shared.updateFindCount()
            PreviewController.shared.syncHover(enabled: DocumentModel.shared.mode == .split)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if navigationAction.navigationType == .linkActivated {
                if url.scheme == "about" || (url.fragment != nil && url.path.isEmpty) {
                    decisionHandler(.allow) // in-page anchor
                } else {
                    // Only ordinary web and mail links leave the app; anything
                    // else a document could carry (file:, custom schemes) is dropped.
                    if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                        NSWorkspace.shared.open(url)
                    }
                    decisionHandler(.cancel)
                }
                return
            }
            // The page itself (about:blank or the document's folder as base) may
            // load; script-driven navigation elsewhere may not.
            decisionHandler(url.scheme == "about" || url.isFileURL ? .allow : .cancel)
        }
    }
}
