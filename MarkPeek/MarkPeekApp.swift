import SwiftUI
import WebKit
import UniformTypeIdentifiers

extension Color {
    /// Brand brown sampled from the app icon — the app's single accent.
    static let brand = Color(.sRGB, red: 0.545, green: 0.373, blue: 0.243)
}

/// Liquid-glass surface: blurs whatever is behind the window (the desktop),
/// like the translucent chrome in Apple's latest OS design.
struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

// MARK: - App

@main
struct MarkPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = ReaderModel.shared

    var body: some Scene {
        Window("MarkPeek", id: "main") {
            MainView()
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { ReaderModel.shared.isImporting = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { ReaderModel.shared.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.hasUnsavedChanges)
            }
        }
    }
}

// "Open With MarkPeek" / double-click routing from Finder
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            Task { @MainActor in ReaderModel.shared.open(url) }
        }
    }
}

// MARK: - Reader model

struct RecentFile: Codable, Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let bookmark: Data
}

@MainActor
final class ReaderModel: ObservableObject {
    static let shared = ReaderModel()

    enum ViewMode: String, CaseIterable {
        case preview, split, edit
    }

    @Published var fileURL: URL?
    @Published var markdown = ""
    @Published var draft = "" {
        didSet { scheduleAutoSave() }
    }
    @Published var mode: ViewMode = .preview
    @Published var isImporting = false
    @Published var loadError: String?
    @Published var recents: [RecentFile] = ReaderModel.loadRecents()
    @Published var autoSave = UserDefaults.standard.bool(forKey: "autoSave") {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: "autoSave")
            if autoSave { save() }
        }
    }

    /// URL currently holding a security-scope access grant (kept while the file is open so edits can be saved).
    private var accessedURL: URL?
    private var autoSaveTask: Task<Void, Never>?

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        guard autoSave, hasUnsavedChanges else { return }
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
    }

    var hasUnsavedChanges: Bool { fileURL != nil && draft != markdown }

    static let markdownExtensions = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static var markdownTypes: [UTType] {
        markdownExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    func open(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url.startAccessingSecurityScopedResource() ? url : nil
        do {
            markdown = try Self.readText(at: url)
            draft = markdown
            fileURL = url
            loadError = nil
            noteRecent(url)
        } catch {
            loadError = "Couldn't read \(url.lastPathComponent)"
        }
    }

    func save() {
        guard let url = fileURL, hasUnsavedChanges else { return }
        do {
            try draft.write(to: url, atomically: true, encoding: .utf8)
            markdown = draft
        } catch {
            loadError = "Couldn't save \(url.lastPathComponent). The file may be read-only."
        }
    }

    func openRecent(_ recent: RecentFile) {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: recent.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            recents.removeAll { $0.id == recent.id }
            saveRecents()
            loadError = "\(recent.name) is no longer available"
            return
        }
        open(url)
    }

    func removeRecent(_ recent: RecentFile) {
        recents.removeAll { $0.id == recent.id }
        saveRecents()
    }

    private func noteRecent(_ url: URL) {
        // Dropped files may not allow security-scoped bookmarks; skip those.
        guard let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let entry = RecentFile(name: url.lastPathComponent, path: url.path, bookmark: bookmark)
        recents.removeAll { $0.path == entry.path }
        recents.insert(entry, at: 0)
        if recents.count > 8 { recents.removeLast(recents.count - 8) }
        saveRecents()
    }

    private static let recentsKey = "recentFiles"

    private static func loadRecents() -> [RecentFile] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let recents = try? JSONDecoder().decode([RecentFile].self, from: data) else { return [] }
        return recents
    }

    private func saveRecents() {
        guard let data = try? JSONEncoder().encode(recents) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    static func readText(at url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}

// MARK: - Main window: sidebar + detail

enum SidebarItem: String, CaseIterable, Identifiable {
    case reader, presets, typography, layout, colors, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .reader: "Reader"
        case .presets: "Presets"
        case .typography: "Typography"
        case .layout: "Layout"
        case .colors: "Colors"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .reader: "doc.richtext"
        case .presets: "square.grid.2x2"
        case .typography: "textformat"
        case .layout: "ruler"
        case .colors: "paintpalette"
        case .about: "info.circle"
        }
    }
}

struct MainView: View {
    @State private var selection: SidebarItem = .reader
    @ObservedObject private var model = ReaderModel.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var previewDark = false
    @State private var showingHelp = false
    @AppStorage("hasCompletedOnboarding") private var hasOnboarded = false
    @State private var showOnboarding = false

    var body: some View {
        mainContent
            .onAppear {
                if !hasOnboarded { showOnboarding = true }
            }
            .sheet(isPresented: $showOnboarding, onDismiss: { hasOnboarded = true }) {
                OnboardingView()
            }
    }

    private var mainContent: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 165, ideal: 180, max: 220)
        } detail: {
            switch selection {
            case .reader:
                ReaderView()
            case .presets:
                settingsDetail("Presets") { PresetsTab(store: store) }
            case .typography:
                settingsDetail("Typography") { TypographyTab(store: store) }
            case .layout:
                settingsDetail("Layout") { LayoutTab(store: store) }
            case .colors:
                settingsDetail("Colors") { ColorsTab(store: store) }
            case .about:
                AboutView()
            }
        }
    }

    private func settingsDetail<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        HSplitView {
            content()
                .frame(minWidth: 300, idealWidth: 390, maxWidth: 470)
            LivePreview(
                markdown: sampleMarkdown,
                settings: store.settings,
                appearance: NSAppearance(named: previewDark ? .darkAqua : .aqua)
            )
            .frame(minWidth: 260, maxWidth: .infinity)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                Picker("Preview appearance", selection: $previewDark) {
                    Label("Light", systemImage: "sun.max").tag(false)
                    Label("Dark", systemImage: "moon").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Preview appearance")

                Button {
                    showingHelp.toggle()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityLabel("Setup help")
                .help("How to use MarkPeek")
                .popover(isPresented: $showingHelp, arrowEdge: .bottom) {
                    SetupHelp()
                }
            }
        }
    }
}

let sampleMarkdown = """
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

// MARK: - Reader

struct ReaderView: View {
    @ObservedObject private var model = ReaderModel.shared
    @ObservedObject private var store = SettingsStore.shared
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if model.fileURL == nil {
                DropBrowseView()
            } else {
                switch model.mode {
                case .preview:
                    LivePreview(markdown: model.draft, settings: store.settings, appearance: readerAppearance)
                case .edit:
                    EditorView()
                case .split:
                    HSplitView {
                        EditorView()
                            .frame(minWidth: 280)
                        LivePreview(markdown: model.draft, settings: store.settings, appearance: readerAppearance)
                            .frame(minWidth: 300)
                    }
                }
            }
        }
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .animation(.snappy, value: isDropTargeted)
        .navigationTitle(model.fileURL?.lastPathComponent ?? "MarkPeek")
        .toolbar {
            ToolbarItemGroup {
                if model.fileURL != nil {
                    Picker("Mode", selection: $model.mode) {
                        Label("Preview", systemImage: "eye").tag(ReaderModel.ViewMode.preview)
                        Label("Split", systemImage: "rectangle.split.2x1").tag(ReaderModel.ViewMode.split)
                        Label("Edit", systemImage: "pencil").tag(ReaderModel.ViewMode.edit)
                    }
                    .pickerStyle(.segmented)
                    .help("Preview, edit, or both side by side")

                    Button {
                        model.save()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!model.hasUnsavedChanges)
                    .help("Save changes (⌘S)")
                }

                PresetMenu(store: store)

                Button {
                    model.isImporting = true
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .help("Open a Markdown file (⌘O)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: ReaderModel.isMarkdown) else { return false }
            model.open(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $model.isImporting,
            allowedContentTypes: ReaderModel.markdownTypes
        ) { result in
            if case .success(let url) = result {
                model.open(url)
            }
        }
        .alert("Something Went Wrong", isPresented: .init(
            get: { model.loadError != nil },
            set: { if !$0 { model.loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
        }
    }

    private var readerAppearance: NSAppearance? {
        switch store.settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// Rendered preview that re-renders as the markdown or settings change,
/// debounced so typing in split mode doesn't reload the web view per keystroke.
struct LivePreview: View {
    let markdown: String
    let settings: PreviewSettings
    let appearance: NSAppearance?
    @State private var html = ""

    private struct RenderKey: Hashable {
        let markdown: String
        let settings: PreviewSettings
    }

    var body: some View {
        ZStack {
            Glass()
            MarkdownWebView(html: html, appearance: appearance)
        }
        .task(id: RenderKey(markdown: markdown, settings: settings)) {
            if !html.isEmpty {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }
            }
            html = MarkdownRenderer.html(from: markdown, settings: settings, pageCard: true)
        }
    }
}

// MARK: - Editor

struct EditorView: View {
    @ObservedObject private var model = ReaderModel.shared

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.draft)
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(3)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack {
                if model.hasUnsavedChanges {
                    Circle().fill(Color.brand).frame(width: 7, height: 7)
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("Auto Save", isOn: $model.autoSave)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Save automatically shortly after you stop typing")
                Text("\(model.draft.count) characters")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }
}

// MARK: - Drop / browse zone (FinderConvert style)

struct DropBrowseView: View {
    @ObservedObject private var model = ReaderModel.shared

    var body: some View {
        VStack(spacing: 18) {
            Button {
                model.isImporting = true
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color.brand)
                    Text("Drop a Markdown file here or click to browse")
                        .font(.system(size: 15, weight: .semibold))
                    Text(".md · .markdown · .mdown · .mkd · .mkdn")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if !model.recents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recents")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(model.recents.prefix(5)) { recent in
                        Button {
                            model.openRecent(recent)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(Color.brand)
                                Text(recent.name)
                                    .fontWeight(.medium)
                                Text((recent.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                        .contextMenu {
                            Button("Remove from Recents") { model.removeRecent(recent) }
                        }
                    }
                }
            }

            Text("Tip: press Space on any .md file in Finder for an instant Quick Look preview.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Glass())
    }
}

/// Shown only while a drag hovers over the window.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.brand, lineWidth: 3)
                .padding(10)
            Label("Drop to Open", systemImage: "arrow.down.doc.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - About

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
            Text("MarkPeek")
                .font(.system(size: 26, weight: .bold))
            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)
            Text("Styled Markdown everywhere: press Space in Finder for a Quick Look preview, or read and edit right here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 4)
            HStack(spacing: 10) {
                Button("Quick Look Extension Settings…") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Glass())
        .navigationTitle("About")
    }
}

// MARK: - Preset menu (toolbar pill)

struct PresetMenu: View {
    @ObservedObject var store: SettingsStore

    private var selection: Binding<String> {
        Binding(
            get: { store.settings.presetName },
            set: { raw in
                if let style = MarkdownStyle(rawValue: raw) {
                    store.apply(style)
                } else if let id = UUID(uuidString: raw),
                          let preset = store.customPresets.first(where: { $0.id == id }) {
                    store.apply(preset)
                }
            }
        )
    }

    var body: some View {
        Menu {
            Picker("Style", selection: selection) {
                ForEach(MarkdownStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            .pickerStyle(.inline)
            if !store.customPresets.isEmpty {
                Picker("My Presets", selection: selection) {
                    ForEach(store.customPresets) { preset in
                        Text(preset.name).tag(preset.id.uuidString)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(store.currentPresetLabel, systemImage: "paintbrush.pointed")
        }
        .help("Reading style")
    }
}

// MARK: - Settings store

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

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
        .scrollContentBackground(.hidden)
        .background(Glass())
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
        .scrollContentBackground(.hidden)
        .background(Glass())
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
        .scrollContentBackground(.hidden)
        .background(Glass())
    }
}

// MARK: - Colors tab

struct ColorsTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Previews Follow") {
                    Picker("Previews Follow", selection: store.customize(\.appearance)) {
                        ForEach(PreviewSettings.Appearance.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            colorSection("Light Colors", set: \.light)
            colorSection("Dark Colors", set: \.dark)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Glass())
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

// MARK: - Onboarding (first launch)

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = SettingsStore.shared
    @State private var step = 0

    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: quickLook
                default: styles
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.brand : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 14)

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation(.snappy) { step -= 1 } }
                }
                Spacer()
                Button(step == lastStep ? "Get Started" : "Continue") {
                    if step == lastStep {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { step += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(width: 500, height: 440)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 100, height: 100)
                .shadow(color: .black.opacity(0.18), radius: 9, y: 4)
            Text("Welcome to MarkPeek")
                .font(.title.bold())
            Text("Beautiful Markdown, everywhere on your Mac — in Finder previews and right here in the app.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var quickLook: some View {
        VStack(spacing: 14) {
            Spacer()
            HStack(spacing: 8) {
                Text("space")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.tertiary))
            }
            Text("Press Space in Finder")
                .font(.title2.bold())
            Text("Select any .md file and press Space — Quick Look shows it styled instead of raw text. Nothing to launch, ever.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Enable the Quick Look Extension…") {
                let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
                NSWorkspace.shared.open(url)
            }
            .padding(.top, 2)
            Text("Only needed if previews still look plain — most Macs enable it automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var styles: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.brand)
            Text("Pick a starting style")
                .font(.title2.bold())
            Picker("Style", selection: Binding(
                get: { MarkdownStyle(rawValue: store.settings.presetName) ?? .modern },
                set: { store.apply($0) }
            )) {
                ForEach(MarkdownStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)
            Text("Every font, color, and spacing is adjustable later — and you can save your own presets. Previews everywhere follow whatever style is active.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

// MARK: - Setup help

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

// MARK: - Web view

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = appearance
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""

        // Open tapped links in the default browser instead of navigating the reader
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
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
