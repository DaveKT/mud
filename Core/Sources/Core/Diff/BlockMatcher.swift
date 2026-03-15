import Markdown

/// Matches leaf blocks between two parsed Markdown documents.
///
/// Two phases:
/// 1. Fingerprint matching — flatten each AST into leaf blocks, hash
///    source text, run `CollectionDifference`.
/// 2. Modification detection — pair removals and insertions at the
///    same effective position into `.modified` matches.
enum BlockMatcher {
    /// Compares the leaf blocks of two documents and returns an ordered
    /// list of matches describing how blocks changed.
    static func match(old: ParsedMarkdown, new: ParsedMarkdown) -> [BlockMatch] {
        let oldBlocks = collectLeafBlocks(from: old)
        let newBlocks = collectLeafBlocks(from: new)

        guard !oldBlocks.isEmpty || !newBlocks.isEmpty else { return [] }

        let oldFingerprints = oldBlocks.map(\.fingerprint)
        let newFingerprints = newBlocks.map(\.fingerprint)

        let diff = newFingerprints.difference(from: oldFingerprints)

        // Classify every index.
        var removedOld = Set<Int>()  // old indices removed
        var insertedNew = Set<Int>() // new indices inserted

        for change in diff {
            switch change {
            case .remove(let offset, _, _):  removedOld.insert(offset)
            case .insert(let offset, _, _):  insertedNew.insert(offset)
            }
        }

        // Phase 2: Pair removals and insertions at the same index into
        // modifications (positional heuristic from the plan).
        var modOldForNew: [Int: Int] = [:] // newIndex → oldIndex
        for oi in removedOld.sorted() {
            if insertedNew.contains(oi) {
                modOldForNew[oi] = oi
                removedOld.remove(oi)
                insertedNew.remove(oi)
            }
        }

        // Build old→new mapping for unchanged blocks by walking both
        // index sequences and skipping removed/inserted indices.
        var unchangedOldForNew: [Int: Int] = [:] // newIndex → oldIndex
        var oi = 0, ni = 0
        while oi < oldBlocks.count && ni < newBlocks.count {
            if removedOld.contains(oi) { oi += 1; continue }
            if insertedNew.contains(ni) || modOldForNew[ni] != nil {
                ni += 1; continue
            }
            unchangedOldForNew[ni] = oi
            oi += 1; ni += 1
        }

        // Build the result in new-document order, interleaving deletions
        // at the correct positions using an old-index cursor.
        return buildResult(
            oldBlocks: oldBlocks,
            newBlocks: newBlocks,
            removedOld: removedOld,
            insertedNew: insertedNew,
            modOldForNew: modOldForNew,
            unchangedOldForNew: unchangedOldForNew
        )
    }
}

// MARK: - BlockMatch enum

/// Describes the relationship between a block in the old and new documents.
enum BlockMatch {
    /// Block is unchanged between old and new.
    case unchanged(old: LeafBlock, new: LeafBlock)
    /// Block was modified — same position, different content.
    case modified(old: LeafBlock, new: LeafBlock)
    /// Block was inserted in the new document.
    case inserted(new: LeafBlock)
    /// Block was deleted from the old document.
    case deleted(old: LeafBlock)
}

// MARK: - LeafBlock

/// A leaf-level block extracted from a Markdown AST, carrying its
/// source text fingerprint and AST node reference.
struct LeafBlock {
    /// The AST node for this block.
    let markup: Markup
    /// Hash of the source text within this block's range.
    let fingerprint: String
    /// 1-based line number of the block's start in the source.
    let sourceLine: Int
    /// The source text of this block (substring of the original markdown).
    let sourceText: String
}

// MARK: - Leaf block collection

extension BlockMatcher {
    /// Flattens an AST into an ordered list of leaf blocks.
    static func collectLeafBlocks(from parsed: ParsedMarkdown) -> [LeafBlock] {
        var collector = LeafBlockCollector(markdown: parsed.markdown)
        collector.visit(parsed.document)
        return collector.blocks
    }
}

/// Walks a Markdown AST and collects leaf blocks: paragraphs, headings,
/// code blocks, list items, table rows, blockquote paragraphs, thematic
/// breaks, and HTML blocks.
private struct LeafBlockCollector: MarkupWalker {
    let markdown: String
    private let lines: [Substring]
    var blocks: [LeafBlock] = []

    init(markdown: String) {
        self.markdown = markdown
        self.lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        appendBlock(paragraph)
    }

    mutating func visitHeading(_ heading: Heading) {
        appendBlock(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        appendBlock(codeBlock)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        let hasNestedList = listItem.children.contains {
            $0 is UnorderedList || $0 is OrderedList
        }
        if hasNestedList {
            // The item contains a nested list. Append the item's own
            // paragraph as a leaf block, then visit only the nested
            // list(s) — not the full item — so inner items become
            // separate leaf blocks without double-counting the paragraph.
            if let para = listItem.children.first(where: { $0 is Paragraph }) {
                appendBlock(para)
            }
            for child in listItem.children
                where child is UnorderedList || child is OrderedList {
                visit(child)
            }
        } else {
            appendBlock(listItem)
            // No descending — the list item is the leaf unit for diffing.
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        // Descend to find paragraphs inside the blockquote.
        descendInto(blockQuote)
    }

    mutating func visitTable(_ table: Table) {
        // Descend to find rows.
        descendInto(table)
    }

    mutating func visitTableHead(_ head: Table.Head) {
        // Table head is a row-like structure.
        appendBlock(head)
    }

    mutating func visitTableRow(_ row: Table.Row) {
        appendBlock(row)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        appendBlock(thematicBreak)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        appendBlock(html)
    }

    // MARK: - Helpers

    private mutating func appendBlock(_ node: Markup) {
        let sourceText = extractSourceText(for: node)
        let line = node.range?.lowerBound.line ?? 0
        blocks.append(LeafBlock(
            markup: node, fingerprint: sourceText,
            sourceLine: line, sourceText: sourceText
        ))
    }

    /// Extracts the source text for a node using its source range.
    private func extractSourceText(for node: Markup) -> String {
        guard let range = node.range else { return "" }
        let startLine = range.lowerBound.line  // 1-based
        let endLine = range.upperBound.line    // 1-based
        guard startLine >= 1, endLine >= startLine,
              startLine <= lines.count else { return "" }

        let clampedEnd = min(endLine, lines.count)
        let slice = lines[(startLine - 1)..<clampedEnd]
        return slice.joined(separator: "\n")
    }
}

// MARK: - Result builder

private extension BlockMatcher {
    /// Builds the result array in new-document order, interleaving
    /// deletions at their correct positions.
    ///
    /// Uses an old-index cursor: before emitting each surviving new
    /// block, drain any deleted old blocks between the previous cursor
    /// position and the old index of the current block.
    static func buildResult(
        oldBlocks: [LeafBlock],
        newBlocks: [LeafBlock],
        removedOld: Set<Int>,
        insertedNew: Set<Int>,
        modOldForNew: [Int: Int],
        unchangedOldForNew: [Int: Int]
    ) -> [BlockMatch] {
        var result: [BlockMatch] = []
        var oldCursor = 0  // next old index to consider for deletions

        /// Emit `.deleted` for every removed old index in [oldCursor, upTo).
        func drainDeletions(upTo limit: Int) {
            while oldCursor < limit {
                if removedOld.contains(oldCursor) {
                    result.append(.deleted(old: oldBlocks[oldCursor]))
                }
                oldCursor += 1
            }
        }

        for ni in 0..<newBlocks.count {
            if let oi = modOldForNew[ni] {
                drainDeletions(upTo: oi)
                result.append(.modified(
                    old: oldBlocks[oi], new: newBlocks[ni]))
                oldCursor = oi + 1
            } else if insertedNew.contains(ni) {
                result.append(.inserted(new: newBlocks[ni]))
            } else if let oi = unchangedOldForNew[ni] {
                drainDeletions(upTo: oi)
                result.append(.unchanged(
                    old: oldBlocks[oi], new: newBlocks[ni]))
                oldCursor = oi + 1
            }
        }

        // Trailing deletions — remaining removed old blocks.
        drainDeletions(upTo: oldBlocks.count)

        return result
    }
}
