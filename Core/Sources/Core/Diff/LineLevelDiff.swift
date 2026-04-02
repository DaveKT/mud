/// Diffs two arrays of lines and returns per-line annotations.
///
/// Within each gap between unchanged anchors, deletions precede
/// insertions. Returns `nil` when the arrays are identical.
struct LineLevelDiff {
    struct Entry {
        let annotation: Annotation
        /// 0-based index in the source array: the new array for
        /// `.unchanged` and `.inserted`, the old array for `.deleted`.
        let sourceIndex: Int
    }

    enum Annotation: Equatable {
        case unchanged
        case inserted
        case deleted
    }

    /// Returns `nil` when the arrays are identical.
    static func diff(old: [String], new: [String]) -> [Entry]? {
        let cdiff = new.difference(from: old)
        guard !cdiff.isEmpty else { return nil }

        var removedOld = Set<Int>()
        var insertedNew = Set<Int>()
        for change in cdiff {
            switch change {
            case .remove(let offset, _, _): removedOld.insert(offset)
            case .insert(let offset, _, _): insertedNew.insert(offset)
            }
        }

        // Build anchors (unchanged pairs).
        var anchors: [(old: Int, new: Int)] = []
        var oi = 0, ni = 0
        while oi < old.count && ni < new.count {
            if removedOld.contains(oi) { oi += 1; continue }
            if insertedNew.contains(ni) { ni += 1; continue }
            anchors.append((old: oi, new: ni))
            oi += 1; ni += 1
        }

        // Build result with deletions before insertions in each gap.
        var result: [Entry] = []
        var prevOld = -1, prevNew = -1

        for anchor in anchors {
            for i in (prevOld + 1)..<anchor.old {
                result.append(Entry(
                    annotation: .deleted, sourceIndex: i))
            }
            for i in (prevNew + 1)..<anchor.new {
                result.append(Entry(
                    annotation: .inserted, sourceIndex: i))
            }
            result.append(Entry(
                annotation: .unchanged, sourceIndex: anchor.new))
            prevOld = anchor.old
            prevNew = anchor.new
        }

        // Trailing gap.
        for i in (prevOld + 1)..<old.count {
            result.append(Entry(
                annotation: .deleted, sourceIndex: i))
        }
        for i in (prevNew + 1)..<new.count {
            result.append(Entry(
                annotation: .inserted, sourceIndex: i))
        }

        return result
    }
}
