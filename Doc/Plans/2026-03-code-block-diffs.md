Plan: Code Block Diffs
===============================================================================

> Status: Planning


## Overview

Enhance the track-changes feature to show **line-level diffs within code
blocks** in Up mode. Currently, a changed code block is a single leaf block —
if one line changes in a 50-line block, the entire block is marked as
inserted/deleted. This plan adds line-granularity: unchanged lines render
normally, changed lines get insertion/deletion markers, and each cluster of
consecutive changes forms its own navigable group with an overlay badge.

Mermaid code blocks get special handling: only the new diagram is shown, with a
mixed-change overlay. No line-level diff (the rendered SVG can't be
meaningfully diffed).


## Design goals

1. **Line-level precision** — individual changed lines within a code block are
   highlighted, not the whole block.
2. **Per-group navigation** — each cluster of consecutive changed lines is a
   separate sidebar entry with its own overlay badge. Independent reveal.
3. **Visual consistency** — diffed and non-diffed code blocks look identical
   for unchanged lines. Same syntax highlighting, same structure.
4. **Hide-until-revealed** — deleted code lines are hidden by default, matching
   the existing deletion behavior. One click reveals all deleted lines in a
   group.
5. **Mermaid** — suppress old diagrams entirely. Show only the new diagram with
   a mixed overlay.


## HTML structure

### Diffed code block

When a code block has line-level diff data, `UpHTMLVisitor` emits line-wrapped
structure inside the `<code>` element:

```html
<pre class="mud-code mud-code-diff">
  <div class="code-header">
    <span class="code-language">swift</span>
  </div>
  <code class="language-swift"><span class="cl">func greet() {
</span><span class="cl cl-del" data-change-id="change-5" data-group-id="group-3" data-group-index="3">    print("hello " + name)
</span><span class="cl cl-ins" data-change-id="change-6" data-group-id="group-3" data-group-index="3">    print("hello \(name)")
</span><span class="cl">    return true
</span><span class="cl cl-ins" data-change-id="change-7" data-group-id="group-4" data-group-index="4">    log("greeted")
</span><span class="cl">}
</span></code>
</pre>
```

Key points:

- **`mud-code-diff`** class on the `<pre>` signals that this code block
  contains line-level changes. The `<pre>` itself has no `data-change-id` — the
  individual line spans do.
- **`<span class="cl">`** wraps every line (including unchanged). Inside
  `<pre>`, these inline spans preserve whitespace and newlines naturally. The
  `cl` class adds no visual properties — it's a structural wrapper.
- **`cl-del`** lines are hidden via CSS (`display: none`). When the group's
  expando button is clicked, `mud-change-revealed` is added and they become
  visible (`display: inline`).
- **`cl-ins`** lines are always visible with a green tint.
- Each line span contains **pre-highlighted HTML** (syntax-highlighted
  server-side by `CodeHighlighter`). The `\n` at the end of each span is the
  literal newline that creates the visual line break inside `<pre>`. The `\n`
  must be the **last character inside the span** (not between spans), so that
  `textContent` extraction and selection behavior are correct.


### Non-diffed code block (unchanged)

No structural change:

```html
<pre class="mud-code">
  <code class="language-swift">highlighted content blob</code>
</pre>
```


### Visual consistency

Both paths use `CodeHighlighter.highlight()` for syntax highlighting. The only
difference is that diffed code blocks split the highlighted output into
per-line `<span class="cl">` wrappers. Since `cl` is an inline element with no
default styling, and `<pre>` preserves whitespace, the visual output is
identical for unchanged content.

When highlight.js emits spans that cross line boundaries (e.g., multi-line
strings or comments), the split function closes and reopens them at `\n`
boundaries. The visual result is the same — same CSS classes, same content —
just more elements.


## Syntax highlighting: highlight then split

Highlight the entire code block as a single unit (preserving full syntactic
context), then split the highlighted HTML into per-line strings:

```
1. CodeHighlighter.highlight(code, language: lang) → highlighted HTML string
2. splitHighlightedLines(html) → [String]
   - Scan for \n characters in the text content (not inside tags)
   - Track open <span> tags (class stack)
   - At each \n: include the \n in the current line's text content, then
     close all open spans. The resulting line string ends with \n as its
     last text character, followed only by </span> close tags.
     Start the next line by reopening all spans from the class stack.
   - Result: array of self-contained highlighted HTML strings, one per line
```

This is applied to both old and new code block content independently. Each gets
fully highlighted, then split into lines. The line-level diff operates on the
**raw source lines** (not highlighted HTML) for matching, and the highlighted
lines are used for rendering.

Fallback: if `CodeHighlighter` returns nil (unknown language), use HTML-escaped
plain text split by newlines. No span tracking needed.


## Diff computation

### Line-level diff within a code block pair

When `DiffContext` encounters a paired code block (deletion + insertion in the
same gap):

1. Extract content from both: `oldBlock.code` and `newBlock.code` (the
   `CodeBlock.code` property gives content without fences).
2. Split into lines.
3. Run `CollectionDifference` on the line arrays to produce unchanged /
   inserted / deleted classifications.
4. Cluster consecutive changed lines into **line groups** (same logic as
   block-level grouping: consecutive changes with no unchanged line between
   them form a group).
5. Assign a change ID to each line group (participates in the global
   `changeCounter` sequence).
6. Assign group IDs to each line group (participates in the global group
   sequence).
7. For each line group, determine type: pure insertion (green), pure deletion
   (red), or mixed (blue).


### Result type

```swift
struct CodeBlockDiff {
  let lines: [CodeLine]
  // Indexed by line position in the interleaved output.
  // Ordering rule: within each gap (cluster of consecutive
  // changes), all deleted lines come before all inserted lines.
  // This matches the block-level convention where deletions
  // precede insertions.

  struct CodeLine {
    let highlightedHTML: String  // Pre-highlighted line content
    let annotation: Annotation
    let changeID: String?       // nil for unchanged lines
    let groupID: String?
    let groupIndex: Int?
  }

  enum Annotation {
    case unchanged
    case inserted
    case deleted
  }
}
```


### Fallback to block-level

If the line-level diff of content shows **no changes** (e.g., only the language
tag or fence style changed), fall back to block-level handling — the whole code
block is marked as a single change, as today.


### Integration with DiffContext

New field: `codeBlockDiffMap: [SourceKey: CodeBlockDiff]` — keyed by the new
code block's source key. When `DiffContext` encounters a paired code block, it
populates this map instead of (not in addition to) the block-level change
entry.

The paired code block's deletion is **not** added to `precedingDeletionMap`.
Its insertion is **not** added to the annotation map. Instead, the code block
is "neutral" at the block level — `annotation(for:)` returns nil — but carries
line-level diff data in `codeBlockDiffMap`.

**Interaction with preceding deletions from other blocks:** When
`changeAttributes(for:)` is called on a code block with a line diff, it returns
nil (no block-level annotation). But `emitPrecedingDeletions()` is a side
effect of `changeAttributes()` — it still fires and emits any non-code-block
deletions that precede this code block. Only the code block's own paired
deletion is suppressed from `precedingDeletionMap`. Other deletions (e.g., a
deleted paragraph before the code block) flow through the normal path
unaffected.

New API:

```swift
func codeBlockDiff(for node: Markup) -> CodeBlockDiff?
```

`UpHTMLVisitor.visitCodeBlock()` calls this. If non-nil, uses the line-level
rendering path. If nil, uses the existing block-level path.


### Change IDs and grouping

Line groups within a code block participate in the global change ID and group
ID sequences. If blocks before the code block use change-1 through change-4
(groups 1-2), the first line group in the code block gets change-5 (group 3),
etc.

**Assignment timing:** Line group change IDs are assigned within
`finalizeGap()`, at the point where the code block pair is detected. The
`changeCounter` increments by N (one per line group) instead of the usual 2
(one for the deletion, one for the insertion). A single code block modification
with scattered changes could consume many change IDs, affecting downstream
badge numbers. This is intentional — each line group is a navigable change.

**Group break at code block boundaries:** a code block's line groups are always
separate from adjacent block-level changes, even if they're consecutive in
document order. The code block boundary forces a group break.


## Sidebar representation

Each line group within a changed code block produces one `DocumentChange`
entry. The sidebar groups them via `ChangeGroup.build(from:)` as usual.

**How `ChangeList.computeChanges()` handles this:** `computeChanges()` walks
new blocks and checks `annotation(for:)`. For a code block with line diffs,
`annotation(for:)` returns nil. So the walker adds a second check: if
`codeBlockDiff(for:)` returns non-nil, emit `DocumentChange` entries for each
line group in the `CodeBlockDiff`. Each line group produces one entry with its
own change ID, group ID, and summary. The walker then continues to the next
block — it does not descend into sub-block structure.

Summary text: the first changed line's content (truncated). If the group has
multiple changes, the count badge `"(N)"` appears as with other groups.

Icon: same logic as block-level groups — green plus for pure insertion, red
minus for pure deletion, blue pencil for mixed.


## Overlay and JS interaction

### Overlay discovery

`buildOverlays()` discovers groups from `[data-group-id]` attributes. Code
block line spans have these attributes, so they're discovered automatically.
Each line group gets its own overlay, positioned to cover just those lines
within the code block.


### Positioning

`positionOverlay()` uses `getBoundingClientRect()` to measure elements. For
inline `<span class="cl">` elements inside `<pre><code>`,
`getBoundingClientRect` returns the visual extent of the line content. This
already works — the existing code uses `getBoundingClientRect`, not
`offsetTop`/ `offsetHeight` (which would be unreliable for inline elements).
The overlay spans from the first to last element in the group — covering just
the relevant lines, not the whole code block.


### Expand / collapse

The existing expando system works as-is:

- **Insertion-only line groups:** always expanded, button disabled. Green
  overlay covers the inserted lines.
- **Deletion-only line groups:** start collapsed. Button click adds
  `mud-change-revealed` to the `cl-del` spans, making them visible. Red overlay
  covers the deleted lines (which are now visible).
- **Mixed line groups:** start collapsed (insertions visible, deletions
  hidden). Button click reveals deletions and splits into sub-overlays
  (red/green runs).


### Collapsed deletion positioning

For collapsed del-only groups within a code block: `positionCollapsedOverlay()`
finds the previous visible sibling. Inside `<code>`, the previous sibling is
the preceding `<span class="cl">` line. The overlay button appears at that gap.


### Potential JS adjustments

- **`positionOverlay`** — verify that `getBoundingClientRect()` returns correct
  rects for inline `<span>` elements inside `<pre>`. If a span wraps to
  multiple visual lines (shouldn't happen with our line-per-span structure, but
  edge case), the rect might be unexpectedly tall. Test and adjust.
- **Copy-code button** (`copy-code.js`): currently copies `code.textContent`.
  For diffed code blocks (detected via
  `pre.classList.contains('mud-code-diff')`), switch to
  `querySelectorAll('.cl:not(.cl-del)')` and join their `textContent`. Copy
  should **always give the new code**, regardless of reveal state — copying a
  mix of old and new lines produces broken code.


## Mermaid code blocks

### Detection

Check `CodeBlock.language == "mermaid"` when processing paired code blocks in
`DiffContext`.


### Behavior

- **No line-level diff.** Mermaid source changes produce a new diagram — line
  diffs of the source aren't useful in Up mode (Down mode already shows them).
- **Suppress the deletion.** Don't add the old mermaid block to
  `precedingDeletionMap`. Don't render an old hidden diagram.
- **Mark the insertion as mixed.** The new code block gets `mud-change-ins` and
  the overlay type is forced to `mix` (blue), since it's really a modification.
  One sidebar entry, one overlay badge.


### Attribute preservation through mermaid-init.js

`mermaid-init.js` currently replaces `<pre>` with `<div class="mermaid">`
without copying data attributes. Update it to copy change-related attributes:

```javascript
var pre = code.parentElement;
if (!pre || pre.tagName !== "PRE") return;

var container = document.createElement("div");
container.className = "mermaid";

// Preserve change-tracking attributes
if (pre.dataset.changeId) {
  container.dataset.changeId = pre.dataset.changeId;
  container.dataset.groupId = pre.dataset.groupId;
  container.dataset.groupIndex = pre.dataset.groupIndex;
  // Copy change classes (mud-change-ins, mud-change-del, etc.)
  pre.classList.forEach(function (cls) {
    if (cls.startsWith("mud-change-")) container.classList.add(cls);
  });
}
```


### Preventing old mermaid diagram rendering

Even if we suppress the deletion in `DiffContext`, there's a safety concern: if
a deleted mermaid `<pre>` is ever emitted (e.g., from a code path we didn't
account for), `mermaid-init.js` should skip it:

```javascript
if (pre.classList.contains("mud-change-del")) return;
```


## CSS additions

```css
/* Code block line diff structure */
.mud-code-diff code {
  /* Ensure line spans work correctly inside pre */
}

.cl {
  /* No visual properties — structural wrapper only */
}

.cl.cl-del {
  display: none;
}

.cl.cl-del.mud-change-revealed {
  display: inline;
  text-decoration: line-through;
  opacity: 0.75;
}

.cl.cl-ins {
  /* Green tint background — reuse --change-ins variable */
  background: color-mix(in srgb, var(--change-ins) 12%, transparent);
}
```

This parallels the existing Down mode styles for `dl-ins` and `dl-del`, adapted
for inline spans within `<pre>`.


## Word-level diffs within code lines

**Deferred.** For the initial implementation, code block diffs are line-level
only. A future enhancement could pair deleted and inserted lines within a group
(first deleted with first inserted, etc.) and run word-level diff on them,
adding inline `<ins>` / `<del>` markers within the highlighted line content.
The `injectMarkers` machinery from Down mode can be reused for this.


## Edge cases

1. **Entirely new or deleted code block (no pair)** — block-level handling as
   today. No line-level diff.
2. **Small code block (1-3 lines)** — line-level diff still applies. If all
   lines changed, it degenerates to one group covering the whole block.
3. **Empty code block** — no content lines to diff. Fall back to block-level.
4. **Language changed, content identical** — line-level diff shows no changes.
   Fall back to block-level (whole block marked as changed).
5. **Indented code blocks** — treated the same as fenced. `CodeBlock` is the
   AST node for both.
6. **Code block within a blockquote** — should work: `UpHTMLVisitor` already
   handles blockquote content. The `<pre>` is inside the `<blockquote>`.
7. **Very large code blocks** — `CollectionDifference` is O(n*d) where d is the
   edit distance. For typical code blocks (< 200 lines) this is fast. No async
   needed.
8. **Whitespace-only line changes** — `CollectionDifference` compares by exact
   string match. Re-indentation of a code block lights up every affected line
   as a full delete+insert. Acceptable for v1 since word-level line diffs are
   deferred, but worth revisiting if re-indentation diffs prove noisy.
9. **Language tag changed** — If the language changed between old and new, the
   new language is displayed in the code header. Deleted lines are highlighted
   with the old language's syntax coloring, inserted lines with the new. This
   could look jarring (different colors for del vs ins lines) but is rare and
   correct.
10. **Trailing newline** — `CodeBlock.code` may include a trailing newline
    before the closing fence. Trim trailing empty lines from both old and new
    content before splitting, to avoid a phantom empty-line diff.


## Implementation sequence

1. **`splitHighlightedLines`** — utility function in Core to split highlighted
   HTML at newline boundaries, tracking and reopening open `<span>` tags.

2. **`CodeBlockDiff`** — new type in `Core/Sources/Core/Diff/`. Line-level diff
   computation using `CollectionDifference` on raw source lines. Line grouping
   within the code block (consecutive changed lines form a group).

3. **`DiffContext` integration** — detect code block pairs, compute
   `CodeBlockDiff`, populate `codeBlockDiffMap`. Suppress block-level entries
   for these pairs. Assign change IDs and group IDs from the global sequence.

4. **`UpHTMLVisitor` changes** — `visitCodeBlock()` checks
   `codeBlockDiff(for:)`. When present, emits line-span structure with
   pre-highlighted HTML. When absent, existing path.

5. **`ChangeList` changes** — emit `DocumentChange` entries for code block line
   groups.

6. **CSS** — `cl`, `cl-ins`, `cl-del` styles in `mud-changes.css`.

7. **JS: mermaid-init.js** — copy change attributes through `<pre>` → `<div>`
   replacement. Skip `mud-change-del` blocks.

8. **JS: copy-code.js** — filter hidden deleted lines from copy.

9. **Mermaid suppression** — `DiffContext` skips deletion for paired mermaid
   blocks, marks insertion as mixed.

10. **Testing and polish** — overlay positioning for in-code-block groups,
    collapsed button positioning, visual review.
