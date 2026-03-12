Plan: HTML Document Builder
===============================================================================

> Status: Complete


## Context

`HTMLTemplate.wrapUp` built the final HTML document via a single string
interpolation. Every feature that conditionally added scripts, modified CSP
directives, or injected attributes was interleaved into one expression. Mermaid
embedding scattered logic across CSP construction, script-tag generation, and
body closing — all inside the same interpolated string.

Meanwhile, `WebView.injectState` post-processed the finished HTML string,
replacing `<html>` with `<html class="..." style="...">` via
`String.replacingOccurrences(of:)`. This was fragile and conceptually belonged
in the same assembly step.


## Design

### `HTMLDocument` — a structured intermediate

A lightweight value type that accumulates document-level concerns as data, then
serializes them in one `render()` method. Fields include `title`, `baseURL`,
`styles`, `cspImgSrc`, `cspScriptSrc`, `htmlClasses`, `htmlStyles`,
`bodyContent`, and `bodyScripts`. The initializer reads shared display-state
fields (`htmlClasses`, `zoomLevel`) directly from `RenderOptions`.

`render()` is the only place that produces HTML. It assembles CSP from the
accumulated source arrays, concatenates styles, appends scripts before
`</body>`, and applies HTML-element attributes.


### How `wrapUp` and `wrapDown` changed

Both became thin builders that populate an `HTMLDocument` and call `render()`.
Each concern (styles, CSP, extensions/scripts) is a clear, self-contained
block. The extension loop in `wrapUp` checks each registered
`RenderExtension`'s marker against the body and appends its CSP sources and
embedded scripts — adding a future feature (e.g. KaTeX) means registering an
extension, not editing the template.


### `WebView.injectState` eliminated

View-state injection (body classes, zoom) moved into `RenderOptions` as
`htmlClasses: Set<String>` and `zoomLevel: Double`.
`HTMLDocument.init(options:)` reads these fields and populates `htmlClasses`
and `htmlStyles` accordingly. `WebView.injectState` was removed entirely — no
more string replacement on rendered HTML.


### Scope boundaries

`HTMLDocument` lives in Core alongside `HTMLTemplate`. It is an internal type —
not part of MudCore's public API. The public API remains the
`renderUpModeDocument` / `renderDownModeDocument` functions that return
`String`.


## Changes

### 1. Add `HTMLDocument` to Core

New file `Core/Sources/Core/Rendering/HTMLDocument.swift`. The struct, its
`init(options:)`, `render()`, and private helpers for CSP, attributes, and
script assembly.


### 2. Refactor `HTMLTemplate.wrapUp`

Replaced the string interpolation with `HTMLDocument` builder pattern.
Extension handling (Mermaid et al.) uses the `RenderExtension` registry loop
instead of hard-coded conditionals.


### 3. Refactor `HTMLTemplate.wrapDown`

Same pattern. Down mode has no scripts or CSP complexity, but uses the same
`render()` path for consistency.


### 4. Eliminate `WebView.injectState`

`RenderOptions` gained `htmlClasses` and `zoomLevel` fields.
`HTMLDocument.init(options:)` consumes them. `WebView.injectState` was deleted.


### 5. Update tests

Existing `HTMLTemplateTests` assertions continued to pass against the rendered
output string.


### 6. Update `Doc/AGENTS.md`

Added `HTMLDocument.swift` to the Core file reference.


## Files changed

| File                                             | Change                                   |
| ------------------------------------------------ | ---------------------------------------- |
| `Core/Sources/Core/Rendering/HTMLDocument.swift` | New: structured HTML document builder    |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Refactor wrapUp/wrapDown to use builder  |
| `Core/Sources/Core/RenderOptions.swift`          | Add `htmlClasses` and `zoomLevel` fields |
| `App/WebView.swift`                              | Remove `injectState`                     |
| `Core/Tests/Core/HTMLTemplateTests.swift`        | Update tests                             |
| `Doc/AGENTS.md`                                  | Add file reference                       |


## What this did NOT change

- **MudCore's public API.** The `renderUpModeDocument` /
  `renderDownModeDocument` functions still accept `RenderOptions` and return
  `String`. `HTMLDocument` is an internal implementation detail.

- **WKWebView JS injection.** The in-app mermaid path (loading mermaid.min.js
  via `evaluateJavaScript` after page load) is unrelated to document assembly.
  It stays in `WebView.Coordinator`.
