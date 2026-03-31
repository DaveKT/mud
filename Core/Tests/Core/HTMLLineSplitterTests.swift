import Testing
@testable import MudCore

@Suite("HTMLLineSplitter")
struct HTMLLineSplitterTests {
  // MARK: - Basic splitting

  @Test func plainTextSplitsAtNewlines() {
    let lines = HTMLLineSplitter.splitByLine("alpha\nbeta\ngamma")
    #expect(lines == ["alpha", "beta", "gamma"])
  }

  @Test func singleLineReturnsOneElement() {
    let lines = HTMLLineSplitter.splitByLine("hello")
    #expect(lines == ["hello"])
  }

  @Test func emptyStringReturnsOneEmptyElement() {
    let lines = HTMLLineSplitter.splitByLine("")
    #expect(lines == [""])
  }

  @Test func trailingNewlineDoesNotProduceEmptyLine() {
    // Code blocks often end with a trailing \n before the closing
    // fence. Splitting should not produce a phantom empty line.
    let lines = HTMLLineSplitter.splitByLine("line one\nline two\n")
    #expect(lines == ["line one", "line two"])
  }

  @Test func multipleTrailingNewlinesPreserveInternal() {
    // Two trailing newlines: the first ends "line two", the second
    // would be an empty trailing line that should be dropped.
    let lines = HTMLLineSplitter.splitByLine("a\nb\n\n")
    // "a", "b", "" — the empty trailing element is dropped.
    #expect(lines == ["a", "b", ""])
  }

  // MARK: - Span balancing

  @Test func spanClosedAndReopenedAcrossLines() {
    let html = "<span class=\"hljs-keyword\">if\ntrue</span>"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 2)
    #expect(lines[0] == "<span class=\"hljs-keyword\">if</span>")
    #expect(lines[1] == "<span class=\"hljs-keyword\">true</span>")
  }

  @Test func nestedSpansClosedAndReopened() {
    let html = "<span class=\"a\"><span class=\"b\">x\ny</span></span>"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 2)
    // First line: both spans opened, both closed.
    #expect(lines[0] == "<span class=\"a\"><span class=\"b\">x</span></span>")
    // Second line: both reopened, then naturally closed.
    #expect(lines[1] == "<span class=\"a\"><span class=\"b\">y</span></span>")
  }

  @Test func spanOpenedAndClosedOnSameLine() {
    let html = "<span class=\"k\">let</span> x = 1\n<span class=\"k\">var</span> y = 2"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 2)
    #expect(lines[0] == "<span class=\"k\">let</span> x = 1")
    #expect(lines[1] == "<span class=\"k\">var</span> y = 2")
  }

  @Test func multipleSpansOnOneLine() {
    let html = "<span class=\"a\">x</span> <span class=\"b\">y</span>"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 1)
    #expect(lines[0] == html)
  }

  // MARK: - HTML entities preserved

  @Test func htmlEntitiesPreserved() {
    let html = "&lt;div&gt;\n&amp;foo"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines == ["&lt;div&gt;", "&amp;foo"])
  }

  // MARK: - Real highlight.js output patterns

  @Test func highlightJSMultiLineString() {
    // highlight.js wraps multi-line strings in a single span.
    let html = "<span class=\"hljs-string\">\"line 1\nline 2\"</span>"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 2)
    #expect(lines[0].hasPrefix("<span class=\"hljs-string\">"))
    #expect(lines[0].hasSuffix("</span>"))
    #expect(lines[1].hasPrefix("<span class=\"hljs-string\">"))
    #expect(lines[1].hasSuffix("</span>"))
  }

  @Test func highlightJSMultiLineComment() {
    let html = "<span class=\"hljs-comment\">/* start\n   middle\n   end */</span>"
    let lines = HTMLLineSplitter.splitByLine(html)
    #expect(lines.count == 3)
    for line in lines {
      #expect(line.hasPrefix("<span class=\"hljs-comment\">"))
      #expect(line.hasSuffix("</span>"))
    }
  }
}
