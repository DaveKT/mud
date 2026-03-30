Plan: Down Mode Layout
===============================================================================

> Status: Complete


## Context

Down Mode rendered raw Markdown source as a syntax-highlighted HTML table with
one `<tr>` per source line. This table-based layout had several problems
visible when horizontally scrolling:

1. **Code fence lines overlay line numbers** — the `opacity: 0.5` on fence
   `<td>` cells paints over the sticky `.ln` column when scrolled
2. **Code block backgrounds end at viewport width** — the `<td>` background
   doesn't extend into the overflow area, so scrolling right reveals bare
   background
3. **Overscroll hack** — `overscroll-behavior-x: none` is required to prevent
   elastic bounce from detaching sticky line numbers
4. **Word wrap affects code blocks** — when word-wrap is on, code block content
   wraps too; ideally code blocks would scroll independently

Problems 1, 2, and 4 stemmed from the line-by-line table structure that
prevented grouping consecutive code lines into a scrollable container. Problem
3 is inherent to `position: sticky` inside horizontal scroll containers during
elastic overscroll — `overscroll-behavior-x: none` is the correct CSS property
for this, not a hack.


## Approach: div-based lines with scrollable code regions

Replace the `<table>` with `<div>`-based flex rows. Entire code blocks (fences
and content) are grouped inside a `.dc-scroll` wrapper.


### HTML structure

Each line is a `.dl` div with `.ln` and `.lc` spans. Code blocks (fences +
content lines) are grouped inside a `.dc-scroll` wrapper. Lines carry role
classes: `.dc-fence` for fence delimiters, `.dc-code` for code content. See
`DownHTMLVisitor.swift` for the generated structure.


### How this solves each problem

| Problem                      | Solution                                                                                                                                                                    |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Fence over line numbers   | `.dl` is `display: flex`; `.ln` gets `z-index: 2` — works reliably on flex children unlike table cells. Fence dimming applies to `.dc-fence .lc` only, not the line number. |
| 2. Code-bg stops at viewport | Code-bg is on `.dc-fence .lc` and `.dc-code .lc`. `.dc-scroll` is `display: grid`, so all children share the same column-track width (the widest code line).                |
| 3. Overscroll hack           | Unchanged. `overscroll-behavior-x: none` on `.down-mode-output` and (when active) `.dc-scroll`.                                                                             |
| 4. Word wrap + code          | Word-wrap rule targets `.dl:not(.dc-code) .lc` only. When word-wrap is on, `.dc-scroll` gets `overflow-x: auto` and code blocks scroll independently.                       |


### Word-wrap–conditional scroll behavior

**Word-wrap off:** `min-width: max-content` on `.down-lines` grows the entire
container to fit the widest content (code or non-code). All lines share the
same width. Single horizontal scroll context on `.down-mode-output`. All `.ln`
elements are sticky relative to the same scroll container. Line numbers always
form a solid column.

**Word-wrap on:** non-code content wraps, so `.down-mode-output` has no
horizontal scroll. `.dc-scroll` gets `overflow-x: auto` — code blocks scroll
independently within their own container. `.dc-code` gets
`min-width: max-content` to trigger the scroll. The grid layout on `.dc-scroll`
ensures fence lines stretch to match the widest code line. Code `.ln` elements
are sticky within `.dc-scroll`; non-code `.ln` sit at the left edge. Both land
at the same position because the outer container has no horizontal offset.


### Line number column consistency

All `.ln` elements use the same background (`color-mix(…)`) regardless of
whether they're inside a code block. This preserves the visual illusion of a
single solid line-number column. Code-bg is applied to `.lc` elements (not the
row or `.ln`), so it only appears in the content area.

Flex `stretch` (the default) ensures `.ln` background covers the full row
height when `.lc` wraps to multiple visual lines.


## What was implemented

### 1. `DownHTMLVisitor.swift` — three-phase pipeline

Restructured from a monolithic `applyEventsAsTable` into three phases:
`EventCollector` (AST → span events + code block info), `renderLineContent()`
(span events → per-line HTML strings), and `buildLayout()` (line roles →
structural div/flex HTML with `.dc-scroll` groups). Public method renamed
`highlightAsTable` → `highlight`.


### 2. `HTMLTemplate.swift`

Renamed `wrapDown(tableHTML:options:)` → `wrapDown(bodyHTML:options:)`.


### 3. `MudCore.swift`

Updated `renderDownToHTML` and `renderDownModeDocument` to use renamed methods.


### 4. `mud-down.css` — rewrite

Replaced table styles with flex rows (`.dl`), sticky line numbers with
`z-index`, grid-based `.dc-scroll` containers, and word-wrap–conditional
overflow. See the committed file for details.


### 5. `mud.js`

`scrollToLine` selector updated from `table.down-lines tr` to
`.down-lines .dl`.


### 6. Tests

Updated all assertions for div-based structure; added layout-specific cases for
fenced, empty fenced, and indented code blocks.


## Files modified

- `Core/Sources/Core/Rendering/DownHTMLVisitor.swift`
- `Core/Sources/Core/Resources/mud-down.css`
- `Core/Sources/Core/Resources/mud.js`
- `Core/Sources/Core/Rendering/HTMLTemplate.swift`
- `Core/Sources/Core/MudCore.swift`
- `Core/Tests/Core/DownHTMLVisitorTests.swift`
- `Core/Tests/Core/HTMLTemplateTests.swift`


## Verification

Build and test in Xcode. Then manually verify:

- [ ] Horizontal scroll: line numbers stay visible, no overlay artifacts
- [ ] Code block backgrounds extend through full scroll width
- [ ] Word wrap on: regular text wraps, code blocks scroll independently
- [ ] Word wrap off: entire document scrolls horizontally as a unit
- [ ] Line numbers on/off toggle
- [ ] Readable column toggle
- [ ] Zoom in/out
- [ ] Find (Cmd+F) highlights in both regular text and code blocks
- [ ] Find scrolls to matches inside code blocks (horizontal auto-scroll)
- [ ] Outline sidebar → scroll-to-line works
- [ ] All four themes, light and dark
- [ ] Print / Save as PDF
- [ ] Indented code blocks (no fences)
- [ ] Empty fenced code blocks
