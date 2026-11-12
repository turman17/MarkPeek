import SwiftUI

/// Theme builder: start from any theme, set the basics, then fine-tune in
/// the inspector. Creates a `.markpeektheme` file in My Themes.
struct NewThemeSheet: View {
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState
    @Environment(\.dismiss) private var dismiss

    @State private var name = "My Theme"
    @State private var author = NSFullUserName()
    @State private var baseID: UUID = Theme.modern.id
    @State private var appearance: Theme.Appearance = .system
    @State private var bodyFont = "-apple-system"
    @State private var codeFont = "SF Mono"
    @State private var accentLight = Color(hex: "#0969DA")
    @State private var accentDark = Color(hex: "#6CB2FF")
    @State private var fontSize: Double = 16
    @State private var maxWidth: Double = 700
    @State private var openInspector = true

    private var base: Theme { themes.theme(id: baseID) ?? .modern }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Theme") {
                    TextField("Name", text: $name)
                    TextField("Author", text: $author)
                    Picker("Start from", selection: $baseID) {
                        Section("Built-in") {
                            ForEach(themes.builtInThemes) { Text($0.name).tag($0.id) }
                        }
                        if !themes.userThemes.isEmpty {
                            Section("My Themes") {
                                ForEach(themes.userThemes) { Text($0.theme.name).tag($0.id) }
                            }
                        }
                    }
                    .onChange(of: baseID) { _, _ in loadFromBase() }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Theme.Appearance.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Basics") {
                    FontFamilyPicker("Body font", selection: $bodyFont, families: FontCatalog.body)
                    FontFamilyPicker("Code font", selection: $codeFont, families: FontCatalog.code)
                    SettingSlider("Text size", value: $fontSize, in: 11...24, step: 1, format: "%.0f px")
                    SettingSlider("Content width", value: $maxWidth, in: 0...1200, step: 20, format: "%.0f px", zeroLabel: "Full")
                    ColorPicker("Accent (light)", selection: $accentLight, supportsOpacity: false)
                    ColorPicker("Accent (dark)", selection: $accentDark, supportsOpacity: false)
                }
                Section {
                    Toggle("Open the inspector to fine-tune", isOn: $openInspector)
                } footer: {
                    Text("The theme is saved as a .markpeektheme JSON file in My Themes. Every other setting keeps the values of the theme you start from.")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Theme", action: create)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(Design.Space.l)
        }
        .frame(width: 480, height: 560)
        .onAppear(perform: loadFromBase)
    }

    private func loadFromBase() {
        let t = base
        appearance = t.appearance
        bodyFont = t.typography.bodyFont
        codeFont = t.typography.codeFont
        fontSize = t.typography.fontSize
        maxWidth = t.layout.maxWidth
        accentLight = Color(hex: t.light.accent)
        accentDark = Color(hex: t.dark.accent)
    }

    private func create() {
        var t = base
        t.id = UUID()
        t.name = name.trimmingCharacters(in: .whitespaces)
        t.author = author
        t.appearance = appearance
        t.typography.bodyFont = bodyFont
        t.typography.codeFont = codeFont
        t.typography.fontSize = fontSize
        t.layout.maxWidth = maxWidth
        t.light.accent = accentLight.hexString
        t.light.link = accentLight.hexString
        t.dark.accent = accentDark.hexString
        t.dark.link = accentDark.hexString
        themes.create(t)
        if openInspector { ui.showInspector = true }
        dismiss()
    }
}
