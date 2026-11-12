import SwiftUI
import UniformTypeIdentifiers

/// Sidebar (documents + themes) · document · theme inspector.
struct MainWindow: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState
    @AppStorage("hasCompletedOnboarding") private var hasOnboarded = false
    @AppStorage("reopenLastDocument") private var reopenLastDocument = true
    @State private var isDropTargeted = false
    @State private var printError: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $ui.sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            ReaderView()
                .inspector(isPresented: $ui.showInspector) {
                    ThemeInspector()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
                .toolbar { toolbarContent }
        }
        .navigationTitle(document.title)
        .navigationSubtitle(subtitle)
        .overlay {
            if isDropTargeted { DropOverlay() }
        }
        .animation(.snappy, value: isDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(isPresented: $document.isImporting, allowedContentTypes: DocumentModel.markdownTypes) { result in
            if case .success(let url) = result { document.open(url) }
        }
        .fileImporter(isPresented: $ui.isImportingTheme, allowedContentTypes: [ThemeStore.themeType, .json]) { result in
            if case .success(let url) = result { themes.importTheme(from: url) }
        }
        .fileExporter(
            isPresented: Binding(get: { ui.exportTheme != nil }, set: { if !$0 { ui.exportTheme = nil } }),
            document: ui.exportTheme.map(ThemeFile.init),
            contentType: ThemeStore.themeType,
            defaultFilename: ui.exportTheme?.name
        ) { _ in }
        .sheet(isPresented: $ui.showExport) {
            ExportSheet()
        }
        .sheet(isPresented: $ui.showNewTheme) {
            NewThemeSheet()
        }
        .sheet(isPresented: $ui.showSaveTheme) {
            NameSheet(title: "Save as New Theme", prompt: "Theme name", name: suggestedThemeName(), action: "Save") { name in
                themes.saveActiveAsNewTheme(named: name)
            }
        }
        .sheet(isPresented: $ui.showOnboarding, onDismiss: { hasOnboarded = true }) {
            OnboardingView()
        }
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(document.errorMessage ?? themes.errorMessage ?? printError ?? "")
        }
        .onAppear {
            if !hasOnboarded { ui.showOnboarding = true }
            if reopenLastDocument { document.reopenLastDocument() }
        }
        .onChange(of: ui.requestPrint) { _, requested in
            guard requested else { return }
            ui.requestPrint = false
            Task { await printDocument() }
        }
        .onChange(of: ui.requestQuickPDF) { _, requested in
            guard requested else { return }
            ui.requestQuickPDF = false
            Task { await quickPDF() }
        }
        .onChange(of: ui.requestHTMLExport) { _, requested in
            guard requested else { return }
            ui.requestHTMLExport = false
            HTMLExporter.export(document: document, theme: themes.active)
        }
        .onChange(of: ui.requestFind) { _, requested in
            guard requested else { return }
            ui.requestFind = false
            if document.mode == .edit || ui.focusMode {
                ui.showEditorFind = true
            } else {
                ui.showFind = true
            }
        }
    }

    private var subtitle: String {
        guard document.hasDocument else { return "" }
        return document.hasUnsavedChanges ? "Edited" : ""
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if document.hasDocument {
                Picker("View", selection: $document.mode) {
                    ForEach(DocumentModel.ViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Preview, edit, or both side by side (⌘1, ⌘2, ⌘3)")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ThemePickerMenuContent()
            } label: {
                Label(themes.activeLabel, systemImage: "paintpalette")
                    .labelStyle(.titleAndIcon)
            }
            .help("Switch theme")

            Button {
                ui.showExport = true
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .disabled(!document.hasDocument)
            .help("Export as PDF (⇧⌘E)")

            Button {
                document.isImporting = true
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open a Markdown file (⌘O)")

            Button {
                ui.showInspector.toggle()
            } label: {
                Label("Theme Inspector", systemImage: "slider.horizontal.3")
            }
            .help("Customize the active theme (⌥⌘I)")
        }
        ToolbarItem(placement: .navigation) {
            if document.hasDocument && ui.focusMode {
                Button("Exit Focus") { ui.toggleFocusMode() }
            }
        }
    }

    // MARK: Actions

    private func handleDrop(_ urls: [URL]) -> Bool {
        var handled = false
        for url in urls {
            if url.pathExtension.lowercased() == Theme.fileExtension {
                themes.importTheme(from: url)
                handled = true
            } else if DocumentModel.isMarkdown(url), !handled {
                document.open(url)
                handled = true
            }
        }
        return handled
    }

    private func suggestedThemeName() -> String {
        let base = themes.activeLabel == "Custom" ? "My Theme" : themes.activeLabel
        let taken = Set((themes.builtInThemes + themes.userThemes.map(\.theme)).map(\.name))
        var n = 2
        var candidate = "\(base) Custom"
        while taken.contains(candidate) { candidate = "\(base) Custom \(n)"; n += 1 }
        return candidate
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { document.errorMessage != nil || themes.errorMessage != nil || printError != nil },
            set: { if !$0 { document.errorMessage = nil; themes.errorMessage = nil; printError = nil } }
        )
    }

    private func quickPDF() async {
        guard document.hasDocument else { return }
        let defaults = UserDefaults.standard
        var options = PDFExporter.Options()
        options.paper = PDFExporter.Paper(rawValue: defaults.string(forKey: "export.paper") ?? "") ?? .a4
        options.orientation = PDFExporter.Orientation(rawValue: defaults.string(forKey: "export.orientation") ?? "") ?? .portrait
        options.margins = PDFExporter.Margins(rawValue: defaults.string(forKey: "export.margins") ?? "") ?? .normal
        options.layout = PDFExporter.PageLayout(rawValue: defaults.string(forKey: "export.layout") ?? "") ?? .pages
        options.appearance = PDFExporter.Appearance(rawValue: defaults.string(forKey: "export.appearance") ?? "") ?? .theme
        options.pageNumbers = defaults.object(forKey: "export.pageNumbers") as? Bool ?? true
        options.headerTitle = defaults.bool(forKey: "export.headerTitle")
        do {
            try await PDFExporter.exportNextToFile(document: document, theme: themes.active, options: options)
        } catch {
            printError = error.localizedDescription
        }
    }

    private func printDocument() async {
        guard document.hasDocument, let window = NSApp.keyWindow else { return }
        let scheme = PDFExporter.resolvedScheme(for: themes.active, preferred: nil)
        let features = MarkdownRenderer.features(of: document.draft)
        let html = MarkdownRenderer.document(
            markdown: document.draft, theme: themes.active,
            options: RenderOptions(surface: .print, colorScheme: scheme, imageResolver: document.imageResolver,
                                   scripts: ScriptLibrary.scripts(for: features, scheme: scheme)))
        do {
            try await PDFExporter.print(html: html, baseURL: document.folderURL, scheme: scheme, in: window)
        } catch {
            printError = error.localizedDescription
        }
    }
}

/// Shown while a drag hovers over the window.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: Design.Radius.l)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .padding(10)
            Label("Drop to Open", systemImage: "arrow.down.doc.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Design.Radius.m))
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

/// Small sheet that asks for a name (new theme, rename).
struct NameSheet: View {
    let title: String
    let prompt: String
    @State var name: String
    let action: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.m) {
            Text(title).font(.headline)
            TextField(prompt, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, Design.Space.xs)
        }
        .padding(Design.Space.xl)
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
        dismiss()
    }
}

/// Wraps a theme for the system export panel.
struct ThemeFile: FileDocument {
    static var readableContentTypes: [UTType] { [ThemeStore.themeType, .json] }
    var theme: Theme

    init(theme: Theme) { self.theme = theme }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        theme = try Theme.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try theme.encoded())
    }
}
