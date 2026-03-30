Plan: Render Options
===============================================================================

> Status: Complete


## Context

Every new rendering option (e.g. `doccAlertMode`) required changes to multiple
MudCore function signatures, `HTMLTemplate.wrapUp`, and every call site
(`DocumentContentView`, CLI, open-in-browser). The root cause was that
rendering options were threaded as individual function parameters rather than
grouped into a value type.

This plan introduced a `RenderOptions` struct in MudCore that bundles all
rendering configuration, making signatures stable across future additions.


## Design

### `RenderOptions` — a value type in Core

A single, flat `Sendable` and `Equatable` struct that travels from the call
site into MudCore's rendering pipeline. Initial fields: `title`, `baseURL`,
`theme`, `includeBaseTag`, `blockRemoteContent`, `embedMermaid`, and
`doccAlertMode`. The `resolveImageSource` closure stays as a separate function
parameter since it is a rendering behavior, not a configuration value.

A single struct (rather than separate Up/Down structs) keeps the API simple.
Unused fields have harmless defaults.


### How it flows

```
AppState (App)
  → builds RenderOptions from its @Published properties
  → passed to MudCore.renderUpModeDocument / renderDownModeDocument
  → MudCore unpacks into UpHTMLVisitor, HTMLTemplate, etc.

CLI argument parsing
  → builds RenderOptions
  → passed to MudCore
```


## Changes

### 1. Add `RenderOptions` to Core

New file `Core/Sources/Core/RenderOptions.swift`. The struct includes a
`contentIdentity` computed property covering content-affecting options, used by
`WebView` to detect when a reload is needed.


### 2. Refactor MudCore public API

Replaced parameter lists with `RenderOptions` across all four public functions:
`renderUpToHTML`, `renderUpModeDocument`, `renderDownToHTML`, and
`renderDownModeDocument`. Each takes `options: RenderOptions` (plus
`resolveImageSource` for the Up functions).


### 3. Refactor `HTMLTemplate.wrapUp` and `wrapDown`

Both internal functions adopted `RenderOptions` to avoid re-spreading fields.


### 4. Update `DocumentContentView`

Added a computed `renderOptions` property that builds the struct from
`AppState`. Replaced the manual `displayContentID` string with
`renderOptions.contentIdentity`.


### 5. Update CLI

Builds a `RenderOptions` from parsed arguments.


### 6. Update tests

Test call sites switched to building a `RenderOptions`.


### 7. Extract `AppState` into its own file

Moved the `AppState` class from `MudApp.swift` into `App/AppState.swift`. Small
extensions (`isSandboxed`, `URL.isBundleResource`, `UTType.markdown`) stayed in
`MudApp.swift`.


### 8. Update `Doc/AGENTS.md`

Added `RenderOptions.swift` to the Core file reference and `AppState.swift` to
the App file reference. Updated the rendering pipeline section.


## What this did NOT change

- **AppState persistence.** The `@Published` properties, UserDefaults keys, and
  `save*()` methods stayed as-is.

- **ViewToggle.** The CSS-class toggles flow through `bodyClasses` on
  `WebView`, not through MudCore rendering.

- **WebView parameters.** `WebView` takes its own display-state parameters
  (html, mode, theme, bodyClasses, zoomLevel). These are view state, not
  rendering options.


## Files changed

| File                                             | Change                             |
| ------------------------------------------------ | ---------------------------------- |
| `Core/Sources/Core/RenderOptions.swift`          | New: `RenderOptions` struct        |
| `Core/Sources/Core/MudCore.swift`                | Adopt `RenderOptions` in all APIs  |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Adopt `RenderOptions` in wrappers  |
| `App/AppState.swift`                             | New: extracted from `MudApp.swift` |
| `App/MudApp.swift`                               | Remove `AppState` class            |
| `App/DocumentContentView.swift`                  | Build + pass `RenderOptions`       |
| `App/CLI/main.swift`                             | Build + pass `RenderOptions`       |
| `Core/Tests/Core/UpHTMLVisitorTests.swift`       | Update test call sites             |
| `Doc/AGENTS.md`                                  | Add file references                |
