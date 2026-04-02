Plan: Word Diff Similarity Threshold
===============================================================================

> Status: Planning


## Context

Word-level diff highlighting (inline `<ins>` and `<del>` tags within paired
blocks) is always shown when any word differs, regardless of how much has
changed. When most words in a block have changed, the markers cover nearly all
the text and become visual noise — the reader would be better served by plain
block-level coloring (red/green/blue overlays) without inline markers.

This plan adds a similarity threshold so that word-level highlighting is
suppressed when the old and new text are too dissimilar for the markers to be
useful landmarks.


## Design

### Metric

Compute the fraction of the longer side's character count that is unchanged:

```
similarity = unchangedChars / max(oldChars, newChars)
```

Where:

- `unchangedChars` = total `.count` of `.unchanged` span text
- `oldChars` = `unchangedChars` + total `.count` of `.deleted` span text
- `newChars` = `unchangedChars` + total `.count` of `.inserted` span text

Whitespace spans count toward their respective totals. Shared whitespace
between different words is a small fraction of total characters and does not
meaningfully skew the ratio.


### Threshold

**0.25** — at least 25% of the longer side must be unchanged text for
word-level markers to appear. Below that, fewer than 1 in 4 characters survived
and the markers cover so much surface area that they hurt readability.

No minimum word count exemption is needed. For very short blocks (1–2 words)
where the ratio is 0, block-level highlighting is visually equivalent to
word-level highlighting anyway.


### Call sites

All five sites where `WordDiff.diff()` results are checked for changes:

| #   | File                  | Line | Mode | Granularity                   |
| --- | --------------------- | ---- | ---- | ----------------------------- |
| 1   | `DiffContext.swift`   | ~86  | Up   | Block-level word spans        |
| 2   | `LineDiffMap.swift`   | ~210 | Down | Line-level within blocks      |
| 3   | `LineDiffMap.swift`   | ~325 | Down | Line-level within code blocks |
| 4   | `LineDiffMap.swift`   | ~383 | Down | Block-level fallback          |
| 5   | `CodeBlockDiff.swift` | ~223 | Up   | Line-level within code blocks |

All five follow the same pattern today:

```swift
let spans = WordDiff.diff(old: ..., new: ...)
let hasWordChanges = spans.contains { !$0.isUnchanged }
```


## Implementation

### 1. Add `WordDiff.similarity(_:)` in `WordDiff.swift`

A static method that computes the similarity ratio from an existing span array:

```swift
/// Fraction of the longer side (old or new) that is unchanged text.
/// Returns 1.0 when both sides are empty.
static func similarity(_ spans: [WordSpan]) -> Double {
    var unchangedLen = 0, deletedLen = 0, insertedLen = 0
    for span in spans {
        switch span {
        case .unchanged(let t): unchangedLen += t.count
        case .deleted(let t):   deletedLen += t.count
        case .inserted(let t):  insertedLen += t.count
        }
    }
    let total = max(unchangedLen + deletedLen,
                    unchangedLen + insertedLen)
    guard total > 0 else { return 1.0 }
    return Double(unchangedLen) / Double(total)
}
```


### 2. Add `WordDiff.hasSignificantChanges(_:threshold:)` in `WordDiff.swift`

A convenience that combines both checks — has changes AND meets threshold:

```swift
/// True when spans contain word-level changes worth highlighting.
///
/// Returns `false` when all spans are unchanged (nothing to mark)
/// or when similarity is below the threshold (too noisy to be useful).
static func hasSignificantChanges(
    _ spans: [WordSpan], threshold: Double
) -> Bool {
    let hasWordChanges = spans.contains { !$0.isUnchanged }
    guard hasWordChanges else { return false }
    return similarity(spans) >= threshold
}
```


### 3. Add `wordDiffThreshold` to `RenderOptions`

In `RenderOptions.swift`, add a new field in the "Change tracking" section:

```swift
public var wordDiffThreshold: Double = 0.25
```

Include it in `contentIdentity` so the view reloads when the threshold changes.


### 4. Thread the threshold through the rendering pipeline

The threshold must reach all five call sites. The plumbing path differs for Up
mode and Down mode.

**Up mode** — `MudCore.renderUpToHTML` already has `options`. Pass the
threshold into `DiffContext`:

- `DiffContext.init(old:new:)` → `DiffContext.init(old:new:wordDiffThreshold:)`
- Store as a property; use in `finalizeGap()` (site 1)
- `CodeBlockDiff.compute()` (site 5) uses its own `WordDiff.diff` calls — add a
  `wordDiffThreshold` parameter there too

**Down mode** — `MudCore.renderDownToHTML` calls
`downVisitor.highlightWithChanges(...)`. Add a `wordDiffThreshold` parameter
there, and pass it into `LineDiffMap.init(matches:wordDiffThreshold:)`. The
`LineDiffMap` builder uses it at sites 2, 3, and 4.

Summary of signature changes:

| Type                                   | Change                                       |
| -------------------------------------- | -------------------------------------------- |
| `RenderOptions`                        | Add `wordDiffThreshold: Double = 0.25`       |
| `DiffContext.init`                     | Add `wordDiffThreshold: Double = 0.25` param |
| `LineDiffMap.init`                     | Add `wordDiffThreshold: Double = 0.25` param |
| `CodeBlockDiff.compute`                | Add `wordDiffThreshold: Double = 0.25` param |
| `DownHTMLVisitor.highlightWithChanges` | Add `wordDiffThreshold: Double = 0.25` param |


### 5. Read from UserDefaults in `AppState`

Add a `wordDiffThreshold` property to `AppState` with key
`"Mud-WordDiffThreshold"`, defaulting to 0.25. No `@Published` needed — this is
a hidden knob, not wired to any UI or Combine sink. Read once at init.

In `DocumentContentView`, set `opts.wordDiffThreshold` from
`appState.wordDiffThreshold`.


### 6. Replace the five call sites

At each site, replace:

```swift
let hasWordChanges = spans.contains { !$0.isUnchanged }
```

with:

```swift
let hasWordChanges = WordDiff.hasSignificantChanges(
    spans, threshold: wordDiffThreshold)
```

The variable at sites 4 and 5 is currently named `hasChanges` — rename to
`hasWordChanges` for consistency.


## Verification

### Unit tests in `WordDiffTests.swift`

- `similarity` returns 1.0 for identical text (all unchanged)
- `similarity` returns 0.0 for completely different text (no unchanged spans)
- `similarity` returns expected ratio for a known mixed case
- `similarity` returns 1.0 for empty spans
- `hasSignificantChanges` returns `false` for all-unchanged spans
- `hasSignificantChanges` returns `false` when similarity is below threshold
- `hasSignificantChanges` returns `true` when similarity is above threshold


### Integration test in `UpModeChangeTrackingTests.swift`

A test with a paired block where most words have changed (similarity < 0.25)
verifying that the rendered HTML has block-level classes but no inline `<ins>`
or `<del>` tags.


### Manual verification

Open a markdown file with a paragraph change where most words differ. Confirm
that Up mode and Down mode show block-level coloring only (no inline word
markers). Then make a small edit to a long paragraph and confirm word-level
markers still appear.

To override the threshold via `defaults`:

```
defaults write org.josephpearson.Mud Mud-WordDiffThreshold -float 0.4
```

Relaunch the app and verify the new threshold takes effect.
