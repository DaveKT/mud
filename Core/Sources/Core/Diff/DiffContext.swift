import Markdown

/// Bridge between the diff engine and the rendering visitors.
///
/// Built from two `ParsedMarkdown` values. Provides annotation lookups
/// for AST nodes (used during rendering) and pre-rendered HTML for
/// deleted blocks.
struct DiffContext {
    private let annotations: [SourceKey: AnnotationEntry]
    private let precedingDeletionMap: [SourceKey: [RenderedDeletion]]
    private let _trailingDeletions: [RenderedDeletion]
    private let _groupMap: [String: GroupInfo]
    private let _pairMap: [String: String]

    /// Creates a diff context by matching blocks between old and new documents.
    init(old: ParsedMarkdown, new: ParsedMarkdown) {
        let matches = BlockMatcher.match(old: old, new: new)

        var annotations: [SourceKey: AnnotationEntry] = [:]
        var precedingMap: [SourceKey: [RenderedDeletion]] = [:]
        var trailing: [RenderedDeletion] = []

        // Assign change IDs and build lookup tables.
        var changeCounter = 0

        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        // Collect deletions and modifications in document order so we can
        // attach them to the correct following block.
        var pendingDeletions: [RenderedDeletion] = []

        /// Flush accumulated deletions into the preceding-deletion map
        /// for the given new-document node.
        func flushDeletions(before node: Markup) {
            guard !pendingDeletions.isEmpty,
                  let key = sourceKey(for: node) else { return }
            precedingMap[key] = pendingDeletions
            pendingDeletions.removeAll()
        }

        // Track change IDs in document order for the grouping pass.
        struct ChangeEntry {
            let changeID: String
            let isDeletion: Bool
            let isConsecutive: Bool
        }
        var changeEntries: [ChangeEntry] = []
        var lastWasChange = false

        // Track deletions and insertions per gap for positional pairing.
        // Within each gap, buildResult emits all deletions before all
        // insertions. The i-th deletion pairs with the i-th insertion.
        struct GapBlock {
            let changeID: String
            let block: LeafBlock
        }
        var gapDeletions: [GapBlock] = []
        var gapInsertions: [GapBlock] = []
        var pairMap: [String: String] = [:]
        var wordSpanMap: [String: [WordSpan]] = [:]
        var wordSpanDeletionHTML: [String: String] = [:]

        /// Pair deletions with insertions in the current gap and compute
        /// word spans for pairs with matching inline structure.
        func processGap() {
            for (del, ins) in zip(gapDeletions, gapInsertions) {
                pairMap[del.changeID] = ins.changeID
                pairMap[ins.changeID] = del.changeID

                // Compute word spans for pairs with compatible structure.
                guard WordDiff.hasMatchingStructure(
                    del.block.markup, ins.block.markup
                ) else { continue }

                guard let oldInline = del.block.markup
                        as? (any InlineContainer),
                      let newInline = ins.block.markup
                        as? (any InlineContainer)
                else { continue }

                let result = WordDiff.diff(
                    old: oldInline.plainText,
                    new: newInline.plainText)
                if !result.forNew.isEmpty {
                    wordSpanMap[del.changeID] = result.forOld
                    wordSpanMap[ins.changeID] = result.forNew
                    // Re-render the deletion with word-level markers
                    // for the red block (using old-side spans).
                    wordSpanDeletionHTML[del.changeID] =
                        UpHTMLVisitor.renderWithWordSpans(
                            del.block.markup, spans: result.forOld,
                            role: .deletion)
                }
            }
            gapDeletions.removeAll()
            gapInsertions.removeAll()
        }

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                flushDeletions(before: new.markup)
                processGap()
                lastWasChange = false

            case .inserted(let new):
                flushDeletions(before: new.markup)
                let id = nextChangeID()
                if let key = sourceKey(for: new.markup) {
                    annotations[key] = AnnotationEntry(
                        annotation: .inserted, changeID: id)
                }
                gapInsertions.append(GapBlock(
                    changeID: id, block: new))
                changeEntries.append(ChangeEntry(
                    changeID: id, isDeletion: false,
                    isConsecutive: lastWasChange))
                lastWasChange = true

            case .deleted(let old):
                let id = nextChangeID()
                pendingDeletions.append(Self.renderedDeletion(
                    for: old, changeID: id))
                gapDeletions.append(GapBlock(
                    changeID: id, block: old))
                changeEntries.append(ChangeEntry(
                    changeID: id, isDeletion: true,
                    isConsecutive: lastWasChange))
                lastWasChange = true
            }
        }

        trailing = pendingDeletions
        processGap()

        // Attach word spans to paired annotations and deletions.
        if !wordSpanMap.isEmpty {
            for (key, entry) in annotations
                where wordSpanMap[entry.changeID] != nil {
                annotations[key] = AnnotationEntry(
                    annotation: entry.annotation,
                    changeID: entry.changeID,
                    wordSpans: wordSpanMap[entry.changeID])
            }

            func applyWordSpans(
                _ deletions: [RenderedDeletion]
            ) -> [RenderedDeletion] {
                deletions.map { del in
                    guard let spans = wordSpanMap[del.changeID]
                    else { return del }
                    return RenderedDeletion(
                        html: wordSpanDeletionHTML[del.changeID]
                            ?? del.html,
                        changeID: del.changeID,
                        summary: del.summary, tag: del.tag,
                        wordSpans: spans)
                }
            }

            for (key, deletions) in precedingMap {
                precedingMap[key] = applyWordSpans(deletions)
            }
            trailing = applyWordSpans(trailing)
        }

        // Grouping pass: break change entries into groups at
        // non-consecutive boundaries.
        var groupMap: [String: GroupInfo] = [:]
        var groupCounter = 0
        var currentGroup: [ChangeEntry] = []

        func finalizeGroup() {
            guard !currentGroup.isEmpty else { return }
            groupCounter += 1
            let groupID = "group-\(groupCounter)"
            let hasDel = currentGroup.contains { $0.isDeletion }
            let hasIns = currentGroup.contains { !$0.isDeletion }
            let isMixed = hasDel && hasIns
            let count = currentGroup.count
            for (i, entry) in currentGroup.enumerated() {
                let pos: GroupPos
                if count == 1 {
                    pos = .sole
                } else if i == 0 {
                    pos = .first
                } else if i == count - 1 {
                    pos = .last
                } else {
                    pos = .middle
                }
                groupMap[entry.changeID] = GroupInfo(
                    groupID: groupID, groupPos: pos,
                    groupIndex: groupCounter, isMixed: isMixed)
            }
            currentGroup.removeAll()
        }

        for entry in changeEntries {
            if !entry.isConsecutive && !currentGroup.isEmpty {
                finalizeGroup()
            }
            currentGroup.append(entry)
        }
        finalizeGroup()

        self.annotations = annotations
        self.precedingDeletionMap = precedingMap
        self._trailingDeletions = trailing
        self._groupMap = groupMap
        self._pairMap = pairMap
    }

    // MARK: - Public API

    /// Returns the annotation for a block in the new AST, or `nil` if unchanged.
    func annotation(for node: Markup) -> BlockAnnotation? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.annotation
    }

    /// Returns the change ID for a block in the new AST, or `nil` if unchanged.
    func changeID(for node: Markup) -> String? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.changeID
    }

    /// Returns pre-rendered deleted blocks that should appear before
    /// the given node.
    func precedingDeletions(before node: Markup) -> [RenderedDeletion] {
        guard let key = sourceKey(for: node) else { return [] }
        return precedingDeletionMap[key] ?? []
    }

    /// Returns pre-rendered deleted blocks that appear after the last
    /// surviving block (or all deletions when the new document is empty).
    func trailingDeletions() -> [RenderedDeletion] {
        _trailingDeletions
    }

    /// Returns group info for a change ID, or `nil` if unknown.
    func groupInfo(for changeID: String) -> GroupInfo? {
        _groupMap[changeID]
    }

    /// Returns the change ID of the block paired with the given change ID
    /// (deletion ↔ insertion), or `nil` if the block is unpaired.
    func pairedChangeID(for changeID: String) -> String? {
        _pairMap[changeID]
    }

    /// Returns word-level diff spans for a block in the new AST,
    /// or `nil` if the block is unpaired or has divergent structure.
    func wordSpans(for node: Markup) -> [WordSpan]? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.wordSpans
    }
}

// MARK: - Block annotation

/// The type of change for a block in the new document.
enum BlockAnnotation: Equatable {
    case inserted
}

// MARK: - Group info

/// Position of a change within its group.
enum GroupPos: String {
    case first, middle, last, sole
}

/// Describes a change's membership in a consecutive group.
struct GroupInfo {
    /// The group identifier (e.g. "group-1").
    let groupID: String
    /// Position within the group.
    let groupPos: GroupPos
    /// 1-based group index, used for badge numbers.
    let groupIndex: Int
    /// True when the group contains both deletions and insertions.
    let isMixed: Bool
}

// MARK: - Rendered deletion

/// A pre-rendered deleted block, ready for injection into the HTML output.
struct RenderedDeletion {
    /// The inner HTML content of the deleted block (no outer tag).
    let html: String
    /// The change ID matching the sidebar entry.
    let changeID: String
    /// Plain-text summary of the deleted content (for the sidebar).
    let summary: String
    /// The native HTML tag for this block (e.g. "p", "li", "tr", "pre").
    let tag: String
    /// Word-level diff spans when this deletion is paired with an insertion.
    /// `nil` when unpaired or when inline structure diverges.
    let wordSpans: [WordSpan]?

    init(
        html: String, changeID: String, summary: String, tag: String,
        wordSpans: [WordSpan]? = nil
    ) {
        self.html = html
        self.changeID = changeID
        self.summary = summary
        self.tag = tag
        self.wordSpans = wordSpans
    }
}

// MARK: - Source key

/// A hashable key derived from a Markup node's source range,
/// used to look up annotations by AST node.
private struct SourceKey: Hashable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}

private func sourceKey(for node: Markup) -> SourceKey? {
    guard let range = node.range else { return nil }
    return SourceKey(
        startLine: range.lowerBound.line,
        startColumn: range.lowerBound.column,
        endLine: range.upperBound.line,
        endColumn: range.upperBound.column
    )
}

// MARK: - Annotation entry

private struct AnnotationEntry {
    let annotation: BlockAnnotation
    let changeID: String
    let wordSpans: [WordSpan]?

    init(
        annotation: BlockAnnotation, changeID: String,
        wordSpans: [WordSpan]? = nil
    ) {
        self.annotation = annotation
        self.changeID = changeID
        self.wordSpans = wordSpans
    }
}

// MARK: - Block rendering

extension DiffContext {
    /// The native HTML tag for a leaf block.
    static func tagForBlock(_ markup: Markup) -> String {
        switch markup {
        case let h as Heading:             return "h\(h.level)"
        case is Paragraph:                 return "p"
        case is CodeBlock:                 return "pre"
        case is ListItem:                  return "li"
        case is Table.Head, is Table.Row:  return "tr"
        case is ThematicBreak:             return "hr"
        default:                           return "div"
        }
    }

    /// Builds a `RenderedDeletion` for a leaf block: renders inner HTML
    /// and extracts a plain-text summary. The `tag` field records the
    /// native element type; `html` contains only inner content.
    static func renderedDeletion(
        for block: LeafBlock, changeID: String
    ) -> RenderedDeletion {
        let markup = block.markup
        let tag = tagForBlock(markup)
        let html: String

        switch markup {
        case let cb as CodeBlock:
            html = UpHTMLVisitor.codeBlockInnerHTML(cb)
        case is ThematicBreak:
            html = ""
        case let hb as HTMLBlock:
            html = hb.rawHTML
        default:
            var visitor = UpHTMLVisitor()
            for child in markup.children { visitor.visit(child) }
            html = visitor.result
        }

        return RenderedDeletion(
            html: html, changeID: changeID,
            summary: blockSummary(block), tag: tag
        )
    }

    /// Extracts a plain-text summary (~60 chars) from a leaf block.
    ///
    /// Strips markdown syntax (list markers, code fences, emphasis) so the
    /// sidebar shows clean, readable text.
    static func blockSummary(_ block: LeafBlock) -> String {
        let raw: String
        if let inline = block.markup as? (any InlineContainer) {
            raw = inline.plainText
        } else if let codeBlock = block.markup as? CodeBlock {
            raw = codeBlock.code
                .split(separator: "\n", maxSplits: 1,
                       omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
        } else if let listItem = block.markup as? ListItem,
                  let para = listItem.children
                      .first(where: { $0 is Paragraph }) as? Paragraph {
            raw = para.plainText
        } else {
            raw = block.sourceText
        }
        let text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard text.count > 60 else { return text }
        let prefix = text.prefix(60)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
