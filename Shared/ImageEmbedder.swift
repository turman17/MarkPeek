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
            guard let data = try? Data(contentsOf: url), data.count <= 25_000_000 else { return nil }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            return "data:\(mime);base64,\(data.base64EncodedString())"
        }
    }
}
