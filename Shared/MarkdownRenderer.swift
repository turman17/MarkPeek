import Foundation

// Markdown → HTML conversion ported from FinderConvert's DocumentConversionEngine
// so previews match the converter's output exactly.
public enum MarkdownRenderer {
    /// pageCard renders the document on a floating "paper" card over a neutral
    /// surface (used by the app's reader and settings preview). Quick Look
    /// previews stay edge-to-edge.
    public static func html(from markdown: String, settings: PreviewSettings, pageCard: Bool = false) -> String {
        var html = ""
        let lines = markdown.components(separatedBy: .newlines)
        var inCodeBlock = false
        var inList = false
        var listType = "" // "ul" or "ol"

        for line in lines {
            // Code blocks
            if line.hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                } else {
                    if inList { html += "</\(listType)>\n"; inList = false }
                    html += "<pre><code>"
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                if inList { html += "</\(listType)>\n"; inList = false }
                continue
            }

            // Headers
            if trimmed.hasPrefix("######") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h6>\(processInline(String(trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces))))</h6>\n"
            } else if trimmed.hasPrefix("#####") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h5>\(processInline(String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))))</h5>\n"
            } else if trimmed.hasPrefix("####") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h4>\(processInline(String(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))))</h4>\n"
            } else if trimmed.hasPrefix("###") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h3>\(processInline(String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))))</h3>\n"
            } else if trimmed.hasPrefix("##") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h2>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h2>\n"
            } else if trimmed.hasPrefix("# ") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<h1>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h1>\n"
            }
            // Horizontal rule
            else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<hr/>\n"
            }
            // Unordered list
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !inList || listType != "ul" {
                    if inList { html += "</\(listType)>\n" }
                    html += "<ul>\n"; inList = true; listType = "ul"
                }
                html += "<li>\(processInline(String(trimmed.dropFirst(2))))</li>\n"
            }
            // Ordered list
            else if trimmed.first?.isNumber == true && trimmed.contains(". ") {
                if let dotIdx = trimmed.firstIndex(of: "."), trimmed[trimmed.startIndex..<dotIdx].allSatisfy(\.isNumber) {
                    if !inList || listType != "ol" {
                        if inList { html += "</\(listType)>\n" }
                        html += "<ol>\n"; inList = true; listType = "ol"
                    }
                    let content = String(trimmed[trimmed.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                    html += "<li>\(processInline(content))</li>\n"
                } else {
                    if inList { html += "</\(listType)>\n"; inList = false }
                    html += "<p>\(processInline(trimmed))</p>\n"
                }
            }
            // Blockquote
            else if trimmed.hasPrefix("> ") {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<blockquote><p>\(processInline(String(trimmed.dropFirst(2))))</p></blockquote>\n"
            }
            // Regular paragraph
            else {
                if inList { html += "</\(listType)>\n"; inList = false }
                html += "<p>\(processInline(trimmed))</p>\n"
            }
        }

        if inCodeBlock { html += "</code></pre>\n" }
        if inList { html += "</\(listType)>\n" }

        let body = pageCard ? "<div class=\"page\">\n\(html)</div>" : html
        let extraCSS = pageCard ? "\n" + pageCardCSS(settings) : ""
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(settings.css)\(extraCSS)
        </style></head><body>
        \(body)
        </body></html>
        """
    }

    private static func pageCardCSS(_ s: PreviewSettings) -> String {
        // Transparent body: the app places a glass (blur) material behind the
        // web view, so the desktop shows through around the floating page.
        let width = s.maxWidth > 0 ? "\(Int(s.maxWidth))px" : "820px"
        func block(page: String, shadow: String) -> String {
            """
            html { height: 100%; }
            body { background: transparent; max-width: none; margin: 0; padding: \(max(24, Int(s.pagePadding)))px 24px; box-sizing: border-box; min-height: 100%; display: grid; align-content: safe center; }
            .page { background: \(page); width: 100%; max-width: \(width); margin: 0 auto; padding: 34px 38px; box-sizing: border-box; border-radius: 12px; box-shadow: \(shadow); }
            """
        }
        let light = block(
            page: s.light.background,
            shadow: "0 8px 28px rgba(0,0,0,0.18), 0 0 0 1px rgba(0,0,0,0.05)")
        let dark = block(
            page: s.dark.background,
            shadow: "0 10px 32px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.08)")
        switch s.appearance {
        case .light: return light
        case .dark: return dark
        case .system:
            return light + "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}"
        }
    }

    private static func processInline(_ text: String) -> String {
        var result = escapeHTML(text)
        // Bold: **text** or __text__
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "<strong>$1</strong>", options: .regularExpression)
        // Italic: *text* or _text_
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<![a-zA-Z])_(.+?)_(?![a-zA-Z])", with: "<em>$1</em>", options: .regularExpression)
        // Inline code: `text`
        result = result.replacingOccurrences(of: "`(.+?)`", with: "<code>$1</code>", options: .regularExpression)
        // Links: [text](url)
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
