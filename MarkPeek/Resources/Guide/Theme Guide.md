# Theme Guide

A theme decides how every Markdown file looks: in this window, in Finder's Quick Look previews, and in the PDFs and HTML you export. This page is rendered with the theme that is active right now, so switch themes while you read to see the difference.

## The short version

1. Pick a theme in the sidebar. Six are built in: **Modern**, **Serif**, **GitHub**, **Plain**, **Paper** and **Mono**.
2. Open the inspector with **⌥⌘I** and change anything. The document updates as you drag.
3. Choose **Save As…** at the top of the inspector to keep the result as your own theme.

Built-in themes never change. While you edit one, the sidebar shows *Edited* next to it; **Revert** puts it back, and **Save As…** turns your edits into a new theme under **My Themes**.

## Starting a theme from scratch

**Theme ▸ New Theme…** (⇧⌘N) is the quickest start. Pick a base, a body and code font, size, page width, and the accent colors for light and dark. The new theme opens in the inspector for fine-tuning.

> Tip: the base you choose only sets the starting values. Nothing links the two afterwards.

## The inspector, tab by tab

### Type

- **Fonts** for body, headings and code. Leave the heading font as the body font to keep one family. Any font installed on your Mac works; `-apple-system` is San Francisco.
- **Size**: text size in pixels, line height as a multiple of it, paragraph spacing in em, and code size relative to the body.
- **Headings**: weight from Regular to Heavy, the **scale** between levels (1.25 is a classic "major third"), and the space above each heading.
- **Text**: alignment and hyphenation.

### Layout

- **Page**: content width caps the measure. Around 65 to 75 characters per line reads best; 700 px suits 16 px text. Top, bottom and side padding sit around it.
- **Blocks**: corner radius for code, images and tables, code block padding, quote border width, list indent and table cell padding.
- **Images**: maximum width as a share of the content width.

### Colors

There are two palettes, **Light** and **Dark**. Each has colors for the background, text, headings, links, code, quotes, rules, tables and the accent that is used for selections and highlights. The **Appearance** setting decides which palette a preview uses: follow the system, or always light, or always dark.

Code syntax colors live in each palette too. Picking a background suggests a matching set, which you can then adjust.

### Extras

- **Headings**: a rule under H1 and H2, and automatic numbering.
- **Code blocks**: syntax colors, the language label, wrapped lines and line numbers.
- **Lists and tables**: bullet style, table borders and striped rows.
- **Images**: rounded corners, a shadow, and centering for standalone images.
- **Details**: underlined links, italic quotes, a drop cap on the first paragraph, the horizontal rule style, and how front matter (`---` at the top) is shown: as a table, hidden, or raw.
- **Custom CSS** for anything the controls don't cover.

## Custom CSS

Custom CSS is appended after the generated stylesheet, so it wins. The palette is exposed as variables you can reuse:

```css
h2 { border-bottom: 1px solid var(--mp-rule); padding-bottom: 0.2em; }
blockquote { background: color-mix(in srgb, var(--mp-accent) 8%, transparent); }
a { text-decoration-thickness: 2px; }
```

Available variables: `--mp-bg`, `--mp-text`, `--mp-heading`, `--mp-link`, `--mp-code-bg`, `--mp-code-text`, `--mp-quote-text`, `--mp-quote-border`, `--mp-rule`, `--mp-table-border`, `--mp-table-head`, `--mp-table-stripe`, `--mp-accent`, `--mp-muted`, `--mp-card-shadow`, and the syntax colors `--mp-syn-kw`, `--mp-syn-str`, `--mp-syn-cm`, `--mp-syn-num`, `--mp-syn-type`, `--mp-syn-fn`, `--mp-syn-attr`. They switch with the palette, so one rule works in light and dark.

Raw HTML in a document is shown, but scripts, event handlers and `javascript:` links are removed before rendering.

Elements use plain HTML tags (`h1`…`h6`, `p`, `blockquote`, `pre`, `code`, `table`, `ul`, `ol`, `img`). Tables are wrapped in `.mp-table`, the front matter table has the class `mp-frontmatter`, and the whole document sits in `.mp-content`.

## Sharing themes

A theme is one small JSON file with the `.markpeektheme` extension. To share one:

- Right-click a theme in the sidebar and choose **Export…**, or use **Theme ▸ Export Active Theme…**.
- To install, double-click the file, drop it on the MarkPeek window, or use **Theme ▸ Import Theme…**.
- **Theme ▸ Show Themes Folder in Finder** opens the folder where your themes are stored. Files you copy in there appear in the sidebar.

Your own themes save automatically as you edit them.

## Editing the file by hand

Any text editor works. Keys you leave out keep their defaults, so a minimal theme can be tiny:

```json
{
  "name": "Just Bigger",
  "typography": { "fontSize": 19, "lineHeight": 1.7 }
}
```

The main sections and their most useful keys:

| Section | Keys |
|---|---|
| `typography` | `bodyFont`, `headingFont`, `codeFont`, `fontSize`, `lineHeight`, `paragraphSpacing`, `headingWeight`, `headingScale`, `headingSpacing`, `codeFontSize`, `textAlignment`, `hyphenate` |
| `layout` | `maxWidth`, `pagePadding`, `sidePadding`, `codeBlockPadding`, `cornerRadius`, `listIndent`, `tableCellPadding`, `imageMaxWidth`, `blockquoteBorderWidth` |
| `elements` | `headingUnderline`, `headingNumbering`, `codeHighlighting`, `codeShowLanguage`, `codeWrapLines`, `codeLineNumbers`, `listMarker`, `tableBorders`, `tableStriped`, `imageRounded`, `imageShadow`, `imageCentered`, `linkUnderline`, `blockquoteItalic`, `dropCap`, `ruleStyle`, `frontMatter` |
| `light`, `dark` | `background`, `text`, `heading`, `link`, `codeBackground`, `codeText`, `blockquoteText`, `blockquoteBorder`, `rule`, `tableBorder`, `tableHeaderBackground`, `tableStripe`, `accent`, `muted`, `syntax` |
| top level | `name`, `author`, `appearance` (`system`, `light`, `dark`), `customCSS` |

Colors are hex strings such as `"#1F2328"`. Sizes are numbers: pixels for `fontSize`, `maxWidth` and the paddings, and em units for spacing and indents.

## Where themes apply

- **This window**, in every mode.
- **Quick Look**: press Space on a Markdown file in Finder. It uses the active theme.
- **Export as PDF** and **Export as HTML** use the active theme too, so the file looks exactly like the preview. Choose light or dark for the export in the export sheet.
