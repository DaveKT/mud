import Testing
@testable import MudCore

@Suite("Down mode change tracking")
struct DownModeChangeTrackingTests {
  // MARK: - No-op when waypoint is nil

  @Test func noWaypointProducesNoMarkers() {
    let html = MudCore.renderDownToHTML("Hello.\n")
    #expect(!html.contains("dl-ins"))
    #expect(!html.contains("dl-del"))
    #expect(!html.contains("data-change-id"))
  }

  @Test func identicalContentProducesNoMarkers() {
    let md = "Hello.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(md)
    let html = MudCore.renderDownToHTML(md, options: opts)
    #expect(!html.contains("dl-ins"))
    #expect(!html.contains("dl-del"))
  }

  // MARK: - Insertions

  @Test func insertedParagraphLineMarkedAsInsertion() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Added."))
    #expect(html.contains("data-change-id"))
  }

  @Test func multiLineInsertionMarksAllLines() {
    let old = "Keep.\n"
    let new = "Keep.\n\nLine one.\nLine two.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("Line one."))
    #expect(html.contains("Line two."))
    // Both content lines of the inserted paragraph should be marked.
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    #expect(insCount >= 2)
  }

  // MARK: - Deletions

  @Test func deletedParagraphLineMarkedAsDeletion() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Removed."))
    #expect(html.contains("data-change-id"))
  }

  @Test func deletedLinesShowDashLineNumber() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Deleted lines use an en dash instead of a number.
    #expect(html.contains("<span class=\"ln\">\u{2013}</span>"))
  }

  @Test func deletionAppearsAtCorrectPosition() {
    let old = "First.\n\nMiddle.\n\nLast.\n"
    let new = "First.\n\nLast.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // "Middle." should appear between "First." and "Last.".
    let firstRange = html.range(of: "First.")!
    let middleRange = html.range(of: "Middle.")!
    let lastRange = html.range(of: "Last.")!
    #expect(firstRange.lowerBound < middleRange.lowerBound)
    #expect(middleRange.lowerBound < lastRange.lowerBound)
  }

  @Test func trailingDeletionAppearsAtEnd() {
    let old = "Keep.\n\nTrailing.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let keepRange = html.range(of: "Keep.")!
    let delRange = html.range(of: "Trailing.")!
    #expect(keepRange.lowerBound < delRange.lowerBound)
  }

  // MARK: - Replacements (del + ins)

  @Test func replacedBlockShowsOldAndNewLines() {
    let old = "Original text.\n"
    let new = "Revised text.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Original"))
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Revised"))
  }

  @Test func replacementOldLinesPrecedeNewLines() {
    let old = "Original.\n"
    let new = "Changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let delRange = html.range(of: "Original.")!
    let insRange = html.range(of: "Changed.")!
    #expect(delRange.lowerBound < insRange.lowerBound)
  }

  // MARK: - Line numbers

  @Test func survivingLinesKeepNewDocumentLineNumbers() {
    let old = "First.\n\nRemoved.\n\nThird.\n"
    let new = "First.\n\nThird.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // New doc: line 1 = "First.", line 2 = "", line 3 = "Third."
    // Deleted lines get "–", surviving lines keep their new-doc numbers.
    #expect(html.contains("<span class=\"ln\">1</span>"))
    #expect(html.contains("<span class=\"ln\">3</span>"))
  }

  // MARK: - Change IDs

  @Test func changeIDsOnChangedLines() {
    let old = "First.\n"
    let new = "First.\n\nSecond.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("data-change-id=\"change-"))
  }

  // MARK: - Syntax highlighting of deleted lines

  @Test func deletedHeadingRetainsSyntaxHighlighting() {
    let old = "# Heading\n\nKeep.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // The deleted heading line should carry md-heading syntax spans.
    #expect(html.contains("md-heading"))
    #expect(html.contains("Heading"))
  }

  // MARK: - Word-level diffs

  @Test func wordChangedInPairedBlockShowsInlineMarkers() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Insertion line should contain inline <ins> and <del>.
    #expect(html.contains("<ins>"))
    #expect(html.contains("<del>"))
    #expect(html.contains("slow"))
    #expect(html.contains("quick"))
  }

  @Test func deletionLineInPairedBlockShowsDelOnly() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Isolate deletion divs — split on </div> and filter.
    let delDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-del") }
    #expect(!delDivs.isEmpty, "Should have at least one deletion div")
    for div in delDivs {
      #expect(!div.contains("<ins>"),
        "Deletion line must not contain <ins>")
    }
  }

  @Test func unpairedInsertionHasNoInlineMarkers() {
    let old = "Keep.\n"
    let new = "Keep.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insLines = html.components(separatedBy: "\n")
      .filter { $0.contains("dl-ins") }
    for line in insLines {
      #expect(!line.contains("<ins>"),
        "Unpaired insertion should not have word-level markers")
      #expect(!line.contains("<del>"),
        "Unpaired insertion should not have word-level markers")
    }
  }

  // MARK: - Edge cases

  @Test func allContentDeleted() {
    let old = "Gone.\n"
    let new = ""
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Gone."))
  }

  @Test func allContentInserted() {
    let old = ""
    let new = "Brand new.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Brand new."))
  }
}
