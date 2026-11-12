import Foundation

// A theme describes how Markdown is displayed: type, layout, element options
// and a light + dark palette. Themes are stored as `.markpeektheme` JSON files
// so they can be shared, installed and edited by hand. Decoding is lenient:
// missing keys fall back to defaults, so older or partial files keep working.
public struct Theme: Codable, Identifiable, Equatable, Hashable, Sendable {

    public static let currentFormatVersion = 2
    public static let fileExtension = "markpeektheme"
    public static let uniformTypeIdentifier = "com.markpeek.theme"

    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var author: String
    public var typography: Typography
    public var layout: Layout
    public var elements: Elements
    public var appearance: Appearance
    public var light: Palette
    public var dark: Palette
    /// Appended verbatim after the generated stylesheet. Palette values are
    /// available as CSS variables (`--mp-text`, `--mp-link`, ...).
    public var customCSS: String

    public init(
        id: UUID = UUID(),
        name: String,
        author: String = "",
        typography: Typography = Typography(),
        layout: Layout = Layout(),
        elements: Elements = Elements(),
        appearance: Appearance = .system,
        light: Palette = .defaultLight,
        dark: Palette = .defaultDark,
        customCSS: String = ""
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.author = author
        self.typography = typography
        self.layout = layout
        self.elements = elements
        self.appearance = appearance
        self.light = light
        self.dark = dark
        self.customCSS = customCSS
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, author, typography, layout, elements, appearance, light, dark, customCSS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = c.value(.formatVersion, default: Self.currentFormatVersion)
        id = c.value(.id, default: UUID())
        name = c.value(.name, default: "Untitled")
        author = c.value(.author, default: "")
        typography = c.value(.typography, default: Typography())
        layout = c.value(.layout, default: Layout())
        elements = c.value(.elements, default: Elements())
        appearance = c.value(.appearance, default: .system)
        light = Palette.decode(c, key: .light, defaults: .defaultLight)
        dark = Palette.decode(c, key: .dark, defaults: .defaultDark)
        customCSS = c.value(.customCSS, default: "")
    }

    // MARK: Enums

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system, light, dark
        public var displayName: String {
            switch self {
            case .system: "Follow System"
            case .light: "Always Light"
            case .dark: "Always Dark"
            }
        }
    }

    public enum TextAlignment: String, Codable, CaseIterable, Sendable {
        case leading, justified
        public var displayName: String { self == .leading ? "Left" : "Justified" }
    }

    public enum ListMarker: String, Codable, CaseIterable, Sendable {
        case disc, circle, square, dash
        public var displayName: String {
            switch self {
            case .disc: "Bullet"
            case .circle: "Circle"
            case .square: "Square"
            case .dash: "Dash"
            }
        }
    }

    public enum TableBorders: String, Codable, CaseIterable, Sendable {
        case all, horizontal, none
        public var displayName: String {
            switch self {
            case .all: "Grid"
            case .horizontal: "Rows"
            case .none: "None"
            }
        }
    }

    public enum RuleStyle: String, Codable, CaseIterable, Sendable {
        case line, short, dots
        public var displayName: String {
            switch self {
            case .line: "Line"
            case .short: "Short line"
            case .dots: "Dots"
            }
        }
    }

    public enum FrontMatterStyle: String, Codable, CaseIterable, Sendable {
        case table, hidden, raw
        public var displayName: String {
            switch self {
            case .table: "Show as table"
            case .hidden: "Hide"
            case .raw: "Show as written"
            }
        }
    }

    public enum HeadingNumbering: String, Codable, CaseIterable, Sendable {
        case off, h2, h3
        public var displayName: String {
            switch self {
            case .off: "Off"
            case .h2: "Sections"
            case .h3: "Sections and subsections"
            }
        }
    }

    // MARK: Typography

    public struct Typography: Codable, Equatable, Hashable, Sendable {
        public var bodyFont = "-apple-system"
        /// Empty means "same as body".
        public var headingFont = ""
        public var codeFont = "SF Mono"
        public var fontSize: Double = 16          // px
        public var lineHeight: Double = 1.6
        public var paragraphSpacing: Double = 1.0 // em
        public var headingWeight = 700            // 400...800
        public var headingScale: Double = 1.25    // modular scale between heading levels
        public var headingSpacing: Double = 1.5   // em above headings
        public var codeFontSize: Double = 0.9     // em relative to body
        public var textAlignment: TextAlignment = .leading
        public var hyphenate = false

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case bodyFont, headingFont, codeFont, fontSize, lineHeight, paragraphSpacing
            case headingWeight, headingScale, headingSpacing, codeFontSize, textAlignment, hyphenate
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Typography()
            bodyFont = c.value(.bodyFont, default: d.bodyFont)
            headingFont = c.value(.headingFont, default: d.headingFont)
            codeFont = c.value(.codeFont, default: d.codeFont)
            fontSize = c.value(.fontSize, default: d.fontSize)
            lineHeight = c.value(.lineHeight, default: d.lineHeight)
            paragraphSpacing = c.value(.paragraphSpacing, default: d.paragraphSpacing)
            headingWeight = c.value(.headingWeight, default: d.headingWeight)
            headingScale = c.value(.headingScale, default: d.headingScale)
            headingSpacing = c.value(.headingSpacing, default: d.headingSpacing)
            codeFontSize = c.value(.codeFontSize, default: d.codeFontSize)
            textAlignment = c.value(.textAlignment, default: d.textAlignment)
            hyphenate = c.value(.hyphenate, default: d.hyphenate)
        }
    }

    // MARK: Layout

    public struct Layout: Codable, Equatable, Hashable, Sendable {
        public var maxWidth: Double = 700        // px; 0 = full width
        public var pagePadding: Double = 40      // px, top/bottom
        public var sidePadding: Double = 24      // px, left/right
        public var codeBlockPadding: Double = 16 // px
        public var cornerRadius: Double = 6      // px; code, images, tables
        public var listIndent: Double = 1.6      // em
        public var tableCellPadding: Double = 8  // px
        public var imageMaxWidth: Double = 100   // percent of content width
        public var blockquoteBorderWidth: Double = 4 // px

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case maxWidth, pagePadding, sidePadding, codeBlockPadding, cornerRadius
            case listIndent, tableCellPadding, imageMaxWidth, blockquoteBorderWidth
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Layout()
            maxWidth = c.value(.maxWidth, default: d.maxWidth)
            pagePadding = c.value(.pagePadding, default: d.pagePadding)
            sidePadding = c.value(.sidePadding, default: d.sidePadding)
            codeBlockPadding = c.value(.codeBlockPadding, default: d.codeBlockPadding)
            cornerRadius = c.value(.cornerRadius, default: d.cornerRadius)
            listIndent = c.value(.listIndent, default: d.listIndent)
            tableCellPadding = c.value(.tableCellPadding, default: d.tableCellPadding)
            imageMaxWidth = c.value(.imageMaxWidth, default: d.imageMaxWidth)
            blockquoteBorderWidth = c.value(.blockquoteBorderWidth, default: d.blockquoteBorderWidth)
        }
    }

    // MARK: Elements

    public struct Elements: Codable, Equatable, Hashable, Sendable {
        public var headingUnderline = false      // rule under h1 and h2
        public var headingNumbering: HeadingNumbering = .off
        public var blockquoteItalic = false
        public var linkUnderline = false
        public var codeShowLanguage = true       // language badge on fenced blocks
        public var codeWrapLines = false
        public var codeLineNumbers = false
        public var codeHighlighting = true       // syntax colors in fenced blocks
        public var tableStriped = true
        public var tableBorders: TableBorders = .horizontal
        public var imageRounded = true
        public var imageShadow = false
        public var imageCentered = false
        public var listMarker: ListMarker = .disc
        public var ruleStyle: RuleStyle = .line
        public var dropCap = false
        public var frontMatter: FrontMatterStyle = .table

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case headingUnderline, headingNumbering, blockquoteItalic, linkUnderline
            case codeShowLanguage, codeWrapLines, codeLineNumbers, codeHighlighting
            case tableStriped, tableBorders, imageRounded, imageShadow, imageCentered
            case listMarker, ruleStyle, dropCap, frontMatter
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Elements()
            headingUnderline = c.value(.headingUnderline, default: d.headingUnderline)
            headingNumbering = c.value(.headingNumbering, default: d.headingNumbering)
            blockquoteItalic = c.value(.blockquoteItalic, default: d.blockquoteItalic)
            linkUnderline = c.value(.linkUnderline, default: d.linkUnderline)
            codeShowLanguage = c.value(.codeShowLanguage, default: d.codeShowLanguage)
            codeWrapLines = c.value(.codeWrapLines, default: d.codeWrapLines)
            codeLineNumbers = c.value(.codeLineNumbers, default: d.codeLineNumbers)
            codeHighlighting = c.value(.codeHighlighting, default: d.codeHighlighting)
            tableStriped = c.value(.tableStriped, default: d.tableStriped)
            tableBorders = c.value(.tableBorders, default: d.tableBorders)
            imageRounded = c.value(.imageRounded, default: d.imageRounded)
            imageShadow = c.value(.imageShadow, default: d.imageShadow)
            imageCentered = c.value(.imageCentered, default: d.imageCentered)
            listMarker = c.value(.listMarker, default: d.listMarker)
            ruleStyle = c.value(.ruleStyle, default: d.ruleStyle)
            dropCap = c.value(.dropCap, default: d.dropCap)
            frontMatter = c.value(.frontMatter, default: d.frontMatter)
        }
    }

    // MARK: Palette

    public struct Palette: Codable, Equatable, Hashable, Sendable {
        public var background: String
        public var text: String
        public var heading: String
        public var link: String
        public var codeBackground: String
        public var codeText: String
        public var blockquoteText: String
        public var blockquoteBorder: String
        public var rule: String
        public var tableBorder: String
        public var tableHeaderBackground: String
        public var tableStripe: String
        public var accent: String
        public var muted: String
        public var syntax: Syntax

        /// Colors for syntax highlighting in fenced code blocks.
        public struct Syntax: Codable, Equatable, Hashable, Sendable {
            public var keyword: String
            public var string: String
            public var comment: String
            public var number: String
            public var type: String
            public var function: String
            public var attribute: String

            public init(keyword: String, string: String, comment: String, number: String,
                        type: String, function: String, attribute: String) {
                self.keyword = keyword
                self.string = string
                self.comment = comment
                self.number = number
                self.type = type
                self.function = function
                self.attribute = attribute
            }

            public static let defaultLight = Syntax(
                keyword: "#9B2393", string: "#C41A16", comment: "#6C7986", number: "#1C00CF",
                type: "#0B4F79", function: "#326D74", attribute: "#947100")
            public static let defaultDark = Syntax(
                keyword: "#FC5FA3", string: "#FC6A5D", comment: "#7F8C98", number: "#D0BF69",
                type: "#5DD8FF", function: "#67B7A4", attribute: "#D9C97C")

            /// Picks readable defaults for a given background.
            public static func `default`(forBackground hex: String) -> Syntax {
                Palette.isDark(hex) ? defaultDark : defaultLight
            }

            private enum CodingKeys: String, CodingKey { case keyword, string, comment, number, type, function, attribute }

            /// The keys a file supplied; the rest come from `defaults`.
            struct Partial: Decodable, Sendable {
                var keyword, string, comment, number, type, function, attribute: String?
            }

            static func resolve(_ p: Partial?, defaults d: Syntax) -> Syntax {
                guard let p else { return d }
                return Syntax(keyword: p.keyword ?? d.keyword, string: p.string ?? d.string, comment: p.comment ?? d.comment,
                              number: p.number ?? d.number, type: p.type ?? d.type, function: p.function ?? d.function,
                              attribute: p.attribute ?? d.attribute)
            }

            public init(from decoder: Decoder) throws {
                self = Syntax.resolve(try Partial(from: decoder), defaults: .defaultLight)
            }
        }

        /// Relative luminance check used to pick defaults for dark backgrounds.
        static func isDark(_ hex: String) -> Bool {
            var value: UInt64 = 0
            Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
            let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
            return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.5
        }

        public init(
            background: String, text: String, heading: String, link: String,
            codeBackground: String, codeText: String,
            blockquoteText: String, blockquoteBorder: String, rule: String,
            tableBorder: String? = nil, tableHeaderBackground: String? = nil, tableStripe: String? = nil,
            accent: String? = nil, muted: String? = nil, syntax: Syntax? = nil
        ) {
            self.background = background
            self.text = text
            self.heading = heading
            self.link = link
            self.codeBackground = codeBackground
            self.codeText = codeText
            self.blockquoteText = blockquoteText
            self.blockquoteBorder = blockquoteBorder
            self.rule = rule
            self.tableBorder = tableBorder ?? rule
            self.tableHeaderBackground = tableHeaderBackground ?? codeBackground
            self.tableStripe = tableStripe ?? codeBackground
            self.accent = accent ?? link
            self.muted = muted ?? blockquoteText
            self.syntax = syntax ?? Syntax.default(forBackground: background)
        }

        private enum CodingKeys: String, CodingKey {
            case background, text, heading, link, codeBackground, codeText
            case blockquoteText, blockquoteBorder, rule, tableBorder, tableHeaderBackground, tableStripe, accent, muted, syntax
        }

        /// The keys a file supplied; the rest are filled from a default palette.
        struct Partial: Decodable, Sendable {
            var background, text, heading, link, codeBackground, codeText: String?
            var blockquoteText, blockquoteBorder, rule, tableBorder, tableHeaderBackground, tableStripe, accent, muted: String?
            var syntax: Syntax.Partial?
        }

        /// Missing keys fall back to `defaults` (light or dark), and derived
        /// colors (headings, table borders, accent…) follow the supplied ones.
        static func resolve(_ p: Partial, defaults d: Palette) -> Palette {
            let background = p.background ?? d.background
            let text = p.text ?? d.text
            let link = p.link ?? d.link
            let codeBackground = p.codeBackground ?? d.codeBackground
            let rule = p.rule ?? d.rule
            let blockquoteText = p.blockquoteText ?? d.blockquoteText
            let supplied = p.background != nil || p.text != nil
            return Palette(
                background: background, text: text,
                heading: p.heading ?? (supplied ? text : d.heading), link: link,
                codeBackground: codeBackground, codeText: p.codeText ?? (supplied ? text : d.codeText),
                blockquoteText: blockquoteText, blockquoteBorder: p.blockquoteBorder ?? d.blockquoteBorder, rule: rule,
                tableBorder: p.tableBorder ?? (p.rule != nil ? rule : d.tableBorder),
                tableHeaderBackground: p.tableHeaderBackground ?? (p.codeBackground != nil ? codeBackground : d.tableHeaderBackground),
                tableStripe: p.tableStripe ?? (p.codeBackground != nil ? codeBackground : d.tableStripe),
                accent: p.accent ?? (p.link != nil ? link : d.accent),
                muted: p.muted ?? (p.blockquoteText != nil ? blockquoteText : d.muted),
                syntax: p.syntax.map { Syntax.resolve($0, defaults: Syntax.default(forBackground: background)) }
                    ?? (p.background != nil ? Syntax.default(forBackground: background) : d.syntax))
        }

        static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K, defaults: Palette) -> Palette {
            guard let partial = try? c.decodeIfPresent(Partial.self, forKey: key) else { return defaults }
            return resolve(partial, defaults: defaults)
        }

        public init(from decoder: Decoder) throws {
            self = Palette.resolve(try Partial(from: decoder), defaults: .defaultLight)
        }

        public static let defaultLight = Palette(
            background: "#FFFFFF", text: "#333333", heading: "#1D1D1F", link: "#0969DA",
            codeBackground: "#F4F4F5", codeText: "#333333",
            blockquoteText: "#666666", blockquoteBorder: "#DDDDDD", rule: "#E2E2E4",
            tableBorder: "#E2E2E4", tableHeaderBackground: "#F4F4F5", tableStripe: "#FAFAFA",
            accent: "#0969DA", muted: "#8E8E93")

        public static let defaultDark = Palette(
            background: "#1E1E1E", text: "#DDDDDD", heading: "#F2F2F2", link: "#6CB2FF",
            codeBackground: "#2B2B2B", codeText: "#DDDDDD",
            blockquoteText: "#AAAAAA", blockquoteBorder: "#444444", rule: "#3A3A3A",
            tableBorder: "#3A3A3A", tableHeaderBackground: "#2B2B2B", tableStripe: "#242424",
            accent: "#6CB2FF", muted: "#8E8E93")
    }
}

// MARK: - Lenient decoding helper

extension KeyedDecodingContainer {
    /// Decodes the value for `key`, falling back to `default` when the key is
    /// missing or holds an incompatible value.
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - Serialization

extension Theme {
    public static func decode(_ data: Data) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
