import Foundation

/// A user theme together with the file it lives in.
public struct StoredTheme: Identifiable, Equatable, Sendable {
    public var theme: Theme
    public var url: URL
    public var id: UUID { theme.id }
}

public enum ThemeStorageError: LocalizedError {
    case unreadable(URL)
    case invalidFormat(URL)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "Couldn't read \(url.lastPathComponent)."
        case .invalidFormat(let url): "\(url.lastPathComponent) isn't a MarkPeek theme."
        }
    }
}

// Persistence shared by the app and the Quick Look extension.
//
// - The *active* theme is a full snapshot in the app-group defaults, so the
//   extension never has to resolve anything: it reads one record and renders.
// - User themes are individual `.markpeektheme` files in the app-group
//   container's Themes folder. Installing a theme is a file copy.
public enum ThemeStorage {

    public static let appGroupID = "YJ3UZ772GP.com.markpeek.app.shared"
    private static let activeThemeKey = "activeTheme"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("MarkPeek", isDirectory: true)
    }

    public static var themesDirectory: URL {
        let url = containerURL.appendingPathComponent("Themes", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Active theme

    public static func loadActiveTheme() -> Theme {
        if let data = defaults.data(forKey: activeThemeKey), let theme = try? Theme.decode(data) {
            return theme
        }
        return .modern
    }

    public static func saveActiveTheme(_ theme: Theme) {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        defaults.set(data, forKey: activeThemeKey)
    }

    // MARK: User themes

    public static func loadUserThemes() -> [StoredTheme] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: themesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == Theme.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let theme = try? Theme.decode(data) else { return nil }
                return StoredTheme(theme: theme, url: url)
            }
            .sorted { $0.theme.name.localizedStandardCompare($1.theme.name) == .orderedAscending }
    }

    /// Writes the theme to `url` when given, otherwise to a new file named
    /// after the theme. Returns the file that now holds it.
    @discardableResult
    public static func save(_ theme: Theme, at url: URL? = nil) throws -> URL {
        var theme = theme
        theme.formatVersion = Theme.currentFormatVersion
        let target = url ?? newFileURL(for: theme)
        try theme.encoded().write(to: target, options: .atomic)
        return target
    }

    public static func delete(_ stored: StoredTheme) throws {
        try FileManager.default.removeItem(at: stored.url)
    }

    /// Reads a theme file from anywhere, gives it a fresh identity when it
    /// collides with a built-in, and installs it into the Themes folder.
    public static func importTheme(from url: URL) throws -> StoredTheme {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ThemeStorageError.unreadable(url) }
        guard var theme = try? Theme.decode(data) else { throw ThemeStorageError.invalidFormat(url) }
        if Theme.builtIn(id: theme.id) != nil { theme.id = UUID() }
        let existing = loadUserThemes().first { $0.id == theme.id }
        let saved = try save(theme, at: existing?.url)
        return StoredTheme(theme: theme, url: saved)
    }

    private static func newFileURL(for theme: Theme) -> URL {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        var base = theme.name.components(separatedBy: invalid).joined().trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "Theme" }
        var candidate = themesDirectory.appendingPathComponent(base).appendingPathExtension(Theme.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = themesDirectory.appendingPathComponent("\(base) \(n)").appendingPathExtension(Theme.fileExtension)
            n += 1
        }
        return candidate
    }

}
