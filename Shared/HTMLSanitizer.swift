import Foundation

/// Strips the parts of raw HTML that can run code. Markdown files come from
/// anywhere, and the reader renders them in a WKWebView with JavaScript on,
/// so inline `<script>`, event handlers and `javascript:` URLs are removed.
/// Everything else (tables, details, styled spans) passes through.
public enum HTMLSanitizer {
    private static let blockedElements = try! NSRegularExpression(
        pattern: #"<\s*(script|iframe|object|embed|applet|frame|frameset)\b[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#,
        options: .caseInsensitive)
    private static let blockedTags = try! NSRegularExpression(
        pattern: #"<\s*/?\s*(script|iframe|object|embed|applet|frame|frameset|base|link|meta)\b[^>]*>"#,
        options: .caseInsensitive)
    private static let eventHandlers = try! NSRegularExpression(
        pattern: #"\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#,
        options: .caseInsensitive)
    private static let scriptURLs = try! NSRegularExpression(
        pattern: #"(\s(?:href|src|action|formaction|xlink:href|data)\s*=\s*["']?\s*)(?:javascript|vbscript|data:text/html)[^"'\s>]*"#,
        options: .caseInsensitive)

    public static func sanitize(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var out = html
        out = replace(blockedElements, in: out, with: "")
        out = replace(blockedTags, in: out, with: "")
        out = replace(eventHandlers, in: out, with: "")
        out = replace(scriptURLs, in: out, with: "$1#")
        return out
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }
}
