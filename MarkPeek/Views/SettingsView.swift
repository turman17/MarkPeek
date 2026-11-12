import SwiftUI

/// App preferences (⌘,). Document styling lives in the theme inspector.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ThemeSettings()
                .tabItem { Label("Themes", systemImage: "paintpalette") }
            ExportSettings()
                .tabItem { Label("Export", systemImage: "doc.richtext") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var updater = Updater.shared
    @StateObject private var setup = SetupStatus()
    @AppStorage("reopenLastDocument") private var reopenLastDocument = true

    var body: some View {
        Form {
            Section("Documents") {
                Toggle("Save automatically while editing", isOn: $document.autoSave)
                Toggle("Reopen the last document at launch", isOn: $reopenLastDocument)
                LabeledContent("Markdown files") {
                    if setup.isDefaultApp {
                        Label("Open in MarkPeek", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Open in MarkPeek by Default") { setup.makeDefault() }
                    }
                }
            }
            Section {
                ForEach(setup.grantedFolders, id: \.self) { path in
                    HStack {
                        Label(SetupStatus.abbreviated(path), systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove") { setup.removeFolder(path) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Allow a Folder…") { setup.requestFolder() }
            } header: {
                Text("Images")
            } footer: {
                Text("MarkPeek can read a document you open, but not the images beside it, until you allow the folder. Each grant covers its subfolders.")
            }
            Section {
                LabeledContent("Finder previews") {
                    Button("Open Extension Settings…") { openQuickLookSettings() }
                }
            } footer: {
                Text("Select any Markdown file in Finder and press Space. If the preview shows raw text, enable MarkPeek under Quick Look in System Settings.")
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                LabeledContent("Version \(updater.currentVersion)") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(updater.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .onAppear { setup.refresh() }
    }
}

func openQuickLookSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.quicklook.preview")!
    NSWorkspace.shared.open(url)
}

private struct ThemeSettings: View {
    @ObservedObject private var themes = ThemeStore.shared
    @State private var isImporting = false
    @State private var exporting: Theme?

    var body: some View {
        Form {
            Section {
                if themes.userThemes.isEmpty {
                    Text("No custom themes yet. Customize any theme in the inspector and choose Save As.")
                        .foregroundStyle(.secondary)
                }
                ForEach(themes.userThemes) { stored in
                    HStack {
                        Label(stored.theme.name, systemImage: "paintbrush.pointed")
                        if themes.isActive(stored.id) {
                            Text("Active").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Export…") { exporting = stored.theme }
                        Button("Delete", role: .destructive) { themes.delete(stored.id) }
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("My Themes")
            } footer: {
                Text("Themes are .markpeektheme files. Share one by exporting it; install one by opening it, dropping it on the window, or copying it into the themes folder.")
            }
            Section {
                HStack {
                    Button("Import Theme…") { isImporting = true }
                    Button("Show Themes Folder in Finder") { themes.revealThemesFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [ThemeStore.themeType, .json]) { result in
            if case .success(let url) = result { themes.importTheme(from: url) }
        }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting.map(ThemeFile.init),
            contentType: ThemeStore.themeType,
            defaultFilename: exporting?.name
        ) { _ in }
    }
}

private struct ExportSettings: View {
    @AppStorage("export.paper") private var paper: PDFExporter.Paper = .a4
    @AppStorage("export.orientation") private var orientation: PDFExporter.Orientation = .portrait
    @AppStorage("export.margins") private var margins: PDFExporter.Margins = .normal
    @AppStorage("export.layout") private var layout: PDFExporter.PageLayout = .pages
    @AppStorage("export.appearance") private var appearance: PDFExporter.Appearance = .theme
    @AppStorage("export.openAfter") private var openAfter = true

    var body: some View {
        Form {
            Section("PDF defaults") {
                Picker("Paper", selection: $paper) {
                    ForEach(PDFExporter.Paper.allCases) { Text($0.name).tag($0) }
                }
                Picker("Orientation", selection: $orientation) {
                    ForEach(PDFExporter.Orientation.allCases) { Text($0.name).tag($0) }
                }
                Picker("Margins", selection: $margins) {
                    ForEach(PDFExporter.Margins.allCases) { Text($0.name).tag($0) }
                }
                Picker("Layout", selection: $layout) {
                    ForEach(PDFExporter.PageLayout.allCases) { Text($0.name).tag($0) }
                }
                Picker("Appearance", selection: $appearance) {
                    ForEach(PDFExporter.Appearance.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Open in Preview when done", isOn: $openAfter)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}
