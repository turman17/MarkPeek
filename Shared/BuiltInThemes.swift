import Foundation

// The themes that ship with MarkPeek. Fixed identifiers so the active-theme
// record can refer to them across launches; they are never written to disk.
extension Theme {

    public static let builtIn: [Theme] = [modern, serif, github, plain, paper, mono]

    public static func builtIn(id: UUID) -> Theme? {
        builtIn.first { $0.id == id }
    }

    public static let modern: Theme = {
        var t = Theme(id: UUID(uuidString: "6D6F6465-726E-4000-8000-000000000001")!, name: "Modern", author: "MarkPeek")
        t.typography.codeFont = "SF Mono"
        t.layout.cornerRadius = 6
        return t
    }()

    public static let serif: Theme = {
        var t = Theme(id: UUID(uuidString: "73657269-6600-4000-8000-000000000002")!, name: "Serif", author: "MarkPeek")
        t.typography.bodyFont = "Charter"
        t.typography.codeFont = "Menlo"
        t.typography.fontSize = 17
        t.typography.lineHeight = 1.7
        t.typography.headingWeight = 600
        t.typography.headingScale = 1.3
        t.layout.maxWidth = 640
        t.layout.cornerRadius = 4
        t.elements.blockquoteItalic = true
        t.elements.ruleStyle = .short
        t.light = Palette(
            background: "#FFFFFF", text: "#222222", heading: "#1A1A1A", link: "#7A5C2E",
            codeBackground: "#F7F5F0", codeText: "#222222",
            blockquoteText: "#555555", blockquoteBorder: "#B8A98A", rule: "#D8D2C4",
            tableHeaderBackground: "#F7F5F0", tableStripe: "#FBFAF7", accent: "#7A5C2E", muted: "#8A8378",
            syntax: Palette.Syntax(keyword: "#8A3B2E", string: "#4F6B3A", comment: "#8A8378", number: "#2F5D7A",
                                   type: "#5B4A8A", function: "#7A5C2E", attribute: "#946B1C"))
        t.dark = Palette(
            background: "#1C1A17", text: "#DED8CC", heading: "#EFE9DD", link: "#C8A86A",
            codeBackground: "#2A2723", codeText: "#DED8CC",
            blockquoteText: "#B0A892", blockquoteBorder: "#6E6045", rule: "#4A453B",
            tableHeaderBackground: "#2A2723", tableStripe: "#221F1B", accent: "#C8A86A", muted: "#8F877A",
            syntax: Palette.Syntax(keyword: "#E09A86", string: "#B7C98B", comment: "#8F877A", number: "#8FB8D6",
                                   type: "#B9A6E0", function: "#C8A86A", attribute: "#D6C07A"))
        return t
    }()

    public static let github: Theme = {
        var t = Theme(id: UUID(uuidString: "67697468-7562-4000-8000-000000000003")!, name: "GitHub", author: "MarkPeek")
        t.typography.codeFont = "SF Mono"
        t.typography.lineHeight = 1.5
        t.typography.headingWeight = 600
        t.typography.headingScale = 1.26
        t.layout.maxWidth = 760
        t.layout.cornerRadius = 6
        t.elements.headingUnderline = true
        t.elements.tableBorders = .all
        t.elements.tableStriped = true
        t.light = Palette(
            background: "#FFFFFF", text: "#1F2328", heading: "#1F2328", link: "#0969DA",
            codeBackground: "#F6F8FA", codeText: "#1F2328",
            blockquoteText: "#59636E", blockquoteBorder: "#D1D9E0", rule: "#D1D9E0",
            tableBorder: "#D1D9E0", tableHeaderBackground: "#F6F8FA", tableStripe: "#F6F8FA",
            accent: "#1F883D", muted: "#59636E",
            syntax: Palette.Syntax(keyword: "#CF222E", string: "#0A3069", comment: "#6E7781", number: "#0550AE",
                                   type: "#953800", function: "#8250DF", attribute: "#116329"))
        t.dark = Palette(
            background: "#0D1117", text: "#E6EDF3", heading: "#E6EDF3", link: "#4493F8",
            codeBackground: "#161B22", codeText: "#E6EDF3",
            blockquoteText: "#8D96A0", blockquoteBorder: "#30363D", rule: "#30363D",
            tableBorder: "#30363D", tableHeaderBackground: "#161B22", tableStripe: "#161B22",
            accent: "#3FB950", muted: "#8D96A0",
            syntax: Palette.Syntax(keyword: "#FF7B72", string: "#A5D6FF", comment: "#8B949E", number: "#79C0FF",
                                   type: "#FFA657", function: "#D2A8FF", attribute: "#7EE787"))
        return t
    }()

    public static let plain: Theme = {
        var t = Theme(id: UUID(uuidString: "706C6169-6E00-4000-8000-000000000004")!, name: "Plain", author: "MarkPeek")
        t.typography.bodyFont = "Helvetica"
        t.typography.codeFont = "Courier"
        t.typography.lineHeight = 1.4
        t.typography.headingScale = 1.2
        t.layout.maxWidth = 0
        t.layout.pagePadding = 20
        t.layout.cornerRadius = 0
        t.layout.codeBlockPadding = 12
        t.elements.codeShowLanguage = false
        t.elements.codeHighlighting = false
        t.elements.tableStriped = false
        t.elements.tableBorders = .all
        t.elements.imageRounded = false
        t.elements.linkUnderline = true
        t.light = Palette(
            background: "#FFFFFF", text: "#000000", heading: "#000000", link: "#000000",
            codeBackground: "#F0F0F0", codeText: "#000000",
            blockquoteText: "#000000", blockquoteBorder: "#000000", rule: "#000000",
            tableBorder: "#000000", tableHeaderBackground: "#F0F0F0", tableStripe: "#FFFFFF",
            accent: "#000000", muted: "#555555")
        t.dark = Palette(
            background: "#111111", text: "#EEEEEE", heading: "#EEEEEE", link: "#EEEEEE",
            codeBackground: "#2A2A2A", codeText: "#EEEEEE",
            blockquoteText: "#EEEEEE", blockquoteBorder: "#EEEEEE", rule: "#EEEEEE",
            tableBorder: "#EEEEEE", tableHeaderBackground: "#2A2A2A", tableStripe: "#111111",
            accent: "#EEEEEE", muted: "#AAAAAA")
        return t
    }()

    public static let paper: Theme = {
        var t = Theme(id: UUID(uuidString: "70617065-7200-4000-8000-000000000005")!, name: "Paper", author: "MarkPeek")
        t.typography.bodyFont = "Iowan Old Style"
        t.typography.headingFont = "-apple-system"
        t.typography.codeFont = "Menlo"
        t.typography.fontSize = 17
        t.typography.lineHeight = 1.65
        t.typography.headingWeight = 600
        t.typography.headingScale = 1.33
        t.typography.textAlignment = .justified
        t.typography.hyphenate = true
        t.layout.maxWidth = 620
        t.layout.pagePadding = 56
        t.layout.cornerRadius = 3
        t.elements.blockquoteItalic = true
        t.elements.dropCap = true
        t.elements.ruleStyle = .dots
        t.elements.listMarker = .dash
        t.light = Palette(
            background: "#FBF8F1", text: "#2C2A25", heading: "#1E1C18", link: "#8B5F3E",
            codeBackground: "#F0EBE0", codeText: "#2C2A25",
            blockquoteText: "#5E5A50", blockquoteBorder: "#C9BBA3", rule: "#D9D0BE",
            tableBorder: "#D9D0BE", tableHeaderBackground: "#F0EBE0", tableStripe: "#F6F2E8",
            accent: "#8B5F3E", muted: "#8A8273",
            syntax: Palette.Syntax(keyword: "#8B3A3A", string: "#4E6E3B", comment: "#8A8273", number: "#2E5E7E",
                                   type: "#5A4B8C", function: "#8B5F3E", attribute: "#946B1C"))
        t.dark = Palette(
            background: "#201D18", text: "#D9D2C3", heading: "#EFE8D8", link: "#C89A6E",
            codeBackground: "#2C2822", codeText: "#D9D2C3",
            blockquoteText: "#A79E8B", blockquoteBorder: "#5C5240", rule: "#3E382E",
            tableBorder: "#3E382E", tableHeaderBackground: "#2C2822", tableStripe: "#262219",
            accent: "#C89A6E", muted: "#8A8273",
            syntax: Palette.Syntax(keyword: "#E39A8A", string: "#B5C98E", comment: "#8A8273", number: "#8FB8D6",
                                   type: "#B9A6E0", function: "#C89A6E", attribute: "#D6C07A"))
        return t
    }()

    public static let mono: Theme = {
        var t = Theme(id: UUID(uuidString: "6D6F6E6F-0000-4000-8000-000000000006")!, name: "Mono", author: "MarkPeek")
        t.typography.bodyFont = "SF Mono"
        t.typography.codeFont = "SF Mono"
        t.typography.fontSize = 14
        t.typography.lineHeight = 1.7
        t.typography.headingWeight = 700
        t.typography.headingScale = 1.15
        t.typography.codeFontSize = 1.0
        t.layout.maxWidth = 720
        t.layout.cornerRadius = 4
        t.elements.headingUnderline = true
        t.elements.linkUnderline = true
        t.elements.listMarker = .dash
        t.elements.tableBorders = .all
        t.elements.tableStriped = false
        t.elements.imageRounded = false
        t.light = Palette(
            background: "#FAFAFA", text: "#24292F", heading: "#000000", link: "#0550AE",
            codeBackground: "#EFF1F3", codeText: "#24292F",
            blockquoteText: "#57606A", blockquoteBorder: "#24292F", rule: "#24292F",
            tableBorder: "#24292F", tableHeaderBackground: "#EFF1F3", tableStripe: "#FAFAFA",
            accent: "#0550AE", muted: "#6E7781")
        t.dark = Palette(
            background: "#161616", text: "#C9D1D9", heading: "#FFFFFF", link: "#79C0FF",
            codeBackground: "#202020", codeText: "#C9D1D9",
            blockquoteText: "#8B949E", blockquoteBorder: "#C9D1D9", rule: "#C9D1D9",
            tableBorder: "#C9D1D9", tableHeaderBackground: "#202020", tableStripe: "#161616",
            accent: "#79C0FF", muted: "#8B949E")
        return t
    }()
}
