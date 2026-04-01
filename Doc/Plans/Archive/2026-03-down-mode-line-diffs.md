Plan: Down Mode Line Diffs
===============================================================================

> Status: Complete


## Overview

Switch Down mode change tracking from block-level to line-level diffs,
producing output equivalent to a unified git diff. Currently, when a code block
(or any multi-line block) changes, every source line in both the old and new
block is marked as deleted or inserted. With line-level diffs, only the lines
that actually changed are marked — unchanged lines within a modified block
render normally.


## Current behavior

`LineDiffMap` maps block-level `BlockMatch` results to line ranges. A paired
code block (one deleted, one inserted in the same gap) marks _all_ lines of the
old block as deleted and _all_ lines of the new block as inserted. Word- level
diffs operate within paired blocks but don't reduce the set of marked lines.

For a 50-line code block where one line changed, Down mode currently shows 50
red lines + 50 green lines. The goal is 49 unchanged lines, 1 red, 1 green.


## Design

### Line-level diff within block pairs

When `LineDiffMap` encounters a paired block (deletion + insertion in the same
gap), instead of marking all lines:

1. Extract source text from both blocks.
2. Split into lines.
3. Run `CollectionDifference` on the line arrays (same algorithm as
   `CodeBlockDiff.computeRaw`).
4. Classify each line as unchanged, inserted, or deleted.
5. Emit only the changed lines as annotations/deletion groups. Unchanged lines
   within the block get no annotation — they render normally as part of the new
   document.

This applies to **all** block types, not just code blocks. A paragraph that
reflows across lines, a list item with added lines, a blockquote with internal
edits — all benefit.


### Reuse from code block diffs

`CodeBlockDiff` already implements the core algorithm: split lines, diff via
`CollectionDifference`, build anchors, classify gaps. The key difference:

- **Code block diffs (Up mode):** operate on code content (without fences),
  highlight with `CodeHighlighter`, produce `CodeLine` structs with highlighted
  HTML.
- **Down mode line diffs:** operate on raw source text (including markdown
  syntax), don't need highlighting (the layout phase handles that), produce
  line-range annotations.

Extract the shared diffing logic into a reusable function:

```swift
/// Diffs two arrays of lines and returns per-line annotations.
/// Within each gap, deletions precede insertions.
struct LineLevelDiff {
  struct Entry {
    let annotation: Annotation
    /// 0-based index in the original (old or new) line array.
    let sourceIndex: Int
  }
  enum Annotation { case unchanged, inserted, deleted }

  /// Returns nil when the arrays are identical.
  static func diff(old: [String], new: [String]) -> [Entry]?
}
```

`CodeBlockDiff.computeRaw` can be refactored to call this, and `LineDiffMap`
uses the same function.


### Integration with LineDiffMap

In `LineDiffMap.finalizeGap`, when processing a paired block:

1. Split both blocks' `sourceText` into lines.

2. Call `LineLevelDiff.diff(old:new:)`.

3. If nil (identical content but different fingerprints, e.g. re-indented list
   item), fall back to block-level treatment.

4. Otherwise, iterate the entries:

   - **Unchanged:** skip (no annotation, no deletion group).
   - **Inserted:** add `LineAnnotation` for the corresponding new-document
     line.
   - **Deleted:** accumulate into deletion groups positioned before the next
     changed or unchanged new-document line.

Unpaired blocks (pure insertions or pure deletions) keep the current
block-level treatment — all their lines are marked.


### Word-level diffs within line pairs

Within each gap of the line-level diff, pair deleted and inserted lines by word
overlap and run `WordDiff.diff` on each pair. `WordPairing.bestPairs` scores
every (del, ins) combination by shared-word count and greedily picks the
best-scoring pairs. This matters when a gap has unequal counts (e.g. 3
deletions, 1 insertion) — positional pairing would compare against the first
deletion, which may be completely unrelated, while best-match pairing finds the
most similar deletion and produces a narrow, useful word diff.

The same best-match pairing is used in `CodeBlockDiff.emitGap` (Up mode code
block diffs) and both `processLineLevelPair` and `processCodeBlockPair` in
`LineDiffMap` (Down mode).

The existing `wordMarkers(from:forLine:)` and `injectMarkers(into:markers:)`
machinery works unchanged — it already operates at the single-line level.

`BlockWordData` stores per-line word data, keyed by `(changeID, lineNumber)` in
the `wordDataMap`. Each paired line gets its own `BlockWordData` with
`startLine` equal to its document line number and `sourceText` equal to the
single line. The block-level fallback stores one `BlockWordData` per line of
the block, all pointing to the same block-wide span data.


### Change IDs and sidebar consistency

The sidebar is computed once by `ChangeList.computeChanges()` via
`DiffContext`, regardless of which mode is displayed. The `data-change-id`
values in the Down mode HTML must match the sidebar's IDs or scroll-to-change
breaks.

`DiffContext` and `LineDiffMap` are independent instances that process the same
`BlockMatch` results with their own change counters. They produce matching IDs
as long as they consume the same number of IDs in the same order. This is the
key invariant to maintain.

`DiffContext` uses per-cluster IDs for code block pairs (via `CodeBlockDiff`)
and per-block IDs for everything else. `LineDiffMap` must match this
granularity:

- **Code block pairs:** one change ID per line-level cluster (matching
  `DiffContext`'s `CodeBlockDiff` line groups). Each cluster is a separate
  sidebar entry.
- **Other pairs:** one change ID per block (matching `DiffContext`'s
  block-level treatment). The sidebar has one entry per block pair.

The visual treatment (which lines are highlighted) is independent of ID
assignment. All paired blocks show line-level highlighting, but non-code-block
pairs share a single ID across all their changed lines.

**Pre-existing bug:** `LineDiffMap` currently assigns two block-level IDs per
code block pair (one for the deletion, one for the insertion). `DiffContext`
consumes the same two initial IDs but then replaces them with per-cluster IDs
via `CodeBlockDiff.assignGroups`. The total ID count diverges, so all
subsequent IDs are offset — scroll-to-change is broken for code blocks in Down
mode and for any block-level change that follows a code block pair. This work
fixes the bug by making `LineDiffMap` match `DiffContext`'s ID assignment for
code block pairs.

For code blocks specifically, `LineDiffMap` must use `CodeBlockDiff` (on code
content, without fences) rather than `LineLevelDiff` (on raw source text,
including fences). The reason: when the language tag changes, `LineLevelDiff`
sees the opening fence as a changed line (producing an extra cluster), while
`CodeBlockDiff` only sees code content and ignores fence changes. Using
`CodeBlockDiff` ensures the cluster count — and therefore the ID count —
matches `DiffContext` exactly.


### Deletion group positioning

Currently, a block's deletion group is positioned before the first insertion
line (or the next unchanged block). With line-level diffs, deletion lines are
positioned precisely:

- Within a gap between unchanged line anchors, deleted lines appear before
  inserted lines (matching unified diff convention).
- Each cluster of consecutive changed lines produces its own deletion group,
  positioned before the corresponding new-document lines.
- Trailing deleted lines (after the last unchanged anchor within the block) are
  positioned before the next unchanged line in the new document.


### Unchanged lines between changes

Unchanged lines within a modified block are part of the new document and
already have line numbers in the layout. They need no annotation and appear as
normal `<div class="dl">` rows. This is already the default — `LineDiffMap`
only annotates lines that appear in `annotations`.


## Edge cases

1. **Entirely rewritten block** — all lines changed. Degenerates to current
   behavior (all old lines deleted, all new lines inserted). No regression.

2. **Whitespace-only changes** — `CollectionDifference` compares exact strings.
   Re-indentation marks affected lines as changed. Acceptable, same as Up mode.

3. **Block that changes type** — e.g., a paragraph becomes a code block. The
   fingerprints differ, so they pair positionally. Line-level diff of their
   source text may produce useful results (common lines survive) or may
   degenerate to full replacement. Both are acceptable.

4. **Single-line blocks** — paragraphs, headings. Line-level diff of a
   single-line pair is trivially "1 deleted, 1 inserted". Same as today, no
   regression. Word-level diffs still apply.

5. **Nested list items** — `LeafBlockCollector` treats each item as a leaf
   block. A modified list item's source includes the marker (`- `). If only
   content changes, the line-level diff catches it.

6. **Fenced code blocks** — handled via `CodeBlockDiff` (not `LineLevelDiff`)
   to match `DiffContext`'s cluster-based ID assignment. `CodeBlockDiff`
   operates on code content without fences; fence lines are always rendered
   unchanged in the Down mode layout. If only the language tag changes (no code
   content change), `CodeBlockDiff.computeRaw` returns nil and the pair falls
   back to block-level treatment — matching `DiffContext`'s behavior.

7. **Table rows** — each row is a separate leaf block (not a multi-line block),
   so line-level diffing doesn't apply. No change needed.


## Tests

Written TDD-style before the implementation. Two test files:

**`LineLevelDiffTests.swift`** — 17 unit tests for the new `LineLevelDiff`
type. Covers identical content (nil return), single-line changes, pure
insertions/deletions, multiple gaps, gap ordering (deletions before
insertions), degenerate cases (all changed, empty arrays), source index
tracking (unchanged→new index, deleted→old index, inserted→new index), and
whitespace sensitivity.

**`DownModeChangeTrackingTests.swift`** — 13 new integration tests added to the
existing suite (21 tests). Tests render through `MudCore.renderDownToHTML` and
check the output HTML.

Line-level behavior tests (fail until implemented):

- Multi-line paragraph — only changed lines get `dl-ins`/ `dl-del`
- Unchanged lines within a modified block render as normal divs
- Word-level markers appear on line-paired content
- Best-match word pairing compares against the most similar deletion
- `data-change-id` attributes only on changed lines (not entire block)
- Fenced code block — only changed content lines marked
- Multi-line list item — only changed lines marked
- Lines added within a paired block — insertion only, no deletions
- Lines deleted within a paired block — deletion only, no insertions
- Code block sidebar/HTML change ID consistency (exposes pre-existing bug)

Regression guards (pass now):

- All lines changed degenerates to full replacement (3 del + 3 ins)
- Single-line block behavior unchanged (1 del + 1 ins)
- Deletion precedes insertion in output order
- Non-code-block sidebar/HTML change ID consistency


## Implementation sequence

1. ~~**Extract `LineLevelDiff`**~~ _Done._ New
   `Core/Sources/Core/Diff/LineLevelDiff.swift`.

2. ~~**Update `LineDiffMap.finalizeGap`**~~ _Done._ Rewritten
   `LineDiffMap.swift` with `processLineLevelPair` (non-code-blocks) and
   `processCodeBlockPair` (code blocks via `CodeBlockDiff`). Word data map
   changed to per-line keying. `DownHTMLVisitor` callers updated.

3. ~~**Adapt word-level diffs**~~ _Done._ Per-line word diffs computed within
   each gap of the line-level diff.

4. ~~**Tests**~~ _Done._ 17 `LineLevelDiffTests` + 14 new
   `DownModeChangeTrackingTests` + 5 `WordPairingTests`. All pass.

5. ~~**Verify Up mode code block diffs**~~ _Done._ `CodeBlockDiff.computeRaw`
   refactored to use `LineLevelDiff`. All existing tests pass.

6. ~~**Best-match word pairing**~~ _Done._ `WordPairing.bestPairs` pairs by
   word overlap instead of position. Applied to `LineDiffMap` (both pair
   handlers) and `CodeBlockDiff.emitGap`.
