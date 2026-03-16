/// Maps block-level diff matches to line-level annotations for Down mode
/// rendering.
///
/// Built from `BlockMatcher.match()` results. Provides two lookups:
/// - `annotation(forLine:)` — for new-document lines that fall within an
///   inserted or modified block.
/// - `deletionGroups` — old-document source lines to interleave into the
///   new-document layout.
struct LineDiffMap {
    private let annotations: [Int: LineAnnotation]
    let deletionGroups: [DeletionGroup]

    func annotation(forLine line: Int) -> LineAnnotation? {
        annotations[line]
    }
}

/// A line in the new document that belongs to an inserted or modified block.
struct LineAnnotation {
    let changeID: String
}

/// A contiguous group of old-document lines to re-insert as deletions.
struct DeletionGroup {
    /// Insert before this new-document line number (1-based).
    /// `Int.max` for trailing deletions (after all new-doc lines).
    let beforeNewLine: Int
    /// Line range in the old document (1-based, closed).
    let oldLineRange: ClosedRange<Int>
    /// Change ID for `data-change-id` attributes and sidebar matching.
    let changeID: String
}

// MARK: - Construction

extension LineDiffMap {
    init(matches: [BlockMatch]) {
        var annotations: [Int: LineAnnotation] = [:]
        var groups: [DeletionGroup] = []
        var changeCounter = 0

        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        var pendingDeletions: [(range: ClosedRange<Int>, changeID: String)] = []

        func flushDeletions(beforeNewLine line: Int) {
            for del in pendingDeletions {
                groups.append(DeletionGroup(
                    beforeNewLine: line,
                    oldLineRange: del.range,
                    changeID: del.changeID))
            }
            pendingDeletions.removeAll()
        }

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                if let range = Self.lineRange(for: new) {
                    flushDeletions(beforeNewLine: range.lowerBound)
                }

            case .inserted(let new):
                if let range = Self.lineRange(for: new) {
                    flushDeletions(beforeNewLine: range.lowerBound)
                    let id = nextChangeID()
                    for line in range {
                        annotations[line] = LineAnnotation(changeID: id)
                    }
                }

            case .deleted(let old):
                let id = nextChangeID()
                if let range = Self.lineRange(for: old) {
                    pendingDeletions.append((range: range, changeID: id))
                }

            case .modified(let old, let new):
                let delID = nextChangeID()
                if let range = Self.lineRange(for: old) {
                    pendingDeletions.append((range: range, changeID: delID))
                }
                if let newRange = Self.lineRange(for: new) {
                    flushDeletions(beforeNewLine: newRange.lowerBound)
                    let modID = nextChangeID()
                    for line in newRange {
                        annotations[line] = LineAnnotation(changeID: modID)
                    }
                }
            }
        }

        // Trailing deletions — no surviving block follows.
        for del in pendingDeletions {
            groups.append(DeletionGroup(
                beforeNewLine: Int.max,
                oldLineRange: del.range,
                changeID: del.changeID))
        }

        self.annotations = annotations
        self.deletionGroups = groups
    }

    /// Derives the 1-based line range from a leaf block's AST source range.
    private static func lineRange(for block: LeafBlock) -> ClosedRange<Int>? {
        guard let range = block.markup.range else { return nil }
        return range.lowerBound.line...range.upperBound.line
    }
}
