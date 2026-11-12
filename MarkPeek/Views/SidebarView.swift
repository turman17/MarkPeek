import SwiftUI

/// Recent documents and the theme library. Picking a document opens it;
/// picking a theme activates it (and never discards edits in progress).
struct SidebarView: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState
    @State private var selection: Selection?
    @State private var renaming: Theme?

    enum Selection: Hashable {
        case recent(String)
        case theme(UUID)
    }

    var body: some View {
        List(selection: $selection) {
            Section("Documents") {
                if document.recents.isEmpty {
                    Text("Open a Markdown file to get started.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(document.recents) { recent in
                    recentRow(recent)
                }
            }

            if document.hasDocument, !document.outline.isEmpty {
                Section("Outline") {
                    ForEach(document.outline) { item in
                        outlineRow(item)
                    }
                }
            }

            Section("Themes") {
                ForEach(themes.builtInThemes) { theme in
                    themeRow(theme)
                }
            }

            Section("My Themes") {
                ForEach(themes.userThemes) { stored in
                    themeRow(stored.theme)
                }
                Button {
                    ui.showNewTheme = true
                } label: {
                    Label("New Theme…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .selectionDisabled()
                .help("Start a theme from a base, fonts and colors (⇧⌘N)")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .onChange(of: selection) { _, new in
            switch new {
            case .recent(let id):
                if let recent = document.recents.first(where: { $0.id == id }), document.fileURL?.path != recent.path {
                    document.openRecent(recent)
                }
            case .theme(let id):
                if !themes.isActive(id), let theme = themes.theme(id: id) {
                    themes.activate(theme)
                }
            case nil:
                break
            }
        }
        .onChange(of: document.fileURL) { _, url in
            if let path = url?.path { selection = .recent(path) }
        }
        .onAppear {
            if let path = document.fileURL?.path { selection = .recent(path) }
        }
        .sheet(item: $renaming) { theme in
            NameSheet(title: "Rename Theme", prompt: "Theme name", name: theme.name, action: "Rename") { name in
                themes.rename(theme.id, to: name)
            }
        }
    }

    // MARK: Rows

    private func recentRow(_ recent: RecentFile) -> some View {
        let isOpen = document.fileURL?.path == recent.path
        let folder = ((recent.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        return HStack(spacing: Design.Space.s) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .fontWeight(isOpen ? .semibold : .regular)
                        .lineLimit(1)
                    Text(folder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: "doc.text")
            }
            Spacer(minLength: 0)
            if isOpen && document.hasUnsavedChanges {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Unsaved changes")
            }
        }
        .padding(.vertical, 1)
        .help((recent.path as NSString).abbreviatingWithTildeInPath)
        .tag(Selection.recent(recent.id))
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: recent.path)])
            }
            Button("Remove from Recents") { document.removeRecent(recent) }
        }
    }

    private func outlineRow(_ item: OutlineItem) -> some View {
        Button {
            if document.mode == .edit { document.mode = .split }
            PreviewController.shared.scroll(toHeading: item.id)
        } label: {
            Text(item.title)
                .font(.themeFamily(outlineFontFamily, size: 13,
                                   weight: item.level == 1 ? .semibold : item.level == 2 ? .medium : .regular))
                .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                .lineLimit(1)
                .padding(.leading, CGFloat(min(max(0, item.level - 1), 4)) * 10)
                .padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .help(item.title)
    }

    /// The outline mirrors the preview: headings in the theme's heading font.
    private var outlineFontFamily: String {
        let t = themes.active.typography
        return t.headingFont.isEmpty ? t.bodyFont : t.headingFont
    }

    private func themeRow(_ theme: Theme) -> some View {
        let isActive = themes.isActive(theme.id)
        let isBuiltIn = themes.isBuiltIn(theme.id)
        return HStack(spacing: Design.Space.s) {
            ThemeSwatchIcon(theme: theme)
            Text(theme.name)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isActive && themes.isActiveModified {
                Text("Edited")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if isActive {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Active")
            }
        }
        .padding(.vertical, 1)
        .tag(Selection.theme(theme.id))
        .contextMenu {
            Button("Customize…") {
                if !isActive { themes.activate(theme) }
                ui.showInspector = true
            }
            Button("Duplicate") { themes.duplicate(theme) }
            if !isBuiltIn {
                Button("Rename…") { renaming = theme }
            }
            Button("Export…") { ui.exportTheme = theme }
            if !isBuiltIn {
                Button("Show in Finder") {
                    if let url = themes.fileURL(for: theme.id) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { themes.delete(theme.id) }
            }
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Design.Space.xs) {
            Menu {
                Button("New Theme from Current…") { ui.showSaveTheme = true }
                Button("Import Theme…") { ui.isImportingTheme = true }
                Divider()
                Button("Show Themes Folder in Finder") { themes.revealThemesFolder() }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add a theme")

            Spacer()
        }
        .padding(.horizontal, Design.Space.s)
        .padding(.vertical, Design.Space.xs)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// A small page in the theme's own background, heading color and font.
struct ThemeSwatchIcon: View {
    let theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = theme.palette(for: scheme)
        Text("Aa")
            .font(.themeFamily(theme.typography.headingFont.isEmpty ? theme.typography.bodyFont : theme.typography.headingFont,
                               size: 10, weight: theme.headingFontWeight))
            .foregroundStyle(Color(hex: palette.heading))
            .frame(width: 24, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: palette.background)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
    }
}
