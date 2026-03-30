Plan: Word-Level Diffs
===============================================================================

> Status: Planning


## Context

Block-level change tracking shows entire paragraphs as inserted or deleted.
When a single word changes in a paragraph, the user sees the whole old
paragraph in red and the whole new paragraph in green — with no indication of
what specifically changed. Word-level diffs highlight the individual words that
differ, making changes immediately scannable.

This plan covers paired blocks with matching inline structure. When the inline
structure diverges (e.g., formatting boundaries shift), we fall back to
block-level highlighting. Formatting-only changes (same words, different
emphasis) are not highlighted at the word level.


## Step 1: Block pairing in DiffContext

**File:** `Core/Sources/Core/Diff/DiffContext.swift`

BlockMatcher's `buildResult` emits deletions before insertions within each gap.
Use this ordering to pair them positionally: the i-th deletion in a gap pairs
with the i-th insertion. Unpaired blocks (more deletions than insertions or
vice versa) remain unpaired.

Add a `pairMap: [String: String]` to DiffContext, mapping each insertion's
change ID to its paired deletion's change ID (and vice versa). Computed during
the match-processing loop by collecting deletions and insertions per gap:

```swift
// After processing a gap's matches, pair by position.
let pairs = zip(gapDeletionIDs, gapInsertionIDs)
for (delID, insID) in pairs {
    pairMap[delID] = insID
    pairMap[insID] = delID
}
```

New public API:

```swift
func pairedChangeID(for changeID: String) -> String?
```


### RenderedDeletion gains word spans

When a deletion is paired with an insertion, compute word spans and store them
on the `RenderedDeletion`. Also store word spans on the `AnnotationEntry` for
the paired insertion.

```swift
struct RenderedDeletion {
    // ... existing fields ...
    let wordSpans: [WordSpan]?  // nil when unpaired
}

private struct AnnotationEntry {
    let annotation: BlockAnnotation
    let changeID: String
    let wordSpans: [WordSpan]?  // nil when unpaired
}
```


## Step 2: Word diff algorithm

**File:** `Core/Sources/Core/Diff/WordDiff.swift` (new)

Myers diff on word arrays, producing a list of spans:

```swift
enum WordSpan {
    case unchanged(String)
    case inserted(String)
    case deleted(String)
}

enum WordDiff {
    static func diff(old: String, new: String) -> [WordSpan]
}
```

Tokenization splits on whitespace boundaries, preserving whitespace in the
tokens (e.g., `"hello "` and `"world"`) so that reconstructing the text from
spans is lossless.

The diff operates on the plain text extracted from each block's inline content.
It does not see or operate on formatting — formatting is handled separately
during rendering (Step 4).


## Step 3: Inline structure comparison

**File:** `Core/Sources/Core/Diff/WordDiff.swift`

Before computing word spans, verify that the old and new blocks have compatible
inline structure. "Compatible" means the sequence of inline formatting nodes
matches — same nesting of Strong, Emphasis, Strikethrough, InlineCode, Link,
etc., differing only in the text content of their Text leaf nodes.

```swift
enum WordDiff {
    /// Returns true if two markup nodes have the same inline
    /// formatting structure (ignoring text content).
    static func hasMatchingStructure(
        _ old: Markup, _ new: Markup
    ) -> Bool
}
```

This walks both trees in parallel, comparing node types at each level. If the
structure diverges at any point, return false — the caller falls back to
block-level highlighting.

When computing word spans for a structurally compatible pair, diff only the
text leaf content. The spans are interleaved with formatting boundaries so the
renderer knows where to open and close `<ins>`/ `<del>` within the existing
inline structure.

The span list is flat — it represents the full inline content in document
order, with each span tagged as unchanged/inserted/deleted. Formatting
boundaries are not encoded in the spans; they're handled by the renderer
walking the AST in parallel with the span list.


## Step 4: Up mode rendering

**File:** `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`

When visiting a block that has `wordSpans`, the visitor uses a modified inline
walk. Instead of the normal `visitText` (which emits the text node's content
verbatim), it consumes spans from the word span list. Which span types are
emitted depends on the block's role:

**Blue block** (paired insertion — visible by default, blue overlay):

- `unchanged` spans → emit as normal text
- `inserted` spans → wrap in `<ins>`
- `deleted` spans → wrap in `<del>` (old words shown inline for context)

**Red block** (paired deletion — hidden, shown on reveal):

- `unchanged` spans → emit as normal text
- `deleted` spans → wrap in `<del>`
- `inserted` spans → skip entirely

**Green block** (pure insertion — no paired deletion): no word spans, renders
normally at block level.

The same span list drives both the blue and red blocks; only the rendering
filter differs. The formatting structure (Strong, Emphasis, etc.) is walked
normally — the visitor opens and closes `<strong>`, `<em>`, etc. as usual. Only
the Text leaf nodes are affected, emitting word spans instead of their literal
content.

A `wordSpanCursor` index tracks position in the span list as the visitor
descends through inline nodes.


### Example output

Old paragraph: `"The quick brown fox"`

New paragraph: `"The slow brown dog"`

Word spans:
`[unchanged("The "), deleted("quick "), inserted("slow "), unchanged("brown "), deleted("fox"), inserted("dog")]`

Blue block (paired insertion, visible by default):

```html
<p class="mud-change-ins" data-change-id="change-2" data-group-id="group-1">
The <del>quick </del><ins>slow </ins>brown <del>fox</del><ins>dog</ins>
</p>
```

Red block (paired deletion, hidden by default, shown on reveal):

```html
<p class="mud-change-del" data-change-id="change-1" data-group-id="group-1">
The <del>quick </del>brown <del>fox</del>
</p>
```

The red block reads as the original text with removed words highlighted. The
blue block shows the new text with both removed and added words marked, giving
a complete inline diff.


## Step 5: Down mode rendering

**File:** `Core/Sources/Core/Rendering/DownHTMLVisitor.swift`

Down mode renders syntax-highlighted source lines. When a line falls within a
paired block that has word spans, the line's content gets inline `<ins>`/
`<del>` markers within the existing syntax `<span>` structure.

The approach: after rendering a line's syntax spans, post-process the HTML to
splice in word-level markers. This is simpler than modifying the syntax
highlighting pipeline, which operates on raw source bytes.

Alternatively, if the syntax spans and word spans don't interact well (syntax
highlighting splits tokens differently from word boundaries), we could apply
word-level markers to the raw text first, then syntax-highlight the result.
This needs experimentation during implementation.


## Step 6: CSS for inline changes

**File:** `Core/Sources/Core/Resources/mud-changes.css`

Inline `<ins>` and `<del>` within changed blocks need distinct styling from
block-level changes:

```css
/* Inline word-level markers within changed blocks */
[data-change-id] ins {
    text-decoration: none;
    background: color-mix(in srgb, var(--change-ins) 25%, transparent);
    border-radius: 2px;
}

[data-change-id] del {
    text-decoration: line-through;
    text-decoration-color: var(--change-del);
    background: color-mix(in srgb, var(--change-del) 15%, transparent);
    border-radius: 2px;
}
```


## Files to modify

| File                                                | Change                                   |
| --------------------------------------------------- | ---------------------------------------- |
| `Core/Sources/Core/Diff/DiffContext.swift`          | Block pairing, word spans on annotations |
| `Core/Sources/Core/Diff/WordDiff.swift`             | New: Myers diff, structure comparison    |
| `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`   | Word-span-aware inline rendering         |
| `Core/Sources/Core/Rendering/DownHTMLVisitor.swift` | Word-level markers in syntax lines       |
| `Core/Sources/Core/Resources/mud-changes.css`       | Inline ins/del styles                    |


## Verification

1. `swift test` — all existing tests pass
2. Change one word in a paragraph — inline `<del>`/ `<ins>` markers around the
   changed word, rest of paragraph unmarked
3. Change multiple words — each changed word independently marked
4. Add/remove a sentence — word-level markers for added/removed words
5. Change formatting only (bold a word) — falls back to block-level
   highlighting, no word markers
6. Change both words and formatting — falls back to block-level
7. Down mode shows word-level markers in syntax-highlighted lines
8. Unpaired blocks (pure insertion/deletion with no counterpart) — no word
   markers, block-level only
