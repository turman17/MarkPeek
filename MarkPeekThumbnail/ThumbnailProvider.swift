import AppKit
import QuickLookThumbnailing

// Finder icon thumbnails for Markdown files: a small page with the title and
// the first lines of text, drawn with the active theme's light palette.
class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let theme = ThemeStorage.loadActiveTheme()
        let text = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""
        let page = Self.summarize(text, fallbackTitle: request.fileURL.deletingPathExtension().lastPathComponent)

        // Portrait page that fits the requested box.
        let maximum = request.maximumSize
        let aspect: CGFloat = 0.78
        var size = CGSize(width: maximum.height * aspect, height: maximum.height)
        if size.width > maximum.width {
            size = CGSize(width: maximum.width, height: maximum.width / aspect)
        }

        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            Self.draw(page, theme: theme, in: CGRect(origin: .zero, size: size))
            return true
        }
        handler(reply, nil)
    }

    // MARK: Content

    struct Page {
        var title: String
        var lines: [String]
    }

    /// First heading (or the file name) plus a few plain lines, with the
    /// most common Markdown syntax stripped.
    static func summarize(_ markdown: String, fallbackTitle: String) -> Page {
        var title: String?
        var lines: [String] = []
        var inFence = false
        var inFrontMatter = false
        for (index, raw) in markdown.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if index == 0, line == "---" { inFrontMatter = true; continue }
            if inFrontMatter { if line == "---" { inFrontMatter = false }; continue }
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { lines.append(line); if lines.count >= 14 { break }; continue }
            if line.isEmpty || line == ">" || line.hasPrefix("<!--") || line.hasPrefix("![") { continue }
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if title == nil { title = heading; continue }
                lines.append(heading)
            } else {
                lines.append(clean(line))
            }
            if lines.count >= 14 { break }
        }
        return Page(title: title ?? fallbackTitle, lines: lines)
    }

    private static func clean(_ line: String) -> String {
        var s = line
        for prefix in ["> ", "- [ ] ", "- [x] ", "- ", "* ", "+ "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count)); break
        }
        s = s.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for marker in ["**", "__", "~~", "`", "*", "_"] { s = s.replacingOccurrences(of: marker, with: "") }
        s = s.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        return s
    }

    // MARK: Drawing

    static func draw(_ page: Page, theme: Theme, in rect: CGRect) {
        let palette = theme.light
        let scale = rect.height / 320   // design at 320pt tall, scale to request
        let inset = 22 * scale

        NSColor(hex: palette.background).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6 * scale, yRadius: 6 * scale).fill()

        let titleFont = NSFont.systemFont(ofSize: 17 * scale, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 8.5 * scale)
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: NSColor(hex: palette.heading)]
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: NSColor(hex: palette.text)]

        var y = rect.maxY - inset
        let width = rect.width - inset * 2
        let title = NSAttributedString(string: page.title, attributes: titleAttributes)
        let titleHeight = title.boundingRect(with: CGSize(width: width, height: 60 * scale), options: [.usesLineFragmentOrigin]).height
        title.draw(with: CGRect(x: rect.minX + inset, y: y - titleHeight, width: width, height: titleHeight), options: [.usesLineFragmentOrigin])
        y -= titleHeight + 8 * scale

        // A thin rule under the title, like the GitHub theme.
        NSColor(hex: palette.rule).setFill()
        CGRect(x: rect.minX + inset, y: y, width: width, height: max(0.5, 0.6 * scale)).fill()
        y -= 8 * scale

        let lineHeight = 12.5 * scale
        for line in page.lines {
            guard y - lineHeight > rect.minY + inset * 0.6 else { break }
            let text = NSAttributedString(string: line, attributes: bodyAttributes)
            text.draw(with: CGRect(x: rect.minX + inset, y: y - lineHeight, width: width, height: lineHeight), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            y -= lineHeight
        }
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
