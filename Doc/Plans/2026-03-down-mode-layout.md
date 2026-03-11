Plan: Down Mode Layout
===============================================================================

> Status: Planning


## Context

Down Mode renders raw Markdown source as a syntax-highlighted HTML table with
one `<tr>` per source line. This table-based layout has several problems
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

These all stem from the line-by-line table structure that prevents grouping
consecutive code lines into a scrollable container.


## Approach: div-based lines with scrollable code regions

Replace the `<table>` with a `<div>`-based structure. Each line becomes a flex
row. Consecutive code-block content lines are grouped inside a scrollable
wrapper `<div>`.


### New HTML structure

````html
<div class="down-lines">
  <!-- Regular lines -->
  <div class="dl"><span class="ln">1</span><span class="lc">text</span></div>

  <!-- Code fence (opening) -->
  <div class="dl dc-fence"><span class="ln">5</span><span class="lc"><span class="md-code-fence">```python</span></span></div>

  <!-- Scrollable code region -->
  <div class="dc-scroll">
    <div class="dl dc-code"><span class="ln">6</span><span class="lc"><span class="md-code-block">import os</span></span></div>
    <div class="dl dc-code"><span class="ln">7</span><span class="lc"><span class="md-code-block">print("hello")</span></span></div>
  </div>

  <!-- Code fence (closing) -->
  <div class="dl dc-fence"><span class="ln">9</span><span class="lc"><span class="md-code-fence">```</span></span></div>
</div>
````


### How this solves each problem

| Problem                      | Solution                                                                                                                                                                      |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Fence over line numbers   | `.dl` is `display: flex`; `.ln` gets `z-index: 2` — works reliably on flex children unlike table cells. Fence dimming applies to `.dc-fence .lc` only, not the line number.   |
| 2. Code-bg stops at viewport | `.dc-scroll` has `background: var(--code-bg)` and its own `overflow-x: auto`, so background fills the scrollable area naturally.                                              |
| 3. Overscroll hack           | Not solved by the layout change. `overscroll-behavior-x: none` is still needed on any scroll container with sticky children. Applied to `.down-mode-output` and `.dc-scroll`. |
| 4. Word wrap + code          | Word-wrap rule targets `.dl:not(.dc-code) .lc` only. Code lines inside `.dc-scroll` always use `white-space: pre` and scroll independently.                                   |


### Word-wrap–conditional scroll on `.dc-scroll`

When word-wrap is **off**, the entire document scrolls horizontally as a unit.
Making `.dc-scroll` an independent scroll container in this state would create
confusing nested horizontal scrolling (document vs. code block). Instead,
`.dc-scroll` only activates its own scroll when word-wrap is **on**:

```css
/* Word-wrap OFF: code blocks participate in document-level scroll */
html:not(.has-word-wrap) .dc-scroll {
  overflow-x: visible;
  min-width: max-content;  /* grow to fit content so code-bg extends */
}

/* Word-wrap ON: code blocks scroll independently */
.has-word-wrap .dc-scroll {
  overflow-x: auto;
  overscroll-behavior-x: none;
}
```

When word-wrap is off, `min-width: max-content` makes the `.dc-scroll` div grow
to the width of its widest line. This ensures `background: var(--code-bg)`
extends to cover all content, solving problem 2 in both word-wrap states.


### Line number column consistency

All `.ln` elements use the same background (`color-mix(…)`) regardless of
whether they're inside a code block or not. This preserves the visual illusion
of a single solid line-number column. The `.dc-scroll` background
(`var(--code-bg)`) shows through in the `.lc` content area but is painted over
by each `.ln`'s own background.

When word-wrap is **on**, `.dc-scroll` becomes its own scroll container, so its
`.ln` elements are sticky relative to `.dc-scroll` rather than the outer
container. However, this causes no misalignment: with word-wrap on, all
non-code content wraps, so the outer container has no horizontal scroll offset.
Both sets of `.ln` elements land at the same left edge.

When word-wrap is **off**, `.dc-scroll` has `overflow-x: visible` and is _not_
a scroll container. All `.ln` elements (inside and outside code blocks) are
sticky relative to the same ancestor (`.down-mode-output`). Perfect alignment.


## Implementation

### 1. `DownHTMLVisitor.swift` — restructure into a three-phase pipeline

The current `applyEventsAsTable` mixes too many concerns: structural HTML
layout, span-event application, highlight.js substitution, and line iteration.
Adding code-block grouping would make it worse. Restructure as three clean
phases:

```
Phase 1 (existing): AST → EventCollector → (events, codeBlocks)
Phase 2 (new):      events + sourceLines + codeBlocks → [String]   (per-line HTML content)
Phase 3 (new):      [String] + codeBlocks → String                 (structural layout)
```

**Phase 1: `EventCollector`** — stays mostly as-is. One change: enrich
`CodeBlockInfo` with an `isFenced: Bool` flag so Phase 3 can distinguish fenced
from indented blocks. Also always create a `CodeBlockInfo` for empty fenced
blocks (where `contentFirstLine > contentLastLine`) so their fence lines are
captured.

**Phase 2: `renderLineContent()`** — extracted from the current
`applyEventsAsTable` loop body. For each source line, produce the inner HTML
string: apply span events at their column positions (segment-by-segment
escaping), substitute highlight.js output for code-block content lines, manage
the span carry-over stack across line boundaries. Output: `[String]`, one entry
per source line. Knows nothing about divs, line numbers, or layout.

**Phase 3: `buildLayout()`** — new. Takes the rendered content strings + code
block metadata, produces the final structural HTML:

- Outer wrapper: `<div class="down-lines">`

- Each line:
  `<div class="dl"><span class="ln">N</span><span class="lc">…</span></div>`

- Iterates `codeBlocks` to classify lines and emit structural wrappers:

  - Before `contentFirstLine`, emit `<div class="dc-scroll">`
  - After `contentLastLine`, emit `</div>`
  - Code content lines get class `dc-code` on their `.dl`
  - If `isFenced`, lines at `contentFirstLine - 1` and `contentLastLine + 1`
    get class `dc-fence`

- For indented code blocks (`isFenced == false`): `.dc-scroll` wrapper with
  `.dc-code` lines, no `.dc-fence`

- Empty fenced code blocks: two `.dc-fence` lines, no `.dc-scroll` wrapper

This phase is straightforward to read because it only deals with structure, not
content rendering.

Rename the public method `highlightAsTable` → `highlight`.

All three phases remain private types/methods within `DownHTMLVisitor` — no new
files needed. The public API stays a single method.


### 2. `HTMLTemplate.swift` — rename parameter

Rename `wrapDown(tableHTML:options:)` → `wrapDown(bodyHTML:options:)`.


### 3. `MudCore.swift` — update call sites

Update `renderDownToHTML` and `renderDownModeDocument` to use the renamed
methods.


### 4. `mud-down.css` — rewrite layout

```css
/* Container */
.down-mode-output {
  margin: 0 auto;
  box-sizing: content-box;
  background: var(--bg-color);
  overflow-x: auto;
  overscroll-behavior-x: none;
}

.is-readable-column .down-mode-output {
  max-width: calc(800px + 4em);
}

/* Line container */
.down-lines {
  font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
  font-size: 0.875em;
  line-height: 1.6;
  padding-top: 2rem;
  padding-bottom: 2rem;
}

/* Each line: flex row (stretch is the default — ensures .ln background
   covers the full row height when .lc wraps to multiple visual lines) */
.dl {
  display: flex;
}

/* Line numbers */
.ln {
  position: sticky;
  left: 0;
  z-index: 2;
  flex: 0 0 4em;
  padding-right: 1em;
  text-align: right;
  font-size: 0.85em;
  font-weight: 300;
  user-select: none;
  -webkit-user-select: none;
  white-space: nowrap;
  background: color-mix(in srgb, var(--code-bg), var(--bg-color));
  color: color-mix(in srgb, var(--blockquote-color), var(--bg-color));
  line-height: 1.7;
}

/* Line content */
.lc {
  flex: 1 1 auto;
  white-space: pre;
  padding: 0 1em;
  min-width: 0;
}

/* Word wrap — excludes code lines */
.has-word-wrap .dl:not(.dc-code) .lc {
  white-space: pre-wrap;
  overflow-wrap: break-word;
}

/* Hide line numbers */
html:not(.has-line-numbers) .ln {
  visibility: hidden;
  flex-basis: 0;
  width: 0;
  padding: 0;
}

/* Code fence lines — content dimmed, line number untouched */
.dc-fence {
  background: var(--code-bg);
}
.dc-fence .lc {
  opacity: 0.5;
}

/* Scrollable code block wrapper */
.dc-scroll {
  background: var(--code-bg);
}

/* Word-wrap OFF: code blocks participate in document-level scroll */
html:not(.has-word-wrap) .dc-scroll {
  overflow-x: visible;
  min-width: max-content;
}

/* Word-wrap ON: code blocks scroll independently */
.has-word-wrap .dc-scroll {
  overflow-x: auto;
  overscroll-behavior-x: none;
}
```

Syntax highlighting class rules (`.md-heading`, `.md-code-block`, etc.) stay
unchanged.


### 5. `mud.js` — update `scrollToLine`

```javascript
function scrollToLine(lineNumber) {
  var lines = document.querySelectorAll(".down-lines .dl");
  var idx = lineNumber - 1;
  if (idx >= 0 && idx < lines.length) {
    lines[idx].scrollIntoView({ behavior: "smooth", block: "start" });
  }
}
```


### 6. `DownHTMLVisitorTests.swift` — update assertions

- `lineCount` helper: count `class="dl"` occurrences instead of `<tr>`
- `wrappedInTable` → `wrappedInContainer`: check for `<div class="down-lines">`
  prefix and `</div>` suffix
- Line number assertions: `<span class="ln">` instead of `<td class="ln">`
- Add tests for code block structure: verify `.dc-scroll` wrapper, `.dc-fence`
  and `.dc-code` classes


## Files to modify

- `Core/Sources/Core/Rendering/DownHTMLVisitor.swift` — HTML generation
- `Core/Sources/Core/Resources/mud-down.css` — layout styles
- `Core/Sources/Core/Resources/mud.js` — `scrollToLine` selector
- `Core/Sources/Core/Rendering/HTMLTemplate.swift` — parameter rename
- `Core/Sources/Core/MudCore.swift` — call site updates
- `Core/Tests/Core/DownHTMLVisitorTests.swift` — test updates


## Edge cases

- **Empty code blocks** (fences with no content): two `.dc-fence` lines, no
  `.dc-scroll` wrapper
- **Indented code blocks**: `.dc-scroll` wrapper with `.dc-code` lines, no
  `.dc-fence` lines
- **Adjacent code blocks**: each gets its own `.dc-scroll` wrapper
- **Print**: add `@media print { .dc-scroll { overflow-x: visible; } }` so code
  isn't clipped


## Verification

Build and test in Xcode. Then manually verify:

- [ ] Horizontal scroll: line numbers stay visible, no overlay artifacts
- [ ] Code block backgrounds extend through full scroll width
- [ ] Word wrap on: regular text wraps, code blocks scroll independently
- [ ] Word wrap off: entire document scrolls horizontally
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
