import SwiftUI

/// Help ▸ Theme Guide: the bundled guide rendered with the active theme, so
/// reading it doubles as a preview of the theme.
struct GuideView: View {
    @ObservedObject private var themes = ThemeStore.shared
    @State private var markdown = GuideView.load()

    static let windowID = "theme-guide"

    var body: some View {
        LivePreview(
            markdown: markdown,
            theme: themes.active,
            scheme: themes.previewScheme,
            documentID: "theme-guide",
            generation: 0,
            baseURL: nil,
            imageResolver: nil,
            scripts: [],
            isMainPreview: false
        )
        .frame(minWidth: 560, minHeight: 480)
        .navigationTitle("Theme Guide")
    }

    private static func load() -> String {
        let url = Bundle.main.url(forResource: "Theme Guide", withExtension: "md", subdirectory: "Guide")
            ?? Bundle.main.url(forResource: "Theme Guide", withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "# Theme Guide\n\nThe guide is missing from this build."
        }
        return text
    }
}
