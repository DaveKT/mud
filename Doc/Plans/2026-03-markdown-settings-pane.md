Plan: Markdown Settings Pane
===============================================================================

> Status: Underway


## Context

The "DocC Asides" setting (a three-way picker: Off / Common / Extended, plus an
interactive reference table) currently lives in the Up Mode settings pane. Now
that alert highlighting is rendered in both Up Mode and Down Mode, this setting
is no longer mode-specific — it controls Markdown _parsing_ behavior that
affects all output.

A new **Markdown** settings pane will house this setting and serve as the
natural home for any future parsing- or content-level preferences (e.g. emoji
shortcodes). The Mermaid Diagrams toggle stays in Up Mode — it controls
client-side rendering that only applies to Up Mode, not Markdown parsing.


## Changes

### 1. Add `SettingsPane.markdown` to the enum

In `App/Settings/SettingsView.swift`:

- Add `.markdown` case between `.general` and `.theme`.
- Title: `"Markdown"`.
- Icon: `"text.document"` (SF Symbols; visually distinct from the existing pane
  icons).
- Route `.markdown` → `MarkdownSettingsView()` in `detailView`.


### 2. Create `App/Settings/MarkdownSettingsView.swift`

New file following the existing settings-view pattern
(`@ObservedObject appState`, `Form` with `.formStyle(.grouped)`, top-padding
hack).

Move the entire DocC Asides section (picker + `AlertReferenceTable` + "Learn
more" link) here verbatim from `UpModeSettingsView`, along with the supporting
private types (`AlertReferenceTable`, `AlertBadgeView`, `AlertCategory.nsImage`
extension).


### 3. Slim down `UpModeSettingsView`

Remove the DocC Asides section and all supporting private types. The pane
retains the "Allow Remote Content" and "Mermaid Diagrams" toggles.


### 4. Update `Doc/AGENTS.md`

Add a bullet under **App/Settings/ key files** for the new file:

```
- `MarkdownSettingsView.swift` — Markdown settings pane (DocC alert mode)
```

Update the existing `UpModeSettingsView.swift` bullet to reflect that it no
longer contains DocC Asides.


## Files changed

| File                                      | Change                                |
| ----------------------------------------- | ------------------------------------- |
| `App/Settings/SettingsView.swift`         | Add `.markdown` case and routing      |
| `App/Settings/MarkdownSettingsView.swift` | New file: DocC Asides setting + table |
| `App/Settings/UpModeSettingsView.swift`   | Remove DocC Asides section            |
| `Doc/AGENTS.md`                           | Update settings file reference        |


## Verification

- Open Settings → the sidebar shows six panes: General, Markdown, Theme, Up
  Mode, Down Mode, Command Line.
- Markdown pane displays the DocC Asides picker and reference table exactly as
  before.
- Up Mode pane retains "Allow Remote Content" and "Mermaid Diagrams" toggles.
- Changing the DocC Asides mode still affects both Up Mode and Down Mode
  rendering.
