# Contributing to MarkPeek

Thanks for your interest! Bug reports, feature requests, theme contributions and pull requests are all welcome.

## Reporting bugs

Open an issue with the bug report template. The most useful reports include:

- macOS version and Mac model (Apple Silicon or Intel)
- Where it happened: Quick Look, a Finder thumbnail, the app, or an export
- A small Markdown sample that reproduces it (strip anything private first)
- The active theme, or the `.markpeektheme` file if it's a custom one

## Building from source

Requirements: macOS 14+, Xcode 16+, Swift 6.

```bash
bash scripts/build-and-install.sh   # build, sign, install to /Applications, register the Quick Look extensions
```

The project layout is described in the README's Architecture section. The short version:

- `Shared/` — the theme model, the Markdown → HTML renderer and the stylesheet. Compiled into the app and both extensions. Most rendering changes happen here.
- `MarkPeek/` — the SwiftUI app: sidebar, reader, editor, inspector, exports, setup assistant.
- `MarkPeekQuickLook/` and `MarkPeekThumbnail/` — the Finder extensions.
- `docs/THEME-FORMAT.md` — the theme file reference. Keep it and the in-app Theme Guide in step with `Shared/Theme.swift`.

Run tests with:

```bash
xcodebuild -project MarkPeek.xcodeproj -scheme MarkPeek -destination 'platform=macOS' test
```

## Pull requests

- Keep PRs focused — one fix or feature per PR.
- Match the surrounding code style; the codebase is plain Swift with no linter config yet.
- Commit messages follow Conventional Commits: `type(scope): summary` (types: feat, fix, refactor, chore, docs, test).
- Rendering changes should keep `docs/sample.md` looking right in all six built-in themes, in the app and in Quick Look.
- Adding tests with your change is very welcome.

## Themes

Built a theme worth sharing? Open a pull request adding it to `docs/themes/`, or link it from an issue.

## Licensing

MarkPeek is GPL-3.0. By contributing, you agree your contributions are licensed under the same terms.
