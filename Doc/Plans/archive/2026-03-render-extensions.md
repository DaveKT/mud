Plan: Render Extensions
===============================================================================

> Status: Complete


## Context

Mermaid diagram support was hard-wired across three layers: HTMLTemplate (CDN
URL constant, `embedMermaid` conditional), WebView.Coordinator (`needsMermaid`
flag, `injectMermaid()` method), and RenderOptions (`embedMermaid: Bool`).
Adding any future client-side library would duplicate this exact pattern.

This plan introduced a `RenderExtension` type that encapsulates the full
lifecycle of a client-side rendering feature, so that adding a new one means
defining an instance — not threading logic through three files.


## The pattern each extension follows

Every client-side rendering extension has the same shape:

1. **Detection** — check for a marker string in the rendered HTML body.
2. **Embedded export** (CLI `--browser`, Open in Browser) — add `<script>` tags
   to the HTML document; update the CSP to allow them.
3. **Live rendering** (WKWebView) — inject JS resources via
   `evaluateJavaScript` after page load, chained sequentially.

A `RenderExtension` captures all three via fields: `name`, `marker`,
`cspSources`, `embeddedScripts`, and `runtimeResources`.


## Design decision

Option C was chosen: the `RenderExtension` type lives in Core with a static
registry. `RenderOptions.extensions` is a `Set<String>` of extension names.
HTMLTemplate and WebView both look up active extensions from the registry by
name and iterate generically.


## Changes

### `RenderExtension` type

New file `Core/Sources/Core/RenderExtension.swift`. The struct, the `mermaid`
static instance, and the `registry` dictionary. `runtimeJS()` loads resources
via `HTMLTemplate.loadResource`.


### `RenderOptions`

Replaced `embedMermaid: Bool` with `extensions: Set<String>`. `contentIdentity`
includes the sorted extension set, so toggling an extension triggers a
re-render.


### `HTMLTemplate.wrapUp`

The mermaid-specific conditional became a generic loop over
`options.extensions`, looking up each in the registry, checking the marker, and
appending CSP sources and embedded scripts. `loadResource` visibility changed
from `private` to `internal`.


### `WebView.Coordinator`

The `needsMermaid` flag and `injectMermaid()` method were replaced by
`activeExtensions` (resolved from the registry and filtered by marker in
`updateNSView`) and generic `injectExtension` / `injectSequentially` methods
called from `didFinish`.


### Call sites

`DocumentContentView` and `App/CLI/main.swift` changed from
`embedMermaid = true` to `extensions.insert("mermaid")`.


## Files changed

| File                                             | Change                                     |
| ------------------------------------------------ | ------------------------------------------ |
| `Core/Sources/Core/RenderExtension.swift`        | New: type, mermaid instance, registry      |
| `Core/Sources/Core/RenderOptions.swift`          | Replace `embedMermaid` with `extensions`   |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Generic extension loop; adjust visibility  |
| `App/WebView.swift`                              | Generic extension injection                |
| `App/DocumentContentView.swift`                  | Use `extensions` set                       |
| `App/CLI/main.swift`                             | Use `extensions` set                       |
| `Core/Tests/Core/HTMLTemplateTests.swift`        | Update mermaid tests to use extensions set |
| `Doc/AGENTS.md`                                  | Add file reference                         |
