import QuickLookUI
import UniformTypeIdentifiers
import os

// Data-based Quick Look preview: Finder invokes this when the user presses
// Space on a Markdown file. Returns styled HTML that Quick Look renders
// natively with whatever theme is active in the MarkPeek app.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let log = Logger(subsystem: "com.markpeek.app", category: "QuickLook")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        Self.log.info("preview requested for \(request.fileURL.lastPathComponent, privacy: .private)")
        let markdown: String
        do {
            markdown = try Self.readText(at: request.fileURL)
        } catch {
            Self.log.error("read failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let theme = ThemeStorage.loadActiveTheme()
        // Quick Look's data-based renderer has no base URL, so images next to
        // the file are embedded. The extension's read-only home-folder
        // entitlement makes that possible; only files inside the document's
        // folder are ever read.
        let folder = request.fileURL.deletingLastPathComponent()
        var options = RenderOptions(surface: .edgeToEdge, imageResolver: ImageEmbedder.resolver(folder: folder, containedOnly: true), inlineColors: true)
        var html = MarkdownRenderer.document(markdown: markdown, theme: theme, options: options)
        // Math and diagrams need their engines; run them offscreen and keep
        // the result. Without it the preview shows their source.
        let features = MarkdownRenderer.features(of: markdown)
        if features.math || features.mermaid {
            options.scripts = ScriptLibrary.scripts(for: features, scheme: nil)
            let live = MarkdownRenderer.document(markdown: markdown, theme: theme, options: options)
            if let baked = await ScriptBaker.bake(live, width: 800) {
                html = baked
            } else {
                Self.log.error("math/diagram rendering timed out; showing source")
            }
        }
        Self.log.info("rendered \(html.utf8.count) bytes with theme \(theme.name, privacy: .public)")
        let htmlData = Data(html.utf8)

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 900)
        ) { _ in htmlData }
        reply.title = request.fileURL.lastPathComponent
        reply.stringEncoding = .utf8
        return reply
    }

    private static func readText(at url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}
