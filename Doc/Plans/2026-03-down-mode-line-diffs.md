Plan: Down Mode Line Diffs
===============================================================================

> Status: Planning


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

Within each gap of the line-level diff, pair deleted and inserted lines
positionally (first deleted with first inserted) and run `WordDiff.diff` on
each pair. This gives word-level markers within individual changed lines,
exactly as block-level pairing does today.

The existing `wordMarkers(from:forLine:)` and `injectMarkers(into:markers:)`
machinery works unchanged — it already operates at the single-line level.

`BlockWordData` currently stores spans for an entire block with a start line.
With line-level pairing, each paired line gets its own `BlockWordData` (or the
existing structure is adapted to store per-line spans keyed by line number).


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

6. **Fenced code blocks** — source text includes the opening/closing fences. If
   only content changes, the fence lines are unchanged anchors. If the language
   tag changes, the opening fence is a changed line.

7. **Table rows** — each row is a separate leaf block (not a multi-line block),
   so line-level diffing doesn't apply. No change needed.


## Implementation sequence

1. **Extract `LineLevelDiff`** — shared line-diffing function from
   `CodeBlockDiff.computeRaw`. Both callers use it.

2. **Update `LineDiffMap.finalizeGap`** — detect paired blocks, run
   `LineLevelDiff.diff`, emit fine-grained annotations and deletion groups.

3. **Adapt word-level diffs** — pair changed lines within gaps, compute
   `WordDiff` per line pair, store in `wordDataMap`.

4. **Tests** — update `DownModeChangeTrackingTests` to verify line-level
   behavior. Existing tests for single-line blocks should pass unchanged. Add
   tests for multi-line block edits.

5. **Verify Up mode code block diffs** — refactor `CodeBlockDiff.computeRaw` to
   use `LineLevelDiff`. Existing tests must pass.
