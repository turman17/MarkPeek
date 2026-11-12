import AppKit
import WebKit

/// Runs the math and diagram engines once in a hidden web view and returns
/// the finished page with its scripts removed. Quick Look's HTML renderer
/// never runs JavaScript, so formulas and diagrams have to arrive as SVG.
@MainActor
final class ScriptBaker: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Bool, Never>?

    /// The baked HTML, or nil when loading failed or the engines took too long.
    static func bake(_ html: String, width: CGFloat) async -> String? {
        await ScriptBaker(width: width).run(html)
    }

    private init(width: CGFloat) {
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900))
        super.init()
        webView.navigationDelegate = self
    }

    private func run(_ html: String) async -> String? {
        // WebKit needs the network entitlement to start at all; the policy
        // keeps the page from using it (remote images, trackers).
        guard let head = html.range(of: "<head>") else { return nil }
        var html = html
        html.insert(contentsOf: "\n" + Self.offlinePolicy, at: head.upperBound)
        // A load that never reports back (the web process can fail to start
        // in an extension) must not hang the preview.
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.finish(false)
        }
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            loaded = cont
            webView.loadHTMLString(html, baseURL: nil)
        }
        timeout.cancel()
        guard ok else { return nil }
        // ScriptLibrary's ready script sets __mpReady once every engine finished.
        for _ in 0..<30 {
            if (try? await webView.evaluateJavaScript("window.__mpReady === true")) as? Bool == true {
                return try? await webView.evaluateJavaScript(Self.extract) as? String
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static let offlinePolicy = """
    <meta id="mp-offline" http-equiv="Content-Security-Policy" content="default-src 'none'; \
    script-src 'unsafe-inline' 'unsafe-eval'; style-src 'unsafe-inline'; img-src data:; font-src data:">
    """

    private static let extract = """
    document.querySelectorAll('script, #mp-offline').forEach(function (e) { e.remove(); });
    '<!DOCTYPE html>\\n' + document.documentElement.outerHTML;
    """

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(false)
    }

    private func finish(_ ok: Bool) {
        loaded?.resume(returning: ok)
        loaded = nil
    }
}
