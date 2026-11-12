import AppKit

/// Security-scoped bookmarks for folders the user granted access to, so
/// images next to a document can be read on later launches too.
enum FolderAccess {
    private static let key = "folderBookmarks"

    private static var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Paths of every folder the user has allowed, for display.
    static var grantedFolders: [String] { bookmarks.keys.sorted() }

    /// Forgets a granted folder. Documents in it go back to needing a grant.
    static func remove(_ path: String) {
        var all = bookmarks
        all.removeValue(forKey: path)
        bookmarks = all
    }

    /// Starts accessing a stored folder that contains `folder`. The returned
    /// URL must be passed to `stopAccessingSecurityScopedResource` later.
    static func startAccessing(folderContaining folder: URL) -> URL? {
        let path = folder.standardizedFileURL.path
        for (stored, data) in bookmarks where path == stored || path.hasPrefix(stored + "/") {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                var all = bookmarks
                all[stored] = fresh
                bookmarks = all
            }
            return url
        }
        return nil
    }

    /// Asks the user to pick (and thereby grant) a folder. Returns the folder.
    @MainActor
    static func request(for folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = "Allow MarkPeek to read images in this folder."
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var all = bookmarks
            all[url.standardizedFileURL.path] = data
            bookmarks = all
        }
        return url
    }
}
