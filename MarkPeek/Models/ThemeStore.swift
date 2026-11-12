import SwiftUI
import UniformTypeIdentifiers

/// The theme library plus the theme currently in use.
///
/// `active` is a working copy. Editing a user theme writes back to its file;
/// editing a built-in marks it "edited" until you revert or save it as your
/// own theme. The active snapshot is also what Quick Look renders with.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published private(set) var userThemes: [StoredTheme] = []
    @Published var active: Theme {
        didSet {
            guard active != oldValue else { return }
            ThemeStorage.saveActiveTheme(active)
            scheduleWriteBack()
        }
    }
    /// Forces the reader to one palette while colors are being edited.
    @Published var previewScheme: ThemeColorScheme?
    @Published var errorMessage: String?

    private var writeBackTask: Task<Void, Never>?

    nonisolated static let themeType = UTType(exportedAs: Theme.uniformTypeIdentifier)

    init() {
        active = ThemeStorage.loadActiveTheme()
        reload()
    }

    // MARK: Library

    var builtInThemes: [Theme] { Theme.builtIn }

    func reload() {
        userThemes = ThemeStorage.loadUserThemes()
    }

    func theme(id: UUID) -> Theme? {
        Theme.builtIn(id: id) ?? userThemes.first { $0.id == id }?.theme
    }

    func isBuiltIn(_ id: UUID) -> Bool { Theme.builtIn(id: id) != nil }

    // MARK: Active theme state

    /// The library theme `active` was derived from, if it still exists.
    var source: Theme? { theme(id: active.id) }
    var isActiveBuiltIn: Bool { isBuiltIn(active.id) }
    var isActiveModified: Bool {
        guard let source else { return true }
        return source != active
    }
    var activeLabel: String { source?.name ?? active.name }

    func isActive(_ id: UUID) -> Bool { active.id == id }

    func activate(_ theme: Theme) {
        previewScheme = nil
        active = theme
    }

    /// A binding that edits a field of the active theme.
    func binding<T>(_ keyPath: WritableKeyPath<Theme, T>) -> Binding<T> {
        Binding(
            get: { self.active[keyPath: keyPath] },
            set: { self.active[keyPath: keyPath] = $0 }
        )
    }

    func revert() {
        if let source { active = source }
    }

    // MARK: Editing the library

    @discardableResult
    func saveActiveAsNewTheme(named name: String) -> Theme? {
        var theme = active
        theme.id = UUID()
        theme.name = name
        theme.author = NSFullUserName()
        do {
            let url = try ThemeStorage.save(theme)
            userThemes.append(StoredTheme(theme: theme, url: url))
            sortThemes()
            active = theme
            return theme
        } catch {
            errorMessage = "Couldn't save the theme: \(error.localizedDescription)"
            return nil
        }
    }

    /// Adds a fully formed theme to the library and makes it active.
    func create(_ theme: Theme) {
        var theme = theme
        if theme.name.trimmingCharacters(in: .whitespaces).isEmpty { theme.name = "Untitled Theme" }
        theme.name = uniqueName(for: theme.name)
        do {
            let url = try ThemeStorage.save(theme)
            userThemes.append(StoredTheme(theme: theme, url: url))
            sortThemes()
            active = theme
        } catch {
            errorMessage = "Couldn't create the theme: \(error.localizedDescription)"
        }
    }

    func duplicate(_ theme: Theme) {
        var copy = theme
        copy.id = UUID()
        copy.name = uniqueName(for: theme.name + " Copy")
        do {
            let url = try ThemeStorage.save(copy)
            userThemes.append(StoredTheme(theme: copy, url: url))
            sortThemes()
            active = copy
        } catch {
            errorMessage = "Couldn't duplicate the theme: \(error.localizedDescription)"
        }
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = userThemes.firstIndex(where: { $0.id == id }) else { return }
        userThemes[index].theme.name = name
        write(userThemes[index])
        if active.id == id { active.name = name }
    }

    func delete(_ id: UUID) {
        guard let index = userThemes.firstIndex(where: { $0.id == id }) else { return }
        do {
            try ThemeStorage.delete(userThemes[index])
            userThemes.remove(at: index)
            if active.id == id { active = .modern }
        } catch {
            errorMessage = "Couldn't delete the theme: \(error.localizedDescription)"
        }
    }

    func importTheme(from url: URL) {
        do {
            let stored = try ThemeStorage.importTheme(from: url)
            userThemes.removeAll { $0.id == stored.id }
            userThemes.append(stored)
            sortThemes()
            active = stored.theme
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportData(for theme: Theme) -> Data? {
        try? theme.encoded()
    }

    func fileURL(for id: UUID) -> URL? {
        userThemes.first { $0.id == id }?.url
    }

    func revealThemesFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([ThemeStorage.themesDirectory])
    }

    // MARK: Private

    /// Debounced so dragging a slider doesn't rewrite the file on every tick.
    private func scheduleWriteBack() {
        writeBackTask?.cancel()
        guard let index = userThemes.firstIndex(where: { $0.id == active.id }),
              userThemes[index].theme != active else { return }
        let snapshot = active
        writeBackTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            userThemes[index].theme = snapshot
            write(userThemes[index])
        }
    }

    private func write(_ stored: StoredTheme) {
        do {
            try ThemeStorage.save(stored.theme, at: stored.url)
        } catch {
            errorMessage = "Couldn't save the theme: \(error.localizedDescription)"
        }
    }

    private func sortThemes() {
        userThemes.sort { $0.theme.name.localizedStandardCompare($1.theme.name) == .orderedAscending }
    }

    private func uniqueName(for base: String) -> String {
        let names = Set((builtInThemes + userThemes.map(\.theme)).map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
