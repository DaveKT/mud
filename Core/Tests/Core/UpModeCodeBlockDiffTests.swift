import Testing
@testable import MudCore

@Suite("Up mode code block diffs")
struct UpModeCodeBlockDiffTests {
  // MARK: - Diffed code block structure

  @Test func changedCodeBlockHasMudCodeDiffClass() {
    let old = "```\nold line\n```\n"
    let new = "```\nnew line\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-code-diff"),
      "Changed code block should have mud-code-diff class")
  }

  @Test func diffedCodeBlockPreHasNoBlockLevelChangeID() {
    // The <pre> itself should NOT have data-change-id — the
    // individual line spans own the change IDs.
    let old = "```\nold\n```\n"
    let new = "```\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // Find the <pre> tag.
    let prePattern = /<pre[^>]*>/
    if let match = html.firstMatch(of: prePattern) {
      let preTag = String(html[match.range])
      #expect(!preTag.contains("data-change-id"),
        "<pre> of diffed code block should not carry data-change-id")
    }
  }

  // MARK: - Line span structure

  @Test func unchangedLinesWrappedInClSpan() {
    let old = "```\nkeep\nold\n```\n"
    let new = "```\nkeep\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<span class=\"cl\">"),
      "Unchanged lines should be wrapped in <span class=\"cl\">")
  }

  @Test func insertedLineHasClInsClass() {
    let old = "```\nkeep\n```\n"
    let new = "```\nkeep\nadded\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("cl-ins"),
      "Inserted lines should have cl-ins class")
  }

  @Test func deletedLineHasClDelClass() {
    let old = "```\nkeep\nremoved\n```\n"
    let new = "```\nkeep\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("cl-del"),
      "Deleted lines should have cl-del class")
  }

  @Test func changedLinesCarryDataAttributes() {
    let old = "```\nold\n```\n"
    let new = "```\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // Line spans should carry data-change-id and data-group-id.
    let clPattern = /<span class="cl cl-(?:ins|del)"[^>]*>/
    let matches = html.matches(of: clPattern)
    #expect(!matches.isEmpty, "Should have cl-ins or cl-del spans")
    for match in matches {
      let tag = String(html[match.range])
      #expect(tag.contains("data-change-id"),
        "Changed line span should carry data-change-id")
      #expect(tag.contains("data-group-id"),
        "Changed line span should carry data-group-id")
    }
  }

  @Test func firstLineInGroupCarriesGroupIndex() {
    let old = "```\nold\n```\n"
    let new = "```\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-group-index"),
      "First line in group should carry data-group-index")
  }

  // MARK: - Syntax highlighting preserved

  @Test func syntaxHighlightingPreservedInDiffedBlock() {
    let old = "```swift\nlet x = 1\n```\n"
    let new = "```swift\nlet y = 2\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // highlight.js spans should be present inside the cl spans.
    #expect(html.contains("hljs-"),
      "Syntax highlighting should be preserved in diffed code block")
  }

  @Test func unchangedLinesRetainSyntaxHighlighting() {
    let old = "```swift\nlet x = 1\nlet y = 2\n```\n"
    let new = "```swift\nlet x = 1\nlet z = 3\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The unchanged "let x = 1" line should be in a plain "cl" span
    // with syntax highlighting inside.
    #expect(html.contains("<span class=\"cl\">"),
      "Unchanged line should use plain cl class")
    #expect(html.contains("hljs-"),
      "Syntax highlighting should be present")
  }

  // MARK: - Non-diffed code blocks unchanged

  @Test func unchangedCodeBlockHasNoClSpans() {
    let old = "```\ncode\n```\n"
    let new = "```\ncode\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(!html.contains("mud-code-diff"),
      "Unchanged code block should not have mud-code-diff class")
    #expect(!html.contains("class=\"cl\""),
      "Unchanged code block should not have cl line spans")
  }

  @Test func newCodeBlockUsesBlockLevelNotLineDiff() {
    // A purely inserted code block (no paired deletion) should
    // get block-level mud-change-ins, not line-level spans.
    let old = "Before.\n"
    let new = "Before.\n\n```\nnew code\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"),
      "New code block should have block-level insertion class")
    #expect(!html.contains("mud-code-diff"),
      "New code block should not have line-level diff")
  }

  // MARK: - Newline placement

  @Test func newlineInsideLineSpan() {
    // The \n must be the last character inside the span (not between
    // spans), per the plan's HTML structure.
    let old = "```\nold\n```\n"
    let new = "```\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // Each cl span should end with \n followed by </span>.
    let clEndPattern = /\n<\/span>/
    let matches = html.matches(of: clEndPattern)
    // There should be at least one (the line spans contain trailing \n).
    #expect(!matches.isEmpty,
      "Line spans should contain trailing newline before </span>")
  }

  // MARK: - Code header preserved

  @Test func codeHeaderPresentInDiffedBlock() {
    let old = "```swift\nold\n```\n"
    let new = "```swift\nnew\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("code-header"),
      "Diffed code block should still have code header")
    #expect(html.contains("code-language"),
      "Diffed code block should still show language label")
  }

  // MARK: - Mermaid code blocks

  @Test func changedMermaidBlockUsesBlockLevelNotLineDiff() {
    let old = "```mermaid\ngraph LR\n  A-->B\n```\n"
    let new = "```mermaid\ngraph LR\n  A-->C\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(!html.contains("mud-code-diff"),
      "Mermaid blocks should not get line-level diff")
    #expect(html.contains("mud-change-ins"),
      "Changed mermaid block should have block-level insertion marker")
  }

  @Test func changedMermaidBlockOldVersionShowsPlaceholder() {
    let old = "```mermaid\ngraph LR\n  A-->B\n```\n"
    let new = "```mermaid\ngraph LR\n  A-->C\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deleted mermaid block should show a placeholder.
    #expect(html.contains("[revised diagram]"),
      "Old mermaid block should show placeholder")
    #expect(!html.contains("A--&gt;B"),
      "Old mermaid source should not appear")
    // The new content should appear.
    #expect(html.contains("A--&gt;C"))
  }

  // MARK: - Multiple groups within one code block

  @Test func multipleGroupsInOneCodeBlock() {
    // Lines 1, 3, 5 unchanged; lines 2 and 4 changed → two groups.
    let old = "```\na\nb\nc\nd\ne\n```\n"
    let new = "```\na\nB\nc\nD\ne\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("mud-code-diff"))

    // Should have at least two distinct group IDs.
    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    let unique = Set(groupIDs)
    #expect(unique.count >= 2,
      "Separated changes should produce multiple groups")
  }

  // MARK: - Ordering within the code element

  @Test func deletionLinesBeforeInsertionLinesInGap() {
    let old = "```\na\nold\nc\n```\n"
    let new = "```\na\nnew\nc\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // Within the changed gap, cl-del should appear before cl-ins.
    if let delRange = html.range(of: "cl-del"),
       let insRange = html.range(of: "cl-ins") {
      #expect(delRange.lowerBound < insRange.lowerBound,
        "Deleted lines should come before inserted lines")
    }
  }

  // MARK: - Edge case: no waypoint

  @Test func noWaypointCodeBlockRendersNormally() {
    let md = "```swift\nlet x = 1\n```\n"
    let html = MudCore.renderUpToHTML(md)
    #expect(!html.contains("mud-code-diff"))
    #expect(!html.contains("cl-ins"))
    #expect(!html.contains("cl-del"))
    #expect(html.contains("<pre class=\"mud-code\">"))
  }
}
