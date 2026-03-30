import Markdown
import Testing
@testable import MudCore

@Suite("WordDiff")
struct WordDiffTests {
  // MARK: - Diff algorithm

  @Test func identicalStrings() {
    let spans = WordDiff.diff(old: "hello world", new: "hello world")
    let allUnchanged = spans.allSatisfy(\.isUnchanged)
    #expect(allUnchanged)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func singleWordChanged() {
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox")
    // Transition separator between gap and anchor is unchanged.
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .deleted("quick"),
      .inserted("slow"),
      .unchanged(" "),
      .unchanged("fox"),
    ])
  }

  @Test func wordAddedInMiddle() {
    let spans = WordDiff.diff(old: "the fox", new: "the brown fox")
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .inserted("brown"), .inserted(" "),
      .unchanged("fox"),
    ])
  }

  @Test func wordRemovedFromMiddle() {
    let spans = WordDiff.diff(old: "the brown fox", new: "the fox")
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .deleted("brown"), .deleted(" "),
      .unchanged("fox"),
    ])
  }

  @Test func multipleChanges() {
    let spans = WordDiff.diff(
      old: "the quick brown fox jumps",
      new: "the slow brown dog leaps")
    #expect(reconstructOld(spans) == "the quick brown fox jumps")
    #expect(reconstructNew(spans) == "the slow brown dog leaps")
    let deletedWords = spans.filter(\.isDeleted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    let insertedWords = spans.filter(\.isInserted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    #expect(deletedWords.count == 3)
    #expect(insertedWords.count == 3)
  }

  @Test func completelyDifferent() {
    let spans = WordDiff.diff(old: "alpha beta", new: "gamma delta")
    // The space is the same in both, so it's unchanged.
    #expect(reconstructOld(spans) == "alpha beta")
    #expect(reconstructNew(spans) == "gamma delta")
  }

  @Test func emptyOld() {
    let spans = WordDiff.diff(old: "", new: "hello world")
    let allInserted = spans.allSatisfy(\.isInserted)
    #expect(allInserted)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func emptyNew() {
    let spans = WordDiff.diff(old: "hello world", new: "")
    let allDeleted = spans.allSatisfy(\.isDeleted)
    #expect(allDeleted)
    #expect(reconstructOld(spans) == "hello world")
  }

  @Test func bothEmpty() {
    let spans = WordDiff.diff(old: "", new: "")
    #expect(spans.isEmpty)
  }

  @Test func whitespacePreservation() {
    let spans = WordDiff.diff(
      old: "one two three", new: "one changed three")
    #expect(reconstructOld(spans) == "one two three")
    #expect(reconstructNew(spans) == "one changed three")
  }

  @Test func multipleConsecutiveSpaces() {
    // Double-space is its own token, distinct from single space.
    let spans = WordDiff.diff(
      old: "hello  world", new: "hello  earth")
    #expect(reconstructOld(spans) == "hello  world")
    #expect(reconstructNew(spans) == "hello  earth")
    let hasDeleted = spans.contains(where: \.isDeleted)
    let hasInserted = spans.contains(where: \.isInserted)
    #expect(hasDeleted)
    #expect(hasInserted)
  }

  @Test func wordsRemovedFromEnd() {
    // A word at the end of one text matches the same word in the
    // middle of the other — no trailing whitespace mismatch because
    // words and whitespace are separate tokens.
    let spans = WordDiff.diff(
      old: "hello world end", new: "hello world")
    #expect(reconstructNew(spans) == "hello world")
    #expect(reconstructOld(spans) == "hello world end")
    let deletedWords = spans.filter(\.isDeleted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    #expect(deletedWords.count == 1)
    #expect(deletedWords[0].text == "end")
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
