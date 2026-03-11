Plan: Mermaid Diagrams Toggle
===============================================================================

> Status: Planning


## Context

Mermaid diagram rendering is always enabled in Up Mode. The `RenderExtension`
system (introduced in f16f2d6) detects `language-mermaid` code blocks and
injects mermaid.min.js at runtime, but there is no way for the user to disable
this.

A toggle in the Up Mode settings pane lets users turn off diagram rendering.
When disabled, mermaid code blocks remain as syntax-highlighted `<pre><code>`
blocks (same as Down Mode shows them).


## Current flow

```
UpHTMLVisitor
  → <pre><code class="language-mermaid">…</code></pre>
  → WebView filters RenderExtension.registry by marker presence in HTML
  → activeExtensions populated with matching RenderExtension values
  → didFinish injects each extension's runtimeJS() sequentially
  → mermaid-init.js replaces <pre> with <div class="mermaid"> and calls mermaid.run()
```

The toggle adds a filter step: exclude `RenderExtension.mermaid` from
`activeExtensions` when the setting is off.


## Changes

### 1. Add `mermaidEnabled` to `AppState`

In `App/AppState.swift`:

- Add `@Published var mermaidEnabled: Bool`.
- UserDefaults key: `"Mud-MermaidEnabled"`.
- Default: `true`.
- Add `saveMermaidEnabled()` method (same pattern as other prefs).


### 2. Gate mermaid extension in `WebView`

In `App/WebView.swift`, `updateNSView`: add a filter to exclude extensions
disabled by settings:

```swift
context.coordinator.activeExtensions = RenderExtension.registry.values
    .filter { html.contains($0.marker) }
    .filter { $0.name != "mermaid" || appState.mermaidEnabled }
```

Include `appState.mermaidEnabled` in `displayContentID` (in
`DocumentContentView.swift`) so toggling the setting triggers a re-render. This
is already handled by `RenderOptions.contentIdentity` — we just need to make
sure the setting flows into the render options or the content ID.

Simplest approach: incorporate `mermaidEnabled` into `displayContentID`
directly, since it affects WebView behaviour but not the HTML itself:

```swift
private var displayContentID: String {
    switch content {
    case .text(let text):
        return "\(text)\(renderOptions.contentIdentity)\(appState.mermaidEnabled)"
    case .error:
        return "load-error"
    }
}
```


### 3. Add toggle to `UpModeSettingsView`

In `App/Settings/UpModeSettingsView.swift`, add a section with a "Mermaid
Diagrams" toggle and a brief description. Place it after the "Allow Remote
Content" section.


### 4. Update `Doc/AGENTS.md`

Add "Mermaid Diagrams" to the `UpModeSettingsView.swift` bullet.


## Files changed

| File                                    | Change                                  |
| --------------------------------------- | --------------------------------------- |
| `App/AppState.swift`                    | Add `mermaidEnabled` property + persist |
| `App/WebView.swift`                     | Filter `activeExtensions` on setting    |
| `App/DocumentContentView.swift`         | Include flag in `displayContentID`      |
| `App/Settings/UpModeSettingsView.swift` | Add Mermaid Diagrams toggle             |
| `Doc/AGENTS.md`                         | Update settings file reference          |


## Verification

- Settings → Up Mode shows a "Mermaid Diagrams" toggle (default: on).
- With toggle on: mermaid code blocks render as diagrams.
- With toggle off: mermaid code blocks render as syntax-highlighted source.
- Toggling triggers an immediate re-render of the current document.
- Down Mode is unaffected regardless of toggle state.
