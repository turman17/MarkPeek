import SwiftUI

/// Right-hand inspector that edits the active theme with a live preview in
/// the reader. Four tabs keep each setting one click away.
struct ThemeInspector: View {
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState
    @Environment(\.openWindow) private var openWindow
    @State private var tab: Tab = .type

    enum Tab: String, CaseIterable, Identifiable {
        case type = "Type", layout = "Layout", colors = "Colors", extras = "Extras"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Design.Space.m)
            .padding(.vertical, Design.Space.s)

            Form {
                switch tab {
                case .type: TypeSection()
                case .layout: LayoutSection()
                case .colors: ColorsSection()
                case .extras: ExtrasSection()
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: tab) { _, new in
            if new != .colors { themes.previewScheme = nil }
        }
        .onDisappear { themes.previewScheme = nil }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(themes.activeLabel)
                    .font(.headline)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if themes.isActiveModified && themes.source != nil {
                Button("Revert") { themes.revert() }
                    .help("Discard edits and go back to the saved theme")
            }
            Button("Save As…") { ui.showSaveTheme = true }
                .help("Save these settings as a new theme")
            Button {
                openWindow(id: GuideView.windowID)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Open the theme guide (⇧⌘?)")
        }
        .controlSize(.small)
        .padding(.horizontal, Design.Space.l)
        .padding(.vertical, Design.Space.m)
    }

    private var status: String {
        if themes.source == nil { return "Unsaved custom theme" }
        if themes.isActiveBuiltIn {
            return themes.isActiveModified ? "Built-in · edited, save as a new theme to keep" : "Built-in theme"
        }
        return themes.isActiveModified ? "Saving…" : "Your theme · changes save automatically"
    }
}

// MARK: - Type

private struct TypeSection: View {
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        Section("Fonts") {
            FontFamilyPicker("Body", selection: themes.binding(\.typography.bodyFont), families: FontCatalog.body)
            FontFamilyPicker("Headings", selection: themes.binding(\.typography.headingFont), families: FontCatalog.body, inheritLabel: "Same as body")
            FontFamilyPicker("Code", selection: themes.binding(\.typography.codeFont), families: FontCatalog.code)
        }
        Section("Size") {
            SettingSlider("Text size", value: themes.binding(\.typography.fontSize), in: 11...24, step: 1, format: "%.0f px")
            SettingSlider("Line height", value: themes.binding(\.typography.lineHeight), in: 1.2...2.2, step: 0.05, format: "%.2f")
            SettingSlider("Paragraph spacing", value: themes.binding(\.typography.paragraphSpacing), in: 0...2.5, step: 0.1, format: "%.1f em")
            SettingSlider("Code size", value: themes.binding(\.typography.codeFontSize), in: 0.7...1.1, step: 0.05, format: "%.2f em")
        }
        Section("Headings") {
            Picker("Weight", selection: themes.binding(\.typography.headingWeight)) {
                Text("Regular").tag(400)
                Text("Medium").tag(500)
                Text("Semibold").tag(600)
                Text("Bold").tag(700)
                Text("Heavy").tag(800)
            }
            SettingSlider("Scale", value: themes.binding(\.typography.headingScale), in: 1.1...1.5, step: 0.01, format: "%.2f")
            SettingSlider("Space above", value: themes.binding(\.typography.headingSpacing), in: 0.5...3, step: 0.1, format: "%.1f em")
        }
        Section("Text") {
            Picker("Alignment", selection: themes.binding(\.typography.textAlignment)) {
                ForEach(Theme.TextAlignment.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Hyphenate long words", isOn: themes.binding(\.typography.hyphenate))
        }
    }
}

// MARK: - Layout

private struct LayoutSection: View {
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        Section("Page") {
            SettingSlider("Content width", value: themes.binding(\.layout.maxWidth), in: 0...1200, step: 20, format: "%.0f px", zeroLabel: "Full")
            SettingSlider("Top and bottom", value: themes.binding(\.layout.pagePadding), in: 0...120, step: 4, format: "%.0f px")
            SettingSlider("Sides", value: themes.binding(\.layout.sidePadding), in: 0...80, step: 4, format: "%.0f px")
        }
        Section("Blocks") {
            SettingSlider("Corner radius", value: themes.binding(\.layout.cornerRadius), in: 0...20, step: 1, format: "%.0f px")
            SettingSlider("Code padding", value: themes.binding(\.layout.codeBlockPadding), in: 0...32, step: 2, format: "%.0f px")
            SettingSlider("Quote border", value: themes.binding(\.layout.blockquoteBorderWidth), in: 0...12, step: 1, format: "%.0f px")
            SettingSlider("List indent", value: themes.binding(\.layout.listIndent), in: 1...3, step: 0.1, format: "%.1f em")
            SettingSlider("Table cell padding", value: themes.binding(\.layout.tableCellPadding), in: 2...16, step: 1, format: "%.0f px")
        }
        Section("Images") {
            SettingSlider("Max width", value: themes.binding(\.layout.imageMaxWidth), in: 25...100, step: 5, format: "%.0f %%")
        }
    }
}

// MARK: - Colors

private struct ColorsSection: View {
    @ObservedObject private var themes = ThemeStore.shared
    @State private var editing: ThemeColorScheme = .light

    private var palette: WritableKeyPath<Theme, Theme.Palette> {
        editing == .light ? \.light : \.dark
    }

    var body: some View {
        Section {
            Picker("Appearance", selection: themes.binding(\.appearance)) {
                ForEach(Theme.Appearance.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Editing", selection: $editing) {
                Text("Light").tag(ThemeColorScheme.light)
                Text("Dark").tag(ThemeColorScheme.dark)
            }
            .pickerStyle(.segmented)
            .onAppear { themes.previewScheme = editing }
            .onChange(of: editing) { _, new in themes.previewScheme = new }
        } footer: {
            Text("The reader shows the palette you're editing while this tab is open.")
        }
        Section("Text") {
            ColorRow("Background", themes.binding(palette.appending(path: \.background)))
            ColorRow("Text", themes.binding(palette.appending(path: \.text)))
            ColorRow("Headings", themes.binding(palette.appending(path: \.heading)))
            ColorRow("Links", themes.binding(palette.appending(path: \.link)))
            ColorRow("Accent", themes.binding(palette.appending(path: \.accent)))
            ColorRow("Secondary text", themes.binding(palette.appending(path: \.muted)))
        }
        Section("Code") {
            ColorRow("Background", themes.binding(palette.appending(path: \.codeBackground)))
            ColorRow("Text", themes.binding(palette.appending(path: \.codeText)))
        }
        Section("Syntax colors") {
            ColorRow("Keywords", themes.binding(palette.appending(path: \.syntax.keyword)))
            ColorRow("Strings", themes.binding(palette.appending(path: \.syntax.string)))
            ColorRow("Comments", themes.binding(palette.appending(path: \.syntax.comment)))
            ColorRow("Numbers", themes.binding(palette.appending(path: \.syntax.number)))
            ColorRow("Types", themes.binding(palette.appending(path: \.syntax.type)))
            ColorRow("Functions", themes.binding(palette.appending(path: \.syntax.function)))
            ColorRow("Attributes and keys", themes.binding(palette.appending(path: \.syntax.attribute)))
        }
        Section("Quotes and rules") {
            ColorRow("Quote text", themes.binding(palette.appending(path: \.blockquoteText)))
            ColorRow("Quote border", themes.binding(palette.appending(path: \.blockquoteBorder)))
            ColorRow("Rules", themes.binding(palette.appending(path: \.rule)))
        }
        Section("Tables") {
            ColorRow("Borders", themes.binding(palette.appending(path: \.tableBorder)))
            ColorRow("Header", themes.binding(palette.appending(path: \.tableHeaderBackground)))
            ColorRow("Stripe", themes.binding(palette.appending(path: \.tableStripe)))
        }
        Section {
            if canResetPalette {
                Button("Reset \(editingName) Colors to Saved…") { confirmReset = true }
            }
            Button("Replace \(editingName) Colors with \(otherName)…") { confirmCopy = true }
        } footer: {
            Text("Both replace every \(editingName.lowercased()) color above. Revert in the header restores the whole theme.")
        }
        .confirmationDialog("Replace all \(editingName.lowercased()) colors with the \(otherName.lowercased()) palette?",
                            isPresented: $confirmCopy, titleVisibility: .visible) {
            Button("Replace \(editingName) Colors", role: .destructive) {
                if editing == .light { themes.active.light = themes.active.dark } else { themes.active.dark = themes.active.light }
            }
        } message: {
            Text("Useful as a starting point for a single-appearance theme. You can undo with Revert or Reset.")
        }
        .confirmationDialog("Reset all \(editingName.lowercased()) colors to the saved theme?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset \(editingName) Colors", role: .destructive) {
                guard let source = themes.source else { return }
                if editing == .light { themes.active.light = source.light } else { themes.active.dark = source.dark }
            }
        }
    }

    @State private var confirmCopy = false
    @State private var confirmReset = false

    private var editingName: String { editing == .light ? "Light" : "Dark" }
    private var otherName: String { editing == .light ? "Dark" : "Light" }

    private var canResetPalette: Bool {
        guard let source = themes.source else { return false }
        return editing == .light ? source.light != themes.active.light : source.dark != themes.active.dark
    }
}

// MARK: - Extras

private struct ExtrasSection: View {
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        Section("Headings") {
            Toggle("Rule under H1 and H2", isOn: themes.binding(\.elements.headingUnderline))
            Picker("Numbering", selection: themes.binding(\.elements.headingNumbering)) {
                ForEach(Theme.HeadingNumbering.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        Section("Code blocks") {
            Toggle("Syntax colors", isOn: themes.binding(\.elements.codeHighlighting))
            Toggle("Show language", isOn: themes.binding(\.elements.codeShowLanguage))
            Toggle("Wrap long lines", isOn: themes.binding(\.elements.codeWrapLines))
            Toggle("Line numbers", isOn: themes.binding(\.elements.codeLineNumbers))
        }
        Section("Lists and tables") {
            Picker("Bullet", selection: themes.binding(\.elements.listMarker)) {
                ForEach(Theme.ListMarker.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Table borders", selection: themes.binding(\.elements.tableBorders)) {
                ForEach(Theme.TableBorders.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Striped rows", isOn: themes.binding(\.elements.tableStriped))
        }
        Section("Images") {
            Toggle("Rounded corners", isOn: themes.binding(\.elements.imageRounded))
            Toggle("Shadow", isOn: themes.binding(\.elements.imageShadow))
            Toggle("Center standalone images", isOn: themes.binding(\.elements.imageCentered))
        }
        Section("Details") {
            Toggle("Underline links", isOn: themes.binding(\.elements.linkUnderline))
            Toggle("Italic quotes", isOn: themes.binding(\.elements.blockquoteItalic))
            Toggle("Drop cap on first paragraph", isOn: themes.binding(\.elements.dropCap))
            Picker("Horizontal rule", selection: themes.binding(\.elements.ruleStyle)) {
                ForEach(Theme.RuleStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Front matter", selection: themes.binding(\.elements.frontMatter)) {
                ForEach(Theme.FrontMatterStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        }
        Section {
            TextEditor(text: themes.binding(\.customCSS))
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 110)
        } header: {
            Text("Custom CSS")
        } footer: {
            Text("Appended after the theme's stylesheet. Palette colors are available as variables: --mp-bg, --mp-text, --mp-heading, --mp-link, --mp-accent, --mp-muted, --mp-code-bg, --mp-rule.")
        }
    }
}

// MARK: - Controls

struct SettingSlider: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let zeroLabel: String?

    init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
         step: Double, format: String, zeroLabel: String? = nil) {
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.format = format
        self.zeroLabel = zeroLabel
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: Design.Space.s) {
                Slider(value: value, in: range, step: step)
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }

    private var display: String {
        if value.wrappedValue == 0, let zeroLabel { return zeroLabel }
        return String(format: format, value.wrappedValue)
    }
}

struct ColorRow: View {
    let label: String
    let hex: Binding<String>

    init(_ label: String, _ hex: Binding<String>) {
        self.label = label
        self.hex = hex
    }

    var body: some View {
        ColorPicker(label, selection: Binding(
            get: { Color(hex: hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString }
        ), supportsOpacity: false)
    }
}

/// Picker over the font catalog with an "Other…" entry for any installed family.
struct FontFamilyPicker: View {
    let label: String
    let selection: Binding<String>
    let families: [FontCatalog.Family]
    let inheritLabel: String?

    private static let customTag = "\u{0}custom"

    init(_ label: String, selection: Binding<String>, families: [FontCatalog.Family], inheritLabel: String? = nil) {
        self.label = label
        self.selection = selection
        self.families = families
        self.inheritLabel = inheritLabel
    }

    private var isCustom: Bool {
        let id = selection.wrappedValue
        if id.isEmpty && inheritLabel != nil { return false }
        return !families.contains { $0.id == id }
    }

    var body: some View {
        Picker(label, selection: Binding(
            get: { isCustom ? Self.customTag : selection.wrappedValue },
            set: { new in
                if new == Self.customTag {
                    if !isCustom { selection.wrappedValue = "Helvetica Neue " }
                } else {
                    selection.wrappedValue = new
                }
            }
        )) {
            if let inheritLabel {
                Text(inheritLabel).tag("")
                Divider()
            }
            ForEach(families) { family in
                Text(family.name).tag(family.id)
            }
            Divider()
            Text("Other…").tag(Self.customTag)
        }
        if isCustom {
            TextField("Font family name", text: selection)
                .textFieldStyle(.roundedBorder)
        }
    }
}
