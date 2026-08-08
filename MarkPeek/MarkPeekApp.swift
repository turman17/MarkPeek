import SwiftUI
import WebKit

@main
struct MarkPeekApp: App {
    var body: some Scene {
        WindowGroup {
            SettingsView()
                .frame(minWidth: 900, minHeight: 580)
        }
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
                    .tabItem { Text("Presets") }
                TypographyTab(store: store)
                    .tabItem { Text("Typography") }
                LayoutTab(store: store)
                    .tabItem { Text("Layout") }
                ColorsTab(store: store)
                    .tabItem { Text("Colors") }
            }
            .padding(8)
            .frame(minWidth: 400, idealWidth: 420, maxWidth: 500)
            PreviewPane(settings: store.settings, previewDark: $previewDark)
                .frame(minWidth: 400, maxWidth: .infinity)
        }
    }
}

// MARK: - Presets tab

struct PresetsTab: View {
    @ObservedObject var store: SettingsStore
    @State private var namingSheet: NamingSheet?

    struct NamingSheet: Identifiable {
        let id = UUID()
        var title: String
        var name: String
        var action: (String) -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Built-in") {
                    ForEach(MarkdownStyle.allCases, id: \.self) { style in
                        presetRow(
                            name: style.displayName,
                            selected: store.settings.presetName == style.rawValue
                        ) { store.apply(style) }
                    }
                }
                Section("My Presets") {
                    ForEach(store.customPresets) { preset in
                        presetRow(
                            name: preset.name,
                            selected: store.settings.customPresetID == preset.id
                        ) { store.apply(preset) }
                        .contextMenu {
                            Button("Rename…") {
                                namingSheet = NamingSheet(title: "Rename Preset", name: preset.name) {
                                    store.rename(preset, to: $0)
                                }
                            }
                            Button("Delete", role: .destructive) { store.delete(preset) }
                        }
                    }
                    if store.settings.presetName == "custom" {
                        presetRow(name: "Custom (unsaved)", selected: true) {}
                            .foregroundStyle(.secondary)
                    }
                    if store.customPresets.isEmpty && store.settings.presetName != "custom" {
                        Text("No presets yet. Adjust any setting, then save it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    namingSheet = NamingSheet(title: "Save Preset", name: suggestedName()) {
                        store.saveAsNewPreset(named: $0)
                    }
                } label: {
                    Label("Save Current as Preset…", systemImage: "plus")
                }
                Spacer()
                Text("Active: \(store.currentPresetLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .sheet(item: $namingSheet) { sheet in
            PresetNameSheet(title: sheet.title, name: sheet.name) { finalName in
                sheet.action(finalName)
            }
        }
    }

    private func suggestedName() -> String {
        var n = 1
        while store.customPresets.contains(where: { $0.name == "My Preset \(n)" }) { n += 1 }
        return "My Preset \(n)"
    }

    private func presetRow(name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct PresetNameSheet: View {
    let title: String
    @State var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.headline)
            TextField("Preset name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(save)
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
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
                fontPicker("Body font", selection: store.customize(\.bodyFont), fonts: Self.bodyFonts)
                fontPicker("Code font", selection: store.customize(\.codeFont), fonts: Self.codeFonts)
                SettingSlider("Font size", value: store.customize(\.fontSize), in: 10...24, step: 1, format: "%.0f px")
                SettingSlider("Line height", value: store.customize(\.lineHeight), in: 1.2...2.2, step: 0.05, format: "%.2f")
            }
            Section("Headings") {
                Picker("Weight", selection: store.customize(\.headingWeight)) {
                    Text("Regular").tag(400)
                    Text("Medium").tag(500)
                    Text("Semibold").tag(600)
                    Text("Bold").tag(700)
                    Text("Heavy").tag(800)
                }
                Toggle("Underline H1 / H2", isOn: store.customize(\.headingUnderline))
            }
            Section("Blockquotes") {
                Toggle("Italic text", isOn: store.customize(\.blockquoteItalic))
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
                SettingSlider("Content width", value: store.customize(\.maxWidth), in: 0...1200, step: 50,
                              format: "%.0f px", zeroLabel: "Full")
                SettingSlider("Page margin", value: store.customize(\.pagePadding), in: 0...100, step: 5, format: "%.0f px")
                SettingSlider("Paragraph spacing", value: store.customize(\.paragraphSpacing), in: 0...2.5, step: 0.25, format: "%.2f em")
            }
            Section("Code Blocks") {
                SettingSlider("Padding", value: store.customize(\.codeBlockPadding), in: 0...32, step: 2, format: "%.0f px")
                SettingSlider("Corner radius", value: store.customize(\.cornerRadius), in: 0...16, step: 1, format: "%.0f px")
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
                Picker("Dark mode", selection: store.customize(\.appearance)) {
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
            colorRow("Code background", set.appending(path: \.codeBackground))
            colorRow("Code text", set.appending(path: \.codeText))
            colorRow("Blockquote text", set.appending(path: \.blockquoteText))
            colorRow("Blockquote border", set.appending(path: \.blockquoteBorder))
            colorRow("Rules & underlines", set.appending(path: \.rule))
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
        HStack {
            Text(label)
            Slider(value: value, in: range, step: step)
            Text(value.wrappedValue == 0 && zeroLabel != nil ? zeroLabel! : String(format: format, value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Live preview

struct PreviewPane: View {
    let settings: PreviewSettings
    @Binding var previewDark: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Live Preview")
                    .font(.headline)
                Spacer()
                Picker("", selection: $previewDark) {
                    Label("Light", systemImage: "sun.max").tag(false)
                    Label("Dark", systemImage: "moon").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(10)
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
