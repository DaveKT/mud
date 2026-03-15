Plan: Title Extraction in MudCore
===============================================================================

> Status: Complete


## Context

Window/tab titles showed the filename (`url.lastPathComponent`). For
stdin-piped content this produced ugly names like `mud-stdin.abc123.md`, and
the HTML `<title>` element never reflected the document's actual content.

Goals:

- AST-based title extraction (first heading), not string heuristics
- HTML `<title>` auto-populated from the first heading
- Both the app (window titles) and CLI output benefit
- Eliminate redundant AST parses per content change


## What was implemented

### `ParsedMarkdown` struct (MudCore)

A parse-once handle that carries the AST, headings, and a derived title
(`headings.first?.text`). Created once per content change; reused for heading
extraction, title derivation, and rendering without re-parsing.


### MudCore rendering overloads

`renderUpToHTML`, `renderUpModeDocument`, and `renderDownModeDocument` gained
`ParsedMarkdown` overloads that reuse the pre-parsed AST. When `options.title`
is empty (the default), the document renderers auto-populate `<title>` from the
first heading. The existing `String`-based API became thin wrappers for
backward compatibility.


### App integration

`DocumentContentView` stores `ParsedMarkdown` instead of raw text. On load,
headings, title, and the parsed document are all derived from a single parse.
Re-renders from theme/zoom/toggle changes reuse the stored AST (zero
re-parses).


### CLI

The `render()` function dropped its `title` parameter. Auto-extraction via the
`String` convenience wrappers handles it.


### Settings toggle

A "First heading as window title" toggle was added under Settings > Markdown,
defaulting to on. When off, the window title falls back to the filename. The
HTML `<title>` is unaffected — it always auto-extracts for export and CLI.


## Parse count comparison

| Scenario                   | Before | After |
| -------------------------- | ------ | ----- |
| Content change (Up mode)   | 2      | 1     |
| Content change (Down mode) | 1      | 1     |
| Re-render (theme/zoom)     | 1      | 0     |
