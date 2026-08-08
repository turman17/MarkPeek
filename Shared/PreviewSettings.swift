import Foundation

// Full visual customization for markdown previews. Stored as JSON in the
// app-group defaults so the app and the Quick Look extension share it.
public struct PreviewSettings: Codable, Equatable, Sendable {

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system, light, dark

        public var displayName: String {
            switch self {
            case .system: "Follow System"
            case .light: "Always Light"
            case .dark: "Always Dark"
            }
        }
    }

    public struct ColorSet: Codable, Equatable, Sendable {
        public var background: String
        public var text: String
        public var heading: String
        public var link: String
        public var codeBackground: String
        public var codeText: String
        public var blockquoteText: String
        public var blockquoteBorder: String
        public var rule: String
    }

    // Identity
    public var presetName: String   // raw MarkdownStyle value, or "custom"

    // Typography
    public var bodyFont: String     // CSS font-family value (first family)
    public var codeFont: String
    public var fontSize: Double     // px
    public var lineHeight: Double
    public var headingWeight: Int   // 400...800
    public var headingUnderline: Bool  // GitHub-style border under h1/h2
    public var blockquoteItalic: Bool

    // Layout
    public var maxWidth: Double         // px; 0 = full width
    public var pagePadding: Double      // px vertical margin around content
    public var paragraphSpacing: Double // em
    public var codeBlockPadding: Double // px
    public var cornerRadius: Double     // px, inline code + code blocks

    // Colors
    public var appearance: Appearance
    public var light: ColorSet
    public var dark: ColorSet

    // MARK: - Presets (ported from FinderConvert's MarkdownStyle CSS)

    public static func preset(_ style: MarkdownStyle) -> PreviewSettings {
        switch style {
        case .modern:
            PreviewSettings(
                presetName: style.rawValue,
                bodyFont: "-apple-system", codeFont: "Menlo",
                fontSize: 16, lineHeight: 1.6, headingWeight: 700,
                headingUnderline: false, blockquoteItalic: false,
                maxWidth: 700, pagePadding: 40, paragraphSpacing: 1.0,
                codeBlockPadding: 16, cornerRadius: 3,
                appearance: .system,
                light: ColorSet(
                    background: "#FFFFFF", text: "#333333", heading: "#333333",
                    link: "#0969DA", codeBackground: "#F4F4F4", codeText: "#333333",
                    blockquoteText: "#666666", blockquoteBorder: "#DDDDDD", rule: "#DDDDDD"),
                dark: ColorSet(
                    background: "#1E1E1E", text: "#DDDDDD", heading: "#DDDDDD",
                    link: "#6CB2FF", codeBackground: "#2D2D2D", codeText: "#DDDDDD",
                    blockquoteText: "#AAAAAA", blockquoteBorder: "#444444", rule: "#444444"))
        case .serif:
            PreviewSettings(
                presetName: style.rawValue,
                bodyFont: "Georgia", codeFont: "Menlo",
                fontSize: 16, lineHeight: 1.7, headingWeight: 600,
                headingUnderline: false, blockquoteItalic: true,
                maxWidth: 650, pagePadding: 40, paragraphSpacing: 1.0,
                codeBlockPadding: 16, cornerRadius: 3,
                appearance: .system,
                light: ColorSet(
                    background: "#FFFFFF", text: "#222222", heading: "#222222",
                    link: "#7A5C2E", codeBackground: "#F7F5F0", codeText: "#222222",
                    blockquoteText: "#555555", blockquoteBorder: "#B8A98A", rule: "#D8D2C4"),
                dark: ColorSet(
                    background: "#1C1A17", text: "#DED8CC", heading: "#DED8CC",
                    link: "#C8A86A", codeBackground: "#2A2723", codeText: "#DED8CC",
                    blockquoteText: "#B0A892", blockquoteBorder: "#6E6045", rule: "#4A453B"))
        case .github:
            PreviewSettings(
                presetName: style.rawValue,
                bodyFont: "-apple-system", codeFont: "SF Mono",
                fontSize: 16, lineHeight: 1.5, headingWeight: 600,
                headingUnderline: true, blockquoteItalic: false,
                maxWidth: 760, pagePadding: 40, paragraphSpacing: 1.0,
                codeBlockPadding: 16, cornerRadius: 6,
                appearance: .system,
                light: ColorSet(
                    background: "#FFFFFF", text: "#1F2328", heading: "#1F2328",
                    link: "#0969DA", codeBackground: "#F6F8FA", codeText: "#1F2328",
                    blockquoteText: "#59636E", blockquoteBorder: "#D1D9E0", rule: "#D1D9E0"),
                dark: ColorSet(
                    background: "#0D1117", text: "#E6EDF3", heading: "#E6EDF3",
                    link: "#4493F8", codeBackground: "#161B22", codeText: "#E6EDF3",
                    blockquoteText: "#8D96A0", blockquoteBorder: "#30363D", rule: "#30363D"))
        case .plain:
            PreviewSettings(
                presetName: style.rawValue,
                bodyFont: "Helvetica", codeFont: "Courier",
                fontSize: 16, lineHeight: 1.4, headingWeight: 700,
                headingUnderline: false, blockquoteItalic: false,
                maxWidth: 0, pagePadding: 20, paragraphSpacing: 1.0,
                codeBlockPadding: 12, cornerRadius: 0,
                appearance: .system,
                light: ColorSet(
                    background: "#FFFFFF", text: "#000000", heading: "#000000",
                    link: "#000000", codeBackground: "#F0F0F0", codeText: "#000000",
                    blockquoteText: "#000000", blockquoteBorder: "#000000", rule: "#000000"),
                dark: ColorSet(
                    background: "#111111", text: "#EEEEEE", heading: "#EEEEEE",
                    link: "#EEEEEE", codeBackground: "#2A2A2A", codeText: "#EEEEEE",
                    blockquoteText: "#EEEEEE", blockquoteBorder: "#EEEEEE", rule: "#EEEEEE"))
        }
    }

    // MARK: - Persistence

    public static let appGroupID = "group.com.markpeek.app.shared"
    public static let defaultsKey = "previewSettings"
    private static let legacyStyleKey = "markdownStyle"

    public static func load() -> PreviewSettings {
        let defaults = UserDefaults(suiteName: appGroupID)
        if let data = defaults?.data(forKey: defaultsKey),
           let settings = try? JSONDecoder().decode(PreviewSettings.self, from: data) {
            return settings
        }
        // Migrate from the old preset-only preference
        if let raw = defaults?.string(forKey: legacyStyleKey),
           let style = MarkdownStyle(rawValue: raw) {
            return preset(style)
        }
        return preset(.modern)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Preset identity helpers

    /// True when presetName refers to one of the built-in styles.
    public var isBuiltinPreset: Bool { MarkdownStyle(rawValue: presetName) != nil }

    /// UUID of the selected user preset, if any.
    public var customPresetID: UUID? { UUID(uuidString: presetName) }

    // MARK: - CSS generation

    private func fontStack(_ family: String, monospace: Bool) -> String {
        let fallback = monospace ? "monospace" : "sans-serif"
        if family.hasPrefix("-apple-system") { return "-apple-system, \(fallback)" }
        return "'\(family)', \(fallback)"
    }

    private func rules(for c: ColorSet) -> String {
        """
        body { background: \(c.background); color: \(c.text); }
        h1, h2, h3, h4, h5, h6 { color: \(c.heading); }
        \(headingUnderline ? "h1, h2 { border-bottom: 1px solid \(c.rule); }" : "")
        a { color: \(c.link); }
        code { background: \(c.codeBackground); color: \(c.codeText); }
        blockquote { border-left-color: \(c.blockquoteBorder); color: \(c.blockquoteText); }
        hr { border-top-color: \(c.rule); }
        """
    }

    public var css: String {
        let width = maxWidth > 0 ? "max-width: \(Int(maxWidth))px; margin: \(Int(pagePadding))px auto;"
                                 : "margin: \(Int(pagePadding))px 20px;"
        let base = """
        body {
            font-family: \(fontStack(bodyFont, monospace: false));
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
            \(width)
            padding: 0 20px;
        }
        p { margin: 0 0 \(paragraphSpacing)em; }
        h1, h2, h3, h4, h5, h6 { margin-top: 1.5em; margin-bottom: 0.5em; font-weight: \(headingWeight); line-height: 1.25; }
        h1 { font-size: 2em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.25em; }
        h4 { font-size: 1.1em; }
        \(headingUnderline ? "h1, h2 { padding-bottom: 0.3em; }" : "")
        code { font-family: \(fontStack(codeFont, monospace: true)); padding: 2px 6px; border-radius: \(Int(cornerRadius))px; font-size: 0.9em; }
        pre code { display: block; padding: \(Int(codeBlockPadding))px; overflow-x: auto; }
        blockquote { border-left: 4px solid; margin: 0 0 \(paragraphSpacing)em; padding-left: 16px; \(blockquoteItalic ? "font-style: italic;" : "") }
        blockquote p { margin: 0; }
        ul, ol { margin: 0 0 \(paragraphSpacing)em; }
        hr { border: none; border-top: 1px solid; margin: 2em 0; }
        """

        switch appearance {
        case .light:
            return base + "\n" + rules(for: light)
        case .dark:
            return base + "\n" + rules(for: dark)
        case .system:
            return base + "\n" + rules(for: light) + """

            @media (prefers-color-scheme: dark) {
            \(rules(for: dark))
            }
            """
        }
    }
}

// MARK: - User preset library

public struct CustomPreset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var settings: PreviewSettings

    public init(id: UUID = UUID(), name: String, settings: PreviewSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}

public enum PresetLibrary {
    private static let key = "customPresets"

    public static func load() -> [CustomPreset] {
        guard let data = UserDefaults(suiteName: PreviewSettings.appGroupID)?.data(forKey: key),
              let presets = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            return []
        }
        return presets
    }

    public static func save(_ presets: [CustomPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults(suiteName: PreviewSettings.appGroupID)?.set(data, forKey: key)
    }
}
