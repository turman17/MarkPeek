import AppKit
import WebKit
import PDFKit

/// Renders HTML in an offscreen web view and writes a PDF, either paginated
/// (via the print system) or as one continuous page.
enum PDFExporter {

    enum Paper: String, CaseIterable, Identifiable {
        case a4, letter, legal, a5
        var id: String { rawValue }
        var name: String {
            switch self {
            case .a4: "A4"
            case .letter: "US Letter"
            case .legal: "US Legal"
            case .a5: "A5"
            }
        }
        /// Portrait size in points.
        var size: NSSize {
            switch self {
            case .a4: NSSize(width: 595.28, height: 841.89)
            case .letter: NSSize(width: 612, height: 792)
            case .legal: NSSize(width: 612, height: 1008)
            case .a5: NSSize(width: 419.53, height: 595.28)
            }
        }
    }

    enum Orientation: String, CaseIterable, Identifiable {
        case portrait, landscape
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
    }

    enum Margins: String, CaseIterable, Identifiable {
        case none, narrow, normal, wide
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var points: CGFloat {
            switch self {
            case .none: 0
            case .narrow: 28
            case .normal: 54
            case .wide: 72
            }
        }
    }

    enum PageLayout: String, CaseIterable, Identifiable {
        case pages, continuous
        var id: String { rawValue }
        var name: String {
            switch self {
            case .pages: "Pages"
            case .continuous: "Single long page"
            }
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case theme, light, dark
        var id: String { rawValue }
        var name: String {
            switch self {
            case .theme: "Follow theme"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    struct Options: Sendable {
        var paper: Paper = .a4
        var orientation: Orientation = .portrait
        var margins: Margins = .normal
        var layout: PageLayout = .pages
        var appearance: Appearance = .theme
        var pageNumbers = true
        var headerTitle = false

        var paperSize: NSSize {
            let s = paper.size
            return orientation == .portrait ? s : NSSize(width: s.height, height: s.width)
        }
    }

    enum ExportError: LocalizedError {
        case loadFailed, printFailed
        var errorDescription: String? {
            switch self {
            case .loadFailed: "The document couldn't be laid out for export."
            case .printFailed: "The PDF couldn't be written."
            }
        }
    }

    /// Picks the concrete palette a PDF should use: PDFs can't follow the
    /// system, so "theme" resolves to the theme's fixed appearance or light.
    static func resolvedScheme(for theme: Theme, preferred: Appearance?) -> ThemeColorScheme {
        switch preferred ?? .theme {
        case .light: return .light
        case .dark: return .dark
        case .theme:
            switch theme.appearance {
            case .dark: return .dark
            case .light, .system: return .light
            }
        }
    }

    // MARK: Export

    @MainActor
    static func export(html: String, baseURL: URL?, options: Options, scheme: ThemeColorScheme, to url: URL,
                       title: String = "") async throws {
        let paper = options.paperSize
        let margin = options.margins.points
        let contentWidth = paper.width - margin * 2
        let page = OffscreenPage(width: contentWidth, scheme: scheme)
        try await page.load(html: html, baseURL: baseURL)

        switch options.layout {
        case .continuous:
            let height = await page.contentHeight()
            page.resize(height: max(height, 100) + margin * 2)
            try await Task.sleep(for: .milliseconds(100))
            let data = try await page.webView.pdf(configuration: WKPDFConfiguration())
            try data.write(to: url, options: .atomic)
        case .pages:
            let info = NSPrintInfo()
            info.paperSize = paper
            info.orientation = options.orientation == .portrait ? .portrait : .landscape
            info.topMargin = margin
            info.bottomMargin = margin
            info.leftMargin = margin
            info.rightMargin = margin
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            let operation = page.webView.printOperation(with: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.view?.frame = NSRect(origin: .zero, size: paper)
            let success = await run(operation, for: NSApp.keyWindow ?? page.window)
            if !success { throw ExportError.printFailed }
            if options.pageNumbers || options.headerTitle {
                try decorate(pdfAt: url, title: options.headerTitle ? title : nil,
                             pageNumbers: options.pageNumbers, paper: paper, margin: margin, scheme: scheme)
            }
        }
    }

    /// Adds page numbers and an optional title line to every page of a PDF.
    private static func decorate(pdfAt url: URL, title: String?, pageNumbers: Bool,
                                 paper: NSSize, margin: CGFloat, scheme: ThemeColorScheme) throws {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { throw ExportError.printFailed }
        var mediaBox = CGRect(origin: .zero, size: paper)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw ExportError.printFailed }
        let color = scheme == .dark ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.45, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: color,
        ]
        let inset = max(18, margin * 0.5)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            context.beginPDFPage(nil)
            page.draw(with: .mediaBox, to: context)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            if pageNumbers {
                let text = NSAttributedString(string: "\(index + 1) / \(document.pageCount)", attributes: attributes)
                let size = text.size()
                text.draw(at: NSPoint(x: (paper.width - size.width) / 2, y: inset - size.height / 2))
            }
            if let title, !title.isEmpty {
                let text = NSAttributedString(string: title, attributes: attributes)
                let size = text.size()
                text.draw(at: NSPoint(x: margin, y: paper.height - inset - size.height / 2))
            }
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        try data.write(to: url, options: .atomic)
    }

    /// Writes `<name>.pdf` next to the document with the remembered options,
    /// or asks where to save when the folder isn't writable from the sandbox.
    @MainActor
    static func exportNextToFile(document: DocumentModel, theme: Theme, options: Options) async throws {
        guard let folder = document.folderURL else { return }
        let name = (document.title as NSString).deletingPathExtension + ".pdf"
        var target = folder.appendingPathComponent(name)
        if !FileManager.default.isWritableFile(atPath: folder.path) {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = name
            panel.directoryURL = folder
            guard panel.runModal() == .OK, let url = panel.url else { return }
            target = url
        }
        let scheme = resolvedScheme(for: theme, preferred: options.appearance)
        let features = MarkdownRenderer.features(of: document.draft)
        let html = MarkdownRenderer.document(
            markdown: document.draft, theme: theme,
            options: RenderOptions(surface: .print, colorScheme: scheme, imageResolver: document.imageResolver,
                                   scripts: ScriptLibrary.scripts(for: features, scheme: scheme)))
        try await export(html: html, baseURL: document.folderURL, options: options, scheme: scheme, to: target,
                         title: (document.title as NSString).deletingPathExtension)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    /// Shows the system print panel for the document.
    @MainActor
    static func print(html: String, baseURL: URL?, scheme: ThemeColorScheme, in window: NSWindow) async throws {
        let info = NSPrintInfo.shared
        let contentWidth = info.paperSize.width - info.leftMargin - info.rightMargin
        let page = OffscreenPage(width: contentWidth, scheme: scheme)
        try await page.load(html: html, baseURL: baseURL)
        let operation = page.webView.printOperation(with: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        _ = await run(operation, for: window)
    }

    @MainActor
    private static func run(_ operation: NSPrintOperation, for window: NSWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            let completion = PrintCompletion(continuation)
            operation.runModal(
                for: window,
                delegate: completion,
                didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: Unmanaged.passRetained(completion).toOpaque()
            )
        }
    }
}

// MARK: - Offscreen page

/// A web view parked in a hidden window; printing requires a window host.
@MainActor
private final class OffscreenPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    private var continuation: CheckedContinuation<Void, Error>?

    init(width: CGFloat, scheme: ThemeColorScheme) {
        let frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        webView = WKWebView(frame: frame)
        webView.appearance = NSAppearance.forScheme(scheme)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(html: String, baseURL: URL?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        // Give fonts and embedded images a moment to settle, and wait for
        // math/diagram engines when the page declares them.
        try await Task.sleep(for: .milliseconds(250))
        for _ in 0..<40 {
            let ready = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                webView.evaluateJavaScript("typeof window.__mpReady === 'undefined' ? true : window.__mpReady") { value, _ in
                    cont.resume(returning: (value as? Bool) ?? true)
                }
            }
            if ready { break }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func contentHeight() async -> CGFloat {
        await withCheckedContinuation { (cont: CheckedContinuation<CGFloat, Never>) in
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                cont.resume(returning: CGFloat((value as? Double) ?? 0))
            }
        }
    }

    func resize(height: CGFloat) {
        var frame = webView.frame
        frame.size.height = height
        window.setContentSize(frame.size)
        webView.frame = frame
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// AppKit may call the completion selector off the main thread; continuations are thread-safe.
private final class PrintCompletion: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume(returning: success)
        continuation = nil
        if let contextInfo {
            Unmanaged<PrintCompletion>.fromOpaque(contextInfo).release()
        }
    }
}
