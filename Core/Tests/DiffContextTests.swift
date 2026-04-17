import Markdown
import Testing
@testable import MudCore

@Suite("DiffContext")
struct DiffContextTests {
  // MARK: - Annotation lookup

  @Test func insertedBlockAnnotatedAsInserted() {
    let old = ParsedMarkdown("First.\n")
    let new = ParsedMarkdown("First.\n\nAdded.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 2)
    #expect(context.annotation(for: leaves[0]) == nil) // First: unchanged
    #expect(context.annotation(for: leaves[1]) == .inserted)
  }

  @Test func replacedBlockAnnotatedAsInserted() {
    let old = ParsedMarkdown("Original.\n")
    let new = ParsedMarkdown("Revised.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)
    #expect(context.annotation(for: leaves[0]) == .inserted)
  }

  @Test func unchangedBlockReturnsNilAnnotation() {
    let md = "Paragraph.\n"
    let old = ParsedMarkdown(md)
    let new = ParsedMarkdown(md)
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)
    #expect(context.annotation(for: leaves[0]) == nil)
  }

  @Test func identicalDocumentsProduceNoAnnotations() {
    let md = "# Title\n\nFirst.\n\nSecond.\n"
    let old = ParsedMarkdown(md)
    let new = ParsedMarkdown(md)
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.allSatisfy { context.annotation(for: $0) == nil })
  }

  @Test func multipleAnnotationTypes() {
    let old = ParsedMarkdown("Keep.\n\nModify this.\n")
    let new = ParsedMarkdown("Keep.\n\nModified now.\n\nBrand new.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 3)
    #expect(context.annotation(for: leaves[0]) == nil)       // Keep: unchanged
    #expect(context.annotation(for: leaves[1]) == .inserted) // Modified now
    #expect(context.annotation(for: leaves[2]) == .inserted) // Brand new
  }

  // MARK: - Deleted blocks are not annotated in new AST

  @Test func deletedBlocksHaveNoAnnotationInNewAST() {
    // Deleted blocks don't exist in the new AST, so annotation(for:)
    // should never return .deleted — deletions surface via
    // precedingDeletions(before:).
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)
    #expect(context.annotation(for: leaves[0]) == nil) // Keep: unchanged
    // No leaf in the new AST should ever get a .deleted annotation.
  }

  // MARK: - Preceding deletions

  @Test func deletedBlockAppearsBeforeNextSurvivor() {
    let old = ParsedMarkdown("First.\n\nDeleted.\n\nThird.\n")
    let new = ParsedMarkdown("First.\n\nThird.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 2)

    // No deletions before "First."
    #expect(context.precedingDeletions(before: leaves[0]).isEmpty)

    // "Deleted." should appear before "Third."
    let deletions = context.precedingDeletions(before: leaves[1])
    #expect(deletions.count == 1)
  }

  @Test func multipleDeletionsBeforeSameBlock() {
    let old = ParsedMarkdown("Keep.\n\nRemoved A.\n\nRemoved B.\n\nAfter.\n")
    let new = ParsedMarkdown("Keep.\n\nAfter.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 2)

    let deletions = context.precedingDeletions(before: leaves[1])
    #expect(deletions.count == 2)
  }

  @Test func replacedBlockOldVersionAppearsBeforeNewVersion() {
    let old = ParsedMarkdown("Original paragraph.\n")
    let new = ParsedMarkdown("Revised paragraph.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)

    // The old version appears as a preceding deletion before the new.
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.count == 1)
  }

  @Test func noPrecedingDeletionsForUnchangedDocument() {
    let md = "Alpha.\n\nBeta.\n"
    let old = ParsedMarkdown(md)
    let new = ParsedMarkdown(md)
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.allSatisfy { context.precedingDeletions(before: $0).isEmpty })
  }

  // MARK: - Trailing deletions

  @Test func trailingDeletionsAttachToLastSurvivor() {
    let old = ParsedMarkdown("Keep.\n\nTrailing A.\n\nTrailing B.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)

    // No block follows the deletions. They should attach after the last
    // surviving block. Test via a dedicated accessor or by verifying they
    // appear as preceding deletions of the last block.
    let trailing = context.trailingDeletions()
    #expect(trailing.count == 2)
  }

  @Test func noTrailingDeletionsWhenNoneExist() {
    let old = ParsedMarkdown("Keep.\n\nAlso keep.\n")
    let new = ParsedMarkdown("Keep.\n\nAlso keep.\n")
    let context = DiffContext(old: old, new: new)

    #expect(context.trailingDeletions().isEmpty)
  }

  // MARK: - Rendered deletion content

  @Test func renderedDeletionContainsHTML() {
    let old = ParsedMarkdown("Keep.\n\n**Bold deleted text.**\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions.count == 1)

    // The rendered deletion should be HTML, not raw markdown.
    let html = deletions[0].html
    #expect(html.contains("<strong>"))
    #expect(html.contains("Bold deleted text."))
    #expect(!html.contains("**")) // No raw markdown markers
  }

  @Test func renderedDeletionForReplacedBlockContainsOldHTML() {
    let old = ParsedMarkdown("Hello *world*.\n")
    let new = ParsedMarkdown("Goodbye *world*.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.count == 1)

    let html = deletions[0].html
    #expect(html.contains("Hello"))
    #expect(html.contains("<em>world</em>"))
  }

  // MARK: - Change IDs

  @Test func renderedDeletionsCarryChangeIDs() {
    let old = ParsedMarkdown("Keep.\n\nDeleted.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions.count == 1)
    #expect(!deletions[0].changeID.isEmpty)
  }

  @Test func annotatedBlocksCarryChangeIDs() {
    let old = ParsedMarkdown("Original.\n")
    let new = ParsedMarkdown("Revised.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let id = context.changeID(for: leaves[0])
    #expect(id != nil)
    #expect(!id!.isEmpty)
  }

  @Test func unchangedBlocksHaveNoChangeID() {
    let md = "Paragraph.\n"
    let new = ParsedMarkdown(md)
    let context = DiffContext(old: ParsedMarkdown(md), new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.changeID(for: leaves[0]) == nil)
  }

  // MARK: - Group info

  @Test func singleInsertionHasSoleGroup() {
    let old = ParsedMarkdown("First.\n")
    let new = ParsedMarkdown("First.\n\nAdded.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let id = context.changeID(for: leaves[1])!
    let info = context.groupInfo(for: id)
    #expect(info != nil)
    #expect(info!.groupPos == .sole)
    #expect(info!.groupIndex == 1)
    #expect(!info!.isMixed)
  }

  @Test func singleDeletionHasSoleGroup() {
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions.count == 1)
    let info = context.groupInfo(for: deletions[0].changeID)
    #expect(info != nil)
    #expect(info!.groupPos == .sole)
    #expect(!info!.isMixed)
  }

  @Test func replacementFormsMixedGroup() {
    let old = ParsedMarkdown("Original.\n")
    let new = ParsedMarkdown("Revised.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let insID = context.changeID(for: leaves[0])!
    let delID = context.precedingDeletions(before: leaves[0])[0].changeID

    let insInfo = context.groupInfo(for: insID)!
    let delInfo = context.groupInfo(for: delID)!

    // Same group.
    #expect(insInfo.groupID == delInfo.groupID)
    #expect(insInfo.isMixed)
    #expect(delInfo.isMixed)
  }

  @Test func consecutiveInsertionsShareGroup() {
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\nAdded A.\n\nAdded B.\n\nAdded C.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let idA = context.changeID(for: leaves[1])!
    let idB = context.changeID(for: leaves[2])!
    let idC = context.changeID(for: leaves[3])!

    let infoA = context.groupInfo(for: idA)!
    let infoB = context.groupInfo(for: idB)!
    let infoC = context.groupInfo(for: idC)!

    // All in the same group.
    #expect(infoA.groupID == infoB.groupID)
    #expect(infoB.groupID == infoC.groupID)

    // Positions.
    #expect(infoA.groupPos == .first)
    #expect(infoB.groupPos == .middle)
    #expect(infoC.groupPos == .last)
  }

  @Test func unchangedBlockBreaksGroups() {
    let old = ParsedMarkdown("First.\n\nMiddle.\n\nLast.\n")
    let new = ParsedMarkdown("First changed.\n\nMiddle.\n\nLast changed.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let id1 = context.changeID(for: leaves[0])!
    let id3 = context.changeID(for: leaves[2])!

    let info1 = context.groupInfo(for: id1)!
    let info3 = context.groupInfo(for: id3)!

    // Different groups because "Middle." is unchanged.
    #expect(info1.groupID != info3.groupID)
    #expect(info1.groupIndex == 1)
    #expect(info3.groupIndex == 2)
  }

  @Test func groupInfoReturnsNilForUnknownID() {
    let md = "Paragraph.\n"
    let context = DiffContext(old: ParsedMarkdown(md), new: ParsedMarkdown(md))
    #expect(context.groupInfo(for: "nonexistent") == nil)
  }

  // MARK: - Rendered deletion tag

  @Test func deletedParagraphHasPTag() {
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions.count == 1)
    #expect(deletions[0].tag == "p")
  }

  @Test func deletedListItemHasLiTag() {
    let old = ParsedMarkdown("- Alpha\n- Beta\n")
    let new = ParsedMarkdown("- Alpha\n")
    let context = DiffContext(old: old, new: new)

    // "Beta" deletion appears as trailing (after the last leaf).
    let trailing = context.trailingDeletions()
    #expect(trailing.count == 1)
    #expect(trailing[0].tag == "li")
  }

  @Test func deletedHeadingHasHTag() {
    let old = ParsedMarkdown("# Title\n\nKeep.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.count == 1)
    #expect(deletions[0].tag == "h1")
  }

  @Test func deletedCodeBlockHasPreTag() {
    let old = ParsedMarkdown("Keep.\n\n```\ncode\n```\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let trailing = context.trailingDeletions()
    #expect(trailing.count == 1)
    #expect(trailing[0].tag == "pre")
  }

  @Test func deletedThematicBreakHasHrTag() {
    let old = ParsedMarkdown("Keep.\n\n---\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let trailing = context.trailingDeletions()
    #expect(trailing.count == 1)
    #expect(trailing[0].tag == "hr")
  }

  @Test func deletedParagraphHTMLIsInnerOnly() {
    // The html field should contain inner content without a <p> wrapper,
    // since the rendering layer will emit the <p> with change attributes.
    let old = ParsedMarkdown("Keep.\n\n**Bold deleted.**\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions.count == 1)
    #expect(deletions[0].html.contains("<strong>Bold deleted.</strong>"))
    #expect(!deletions[0].html.contains("<p>"))
  }

  // MARK: - Block pairing

  @Test func singleReplacementIsPaired() {
    let old = ParsedMarkdown("Original paragraph.\n")
    let new = ParsedMarkdown("Revised paragraph.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let insID = context.changeID(for: leaves[0])!
    let delID = context.precedingDeletions(before: leaves[0])[0].changeID

    #expect(context.pairedChangeID(for: insID) == delID)
    #expect(context.pairedChangeID(for: delID) == insID)
  }

  @Test func twoReplacementsInOneGapPairPositionally() {
    let old = ParsedMarkdown("Keep.\n\nFirst old.\n\nSecond old.\n\nEnd.\n")
    let new = ParsedMarkdown("Keep.\n\nFirst new.\n\nSecond new.\n\nEnd.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // leaves[0] = Keep, leaves[1] = First new, leaves[2] = Second new, leaves[3] = End

    let ins1 = context.changeID(for: leaves[1])!
    let ins2 = context.changeID(for: leaves[2])!

    let dels1 = context.precedingDeletions(before: leaves[1])
    let dels2 = context.precedingDeletions(before: leaves[2])

    // First deletion pairs with first insertion, second with second.
    if !dels1.isEmpty {
      #expect(context.pairedChangeID(for: ins1) == dels1[0].changeID)
      #expect(context.pairedChangeID(for: dels1[0].changeID) == ins1)
    }
    if !dels2.isEmpty {
      #expect(context.pairedChangeID(for: ins2) == dels2[0].changeID)
    }
  }

  @Test func moreDeletionsThanInsertionsLeavesExcessUnpaired() {
    // Three paragraphs deleted, one inserted → only one pair.
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("New.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let insID = context.changeID(for: leaves[0])!

    // The first deletion should be paired; the other two are unpaired.
    let pairedDel = context.pairedChangeID(for: insID)
    #expect(pairedDel != nil)

    // Collect all deletion IDs.
    let preceding = context.precedingDeletions(before: leaves[0])
    let trailing = context.trailingDeletions()
    let allDelIDs = (preceding + trailing).map(\.changeID)

    // Exactly one deletion is paired.
    let pairedCount = allDelIDs.filter {
      context.pairedChangeID(for: $0) != nil
    }.count
    #expect(pairedCount == 1)
  }

  @Test func moreInsertionsThanDeletionsLeavesExcessUnpaired() {
    let old = ParsedMarkdown("Old.\n")
    let new = ParsedMarkdown("New A.\n\nNew B.\n\nNew C.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let ids = leaves.compactMap { context.changeID(for: $0) }

    // Only the first insertion should be paired.
    let pairedCount = ids.filter {
      context.pairedChangeID(for: $0) != nil
    }.count
    #expect(pairedCount == 1)
  }

  @Test func pureDeletionIsUnpaired() {
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let delID = context.trailingDeletions()[0].changeID
    #expect(context.pairedChangeID(for: delID) == nil)
  }

  @Test func pureInsertionIsUnpaired() {
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\nAdded.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let insID = context.changeID(for: leaves[1])!
    #expect(context.pairedChangeID(for: insID) == nil)
  }

  @Test func separateGapsPairIndependently() {
    // Two separate replacement gaps, each with one del+ins pair.
    let old = ParsedMarkdown("Alpha.\n\nKeep.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha new.\n\nKeep.\n\nGamma new.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let id1 = context.changeID(for: leaves[0])!
    let id3 = context.changeID(for: leaves[2])!

    // Each insertion should be paired with the deletion in its own gap.
    let pair1 = context.pairedChangeID(for: id1)
    let pair3 = context.pairedChangeID(for: id3)
    #expect(pair1 != nil)
    #expect(pair3 != nil)
    #expect(pair1 != pair3)
  }

  // MARK: - Word spans on paired blocks

  @Test func pairedReplacementWithMatchingStructureCarriesWordSpans() {
    let old = ParsedMarkdown("The quick fox.\n")
    let new = ParsedMarkdown("The slow fox.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let insSpans = context.wordSpans(for: leaves[0])
    #expect(insSpans != nil, "Paired insertion should carry word spans")
    if let insSpans {
      let hasDeleted = insSpans.contains(where: \.isDeleted)
      let hasInserted = insSpans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }

    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions[0].wordSpans != nil,
      "Paired deletion should carry word spans")
  }

  @Test func formattingOnlyChangeHasNilWordSpans() {
    // Same words, different formatting → no word-level markers.
    let old = ParsedMarkdown("Hello world.\n")
    let new = ParsedMarkdown("Hello **world**.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.wordSpans(for: leaves[0]) == nil,
      "Formatting-only change should fall back to block-level")

    let deletions = context.precedingDeletions(before: leaves[0])
    if !deletions.isEmpty {
      #expect(deletions[0].wordSpans == nil)
    }
  }

  @Test func wordChangedWithFormattingAddedCarriesWordSpans() {
    // Word changed AND formatting added → word spans present.
    let old = ParsedMarkdown("The quick brown fox.\n")
    let new = ParsedMarkdown("The *slow* brown fox.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let spans = context.wordSpans(for: leaves[0])
    #expect(spans != nil, "Word change with formatting change should carry word spans")
    if let spans {
      let hasDeleted = spans.contains(where: \.isDeleted)
      let hasInserted = spans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }

    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions[0].wordSpans != nil)
  }

  @Test func wordChangedWithFormattingRemovedCarriesWordSpans() {
    // Word changed AND formatting removed → word spans present.
    let old = ParsedMarkdown("The **quick** brown fox.\n")
    let new = ParsedMarkdown("The slow brown fox.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let spans = context.wordSpans(for: leaves[0])
    #expect(spans != nil, "Word change with formatting removed should carry word spans")
    if let spans {
      let hasDeleted = spans.contains(where: \.isDeleted)
      let hasInserted = spans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }
  }

  @Test func wordChangedWithFormattingShiftedCarriesWordSpans() {
    // Words changed AND formatting shifted to different words.
    let old = ParsedMarkdown("The **quick brown** fox.\n")
    let new = ParsedMarkdown("The *slow* brown dog.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let spans = context.wordSpans(for: leaves[0])
    #expect(spans != nil, "Word change with shifted formatting should carry word spans")
    if let spans {
      let hasDeleted = spans.contains(where: \.isDeleted)
      let hasInserted = spans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }
  }

  @Test func inlineCodeAddedWithWordChangeCarriesWordSpans() {
    let old = ParsedMarkdown("Call foo now.\n")
    let new = ParsedMarkdown("Call `bar` now.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let spans = context.wordSpans(for: leaves[0])
    #expect(spans != nil, "Word change with inline code added should carry word spans")
    if let spans {
      let hasDeleted = spans.contains(where: \.isDeleted)
      let hasInserted = spans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }
  }

  @Test func linkAddedWithoutWordChangeHasNilWordSpans() {
    // Same words, link added → formatting-only change.
    let old = ParsedMarkdown("Read the guide.\n")
    let new = ParsedMarkdown("Read the [guide](https://example.com).\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.wordSpans(for: leaves[0]) == nil,
      "Link-only change with same words should fall back to block-level")
  }

  @Test func linkAddedWithWordChangeCarriesWordSpans() {
    let old = ParsedMarkdown("Read the old guide.\n")
    let new = ParsedMarkdown("Read the [new guide](https://example.com).\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let spans = context.wordSpans(for: leaves[0])
    #expect(spans != nil, "Word change with link added should carry word spans")
    if let spans {
      let hasDeleted = spans.contains(where: \.isDeleted)
      let hasInserted = spans.contains(where: \.isInserted)
      #expect(hasDeleted)
      #expect(hasInserted)
    }
  }

  @Test func unpairedInsertionHasNilWordSpans() {
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\nAdded.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.wordSpans(for: leaves[1]) == nil)
  }

  @Test func unpairedDeletionHasNilWordSpans() {
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let deletions = context.trailingDeletions()
    #expect(deletions[0].wordSpans == nil)
  }

  // MARK: - All content deleted

  @Test func allDeletedSurfacesAsTrailingDeletions() {
    let old = ParsedMarkdown("# Title\n\nBody.\n")
    let new = ParsedMarkdown("")
    let context = DiffContext(old: old, new: new)

    // New AST is empty — no leaves to query precedingDeletions on.
    let leaves = leafBlocks(of: new)
    #expect(leaves.isEmpty)

    // All deletions must surface as trailing deletions.
    let trailing = context.trailingDeletions()
    #expect(trailing.count == 2)
  }
}

// MARK: - Test helpers

/// Collect leaf blocks from a ParsedMarkdown's AST in document order.
private func leafBlocks(of parsed: ParsedMarkdown) -> [Markup] {
  var collector = LeafBlockCollector()
  collector.visit(parsed.document)
  return collector.leaves
}

private struct LeafBlockCollector: MarkupWalker {
  var leaves: [Markup] = []

  mutating func visitParagraph(_ paragraph: Paragraph) {
    leaves.append(paragraph)
  }

  mutating func visitHeading(_ heading: Heading) {
    leaves.append(heading)
  }

  mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
    leaves.append(codeBlock)
  }

  mutating func visitListItem(_ listItem: ListItem) {
    leaves.append(listItem)
    // Don't descend — list item is the leaf for diffing purposes.
  }

  mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
    // Descend to find paragraphs within the blockquote.
    descendInto(blockQuote)
  }

  mutating func visitTable(_ table: Table) {
    // Descend to find rows.
    descendInto(table)
  }

  mutating func visitTableRow(_ row: Table.Row) {
    leaves.append(row)
  }

  mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
    leaves.append(thematicBreak)
  }

  mutating func visitHTMLBlock(_ html: HTMLBlock) {
    leaves.append(html)
  }
}
