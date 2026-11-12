import Foundation

/// Where the rendered document is shown. Each surface tweaks the outer
/// layout while the theme itself stays the same.
public enum RenderSurface: Sendable, Equatable {
    /// Quick Look and plain views: the document fills the viewport.
    case edgeToEdge
    /// The app's reader: a floating page card over a transparent body.
    case pageCard
    /// PDF export and printing: no chrome, paper handles the margins.
    case print
}

public enum ThemeColorScheme: String, Sendable, CaseIterable {
    case light, dark
}

public struct RenderOptions: Sendable {
    public var surface: RenderSurface = .edgeToEdge
    /// Forces a palette regardless of the theme's appearance setting.
    public var colorScheme: ThemeColorScheme? = nil
    /// Maps an image `src` from the Markdown to the URL the HTML should use
    /// (for example a `data:` URI). Return nil to leave the source untouched.
    public var imageResolver: (@Sendable (String) -> String?)? = nil
    /// Writes palette colors directly into every rule instead of CSS custom
    /// properties. Quick Look's data-based HTML renderer doesn't resolve
    /// `var()`, so the extension needs this.
    public var inlineColors = false
    /// JavaScript appended at the end of the body (math and diagram engines).
    /// Only the app supplies these; Quick Look renders without scripts.
    public var scripts: [String] = []
    /// Tags block elements with `data-line="start-end"` (1-based lines of the
    /// Markdown) so the app can link the preview to the editor. Off for
    /// exports and Quick Look.
    public var sourceMap = false

    public init(surface: RenderSurface = .edgeToEdge, colorScheme: ThemeColorScheme? = nil,
                imageResolver: (@Sendable (String) -> String?)? = nil, inlineColors: Bool = false,
                scripts: [String] = [], sourceMap: Bool = false) {
        self.surface = surface
        self.colorScheme = colorScheme
        self.imageResolver = imageResolver
        self.inlineColors = inlineColors
        self.scripts = scripts
        self.sourceMap = sourceMap
    }
}

// Turns a Theme into CSS. The palette is exposed as CSS custom properties so
// a theme's custom CSS (and future rules) can reuse it without duplication.
public enum ThemeStylesheet {

    public static func css(for theme: Theme, options: RenderOptions) -> String {
        let rules = [
            baseRules(theme),
            headingRules(theme),
            inlineRules(theme),
            listRules(theme),
            codeRules(theme),
            tableRules(theme),
            imageRules(theme),
            surfaceRules(theme, options),
            options.sourceMap ? sourceHoverRules : "",
            theme.customCSS.isEmpty ? "" : "/* Custom CSS */\n" + theme.customCSS,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        if options.inlineColors {
            return inlined(rules, theme, options)
        }
        return colorSchemeBlock(theme, options) + "\n\n" + rules
    }

    // MARK: Palette → custom properties

    private static func variableMap(_ p: Theme.Palette, cardShadow: String) -> [(String, String)] {
        [
            ("bg", p.background), ("text", p.text), ("heading", p.heading), ("link", p.link),
            ("code-bg", p.codeBackground), ("code-text", p.codeText),
            ("quote-text", p.blockquoteText), ("quote-border", p.blockquoteBorder), ("rule", p.rule),
            ("table-border", p.tableBorder), ("table-head", p.tableHeaderBackground), ("table-stripe", p.tableStripe),
            ("accent", p.accent), ("muted", p.muted), ("card-shadow", cardShadow),
            ("syn-kw", p.syntax.keyword), ("syn-str", p.syntax.string), ("syn-cm", p.syntax.comment),
            ("syn-num", p.syntax.number), ("syn-type", p.syntax.type), ("syn-fn", p.syntax.function),
            ("syn-attr", p.syntax.attribute),
        ]
    }

    private static func variables(_ p: Theme.Palette, cardShadow: String) -> String {
        variableMap(p, cardShadow: cardShadow).map { "  --mp-\($0.0): \($0.1);" }.joined(separator: "\n")
    }

    /// Emits the rules once per palette with every `var(--mp-*)` replaced by
    /// its value, so renderers without custom-property support still work.
    private static func inlined(_ rules: String, _ t: Theme, _ o: RenderOptions) -> String {
        func resolve(_ p: Theme.Palette, shadow: String) -> String {
            var out = rules
            for (name, value) in variableMap(p, cardShadow: shadow) {
                out = out.replacingOccurrences(of: "var(--mp-\(name))", with: value)
            }
            return out
        }
        let light = resolve(t.light, shadow: lightShadow)
        let dark = resolve(t.dark, shadow: darkShadow)
        switch resolvedScheme(t, o) {
        case .light: return light
        case .dark: return dark
        case nil: return light + "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}"
        }
    }

    private static func resolvedScheme(_ t: Theme, _ o: RenderOptions) -> ThemeColorScheme? {
        o.colorScheme ?? {
            switch t.appearance {
            case .light: .light
            case .dark: .dark
            case .system: nil
            }
        }()
    }

    /// The block linked to the editor line under the mouse (split view).
    private static let sourceHoverRules = """
        .mp-content [data-line] { transition: background-color 0.12s ease, box-shadow 0.12s ease; }
        .mp-content [data-line].mp-hover {
          background: color-mix(in srgb, var(--mp-accent) 14%, transparent);
          box-shadow: 0 0 0 6px color-mix(in srgb, var(--mp-accent) 14%, transparent);
          border-radius: 3px;
        }
        """

    private static let lightShadow = "0 8px 28px rgba(0,0,0,0.16), 0 0 0 1px rgba(0,0,0,0.05)"
    private static let darkShadow = "0 10px 32px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.08)"

    private static func colorSchemeBlock(_ t: Theme, _ o: RenderOptions) -> String {
        let light = ":root {\n  color-scheme: light;\n" + variables(t.light, cardShadow: lightShadow) + "\n}"
        let dark = ":root {\n  color-scheme: dark;\n" + variables(t.dark, cardShadow: darkShadow) + "\n}"
        switch resolvedScheme(t, o) {
        case .light: return light
        case .dark: return dark
        case nil: return light + "\n@media (prefers-color-scheme: dark) {\n" + dark + "\n}"
        }
    }

    // MARK: Base

    private static func baseRules(_ t: Theme) -> String {
        let ty = t.typography, l = t.layout
        let width = l.maxWidth > 0 ? "max-width: \(fmt(l.maxWidth))px;" : ""
        return """
        html { -webkit-text-size-adjust: 100%; }
        body {
          margin: 0;
          font-family: \(FontCatalog.cssStack(for: ty.bodyFont));
          font-size: \(fmt(ty.fontSize))px;
          line-height: \(fmt(ty.lineHeight));
          color: var(--mp-text);
          background: var(--mp-bg);
          text-align: \(ty.textAlignment == .justified ? "justify" : "start");
          \(ty.hyphenate ? "-webkit-hyphens: auto; hyphens: auto;" : "")
          -webkit-font-smoothing: antialiased;
          text-rendering: optimizeLegibility;
          font-feature-settings: "kern", "liga";
        }
        .mp-content {
          \(width)
          margin: 0 auto;
          padding: \(fmt(l.pagePadding))px \(fmt(l.sidePadding))px;
          box-sizing: border-box;
          overflow-wrap: break-word;
          \(t.elements.headingNumbering != .off ? "counter-reset: mp-h2;" : "")
        }
        .mp-content > :first-child { margin-top: 0; }
        .mp-content > :last-child { margin-bottom: 0; }
        p, blockquote, ul, ol, pre, table, .mp-table, figure { margin: 0 0 \(fmt(ty.paragraphSpacing))em; }
        blockquote {
          padding: 0.1em 0 0.1em 1em;
          border-left: \(fmt(l.blockquoteBorderWidth))px solid var(--mp-quote-border);
          color: var(--mp-quote-text);
          \(t.elements.blockquoteItalic ? "font-style: italic;" : "")
        }
        blockquote > :last-child { margin-bottom: 0; }
        \(ruleRules(t))
        \(t.elements.dropCap ? dropCapRules(t) : "")
        ::selection { background: color-mix(in srgb, var(--mp-accent) 25%, transparent); }
        """
    }

    private static func ruleRules(_ t: Theme) -> String {
        switch t.elements.ruleStyle {
        case .line:
            "hr { border: none; border-top: 1px solid var(--mp-rule); margin: 2em 0; }"
        case .short:
            "hr { border: none; border-top: 2px solid var(--mp-rule); width: 72px; margin: 2.5em auto; }"
        case .dots:
            """
            hr { border: none; margin: 2.2em 0; text-align: center; line-height: 1; }
            hr::before { content: "\\2022 \\2022 \\2022"; color: var(--mp-muted); letter-spacing: 0.6em; margin-left: 0.6em; }
            """
        }
    }

    private static func dropCapRules(_ t: Theme) -> String {
        """
        .mp-content > p:first-of-type::first-letter {
          float: left;
          font-family: \(headingFamily(t));
          font-size: 3.1em;
          line-height: 0.82;
          padding: 0.08em 0.12em 0 0;
          font-weight: \(t.typography.headingWeight);
          color: var(--mp-heading);
        }
        """
    }

    // MARK: Headings

    private static func headingFamily(_ t: Theme) -> String {
        t.typography.headingFont.isEmpty ? "inherit" : FontCatalog.cssStack(for: t.typography.headingFont)
    }

    private static func headingRules(_ t: Theme) -> String {
        let ty = t.typography
        let s = ty.headingScale
        let sizes = [pow(s, 3), pow(s, 2), s, 1.0, 0.9, 0.8]
        var css = """
        h1, h2, h3, h4, h5, h6 {
          font-family: \(headingFamily(t));
          font-weight: \(ty.headingWeight);
          line-height: 1.25;
          margin: \(fmt(ty.headingSpacing))em 0 0.5em;
          color: var(--mp-heading);
          text-align: start;
          -webkit-hyphens: manual; hyphens: manual;
        }
        \(sizes.enumerated().map { "h\($0.offset + 1) { font-size: \(fmt($0.element))em; }" }.joined(separator: "\n"))
        h5, h6 { color: var(--mp-muted); }
        """
        if t.elements.headingUnderline {
            css += "\nh1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid var(--mp-rule); }"
        }
        switch t.elements.headingNumbering {
        case .off: break
        case .h2:
            css += """

            h2 { counter-increment: mp-h2; }
            h2::before { content: counter(mp-h2) ".  "; color: var(--mp-muted); font-weight: 500; }
            """
        case .h3:
            css += """

            h2 { counter-increment: mp-h2; counter-reset: mp-h3; }
            h2::before { content: counter(mp-h2) ".  "; color: var(--mp-muted); font-weight: 500; }
            h3 { counter-increment: mp-h3; }
            h3::before { content: counter(mp-h2) "." counter(mp-h3) "  "; color: var(--mp-muted); font-weight: 500; }
            """
        }
        return css
    }

    // MARK: Inline

    private static func inlineRules(_ t: Theme) -> String {
        """
        a { color: var(--mp-link); text-decoration: \(t.elements.linkUnderline ? "underline" : "none"); text-underline-offset: 0.15em; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 700; }
        del { color: var(--mp-muted); }
        mark { background: color-mix(in srgb, var(--mp-accent) 30%, transparent); color: inherit; padding: 0 0.15em; }
        kbd { font-family: \(FontCatalog.cssStack(for: t.typography.codeFont)); font-size: 0.85em; padding: 0.1em 0.4em; border: 1px solid var(--mp-rule); border-bottom-width: 2px; border-radius: 4px; }
        sup, sub { line-height: 0; }
        """
    }

    // MARK: Lists

    private static func listRules(_ t: Theme) -> String {
        let marker: String = switch t.elements.listMarker {
        case .disc: "disc"
        case .circle: "circle"
        case .square: "square"
        case .dash: "\"\\2013\\00a0\\00a0\""
        }
        return """
        ul, ol { padding-left: \(fmt(t.layout.listIndent))em; }
        ul { list-style-type: \(marker); }
        li { margin: 0.25em 0; }
        li > ul, li > ol { margin-bottom: 0; }
        li::marker { color: var(--mp-muted); }
        li.task { list-style: none; margin-left: -\(fmt(t.layout.listIndent))em; padding-left: \(fmt(t.layout.listIndent))em; position: relative; }
        li.task > input {
          position: absolute; left: 0; top: 0.3em; margin: 0;
          appearance: none; -webkit-appearance: none;
          width: 1em; height: 1em; box-sizing: border-box;
          border: 1.5px solid var(--mp-muted); border-radius: 0.25em;
          background: transparent;
        }
        li.task > input:checked { background: var(--mp-accent); border-color: var(--mp-accent); }
        li.task > input:checked::after {
          content: ""; position: absolute; left: 0.28em; top: 0.08em;
          width: 0.25em; height: 0.5em;
          border: solid var(--mp-bg); border-width: 0 0.15em 0.15em 0; transform: rotate(45deg);
        }
        li.task.done { color: var(--mp-muted); }
        """
    }

    // MARK: Code

    private static func codeRules(_ t: Theme) -> String {
        let e = t.elements, l = t.layout
        var css = """
        code, pre { font-family: \(FontCatalog.cssStack(for: t.typography.codeFont)); font-variant-ligatures: none; }
        :not(pre) > code {
          font-size: \(fmt(t.typography.codeFontSize))em;
          background: var(--mp-code-bg);
          color: var(--mp-code-text);
          padding: 0.15em 0.4em;
          border-radius: \(fmt(min(l.cornerRadius, 6)))px;
        }
        pre {
          position: relative;
          font-size: \(fmt(t.typography.codeFontSize))em;
          line-height: 1.55;
          background: var(--mp-code-bg);
          color: var(--mp-code-text);
          padding: \(fmt(l.codeBlockPadding))px;
          border-radius: \(fmt(l.cornerRadius))px;
          overflow-x: auto;
          text-align: start;
          -webkit-hyphens: none; hyphens: none;
        }
        pre code { font-size: 1em; white-space: \(e.codeWrapLines ? "pre-wrap" : "pre"); word-break: \(e.codeWrapLines ? "break-word" : "normal"); display: block; }
        """
        if e.codeShowLanguage {
            css += """

            pre[data-lang]::before {
              content: attr(data-lang);
              position: absolute; top: 6px; right: 10px;
              font-family: \(FontCatalog.cssStack(for: t.typography.bodyFont));
              font-size: 11px; letter-spacing: 0.02em;
              color: var(--mp-muted);
              pointer-events: none;
            }
            """
        }
        if e.codeHighlighting {
            css += """

            .tok-kw { color: var(--mp-syn-kw); }
            .tok-str { color: var(--mp-syn-str); }
            .tok-cm { color: var(--mp-syn-cm); font-style: italic; }
            .tok-num { color: var(--mp-syn-num); }
            .tok-type { color: var(--mp-syn-type); }
            .tok-fn { color: var(--mp-syn-fn); }
            .tok-attr { color: var(--mp-syn-attr); }
            """
        }
        if e.codeLineNumbers {
            css += """

            pre.mp-ln code { counter-reset: mp-line; }
            pre.mp-ln .line { counter-increment: mp-line; }
            pre.mp-ln .line::before {
              content: counter(mp-line);
              display: inline-block; width: 2.2em; margin-right: 1em;
              text-align: right; color: var(--mp-muted); opacity: 0.8;
              -webkit-user-select: none; user-select: none;
            }
            """
        }
        return css
    }

    // MARK: Tables

    private static func tableRules(_ t: Theme) -> String {
        let p = t.layout.tableCellPadding
        let borders: String = switch t.elements.tableBorders {
        case .all: "th, td { border: 1px solid var(--mp-table-border); }"
        case .horizontal: "th, td { border-bottom: 1px solid var(--mp-table-border); }"
        case .none: "th { border-bottom: 2px solid var(--mp-table-border); }"
        }
        return """
        .mp-table { overflow-x: auto; border-radius: \(fmt(t.layout.cornerRadius))px; }
        table { border-collapse: collapse; width: 100%; font-size: 0.95em; text-align: start; }
        th, td { padding: \(fmt(p))px \(fmt(p * 1.5))px; vertical-align: top; }
        th { background: var(--mp-table-head); font-weight: 600; }
        \(borders)
        \(t.elements.tableStriped ? "tbody tr:nth-child(even) { background: var(--mp-table-stripe); }" : "")
        table.mp-frontmatter { width: auto; min-width: 50%; font-size: 0.9em; margin-bottom: \(fmt(t.typography.paragraphSpacing * 1.5))em; }
        table.mp-frontmatter th { text-align: start; white-space: nowrap; color: var(--mp-muted); font-weight: 500; }
        pre.mp-frontmatter { font-size: 0.85em; color: var(--mp-muted); }
        pre.mermaid { background: transparent; color: var(--mp-text); text-align: center; overflow: visible; }
        pre.mermaid svg { max-width: 100%; height: auto; }
        .math-display { margin: 0 0 \(fmt(t.typography.paragraphSpacing))em; text-align: center; overflow-x: auto; }
        mjx-container[jax="SVG"][display="true"] { margin: 0.5em 0; }
        """
    }

    // MARK: Images

    private static func imageRules(_ t: Theme) -> String {
        let e = t.elements
        var css = """
        img { max-width: \(fmt(t.layout.imageMaxWidth))%; height: auto; vertical-align: middle; }
        """
        if e.imageRounded { css += "\nimg { border-radius: \(fmt(t.layout.cornerRadius))px; }" }
        if e.imageShadow { css += "\nimg { box-shadow: 0 4px 18px rgba(0,0,0,0.18); }" }
        if e.imageCentered { css += "\np:has(> img:only-child) { text-align: center; }" }
        return css
    }

    // MARK: Surface

    private static func surfaceRules(_ t: Theme, _ o: RenderOptions) -> String {
        switch o.surface {
        case .edgeToEdge:
            return ""
        case .pageCard:
            let l = t.layout
            let width = l.maxWidth > 0 ? fmt(l.maxWidth) : "820"
            return """
            html { height: 100%; }
            body {
              background: transparent;
              min-height: 100%;
              display: grid;
              align-content: safe center;
              padding: \(fmt(max(24, l.pagePadding)))px 24px \(fmt(max(24, l.pagePadding)))px calc(24px + var(--mp-inset, 0px));
              box-sizing: border-box;
            }
            .mp-page {
              background: var(--mp-bg);
              width: 100%;
              max-width: \(width)px;
              margin: 0 auto;
              border-radius: 12px;
              box-shadow: var(--mp-card-shadow);
              box-sizing: border-box;
            }
            .mp-page > .mp-content { max-width: none; padding: 36px \(fmt(max(32, l.sidePadding)))px; }
            """
        case .print:
            return """
            body { background: var(--mp-bg); -webkit-print-color-adjust: exact; print-color-adjust: exact; }
            .mp-content { max-width: none; padding: 0; }
            pre, pre code { white-space: pre-wrap; word-break: break-word; }
            h1, h2, h3, h4 { break-after: avoid; }
            pre, blockquote, img, tr, figure { break-inside: avoid; }
            """
        }
    }

    // MARK: Helpers

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }
}

// MARK: - Fonts

/// Font families offered in the UI, with the CSS stack each maps to.
public enum FontCatalog {

    public struct Family: Identifiable, Hashable, Sendable {
        public let id: String      // value stored in the theme
        public let name: String    // shown in the UI
        public let stack: String   // CSS font-family value
    }

    public static let body: [Family] = [
        Family(id: "-apple-system", name: "San Francisco (System)", stack: "-apple-system, system-ui, 'Helvetica Neue', sans-serif"),
        Family(id: "ui-rounded", name: "SF Rounded", stack: "ui-rounded, -apple-system, system-ui, sans-serif"),
        Family(id: "ui-serif", name: "New York (System Serif)", stack: "ui-serif, 'New York', Georgia, serif"),
        Family(id: "Helvetica Neue", name: "Helvetica Neue", stack: "'Helvetica Neue', Helvetica, Arial, sans-serif"),
        Family(id: "Helvetica", name: "Helvetica", stack: "Helvetica, Arial, sans-serif"),
        Family(id: "Avenir Next", name: "Avenir Next", stack: "'Avenir Next', Avenir, sans-serif"),
        Family(id: "Seravek", name: "Seravek", stack: "Seravek, sans-serif"),
        Family(id: "Gill Sans", name: "Gill Sans", stack: "'Gill Sans', sans-serif"),
        Family(id: "Charter", name: "Charter", stack: "Charter, Georgia, serif"),
        Family(id: "Georgia", name: "Georgia", stack: "Georgia, serif"),
        Family(id: "Iowan Old Style", name: "Iowan Old Style", stack: "'Iowan Old Style', Palatino, serif"),
        Family(id: "Palatino", name: "Palatino", stack: "Palatino, 'Palatino Linotype', serif"),
        Family(id: "Baskerville", name: "Baskerville", stack: "Baskerville, serif"),
        Family(id: "Hoefler Text", name: "Hoefler Text", stack: "'Hoefler Text', serif"),
        Family(id: "Times New Roman", name: "Times New Roman", stack: "'Times New Roman', Times, serif"),
        Family(id: "SF Mono", name: "SF Mono", stack: "ui-monospace, 'SF Mono', Menlo, monospace"),
    ]

    public static let code: [Family] = [
        Family(id: "SF Mono", name: "SF Mono", stack: "ui-monospace, 'SF Mono', Menlo, monospace"),
        Family(id: "Menlo", name: "Menlo", stack: "Menlo, ui-monospace, monospace"),
        Family(id: "Monaco", name: "Monaco", stack: "Monaco, ui-monospace, monospace"),
        Family(id: "Courier New", name: "Courier New", stack: "'Courier New', Courier, monospace"),
        Family(id: "Courier", name: "Courier", stack: "Courier, monospace"),
        Family(id: "Andale Mono", name: "Andale Mono", stack: "'Andale Mono', monospace"),
        Family(id: "PT Mono", name: "PT Mono", stack: "'PT Mono', monospace"),
    ]

    /// CSS `font-family` value for a stored family id. Unknown ids (fonts the
    /// user typed in) get a generic fallback so text never disappears.
    public static func cssStack(for id: String) -> String {
        if let known = (body + code).first(where: { $0.id == id }) { return known.stack }
        let mono = id.localizedCaseInsensitiveContains("mono") || id.localizedCaseInsensitiveContains("code")
        let serifHints = ["serif", "georgia", "times", "garamond", "baskerville", "book", "palatino", "charter"]
        let serif = serifHints.contains { id.localizedCaseInsensitiveContains($0) }
        let fallback = mono ? "ui-monospace, monospace" : serif ? "serif" : "sans-serif"
        return "'\(id.replacingOccurrences(of: "'", with: ""))', \(fallback)"
    }
}
