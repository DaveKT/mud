Plan: Ignore Ordered List Renumbering in Change Tracking
===============================================================================

> Status: Complete


## Context

When an item is deleted from an ordered list, the editor renumbers all
subsequent items. Our diff algorithm fingerprints list items using their raw
source text, which includes the leading number (`4. Dog`). Renumbering changes
the source text (`5. Eggplant` → `4. Eggplant`), causing false diffs: what
should be 1 deletion appears as multiple deletions + insertions.

```
Old:                    New (item 4 deleted):
1. Apple                1. Apple
2. Banana               2. Banana
3. Carrot               3. Carrot
4. Dog                  4. Eggplant   ← was "5. Eggplant"
5. Eggplant             5. Fig        ← was "6. Fig"
6. Fig
```

Current result: 3 deletions + 2 insertions. Desired: 1 deletion, 5 unchanged.


## Root cause

`extractSourceText` is line-based — it pulls full source lines using
`lines[(startLine - 1)..<clampedEnd]` and ignores column offsets. This means
even if we fingerprinted a list item's child `Paragraph` (whose source range
starts after the marker), we'd still get the full line including the marker.


## Approach

Make `extractSourceText` column-aware so it respects `SourceRange` column
bounds. Then, for ordered list items, fingerprint based on the child
paragraph's precise source range — which naturally excludes the marker and
continuation indent. No regex, no dedenting helper, no reimplementing parser
rules.

`sourceText` continues to use the full line-based extraction (the `ListItem`'s
own range) for downstream use in `LineDiffMap`, `DiffContext` rendering, and
summaries.


## Changes

### `Core/Sources/Core/Diff/BlockMatcher.swift`

1. **Add `extractSourceText(for:columnAware:)` or a separate
   `extractColumnAwareSourceText(for:)` method** to `LeafBlockCollector`. For a
   multi-line range, it substrings the first line from `startColumn`, takes
   middle lines in full, and takes the last line up to `endColumn`. For a
   single-line range, it substrings from `startColumn` to `endColumn`.

2. **Add `appendBlock(_:fingerprint:)` overload** to `LeafBlockCollector` —
   accepts a pre-computed fingerprint while extracting `sourceText` normally
   via the existing line-based method.

3. **Update `visitListItem`** — in the `else` (no nested list) branch, check
   `listItem.parent is OrderedList`. If true, extract the column-aware source
   text of the first child (the `Paragraph`) and use it as the fingerprint via
   the new overload. The `LeafBlock.markup` stays as the `ListItem` for correct
   annotation keying downstream. Otherwise, call the existing `appendBlock`.


### `Core/Tests/Core/BlockMatcherTests.swift`

Add a `// MARK: - Ordered list renumbering` section:

| Test                                      | Scenario                                       | Expected                  |
| ----------------------------------------- | ---------------------------------------------- | ------------------------- |
| `orderedListDeletionDoesNotFalseDiff`     | Delete middle item, later items renumbered     | 1 deleted, 5 unchanged    |
| `orderedListInsertionDoesNotFalseDiff`    | Insert item, later items renumbered            | 1 inserted, 2 unchanged   |
| `orderedListRenumberingWithContentChange` | Item renumbered AND content changed            | Detected as change        |
| `orderedListDigitWidthChange`             | Renumbering crosses digit boundary (10→9)      | Unchanged, not false diff |
| `unorderedListUnaffected`                 | Sanity check: unordered items use exact source | No regression             |


## Edge cases

- **Content + number change**: the child paragraph's content differs →
  correctly detected as a change.
- **Digit-width change** (e.g., `10.` → `9.`): handled naturally. The child
  paragraph's source range starts at the content column (5 for `10. `, 4 for
  `9. `), so `extractColumnAwareSourceText` clips to the right starting column.
  Continuation-line indentation is also clipped because the paragraph's range
  covers exactly the content.
- **Start index change** (`1.` → `5.`): sits on the `OrderedList` container,
  not tracked at leaf level. No impact.
- **Down mode**: `LineDiffMap` consumes `BlockMatch` results, never reads
  `fingerprint` directly. Both modes benefit automatically.


## Verification

Run `BlockMatcherTests` (ask the user to run in Xcode). Verify the new ordered
list tests pass and existing tests are unaffected.
