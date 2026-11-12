import Foundation
import UniformTypeIdentifiers

/// Turns local image references into `data:` URIs so rendered HTML is
/// self-contained: the reader, exports and Quick Look all need this because
/// their renderers can't (or aren't allowed to) load files next to the document.
public enum ImageEmbedder {
    /// Resolves `src` values relative to `folder`. Remote and `data:` sources
    /// and unreadable files return nil, leaving the source untouched. With
    /// `containedOnly`, only files inside `folder` (and its subfolders) are
    /// read, so a document can't pull in files from elsewhere on disk.
    public static func resolver(folder: URL, containedOnly: Bool = false) -> @Sendable (String) -> String? {
        // Treat `folder` as a directory whether or not it carries a trailing
        // slash, and compare real paths so /var vs /private/var can't fool the check.
        let folder = URL(fileURLWithPath: folder.path, isDirectory: true)
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
        return { source in
            let lower = source.lowercased()
            guard !lower.hasPrefix("http://"), !lower.hasPrefix("https://"), !lower.hasPrefix("data:") else { return nil }
            let path = source.removingPercentEncoding ?? source
            let url: URL = lower.hasPrefix("file://")
                ? (URL(string: source) ?? folder)
                : URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
            if containedOnly {
                let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
                guard resolved.hasPrefix(root + "/") else { return nil }
            }
            // The live preview re-renders on every keystroke; only re-read an
            // image when the file changed.
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let key = "\(url.path)|\(modified?.timeIntervalSince1970 ?? 0)" as NSString
            if let cached = cache.object(forKey: key) { return cached as String }
            guard let data = try? Data(contentsOf: url), data.count <= 25_000_000 else { return nil }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            let uri = "data:\(mime);base64,\(data.base64EncodedString())"
            cache.setObject(uri as NSString, forKey: key, cost: uri.utf8.count)
            return uri
        }
    }

    nonisolated(unsafe) private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.totalCostLimit = 150_000_000
        return cache
    }()
}
