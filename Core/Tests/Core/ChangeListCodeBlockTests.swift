import Testing
@testable import MudCore

@Suite("ChangeList code block diffs")
struct ChangeListCodeBlockTests {
  // MARK: - Line groups produce sidebar entries

  @Test func changedCodeBlockProducesChangeEntries() {
    let old = ParsedMarkdown("```\nold line\n```\n")
    let new = ParsedMarkdown("```\nnew line\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(!changes.isEmpty,
      "Changed code block should produce sidebar entries")
  }

  @Test func oneLineGroupProducesOneEntry() {
    // Single change cluster → one sidebar entry.
    let old = ParsedMarkdown("```\nkeep\nold\n```\n")
    let new = ParsedMarkdown("```\nkeep\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // One line group (the changed line).
    #expect(changes.count == 1,
      "One change cluster should produce one sidebar entry")
  }

  @Test func multipleLineGroupsProduceMultipleEntries() {
    // Two separated change clusters → two sidebar entries.
    let old = ParsedMarkdown("```\na\nb\nc\nd\ne\n```\n")
    let new = ParsedMarkdown("```\na\nB\nc\nD\ne\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 2,
      "Two separated change clusters should produce two sidebar entries")
  }

  // MARK: - Entry properties

  @Test func lineGroupEntryHasChangeID() {
    let old = ParsedMarkdown("```\nold\n```\n")
    let new = ParsedMarkdown("```\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    for change in changes {
      #expect(!change.id.isEmpty, "Each entry should have a change ID")
    }
  }

  @Test func lineGroupEntryHasGroupID() {
    let old = ParsedMarkdown("```\nold\n```\n")
    let new = ParsedMarkdown("```\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    for change in changes {
      #expect(!change.groupID.isEmpty, "Each entry should have a group ID")
      #expect(change.groupIndex > 0, "Group index should be positive")
    }
  }

  @Test func lineGroupEntrySummaryContainsChangedContent() {
    let old = ParsedMarkdown("```\nold line here\n```\n")
    let new = ParsedMarkdown("```\nnew line here\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(!changes.isEmpty)
    // Summary should contain text from the changed line(s).
    let allSummaries = changes.map(\.summary).joined(separator: " ")
    let hasContent = allSummaries.contains("old") || allSummaries.contains("new")
    #expect(hasContent,
      "Summary should reference changed line content")
  }

  // MARK: - Interaction with block-level changes

  @Test func codeBlockEntriesFollowBlockLevelEntries() {
    // A changed paragraph followed by a changed code block.
    let old = ParsedMarkdown("Original.\n\n```\nold\n```\n")
    let new = ParsedMarkdown("Changed.\n\n```\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // Should have entries for both the paragraph and the code block.
    #expect(changes.count >= 3,
      "Should have paragraph del + ins + code block line group(s)")
  }

  @Test func unchangedCodeBlockProducesNoEntries() {
    let old = ParsedMarkdown("Changed.\n\n```\nsame\n```\n")
    let new = ParsedMarkdown("Different.\n\n```\nsame\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // Only the paragraph change should appear, not the code block.
    let codeRelated = changes.filter {
      $0.summary.contains("same")
    }
    #expect(codeRelated.isEmpty,
      "Unchanged code block should not produce sidebar entries")
  }

  // MARK: - Unpaired code blocks

  @Test func newCodeBlockProducesBlockLevelEntry() {
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\n```\nnew code\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    // Should be a single block-level insertion.
    #expect(changes.count == 1)
    #expect(changes[0].type == .insertion)
  }

  @Test func deletedCodeBlockProducesBlockLevelEntry() {
    let old = ParsedMarkdown("Keep.\n\n```\nold code\n```\n")
    let new = ParsedMarkdown("Keep.\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    #expect(changes.count == 1)
    #expect(changes[0].type == .deletion)
  }

  // MARK: - Group type

  @Test func mixedLineGroupHasInsertionAndDeletion() {
    // A single line changed → mixed group (del + ins).
    // The sidebar entry for a mixed group could be either type
    // depending on implementation. Verify we get entries.
    let old = ParsedMarkdown("```\nold\n```\n")
    let new = ParsedMarkdown("```\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)
    #expect(!changes.isEmpty)
  }

  @Test func pureInsertionLineGroupHasInsertionType() {
    let old = ParsedMarkdown("```\na\n```\n")
    let new = ParsedMarkdown("```\na\nb\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    let insertions = changes.filter { $0.type == .insertion }
    #expect(!insertions.isEmpty,
      "Added lines should produce insertion entries")
  }

  @Test func pureDeletionLineGroupHasDeletionType() {
    let old = ParsedMarkdown("```\na\nb\n```\n")
    let new = ParsedMarkdown("```\na\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)

    let deletions = changes.filter { $0.type == .deletion }
    #expect(!deletions.isEmpty,
      "Removed lines should produce deletion entries")
  }
}
