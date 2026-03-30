Plan: Markdown Settings Pane
===============================================================================

> Status: Complete


## Context

The "DocC Asides" setting (a three-way picker: Off / Common / Extended, plus an
interactive reference table) lived in the Up Mode settings pane. Once alert
highlighting was rendered in both Up Mode and Down Mode, this setting was no
longer mode-specific — it controls Markdown parsing behavior that affects all
output.

A new **Markdown** settings pane houses this setting and serves as the natural
home for future parsing- or content-level preferences. The Mermaid Diagrams
toggle stays in Up Mode — it controls client-side rendering, not Markdown
parsing.


## Changes

### 1. Add `SettingsPane.markdown` to the enum

Added `.markdown` case between `.general` and `.theme` in `SettingsView.swift`,
with title "Markdown", icon `"text.document"`, routed to
`MarkdownSettingsView()`.


### 2. Create `MarkdownSettingsView.swift`

New file following the existing settings-view pattern. Moved the entire DocC
Asides section (picker, `AlertReferenceTable`, "Learn more" link) and
supporting private types from `UpModeSettingsView`.


### 3. Slim down `UpModeSettingsView`

Removed the DocC Asides section and all supporting private types. The pane
retains the "Allow Remote Content" and "Mermaid Diagrams" toggles.


### 4. Update `Doc/AGENTS.md`

Added a bullet for `MarkdownSettingsView.swift` and updated the
`UpModeSettingsView.swift` description.


## Files changed

| File                                      | Change                                |
| ----------------------------------------- | ------------------------------------- |
| `App/Settings/SettingsView.swift`         | Add `.markdown` case and routing      |
| `App/Settings/MarkdownSettingsView.swift` | New file: DocC Asides setting + table |
| `App/Settings/UpModeSettingsView.swift`   | Remove DocC Asides section            |
| `Doc/AGENTS.md`                           | Update settings file reference        |
