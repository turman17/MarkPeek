import SwiftUI

@main
struct MarkPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var themes = ThemeStore.shared
    @ObservedObject private var updater = Updater.shared
    @StateObject private var ui = WindowState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("MarkPeek", id: "main") {
            MainWindow()
                .environmentObject(ui)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(updater.isBusy)
            }
            CommandGroup(after: .help) {
                Button("Theme Guide") { openWindow(id: GuideView.windowID) }
                    .keyboardShortcut("?", modifiers: [.command, .shift])
                Button("Welcome Tour…") { ui.showOnboarding = true }
            }
            fileCommands
            editCommands
            viewCommands
            themeCommands
        }

        Window("Theme Guide", id: GuideView.windowID) {
            GuideView()
        }
        .defaultSize(width: 820, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }

    // MARK: File

    @CommandsBuilder
    private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { document.isImporting = true }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(document.recents) { recent in
                    Button(recent.name) { document.openRecent(recent) }
                }
                if !document.recents.isEmpty {
                    Divider()
                    Button("Clear Menu") { document.clearRecents() }
                }
            }
            Button("Close Document") { document.close() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!document.hasDocument)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { document.save() }
                .keyboardShortcut("s")
                .disabled(!document.hasUnsavedChanges)
            Divider()
            Button("Export as PDF…") { ui.showExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!document.hasDocument)
            Button("Export PDF Next to File") { ui.requestQuickPDF = true }
                .keyboardShortcut("e", modifiers: [.command, .shift, .option])
                .disabled(!document.hasDocument)
            Button("Export as HTML…") { ui.requestHTMLExport = true }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(!document.hasDocument)
            Divider()
            Button("Reveal in Finder") { document.revealInFinder() }
                .disabled(!document.hasDocument)
            Button("Allow Folder Access…") { document.grantFolderAccess() }
                .disabled(!document.hasDocument)
                .help("Let MarkPeek read images stored next to this document")
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") { ui.requestPrint = true }
                .keyboardShortcut("p")
                .disabled(!document.hasDocument)
        }
    }

    // MARK: Edit

    @CommandsBuilder
    private var editCommands: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in Document…") { ui.requestFind = true }
                .keyboardShortcut("f")
                .disabled(!document.hasDocument)
            Button("Find Next") { PreviewController.shared.findNext() }
                .keyboardShortcut("g")
                .disabled(!ui.showFind)
            Button("Find Previous") { PreviewController.shared.findNext(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!ui.showFind)
        }
    }

    // MARK: View

    @CommandsBuilder
    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            ForEach(Array(DocumentModel.ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                Button(mode.title) { document.mode = mode }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button("Zoom In") { PreviewController.shared.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { PreviewController.shared.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { PreviewController.shared.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button(ui.focusMode ? "Exit Focus Mode" : "Focus Mode") { ui.toggleFocusMode() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(!document.hasDocument)
            Button(ui.showInspector ? "Hide Theme Inspector" : "Show Theme Inspector") {
                ui.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    // MARK: Theme

    @CommandsBuilder
    private var themeCommands: some Commands {
        CommandMenu("Theme") {
            ThemePickerMenuContent()
            Divider()
            Button("New Theme…") { ui.showNewTheme = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Save as New Theme…") { ui.showSaveTheme = true }
            Button("Revert to Saved") { themes.revert() }
                .disabled(!themes.isActiveModified || themes.source == nil)
            Divider()
            Button("Import Theme…") { ui.isImportingTheme = true }
            Button("Export Active Theme…") { ui.exportTheme = themes.active }
            Button("Show Themes Folder in Finder") { themes.revealThemesFolder() }
        }
    }
}

/// Window-level UI state shared between the menu bar and the main window.
@MainActor
final class WindowState: ObservableObject {
    @Published var showInspector = false
    @Published var showExport = false
    @Published var showSaveTheme = false
    @Published var showNewTheme = false
    @Published var isImportingTheme = false
    @Published var exportTheme: Theme?
    @Published var requestPrint = false
    @Published var requestQuickPDF = false
    @Published var requestHTMLExport = false
    @Published var requestFind = false
    @Published var showFind = false
    @Published var showEditorFind = false
    @Published var showOnboarding = false
    @Published var focusMode = false
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    private var inspectorBeforeFocus = false

    /// Focus mode: editor only, centered, sidebar and inspector tucked away.
    func toggleFocusMode() {
        focusMode.toggle()
        if focusMode {
            inspectorBeforeFocus = showInspector
            showInspector = false
            sidebarVisibility = .detailOnly
            DocumentModel.shared.mode = .edit
        } else {
            sidebarVisibility = .all
            showInspector = inspectorBeforeFocus
        }
    }
}

/// Radio-style list of every theme, used by the Theme menu and the toolbar.
struct ThemePickerMenuContent: View {
    @ObservedObject private var themes = ThemeStore.shared

    var body: some View {
        Section("Built-in") {
            ForEach(themes.builtInThemes) { theme in
                themeButton(theme)
            }
        }
        if !themes.userThemes.isEmpty {
            Section("My Themes") {
                ForEach(themes.userThemes) { stored in
                    themeButton(stored.theme)
                }
            }
        }
    }

    private func themeButton(_ theme: Theme) -> some View {
        Button {
            themes.activate(theme)
        } label: {
            if themes.isActive(theme.id) {
                Label(theme.name, systemImage: "checkmark")
            } else {
                Text(theme.name)
            }
        }
    }
}

// Routes files opened from Finder: Markdown opens, theme files install.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in Updater.shared.checkInBackgroundIfDue() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if url.pathExtension.lowercased() == Theme.fileExtension {
                    ThemeStore.shared.importTheme(from: url)
                } else {
                    DocumentModel.shared.open(url)
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Pick up themes dropped into the folder while the app was in the background.
        Task { @MainActor in ThemeStore.shared.reload() }
    }
}
