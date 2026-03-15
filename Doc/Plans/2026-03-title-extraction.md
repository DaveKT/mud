Plan: Title Extraction in MudCore
===============================================================================

> Status: Planning


## Context

Window/tab titles currently show the filename (`url.lastPathComponent`). For
stdin-piped content this produces ugly names like `mud-stdin.abc123.md`. We
just added a heuristic `extractTitle` in `DocumentContentView` that strips `#`/
`*` from the first line — it works for window titles, but it's not AST-based
and doesn't feed into the HTML `<title>` element.

Moving title extraction into MudCore means:

- AST-based extraction (uses the parsed heading, not string heuristics)
- HTML `<title>` reflects the document's first heading automatically
- Both the app (window titles) and CLI output benefit
- Single source of truth

Additionally, the app currently parses the markdown AST twice per content
change: once for heading extraction (`extractHeadings`) and once for rendering
(`renderUpModeDocument`). A new `ParsedMarkdown` type eliminates this
redundancy.


## Approach

### 1. Introduce `ParsedMarkdown` in MudCore

New public struct in `Core/Sources/Core/ParsedMarkdown.swift`:

```swift
public struct ParsedMarkdown {
  internal let document: Document
  public let markdown: String
  public let headings: [OutlineHeading]
  public var title: String? { headings.first?.text }

  public init(_ markdown: String) {
    self.markdown = markdown
    self.document = MarkdownParser.parse(markdown)
    var extractor = HeadingExtractor()
    extractor.visit(document)
    self.headings = extractor.headings
  }
}
```

Parses the AST once at init. Headings (and derived title) are computed eagerly
and stored. The internal `document` field lets MudCore rendering functions
reuse the AST without re-parsing.


### 2. Add `ParsedMarkdown` overloads to MudCore

Add rendering overloads that accept `ParsedMarkdown`:

```swift
public static func renderUpToHTML(
  _ parsed: ParsedMarkdown, options: RenderOptions, ...
) -> String {
  var upVisitor = UpHTMLVisitor()
  // configure visitor from options...
  upVisitor.visit(parsed.document)
  return upVisitor.result
}

public static func renderUpModeDocument(
  _ parsed: ParsedMarkdown, options: RenderOptions, ...
) -> String {
  var options = options
  if options.title.isEmpty {
    options.title = parsed.title ?? ""
  }
  let body = renderUpToHTML(parsed, options: options, ...)
  return HTMLTemplate.wrapUp(body: body, options: options)
}
```

Same pattern for `renderDownModeDocument` (auto-populates `<title>` from
`parsed.title`, though Down mode rendering itself is line-based and doesn't use
the AST).

The existing `String`-based functions become thin wrappers:

```swift
public static func renderUpModeDocument(
  _ markdown: String, ...
) -> String {
  renderUpModeDocument(ParsedMarkdown(markdown), ...)
}
```

This preserves backward compatibility — the CLI and any other callers that
don't need to share the parse result can keep passing strings.

Remove the standalone `extractHeadings(_:)` function (replaced by
`ParsedMarkdown.headings`). Or keep it as a convenience wrapper:

```swift
public static func extractHeadings(_ markdown: String) -> [OutlineHeading] {
  ParsedMarkdown(markdown).headings
}
```


### 3. Update `DocumentContentView`

- Store `ParsedMarkdown` alongside or instead of the raw text in content state
- In `loadFromDisk()`, create `ParsedMarkdown(text)` once:

  - `state.outlineHeadings = parsed.headings`
  - `state.contentTitle = parsed.title`
- In `modeHTML`, pass the parsed document to `renderUpModeDocument` (avoids
  re-parsing on theme/zoom/toggle changes)
- Remove the heuristic `extractTitle(from:)` method and its MARK section
- Remove `opts.title = fileURL.lastPathComponent` from `renderOptions` (leave
  it empty so rendering auto-extracts)


### 4. Update CLI (`main.swift`)

- `render()` signature: drop the `title` parameter
- Don't set `options.title` — the `String` convenience wrappers auto-extract
  via `ParsedMarkdown`
- For fragment mode (`-f`), there's no `<title>` element anyway


### 5. No changes needed

- `RenderOptions.swift` — `title` stays as `String = ""`; empty means
  auto-extract
- `HTMLDocument.swift` — already uses `options.title`
- `HTMLTemplate.swift` — untouched
- `HeadingExtractor.swift` — reused as-is by `ParsedMarkdown.init`
- `DocumentWindowController.swift` — already observes `state.contentTitle`
- `DocumentState.swift` — `contentTitle` property stays


## Files to modify

| File                                     | Change                                       |
| ---------------------------------------- | -------------------------------------------- |
| `Core/Sources/Core/ParsedMarkdown.swift` | New file: `ParsedMarkdown` struct            |
| `Core/Sources/Core/MudCore.swift`        | Add `ParsedMarkdown` overloads, wrap old API |
| `App/DocumentContentView.swift`          | Use `ParsedMarkdown`, remove heuristic code  |
| `App/CLI/main.swift`                     | Drop `title` param from `render()`           |


## Parse count comparison

| Scenario                   | Before | After |
| -------------------------- | ------ | ----- |
| Content change (Up mode)   | 2      | 1     |
| Content change (Down mode) | 1      | 1     |
| Re-render (theme/zoom)     | 1      | 0     |


## Verification

- Open a Markdown file with a `# Heading` — window title and `<title>` should
  both show "Heading"
- Open a file with no headings — window title falls back to filename, `<title>`
  is empty
- Pipe stdin: `echo "# Hello" | mud -u` — `<title>` should be "Hello"
- CLI file: `mud -u README.md` — `<title>` should be the first heading
- Fragment mode: `mud -uf README.md` — no `<title>` element (unchanged)
- Open in Browser — exported HTML should have a content-derived `<title>`
