import Foundation
import Testing
@testable import MudCore

@Suite("Up mode change tracking")
struct UpModeChangeTrackingTests {
  // MARK: - No-op when waypoint is nil

  @Test func noWaypointProducesNoMarkers() {
    let html = MudCore.renderUpToHTML("Hello.\n")
    #expect(!html.contains("mud-change"))
    #expect(!html.contains("data-change-id"))
  }

  @Test func identicalContentProducesNoMarkers() {
    let md = "Hello.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(md)
    let html = MudCore.renderUpToHTML(md, options: opts)
    #expect(!html.contains("mud-change"))
  }

  // MARK: - Insertions

  @Test func insertedParagraphWrappedInIns() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<ins class=\"mud-change mud-change-ins\""))
    #expect(html.contains("Added."))
    #expect(html.contains("data-change-id"))
  }

  @Test func insertedHeadingWrappedInIns() {
    let old = "Paragraph.\n"
    let new = "Paragraph.\n\n## New heading\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<ins class=\"mud-change mud-change-ins\""))
    #expect(html.contains("<h2"))
    #expect(html.contains("New heading"))
  }

  @Test func insertedCodeBlockWrappedInIns() {
    let old = "Before.\n"
    let new = "Before.\n\n```\ncode\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<ins class=\"mud-change mud-change-ins\""))
    #expect(html.contains("code"))
  }

  @Test func insertedListItemWrappedInIns() {
    let old = "- Alpha\n"
    let new = "- Alpha\n- Beta\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<ins class=\"mud-change mud-change-ins\""))
    #expect(html.contains("Beta"))
  }

  // MARK: - List item deletions

  @Test func deletedUnorderedListItemProducesValidHTML() {
    let old = "- Alpha\n- Beta\n- Gamma\n"
    let new = "- Alpha\n- Gamma\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deletion must be a <li> carrying the del class — not a <del>
    // wrapping a <li>, which is invalid HTML inside <ul>.
    #expect(html.contains("mud-change-del"))
    #expect(html.contains("Beta"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletedOrderedListItemProducesValidHTML() {
    let old = "1. First\n2. Second\n3. Third\n"
    let new = "1. First\n3. Third\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("mud-change-del"))
    #expect(html.contains("Second"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletedListItemContentDoesNotLeakIntoSurvivor() {
    let old = "1. First\n2. Second\n3. Third\n"
    let new = "1. First\n3. Third\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // "Second" and "Third" must not appear in the same <li>.
    // Find the <li> that contains "Third" and verify it does not
    // also contain "Second".
    let liPattern = /<li>[^<]*Third[^<]*<\/li>/
    if let match = html.firstMatch(of: liPattern) {
      let liContent = String(html[match.range])
      #expect(!liContent.contains("Second"),
        "Surviving item must not contain deleted item's content")
    }
  }

  @Test func deletedItemBeforeComplexItemRendersAsSibling() {
    // When the surviving item has a nested list, BlockMatcher
    // decomposes it into paragraph + sub-items. The deletion must
    // still appear as its own <li>, not inside the next item.
    let old = "1. First\n2. Second\n3. Third\n   - Sub A\n   - Sub B\n"
    let new = "1. First\n3. Third\n   - Sub A\n   - Sub B\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("mud-change-del"))
    #expect(html.contains("Second"))
    // The deletion must not be inside the <li> that contains "Third".
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  // MARK: - Deletions

  @Test func deletedParagraphEmittedAsDel() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<del class=\"mud-change mud-change-del\""))
    #expect(html.contains("Removed."))
    #expect(html.contains("data-change-id"))
  }

  @Test func deletionAppearsBeforeSurvivingBlock() {
    let old = "First.\n\nRemoved.\n\nLast.\n"
    let new = "First.\n\nLast.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delRange = html.range(of: "mud-change-del")!
    let lastRange = html.range(of: "Last.")!
    #expect(delRange.lowerBound < lastRange.lowerBound)
  }

  @Test func trailingDeletionAppearsAtEnd() {
    let old = "Keep.\n\nTrailing.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let keepRange = html.range(of: "Keep.")!
    let delRange = html.range(of: "Trailing.")!
    #expect(keepRange.lowerBound < delRange.lowerBound)
  }

  @Test func multipleDeletionsBeforeOneBlock() {
    let old = "Gone A.\n\nGone B.\n\nSurvivor.\n"
    let new = "Survivor.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("Gone A."))
    #expect(html.contains("Gone B."))
    let delA = html.range(of: "Gone A.")!
    let survivor = html.range(of: "Survivor.")!
    #expect(delA.lowerBound < survivor.lowerBound)
  }

  // MARK: - Modifications

  @Test func modifiedParagraphEmitsDelAndIns() {
    let old = "Original text.\n"
    let new = "Revised text.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<del class=\"mud-change mud-change-del\""))
    #expect(html.contains("Original text."))
    #expect(html.contains("<ins class=\"mud-change mud-change-mod\""))
    #expect(html.contains("Revised text."))
  }

  @Test func modificationOldVersionPrecedesNewVersion() {
    let old = "Original.\n"
    let new = "Changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delRange = html.range(of: "Original.")!
    let insRange = html.range(of: "Changed.")!
    #expect(delRange.lowerBound < insRange.lowerBound)
  }

  // MARK: - Deletion HTML content

  @Test func deletionContainsRenderedHTML() {
    let old = "Keep.\n\n**Bold deleted.**\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<strong>Bold deleted.</strong>"))
    #expect(!html.contains("**Bold deleted.**"))
  }

  // MARK: - Change IDs

  @Test func changeIDsPresent() {
    let old = "First.\n"
    let new = "First.\n\nSecond.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-change-id=\"change-"))
  }

  @Test func multipleChangesHaveDistinctIDs() {
    let old = "Alpha.\n\nBeta.\n"
    let new = "Alpha changed.\n\nBeta changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let idPattern = /data-change-id="(change-\d+)"/
    let ids = html.matches(of: idPattern).map { String($0.1) }
    let unique = Set(ids)
    #expect(unique.count == ids.count)
    #expect(unique.count >= 4) // 2 modifications x (del + ins) each
  }

  // MARK: - Edge cases

  @Test func allContentDeleted() {
    let old = "Gone.\n"
    let new = ""
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<del class=\"mud-change mud-change-del\""))
    #expect(html.contains("Gone."))
  }

  @Test func allContentInserted() {
    let old = ""
    let new = "Brand new.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<ins class=\"mud-change mud-change-ins\""))
    #expect(html.contains("Brand new."))
  }

  // MARK: - Alerts and asides

  @Test func insertedGFMAlertHasChangeMarkers() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> [!NOTE]\n> Added alert.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("Added alert."))
  }

  @Test func modifiedDocCAsideHasChangeMarkers() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-mod"))
    #expect(html.contains("data-change-id"))
  }

  @Test func insertedDocCAsideHasChangeMarkers() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> Note: New aside.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("New aside."))
  }

  @Test func alertChangeMarkerIsInsideBlockquote() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The <ins> should be inside the <blockquote>, not wrapping it.
    let bqRange = html.range(of: "blockquote")!
    let insRange = html.range(of: "mud-change-mod")!
    #expect(bqRange.lowerBound < insRange.lowerBound)
  }
}
