# MarkPeek

A native macOS Quick Look extension for Markdown. Select any `.md` file in Finder, press **Space**, and instead of raw Markdown you see a styled preview.

Styling is ported directly from [FinderConvert](../Converter)'s Markdown renderer, so previews look exactly like FinderConvert's Markdown → HTML/PDF output.

## Features

- **Press Space on a `.md` file** — styled preview instead of raw text
- **Tabbed style settings** in the MarkPeek app, with a live preview pane:
  - **Presets tab** — built-in styles (Modern, Serif, GitHub, Plain — same as FinderConvert) plus your own saved presets: save the current settings as a named preset, rename or delete via right-click. Edits to a selected custom preset auto-save into it; edits to a built-in become "Custom (unsaved)" until you save them.
  - **Typography tab** — body/code fonts, font size, line height, heading weight, H1/H2 underline, italic blockquotes
  - **Layout tab** — content width, page margin, paragraph spacing, code block padding, corner radius
  - **Colors tab** — appearance (follow system / always light / always dark) and separate light & dark color sets: background, text, headings, links, code, blockquotes, rules
- **Dark mode** — previews follow the system appearance (or your override)
- Supports `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`
- Renders headings, bold, italic, inline code, code blocks, ordered/unordered lists, blockquotes, links, horizontal rules

## Prerequisites

- macOS 14 or later
- Xcode 16 or later
- Swift 6

## Build & Install

```bash
bash scripts/build-and-install.sh
```

This builds the app, installs it to `/Applications`, registers the Quick Look extension, and resets the Quick Look cache.

For manual builds:

```bash
xcodebuild -project MarkPeek.xcodeproj -scheme MarkPeek -destination 'platform=macOS' build
```

## Setup

1. Build and install: `bash scripts/build-and-install.sh`
2. The app launches once automatically to register the extension
3. Select any `.md` file in Finder and press Space

If previews still show raw text, enable MarkPeek under **System Settings → General → Login Items & Extensions → Quick Look**, then run `qlmanage -r`.

## Architecture

```
MarkPeek/                      # Host app (SwiftUI)
  MarkPeekApp.swift            # Settings UI with live WKWebView preview
  AppIcon.icns                 # FinderConvert-style icon (markdown "M↓")

MarkPeekQuickLook/             # Quick Look preview extension
  PreviewProvider.swift        # QLPreviewProvider: .md -> styled HTML

Shared/                        # Compiled into both targets
  MarkdownRenderer.swift       # Markdown -> HTML (ported from FinderConvert)
  MarkdownStyle.swift          # Preset identifiers
  PreviewSettings.swift        # Settings model, presets, CSS generation, persistence
```

The extension is a data-based Quick Look preview (`QLPreviewReply` with HTML content), so Quick Look renders the HTML natively — no embedded web view needed. Settings are stored as JSON in the `group.com.markpeek.app.shared` app group and read by the extension on every preview, so changes apply immediately.

## Configuration

- App bundle: `com.markpeek.app`
- Extension bundle: `com.markpeek.app.QuickLook`
- App Group: `group.com.markpeek.app.shared`
