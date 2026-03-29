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

  // MARK: - Insertions on native elements

  @Test func insertedParagraphHasAttributesOnP() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-ins\""))
    #expect(html.contains("Added."))
    #expect(html.contains("data-change-id"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedHeadingHasAttributesOnH() {
    let old = "Paragraph.\n"
    let new = "Paragraph.\n\n## New heading\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<h2"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("New heading"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedCodeBlockHasAttributesOnPre() {
    let old = "Before.\n"
    let new = "Before.\n\n```\ncode\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<pre"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("code"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedListItemHasAttributesOnLi() {
    let old = "- Alpha\n"
    let new = "- Alpha\n- Beta\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<li"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("Beta"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  // MARK: - Deletions as native elements

  @Test func deletedParagraphEmittedAsNativeP() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-del\""))
    #expect(html.contains("Removed."))
    #expect(html.contains("data-change-id"))
    #expect(!html.contains("<del"), "Deletions must not use <del> wrappers")
  }

  @Test func deletedUnorderedListItemEmittedAsNativeLi() {
    let old = "- Alpha\n- Beta\n- Gamma\n"
    let new = "- Alpha\n- Gamma\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
    #expect(html.contains("Beta"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletedOrderedListItemEmittedAsNativeLi() {
    let old = "1. First\n2. Second\n3. Third\n"
    let new = "1. First\n3. Third\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
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
    let liPattern = /<li>[^<]*Third[^<]*<\/li>/
    if let match = html.firstMatch(of: liPattern) {
      let liContent = String(html[match.range])
      #expect(!liContent.contains("Second"),
        "Surviving item must not contain deleted item's content")
    }
  }

  @Test func deletedItemBeforeComplexItemRendersAsSibling() {
    let old = "1. First\n2. Second\n3. Third\n   - Sub A\n   - Sub B\n"
    let new = "1. First\n3. Third\n   - Sub A\n   - Sub B\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
    #expect(html.contains("Second"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
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

  // MARK: - Replacements (del + ins as native elements)

  @Test func replacedParagraphEmitsNativeDelAndIns() {
    let old = "Original text.\n"
    let new = "Revised text.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // Deletion as native <p>.
    #expect(html.contains("<p class=\"mud-change-del\""))
    #expect(html.contains("Original text."))
    // Insertion as native <p> — no mud-change-mix on content elements.
    #expect(html.contains("<p class=\"mud-change-ins\""))
    #expect(html.contains("Revised text."))
    #expect(!html.contains("<ins"), "Must not use <ins> wrappers")
    #expect(!html.contains("<del"), "Must not use <del> wrappers")
  }

  @Test func replacementOldVersionPrecedesNewVersion() {
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
    #expect(unique.count >= 4) // 2 replacements x (del + ins) each
  }

  // MARK: - Group attributes

  @Test func changedElementsCarryGroupID() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-group-id=\"group-"))
  }

  @Test func firstElementInGroupCarriesGroupIndex() {
    let old = "First.\n"
    let new = "First.\n\nAdded A.\n\nAdded B.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-group-index=\"1\""))
  }

  @Test func groupAttributesConsistentAcrossMultiBlockGroup() {
    let old = "Keep.\n"
    let new = "Keep.\n\nAdded A.\n\nAdded B.\n\nAdded C.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // All three inserted paragraphs should share the same group ID.
    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    #expect(groupIDs.count == 3)
    #expect(Set(groupIDs).count == 1)
  }

  @Test func separateGroupsGetDifferentIDs() {
    let old = "Alpha.\n\nKeep.\n\nGamma.\n"
    let new = "Alpha changed.\n\nKeep.\n\nGamma changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    let unique = Set(groupIDs)
    #expect(unique.count == 2)
  }

  @Test func deletionElementsCarryGroupID() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deleted <p> should carry a group ID.
    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    #expect(!groupIDs.isEmpty)
  }

  // MARK: - Table rows

  @Test func insertedTableRowHasAttributesOnTr() {
    let old = "| A |\n|---|\n| 1 |\n"
    let new = "| A |\n|---|\n| 1 |\n| 2 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<tr"))
    #expect(html.contains("mud-change-ins"))
    #expect(!html.contains("<ins"), "Inserted table row must not use <ins> wrapper")
  }

  @Test func deletedTableRowEmittedAsNativeTr() {
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n"
    let new = "| A |\n|---|\n| 1 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<tr class=\"mud-change-del\""))
    #expect(!html.contains("<del"), "Deleted table row must not use <del> wrapper")
  }

  @Test func deletedTableRowAppearsAsSiblingInTbody() {
    // Deleted row between two surviving rows must appear as a <tr>
    // sibling inside <tbody>, not wrapped in <del>.
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |\n"
    let new = "| A |\n|---|\n| 1 |\n| 3 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deleted row should be a <tr> with the deletion class.
    #expect(html.contains("<tr class=\"mud-change-del\""))
    #expect(html.contains("2"))
    #expect(!html.contains("<del"), "Deleted table row must not use <del> wrapper")

    // The deleted <tr> must be inside <tbody>, not outside the table.
    let tbodyRange = html.range(of: "<tbody>")!
    let tbodyEndRange = html.range(of: "</tbody>")!
    let delTrRange = html.range(of: "mud-change-del")!
    #expect(delTrRange.lowerBound > tbodyRange.lowerBound)
    #expect(delTrRange.upperBound < tbodyEndRange.upperBound)
  }

  // MARK: - Edge cases

  @Test func allContentDeleted() {
    let old = "Gone.\n"
    let new = ""
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-del\""))
    #expect(html.contains("Gone."))
    #expect(!html.contains("<del"), "Must not use <del> wrappers")
  }

  @Test func allContentInserted() {
    let old = ""
    let new = "Brand new.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-ins\""))
    #expect(html.contains("Brand new."))
    #expect(!html.contains("<ins"), "Must not use <ins> wrappers")
  }

  // MARK: - Alerts and asides

  @Test func insertedGFMAlertHasChangeAttributes() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> [!NOTE]\n> Added alert.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("Added alert."))
    #expect(!html.contains("<ins"), "Must not use <ins> wrappers")
  }

  @Test func replacedDocCAsideHasChangeAttributes() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // Content elements use mud-change-ins, not mud-change-mix.
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
  }

  @Test func insertedDocCAsideHasChangeAttributes() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> Note: New aside.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("New aside."))
  }

  @Test func alertChangeAttributeIsOnBlockquote() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The change attributes should be on the <blockquote> tag.
    let pattern = /blockquote class="[^"]*mud-change-ins/
    #expect(html.contains(pattern))
  }
}
