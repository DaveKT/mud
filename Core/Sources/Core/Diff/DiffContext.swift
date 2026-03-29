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

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                flushDeletions(before: new.markup)
                lastWasChange = false

            case .inserted(let new):
                flushDeletions(before: new.markup)
                let id = nextChangeID()
                if let key = sourceKey(for: new.markup) {
                    annotations[key] = AnnotationEntry(
                        annotation: .inserted, changeID: id)
                }
                changeEntries.append(ChangeEntry(
                    changeID: id, isDeletion: false,
                    isConsecutive: lastWasChange))
                lastWasChange = true

            case .deleted(let old):
                let id = nextChangeID()
                pendingDeletions.append(Self.renderedDeletion(
                    for: old, changeID: id))
                changeEntries.append(ChangeEntry(
                    changeID: id, isDeletion: true,
                    isConsecutive: lastWasChange))
                lastWasChange = true
            }
        }

        trailing = pendingDeletions

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
    static func blockSummary(_ block: LeafBlock) -> String {
        let raw: String
        if let inline = block.markup as? (any InlineContainer) {
            raw = inline.plainText
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
