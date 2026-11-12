import AppKit
import UniformTypeIdentifiers

/// Writes a single self-contained HTML file: theme CSS, embedded local
/// images, and the math/diagram engines when the document uses them.
enum HTMLExporter {
    @MainActor
    static func export(document: DocumentModel, theme: Theme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (document.title as NSString).deletingPathExtension + ".html"
        panel.directoryURL = document.folderURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let features = MarkdownRenderer.features(of: document.draft)
        let scheme: ThemeColorScheme? = theme.appearance == .system ? nil : (theme.appearance == .dark ? .dark : .light)
        let html = MarkdownRenderer.document(
            markdown: document.draft, theme: theme,
            options: RenderOptions(surface: .edgeToEdge, colorScheme: nil,
                                   imageResolver: document.imageResolver,
                                   scripts: ScriptLibrary.scripts(for: features, scheme: scheme)))
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            document.errorMessage = "Couldn't write the HTML file: \(error.localizedDescription)"
        }
    }
}
