import SwiftUI

/// The document area: welcome state, or preview / split / editor.
struct ReaderView: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState

    var body: some View {
        if !document.hasDocument {
            WelcomeView()
        } else if ui.focusMode {
            FocusEditor()
        } else {
            DocumentPanes(mode: document.mode, previewTargetWidth: previewTargetWidth) {
                EditorView()
            } preview: {
                preview
            }
            .onChange(of: document.mode) { _, mode in
                PreviewController.shared.syncHover(enabled: mode == .split)
            }
        }
    }

    /// Page width plus the card's breathing room, clamped to something sane.
    private var previewTargetWidth: CGFloat {
        let content = themes.active.layout.maxWidth > 0 ? themes.active.layout.maxWidth : 700
        return min(max(CGFloat(content) + 64, 520), 820)
    }

    private var previewScheme: ThemeColorScheme? {
        if let scheme = themes.previewScheme { return scheme }
        switch themes.active.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var preview: some View {
        LivePreview(
            markdown: document.draft,
            theme: themes.active,
            scheme: themes.previewScheme,
            documentID: document.fileURL?.path ?? "",
            generation: document.renderGeneration,
            baseURL: document.folderURL,
            imageResolver: document.imageResolver,
            scripts: ScriptLibrary.scripts(for: MarkdownRenderer.features(of: document.draft), scheme: previewScheme)
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if ui.showFind { FindBar() }
                if document.fileChangedOnDisk { FileChangedBanner() }
                if document.needsFolderAccess { FolderAccessBanner() }
            }
        }
    }
}

/// Search field for the rendered preview (⌘F). Uses the web view's own
/// find, so matches scroll into view and stay selected.
struct FindBar: View {
    @ObservedObject private var preview = PreviewController.shared
    @EnvironmentObject private var ui: WindowState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in document", text: $preview.findText)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { preview.findNext() }
                .frame(maxWidth: 320)
            if let count = preview.findCount, !preview.findText.isEmpty {
                Text(count == 1 ? "1 match" : "\(count) matches")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(count == 0 ? .red : .secondary)
            }
            Button { preview.findNext(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("Previous match (⇧⌘G)")
            Button { preview.findNext() } label: { Image(systemName: "chevron.down") }
                .help("Next match (⌘G)")
            Spacer()
            Button("Done") {
                ui.showFind = false
                preview.clearFind()
            }
            .keyboardShortcut(.cancelAction)
        }
        .controlSize(.small)
        .padding(.horizontal, Design.Space.l)
        .padding(.vertical, Design.Space.s)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { focused = true }
        .onChange(of: preview.findText) { _, _ in
            preview.updateFindCount()
            preview.findNext()
        }
    }
}

/// Shown when another app changed the file while there are unsaved edits here.
struct FileChangedBanner: View {
    @ObservedObject private var document = DocumentModel.shared

    var body: some View {
        HStack(spacing: Design.Space.m) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            Text("This file changed on disk. Your unsaved edits are kept.")
                .font(.callout)
                .lineLimit(1)
                .layoutPriority(-1)
            Spacer()
            Button("Reload from Disk") { document.reloadFromDisk() }
            Button("Keep Mine") { document.keepLocalChanges() }
        }
        .controlSize(.small)
        .padding(.horizontal, Design.Space.l)
        .padding(.vertical, Design.Space.s)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Focus mode: the editor alone, centered at a comfortable measure.
struct FocusEditor: View {
    @ObservedObject private var document = DocumentModel.shared
    @EnvironmentObject private var ui: WindowState

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
            SourceEditor(text: $document.draft, showFind: $ui.showEditorFind, fontSize: 15, lineSpacing: 5,
                         inset: CGSize(width: 12, height: 48))
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Exit Focus Mode") { ui.toggleFocusMode() }
                .controlSize(.small)
                .padding(Design.Space.m)
        }
    }
}

/// Re-renders when the text or theme changes, off the main thread and
/// debounced so typing in split mode doesn't reload per keystroke.
struct LivePreview: View {
    let markdown: String
    let theme: Theme
    let scheme: ThemeColorScheme?
    let documentID: String
    let generation: Int
    let baseURL: URL?
    let imageResolver: (@Sendable (String) -> String?)?
    let scripts: [String]
    var isMainPreview = true
    @State private var html = ""

    private struct RenderKey: Hashable {
        let markdown: String
        let theme: Theme
        let scheme: ThemeColorScheme?
        let documentID: String
        let generation: Int
        let scriptCount: Int
    }

    var body: some View {
        ZStack {
            Glass()
            MarkdownWebView(html: html, documentID: documentID, baseURL: baseURL, appearance: appearance, isMainPreview: isMainPreview)
        }
        .task(id: RenderKey(markdown: markdown, theme: theme, scheme: scheme, documentID: documentID, generation: generation, scriptCount: scripts.count)) {
            if !html.isEmpty {
                try? await Task.sleep(for: .milliseconds(160))
                if Task.isCancelled { return }
            }
            let options = RenderOptions(surface: .pageCard, colorScheme: scheme, imageResolver: imageResolver, scripts: scripts, sourceMap: true)
            let markdown = markdown, theme = theme
            let rendered = await Task.detached(priority: .userInitiated) {
                MarkdownRenderer.document(markdown: markdown, theme: theme, options: options)
            }.value
            if !Task.isCancelled { html = rendered }
        }
    }

    private var appearance: NSAppearance? {
        if let scheme { return NSAppearance.forScheme(scheme) }
        switch theme.appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Editor and preview side by side. Both stay mounted; switching modes
/// animates the pane widths so the editor folds in and out instead of
/// snapping, the divider in Split is draggable, and the window grows to fit
/// both panes when Split is entered (and shrinks back when it's left).
///
/// The web view is never resized: it always spans the whole area and the
/// editor slides in on top of it, while the page content moves aside with a
/// CSS transition inside the web view. Resizing a WKWebView blanks it until
/// the web process repaints, which is the flash this avoids. The editor is
/// laid out at its final width inside an animated clip, so it never re-wraps
/// mid-animation either.
struct DocumentPanes<Editor: View, Preview: View>: View {
    let mode: DocumentModel.ViewMode
    /// Width the preview pane wants in Split so the page is fully visible.
    let previewTargetWidth: CGFloat
    @ViewBuilder let editor: () -> Editor
    @ViewBuilder let preview: () -> Preview

    @AppStorage("splitFraction") private var fraction = 0.5
    @State private var dragStartFraction: Double?
    @State private var window: NSWindow?
    @State private var sizer = SplitWindowSizer()
    /// Visible editor width while a mode change animates; nil follows the mode.
    @State private var animatedEditorWidth: CGFloat?

    private let dividerWidth: CGFloat = 1
    private let minimumFraction = 0.25
    private let editorTargetWidth: CGFloat = 460

    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let targetEditor = editorWidth(for: mode, total: total)
            let shownEditor = animatedEditorWidth ?? targetEditor
            let divider = mode == .split ? dividerWidth : 0
            // Content widths: the editor keeps its Split width while folded
            // so it doesn't re-wrap; the preview sits at its final width.
            let editorContent = mode == .edit ? total : splitEditorWidth(total: total)
            let inset = targetEditor + divider
            ZStack(alignment: .leading) {
                preview()
                    .frame(width: total)
                HStack(spacing: 0) {
                    editor()
                        .frame(width: editorContent)
                        .frame(width: shownEditor, alignment: .leading)
                        .clipped()
                    if mode == .split {
                        self.divider(total: total)
                    }
                }
            }
            .onChange(of: mode) { old, new in
                animatedEditorWidth = editorWidth(for: old, total: total)
                withAnimation(.snappy(duration: 0.35, extraBounce: 0)) {
                    animatedEditorWidth = editorWidth(for: new, total: total)
                } completion: {
                    animatedEditorWidth = nil
                }
                PreviewController.shared.setLeftInset(editorWidth(for: new, total: total) + (new == .split ? dividerWidth : 0), animated: true)
                sizer.modeChanged(from: old, to: new, window: window,
                                  availableWidth: total,
                                  neededWidth: editorTargetWidth + dividerWidth + previewTargetWidth)
            }
            .onChange(of: inset) { _, new in
                // Divider drags and window resizes: follow immediately, unless a
                // mode change is mid-flight, in which case the transition retargets.
                PreviewController.shared.setLeftInset(new, animated: animatedEditorWidth != nil)
            }
            .onAppear {
                PreviewController.shared.setLeftInset(inset, animated: false)
            }
        }
        .background(WindowAccessor { window = $0 })
    }

    private func splitEditorWidth(total: CGFloat) -> CGFloat {
        max(0, (total - dividerWidth) * fraction)
    }

    private func editorWidth(for mode: DocumentModel.ViewMode, total: CGFloat) -> CGFloat {
        switch mode {
        case .preview: 0
        case .edit: total
        case .split: splitEditorWidth(total: total)
        }
    }

    private func divider(total: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: dividerWidth)
            .overlay {
                // Wider invisible grab area than the 1pt line.
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartFraction == nil { dragStartFraction = fraction }
                                let start = dragStartFraction ?? fraction
                                let proposed = start + Double(value.translation.width / max(total, 1))
                                fraction = min(max(proposed, minimumFraction), 1 - minimumFraction)
                            }
                            .onEnded { _ in dragStartFraction = nil }
                    )
            }
    }
}

/// Widens the window when Split needs more room than the document area has,
/// and folds it back to the previous size when Split is left, unless the user
/// resized the window in between. The resize runs through the window's
/// animator so it never blocks the main thread.
@MainActor
final class SplitWindowSizer {
    private var savedFrame: NSRect?
    private var grownWidth: CGFloat?

    func modeChanged(from old: DocumentModel.ViewMode, to new: DocumentModel.ViewMode,
                     window: NSWindow?, availableWidth: CGFloat, neededWidth: CGFloat) {
        guard let window else { return }
        if new == .split, old != .split {
            let extra = neededWidth - availableWidth
            guard extra > 0 else { return }
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            var frame = window.frame
            savedFrame = frame
            frame.size.width = min(frame.width + extra, screen.width)
            if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
            grownWidth = frame.width
            animate(window, to: frame)
        } else if old == .split, new != .split, let saved = savedFrame {
            defer { savedFrame = nil; grownWidth = nil }
            guard let grownWidth, abs(window.frame.width - grownWidth) < 2 else { return }
            var frame = window.frame
            frame.size.width = saved.width
            frame.origin.x = min(saved.origin.x, frame.origin.x)
            animate(window, to: frame)
        }
    }

    private func animate(_ window: NSWindow, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

/// Hands the hosting NSWindow to SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor in onWindow(view.window) }
    }
}

/// Shown when the document references images in its folder that the sandbox can't read.
struct FolderAccessBanner: View {
    @ObservedObject private var document = DocumentModel.shared

    var body: some View {
        HStack(spacing: Design.Space.m) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.secondary)
            Text("Images in this folder need access to show.")
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
            Spacer()
            Button("Allow…") { document.grantFolderAccess() }
                .help("Allow MarkPeek to read images in this file's folder")
            Button {
                document.dismissFolderAccessPrompt()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .controlSize(.small)
        .padding(.horizontal, Design.Space.l)
        .padding(.vertical, Design.Space.s)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

// MARK: - Editor

struct EditorView: View {
    @ObservedObject private var document = DocumentModel.shared
    @ObservedObject private var preview = PreviewController.shared
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var ui: WindowState

    var body: some View {
        VStack(spacing: 0) {
            SourceEditor(text: $document.draft, showFind: $ui.showEditorFind, fontSize: 13, lineSpacing: 3,
                         inset: CGSize(width: Design.Space.m, height: Design.Space.m),
                         highlightedLines: preview.editorHighlight,
                         highlightColor: accent,
                         onHover: { preview.editorHovered(line: $0) })
                .background(Color(nsColor: .textBackgroundColor))
            Divider()
            HStack(spacing: Design.Space.m) {
                if document.hasUnsavedChanges {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                    Text(document.autoSave ? "Saving…" : "Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Saved")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle("Auto Save", isOn: $document.autoSave)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Save automatically shortly after you stop typing")
                Text("\(document.wordCount) words")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Design.Space.m)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }

    /// The theme's accent for the editor's appearance (light or dark).
    private var accent: NSColor {
        let light = NSColor(Color(hex: themes.active.light.accent))
        let dark = NSColor(Color(hex: themes.active.dark.accent))
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

// MARK: - Welcome (no document)

struct WelcomeView: View {
    @ObservedObject private var document = DocumentModel.shared

    var body: some View {
        VStack(spacing: Design.Space.xl) {
            Button {
                document.isImporting = true
            } label: {
                VStack(spacing: Design.Space.m) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop a Markdown file here")
                        .font(.system(size: 15, weight: .semibold))
                    Text("or click to browse")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(RoundedRectangle(cornerRadius: Design.Radius.l).fill(Color.primary.opacity(0.035)))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.l)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: Design.Radius.l))
            }
            .buttonStyle(.plain)

            if !document.recents.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.s) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(document.recents.prefix(5)) { recent in
                        Button {
                            document.openRecent(recent)
                        } label: {
                            HStack(spacing: Design.Space.s) {
                                Image(systemName: "doc.text").foregroundStyle(Color.accentColor)
                                Text(recent.name).fontWeight(.medium)
                                Text((recent.path as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, Design.Space.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: Design.Radius.s))
                    }
                }
            }

            Text("Tip: select any .md file in Finder and press Space for an instant styled preview.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(Design.Space.xxl)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Glass())
    }
}
