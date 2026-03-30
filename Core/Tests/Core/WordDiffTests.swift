import Markdown
import Testing
@testable import MudCore

@Suite("WordDiff")
struct WordDiffTests {
  // MARK: - Diff algorithm

  @Test func identicalStrings() {
    let spans = WordDiff.diff(old: "hello world", new: "hello world").forNew
    let allUnchanged = spans.allSatisfy(\.isUnchanged)
    #expect(allUnchanged)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func singleWordChanged() {
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox").forNew
    // Common trailing whitespace is factored out of del+ins pairs.
    #expect(spans == [
      .unchanged("the "),
      .deleted("quick"),
      .inserted("slow"),
      .unchanged(" "),
      .unchanged("fox"),
    ])
  }

  @Test func wordAddedInMiddle() {
    let spans = WordDiff.diff(old: "the fox", new: "the brown fox").forNew
    #expect(spans == [
      .unchanged("the "),
      .inserted("brown "),
      .unchanged("fox"),
    ])
  }

  @Test func wordRemovedFromMiddle() {
    let spans = WordDiff.diff(old: "the brown fox", new: "the fox").forNew
    #expect(spans == [
      .unchanged("the "),
      .deleted("brown "),
      .unchanged("fox"),
    ])
  }

  @Test func multipleChanges() {
    let result = WordDiff.diff(
      old: "the quick brown fox jumps",
      new: "the slow brown dog leaps")
    #expect(reconstructOld(result.forOld) == "the quick brown fox jumps")
    #expect(reconstructNew(result.forNew) == "the slow brown dog leaps")
    let deletedCount = result.forNew.filter(\.isDeleted).count
    let insertedCount = result.forNew.filter(\.isInserted).count
    #expect(deletedCount == 3)
    #expect(insertedCount == 3)
  }

  @Test func completelyDifferent() {
    let spans = WordDiff.diff(old: "alpha beta", new: "gamma delta").forNew
    let unchangedSpans = spans.filter(\.isUnchanged)
    #expect(unchangedSpans.isEmpty)
    #expect(reconstructNew(spans) == "gamma delta")
  }

  @Test func emptyOld() {
    let spans = WordDiff.diff(old: "", new: "hello world").forNew
    let allInserted = spans.allSatisfy(\.isInserted)
    #expect(allInserted)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func emptyNew() {
    let spans = WordDiff.diff(old: "hello world", new: "").forOld
    let allDeleted = spans.allSatisfy(\.isDeleted)
    #expect(allDeleted)
    #expect(reconstructOld(spans) == "hello world")
  }

  @Test func bothEmpty() {
    let spans = WordDiff.diff(old: "", new: "").forNew
    #expect(spans.isEmpty)
  }

  @Test func whitespacePreservation() {
    // Trailing spaces stay attached to tokens; round-trip through
    // spans reproduces the original text.
    let result = WordDiff.diff(
      old: "one two three", new: "one changed three")
    #expect(reconstructOld(result.forOld) == "one two three")
    #expect(reconstructNew(result.forNew) == "one changed three")
  }

  @Test func multipleConsecutiveSpaces() {
    // Runs of multiple spaces attach to the preceding token.
    let result = WordDiff.diff(
      old: "hello  world", new: "hello  earth")
    #expect(reconstructOld(result.forOld) == "hello  world")
    #expect(reconstructNew(result.forNew) == "hello  earth")
    let hasDeleted = result.forNew.contains(where: \.isDeleted)
    let hasInserted = result.forNew.contains(where: \.isInserted)
    #expect(hasDeleted)
    #expect(hasInserted)
  }

  @Test func trailingWhitespaceMismatchStillMatches() {
    // A word at the end of one text (no trailing space) should
    // match the same word in the middle of the other (with trailing
    // space). This happens when lines are removed from a paragraph.
    let result = WordDiff.diff(
      old: "hello world end", new: "hello world")
    // "world" (end of new) matches "world " (middle of old).
    #expect(reconstructNew(result.forNew) == "hello world")
    #expect(reconstructOld(result.forOld) == "hello world end")
    // Only "end" should be deleted (plus the trailing space from
    // old "world " that the new "world" lacks).
    let deletedTexts = result.forNew.filter(\.isDeleted).map(\.text)
    let deletedWords = deletedTexts.filter { !$0.allSatisfy(\.isWhitespace) }
    #expect(deletedWords.count == 1)
    #expect(deletedWords[0].contains("end"))
  }

  // MARK: - Structure comparison

  @Test func sameStructurePlainText() {
    let old = ParsedMarkdown("Hello world.\n")
    let new = ParsedMarkdown("Goodbye world.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func sameStructureWithEmphasis() {
    let old = ParsedMarkdown("Hello *beautiful* world.\n")
    let new = ParsedMarkdown("Goodbye *wonderful* world.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func sameStructureNestedFormatting() {
    let old = ParsedMarkdown("Hello **bold *and italic*** end.\n")
    let new = ParsedMarkdown("Goodbye **changed *stuff here*** end.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func sameStructureWithInlineCode() {
    let old = ParsedMarkdown("Call `foo()` now.\n")
    let new = ParsedMarkdown("Call `bar()` now.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func differentNesting() {
    let old = ParsedMarkdown("Hello **bold** world.\n")
    let new = ParsedMarkdown("Hello *italic* world.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(!WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func extraNodeInNew() {
    let old = ParsedMarkdown("Hello world.\n")
    let new = ParsedMarkdown("Hello **bold** world.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(!WordDiff.hasMatchingStructure(oldPara, newPara))
  }

  @Test func sameStructureDifferentText() {
    let old = ParsedMarkdown("Alpha **beta** gamma.\n")
    let new = ParsedMarkdown("One **two** three.\n")
    let oldPara = old.document.child(at: 0)!
    let newPara = new.document.child(at: 0)!
    #expect(WordDiff.hasMatchingStructure(oldPara, newPara))
  }
}

// MARK: - Test helpers

/// Reconstructs the new text from a span list by concatenating
/// unchanged and inserted spans.
private func reconstructNew(_ spans: [WordSpan]) -> String {
  spans.filter { !$0.isDeleted }.map(\.text).joined()
}

/// Reconstructs the old text from a span list by concatenating
/// unchanged and deleted spans.
private func reconstructOld(_ spans: [WordSpan]) -> String {
  spans.filter { !$0.isInserted }.map(\.text).joined()
}
