import Testing
@testable import MudCore

@Suite("LineLevelDiff")
struct LineLevelDiffTests {
  // MARK: - Identical content

  @Test func identicalLinesReturnsNil() {
    let lines = ["alpha", "beta", "gamma"]
    #expect(LineLevelDiff.diff(old: lines, new: lines) == nil)
  }

  @Test func bothEmptyReturnsNil() {
    #expect(LineLevelDiff.diff(old: [], new: []) == nil)
  }

  @Test func singleLineIdenticalReturnsNil() {
    #expect(LineLevelDiff.diff(old: ["same"], new: ["same"]) == nil)
  }

  // MARK: - Single line changed

  @Test func singleLineReplacedProducesDeletedThenInserted() {
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c"],
      new: ["a", "B", "c"])!
    let annotations = result.map(\.annotation)
    #expect(annotations == [.unchanged, .deleted, .inserted, .unchanged])
  }

  @Test func singleLinePairTriviallyChanged() {
    let result = LineLevelDiff.diff(old: ["old"], new: ["new"])!
    #expect(result.count == 2)
    #expect(result[0].annotation == .deleted)
    #expect(result[1].annotation == .inserted)
  }

  // MARK: - Insertions

  @Test func linesInsertedAtEnd() {
    let result = LineLevelDiff.diff(
      old: ["a", "b"],
      new: ["a", "b", "c", "d"])!
    #expect(result.filter({ $0.annotation == .inserted }).count == 2)
    #expect(result.filter({ $0.annotation == .deleted }).count == 0)
  }

  @Test func linesInsertedInMiddle() {
    let result = LineLevelDiff.diff(
      old: ["a", "c"],
      new: ["a", "b", "c"])!
    let annotations = result.map(\.annotation)
    #expect(annotations == [.unchanged, .inserted, .unchanged])
  }

  // MARK: - Deletions

  @Test func linesDeletedFromMiddle() {
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c", "d"],
      new: ["a", "d"])!
    #expect(result.filter({ $0.annotation == .deleted }).count == 2)
    #expect(result.filter({ $0.annotation == .inserted }).count == 0)
  }

  // MARK: - Multiple gaps

  @Test func twoSeparateChanges() {
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c", "d", "e"],
      new: ["a", "B", "c", "D", "e"])!
    let annotations = result.map(\.annotation)
    #expect(annotations == [
      .unchanged, .deleted, .inserted,
      .unchanged, .deleted, .inserted,
      .unchanged,
    ])
  }

  // MARK: - Gap ordering

  @Test func deletionsBeforeInsertionsInGap() {
    // Gap has 2 deletions and 1 insertion.
    let result = LineLevelDiff.diff(
      old: ["a", "x", "y", "b"],
      new: ["a", "z", "b"])!
    let gap = result.filter { $0.annotation != .unchanged }
    #expect(gap.count == 3)
    #expect(gap[0].annotation == .deleted)
    #expect(gap[1].annotation == .deleted)
    #expect(gap[2].annotation == .inserted)
  }

  // MARK: - Degenerate cases

  @Test func allLinesChanged() {
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c"],
      new: ["x", "y", "z"])!
    #expect(result.filter({ $0.annotation == .deleted }).count == 3)
    #expect(result.filter({ $0.annotation == .inserted }).count == 3)
    #expect(result.filter({ $0.annotation == .unchanged }).count == 0)
  }

  @Test func emptyOldAllInserted() {
    let result = LineLevelDiff.diff(old: [], new: ["a", "b"])!
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.annotation == .inserted })
  }

  @Test func emptyNewAllDeleted() {
    let result = LineLevelDiff.diff(old: ["a", "b"], new: [])!
    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.annotation == .deleted })
  }

  // MARK: - Source indices

  @Test func unchangedEntryCarriesNewIndex() {
    // Old: [a, b, c] → New: [a, X, b, c]
    // "a" is at new[0], "b" at new[2], "c" at new[3].
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c"],
      new: ["a", "X", "b", "c"])!
    let unchanged = result.filter { $0.annotation == .unchanged }
    #expect(unchanged[0].sourceIndex == 0)
    #expect(unchanged[1].sourceIndex == 2)
    #expect(unchanged[2].sourceIndex == 3)
  }

  @Test func deletedEntryCarriesOldIndex() {
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c"],
      new: ["a", "c"])!
    let deleted = result.filter { $0.annotation == .deleted }
    #expect(deleted.count == 1)
    #expect(deleted[0].sourceIndex == 1) // old[1] = "b"
  }

  @Test func insertedEntryCarriesNewIndex() {
    let result = LineLevelDiff.diff(
      old: ["a", "c"],
      new: ["a", "b", "c"])!
    let inserted = result.filter { $0.annotation == .inserted }
    #expect(inserted.count == 1)
    #expect(inserted[0].sourceIndex == 1) // new[1] = "b"
  }

  @Test func indicesCorrectWithShiftedPositions() {
    // Old: [a, b, c] → New: [a, X, Y, c]
    // Deleted b at old[1], inserted X at new[1], Y at new[2].
    let result = LineLevelDiff.diff(
      old: ["a", "b", "c"],
      new: ["a", "X", "Y", "c"])!
    let deleted = result.filter { $0.annotation == .deleted }
    let inserted = result.filter { $0.annotation == .inserted }
    #expect(deleted[0].sourceIndex == 1) // old[1]
    #expect(inserted[0].sourceIndex == 1) // new[1]
    #expect(inserted[1].sourceIndex == 2) // new[2]
  }

  // MARK: - Whitespace sensitivity

  @Test func whitespaceOnlyChangeDetected() {
    let old = ["  line one", "line two"]
    let new = ["    line one", "line two"]
    let result = LineLevelDiff.diff(old: old, new: new)
    #expect(result != nil, "Re-indentation should be detected")
  }
}
