import Testing
@testable import MudCore

@Suite("WordPairing")
struct WordPairingTests {
  // MARK: - Trivial cases

  @Test func singlePair() {
    let pairs = WordPairing.bestPairs(
      delLines: ["old line"], insLines: ["new line"])
    #expect(pairs.count == 1)
    #expect(pairs[0].del == 0)
    #expect(pairs[0].ins == 0)
  }

  @Test func emptyInputs() {
    #expect(WordPairing.bestPairs(delLines: [], insLines: []).isEmpty)
    #expect(WordPairing.bestPairs(
      delLines: ["a"], insLines: []).isEmpty)
    #expect(WordPairing.bestPairs(
      delLines: [], insLines: ["a"]).isEmpty)
  }

  // MARK: - Best-match selection

  @Test func asymmetricGapPicksBestMatch() {
    // 3 deletions, 1 insertion. The insertion is most similar to
    // the third deletion.
    let dels = [
      "completely unrelated content here",
      "another different line of text",
      "the quick brown fox jumps",
    ]
    let ins = [
      "the quick red fox jumps",
    ]
    let pairs = WordPairing.bestPairs(
      delLines: dels, insLines: ins)
    #expect(pairs.count == 1)
    #expect(pairs[0].del == 2,
      "Should pair with the most similar deletion")
    #expect(pairs[0].ins == 0)
  }

  @Test func twoInsertionsMatchCorrectDeletions() {
    let dels = [
      "alpha beta gamma",
      "one two three",
    ]
    let ins = [
      "one two four",   // best match: dels[1]
      "alpha beta delta", // best match: dels[0]
    ]
    let pairs = WordPairing.bestPairs(
      delLines: dels, insLines: ins)
    #expect(pairs.count == 2)
    // Each insertion should pair with its best match.
    let sorted = pairs.sorted { $0.ins < $1.ins }
    #expect(sorted[0].del == 1, "ins[0] should pair with dels[1]")
    #expect(sorted[1].del == 0, "ins[1] should pair with dels[0]")
  }

  @Test func noOverlapStillProducesPairs() {
    let pairs = WordPairing.bestPairs(
      delLines: ["aaa bbb", "ccc ddd"],
      insLines: ["xxx yyy"])
    #expect(pairs.count == 1, "Should still pair even with zero overlap")
  }

  // MARK: - Greedy correctness

  @Test func greedyDoesNotDoubleAssign() {
    // Both insertions want the same deletion, but each can only
    // be used once.
    let dels = [
      "the shared words here",
      "nothing in common",
    ]
    let ins = [
      "the shared words there",
      "the shared words everywhere",
    ]
    let pairs = WordPairing.bestPairs(
      delLines: dels, insLines: ins)
    #expect(pairs.count == 2)
    let delIndices = Set(pairs.map(\.del))
    let insIndices = Set(pairs.map(\.ins))
    #expect(delIndices.count == 2, "Each deletion used at most once")
    #expect(insIndices.count == 2, "Each insertion used at most once")
  }
}
