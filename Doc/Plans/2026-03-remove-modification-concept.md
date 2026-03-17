Plan: Remove Modification Concept from Change Tracking
===============================================================================

> Status: Planning


## Context

The change tracking system has three change types: insertion, deletion, and
modification. A "modification" is a paired deletion + insertion at the same
position, detected by BlockMatcher's Phase 2 gap-based pairing logic. This adds
complexity across the entire stack (diff engine, rendering, CSS, JS, sidebar).

The sidebar already has a consecutive-change grouping feature that collapses
adjacent changes into a single row. This naturally handles the modification
case: when a paragraph is edited in place, the old version is deleted and the
new version is inserted — with no unchanged block between them, they group
together.

Dropping the modification concept and relying on grouping produces
approximately the same user experience with a simpler model:

- All-insertion groups → green (plus icon)
- All-deletion groups → red (minus icon)
- Mixed groups (ins + del) → blue (pencil icon, unfoldable to reveal deletions)

This is arguably more intuitive: "blue means there's more to unfold."


## Step 1: BlockMatcher — remove Phase 2

**File:** `Core/Sources/Core/Diff/BlockMatcher.swift`

Remove the Phase 2 doc comment (lines 8–9) and the entire Phase 2 gap-based
pairing logic (lines 48–82): the `modOldForNew` dictionary, the boundary loop,
and all modification pairing code. Remove the `modOldForNew` parameter from
`buildResult` and the `.modified` case in `buildResult`.

Remove `case modified(old: LeafBlock, new: LeafBlock)` from the `BlockMatch`
enum.

The method signature and Phase 1 (`CollectionDifference`) stay unchanged.
Excess removals and insertions in each gap simply remain as `.deleted` and
`.inserted`.


## Step 2: DiffContext — simplify

**File:** `Core/Sources/Core/Diff/DiffContext.swift`

Remove the `case .modified` branch from the match-processing loop. Without
`.modified` matches, only `.unchanged`, `.inserted`, and `.deleted` remain.

Remove `BlockAnnotation.modified` — the only annotation is now `.inserted`.

Remove `isModificationOld` from `RenderedDeletion` and from
`renderedDeletion(for:changeID:isModificationOld:)`.


## Step 3: LineDiffMap — merge modified into deleted + inserted

**File:** `Core/Sources/Core/Diff/LineDiffMap.swift`

Remove the `case .modified` branch. It currently creates a deletion ID, appends
to pending deletions, flushes, then creates a modification ID and annotates the
new lines. Without it, the `.deleted` and `.inserted` cases already handle each
half independently.


## Step 4: ChangeList — remove modification filtering

**File:** `Core/Sources/Core/Diff/ChangeList.swift`

Remove all `.filter({ !$0.isModificationOld })` calls (three occurrences).
Every deletion is now a standalone deletion — no special filtering needed.

Remove the `.modification` mapping: the annotation-to-ChangeType conversion
currently maps `.modified` → `.modification`. With only `.inserted`
annotations, this becomes a direct `.insertion` mapping.

Remove `case modification` from the `ChangeType` enum.


## Step 5: ChangeGroup — handle mixed groups

**File:** `App/ChangesSidebarView.swift`

Update `ChangeGroup.build` / `makeGroup` to detect mixed groups. Add an
`isMixed` property to `ChangeGroup`:

```
let isMixed: Bool  // true when group contains both insertions and deletions
```

In `makeGroup`, compute `isMixed` from the types array. The `type` field
becomes the "primary" type (insertion if any insertions present, else
deletion).

Update `ChangeGroupRow.iconInfo` to check `isMixed` first:

- `isMixed` → `("pencil.circle", .blue)`
- `.insertion` → `("plus.circle", .green)`
- `.deletion` → `("minus.circle", .red)`


## Step 6: CSS — remove mod styles

**File:** `Core/Sources/Core/Resources/mud-changes.css`

Remove `--change-mod` and `--change-mod-tint` variables (both light and dark
mode).

Remove `.mud-change-mod` from combined selectors with `.mud-change-ins`.

Remove the dedicated `.mud-change-mod::before` rule.


## Step 7: UpHTMLVisitor — remove mod suffix

**File:** `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`

In `emitChangeOpen`, the annotation suffix logic currently chooses `"ins"` or
`"mod"`. With only `.inserted` annotations, this always produces `"ins"`.
Simplify the conditional.


## Step 8: JavaScript — remove backward-walking

**File:** `Core/Sources/Core/Resources/mud.js`

In `revealChanges`, remove the `mud-change-mod` backward-walking block (lines
238–247). Without modifications, each deletion has its own change ID which is
included directly in the group's `changeIDs` array. The existing
`mud-change-del` reveal logic (lines 235–236) handles it.


## Step 9: Tests — update

**BlockMatcherTests:** Tests that expect `.isModified` should expect
`.isDeleted` + `.isInserted` instead. Remove the `isModified` helper.
`samePositionReplacementIsModified` becomes
`samePositionReplacementIsDeletedAndInserted`. `adjacentModifications` tests
two consecutive delete+insert pairs.

**DiffContextTests:** Tests expecting `.modified` annotation should expect
`.inserted` annotation (the new version) and verify a preceding deletion (the
old version).

**UpModeChangeTrackingTests:** The "Modifications" section tests should verify
that editing a paragraph produces a `<del>` (old) +
`<ins class="mud-change-ins">` (new) — no `mud-change-mod` class. Also update
`modifiedDocCAsideHasChangeMarkers()` which expects `mud-change-mod`.

**DownModeChangeTrackingTests:** Similar — verify `dl-del` + `dl-ins` lines
appear for edits.

Remove any assertions about `isModificationOld` or `mud-change-mod`.


## Files to modify

| File                                                | Change                                           |
| --------------------------------------------------- | ------------------------------------------------ |
| `Core/Sources/Core/Diff/BlockMatcher.swift`         | Remove Phase 2 and `.modified` case              |
| `Core/Sources/Core/Diff/DiffContext.swift`          | Remove `.modified` handling, `isModificationOld` |
| `Core/Sources/Core/Diff/LineDiffMap.swift`          | Remove `.modified` case                          |
| `Core/Sources/Core/Diff/ChangeList.swift`           | Remove filtering and `.modification` type        |
| `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`   | Simplify annotation suffix                       |
| `Core/Sources/Core/Resources/mud-changes.css`       | Remove `--change-mod` and `.mud-change-mod`      |
| `Core/Sources/Core/Resources/mud.js`                | Remove `mud-change-mod` backward-walk            |
| `App/ChangesSidebarView.swift`                      | Add `isMixed`, update icon/color                 |
| `Core/Tests/Core/BlockMatcherTests.swift`           | Rewrite modification tests                       |
| `Core/Tests/Core/DiffContextTests.swift`            | Update annotation expectations                   |
| `Core/Tests/Core/UpModeChangeTrackingTests.swift`   | Rewrite modification section                     |
| `Core/Tests/Core/DownModeChangeTrackingTests.swift` | Rewrite modification section                     |


## Verification

1. Run `swift test` — all tests pass

2. Open a markdown file in Mud, edit a paragraph externally:

   - Sidebar shows a blue (mixed) group
   - Clicking the group reveals the old version (red strikethrough) above the
     new version (green tint)

3. Add a new paragraph — sidebar shows green (insertion)

4. Delete a paragraph — sidebar shows red (deletion)

5. Verify light and dark mode both look correct

6. Verify Down mode shows `dl-del` / `dl-ins` lines for edits
