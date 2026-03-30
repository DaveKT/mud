/// Maps block-level diff matches to line-level annotations for Down mode
/// rendering.
///
/// Built from `BlockMatcher.match()` results. Provides two lookups:
/// - `annotation(forLine:)` — for new-document lines that fall within an
///   inserted block.
/// - `deletionGroups` — old-document source lines to interleave into the
///   new-document layout.
///
/// When paired blocks exist (a deletion and insertion in the same gap),
/// word-level diff spans are computed and stored for each change ID.
struct LineDiffMap {
    private let annotations: [Int: LineAnnotation]
    let deletionGroups: [DeletionGroup]
    private let wordDataMap: [String: BlockWordData]

    func annotation(forLine line: Int) -> LineAnnotation? {
        annotations[line]
    }

    func wordData(for changeID: String) -> BlockWordData? {
        wordDataMap[changeID]
    }
}

/// A line in the new document that belongs to an inserted block.
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

/// Word-level diff data for a paired block.
struct BlockWordData {
    /// Word spans from `WordDiff.diff(old:new:)`.
    let spans: [WordSpan]
    /// This block's source text (raw markdown).
    let sourceText: String
    /// True for insertion blocks, false for deletion blocks.
    let isInsertion: Bool
    /// 1-based line number of the block's start in its document.
    let startLine: Int
}

// MARK: - Construction

extension LineDiffMap {
    init(matches: [BlockMatch]) {
        var annotations: [Int: LineAnnotation] = [:]
        var groups: [DeletionGroup] = []
        var wordData: [String: BlockWordData] = [:]
        var changeCounter = 0

        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        // Accumulate deletions and insertions within each gap.
        var pendingDels: [(block: LeafBlock, changeID: String)] = []
        var pendingIns: [(block: LeafBlock, changeID: String,
                          lineRange: ClosedRange<Int>)] = []

        func finalizeGap(beforeNewLine anchorLine: Int) {
            // Pair deletions with insertions and compute word diffs.
            for (del, ins) in zip(pendingDels, pendingIns) {
                let spans = WordDiff.diff(
                    old: del.block.sourceText,
                    new: ins.block.sourceText)
                let hasWordChanges = spans.contains { !$0.isUnchanged }
                if hasWordChanges {
                    wordData[del.changeID] = BlockWordData(
                        spans: spans, sourceText: del.block.sourceText,
                        isInsertion: false,
                        startLine: del.block.sourceLine)
                    wordData[ins.changeID] = BlockWordData(
                        spans: spans, sourceText: ins.block.sourceText,
                        isInsertion: true,
                        startLine: ins.block.sourceLine)
                }
            }

            // Emit deletion groups — positioned before the first
            // insertion, or before the next unchanged block.
            let delBeforeLine = pendingIns.first
                .map { $0.lineRange.lowerBound } ?? anchorLine
            for del in pendingDels {
                if let range = Self.lineRange(for: del.block) {
                    groups.append(DeletionGroup(
                        beforeNewLine: delBeforeLine,
                        oldLineRange: range,
                        changeID: del.changeID))
                }
            }

            // Emit insertion annotations.
            for ins in pendingIns {
                for line in ins.lineRange {
                    annotations[line] = LineAnnotation(
                        changeID: ins.changeID)
                }
            }

            pendingDels.removeAll()
            pendingIns.removeAll()
        }

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                if let range = Self.lineRange(for: new) {
                    finalizeGap(beforeNewLine: range.lowerBound)
                }

            case .inserted(let new):
                let id = nextChangeID()
                if let range = Self.lineRange(for: new) {
                    pendingIns.append((
                        block: new, changeID: id, lineRange: range))
                }

            case .deleted(let old):
                let id = nextChangeID()
                pendingDels.append((block: old, changeID: id))
            }
        }

        // Trailing gap — no surviving block follows.
        finalizeGap(beforeNewLine: Int.max)

        self.annotations = annotations
        self.deletionGroups = groups
        self.wordDataMap = wordData
    }

    /// Derives the 1-based line range from a leaf block's AST source range.
    private static func lineRange(for block: LeafBlock) -> ClosedRange<Int>? {
        guard let range = block.markup.range else { return nil }
        return range.lowerBound.line...range.upperBound.line
    }
}
