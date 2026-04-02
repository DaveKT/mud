import Markdown

/// Maps block-level diff matches to line-level annotations for Down mode
/// rendering.
///
/// Built from `BlockMatcher.match()` results. Paired blocks get
/// line-level diffs: only actually-changed lines are annotated.
/// Unchanged lines within a modified block render normally. Code block
/// pairs use `CodeBlockDiff` for cluster-based ID assignment matching
/// `DiffContext`.
struct LineDiffMap {
    private let annotations: [Int: LineAnnotation]
    let deletionGroups: [DeletionGroup]
    private let wordDataMap: [String: [Int: BlockWordData]]

    func annotation(forLine line: Int) -> LineAnnotation? {
        annotations[line]
    }

    func wordData(for changeID: String, line: Int) -> BlockWordData? {
        wordDataMap[changeID]?[line]
    }
}

/// A line in the new document that belongs to a changed block.
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

/// Word-level diff data for a line within a paired block.
struct BlockWordData {
    /// Word spans from `WordDiff.diff(old:new:)`.
    let spans: [WordSpan]
    /// This line's source text (raw markdown).
    let sourceText: String
    /// True for insertion lines, false for deletion lines.
    let isInsertion: Bool
    /// 1-based line number of this entry in its document.
    let startLine: Int
}

// MARK: - Construction

extension LineDiffMap {
    init(matches: [BlockMatch]) {
        var annotations: [Int: LineAnnotation] = [:]
        var groups: [DeletionGroup] = []
        var wordData: [String: [Int: BlockWordData]] = [:]
        var changeCounter = 0

        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        var pendingDels: [(block: LeafBlock, changeID: String)] = []
        var pendingIns: [(block: LeafBlock, changeID: String,
                          lineRange: ClosedRange<Int>)] = []

        // MARK: Gap finalization

        func finalizeGap(beforeNewLine anchorLine: Int) {
            let pairCount = min(pendingDels.count, pendingIns.count)

            for i in 0..<pairCount {
                let del = pendingDels[i]
                let ins = pendingIns[i]
                if processCodeBlockPair(
                    del: del, ins: ins,
                    anchorLine: anchorLine) {
                    continue
                }
                processLineLevelPair(
                    del: del, ins: ins,
                    anchorLine: anchorLine)
            }

            // Unpaired deletions — block-level.
            for i in pairCount..<pendingDels.count {
                if let range = Self.lineRange(
                    for: pendingDels[i].block) {
                    groups.append(DeletionGroup(
                        beforeNewLine: anchorLine,
                        oldLineRange: range,
                        changeID: pendingDels[i].changeID))
                }
            }

            // Unpaired insertions — block-level.
            for i in pairCount..<pendingIns.count {
                let ins = pendingIns[i]
                for line in ins.lineRange {
                    annotations[line] = LineAnnotation(
                        changeID: ins.changeID)
                }
            }

            pendingDels.removeAll()
            pendingIns.removeAll()
        }

        // MARK: Line-level pair

        /// Runs `LineLevelDiff` on the paired block's source text and
        /// emits fine-grained annotations, deletion groups, and
        /// per-line word data.
        func processLineLevelPair(
            del: (block: LeafBlock, changeID: String),
            ins: (block: LeafBlock, changeID: String,
                  lineRange: ClosedRange<Int>),
            anchorLine: Int
        ) {
            let oldLines = del.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let newLines = ins.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)

            guard let entries = LineLevelDiff.diff(
                old: oldLines, new: newLines
            ) else {
                emitBlockLevel(del: del, ins: ins,
                               anchorLine: anchorLine)
                return
            }

            var idx = 0
            while idx < entries.count {
                if entries[idx].annotation == .unchanged {
                    idx += 1
                    continue
                }

                // Collect the gap (consecutive changed entries).
                var gapDelOldLines: [Int] = []
                var gapInsNewLines: [Int] = []

                while idx < entries.count,
                      entries[idx].annotation != .unchanged {
                    switch entries[idx].annotation {
                    case .deleted:
                        gapDelOldLines.append(
                            del.block.sourceLine
                                + entries[idx].sourceIndex)
                    case .inserted:
                        gapInsNewLines.append(
                            ins.block.sourceLine
                                + entries[idx].sourceIndex)
                    case .unchanged:
                        break
                    }
                    idx += 1
                }

                // Position deletion group before the first insertion
                // in this gap, or before the next unchanged line, or
                // before the overall anchor.
                let beforeLine: Int
                if let firstIns = gapInsNewLines.first {
                    beforeLine = firstIns
                } else if idx < entries.count {
                    beforeLine = ins.block.sourceLine
                        + entries[idx].sourceIndex
                } else {
                    beforeLine = anchorLine
                }

                if let first = gapDelOldLines.first,
                   let last = gapDelOldLines.last {
                    groups.append(DeletionGroup(
                        beforeNewLine: beforeLine,
                        oldLineRange: first...last,
                        changeID: del.changeID))
                }

                for newLine in gapInsNewLines {
                    annotations[newLine] = LineAnnotation(
                        changeID: ins.changeID)
                }

                // Word-level diffs for positionally paired lines.
                for (delLine, insLine) in
                    zip(gapDelOldLines, gapInsNewLines) {
                    let di = delLine - del.block.sourceLine
                    let ii = insLine - ins.block.sourceLine
                    guard di < oldLines.count,
                          ii < newLines.count else { continue }
                    let spans = WordDiff.diff(
                        old: oldLines[di], new: newLines[ii])
                    guard spans.contains(
                        where: { !$0.isUnchanged }) else { continue }
                    wordData[del.changeID, default: [:]][delLine] =
                        BlockWordData(
                            spans: spans,
                            sourceText: oldLines[di],
                            isInsertion: false,
                            startLine: delLine)
                    wordData[ins.changeID, default: [:]][insLine] =
                        BlockWordData(
                            spans: spans,
                            sourceText: newLines[ii],
                            isInsertion: true,
                            startLine: insLine)
                }
            }
        }

        // MARK: Code block pair

        /// Handles code block pairs via `CodeBlockDiff` so that
        /// cluster-based change IDs match `DiffContext`.
        func processCodeBlockPair(
            del: (block: LeafBlock, changeID: String),
            ins: (block: LeafBlock, changeID: String,
                  lineRange: ClosedRange<Int>),
            anchorLine: Int
        ) -> Bool {
            guard let delCB = del.block.markup as? CodeBlock,
                  let insCB = ins.block.markup as? CodeBlock
            else { return false }

            let isMermaid =
                delCB.language?.lowercased() == "mermaid"
                || insCB.language?.lowercased() == "mermaid"
            if isMermaid { return false }

            guard let raw = CodeBlockDiff.computeRaw(
                oldCode: delCB.code, newCode: insCB.code,
                oldLanguage: delCB.language,
                newLanguage: insCB.language
            ) else { return false }

            var codeLines = raw.lines
            CodeBlockDiff.assignGroups(
                &codeLines,
                nextChangeID: { nextChangeID() },
                nextGroupID: { (id: "", index: 0) })

            // Content start offsets (fenced blocks skip the fence).
            let delFenced = del.block.sourceText.hasPrefix("`")
                || del.block.sourceText.hasPrefix("~")
            let insFenced = ins.block.sourceText.hasPrefix("`")
                || ins.block.sourceText.hasPrefix("~")
            let delStart = del.block.sourceLine
                + (delFenced ? 1 : 0)
            let insStart = ins.block.sourceLine
                + (insFenced ? 1 : 0)

            // Source lines for word diffs.
            let delSrcLines = del.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let insSrcLines = ins.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let delFenceOff = delFenced ? 1 : 0
            let insFenceOff = insFenced ? 1 : 0

            var oldCI = 0, newCI = 0
            var gapDels: [(doc: Int, code: Int)] = []
            var gapIns: [(doc: Int, code: Int)] = []
            var gapChangeID: String?

            func flushCodeGap() {
                guard let changeID = gapChangeID else { return }

                if let first = gapDels.first,
                   let last = gapDels.last {
                    let before = gapIns.first?.doc
                        ?? (insStart + newCI)
                    groups.append(DeletionGroup(
                        beforeNewLine: before,
                        oldLineRange: first.doc...last.doc,
                        changeID: changeID))
                }

                for entry in gapIns {
                    annotations[entry.doc] = LineAnnotation(
                        changeID: changeID)
                }

                for (d, i) in zip(gapDels, gapIns) {
                    let dsi = d.code + delFenceOff
                    let isi = i.code + insFenceOff
                    guard dsi < delSrcLines.count,
                          isi < insSrcLines.count
                    else { continue }
                    let spans = WordDiff.diff(
                        old: delSrcLines[dsi],
                        new: insSrcLines[isi])
                    guard spans.contains(
                        where: { !$0.isUnchanged })
                    else { continue }
                    wordData[changeID, default: [:]][d.doc] =
                        BlockWordData(
                            spans: spans,
                            sourceText: delSrcLines[dsi],
                            isInsertion: false,
                            startLine: d.doc)
                    wordData[changeID, default: [:]][i.doc] =
                        BlockWordData(
                            spans: spans,
                            sourceText: insSrcLines[isi],
                            isInsertion: true,
                            startLine: i.doc)
                }

                gapDels.removeAll()
                gapIns.removeAll()
                gapChangeID = nil
            }

            for line in codeLines {
                switch line.annotation {
                case .unchanged:
                    flushCodeGap()
                    oldCI += 1
                    newCI += 1
                case .deleted:
                    gapDels.append(
                        (doc: delStart + oldCI, code: oldCI))
                    gapChangeID = line.changeID
                    oldCI += 1
                case .inserted:
                    gapIns.append(
                        (doc: insStart + newCI, code: newCI))
                    gapChangeID = line.changeID
                    newCI += 1
                }
            }
            flushCodeGap()

            return true
        }

        // MARK: Block-level fallback

        /// Falls back to block-level treatment: all lines of the old
        /// block are deleted, all lines of the new block are inserted.
        func emitBlockLevel(
            del: (block: LeafBlock, changeID: String),
            ins: (block: LeafBlock, changeID: String,
                  lineRange: ClosedRange<Int>),
            anchorLine: Int
        ) {
            let spans = WordDiff.diff(
                old: del.block.sourceText,
                new: ins.block.sourceText)
            let hasChanges = spans.contains { !$0.isUnchanged }
            if hasChanges {
                let delData = BlockWordData(
                    spans: spans,
                    sourceText: del.block.sourceText,
                    isInsertion: false,
                    startLine: del.block.sourceLine)
                let insData = BlockWordData(
                    spans: spans,
                    sourceText: ins.block.sourceText,
                    isInsertion: true,
                    startLine: ins.block.sourceLine)
                if let range = Self.lineRange(for: del.block) {
                    for line in range {
                        wordData[del.changeID, default: [:]][line] =
                            delData
                    }
                }
                for line in ins.lineRange {
                    wordData[ins.changeID, default: [:]][line] =
                        insData
                }
            }

            if let range = Self.lineRange(for: del.block) {
                groups.append(DeletionGroup(
                    beforeNewLine: ins.lineRange.lowerBound,
                    oldLineRange: range,
                    changeID: del.changeID))
            }
            for line in ins.lineRange {
                annotations[line] = LineAnnotation(
                    changeID: ins.changeID)
            }
        }

        // MARK: Match processing

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

        finalizeGap(beforeNewLine: Int.max)

        self.annotations = annotations
        self.deletionGroups = groups
        self.wordDataMap = wordData
    }

    /// Derives the 1-based line range from a leaf block's source text.
    private static func lineRange(
        for block: LeafBlock
    ) -> ClosedRange<Int>? {
        guard block.markup.range != nil else { return nil }
        let lineCount = block.sourceText.split(
            separator: "\n",
            omittingEmptySubsequences: false).count
        guard lineCount > 0 else { return nil }
        return block.sourceLine...(block.sourceLine + lineCount - 1)
    }
}
