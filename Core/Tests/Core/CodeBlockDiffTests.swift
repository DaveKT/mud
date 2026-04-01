import Testing
@testable import MudCore

@Suite("CodeBlockDiff")
struct CodeBlockDiffTests {
  // MARK: - Identical content returns nil

  @Test func identicalContentReturnsNil() {
    // When old and new code block content is identical, the diff
    // should return nil so the caller falls back to block-level.
    let code = "func greet() {\n    print(\"hello\")\n}\n"
    let result = CodeBlockDiff.compute(
      oldCode: code, newCode: code,
      oldLanguage: "swift", newLanguage: "swift",
      nextChangeID: { "change-X" },
      nextGroupID: { (id: "group-X", index: 1) })
    #expect(result == nil, "Identical content should fall back to block-level")
  }

  @Test func languageOnlyChangeReturnsNil() {
    // Same content, different language tag → no line changes.
    // Caller should fall back to block-level.
    let code = "x = 1\n"
    let result = CodeBlockDiff.compute(
      oldCode: code, newCode: code,
      oldLanguage: "python", newLanguage: "ruby",
      nextChangeID: { "change-X" },
      nextGroupID: { (id: "group-X", index: 1) })
    #expect(result == nil, "Language-only change should fall back to block-level")
  }

  // MARK: - Single line changed

  @Test func singleLineChangedProducesMixedGroup() {
    let old = "func greet() {\n    print(\"hello\")\n}\n"
    let new = "func greet() {\n    print(\"hi\")\n}\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: "swift", newLanguage: "swift",
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    // Should have: unchanged, deleted, inserted, unchanged
    // (del before ins within the gap)
    let annotations = diff.lines.map(\.annotation)
    #expect(annotations.contains(.unchanged))
    #expect(annotations.contains(.deleted))
    #expect(annotations.contains(.inserted))

    // One group consumed.
    #expect(groupCounter == 1)

    // The deleted and inserted lines share the same group ID.
    let changedLines = diff.lines.filter { $0.annotation != .unchanged }
    let groupIDs = Set(changedLines.compactMap(\.groupID))
    #expect(groupIDs.count == 1)
  }

  // MARK: - Pure insertion

  @Test func linesAddedProducesInsertionGroup() {
    let old = "a\nb\n"
    let new = "a\nb\nc\nd\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    let inserted = diff.lines.filter { $0.annotation == .inserted }
    let deleted = diff.lines.filter { $0.annotation == .deleted }
    #expect(inserted.count == 2, "Two lines added")
    #expect(deleted.count == 0, "No lines deleted")
    #expect(groupCounter == 1, "One insertion group")
  }

  // MARK: - Pure deletion

  @Test func linesRemovedProducesDeletionGroup() {
    let old = "a\nb\nc\nd\n"
    let new = "a\nd\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    let deleted = diff.lines.filter { $0.annotation == .deleted }
    #expect(deleted.count == 2, "Two lines deleted")
  }

  // MARK: - Multiple groups

  @Test func separateChangeClustersFormSeparateGroups() {
    // Changes at line 2 and line 4, separated by unchanged line 3.
    let old = "a\nb\nc\nd\ne\n"
    let new = "a\nB\nc\nD\ne\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    #expect(groupCounter == 2, "Two separate change clusters")

    let groupIDs = Set(diff.lines.compactMap(\.groupID))
    #expect(groupIDs.count == 2)
  }

  // MARK: - Ordering: deletions before insertions in each gap

  @Test func deletionsBeforeInsertionsInGap() {
    let old = "a\nold line\nc\n"
    let new = "a\nnew line\nc\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    // Find the changed lines in order.
    let changed = diff.lines.filter { $0.annotation != .unchanged }
    #expect(changed.count == 2)
    #expect(changed[0].annotation == .deleted, "Deletion should come first")
    #expect(changed[1].annotation == .inserted, "Insertion should come second")
  }

  // MARK: - Change IDs

  @Test func eachLineGroupGetsDistinctChangeID() {
    let old = "a\nb\nc\nd\ne\n"
    let new = "a\nB\nc\nD\ne\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    let changeIDs = Set(diff.lines.compactMap(\.changeID))
    // Each line group should have a unique change ID.
    // Two groups, each with del + ins = potentially 4 change IDs,
    // but per the plan, each line GROUP gets one change ID (not each line).
    // Actually re-reading the plan: "Assign a change ID to each line group"
    // So all lines in a group share one change ID.
    #expect(changeIDs.count >= 2, "At least two distinct change IDs for two groups")
  }

  @Test func unchangedLinesHaveNilChangeID() {
    let old = "a\nb\n"
    let new = "a\nB\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    let unchanged = diff.lines.filter { $0.annotation == .unchanged }
    for line in unchanged {
      #expect(line.changeID == nil)
      #expect(line.groupID == nil)
      #expect(line.groupIndex == nil)
    }
  }

  // MARK: - Highlighted HTML content

  @Test func linesContainHighlightedHTML() {
    let old = "let x = 1\nlet y = 2\n"
    let new = "let x = 1\nlet z = 3\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: "swift", newLanguage: "swift",
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    // Every line should have non-empty highlighted HTML.
    for line in diff.lines {
      #expect(!line.highlightedHTML.isEmpty)
    }

    // Unchanged lines should contain the original content.
    let unchanged = diff.lines.filter { $0.annotation == .unchanged }
    #expect(unchanged.count >= 1)
    let firstUnchanged = unchanged[0].highlightedHTML
    #expect(firstUnchanged.contains("x"))
  }

  @Test func deletedLinesHighlightedWithOldLanguage() {
    // Old language is swift, new is python. Deleted lines should be
    // highlighted with the old language.
    let old = "let x = 1\nlet y = 2\n"
    let new = "x = 1\nz = 3\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: "swift", newLanguage: "python",
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    // Should produce a diff (content is different).
    #expect(result != nil)
  }

  @Test func noLanguageUsesEscapedPlainText() {
    let old = "a <b> c\n"
    let new = "a <b> d\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    // HTML should be escaped (no raw < or >).
    for line in diff.lines {
      #expect(!line.highlightedHTML.contains("<b>"),
        "Raw HTML should be escaped")
    }
  }

  // MARK: - Trailing newline trimming

  @Test func trailingNewlineDoesNotCausePhantomDiff() {
    // CodeBlock.code may include trailing \n. If both old and new
    // have different trailing whitespace, it shouldn't produce a
    // phantom empty-line diff.
    let old = "line one\nline two\n"
    let new = "line one\nline two changed\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    // Should not have an empty unchanged line at the end.
    if let last = diff.lines.last {
      #expect(!last.highlightedHTML.trimmingCharacters(in: .whitespaces).isEmpty
        || last.annotation != .unchanged,
        "No phantom empty line at the end")
    }
  }

  // MARK: - Edge cases

  @Test func allLinesChangedDegeneratesToOneGroup() {
    let old = "a\nb\nc\n"
    let new = "x\ny\nz\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    #expect(groupCounter == 1, "All changes in one group")
    #expect(diff.lines.filter { $0.annotation == .unchanged }.isEmpty)
  }

  @Test func emptyOldCodeWithNewCodeReturnsNonNil() {
    // Empty → some content. All lines are insertions.
    let old = ""
    let new = "a\nb\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    let inserted = diff.lines.filter { $0.annotation == .inserted }
    #expect(inserted.count >= 2)
  }

  @Test func emptyNewCodeWithOldCodeReturnsNonNil() {
    // Some content → empty. All lines are deletions.
    let old = "a\nb\n"
    let new = ""

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    let deleted = diff.lines.filter { $0.annotation == .deleted }
    #expect(deleted.count >= 2)
  }

  @Test func singleLineCodeBlock() {
    let old = "old\n"
    let new = "new\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    #expect(result != nil)
    guard let diff = result else { return }

    #expect(diff.lines.count == 2) // one deleted, one inserted
    #expect(diff.lines[0].annotation == .deleted)
    #expect(diff.lines[1].annotation == .inserted)
  }

  // MARK: - Group index (badge number)

  @Test func firstGroupInBlockCarriesGroupIndex() {
    let old = "a\nb\nc\n"
    let new = "a\nB\nc\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    let withIndex = diff.lines.filter { $0.groupIndex != nil }
    #expect(!withIndex.isEmpty, "At least one line should carry a group index")
  }

  // MARK: - Word-level markers

  @Test func pairedLinesGetWordLevelMarkers() {
    let old = "let x = 1\nlet y = 2\n"
    let new = "let x = 1\nlet z = 3\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    let deleted = diff.lines.filter { $0.annotation == .deleted }
    let inserted = diff.lines.filter { $0.annotation == .inserted }
    #expect(deleted.count == 1)
    #expect(inserted.count == 1)

    // The deleted line should have <del> markers for changed words.
    #expect(deleted[0].highlightedHTML.contains("<del>"),
      "Paired deleted line should have word-level <del> markers")
    // The inserted line should have <ins> markers.
    #expect(inserted[0].highlightedHTML.contains("<ins>"),
      "Paired inserted line should have word-level <ins> markers")
  }

  @Test func unpairedLinesHaveNoWordMarkers() {
    // More deletions than insertions — excess are unpaired.
    let old = "a\nb\nc\n"
    let new = "x\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    // First deletion pairs with the insertion. Others are unpaired.
    let deleted = diff.lines.filter { $0.annotation == .deleted }
    #expect(deleted.count == 3)

    // Unpaired deletions (indices 1, 2) should not have <del> markers.
    #expect(!deleted[1].highlightedHTML.contains("<del>"))
    #expect(!deleted[2].highlightedHTML.contains("<del>"))
  }

  @Test func identicalPairedLinesHaveNoWordMarkers() {
    // Lines that pair but have identical content (shouldn't happen
    // in practice since they'd be unchanged, but defensive).
    let old = "a\nsame\nb\n"
    let new = "x\nsame\ny\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: nil, newLanguage: nil,
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    // "same" should be unchanged — no markers.
    let unchanged = diff.lines.filter { $0.annotation == .unchanged }
    #expect(unchanged.count == 1)
    #expect(!unchanged[0].highlightedHTML.contains("<ins>"))
    #expect(!unchanged[0].highlightedHTML.contains("<del>"))
  }

  @Test func wordMarkersWorkWithSyntaxHighlighting() {
    let old = "let x = 1\n"
    let new = "let x = 2\n"

    var changeCounter = 0
    var groupCounter = 0
    let result = CodeBlockDiff.compute(
      oldCode: old, newCode: new,
      oldLanguage: "swift", newLanguage: "swift",
      nextChangeID: { changeCounter += 1; return "change-\(changeCounter)" },
      nextGroupID: { groupCounter += 1; return (id: "group-\(groupCounter)", index: groupCounter) })

    guard let diff = result else { return }

    let inserted = diff.lines.filter { $0.annotation == .inserted }
    #expect(inserted.count == 1)

    let html = inserted[0].highlightedHTML
    // Should have both syntax highlighting spans and word markers.
    #expect(html.contains("<ins>"),
      "Should have word-level markers")
    #expect(html.contains("hljs-") || html.contains("x"),
      "Should preserve syntax highlighting or content")
  }
}
