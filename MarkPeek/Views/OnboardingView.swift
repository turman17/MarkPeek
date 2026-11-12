import SwiftUI
import UniformTypeIdentifiers

/// First-launch setup assistant (also Help ▸ Welcome Tour…): what MarkPeek
/// does, the permissions it benefits from, how the modes and themes work,
/// and a starting theme. Each step is skippable; the two permission steps
/// show their live status so it's clear what's already done.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .welcome
    @StateObject private var setup = SetupStatus()

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, finder, images, defaultApp, tour, theme
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .finder: "Finder Previews"
            case .images: "Images"
            case .defaultApp: "Default App"
            case .tour: "How It Works"
            case .theme: "Your Theme"
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "hand.wave"
            case .finder: "eye"
            case .images: "photo.on.rectangle.angled"
            case .defaultApp: "doc.badge.gearshape"
            case .tour: "rectangle.split.2x1"
            case .theme: "paintpalette"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, Design.Space.xxl)
                    .padding(.top, Design.Space.xxl)
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 540)
        .animation(.snappy(duration: 0.3, extraBounce: 0), value: step)
        .onAppear { setup.refresh() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Design.Space.s) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                Text("Set up MarkPeek")
                    .font(.headline)
            }
            .padding(.horizontal, Design.Space.l)
            .padding(.top, Design.Space.xl)
            .padding(.bottom, Design.Space.l)

            ForEach(Step.allCases) { item in
                Button { step = item } label: {
                    HStack(spacing: Design.Space.s) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 20)
                            .foregroundStyle(item == step ? Color.accentColor : .secondary)
                        Text(item.title)
                            .fontWeight(item == step ? .semibold : .regular)
                        Spacer()
                        if let done = status(of: item) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? Color.green : Color.secondary.opacity(0.5))
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, Design.Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.s)
                            .fill(item == step ? Color.accentColor.opacity(0.12) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Design.Space.s)
            }
            Spacer()
            Text("You can change all of this later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(Design.Space.l)
        }
        .frame(width: 210)
        .background(Glass(material: .sidebar))
    }

    /// Nil for informational steps; otherwise whether the step is satisfied.
    private func status(of item: Step) -> Bool? {
        switch item {
        case .images: !setup.grantedFolders.isEmpty
        case .defaultApp: setup.isDefaultApp
        default: nil
        }
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .finder: finder
        case .images: images
        case .defaultApp: defaultApp
        case .tour: tour
        case .theme: theme
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            Hero {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            PageTitle("Markdown that looks finished",
                      "MarkPeek styles your Markdown everywhere on your Mac: in Finder previews, in this reader and editor, and in the PDFs and HTML you export.")
            VStack(alignment: .leading, spacing: Design.Space.m) {
                FeatureRow(symbol: "eye", title: "Press Space in Finder", detail: "Quick Look shows any Markdown file with your theme instead of raw text.")
                FeatureRow(symbol: "rectangle.split.2x1", title: "Read, split, or edit", detail: "A page-like reader, a side-by-side editor that stays in sync, or a focused writing view.")
                FeatureRow(symbol: "paintpalette", title: "Themes you own", detail: "Six built-in looks, every detail adjustable, saved as small files you can share.")
            }
        }
    }

    private var finder: some View {
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            Hero {
                HStack(spacing: Design.Space.l) {
                    FileIcon(name: "notes.md")
                    KeyCap("space")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    MiniPage()
                }
            }
            PageTitle("Previews and thumbnails in Finder",
                      "Select a Markdown file and press Space. The preview uses whichever theme is active here. Files MarkPeek owns, such as .mdown and .mkd, also get page thumbnails.")
            VStack(alignment: .leading, spacing: Design.Space.s) {
                Text("macOS enables the extension on most Macs automatically. If a preview still shows plain text, switch it on under Quick Look in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: Design.Space.m) {
                    Button("Open Extension Settings…") { openQuickLookSettings() }
                    Text("General ▸ Login Items & Extensions ▸ Quick Look")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var images: some View {
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            Hero {
                HStack(spacing: Design.Space.l) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                    Image(systemName: "lock.open")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    MiniPage(withImage: true)
                }
            }
            PageTitle("Show images next to your documents",
                      "MarkPeek runs in the macOS sandbox, so it can read a file you open but not the images sitting beside it. Allow a folder once and every document inside it, including subfolders, shows its images.")
            VStack(alignment: .leading, spacing: Design.Space.s) {
                HStack(spacing: Design.Space.m) {
                    Button("Allow a Folder…") { setup.requestFolder() }
                    Text("Your Documents folder is a good start; you can add more at any time from the File menu.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if setup.grantedFolders.isEmpty {
                    StatusLine(ok: false, text: "No folders allowed yet. Documents without images work fine without this.")
                } else {
                    ForEach(setup.grantedFolders, id: \.self) { path in
                        StatusLine(ok: true, text: SetupStatus.abbreviated(path))
                    }
                }
            }
        }
    }

    private var defaultApp: some View {
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            Hero {
                HStack(spacing: Design.Space.l) {
                    FileIcon(name: "README.md")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
            }
            PageTitle("Open Markdown files with MarkPeek",
                      "Double-clicking a .md or .markdown file in Finder opens it here instead of a text editor. Other apps keep working with the files as before.")
            VStack(alignment: .leading, spacing: Design.Space.s) {
                HStack(spacing: Design.Space.m) {
                    Button("Make MarkPeek the Default") { setup.makeDefault() }
                        .disabled(setup.isDefaultApp)
                    Text("Undo any time from a file's Get Info panel in Finder.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                StatusLine(ok: setup.isDefaultApp,
                           text: setup.isDefaultApp ? "MarkPeek opens Markdown files."
                                                    : "Markdown files currently open in \(setup.currentDefaultName).")
            }
        }
    }

    private var tour: some View {
        VStack(alignment: .leading, spacing: Design.Space.l) {
            PageTitle("Three ways to work",
                      "Switch with the toolbar or ⌘1, ⌘2 and ⌘3. In Split, hovering a paragraph highlights it on the other side so you never lose your place.")
            HStack(spacing: Design.Space.m) {
                ModeCard(symbol: "doc.richtext", title: "Preview", detail: "Read on a page card with your theme. ⌘F finds text, ⌘+ and ⌘− zoom.")
                ModeCard(symbol: "rectangle.split.2x1", title: "Split", detail: "Source on the left, live preview on the right, linked by hover.")
                ModeCard(symbol: "pencil.line", title: "Edit", detail: "Just the text. ⌥⌘F for a centered, distraction-free focus mode.")
            }
            Grid(alignment: .leading, horizontalSpacing: Design.Space.xl, verticalSpacing: Design.Space.s) {
                GridRow {
                    Shortcut("⌥⌘I", "Theme inspector: fonts, colors, spacing, extras")
                    Shortcut("⇧⌘E", "Export as PDF with page numbers")
                }
                GridRow {
                    Shortcut("⌥⌘E", "Export a self-contained HTML file")
                    Shortcut("⇧⌘N", "New theme from a base and a few choices")
                }
                GridRow {
                    Shortcut("⌘O", "Open a file, or drop one on the window")
                    Shortcut("Space", "Quick Look any Markdown file in Finder")
                }
            }
            .font(.callout)
            .padding(.top, Design.Space.xs)
        }
    }

    private var theme: some View {
        ThemePickStep()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .theme {
                Button("Skip Setup") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
            }
            Button(step == .theme ? "Get Started" : "Continue") {
                if step == .theme { dismiss() } else { step = Step(rawValue: step.rawValue + 1) ?? .theme }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Design.Space.xxl)
        .padding(.vertical, Design.Space.l)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Setup state

/// Live status of the permissions the assistant can grant.
@MainActor
final class SetupStatus: ObservableObject {
    @Published private(set) var grantedFolders: [String] = []
    @Published private(set) var isDefaultApp = false
    @Published private(set) var currentDefaultName = "another app"

    static let markdownType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText

    func refresh() {
        grantedFolders = FolderAccess.grantedFolders
        let current = NSWorkspace.shared.urlForApplication(toOpen: Self.markdownType)
        isDefaultApp = current?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        currentDefaultName = current.map { FileManager.default.displayName(atPath: $0.path) } ?? "another app"
    }

    func requestFolder() {
        _ = FolderAccess.request(for: Self.realHome.appendingPathComponent("Documents"))
        refresh()
        DocumentModel.shared.folderAccessChanged()
    }

    func removeFolder(_ path: String) {
        FolderAccess.remove(path)
        refresh()
        DocumentModel.shared.folderAccessChanged()
    }

    /// The user's home folder; inside the sandbox, `NSHomeDirectory` is the container.
    static let realHome: URL = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static func abbreviated(_ path: String) -> String {
        let home = realHome.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    func makeDefault() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: Self.markdownType) { _ in
            Task { @MainActor in self.refresh() }
        }
    }
}

// MARK: - Pieces

/// Tinted stage at the top of a page for an illustration.
private struct Hero<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Design.Radius.l)
                .fill(LinearGradient(colors: [Design.brand.opacity(0.16), Design.brand.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            content()
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }
}

private struct PageTitle: View {
    let title: String
    let detail: String
    init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ModeCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title).fontWeight(.semibold)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Design.Space.l)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: Design.Radius.m).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.m).strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct Shortcut: View {
    let keys: String
    let text: String
    init(_ keys: String, _ text: String) { self.keys = keys; self.text = text }

    var body: some View {
        HStack(spacing: Design.Space.s) {
            KeyCap(keys)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}

private struct StatusLine: View {
    let ok: Bool
    let text: String

    var body: some View {
        HStack(spacing: Design.Space.s) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            Text(text).font(.callout).foregroundStyle(ok ? .primary : .secondary)
        }
    }
}

/// A document icon with a name, for the illustrations.
private struct FileIcon: View {
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white, Color.secondary.opacity(0.55))
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// A tiny rendered page, for the illustrations.
private struct MiniPage: View {
    var withImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.7)).frame(width: 46, height: 6)
            RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 66, height: 3)
            RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 58, height: 3)
            if withImage {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 66, height: 22)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 62, height: 3)
            }
            RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.5)).frame(width: 40, height: 3)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

/// Last step: starting theme, and automatic updates when the updater is configured.
private struct ThemePickStep: View {
    @ObservedObject private var themes = ThemeStore.shared
    @ObservedObject private var updater = Updater.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xl) {
            PageTitle("Pick a starting theme",
                      "Every font, color and spacing is adjustable in the theme inspector, and you can save your own themes as small files to share.")
            Picker("Theme", selection: Binding(
                get: { themes.source?.id ?? Theme.modern.id },
                set: { id in if let theme = themes.theme(id: id) { themes.activate(theme) } }
            )) {
                ForEach(themes.builtInThemes) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ThemeSwatch(theme: themes.active)
            Text(blurb)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Read the Theme Guide") { openWindow(id: GuideView.windowID) }
                .buttonStyle(.link)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            ))
            .padding(.top, Design.Space.s)
        }
    }

    private var blurb: String {
        switch themes.source?.name {
        case "Serif": "Charter and generous spacing: bookish, made for long reads."
        case "GitHub": "The familiar look of READMEs on GitHub, light and dark."
        case "Plain": "Minimal and unadorned. The text, and nothing else."
        case "Paper": "Warm paper tones and justified text, like a printed page."
        case "Mono": "Monospaced throughout, in the spirit of a terminal."
        default: "Clean sans-serif with a comfortable measure. A safe default for anything."
        }
    }
}

/// A small page rendered with the theme's own fonts and colors.
private struct ThemeSwatch: View {
    let theme: Theme
    @Environment(\.colorScheme) private var scheme

    private var palette: Theme.Palette { theme.palette(for: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The Quick Brown Fox")
                .font(.themeFamily(theme.typography.headingFont.isEmpty ? theme.typography.bodyFont : theme.typography.headingFont,
                                   size: 22, weight: theme.headingFontWeight))
                .foregroundStyle(Color(hex: palette.heading))
            Text("Jumps over the lazy dog, with a [link](#) and `inline code` to show the palette in use.")
                .font(.themeFamily(theme.typography.bodyFont, size: 13))
                .foregroundStyle(Color(hex: palette.text))
            HStack(spacing: 6) {
                ForEach([palette.accent, palette.link, palette.codeBackground, palette.blockquoteBorder], id: \.self) { hex in
                    Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                }
            }
        }
        .padding(Design.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.m).fill(Color(hex: palette.background)))
        .overlay(RoundedRectangle(cornerRadius: Design.Radius.m).strokeBorder(Color.primary.opacity(0.1)))
        .animation(.snappy, value: theme.id)
    }

}
