import Foundation
import Markdown

/// A heading in the document, for outlines and navigation.
public struct OutlineItem: Identifiable, Hashable, Sendable {
    public let level: Int
    public let title: String
    /// Matches the `id` attribute the renderer gives the heading.
    public let id: String
}

/// Which optional engines a document needs.
public struct DocumentFeatures: Sendable, Equatable {
    public var math = false
    public var mermaid = false
}

// Markdown → HTML using Apple's swift-markdown (CommonMark + GitHub tables,
// task lists and strikethrough). The HTML is deliberately plain so a theme's
// CSS has full control over the look.
public enum MarkdownRenderer {

    /// A complete HTML document: stylesheet from the theme plus rendered body.
    public static func document(markdown: String, theme: Theme, options: RenderOptions = RenderOptions()) -> String {
        let body = fragment(markdown: markdown, theme: theme, options: options)
        let css = ThemeStylesheet.css(for: theme, options: options)
        let content = "<article class=\"mp-content\">\n\(body)</article>"
        let wrapped = options.surface == .pageCard ? "<div class=\"mp-page\">\n\(content)\n</div>" : content
        let scripts = options.scripts.map { "<script>\n\($0)\n</script>" }.joined(separator: "\n")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
        \(css)
        </style>
        </head>
        <body>
        \(wrapped)
        \(scripts)
        </body>
        </html>
        """
    }

    /// Only the rendered body, without `<html>` or styles.
    public static func fragment(markdown: String, theme: Theme, options: RenderOptions = RenderOptions()) -> String {
        let (frontMatter, text, skippedLines) = FrontMatter.split(markdown)
        let protected = MathProtector.protect(text)
        let doc = Document(parsing: protected.text)
        var visitor = HTMLVisitor(
            imageResolver: options.imageResolver,
            lineNumbers: theme.elements.codeLineNumbers,
            showLanguage: theme.elements.codeShowLanguage,
            highlight: theme.elements.codeHighlighting,
            sourceMap: options.sourceMap ? SourceLineMap(offset: skippedLines, protected: protected) : nil)
        var html = visitor.visit(doc)
        html = protected.restore(html)
        if let frontMatter {
            let lines = options.sourceMap ? 1...max(skippedLines, 1) : nil
            html = FrontMatter.html(frontMatter, style: theme.elements.frontMatter, lines: lines) + html
        }
        return html
    }

    /// Headings in document order, with the ids the renderer assigns.
    public static func outline(markdown: String) -> [OutlineItem] {
        let (_, text, _) = FrontMatter.split(markdown)
        let doc = Document(parsing: text)
        var slugs = HeadingSlugs()
        var items: [OutlineItem] = []
        for case let heading as Heading in doc.children {
            let title = heading.plainText
            items.append(OutlineItem(level: heading.level, title: title, id: slugs.unique(for: title)))
        }
        return items
    }

    /// Detects math and Mermaid usage so the app can attach the engines.
    public static func features(of markdown: String) -> DocumentFeatures {
        var features = DocumentFeatures()
        features.mermaid = markdown.range(of: "```mermaid", options: .caseInsensitive) != nil
        features.math = MathProtector.containsMath(markdown)
        return features
    }

    /// Plain text of the document, for word counts and search.
    public static func plainText(markdown: String) -> String {
        Document(parsing: markdown).format()
    }
}

// MARK: - Heading ids

struct HeadingSlugs {
    private var used: Set<String> = []

    mutating func unique(for text: String) -> String {
        var slug = text.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "section" }
        var candidate = slug
        var n = 1
        while used.contains(candidate) {
            n += 1
            candidate = "\(slug)-\(n)"
        }
        used.insert(candidate)
        return candidate
    }
}

// MARK: - Front matter

enum FrontMatter {
    /// Splits a leading `---` YAML block from the body. The third value is
    /// how many source lines the block took, so line numbers in the body can
    /// be mapped back to the original text.
    static func split(_ markdown: String) -> ([(String, String)]?, String, Int) {
        var lines = markdown.components(separatedBy: "\n")
        guard lines.count > 2, lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return (nil, markdown, 0) }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" || $0.trimmingCharacters(in: .whitespaces) == "..." }) else {
            return (nil, markdown, 0)
        }
        let block = Array(lines[1..<end])
        lines.removeSubrange(0...end)
        return (parse(block), lines.joined(separator: "\n"), end + 1)
    }

    private static func parse(_ lines: [String]) -> [(String, String)] {
        var entries: [(String, String)] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            if let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if value.count >= 2, let first = value.first, let last = value.last, (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
                if value.hasPrefix("[") && value.hasSuffix("]") {
                    value = value.dropFirst().dropLast().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }.joined(separator: ", ")
                }
                entries.append((key, value))
            } else if let last = entries.indices.last {
                // Continuation or list item under the previous key.
                var item = line.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") { item.removeFirst(2) }
                item = item.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                guard !item.isEmpty else { continue }
                entries[last].1 = entries[last].1.isEmpty ? item : entries[last].1 + ", " + item
            }
        }
        return entries
    }

    static func html(_ entries: [(String, String)], style: Theme.FrontMatterStyle, lines: ClosedRange<Int>? = nil) -> String {
        let attr = lines.map { " data-line=\"\($0.lowerBound)-\($0.upperBound)\"" } ?? ""
        switch style {
        case .hidden:
            return ""
        case .raw:
            let body = entries.map { "\(escape($0.0)): \(escape($0.1))" }.joined(separator: "\n")
            return "<pre class=\"mp-frontmatter\"\(attr)><code>---\n\(body)\n---</code></pre>\n"
        case .table:
            guard !entries.isEmpty else { return "" }
            let rows = entries.map { "<tr><th>\(escape($0.0))</th><td>\(escape($0.1))</td></tr>" }.joined(separator: "\n")
            return "<div class=\"mp-table\"\(attr)><table class=\"mp-frontmatter\"><tbody>\n\(rows)\n</tbody></table></div>\n"
        }
    }

    private static func escape(_ s: String) -> String { HTMLEscape.escape(s) }
}

// MARK: - Math

/// Pulls `$…$` and `$$…$$` out of the Markdown before parsing so underscores
/// and asterisks inside formulas survive, then puts them back as MathJax
/// delimiters. Fenced and inline code are left alone.
enum MathProtector {
    struct Protected {
        var text: String
        var spans: [String]   // HTML to substitute for each placeholder
        /// For each line of `text`, the 1-based first and last line of the
        /// original it covers (a display-math placeholder stands for several).
        /// Nil when nothing was protected and the lines match one to one.
        var lineSpans: [(Int, Int)]?

        func restore(_ html: String) -> String {
            var out = html
            for (index, span) in spans.enumerated() {
                // A display block alone in a paragraph replaces the paragraph
                // and takes its attributes (data-line): a <div> inside a <p>
                // would close the paragraph early, leaving it empty.
                if span.hasPrefix(MathProtector.displayOpen) {
                    let pattern = "<p([^>]*)>" + NSRegularExpression.escapedPattern(for: placeholder(index)) + "</p>"
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
                       let whole = Range(match.range, in: out), let attrs = Range(match.range(at: 1), in: out) {
                        let div = "<div class=\"math-display\"\(out[attrs])>" + span.dropFirst(MathProtector.displayOpen.count)
                        out.replaceSubrange(whole, with: div)
                        continue
                    }
                }
                out = out.replacingOccurrences(of: placeholder(index), with: span)
            }
            return out
        }
    }

    private static let marker = "\u{E000}"
    fileprivate static let displayOpen = "<div class=\"math-display\">"
    private static func placeholder(_ index: Int) -> String { "\(marker)MATH\(index)\(marker)" }

    private static let inlinePattern = try! NSRegularExpression(pattern: #"(?<![\\$\w])\$(?!\s)((?:\\.|[^$\\\n])+?)(?<!\s)\$(?!\w|\$)"#)
    private static let codeSpanPattern = try! NSRegularExpression(pattern: #"`+[^`]*`+"#)

    static func containsMath(_ markdown: String) -> Bool {
        guard markdown.contains("$") else { return false }
        return protect(markdown).spans.count > 0
    }

    static func protect(_ markdown: String) -> Protected {
        guard markdown.contains("$") else { return Protected(text: markdown, spans: [], lineSpans: nil) }
        var spans: [String] = []
        var output: [String] = []
        var lineSpans: [(Int, Int)] = []
        var inFence = false
        var fenceMarker = ""
        var displayBuffer: [String]? = nil
        var displayStart = 0

        for (index, line) in markdown.components(separatedBy: "\n").enumerated() {
            let number = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if displayBuffer != nil {
                if trimmed.hasSuffix("$$") {
                    var content = displayBuffer!
                    content.append(String(trimmed.dropLast(2)))
                    let tex = content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    spans.append("\(displayOpen)\\[\(HTMLEscape.escape(tex))\\]</div>")
                    output.append(placeholder(spans.count - 1))
                    lineSpans.append((displayStart, number))
                    displayBuffer = nil
                } else {
                    displayBuffer!.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if inFence && marker == fenceMarker { inFence = false } else if !inFence { inFence = true; fenceMarker = marker }
                output.append(line)
                lineSpans.append((number, number))
                continue
            }
            if inFence { output.append(line); lineSpans.append((number, number)); continue }
            if trimmed.hasPrefix("$$") {
                let rest = String(trimmed.dropFirst(2))
                if rest.hasSuffix("$$"), rest.count >= 2 {
                    let tex = String(rest.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    spans.append("\(displayOpen)\\[\(HTMLEscape.escape(tex))\\]</div>")
                    output.append(placeholder(spans.count - 1))
                    lineSpans.append((number, number))
                } else {
                    displayBuffer = rest.isEmpty ? [] : [rest]
                    displayStart = number
                }
                continue
            }
            output.append(protectInline(line, spans: &spans))
            lineSpans.append((number, number))
        }
        if let leftover = displayBuffer {
            // Unterminated block: put the lines back as they were.
            let lines = ["$$"] + leftover
            output.append(contentsOf: lines)
            for i in 0..<lines.count { lineSpans.append((displayStart + i, displayStart + i)) }
        }
        return Protected(text: output.joined(separator: "\n"), spans: spans, lineSpans: lineSpans)
    }

    private static func protectInline(_ line: String, spans: inout [String]) -> String {
        guard line.contains("$") else { return line }
        let ns = line as NSString
        let codeRanges = codeSpanPattern.matches(in: line, range: NSRange(location: 0, length: ns.length)).map(\.range)
        var result = ""
        var cursor = 0
        for match in inlinePattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let tex = ns.substring(with: match.range(at: 1))
            spans.append("<span class=\"math-inline\">\\(\(HTMLEscape.escape(tex))\\)</span>")
            result += placeholder(spans.count - 1)
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}

enum HTMLEscape {
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for ch in text {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}

// MARK: - Source lines

/// Maps parser line numbers (relative to the text after front matter and
/// math protection) back to 1-based lines of the original Markdown.
struct SourceLineMap {
    let offset: Int
    let spans: [(Int, Int)]?

    init(offset: Int, protected: MathProtector.Protected) {
        self.offset = offset
        self.spans = protected.lineSpans
    }

    /// The original line range of a parsed element, as a `data-line` attribute.
    func attribute(for markup: Markup) -> String {
        guard let range = markup.range else { return "" }
        let first = range.lowerBound.line, last = range.upperBound.line
        var start = first, end = last
        if let spans {
            if first >= 1, first <= spans.count { start = spans[first - 1].0 }
            if last >= 1, last <= spans.count { end = spans[last - 1].1 }
        }
        return " data-line=\"\(start + offset)-\(max(end, start) + offset)\""
    }
}

// MARK: - Visitor

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    let imageResolver: (@Sendable (String) -> String?)?
    let lineNumbers: Bool
    let showLanguage: Bool
    let highlight: Bool
    let sourceMap: SourceLineMap?
    private var slugs = HeadingSlugs()

    init(imageResolver: (@Sendable (String) -> String?)?, lineNumbers: Bool, showLanguage: Bool, highlight: Bool, sourceMap: SourceLineMap? = nil) {
        self.imageResolver = imageResolver
        self.lineNumbers = lineNumbers
        self.showLanguage = showLanguage
        self.highlight = highlight
        self.sourceMap = sourceMap
    }

    /// ` data-line="start-end"` for the element, or nothing without a source map.
    private func lines(_ markup: Markup) -> String {
        sourceMap?.attribute(for: markup) ?? ""
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        children(of: markup)
    }

    private mutating func children(of markup: Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    // MARK: Blocks

    mutating func visitDocument(_ document: Document) -> String {
        children(of: document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p\(lines(paragraph))>\(children(of: paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let id = slugs.unique(for: heading.plainText)
        return "<h\(heading.level) id=\"\(id)\"\(lines(heading))>\(children(of: heading))</h\(heading.level)>\n"
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) -> String {
        "<blockquote\(lines(quote))>\n\(children(of: quote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ rule: ThematicBreak) -> String {
        "<hr\(lines(rule))>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        HTMLSanitizer.sanitize(html.rawHTML) + "\n"
    }

    mutating func visitCodeBlock(_ block: CodeBlock) -> String {
        var code = block.code
        if code.hasSuffix("\n") { code.removeLast() }
        let language = block.language?.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
        if language.lowercased() == "mermaid" {
            return "<pre class=\"mermaid\"\(lines(block))>\(escape(code))</pre>\n"
        }
        var attrs = ""
        var preAttrs = (lineNumbers ? " class=\"mp-ln\"" : "") + lines(block)
        if !language.isEmpty {
            attrs += " class=\"language-\(escape(language))\""
            if showLanguage { preAttrs += " data-lang=\"\(escape(language))\"" }
        }
        let lines: [String]
        if highlight, let highlighted = SyntaxHighlighter.htmlLines(code, language: language) {
            lines = highlighted
        } else {
            lines = code.components(separatedBy: "\n").map(escape)
        }
        let body: String
        if lineNumbers {
            body = lines.map { "<span class=\"line\">\($0)</span>" }.joined(separator: "\n")
        } else {
            body = lines.joined(separator: "\n")
        }
        return "<pre\(preAttrs)><code\(attrs)>\(body)</code></pre>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul\(lines(list))>\n\(children(of: list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
        return "<ol\(start)\(lines(list))>\n\(children(of: list))</ol>\n"
    }

    mutating func visitListItem(_ item: ListItem) -> String {
        var classes: [String] = []
        var prefix = ""
        if let checkbox = item.checkbox {
            classes.append("task")
            if checkbox == .checked { classes.append("done") }
            prefix = "<input type=\"checkbox\" disabled\(checkbox == .checked ? " checked" : "")> "
        }
        // A single paragraph renders inline so simple lists stay tight.
        let blocks = Array(item.children)
        let paragraphs = blocks.filter { $0 is Paragraph }.count
        var body = ""
        for block in blocks {
            if paragraphs == 1, let p = block as? Paragraph {
                body += children(of: p)
            } else {
                body += visit(block)
            }
        }
        let cls = classes.isEmpty ? "" : " class=\"\(classes.joined(separator: " "))\""
        return "<li\(cls)\(lines(item))>\(prefix)\(body)</li>\n"
    }

    mutating func visitTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
        var html = "<div class=\"mp-table\"\(lines(table))><table>\n<thead><tr>"
        for (i, cell) in table.head.children.enumerated() {
            html += "<th\(style(i))>\(children(of: cell))</th>"
        }
        html += "</tr></thead>\n<tbody>\n"
        for row in table.body.children {
            html += "<tr>"
            for (i, cell) in row.children.enumerated() {
                html += "<td\(style(i))>\(children(of: cell))</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody>\n</table></div>\n"
        return html
    }

    mutating func visitBlockDirective(_ directive: BlockDirective) -> String {
        children(of: directive)
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> String {
        autolink(text.string)
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String {
        "\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String {
        "<br>\n"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(children(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(children(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(children(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ code: InlineCode) -> String {
        "<code>\(escape(code.code))</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) -> String {
        HTMLSanitizer.sanitize(html.rawHTML)
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = escape(link.destination ?? "")
        let title = link.title.map { " title=\"\(escape($0))\"" } ?? ""
        return "<a href=\"\(href)\"\(title)>\(children(of: link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let source = image.source ?? ""
        let resolved = imageResolver?(source) ?? source
        let alt = escape(image.plainText)
        let title = image.title.map { " title=\"\(escape($0))\"" } ?? ""
        return "<img src=\"\(escape(resolved))\" alt=\"\(alt)\"\(title)>"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        "<code>\(escape(symbolLink.destination ?? ""))</code>"
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> String {
        "<span>\(children(of: attributes))</span>"
    }

    // MARK: Helpers

    private static let urlPattern = try! NSRegularExpression(pattern: #"(?<![\w"'=/])https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)

    /// Escapes text and turns bare http(s) URLs into links (GitHub-style autolinks).
    private func autolink(_ text: String) -> String {
        let ns = text as NSString
        let matches = Self.urlPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return escape(text) }
        var out = ""
        var cursor = 0
        for match in matches {
            out += escape(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let url = escape(ns.substring(with: match.range))
            out += "<a href=\"\(url)\">\(url)</a>"
            cursor = match.range.location + match.range.length
        }
        out += escape(ns.substring(from: cursor))
        return out
    }

    private func escape(_ text: String) -> String { HTMLEscape.escape(text) }
}
