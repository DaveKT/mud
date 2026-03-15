import Testing
@testable import MudCore

@Suite("BlockMatcher")
struct BlockMatcherTests {
  // MARK: - Identical content

  @Test func identicalDocumentsProduceAllUnchanged() {
    let md = "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n"
    let matches = BlockMatcher.match(
      old: ParsedMarkdown(md), new: ParsedMarkdown(md)
    )
    #expect(matches.allSatisfy { $0.isUnchanged })
    #expect(matches.count == 3) // heading + 2 paragraphs
  }

  @Test func bothEmptyProduceNoMatches() {
    let matches = BlockMatcher.match(
      old: ParsedMarkdown(""), new: ParsedMarkdown("")
    )
    #expect(matches.isEmpty)
  }

  // MARK: - Insertions

  @Test func appendedParagraph() {
    let old = ParsedMarkdown("First paragraph.\n")
    let new = ParsedMarkdown("First paragraph.\n\nSecond paragraph.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isInserted)
  }

  @Test func prependedParagraph() {
    let old = ParsedMarkdown("Original.\n")
    let new = ParsedMarkdown("New first.\n\nOriginal.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches[0].isInserted)
    #expect(matches[1].isUnchanged)
  }

  @Test func insertedBetweenExisting() {
    let old = ParsedMarkdown("Alpha.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 3)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isInserted)
    #expect(matches[2].isUnchanged)
  }

  @Test func allNewContentInEmptyDocument() {
    let old = ParsedMarkdown("")
    let new = ParsedMarkdown("# Hello\n\nWorld.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches.allSatisfy { $0.isInserted })
  }

  // MARK: - Deletions

  @Test func removedParagraph() {
    let old = ParsedMarkdown("First.\n\nSecond.\n")
    let new = ParsedMarkdown("First.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isDeleted)
  }

  @Test func allContentRemoved() {
    let old = ParsedMarkdown("# Hello\n\nWorld.\n")
    let new = ParsedMarkdown("")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches.allSatisfy { $0.isDeleted })
  }

  @Test func removedFromMiddle() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha.\n\nGamma.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 3)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isDeleted)
    #expect(matches[2].isUnchanged)
  }

  // MARK: - Modifications

  @Test func modifiedParagraph() {
    let old = ParsedMarkdown("Hello world.\n")
    let new = ParsedMarkdown("Hello there.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 1)
    #expect(matches[0].isModified)
  }

  @Test func modifiedHeading() {
    let old = ParsedMarkdown("# Draft title\n\nBody.\n")
    let new = ParsedMarkdown("# Final title\n\nBody.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches[0].isModified)
    #expect(matches[1].isUnchanged)
  }

  @Test func modifiedAmongUnchanged() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha.\n\nBeta revised.\n\nGamma.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 3)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isModified)
    #expect(matches[2].isUnchanged)
  }

  // MARK: - Mixed changes

  @Test func samePositionReplacementIsModified() {
    let old = ParsedMarkdown("Keep.\n\nRemove.\n")
    let new = ParsedMarkdown("Keep.\n\nAdded.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Positional pairing: old-index 1 removed, new-index 1 inserted
    // → merged into a single .modified match.
    #expect(matches.count == 2)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isModified)
  }

  @Test func adjacentModifications() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha changed.\n\nBeta changed.\n\nGamma.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Two consecutive positional pairings, each producing .modified.
    #expect(matches.count == 3)
    #expect(matches[0].isModified)
    #expect(matches[1].isModified)
    #expect(matches[2].isUnchanged)
  }

  @Test func multipleChangesAcrossDocument() {
    let old = ParsedMarkdown(
      "# Title\n\nFirst paragraph.\n\nSecond paragraph.\n\nThird paragraph.\n"
    )
    let new = ParsedMarkdown(
      "# Updated title\n\nFirst paragraph.\n\nReplaced paragraph.\n\n"
      + "Third paragraph.\n\nNew final paragraph.\n"
    )
    let matches = BlockMatcher.match(old: old, new: new)

    // Title: modified, First: unchanged, Second→Replaced: modified,
    // Third: unchanged, New final: inserted
    let unchanged = matches.filter { $0.isUnchanged }
    let modified = matches.filter { $0.isModified }
    let inserted = matches.filter { $0.isInserted }

    #expect(unchanged.count == 2) // First, Third
    #expect(modified.count == 2)  // Title, Second→Replaced
    #expect(inserted.count == 1)  // New final
  }

  // MARK: - Block types

  @Test func codeBlockChanges() {
    let old = ParsedMarkdown("Intro.\n\n```swift\nlet x = 1\n```\n")
    let new = ParsedMarkdown("Intro.\n\n```swift\nlet x = 2\n```\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 2)
    #expect(matches[0].isUnchanged) // Intro
    #expect(matches[1].isModified)  // Code block
  }

  @Test func listItemGranularity() {
    let old = ParsedMarkdown("- Alpha\n- Beta\n- Gamma\n")
    let new = ParsedMarkdown("- Alpha\n- Beta revised\n- Gamma\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Individual list items are leaf blocks per the plan.
    // Alpha and Gamma unchanged, Beta modified.
    let unchanged = matches.filter { $0.isUnchanged }
    let modified = matches.filter { $0.isModified }

    #expect(unchanged.count == 2)
    #expect(modified.count == 1)
  }

  @Test func addedListItem() {
    let old = ParsedMarkdown("- First\n- Second\n")
    let new = ParsedMarkdown("- First\n- Second\n- Third\n")
    let matches = BlockMatcher.match(old: old, new: new)

    let unchanged = matches.filter { $0.isUnchanged }
    let inserted = matches.filter { $0.isInserted }

    #expect(unchanged.count == 2)
    #expect(inserted.count == 1)
  }

  @Test func blockquoteParagraphGranularity() {
    let old = ParsedMarkdown("> First line.\n>\n> Second line.\n")
    let new = ParsedMarkdown("> First line.\n>\n> Changed line.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Blockquote paragraphs are leaf blocks.
    let unchanged = matches.filter { $0.isUnchanged }
    #expect(unchanged.count >= 1) // At least "First line" unchanged
    #expect(matches.contains { $0.isModified || $0.isInserted })
  }

  @Test func tableRowGranularity() {
    let old = ParsedMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n")
    let new = ParsedMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | changed |\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Table rows are leaf blocks. Header row and first data row unchanged,
    // second data row modified.
    let unchanged = matches.filter { $0.isUnchanged }
    let modified = matches.filter { $0.isModified }

    #expect(unchanged.count >= 1) // At least the unchanged data row
    #expect(modified.count == 1)  // The changed data row
  }

  @Test func nestedListItems() {
    let old = ParsedMarkdown("- Outer\n  - Inner A\n  - Inner B\n")
    let new = ParsedMarkdown("- Outer\n  - Inner A\n  - Inner B changed\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Inner list items should be leaf blocks. The outer item and Inner A
    // are unchanged; Inner B is modified.
    let unchanged = matches.filter { $0.isUnchanged }
    let modified = matches.filter { $0.isModified }

    #expect(unchanged.count >= 2) // Outer + Inner A
    #expect(modified.count == 1)  // Inner B
  }

  // MARK: - Trailing deletions

  @Test func multipleTrailingDeletions() {
    let old = ParsedMarkdown("Keep.\n\nRemoved.\n\nAlso removed.\n")
    let new = ParsedMarkdown("Keep.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 3)
    #expect(matches[0].isUnchanged)
    #expect(matches[1].isDeleted)
    #expect(matches[2].isDeleted)
  }

  // MARK: - Reordering

  @Test func swappedParagraphs() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n")
    let new = ParsedMarkdown("Beta.\n\nAlpha.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // CollectionDifference treats reorders as remove + insert.
    // Both blocks still appear in the output.
    #expect(matches.count >= 2)
    // No blocks should be lost — total old + new blocks accounted for.
    let deleted = matches.filter { $0.isDeleted }.count
    let inserted = matches.filter { $0.isInserted }.count
    let unchanged = matches.filter { $0.isUnchanged }.count
    #expect(deleted + inserted + unchanged >= 2)
  }

  // MARK: - Whitespace and formatting

  @Test func contentAndFormattingChangeIsModification() {
    let old = ParsedMarkdown("Some plain text.\n")
    let new = ParsedMarkdown("Some **bold** text.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    #expect(matches.count == 1)
    #expect(matches[0].isModified)
  }

  @Test func formattingOnlyChangeIsModification() {
    let old = ParsedMarkdown("Some text.\n")
    let new = ParsedMarkdown("Some **text**.\n")
    let matches = BlockMatcher.match(old: old, new: new)

    // Source text fingerprints differ ("Some text." vs "Some **text**."),
    // even though the plain text is identical. Formatting changes are
    // deliberate authorial changes that affect rendered output.
    #expect(matches.count == 1)
    #expect(matches[0].isModified)
  }
}

// MARK: - BlockMatch test helpers

extension BlockMatch {
  var isUnchanged: Bool {
    if case .unchanged = self { return true }
    return false
  }

  var isInserted: Bool {
    if case .inserted = self { return true }
    return false
  }

  var isDeleted: Bool {
    if case .deleted = self { return true }
    return false
  }

  var isModified: Bool {
    if case .modified = self { return true }
    return false
  }
}
