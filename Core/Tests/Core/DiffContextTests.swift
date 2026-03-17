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
