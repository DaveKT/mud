import Markdown
import Testing
@testable import MudCore

@Suite("DiffContext code block diffs")
struct DiffContextCodeBlockTests {
  // MARK: - Paired code block produces line-level diff

  @Test func pairedCodeBlockHasCodeBlockDiff() {
    let old = ParsedMarkdown("```\nold line\n```\n")
    let new = ParsedMarkdown("```\nnew line\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 1)

    let diff = context.codeBlockDiff(for: leaves[0])
    #expect(diff != nil, "Paired code block should have a line-level diff")
  }

  @Test func pairedCodeBlockAnnotationReturnsNil() {
    // A code block with line-level diff should be neutral at block
    // level — annotation(for:) returns nil.
    let old = ParsedMarkdown("```\nold line\n```\n")
    let new = ParsedMarkdown("```\nnew line\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.annotation(for: leaves[0]) == nil,
      "Code block with line diff should have nil block-level annotation")
  }

  @Test func pairedCodeBlockChangeIDReturnsNil() {
    // Block-level change ID should be nil for a code block with
    // line-level diff — the line groups own the change IDs.
    let old = ParsedMarkdown("```\nold line\n```\n")
    let new = ParsedMarkdown("```\nnew line\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(context.changeID(for: leaves[0]) == nil,
      "Code block with line diff should have nil block-level change ID")
  }

  // MARK: - Paired code block suppresses block-level deletion

  @Test func pairedCodeBlockDeletionNotInPrecedingDeletions() {
    // The old code block's deletion should NOT appear in
    // precedingDeletions — it's absorbed into the line-level diff.
    let old = ParsedMarkdown("```\nold\n```\n")
    let new = ParsedMarkdown("```\nnew\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.isEmpty,
      "Paired code block deletion should not appear in precedingDeletions")
    #expect(context.trailingDeletions().isEmpty,
      "Paired code block deletion should not appear in trailingDeletions")
  }

  // MARK: - Non-code deletions still flow through

  @Test func nonCodeDeletionBeforeCodeBlockStillAppears() {
    // A deleted paragraph before a changed code block should still
    // appear as a preceding deletion.
    let old = ParsedMarkdown("Removed.\n\n```\nold\n```\n")
    let new = ParsedMarkdown("```\nnew\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.count == 1, "Deleted paragraph should appear")
    #expect(deletions[0].tag == "p")
  }

  // MARK: - Change ID sequencing

  @Test func codeBlockLineGroupIDsFollowGlobalSequence() {
    // Changes before the code block use some change IDs. The code
    // block's line groups should continue the sequence.
    let old = ParsedMarkdown("Original.\n\n```\nold line\n```\n")
    let new = ParsedMarkdown("Changed.\n\n```\nnew line\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // leaves[0] = "Changed." paragraph, leaves[1] = code block

    // The paragraph replacement uses change IDs (del + ins).
    let paraID = context.changeID(for: leaves[0])
    #expect(paraID != nil, "Changed paragraph should have a change ID")

    // The code block's line groups should have higher-numbered IDs.
    let codeDiff = context.codeBlockDiff(for: leaves[1])
    #expect(codeDiff != nil)
    if let codeDiff {
      let codeChangeIDs = codeDiff.lines.compactMap(\.changeID)
      #expect(!codeChangeIDs.isEmpty)
      // All code block change IDs should be "later" than the paragraph's.
      // Since IDs are "change-N", compare numerically.
      if let paraNum = paraID.flatMap({ extractNumber($0) }) {
        for codeID in codeChangeIDs {
          if let codeNum = extractNumber(codeID) {
            #expect(codeNum > paraNum,
              "Code block change ID \(codeID) should follow paragraph's \(paraID!)")
          }
        }
      }
    }
  }

  @Test func codeBlockGroupIDsFollowGlobalSequence() {
    // Group IDs from code block line groups should follow the
    // global group sequence.
    let old = ParsedMarkdown("Original.\n\n```\nold line\n```\n")
    let new = ParsedMarkdown("Changed.\n\n```\nnew line\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let paraID = context.changeID(for: leaves[0])!
    let paraGroup = context.groupInfo(for: paraID)
    #expect(paraGroup != nil)

    let codeDiff = context.codeBlockDiff(for: leaves[1])
    #expect(codeDiff != nil)
    if let codeDiff, let paraGroup {
      let codeGroupIndices = Set(codeDiff.lines.compactMap(\.groupIndex))
      for idx in codeGroupIndices {
        #expect(idx > paraGroup.groupIndex,
          "Code block group index should follow paragraph's group")
      }
    }
  }

  // MARK: - Group break at code block boundaries

  @Test func codeBlockGroupsSeparateFromAdjacentBlockChanges() {
    // A changed paragraph immediately followed by a changed code
    // block should be in separate groups — the code block boundary
    // forces a break.
    let old = ParsedMarkdown("Para.\n\n```\nold\n```\n")
    let new = ParsedMarkdown("Para changed.\n\n```\nnew\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let paraID = context.changeID(for: leaves[0])!
    let paraGroupID = context.groupInfo(for: paraID)!.groupID

    let codeDiff = context.codeBlockDiff(for: leaves[1])
    #expect(codeDiff != nil)
    if let codeDiff {
      let codeGroupIDs = Set(codeDiff.lines.compactMap(\.groupID))
      for gid in codeGroupIDs {
        #expect(gid != paraGroupID,
          "Code block groups should be separate from adjacent paragraph group")
      }
    }
  }

  // MARK: - Unpaired code blocks use block-level

  @Test func newCodeBlockUsesBlockLevel() {
    // A code block that's purely inserted (no paired deletion)
    // should use block-level handling as today.
    let old = ParsedMarkdown("Keep.\n")
    let new = ParsedMarkdown("Keep.\n\n```\nnew code\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    #expect(leaves.count == 2)

    // Code block should be annotated at block level.
    #expect(context.annotation(for: leaves[1]) == .inserted)
    // No line-level diff.
    #expect(context.codeBlockDiff(for: leaves[1]) == nil)
  }

  @Test func deletedCodeBlockUsesBlockLevel() {
    // A purely deleted code block should appear as a block-level
    // deletion, not a line-level diff.
    let old = ParsedMarkdown("Keep.\n\n```\nold code\n```\n")
    let new = ParsedMarkdown("Keep.\n")
    let context = DiffContext(old: old, new: new)

    let trailing = context.trailingDeletions()
    #expect(trailing.count == 1)
    #expect(trailing[0].tag == "pre")
  }

  // MARK: - Fallback for identical content

  @Test func pairedCodeBlockWithSameContentFallsToBlockLevel() {
    // Old and new code blocks have identical content but different
    // fencing (e.g. ``` vs ~~~~). Content matches → fall back to
    // block-level.
    let old = ParsedMarkdown("```\nsame\n```\n")
    let new = ParsedMarkdown("~~~~\nsame\n~~~~\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // If the block matcher sees them as different (different
    // fingerprints due to fence style), they'll be a del+ins pair
    // with identical code. The line diff returns nil, so block-level
    // handling applies.
    if context.annotation(for: leaves[0]) == .inserted {
      // Block-level path taken — no line-level diff.
      #expect(context.codeBlockDiff(for: leaves[0]) == nil)
    }
    // If block matcher sees them as unchanged (same fingerprint),
    // no annotation at all, which is also fine.
  }

  // MARK: - Mermaid code blocks

  @Test func pairedMermaidBlockHasNoLineDiff() {
    let old = ParsedMarkdown("```mermaid\ngraph LR\n  A-->B\n```\n")
    let new = ParsedMarkdown("```mermaid\ngraph LR\n  A-->C\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // Mermaid should not get line-level diff.
    #expect(context.codeBlockDiff(for: leaves[0]) == nil,
      "Mermaid code blocks should not get line-level diff")
  }

  @Test func pairedMermaidBlockMarkedAsMixedInsertion() {
    let old = ParsedMarkdown("```mermaid\ngraph LR\n  A-->B\n```\n")
    let new = ParsedMarkdown("```mermaid\ngraph LR\n  A-->C\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // The new mermaid block should be annotated as inserted.
    #expect(context.annotation(for: leaves[0]) == .inserted,
      "Changed mermaid block should be annotated as inserted")

    // The group should be mixed (del + ins).
    let changeID = context.changeID(for: leaves[0])!
    let info = context.groupInfo(for: changeID)!
    #expect(info.isMixed,
      "Mermaid replacement should produce a mixed group")
  }

  @Test func pairedMermaidDeletionRendersPlaceholder() {
    let old = ParsedMarkdown("```mermaid\ngraph LR\n  A-->B\n```\n")
    let new = ParsedMarkdown("```mermaid\ngraph LR\n  A-->C\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    let deletions = context.precedingDeletions(before: leaves[0])
    #expect(deletions.count == 1,
      "Mermaid deletion should appear as a preceding deletion")
    #expect(deletions[0].html.contains("[revised diagram]"),
      "Mermaid deletion should show placeholder text")
    #expect(!deletions[0].html.contains("graph LR"),
      "Mermaid deletion should not show raw source")
  }

  // MARK: - Code block with surrounding context

  @Test func codeBlockDiffWithSurroundingUnchangedBlocks() {
    let old = ParsedMarkdown("Before.\n\n```\nold line\n```\n\nAfter.\n")
    let new = ParsedMarkdown("Before.\n\n```\nnew line\n```\n\nAfter.\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // leaves: Before, code block, After
    #expect(leaves.count == 3)

    // Before and After are unchanged.
    #expect(context.annotation(for: leaves[0]) == nil)
    #expect(context.annotation(for: leaves[2]) == nil)

    // Code block has line-level diff.
    #expect(context.codeBlockDiff(for: leaves[1]) != nil)
    #expect(context.annotation(for: leaves[1]) == nil)
  }

  // MARK: - Multiple changed code blocks

  @Test func multiplePairedCodeBlocksEachGetLineDiff() {
    let old = ParsedMarkdown(
      "```\nalpha\n```\n\nSep.\n\n```\nbeta\n```\n")
    let new = ParsedMarkdown(
      "```\nalpha2\n```\n\nSep.\n\n```\nbeta2\n```\n")
    let context = DiffContext(old: old, new: new)

    let leaves = leafBlocks(of: new)
    // leaves: code block 1, Sep, code block 2
    #expect(leaves.count == 3)

    let diff1 = context.codeBlockDiff(for: leaves[0])
    let diff2 = context.codeBlockDiff(for: leaves[2])
    #expect(diff1 != nil, "First code block should have line diff")
    #expect(diff2 != nil, "Second code block should have line diff")

    // Their group IDs should be distinct.
    if let d1 = diff1, let d2 = diff2 {
      let groups1 = Set(d1.lines.compactMap(\.groupID))
      let groups2 = Set(d2.lines.compactMap(\.groupID))
      #expect(groups1.isDisjoint(with: groups2),
        "Different code blocks should have different group IDs")
    }
  }
}

// MARK: - Test helpers

private func leafBlocks(of parsed: ParsedMarkdown) -> [Markup] {
  var collector = LeafCollector()
  collector.visit(parsed.document)
  return collector.leaves
}

private struct LeafCollector: MarkupWalker {
  var leaves: [Markup] = []

  mutating func visitParagraph(_ p: Paragraph) { leaves.append(p) }
  mutating func visitHeading(_ h: Heading) { leaves.append(h) }
  mutating func visitCodeBlock(_ c: CodeBlock) { leaves.append(c) }
  mutating func visitListItem(_ l: ListItem) { leaves.append(l) }
  mutating func visitBlockQuote(_ b: BlockQuote) { descendInto(b) }
  mutating func visitTable(_ t: Table) { descendInto(t) }
  mutating func visitTableRow(_ r: Table.Row) { leaves.append(r) }
  mutating func visitThematicBreak(_ t: ThematicBreak) { leaves.append(t) }
  mutating func visitHTMLBlock(_ h: HTMLBlock) { leaves.append(h) }
}

/// Extracts the numeric suffix from a change ID like "change-3".
private func extractNumber(_ id: String) -> Int? {
  guard let idx = id.lastIndex(of: "-") else { return nil }
  return Int(id[id.index(after: idx)...])
}
