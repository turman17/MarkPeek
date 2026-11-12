import SwiftUI
import UniformTypeIdentifiers

struct RecentFile: Codable, Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let bookmark: Data
}

/// The open Markdown file: its saved text, the draft being edited, recents
/// and everything needed to render it (base URL, local image embedding).
@MainActor
final class DocumentModel: ObservableObject {
    static let shared = DocumentModel()

    enum ViewMode: String, CaseIterable, Identifiable {
        case preview, split, edit
        var id: String { rawValue }
        var title: String {
            switch self {
            case .preview: "Preview"
            case .split: "Split"
            case .edit: "Edit"
            }
        }
        var symbol: String {
            switch self {
            case .preview: "doc.richtext"
            case .split: "rectangle.split.2x1"
            case .edit: "pencil.line"
            }
        }
    }

    @Published private(set) var fileURL: URL?
    @Published private(set) var savedText = ""
    @Published var draft = "" {
        didSet {
            scheduleAutoSave()
            scheduleOutlineUpdate()
        }
    }
    /// Headings of the draft, refreshed shortly after edits.
    @Published private(set) var outline: [OutlineItem] = []
    /// True when the file was modified by another app while this document has unsaved edits.
    @Published private(set) var fileChangedOnDisk = false
    @Published var mode: ViewMode = .preview
    @Published var isImporting = false
    @Published var errorMessage: String?
    @Published private(set) var recents: [RecentFile] = DocumentModel.loadRecents()
    @Published var autoSave = UserDefaults.standard.bool(forKey: "autoSave") {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: "autoSave")
            if autoSave { save() }
        }
    }

    /// True when the document references local images the sandbox can't read.
    @Published private(set) var needsFolderAccess = false
    /// Bumped to force a re-render when nothing in the content changed (e.g. folder access granted).
    @Published private(set) var renderGeneration = 0

    private var accessedURL: URL?
    private var accessedFolder: URL?
    private var autoSaveTask: Task<Void, Never>?
    private var outlineTask: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var ignoreNextChange = false

    static let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "mdx", "rmd", "qmd", "txt"]
    static var markdownTypes: [UTType] {
        var types = markdownExtensions.compactMap { UTType(filenameExtension: $0) }
        types.append(.plainText)
        return types
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: Derived

    var hasDocument: Bool { fileURL != nil }
    var hasUnsavedChanges: Bool { fileURL != nil && draft != savedText }
    var title: String { fileURL?.lastPathComponent ?? "MarkPeek" }
    var folderURL: URL? { fileURL?.deletingLastPathComponent() }

    var wordCount: Int {
        draft.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Embeds local images as data URIs so they show in the reader and in
    /// exported PDFs even though the sandbox only granted access to the file.
    var imageResolver: (@Sendable (String) -> String?)? {
        folderURL.map { ImageEmbedder.resolver(folder: $0) }
    }

    // MARK: Open / save / close

    func open(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            let text = try Self.readText(at: url)
            savedText = text
            draft = text
            fileURL = url
            errorMessage = nil
            fileChangedOnDisk = false
            noteRecent(url)
            refreshFolderAccess()
            startWatching()
        } catch {
            errorMessage = "Couldn't read \(url.lastPathComponent)."
        }
    }

    func close() {
        watcher = nil
        fileChangedOnDisk = false
        autoSaveTask?.cancel()
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = nil
        needsFolderAccess = false
        fileURL = nil
        savedText = ""
        draft = ""
    }

    func save() {
        guard let url = fileURL, hasUnsavedChanges else { return }
        do {
            ignoreNextChange = true
            try draft.write(to: url, atomically: true, encoding: .utf8)
            savedText = draft
            startWatching() // atomic writes replace the file
        } catch {
            errorMessage = "Couldn't save \(url.lastPathComponent). The file may be read-only."
        }
    }

    // MARK: Live reload

    private func startWatching() {
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in self?.fileDidChangeOnDisk() }
    }

    private func fileDidChangeOnDisk() {
        if ignoreNextChange { ignoreNextChange = false; return }
        guard fileURL != nil else { return }
        if hasUnsavedChanges {
            fileChangedOnDisk = true
        } else {
            reloadFromDisk()
        }
    }

    /// Replaces the draft with the file's current contents.
    func reloadFromDisk() {
        guard let url = fileURL, let text = try? Self.readText(at: url) else { return }
        savedText = text
        draft = text
        fileChangedOnDisk = false
        startWatching()
    }

    func keepLocalChanges() {
        fileChangedOnDisk = false
        startWatching()
    }

    private func scheduleOutlineUpdate() {
        outlineTask?.cancel()
        let text = draft
        outlineTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let items = await Task.detached { MarkdownRenderer.outline(markdown: text) }.value
            if !Task.isCancelled { outline = items }
        }
    }

    // MARK: Folder access for local images

    /// Lets the user grant access to the document's folder so sibling images load.
    func grantFolderAccess() {
        guard let folder = folderURL, FolderAccess.request(for: folder) != nil else { return }
        refreshFolderAccess()
        renderGeneration += 1
    }

    /// Re-checks folder access after a grant made elsewhere (the setup assistant).
    func folderAccessChanged() {
        refreshFolderAccess()
        renderGeneration += 1
    }

    func dismissFolderAccessPrompt() {
        needsFolderAccess = false
    }

    private func refreshFolderAccess() {
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = nil
        needsFolderAccess = false
        guard let folder = folderURL else { return }
        if let granted = FolderAccess.startAccessing(folderContaining: folder) {
            accessedFolder = granted
            return
        }
        needsFolderAccess = hasUnreadableLocalImages(in: folder)
    }

    private static let imagePattern = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\(\s*<?([^)\s>]+)|<img[^>]+src=["']([^"']+)"#, options: .caseInsensitive)

    private func hasUnreadableLocalImages(in folder: URL) -> Bool {
        let text = savedText as NSString
        for match in Self.imagePattern.matches(in: savedText, range: NSRange(location: 0, length: text.length)) {
            let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
            guard range.location != NSNotFound else { continue }
            let source = text.substring(with: range)
            let lower = source.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") { continue }
            let path = (source.removingPercentEncoding ?? source).replacingOccurrences(of: "file://", with: "")
            let url = URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
            if !FileManager.default.isReadableFile(atPath: url.path) { return true }
        }
        return false
    }

    func revealInFinder() {
        guard let url = fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard autoSave, hasUnsavedChanges else { return }
        autoSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    // MARK: Recents

    func openRecent(_ recent: RecentFile) {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: recent.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            removeRecent(recent)
            errorMessage = "\(recent.name) is no longer available."
            return
        }
        open(url)
    }

    func removeRecent(_ recent: RecentFile) {
        recents.removeAll { $0.id == recent.id }
        saveRecents()
    }

    func clearRecents() {
        recents.removeAll()
        saveRecents()
    }

    /// Reopens the most recent file, used at launch when the preference is on.
    func reopenLastDocument() {
        guard fileURL == nil, let last = recents.first else { return }
        openRecent(last)
    }

    private func noteRecent(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let entry = RecentFile(name: url.lastPathComponent, path: url.path, bookmark: bookmark)
        recents.removeAll { $0.path == entry.path }
        recents.insert(entry, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        saveRecents()
    }

    private static let recentsKey = "recentFiles"

    private static func loadRecents() -> [RecentFile] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let recents = try? JSONDecoder().decode([RecentFile].self, from: data) else { return [] }
        return recents
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    static func readText(at url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}
