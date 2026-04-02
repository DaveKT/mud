/// Pairs deleted and inserted lines by word overlap rather than
/// positional order, so word-level diffs compare the most similar
/// lines within a gap.
enum WordPairing {
    /// Returns `(delIndex, insIndex)` pairs chosen by greedy
    /// best-match on shared word count. Indices are offsets into the
    /// provided arrays, not document line numbers.
    static func bestPairs(
        delLines: [String], insLines: [String]
    ) -> [(del: Int, ins: Int)] {
        let pairCount = min(delLines.count, insLines.count)
        guard pairCount > 0 else { return [] }

        // Fast path: exactly one element on each side.
        if delLines.count == 1 && insLines.count == 1 {
            return [(del: 0, ins: 0)]
        }

        // Build scored candidates.
        var candidates: [(del: Int, ins: Int, score: Int)] = []
        candidates.reserveCapacity(delLines.count * insLines.count)
        for d in 0..<delLines.count {
            let dWords = words(in: delLines[d])
            for i in 0..<insLines.count {
                let iWords = words(in: insLines[i])
                let score = dWords.intersection(iWords).count
                candidates.append((del: d, ins: i, score: score))
            }
        }

        // Greedy: pick best score, remove both, repeat.
        candidates.sort { $0.score > $1.score }
        var usedDel = Set<Int>()
        var usedIns = Set<Int>()
        var pairs: [(del: Int, ins: Int)] = []
        pairs.reserveCapacity(pairCount)

        for c in candidates {
            guard pairs.count < pairCount else { break }
            guard !usedDel.contains(c.del),
                  !usedIns.contains(c.ins) else { continue }
            pairs.append((del: c.del, ins: c.ins))
            usedDel.insert(c.del)
            usedIns.insert(c.ins)
        }

        return pairs
    }

    private static func words(in text: String) -> Set<Substring> {
        Set(text.split(whereSeparator: \.isWhitespace))
    }
}
