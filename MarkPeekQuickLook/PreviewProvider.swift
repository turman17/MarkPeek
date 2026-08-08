import QuickLookUI
import UniformTypeIdentifiers

// Data-based Quick Look preview: Finder invokes this when the user presses
// space on a .md file. Returns styled HTML that Quick Look renders natively.
class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let markdown = try Self.readText(at: request.fileURL)
        let settings = PreviewSettings.load()
        let htmlData = Data(MarkdownRenderer.html(from: markdown, settings: settings).utf8)

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
