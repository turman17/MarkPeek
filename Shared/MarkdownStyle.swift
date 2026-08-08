import Foundation

// Preset identifiers, matching FinderConvert's style names. The actual visual
// definitions live in PreviewSettings.preset(_:).
public enum MarkdownStyle: String, Codable, CaseIterable, Sendable {
    case modern
    case serif
    case github
    case plain

    public var displayName: String {
        switch self {
        case .modern: "Modern"
        case .serif: "Serif"
        case .github: "GitHub"
        case .plain: "Plain"
        }
    }
}
