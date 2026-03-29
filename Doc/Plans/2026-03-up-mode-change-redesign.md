Plan: Up Mode Change Tracking Redesign
===============================================================================

> Status: Planning


## Context

The current Up mode change tracking wraps changed blocks in `<ins>` and `<del>`
elements. This causes invalid HTML inside tables and lists, requires
per-element-type special casing (`wrapperTag` for list items, a planned
table-specific rendering path), and creates a visual disconnect between sidebar
groups and per-block highlights in the document.

This redesign replaces wrappers with attributes on native elements, computes
change groups at diff time (not just in the sidebar), and renders one
JS-positioned overlay per group with a numbered badge. The overlay spans from
the top of the first block to the bottom of the last block in the group,
covering inter-block margins seamlessly.


## Step 1: DiffContext — add group assignments

**File:** `Core/Sources/Core/Diff/DiffContext.swift`


### GroupInfo

Add a `GroupInfo` struct and a `groupMap` to DiffContext:

```swift
enum GroupPos: String {
    case first, middle, last, sole
}

struct GroupInfo {
    let groupID: String   // "group-1", "group-2", ...
    let groupPos: GroupPos
    let groupIndex: Int   // 1-based, for the badge number
    let isMixed: Bool     // group contains both deletions and insertions
}
```


### Grouping pass

After the existing match-processing loop (which assigns change IDs and builds
annotations / deletion maps), run a grouping pass over all change IDs in
document order. Track a `lastWasChange` flag, mirroring the `isConsecutive`
logic from `ChangeList`:

- `.unchanged` → set `lastWasChange = false`
- `.deleted` / `.inserted` → record the change ID and whether it's consecutive
  (`lastWasChange` was true)

Walk the collected IDs and consecutive flags. Break into groups at
non-consecutive boundaries. For each group, compute:

- `isMixed` — contains both deletion and insertion change IDs
- Positions: `"sole"` if one member; `"first"` / `"middle"` / `"last"`
  otherwise

Store results in `groupMap: [String: GroupInfo]`.


### Updated RenderedDeletion

Replace `wrapperTag: String?` with:

```swift
let tag: String          // "p", "li", "tr", "h2", "pre", "hr", "div"
```

The `html` field continues to hold inner content only (no outer tag). The `tag`
field is derived from the block's AST node type:

| Markup type     | tag     | Notes                                       |
| --------------- | ------- | ------------------------------------------- |
| `Paragraph`     | `"p"`   | Empty string for tight-list text nodes      |
| `Heading`       | `"hN"`  |                                             |
| `CodeBlock`     | `"pre"` | Inner content includes `<code>` with syntax |
| `ListItem`      | `"li"`  |                                             |
| `Table.Head`    | `"tr"`  |                                             |
| `Table.Row`     | `"tr"`  |                                             |
| `ThematicBreak` | `"hr"`  | Self-closing; `html` is empty               |
| `HTMLBlock`     | `"div"` | Fallback wrapper                            |

For all block types, render only children (no outer element). The current code
already does this for `ListItem`; generalize to all types.


### New public API

```swift
func groupInfo(for changeID: String) -> GroupInfo?
```


## Step 2: ChangeList — add group fields

**File:** `Core/Sources/Core/Diff/ChangeList.swift`

Add `groupID: String` and `groupIndex: Int` to `DocumentChange`, populated from
`DiffContext.groupInfo(for:)`. The `isConsecutive` field can remain for now but
the sidebar will group by `groupID` instead.


## Step 3: UpHTMLVisitor — attributes on native elements

**File:** `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`


### Remove emitChangeOpen / emitChangeClose / inMixedRun

Replace with a single helper that returns an attribute string:

```swift
private mutating func changeAttributes(for node: Markup) -> ChangeAttrs
```

`ChangeAttrs` is a small struct:

```swift
struct ChangeAttrs {
    let classes: String   // "mud-change-ins", "mud-change-del", or ""
    let dataAttrs: String // ' data-change-id="..." data-group-id="..."'
    var isEmpty: Bool { classes.isEmpty }
}
```

Split into `classes` and `dataAttrs` so callers can merge the class with their
own (e.g. `<pre class="mud-code {classes}"`).

Content elements only use two classes: `mud-change-ins` and `mud-change-del`.
There is no `mud-change-mix` on content elements — the overlay element carries
`mud-overlay-mix` and handles the blue/green color. This eliminates the
`inMixedRun` tracking state from the visitor entirely.

This method:

1. Calls `emitPrecedingDeletions(before: node)` (new method — emits deleted
   blocks as native elements with deletion attributes).
2. Returns the attributes for the current node (empty if unchanged).


### emitPrecedingDeletions

New private method. For each preceding deletion:

```html
<{tag} class="mud-change-del" data-change-id="change-2"
       data-group-id="group-1">{innerHTML}</{tag}>
```

Self-closing tags (hr): `<hr class="mud-change-del" ... />`


### Update every visit method

Each block visitor interpolates the attributes into its opening tag:

```swift
mutating func visitParagraph(_ paragraph: Paragraph) {
    let attrs = changeAttributes(for: paragraph)
    if inTightList && paragraph.parent is ListItem {
        if !attrs.isEmpty {
            result += "<span\(attrs.asString)>"
            descendInto(paragraph)
            result += "</span>\n"
        } else {
            descendInto(paragraph)
            result += "\n"
        }
    } else {
        result += "<p\(attrs.asString)>"
        descendInto(paragraph)
        result += "</p>\n"
    }
}
```

Table rows get attributes naturally — no special table rendering code:

```swift
mutating func visitTableRow(_ tableRow: Table.Row) {
    currentCellColumn = 0
    let attrs = changeAttributes(for: tableRow)
    result += "<tr\(attrs.asString)>\n"
    descendInto(tableRow)
    result += "</tr>\n"
}
```

For `<pre>` (which already has `class="mud-code"`), merge classes:

```swift
result += "<pre class=\"mud-code\(attrs.classes.isEmpty ? "" : " \(attrs.classes)")\"\(attrs.dataAttrs)>"
```

For `HTMLBlock` and `ThematicBreak` (can't carry attributes natively), wrap in
`<div>` when changed.


### emitTrailingDeletions

Updated to emit native elements using each deletion's `tag` field, same pattern
as `emitPrecedingDeletions`.


### Alert handling

For alerts (GFM and DocC), the change attributes go on the `<blockquote>`
opening tag:

```swift
result += "<blockquote class=\"alert \(category.cssClass)\(attrs.classes.isEmpty ? "" : " \(attrs.classes)")\"\(attrs.dataAttrs)>\n"
```


## Step 4: CSS — overlays, deletions, table rows

**File:** `Core/Sources/Core/Resources/mud-changes.css`


### Overlay elements

The overlays are absolutely positioned within `.up-mode-output` (which already
has `overflow-x: hidden`). JS sets `top` and `height`; CSS handles everything
else:

```css
.mud-overlay {
    position: absolute;
    left: 0;
    right: 0;
    pointer-events: none;
    border: 1px solid;
    z-index: -1;
}

.mud-overlay-ins { background: var(--change-ins-tint); color: var(--change-ins); }
.mud-overlay-mix { background: var(--change-mix-tint); color: var(--change-mix); }
.mud-overlay-del { background: var(--change-del-tint); color: var(--change-del); }

@media (prefers-color-scheme: dark) {
.mud-overlay { mix-blend-mode: screen; }
}
```

Note: no `left: -100vw` hack needed. The overlay is a child of
`.up-mode-output`, which has `overflow-x: hidden`. Setting `left: 0; right: 0`
fills the container width. If full-bleed beyond the container is desired, use
negative margins or extend to viewport width.


### Number badges

The badge is a `::before` pseudo-element on the overlay:

```css
.mud-overlay::before {
    content: attr(data-group-index);
    position: absolute;
    right: calc(100% + 8px);
    top: 0;
    min-width: 1.4em;
    height: 1.4em;
    line-height: 1.4em;
    text-align: center;
    font-size: 0.7em;
    font-weight: 600;
    border-radius: 50%;
    color: white;
    pointer-events: none;
}

.mud-overlay-ins::before { background: var(--change-ins); }
.mud-overlay-mix::before { background: var(--change-mix); }
.mud-overlay-del::before { background: var(--change-del); }
```

Since the badge lives on the overlay element (not on a `<tr>` or `<li>`), it
works uniformly for all block types. No table-specific badge injection needed.


### Deletions

Deleted blocks are native elements hidden by default:

```css
.mud-change-del { display: none; }

.mud-change-del.mud-change-revealed {
    position: relative;
    text-decoration: line-through;
    text-decoration-color: color-mix(in srgb, var(--change-del) 50%, transparent);
    text-decoration-thickness: 1.5px;
}

/* Tag-specific display when revealed */
p.mud-change-del.mud-change-revealed,
div.mud-change-del.mud-change-revealed,
pre.mud-change-del.mud-change-revealed,
h1.mud-change-del.mud-change-revealed,
h2.mud-change-del.mud-change-revealed,
h3.mud-change-del.mud-change-revealed,
h4.mud-change-del.mud-change-revealed,
h5.mud-change-del.mud-change-revealed,
h6.mud-change-del.mud-change-revealed,
hr.mud-change-del.mud-change-revealed   { display: block; }
li.mud-change-del.mud-change-revealed   { display: list-item; }
tr.mud-change-del.mud-change-revealed   { display: table-row; }
span.mud-change-del.mud-change-revealed { display: inline; }
```


### Table rows

No `::after` pseudo-elements needed on `<tr>` — the JS overlay covers the
table. Table rows only need the deletion reveal styles above.


### Active highlight animation

Flash animation on overlays when a group is selected in the sidebar:

```css
.mud-overlay.mud-change-active {
    animation: overlay-flash 1s ease-out;
}

@keyframes overlay-flash {
    0%   { opacity: 1; filter: brightness(1.5); }
    100% { opacity: 1; filter: brightness(1); }
}
```


## Step 5: JS — overlay creation and positioning

**File:** `Core/Sources/Core/Resources/mud.js`

JavaScript discovers groups from `data-group-id` attributes on changed
elements, creates one overlay `<div>` per group, and positions it to span from
the first visible element to the last.


### buildOverlays

Creates overlay elements by walking `[data-group-id]` elements in the DOM.
Called once on load (content reloads replace the entire HTML, so overlays are
rebuilt from scratch each time).

```js
var _overlays = {};  // groupID → overlay element

function buildOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;

    // Remove any existing overlays.
    var old = container.querySelectorAll(".mud-overlay");
    for (var i = 0; i < old.length; i++) old[i].remove();
    _overlays = {};

    // Discover groups from data-group-id attributes.
    var els = container.querySelectorAll("[data-group-id]");
    var groups = {};  // groupID → { index, hasDel, hasIns }
    for (var j = 0; j < els.length; j++) {
        var gid = els[j].dataset.groupId;
        if (!groups[gid]) {
            groups[gid] = {
                index: els[j].dataset.groupIndex || "",
                hasDel: false,
                hasIns: false
            };
        }
        if (els[j].classList.contains("mud-change-del")) {
            groups[gid].hasDel = true;
        } else {
            groups[gid].hasIns = true;
        }
    }

    // Create one overlay per group.
    for (var gid in groups) {
        var g = groups[gid];
        var typeClass = (g.hasDel && g.hasIns) ? "mud-overlay-mix"
                      : g.hasIns ? "mud-overlay-ins"
                      : "mud-overlay-del";
        var div = document.createElement("div");
        div.className = "mud-overlay " + typeClass;
        div.dataset.groupId = gid;
        div.dataset.groupIndex = g.index;
        div.setAttribute("aria-hidden", "true");
        container.appendChild(div);
        _overlays[gid] = div;
    }

    positionOverlays();
}
```

The `data-group-index` attribute on the first element of each group carries the
badge number. The visitor emits it on the first changed element per group
(where `groupPos` is `"first"` or `"sole"`).


### positionOverlays

Measures and positions all overlays. Called after `buildOverlays`, on resize,
and after reveal/hide:

```js
function positionOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;
    var containerRect = container.getBoundingClientRect();

    for (var gid in _overlays) {
        var overlay = _overlays[gid];
        var els = container.querySelectorAll(
            "[data-group-id='" + gid + "']:not(.mud-overlay)"
        );

        // Find visible elements (skip display:none deletions).
        var visible = [];
        for (var j = 0; j < els.length; j++) {
            if (els[j].offsetParent !== null) visible.push(els[j]);
        }

        if (visible.length === 0) {
            overlay.style.display = "none";
            continue;
        }

        var firstRect = visible[0].getBoundingClientRect();
        var lastRect = visible[visible.length - 1].getBoundingClientRect();

        overlay.style.display = "";
        overlay.style.top = (firstRect.top - containerRect.top
                             + container.scrollTop) + "px";
        overlay.style.height = (lastRect.bottom - firstRect.top) + "px";
    }
}
```


### Initialization and recalculation triggers

```js
// Build overlays on load.
buildOverlays();

// Reposition on resize.
var _resizeObs = new ResizeObserver(positionOverlays);
var _container = document.querySelector(".up-mode-output");
if (_container) _resizeObs.observe(_container);
```

At the end of `revealChanges()`, call `positionOverlays()` to adjust for
shown/hidden deletion blocks.


### Updated scrollToChange

Instead of adding `mud-change-active` to individual content elements, add it to
the overlay for the group:

```js
function scrollToChange(ids) {
    if (!ids.length) return;
    // Scroll to the first element.
    var first = document.querySelector(
        '[data-change-id="' + ids[0] + '"]'
    );
    if (first) first.scrollIntoView({ behavior: "smooth", block: "center" });

    // Flash the overlay.
    var gid = first && first.dataset.groupId;
    if (!gid) return;
    var overlay = document.querySelector(
        '.mud-overlay[data-group-id="' + gid + '"]'
    );
    if (!overlay) return;
    overlay.classList.add("mud-change-active");
    setTimeout(function() {
        overlay.classList.remove("mud-change-active");
    }, 2000);
}
```


### Updated revealChanges

Simplified: only `mud-change-del` elements need toggling. The overlay handles
the visual color change. No `mud-change-mix` class on content elements.

```js
function revealChanges(ids) {
    // Clear previous reveals.
    var revealed = document.querySelectorAll(".mud-change-revealed");
    for (var i = 0; i < revealed.length; i++) {
        revealed[i].classList.remove("mud-change-revealed");
    }

    // Reveal deletions and update their group's overlay.
    var revealedGroupIds = {};
    for (var j = 0; j < ids.length; j++) {
        var el = document.querySelector(
            '[data-change-id="' + ids[j] + '"]'
        );
        if (!el) continue;
        if (el.classList.contains("mud-change-del")) {
            el.classList.add("mud-change-revealed");
        }
        var gid = el.dataset.groupId;
        if (gid) revealedGroupIds[gid] = true;
    }

    // Switch overlay from blue to green for revealed groups.
    for (var gid in revealedGroupIds) {
        var overlay = _overlays[gid];
        if (overlay) overlay.classList.add("mud-change-revealed");
    }

    positionOverlays();
}
```

CSS for the revealed overlay:

```css
.mud-overlay-mix.mud-change-revealed {
    background: var(--change-ins-tint);
    color: var(--change-ins);
}
```


## Step 6: Sidebar — group by groupID

**File:** `App/ChangesSidebarView.swift`

Simplify `ChangeGroup.build(from:)` to group by `DocumentChange.groupID`
instead of recomputing from `isConsecutive`. The group index, mixed state, and
member IDs are already computed by DiffContext.


## Step 7: Tests

Update expectations in:

- `UpModeChangeTrackingTests` — expect attributes on native elements
  (`<p class="mud-change-ins" ...>`) instead of `<ins>` wrappers
- `DiffContextTests` — verify `groupInfo` is populated, verify `tag` on
  `RenderedDeletion`
- `ChangeListTests` — verify `groupID` and `groupIndex` on `DocumentChange`
- `BlockMatcherTests` — no changes (matcher is unchanged)
- `DownModeChangeTrackingTests` — no changes (Down mode is unchanged)

Add new tests for:

- Table row insertion/deletion produces `<tr>` with change attributes
- Deleted list item renders as `<li class="mud-change-del" ...>`
- Group attributes (`data-group-id`) are consistent across a multi-block group
- `data-group-index` present on the first element of each group


## Future: Expando widget

The overlay badge is the foundation for an inline expando widget on mixed
(blue) groups. The widget would allow users to expand a blue group to reveal
its deletion blocks directly in the document, without using the sidebar.

Implementation sketch:

- The badge `::before` on mixed overlays gains `pointer-events: auto` and
  `cursor: pointer`
- A JS click handler toggles `mud-change-revealed` on all `mud-change-del`
  elements in the same `data-group-id`, and calls `positionOverlays()` to
  resize the overlay
- The badge switches between a disclosure triangle (collapsed) and the group
  number (expanded)
- Expanding in the document also selects the group in the sidebar (via the JS
  bridge calling `window.webkit.messageHandlers`)

This is deferred to a follow-up task.


## Files to modify

| File                                              | Change                                    |
| ------------------------------------------------- | ----------------------------------------- |
| `Core/Sources/Core/Diff/DiffContext.swift`        | GroupInfo, groupMap, tag on RenderedDel   |
| `Core/Sources/Core/Diff/ChangeList.swift`         | groupID/groupIndex on DocumentChange      |
| `Core/Sources/Core/Rendering/UpHTMLVisitor.swift` | changeAttributes, overlays, visit methods |
| `Core/Sources/Core/Resources/mud-changes.css`     | Overlay styles, badges, deletion display  |
| `Core/Sources/Core/Resources/mud.js`              | positionOverlays, updated scroll/reveal   |
| `App/ChangesSidebarView.swift`                    | Group by groupID                          |
| `Core/Tests/Core/UpModeChangeTrackingTests.swift` | Update expectations                       |
| `Core/Tests/Core/DiffContextTests.swift`          | Test groupInfo and tag                    |
| `Core/Tests/Core/ChangeListTests.swift`           | Test groupID and groupIndex               |


## Verification

1. `swift test` — all tests pass
2. Insert a new paragraph — green overlay with badge number, matching sidebar
3. Edit a paragraph — blue overlay (folded), green+red when expanded
4. Insert a new table — all rows green
5. Delete one table row — deleted row hidden, red when revealed
6. Multiple consecutive changes — single overlay spanning all blocks (including
   inter-block margins), one badge, matching sidebar group
7. Resize the window — overlays reposition correctly
8. Light and dark mode both look correct
9. Down mode unchanged
