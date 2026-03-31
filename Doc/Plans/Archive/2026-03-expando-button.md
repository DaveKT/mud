Plan: Expando Button for Change Groups
===============================================================================

> Status: Complete


## Context

Previously, selecting a change group in the sidebar auto-expanded it (revealed
deletions, split mixed overlays). The numbered badge on each overlay was a CSS
`::after` pseudo-element with no interactivity.

This plan replaces the `::after` badge with a real `<button>` element that
toggles expand/collapse per group. Sidebar selection becomes scroll-only.


## Behavior by group type

| Type     | Collapsed (default)               | Expanded                                   | Button?        |
| -------- | --------------------------------- | ------------------------------------------ | -------------- |
| Ins-only | N/A (always expanded)             | Normal overlay, always visible             | Yes (disabled) |
| Del-only | 0px-high overlay, top border only | Deletions revealed, overlay sized normally | Yes            |
| Mixed    | Blue overlay at normal size       | Red/green sub-overlays                     | Yes            |

Button appearance:

- **Collapsed**: white text/border, change-color background, 2px border
- **Expanded**: change-color text/border, theme-bg background, 1.5px border
- **Disabled** (ins-only): expanded style, `cursor: default`

For mixed groups when expanded, only the **first sub-overlay** gets the button.


## Files modified

1. `Core/Sources/Core/Resources/mud-changes.css`
2. `Core/Sources/Core/Resources/mud.js`
3. `App/WebView.swift`


## Implementation summary

CSS: replaced `::after` badge with `.mud-expando` button styles, per-type
expanded/collapsed states, and a collapsed overlay rule.

JS: added per-group expand/collapse state and toggle logic. Each overlay gets a
button; del-only overlays start collapsed; mixed overlays split into
sub-overlays on expand with the button moving to the first sub-overlay.
`Mud.revealChanges` removed; `Mud.collapseAllChanges` added.

Swift: sidebar selection now calls only `Mud.scrollToChange()` (no
auto-expand).


## Verification

1. Open a document with tracked changes containing ins-only, del-only, and
   mixed groups.
2. Confirm sidebar selection scrolls to the group without expanding.
3. Click the expando button on a del-only group — deletions appear, button
   inverts to outlined style.
4. Click again — deletions collapse, overlay returns to 0px-high state.
5. Click the expando button on a mixed group — sub-overlays appear, button on
   first sub-overlay.
6. Click again — sub-overlays removed, blue overlay restored.
7. Confirm ins-only groups have a disabled button in expanded style.
8. Resize window — overlays reposition correctly.
9. Test in both light and dark mode.
