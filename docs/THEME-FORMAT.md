# MarkPeek theme format

A theme is a single **JSON** file with the `.markpeektheme` extension (plain UTF-8 text, no scripting). It controls
everything about how Markdown is displayed: in the app, in Finder's Quick Look
previews, and in exported PDFs.

## Installing a theme

Any of these installs a theme into **My Themes**:

- Double-click the `.markpeektheme` file in Finder.
- Drop the file onto the MarkPeek window.
- Use **Theme ▸ Import Theme…** (or the **+** button at the bottom of the sidebar).
- Copy the file into the themes folder (**Theme ▸ Show Themes Folder in Finder**):
  `~/Library/Group Containers/YJ3UZ772GP.com.markpeek.app.shared/Themes/`

Exporting is the reverse: right-click a theme in the sidebar and choose
**Export…**, or use **Theme ▸ Export Active Theme…**.

## Editing

Open the theme inspector (⌥⌘I) to change any value with a live preview.
Edits to your own themes save automatically. Edits to a built-in theme show
as *Edited* until you **Save As…** a new theme or **Revert**.

You can also edit the JSON by hand. Missing keys fall back to their defaults,
so a minimal file only needs what you want to change:

```json
{
  "name": "Just Bigger",
  "typography": { "fontSize": 19, "lineHeight": 1.7 }
}
```

## Reference

| Key | Type | Default | Notes |
|---|---|---|---|
| `formatVersion` | int | 2 | Written by the app |
| `id` | UUID string | random | Identity; built-in ids are reserved |
| `name` | string | | Shown in the sidebar |
| `author` | string | "" | |
| `appearance` | `system` / `light` / `dark` | `system` | Which palette previews use |
| `customCSS` | string | "" | Appended after the generated stylesheet |

### `typography`

| Key | Default | Notes |
|---|---|---|
| `bodyFont` | `-apple-system` | Family name, or `-apple-system`, `ui-serif`, `ui-rounded`, `SF Mono` |
| `headingFont` | "" | Empty = same as body |
| `codeFont` | `SF Mono` | |
| `fontSize` | 16 | px |
| `lineHeight` | 1.6 | unitless |
| `paragraphSpacing` | 1.0 | em |
| `headingWeight` | 700 | 400–800 |
| `headingScale` | 1.25 | Size ratio between heading levels (h3 = scale, h2 = scale², h1 = scale³) |
| `headingSpacing` | 1.5 | em above headings |
| `codeFontSize` | 0.9 | em, relative to body |
| `textAlignment` | `leading` | or `justified` |
| `hyphenate` | false | |

### `layout`

| Key | Default | Notes |
|---|---|---|
| `maxWidth` | 700 | px; 0 = full width |
| `pagePadding` | 40 | px top and bottom |
| `sidePadding` | 24 | px left and right |
| `codeBlockPadding` | 16 | px |
| `cornerRadius` | 6 | px; code blocks, images, tables |
| `listIndent` | 1.6 | em |
| `tableCellPadding` | 8 | px |
| `imageMaxWidth` | 100 | percent of content width |
| `blockquoteBorderWidth` | 4 | px |

### `elements`

| Key | Default | Notes |
|---|---|---|
| `headingUnderline` | false | Rule under h1 and h2 |
| `headingNumbering` | `off` | `h2` numbers sections, `h3` also subsections |
| `blockquoteItalic` | false | |
| `linkUnderline` | false | |
| `codeShowLanguage` | true | Language badge on fenced blocks |
| `codeWrapLines` | false | |
| `codeLineNumbers` | false | |
| `codeHighlighting` | true | Syntax colors for fenced blocks with a known language (Swift, JS/TS, Python, Go, Rust, C-family, Java/Kotlin, Ruby, shell, PHP, SQL, JSON, YAML, TOML, HTML/XML, CSS) |
| `tableStriped` | true | |
| `tableBorders` | `horizontal` | `all`, `horizontal`, `none` |
| `imageRounded` | true | |
| `imageShadow` | false | |
| `imageCentered` | false | Centers paragraphs that contain only an image |
| `listMarker` | `disc` | `disc`, `circle`, `square`, `dash` |
| `ruleStyle` | `line` | `line`, `short`, `dots` |
| `dropCap` | false | First letter of the first paragraph |
| `frontMatter` | `table` | Leading YAML block: `table`, `hidden`, or `raw` |

### `light` and `dark` palettes

Hex colors. Keys: `background`, `text`, `heading`, `link`, `codeBackground`,
`codeText`, `blockquoteText`, `blockquoteBorder`, `rule`, `tableBorder`,
`tableHeaderBackground`, `tableStripe`, `accent`, `muted`, and a `syntax`
object with `keyword`, `string`, `comment`, `number`, `type`, `function`,
`attribute`. When `syntax` is omitted, readable defaults are chosen for the
palette's background (light or dark).

Every color is exposed to custom CSS as a variable:

```
--mp-bg  --mp-text  --mp-heading  --mp-link  --mp-code-bg  --mp-code-text
--mp-quote-text  --mp-quote-border  --mp-rule  --mp-table-border
--mp-table-head  --mp-table-stripe  --mp-accent  --mp-muted
--mp-syn-kw  --mp-syn-str  --mp-syn-cm  --mp-syn-num  --mp-syn-type  --mp-syn-fn  --mp-syn-attr
```

Highlighted tokens are `span.tok-kw`, `.tok-str`, `.tok-cm`, `.tok-num`,
`.tok-type`, `.tok-fn`, `.tok-attr`.

### Generated HTML

The renderer emits plain semantic HTML inside `<article class="mp-content">`:
`h1`–`h6` (with id anchors), `p`, `blockquote`, `ul`/`ol`/`li` (`li.task` for
task items), `pre > code` (`pre[data-lang]`, `pre.mp-ln` with `.line` spans when
line numbers are on), `div.mp-table > table`, `img`, `hr`, `a`, `strong`, `em`,
`del`, `code`. Target these from `customCSS`.

See `docs/themes/Dusk.markpeektheme` for a worked example (keys it leaves out take their defaults).
