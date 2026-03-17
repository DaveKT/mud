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

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                flushDeletions(before: new.markup)

            case .inserted(let new):
                flushDeletions(before: new.markup)
                let id = nextChangeID()
                if let key = sourceKey(for: new.markup) {
                    annotations[key] = AnnotationEntry(
                        annotation: .inserted, changeID: id)
                }

            case .deleted(let old):
                let id = nextChangeID()
                pendingDeletions.append(Self.renderedDeletion(
                    for: old, changeID: id))
            }
        }

        trailing = pendingDeletions

        self.annotations = annotations
        self.precedingDeletionMap = precedingMap
        self._trailingDeletions = trailing
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
}

// MARK: - Block annotation

/// The type of change for a block in the new document.
enum BlockAnnotation: Equatable {
    case inserted
}

// MARK: - Rendered deletion

/// A pre-rendered deleted block, ready for injection into the HTML output.
struct RenderedDeletion {
    /// The HTML content of the deleted block.
    let html: String
    /// The change ID matching the sidebar entry.
    let changeID: String
    /// Plain-text summary of the deleted content (for the sidebar).
    let summary: String
    /// When non-nil, the deletion must be wrapped in this structural
    /// HTML tag (e.g. `"li"`) instead of the default `<del>`. This
    /// avoids invalid nesting like `<del><li>…</li></del>` inside a
    /// list. The `html` field contains only the inner content (no
    /// wrapper tag).
    let wrapperTag: String?
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
    /// Builds a `RenderedDeletion` for a leaf block: renders HTML and
    /// extracts a plain-text summary.
    static func renderedDeletion(
        for block: LeafBlock, changeID: String
    ) -> RenderedDeletion {
        var visitor = UpHTMLVisitor()
        let isListItem = block.markup is ListItem
        if isListItem {
            // Render only the children so the HTML contains inner
            // content without a <li> wrapper. The rendering layer
            // wraps this in a <li> carrying the deletion class,
            // avoiding invalid <del><li>…</li></del> nesting.
            for child in block.markup.children {
                visitor.visit(child)
            }
        } else {
            visitor.visit(block.markup)
        }
        return RenderedDeletion(
            html: visitor.result,
            changeID: changeID,
            summary: blockSummary(block),
            wrapperTag: isListItem ? "li" : nil
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

