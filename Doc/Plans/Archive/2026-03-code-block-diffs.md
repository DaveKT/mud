Plan: Code Block Diffs
===============================================================================

> Status: Complete


## Overview

Line-level diffs within code blocks in Up mode. Previously, a changed code
block was marked as a single inserted/deleted block. Now, individual changed
lines are highlighted, with each cluster of consecutive changes forming its own
navigable group with an overlay badge. Word-level diff markers highlight the
specific words that changed within paired lines.

Mermaid code blocks get block-level handling: the old diagram renders as a
"[revised diagram]" placeholder deletion, and the new diagram renders normally.
No line-level diff (the rendered SVG can't be meaningfully diffed).


## Architecture

### CodeBlockDiff

New type in `Core/Sources/Core/Diff/CodeBlockDiff.swift`. Two-phase design:

- `computeRaw` — splits old/new code into lines, runs `CollectionDifference`,
  builds anchors, classifies gaps. Within each gap, pairs deleted and inserted
  lines positionally and runs `WordDiff.diff` on each pair, injecting `<ins>`/
  `<del>` markers into the syntax-highlighted HTML via
  `DownHTMLVisitor.injectMarkers`. Returns a `RawDiff` with annotations and
  highlighted HTML but no IDs.
- `assignGroups` — walks the raw lines, assigns change IDs and group IDs to
  clusters of consecutive changed lines via closures supplied by the caller.

Syntax highlighting is done per-block (preserving full context), then split
per-line via `HTMLLineSplitter.splitByLine`. Old lines are highlighted with the
old language, new lines with the new.


### DiffContext integration

`processCodeBlockPairs` scans each gap for CodeBlock deletion/insertion pairs
by type (not position). For each non-mermaid pair, computes a `RawDiff` and
stores it keyed by the insertion's source key. The pair's block-level change
entries are replaced with a `CodeBlockMarker` placeholder in the `changeItems`
list. The grouping pass (which runs after all gaps) assigns IDs to code block
line groups in document order alongside block-level groups.

Mermaid pairs skip line-level diffing (bare `continue`). They fall through to
normal block-level del+ins pairing. The deletion renders a "[revised diagram]"
placeholder via `renderedDeletion`.

New API: `codeBlockDiff(for: Markup) -> CodeBlockDiff?`.


### UpHTMLVisitor rendering

`visitCodeBlock` checks `codeBlockDiff(for:)`. When present,
`emitDiffedCodeBlock` renders `<span class="cl">` line structure with `cl-ins`/
`cl-del` classes and data attributes. The `<pre>` gets `mud-code-diff` class
but no block-level `data-change-id`. Code header and syntax highlighting are
preserved.


### Sidebar

`ChangeList.emitCodeBlockChanges` emits one `DocumentChange` per changed line
(not per group). Lines in the same group share a `changeID` and `groupID`, so
`ChangeGroup.build` groups them naturally. The existing `displayLines`
condensation (up to 3 per run, then overflow) applies.

`DocumentChange` carries an `isMixed` field for cases where a single entry
represents a mixed change (used by the sidebar's `ChangeGroup.build` to
propagate mixed-group status).


### CSS

`.cl` (structural wrapper), `.cl-del` (hidden by default, revealed with
strikethrough), `.cl-ins` (green tint) in `mud-changes.css`.


### JS

- `mud.js`: overlay type classification recognizes `cl-del` in addition to
  `mud-change-del` for group type and sub-overlay splitting.
- `mermaid-init.js`: copies change-tracking data attributes through `<pre>` →
  `<div>` replacement; skips `mud-change-del` blocks.
- `copy-code.js`: for `mud-code-diff` blocks, copies only `.cl:not(.cl-del)`
  line content.
