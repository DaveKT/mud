import Testing
@testable import MudCore

@Suite("ChangeList")
struct ChangeListTests {
  // MARK: - Basic extraction

  @Test func identicalDocumentsProduceNoChanges() {
    let md = "# Title\n\nParagraph.\n"
    let changes = MudCore.computeChanges(
      old: ParsedMarkdown(md), new: ParsedMarkdown(md)
    )
    #expect(changes.isEmpty)
  }

  @Test func unchangedBlocksAreExcluded() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha.\n\nBeta changed.\n\nGamma.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // 3 blocks, only 1 changed — unchanged blocks produce no entries.
    // The replacement produces a deletion + insertion.
    #expect(changes.count == 2)
    #expect(changes[0].type == .deletion)
    #expect(changes[1].type == .insertion)
  }

  @Test func insertionProducesInsertionChange() {
    let old = ParsedMarkdown("Existing.\n")
    let new = ParsedMarkdown("Existing.\n\nAdded paragraph.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].type == .insertion)
  }

  @Test func deletionProducesDeletionChange() {
    let old = ParsedMarkdown("Keep.\n\nRemove.\n")
    let new = ParsedMarkdown("Keep.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].type == .deletion)
  }

  @Test func replacementProducesDeletionAndInsertion() {
    let old = ParsedMarkdown("Original text.\n")
    let new = ParsedMarkdown("Revised text.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 2)
    #expect(changes[0].type == .deletion)
    #expect(changes[1].type == .insertion)
  }

  // MARK: - IDs

  @Test func changeIDsAreUnique() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha changed.\n\nBeta changed.\n\nGamma changed.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    let ids = changes.map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test func changeIDsAreNonEmpty() {
    let old = ParsedMarkdown("Before.\n")
    let new = ParsedMarkdown("After.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.allSatisfy { !$0.id.isEmpty })
  }

  // MARK: - Summaries

  @Test func summaryContainsChangedContent() {
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\nA newly added paragraph.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].summary.contains("newly added"))
  }

  @Test func summaryTruncatesLongContent() {
    let longText = String(repeating: "word ", count: 30) // ~150 chars
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\n\(longText)\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].summary.count <= 80) // ~60 chars with some tolerance
  }

  @Test func deletionSummaryUsesOldContent() {
    let old = ParsedMarkdown("Keep.\n\nDeleted paragraph here.\n")
    let new = ParsedMarkdown("Keep.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].summary.contains("Deleted paragraph"))
  }

  @Test func replacementSummariesCoverBothVersions() {
    let old = ParsedMarkdown("Old version of this text.\n")
    let new = ParsedMarkdown("New version of this text.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 2)
    #expect(changes[0].summary.contains("Old version"))
    #expect(changes[1].summary.contains("New version"))
  }

  // MARK: - Source lines

  @Test func sourceLinePointsToChangedBlock() {
    let old = ParsedMarkdown("First.\n\nSecond.\n\nThird.\n")
    let new = ParsedMarkdown("First.\n\nSecond revised.\n\nThird.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // Replacement produces deletion + insertion, both at line 3.
    #expect(changes.count == 2)
    #expect(changes[0].sourceLine == 3)
    #expect(changes[1].sourceLine == 3)
  }

  @Test func insertionSourceLinePointsToNewBlock() {
    let old = ParsedMarkdown("First.\n")
    let new = ParsedMarkdown("First.\n\nInserted.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    // "Inserted." starts on line 3
    #expect(changes[0].sourceLine == 3)
  }

  @Test func deletionSourceLinePointsToNextSurvivingBlock() {
    let old = ParsedMarkdown("First.\n\nDeleted.\n\nThird.\n")
    let new = ParsedMarkdown("First.\n\nThird.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    // "Third." is at line 3 in the new document. The deletion would be
    // revealed before it, so sourceLine targets that position.
    #expect(changes[0].sourceLine == 3)
  }

  @Test func trailingDeletionSourceLinePointsToLastSurvivingBlock() {
    let old = ParsedMarkdown("First.\n\nDeleted.\n")
    let new = ParsedMarkdown("First.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    // No following block exists. Fall back to the last surviving block.
    // "First." is at line 1 in the new document.
    #expect(changes[0].sourceLine == 1)
  }

  // MARK: - Document order

  @Test func changesAreInDocumentOrder() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n\nDelta.\n")
    let new = ParsedMarkdown(
      "Alpha changed.\n\nBeta.\n\nGamma changed.\n\nDelta.\n\nEpsilon.\n"
    )
    let changes = MudCore.computeChanges(old: old, new: new)

    // Alpha: del+ins, Gamma: del+ins, Epsilon: inserted — in that order.
    #expect(changes.count == 5)
    #expect(changes[0].type == .deletion)
    #expect(changes[1].type == .insertion)
    #expect(changes[2].type == .deletion)
    #expect(changes[3].type == .insertion)
    #expect(changes[4].type == .insertion)

    // Source lines should be monotonically non-decreasing.
    for i in 1..<changes.count {
      #expect(changes[i].sourceLine >= changes[i - 1].sourceLine)
    }
  }

  @Test func deletionsAppearInDocumentOrder() {
    let old = ParsedMarkdown("First.\n\nSecond.\n\nThird.\n")
    let new = ParsedMarkdown("")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 3)
    #expect(changes.allSatisfy { $0.type == .deletion })
  }

  // MARK: - Mixed changes

  @Test func mixedChangeTypesAllRepresented() {
    let old = ParsedMarkdown("Keep.\n\nModify this.\n\nRemove this.\n")
    let new = ParsedMarkdown("Keep.\n\nModified now.\n\nBrand new.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    let types = Set(changes.map(\.type))
    // Each replacement produces a deletion + insertion pair.
    #expect(types.contains(.deletion))
    #expect(types.contains(.insertion))
    #expect(changes.count >= 2)
  }

  // MARK: - Group fields

  @Test func changesCarryGroupID() {
    let old = ParsedMarkdown("Before.\n")
    let new = ParsedMarkdown("After.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.allSatisfy { !$0.groupID.isEmpty })
  }

  @Test func changesCarryGroupIndex() {
    let old = ParsedMarkdown("Before.\n")
    let new = ParsedMarkdown("After.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.allSatisfy { $0.groupIndex >= 1 })
  }

  @Test func consecutiveChangesShareGroupID() {
    let old = ParsedMarkdown("Alpha.\n\nBeta.\n")
    let new = ParsedMarkdown("Alpha changed.\n\nBeta changed.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // All four changes (2 del + 2 ins) are consecutive — one group.
    let groupIDs = Set(changes.map(\.groupID))
    #expect(groupIDs.count == 1)
    #expect(changes[0].groupIndex == 1)
  }

  @Test func nonConsecutiveChangesGetDifferentGroupIDs() {
    let old = ParsedMarkdown("Alpha.\n\nKeep.\n\nGamma.\n")
    let new = ParsedMarkdown("Alpha changed.\n\nKeep.\n\nGamma changed.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // Two separate groups, split by "Keep."
    let groupIDs = Set(changes.map(\.groupID))
    #expect(groupIDs.count == 2)

    // Group indices should be 1 and 2.
    let indices = Set(changes.map(\.groupIndex))
    #expect(indices == [1, 2])
  }

  // MARK: - Empty documents

  @Test func bothEmptyProduceNoChanges() {
    let changes = MudCore.computeChanges(
      old: ParsedMarkdown(""), new: ParsedMarkdown("")
    )
    #expect(changes.isEmpty)
  }

  @Test func emptyToContentProducesInsertions() {
    let old = ParsedMarkdown("")
    let new = ParsedMarkdown("# Title\n\nBody.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 2)
    #expect(changes.allSatisfy { $0.type == .insertion })
  }

  @Test func contentToEmptyProducesDeletions() {
    let old = ParsedMarkdown("# Title\n\nBody.\n")
    let new = ParsedMarkdown("")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 2)
    #expect(changes.allSatisfy { $0.type == .deletion })
  }
}
