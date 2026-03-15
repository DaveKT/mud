Plan: Track Changes
===============================================================================

> Status: Planning


## Overview

Add a change-tracking feature to Mud. When a document is opened, its content is
snapshot as a "waypoint". On each subsequent reload (file change), the current
content is diffed against the waypoint at the block level and `<ins>`/ `<del>`
elements are injected into the rendered HTML (both Up and Down modes). A new
sidebar pane lists each change; selecting one scrolls to and highlights it.
Deletions are hidden unless selected.


## Concepts

**Waypoint** — a snapshot of the document content at a point in time, plus a
timestamp. Created automatically when the document is first opened, and
manually when the user clicks "Accept". Old waypoints are retained in memory
for a future waypoint-selector UI.

**Change** — a discrete insertion, deletion, or modification identified by the
diff engine. Each change has a unique ID that appears as a `data-change-id`
attribute in the HTML and as an entry in the sidebar list.

**Accept** — creates a new waypoint from the current content. The diff is
recomputed against the new waypoint (producing zero changes until the next file
modification).


## Data flow

The waypoint is an optional render option. When `RenderOptions.waypoint` is
set, MudCore computes the diff and injects change markers. When nil (the
default), rendering proceeds exactly as today. Print and Open in Browser build
their `RenderOptions` without a waypoint, so exported HTML never contains
change markers.

```mermaid
sequenceDiagram
    participant FW as FileWatcher
    participant DCV as DocumentContentView
    participant CT as ChangeTracker
    participant MC as MudCore
    participant WV as WebView

    Note over DCV: Document opened
    DCV->>CT: setInitialWaypoint(content, Date())
    DCV->>MC: render(content, opts.waypoint = nil)
    MC-->>WV: HTML (no changes)

    Note over FW: File modified on disk
    FW->>DCV: loadFromDisk()
    DCV->>CT: update(newContent)
    CT->>MC: computeChanges(old, new)
    MC-->>CT: [DocumentChange]
    Note over DCV: opts.waypoint = waypoint.content
    DCV->>MC: render(content, opts)
    MC-->>WV: HTML with <ins>/<del>
    CT-->>Sidebar: changes[] populates list

    Note over Sidebar: User clicks Accept
    Sidebar->>CT: accept()
    CT->>CT: pushWaypoint(currentContent, Date())
    CT->>MC: computeChanges → 0 changes
```


## Architecture

### Layer 1: Diff engine (MudCore)

The diff engine lives in MudCore because it needs AST access and integrates
with rendering. It has no UI dependencies.

**Leveraging `ParsedMarkdown` :** MudCore already has a `ParsedMarkdown` struct
(from the title-extraction work) that parses once and stores the `Document`
AST, headings, and source text. The diff engine works with `ParsedMarkdown`
values directly — `BlockMatcher` takes two `ParsedMarkdown` inputs and walks
their pre-parsed ASTs. No redundant parsing.

**New files in `Core/Sources/Core/Diff/` :**

- `BlockMatcher.swift` — given two `ParsedMarkdown` values (old and new), match
  leaf blocks between their ASTs. Two phases:

  1. **Fingerprint matching.** Flatten each AST into a list of leaf blocks
     (paragraphs, headings, code blocks, individual list items, table rows,
     blockquote paragraphs). Compute a content fingerprint (hash of source text
     within the block's range) for each. Run `CollectionDifference` on the
     fingerprint arrays to identify unchanged, inserted, and removed blocks.
     Source text (not plain text) so that formatting-only changes (e.g. `text`
     → `**text**`) are detected as modifications.

  2. **Modification detection.** Post-process the `CollectionDifference` output
     to pair removals and insertions at the same effective position. If
     old-index N was removed and new-index N was inserted (after accounting for
     prior offsets), merge them into a single `.modified(old, new)` match. This
     is a positional heuristic — simpler than content-similarity matching, but
     sufficient to detect in-place edits (the common case). Unpaired removals
     become `.deleted(old)`, unpaired insertions become `.inserted(new)`.

  Output is a `[BlockMatch]` list: `.unchanged(old, new)`,
  `.modified(old, new)`, `.inserted(new)`, or `.deleted(old)`. Each entry
  carries source ranges from the AST nodes for both rendering integration and
  line-range mapping (see Down mode below).

- `DiffContext.swift` — the bridge between diffing and rendering. Built from
  `BlockMatcher` output. Provides:

  - `annotation(for: Markup) -> BlockAnnotation?` — looked up by source range
    during AST walking. Annotation type is `.inserted`, `.deleted`, or
    `.modified` (content changed but block still exists).
  - `precedingDeletions(before: Markup) -> [RenderedDeletion]` — deleted and
    modified-old blocks that should appear before a given node, pre-rendered as
    HTML.

  The `DiffContext` is an optional input to the rendering functions. When
  `nil`, rendering proceeds exactly as today (zero overhead for the common
  case).

- `ChangeList.swift` — extracts a flat `[DocumentChange]` array from the
  `DiffContext` for the sidebar. Each `DocumentChange` carries:

  - `id: String` (matches `data-change-id` in HTML)
  - `type: ChangeType` (.insertion, .deletion, .modification)
  - `summary: String` (first ~60 characters of changed content)
  - `sourceLine: Int` (for scroll targeting)


### Layer 2: Rendering integration (MudCore)

#### Up mode

`UpHTMLVisitor` gains an optional `diffContext: DiffContext?` field.

Block-level visit methods (`visitParagraph`, `visitHeading`, `visitCodeBlock`,
`visitBlockQuote`, `visitListItem`, etc.) call two new helper methods at entry
and exit:

```
emitChangeOpen(for: markup)   // at the top of each visit method
emitChangeClose(for: markup)  // at the bottom
```

These helpers:

1. Emit any **preceding deletions** — pre-rendered HTML from deleted blocks,
   wrapped in `<del class="mud-change mud-change-del" data-change-id="…">`.
   This includes the old version of modified blocks (see below).

2. For **inserted blocks**, wrap the entire block output in
   `<ins class="mud-change mud-change-ins" data-change-id="…">`.

3. For **modified blocks**, emit the old version as a preceding deletion
   (hidden by default), then wrap the new version in
   `<ins class="mud-change mud-change-mod" data-change-id="…">`. The new
   version renders normally — no inline word-level markers. This is the
   `git diff` model: modification = delete old + insert new.

When `diffContext` is nil, these helpers are no-ops — the hot path is
unchanged.

To render deleted and modified-old blocks for insertion, the diff engine
renders each block in isolation using a separate `UpHTMLVisitor` walk (without
a `diffContext`, to avoid recursion).


#### Down mode

`DownHTMLVisitor.highlight()` gains an optional `diffContext: DiffContext?`
parameter.

Down mode uses the same AST-based `DiffContext` as Up mode — one diff engine,
two rendering integrations. Block-level matches carry source ranges from the
AST nodes. `DiffContext` maps these to line ranges: a block spanning lines 5–10
marked as deleted means lines 5–10 are all deletion lines. A block spanning
lines 5–10 marked as modified means those lines are replaced (old lines
deleted, new lines inserted).

Line-level integration:

1. **Deleted lines** are re-inserted into the line array at their original
   positions, wrapped in `<del>` spans and styled distinctly (dimmed text,
   strikethrough). Show a dash (`–`) in the line number column.

2. **Inserted lines** get an `<ins>` wrapper around the line content.

3. **Modified blocks** are expanded to their constituent lines: old lines (from
   the waypoint source) are re-inserted as deletions, new lines are marked as
   insertions. Same visual result as `git diff`.


#### RenderOptions change

`RenderOptions` gains an optional waypoint field:

```swift
struct RenderOptions {
    // ... existing fields ...
    var waypoint: ParsedMarkdown?  // old content to diff against; nil = no tracking
}
```

`RenderOptions` is `Sendable + Equatable`. swift-markdown's `Document` struct
wraps a reference-counted `RawMarkup` tree which declares no `Sendable`
conformance, so `ParsedMarkdown` needs explicit conformances:

```swift
extension ParsedMarkdown: @unchecked Sendable {}

extension ParsedMarkdown: Equatable {
    public static func == (lhs: ParsedMarkdown, rhs: ParsedMarkdown) -> Bool {
        lhs.markdown == rhs.markdown
    }
}
```

`@unchecked Sendable` is justified because `ParsedMarkdown` is immutable (all
`let` fields) and the underlying `RawMarkup` tree has no mutation API.
`Equatable` by source string comparison is semantically correct — identical
source always produces identical ASTs.

When `waypoint` is non-nil, the render functions run block matching →
`DiffContext` using the pre-parsed ASTs from both the current `ParsedMarkdown`
and the waypoint `ParsedMarkdown`. No re-parsing.

`contentIdentity` includes a waypoint discriminator (hash of
`waypoint?.markdown`) so content changes when the waypoint changes (e.g.
Accept). Since theme/zoom changes go through JS (without re-calling the render
function), the diff is only computed when content actually changes — not on
every visual update.


#### API changes

The existing render function signatures are unchanged — they already accept
`RenderOptions`, which now carries the waypoint. One new function:

```swift
// Compute sidebar change list from two ParsedMarkdown values
MudCore.computeChanges(
    old: ParsedMarkdown, new: ParsedMarkdown
) -> [DocumentChange]
```

This is called by `ChangeTracker` when content changes, independently of
rendering. Both paths (rendering and sidebar) work with pre-parsed ASTs — no
redundant parsing anywhere.


### Layer 3: State management (App)

**New file: `App/ChangeTracker.swift`**

```swift
class ChangeTracker: ObservableObject {
    @Published private(set) var waypoints: [Waypoint] = []
    @Published private(set) var changes: [DocumentChange] = []
    @Published var selectedChangeID: String?

    /// The active waypoint's ParsedMarkdown (for RenderOptions).
    var activeWaypoint: ParsedMarkdown? {
        waypoints.last?.parsed
    }

    /// The timestamp of the active waypoint (for sidebar display).
    var activeWaypointTimestamp: Date? {
        waypoints.last?.timestamp
    }

    func setInitialWaypoint(_ parsed: ParsedMarkdown)
    func update(_ currentParsed: ParsedMarkdown)  // recomputes changes
    func accept(_ currentParsed: ParsedMarkdown)   // pushes new waypoint
}

struct Waypoint: Identifiable {
    let id: UUID
    let parsed: ParsedMarkdown  // pre-parsed; AST reused for diffing
    let timestamp: Date
}
```

`ParsedMarkdown` is parsed once per waypoint. The same value flows to
`RenderOptions.waypoint` (for rendering) and to
`MudCore.computeChanges(old:new:)` (for the sidebar). No re-parsing anywhere.

`ChangeTracker` is a per-window `ObservableObject`. `DocumentState` gains a
`let changeTracker = ChangeTracker()` field (same pattern as
`let find = FindState()`). `DocumentContentView` observes it directly via
`@ObservedObject var changeTracker: ChangeTracker` — passed separately, not
accessed through `state.changeTracker`. (SwiftUI does not observe nested
`ObservableObject` fields automatically, so this follows the same pattern used
for `FindState`.)

Waypoints are in-memory only. They do not persist across closing and re-opening
the document. Old waypoints are retained in the `waypoints` array for a future
waypoint-selector UI but are not otherwise used.

**Integration with `DocumentContentView` :**

- `loadFromDisk()` already creates a `ParsedMarkdown` value (from the
  title-extraction work). After setting `content = .parsed(parsed)`, it calls
  `changeTracker.update(parsed)`. On first load this creates the initial
  waypoint; on subsequent loads it diffs against the active waypoint via
  `MudCore.computeChanges(old:new:)` and updates `changes`.
- The `renderOptions` computed property sets
  `opts.waypoint = changeTracker.activeWaypoint` when the content differs from
  the waypoint (i.e. there are changes to show). When content matches the
  waypoint, `opts.waypoint` stays nil (no markers needed).
- The existing content-identity mechanism handles WebView reloads — since
  `contentIdentity` includes the waypoint, enabling/disabling change tracking
  naturally triggers a re-render.


### Layer 4: Sidebar UI (App)

**`App/SidebarView.swift`** and **`App/ChangesSidebarView.swift`** are already
implemented. `SidebarView` wraps a segmented Outline/Changes picker with
`OutlineSidebarView` and `ChangesSidebarView` as panes.
`DocumentWindowController.setupContent()` already wires `SidebarView` in place
of the old direct `OutlineSidebarView`.

`ChangesSidebarView` currently shows a static "No Changes" empty state. It
needs to be extended to accept a `ChangeTracker` and display:

1. **Status line** at the top: "X changes since HH:MM" (or "today at HH:MM",
   "yesterday", etc.) with an **Accept** button.

2. **Change list** — each row shows:

   - An icon: `plus.circle` (insertion), `minus.circle` (deletion), or
     `pencil.circle` (modification), coloured green/red/blue
   - A one-line summary of the changed text
   - Tapping a row sets `changeTracker.selectedChangeID` and triggers a
     scroll-to-change action

3. **Empty state** — when no changes: "No changes since HH:MM".


### Layer 5: WebView and JavaScript (App + Resources)

**Scroll-to-change:**

Add `Mud.scrollToChange(id)` in `mud.js`:

```javascript
Mud.scrollToChange = function(id) {
    const el = document.querySelector('[data-change-id="' + id + '"]');
    if (!el) return;
    el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    el.classList.add('mud-change-active');
    // Remove active class after 2s
    setTimeout(() => el.classList.remove('mud-change-active'), 2000);
};
```

**Deletion reveal:**

Deletions are hidden by default via CSS:

```css
.mud-change-del { display: none; }
.mud-change-del.mud-change-revealed { display: block; }
```

When a deletion is selected in the sidebar, JS reveals it:

```javascript
Mud.revealChange = function(id) {
    document.querySelectorAll('.mud-change-revealed')
        .forEach(el => el.classList.remove('mud-change-revealed'));
    const el = document.querySelector('[data-change-id="' + id + '"]');
    if (el) el.classList.add('mud-change-revealed');
};
```

When the selection is cleared (or moves to a non-deletion), all revealed
deletions are hidden again.

**Scroll target extension:**

`DocumentState.scrollTarget` currently only supports headings. We need a
parallel mechanism for changes. Options:

1. Add a `ScrollTarget.change(id: String)` variant
2. Use a separate `@Published var changeScrollTarget: String?`

Option 2 is simpler and avoids modifying the existing `ScrollTarget` type.
`WebView.updateNSView()` would check this property and call
`Mud.scrollToChange(id)` / `Mud.revealChange(id)` via JS.


### Layer 6: CSS (Resources)

**New file: `Resources/mud-changes.css`** (or additions to `mud.css`)

```css
/* Block-level change markers */
.mud-change-ins,
.mud-change-mod {
    background-color: var(--change-ins-bg);
    border-left: 3px solid var(--change-ins-border);
    padding-left: 4px;
}

.mud-change-del {
    display: none;
}

.mud-change-del.mud-change-revealed {
    display: block;
    background-color: var(--change-del-bg);
    border-left: 3px solid var(--change-del-border);
    padding-left: 4px;
    opacity: 0.7;
    text-decoration: line-through;
}

.mud-change-active {
    outline: 2px solid var(--change-active-border);
    outline-offset: 2px;
}
```

Theme files gain `--change-*` CSS variables so change colours harmonise with
each theme.


## Key design decisions (resolved)

1. **Block matching strategy** — LCS on block fingerprints via Swift's
   `CollectionDifference`. Handles adds/removes/reorders well. Fuzzy matching
   for modified blocks can be added later.

2. **Block granularity** — Leaf blocks (individual list items, table rows,
   blockquote paragraphs), not top-level containers. Finer diffs, more precise
   sidebar entries.

3. **Diff computation** — Synchronous. Markdown files are typically small.
   Profile during implementation and move to async if needed.

4. **Deleted line numbers in Down mode** — Show a dash (`–`) in the line number
   column, styled with the deletion colour.

5. **Sidebar pane state** — Per-window (`@State` in `SidebarView`), not
   persisted.

6. **Diff granularity** — Block-level only for the initial implementation
   (Approach A). See the section below for the full analysis and evolution
   path.


## Diff granularity approaches

Three approaches for how changes are presented in the rendered document,
ordered from simplest to most precise. We implement **Approach A** first and
may evolve to **B** later. **C** is documented for completeness.


### Approach A: Block-level only (the `git diff` model) — ACTIVE

Modifications are treated as a deletion of the old block followed by an
insertion of the new block. No word-level diffing. This is how `git diff`
presents modified lines: old line in red, new line in green.

**In Up mode:** for a modified paragraph, the old version is rendered as a
hidden `<del>` block (revealable via the sidebar), and the new version is
rendered normally inside an `<ins>` wrapper with a "modified" visual indicator.

**In Down mode:** for a modified line, the old line is re-inserted as a hidden
`<del>` row, and the new line gets an `<ins>` wrapper.

**Pros:**

- Simplest to implement — no `WordDiff` engine, no inline marker injection, no
  cross-boundary concerns
- Always readable, even for heavily rewritten prose
- Matches the `git diff` mental model developers are used to

**Cons:**

- A single typo fix in a 200-word paragraph shows the entire paragraph as
  modified (old + new). The sidebar tells you which paragraph changed, but you
  must visually compare the two versions to spot the difference.


### Approach B: Block-level with word highlights (enhanced `git diff`)

Same structure as A — modifications are shown as old block (hidden) + new block
(visible). But within each version, changed words get a subtle background
highlight: insertions in the new block, deletions in the old block.

Crucially, this is **not interleaved**. The new version only has insertion
marks. The old version only has deletion marks. Each version reads as natural
prose with a bit of colour.

**Implementation (deferred):**

- Add `WordDiff.swift` to `Core/Sources/Core/Diff/` — tokenise text into words,
  diff via `CollectionDifference`, produce `[DiffToken]`.
- `DiffContext` gains `wordAnnotations(for: Markup) -> [WordAnnotation]` —
  character-offset ranges within a block's plain text.
- In `UpHTMLVisitor`, when rendering a modified block (old or new version),
  `visitText` consults word annotations and wraps changed runs in
  `<mark class="mud-word-ins">` or `<mark class="mud-word-del">`.
- The cross-boundary problem (a highlight spanning from plain text into
  emphasis) still exists but is less severe than Approach C because each
  version has only one type of mark — no interleaving of `<ins>` and `<del>`.
  The approach: close the `<mark>` before the formatting boundary and reopen it
  after. Only `visitText` needs modification.

**CSS additions for B:**

```css
mark.mud-word-ins { background-color: var(--change-ins-word-bg); }
mark.mud-word-del { background-color: var(--change-del-word-bg); }
```

**Pros:**

- Same readability as A for large changes
- Precise highlighting for small changes (typo fixes, number edits)
- Each version still reads as natural prose

**Cons:**

- Requires `WordDiff` engine
- Cross-boundary `<mark>` handling needed in `visitText` (simpler than C but
  still non-trivial)


### Approach C: Inline word-level (the `--word-diff` model)

Interleaved `<ins>` and `<del>` elements within the text of modified blocks.
The old text is deleted inline and the new text is inserted inline, producing
output like: `This is <del>important</del><ins>critical</ins> and relevant`.

**Implementation (not planned):**

- Same `WordDiff` engine as Approach B.

- `DiffContext` provides `InlineAnnotation` records with character-offset
  ranges and types (insertion/deletion).

- `UpHTMLVisitor.visitText` must:

  1. Track a running character offset across calls within a paragraph.
  2. Split text emission at change boundaries.
  3. Close `<ins>`/ `<del>` before inline formatting boundaries and reopen
     after them, to produce valid HTML (e.g., when a change spans from plain
     text into `<strong>`).

- Substantial edge-case surface: changes inside code spans, changes spanning
  emphasis boundaries, adjacent changes, overlapping formatting.

**Pros:**

- Most precise — you see exactly what changed without comparing two versions
- Compact — no duplicate blocks

**Cons:**

- Least readable for prose. Interleaved markers break reading flow, even for
  unchanged text surrounding the change. Empirically, `git diff` (line-level)
  is consistently more readable than `git diff --word-diff` for prose edits.
- Hardest to implement. The cross-boundary problem requires careful state
  management in the visitor and extensive edge-case testing.
- Modifications cannot be hidden — they're inline in the text, not separate
  blocks.


## Implementation sequence

1. ~~**Sidebar UI** — `SidebarView` container, segmented control, placeholder
   `ChangesSidebarView` .~~ _Done._

2. **Diff engine** — `BlockMatcher`, `DiffContext`, `ChangeList` in MudCore.
   Unit-testable in isolation. (`WordDiff` deferred to Approach B.)

3. **Up mode integration** — `UpHTMLVisitor` changes, `DiffContext` threading
   through `renderUpModeDocument`. Verify with snapshot tests.

4. **Down mode integration** — `DownHTMLVisitor` changes. Similar snapshot
   tests.

5. **ChangeTracker + RenderOptions** — state management in App layer, waypoint
   field on `RenderOptions`. Wire to `DocumentContentView.loadFromDisk()`.

6. **CSS** — change marker styles, theme variable additions.

7. **Sidebar UI (changes pane)** — flesh out `ChangesSidebarView` with change
   list, status line, Accept button.

8. **JS + WebView** — `scrollToChange`, `revealChange`, wire to sidebar
   selection.

9. **Polish** — keyboard shortcuts (Next Change / Previous Change), menu items,
   edge cases (empty document, binary files, very large diffs).


## Resolved questions

- **Undo Accept?** — No. Old waypoints are retained in memory for a future
  waypoint-selector UI, which will provide this capability. No stop-gap undo
  needed.
- **Keyboard shortcuts?** — Deferred. May add shortcuts for Accept,
  Next/Previous Change later.
- **Persist waypoints?** — No. In-memory only. Closing the document discards
  all waypoints.
- **Print / Open in Browser?** — Build `RenderOptions` without a waypoint. No
  change markers in exported HTML.
- **Global disable toggle?** — Deferred. May add a "Change Tracking" settings
  pane in the future for this and other related preferences.
