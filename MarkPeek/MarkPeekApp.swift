import SwiftUI
import WebKit

extension Color {
    /// Brand brown sampled from the app icon — the app's single accent.
    static let brand = Color(.sRGB, red: 0.545, green: 0.373, blue: 0.243)
}

@main
struct MarkPeekApp: App {
    var body: some Scene {
        Window("MarkPeek", id: "main") {
            SettingsView()
                .frame(minWidth: 880, minHeight: 560)
                .tint(.brand)
        }
        .windowResizability(.contentMinSize)
    }
}

// MARK: - Settings store

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: PreviewSettings {
        didSet {
            settings.save()
            autosaveToSelectedPreset()
        }
    }
    @Published var customPresets: [CustomPreset] {
        didSet { PresetLibrary.save(customPresets) }
    }

    init() {
        settings = PreviewSettings.load()
        customPresets = PresetLibrary.load()
    }

    // Edits from individual controls: built-in presets become "custom" (unsaved);
    // edits while a user preset is selected auto-save into that preset.
    func customize<T>(_ keyPath: WritableKeyPath<PreviewSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: {
                self.settings[keyPath: keyPath] = $0
                if self.settings.isBuiltinPreset {
                    self.settings.presetName = "custom"
                }
            }
        )
    }

    private func autosaveToSelectedPreset() {
        guard let id = settings.customPresetID,
              let index = customPresets.firstIndex(where: { $0.id == id }),
              customPresets[index].settings != settings else { return }
        customPresets[index].settings = settings
    }

    var currentPresetLabel: String {
        if let style = MarkdownStyle(rawValue: settings.presetName) { return style.displayName }
        if let id = settings.customPresetID,
           let preset = customPresets.first(where: { $0.id == id }) { return preset.name }
        return "Custom (unsaved)"
    }

    var selectedCustomPreset: CustomPreset? {
        guard let id = settings.customPresetID else { return nil }
        return customPresets.first { $0.id == id }
    }

    func apply(_ style: MarkdownStyle) {
        settings = PreviewSettings.preset(style)
    }

    func apply(_ preset: CustomPreset) {
        var s = preset.settings
        s.presetName = preset.id.uuidString
        settings = s
    }

    func saveAsNewPreset(named name: String) {
        var s = settings
        let preset = CustomPreset(name: name, settings: s)
        s.presetName = preset.id.uuidString
        customPresets.append(CustomPreset(id: preset.id, name: name, settings: s))
        settings = s
    }

    func rename(_ preset: CustomPreset, to name: String) {
        guard let index = customPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        customPresets[index].name = name
    }

    func delete(_ preset: CustomPreset) {
        customPresets.removeAll { $0.id == preset.id }
        if settings.customPresetID == preset.id {
            settings.presetName = "custom"
        }
    }
}

// MARK: - Root view

struct SettingsView: View {
    @StateObject private var store = SettingsStore()
    @State private var previewDark = false

    var body: some View {
        HSplitView {
            TabView {
                PresetsTab(store: store)
                    .tabItem { Label("Presets", systemImage: "square.grid.2x2") }
                TypographyTab(store: store)
                    .tabItem { Label("Typography", systemImage: "textformat") }
                LayoutTab(store: store)
                    .tabItem { Label("Layout", systemImage: "ruler") }
                ColorsTab(store: store)
                    .tabItem { Label("Colors", systemImage: "paintpalette") }
            }
            .padding(.top, 8)
            .frame(minWidth: 400, idealWidth: 430, maxWidth: 520)
            PreviewPane(settings: store.settings, previewDark: $previewDark)
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }
}

// MARK: - Presets tab

private enum PresetRowID: Hashable {
    case builtin(MarkdownStyle)
    case custom(UUID)
    case unsaved
}

struct PresetsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var namingSheet: NamingSheet?

    struct NamingSheet: Identifiable {
        let id = UUID()
        var title: String
        var name: String
        var action: (String) -> Void
    }

    private var selection: Binding<PresetRowID?> {
        Binding(
            get: {
                if let style = MarkdownStyle(rawValue: store.settings.presetName) { return .builtin(style) }
                if let id = store.settings.customPresetID { return .custom(id) }
                return .unsaved
            },
            set: { newValue in
                switch newValue {
                case .builtin(let style): store.apply(style)
                case .custom(let id):
                    if let preset = store.customPresets.first(where: { $0.id == id }) {
                        store.apply(preset)
                    }
                case .unsaved, nil: break
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                Section("Built-in") {
                    ForEach(MarkdownStyle.allCases, id: \.self) { style in
                        Label(style.displayName, systemImage: symbol(for: style))
                            .tag(PresetRowID.builtin(style))
                    }
                }
                Section("My Presets") {
                    ForEach(store.customPresets) { preset in
                        Label(preset.name, systemImage: "paintbrush.pointed")
                            .tag(PresetRowID.custom(preset.id))
                            .contextMenu {
                                Button("Rename…") {
                                    namingSheet = NamingSheet(title: "Rename Preset", name: preset.name) {
                                        store.rename(preset, to: $0)
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(preset) }
                            }
                    }
                    if store.settings.presetName == "custom" {
                        Label("Custom (unsaved)", systemImage: "pencil.circle")
                            .foregroundStyle(.secondary)
                            .tag(PresetRowID.unsaved)
                    }
                    if store.customPresets.isEmpty && store.settings.presetName != "custom" {
                        Label {
                            Text("Adjust any setting, then save it with +")
                        } icon: {
                            Image(systemName: "plus.square.dashed")
                        }
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                    }
                }
            }
            .animation(.snappy, value: store.customPresets)

            Divider()
            HStack(spacing: 2) {
                Button {
                    namingSheet = NamingSheet(title: "Save Preset", name: suggestedName()) {
                        store.saveAsNewPreset(named: $0)
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Save current settings as a new preset")
                .help("Save current settings as a new preset")

                Button {
                    if let preset = store.selectedCustomPreset { store.delete(preset) }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .disabled(store.selectedCustomPreset == nil)
                .accessibilityLabel("Delete selected preset")
                .help("Delete the selected preset")

                Spacer()
                Text(store.currentPresetLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Active preset: \(store.currentPresetLabel)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .sheet(item: $namingSheet) { sheet in
            PresetNameSheet(title: sheet.title, name: sheet.name) { finalName in
                sheet.action(finalName)
            }
        }
    }

    private func symbol(for style: MarkdownStyle) -> String {
        switch style {
        case .modern: "doc.richtext"
        case .serif: "text.book.closed"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .plain: "doc.plaintext"
        }
    }

    private func suggestedName() -> String {
        var n = 1
        while store.customPresets.contains(where: { $0.name == "My Preset \(n)" }) { n += 1 }
        return "My Preset \(n)"
    }
}

struct PresetNameSheet: View {
    let title: String
    @State var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "paintbrush.pointed")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(save)
            HStack(spacing: 10) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(24)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}

// MARK: - Typography tab

struct TypographyTab: View {
    @ObservedObject var store: SettingsStore

    private static let bodyFonts = [
        "-apple-system", "Helvetica Neue", "Helvetica", "Avenir Next", "Avenir",
        "Georgia", "Times New Roman", "Palatino", "Charter", "Iowan Old Style",
        "Hoefler Text", "Seravek", "Menlo",
    ]
    private static let codeFonts = [
        "SF Mono", "Menlo", "Monaco", "Courier", "Courier New", "Andale Mono",
    ]

    var body: some View {
        Form {
            Section("Fonts") {
                fontPicker("Body Font", selection: store.customize(\.bodyFont), fonts: Self.bodyFonts)
                fontPicker("Code Font", selection: store.customize(\.codeFont), fonts: Self.codeFonts)
                SettingSlider("Size", value: store.customize(\.fontSize), in: 10...24, step: 1, format: "%.0f px")
                SettingSlider("Line Height", value: store.customize(\.lineHeight), in: 1.2...2.2, step: 0.05, format: "%.2f")
            }
            Section("Headings") {
                Picker("Weight", selection: store.customize(\.headingWeight)) {
                    Text("Regular").tag(400)
                    Text("Medium").tag(500)
                    Text("Semibold").tag(600)
                    Text("Bold").tag(700)
                    Text("Heavy").tag(800)
                }
                Toggle("Underline H1 and H2", isOn: store.customize(\.headingUnderline))
                    .toggleStyle(.switch)
            }
            Section("Blockquotes") {
                Toggle("Italic Text", isOn: store.customize(\.blockquoteItalic))
                    .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
    }

    private func fontPicker(_ label: String, selection: Binding<String>, fonts: [String]) -> some View {
        Picker(label, selection: selection) {
            ForEach(fonts, id: \.self) { name in
                Text(name == "-apple-system" ? "System (San Francisco)" : name).tag(name)
            }
            if !fonts.contains(selection.wrappedValue) {
                Text(selection.wrappedValue).tag(selection.wrappedValue)
            }
        }
    }
}

// MARK: - Layout tab

struct LayoutTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Page") {
                SettingSlider("Content Width", value: store.customize(\.maxWidth), in: 0...1200, step: 50,
                              format: "%.0f px", zeroLabel: "Full")
                SettingSlider("Margin", value: store.customize(\.pagePadding), in: 0...100, step: 5, format: "%.0f px")
                SettingSlider("Paragraph Spacing", value: store.customize(\.paragraphSpacing), in: 0...2.5, step: 0.25, format: "%.2f em")
            }
            Section("Code Blocks") {
                SettingSlider("Padding", value: store.customize(\.codeBlockPadding), in: 0...32, step: 2, format: "%.0f px")
                SettingSlider("Corner Radius", value: store.customize(\.cornerRadius), in: 0...16, step: 1, format: "%.0f px")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Colors tab

struct ColorsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Previews Follow", selection: store.customize(\.appearance)) {
                    ForEach(PreviewSettings.Appearance.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            colorSection("Light Colors", set: \.light)
            colorSection("Dark Colors", set: \.dark)
        }
        .formStyle(.grouped)
    }

    private func colorSection(_ title: String, set: WritableKeyPath<PreviewSettings, PreviewSettings.ColorSet>) -> some View {
        Section(title) {
            colorRow("Background", set.appending(path: \.background))
            colorRow("Text", set.appending(path: \.text))
            colorRow("Headings", set.appending(path: \.heading))
            colorRow("Links", set.appending(path: \.link))
            colorRow("Code Background", set.appending(path: \.codeBackground))
            colorRow("Code Text", set.appending(path: \.codeText))
            colorRow("Blockquote Text", set.appending(path: \.blockquoteText))
            colorRow("Blockquote Border", set.appending(path: \.blockquoteBorder))
            colorRow("Rules & Underlines", set.appending(path: \.rule))
        }
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<PreviewSettings, String>) -> some View {
        let hex = store.customize(keyPath)
        return ColorPicker(label, selection: Binding(
            get: { Color(hex: hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexString }
        ), supportsOpacity: false)
    }
}

// MARK: - Shared controls

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
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step)
                Text(value.wrappedValue == 0 && zeroLabel != nil ? zeroLabel! : String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .frame(maxWidth: 240)
        }
    }
}

// MARK: - Live preview

struct PreviewPane: View {
    let settings: PreviewSettings
    @Binding var previewDark: Bool
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Preview")
                    .font(.headline)
                Spacer()
                Picker("Preview appearance", selection: $previewDark) {
                    Label("Light", systemImage: "sun.max").tag(false)
                    Label("Dark", systemImage: "moon").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Setup help")
                .help("How to use MarkPeek")
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    SetupHelp()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            MarkdownWebView(
                html: MarkdownRenderer.html(from: Self.sampleMarkdown, settings: settings),
                dark: previewDark
            )
        }
    }

    static let sampleMarkdown = """
    # Heading One
    Regular paragraph with **bold**, *italic*, `inline code`, and a [link](https://example.com).

    ## Heading Two
    > A blockquote to check border and text colors.

    ### Heading Three
    - Unordered item
    - Another item

    1. Ordered item
    2. Another item

    ```
    func hello() {
        print("Code block")
    }
    ```

    ---

    Final paragraph after a horizontal rule.
    """
}

struct SetupHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Select any .md file in Finder", systemImage: "1.circle")
            Label("Press Space to Quick Look it", systemImage: "2.circle")
            Label("It renders with the active preset", systemImage: "3.circle")
            Divider()
            Text("Previews not styled?")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Quick Look Extension Settings…") {
                let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
                NSWorkspace.shared.open(url)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let dark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastHTML = ""
    }
}

// MARK: - Color <-> hex

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255))
        )
    }
}
