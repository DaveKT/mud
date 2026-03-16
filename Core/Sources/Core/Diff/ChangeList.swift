import Markdown

/// Extracts a flat list of document changes from a `DiffContext`,
/// suitable for populating the sidebar change list.
enum ChangeList {
    /// Computes a list of changes between old and new documents.
    static func computeChanges(
        old: ParsedMarkdown, new: ParsedMarkdown
    ) -> [DocumentChange] {
        let context = DiffContext(old: old, new: new)
        let newBlocks = BlockMatcher.collectLeafBlocks(from: new)

        var changes: [DocumentChange] = []
        var lastSurvivingLine = 1
        var sawUnchangedSinceLastChange = true

        for block in newBlocks {
            let node = block.markup

            let isUnchanged = context.annotation(for: node) == nil
                && context.precedingDeletions(before: node)
                    .filter({ !$0.isModificationOld }).isEmpty

            if isUnchanged {
                sawUnchangedSinceLastChange = true
                lastSurvivingLine = block.sourceLine
                continue
            }

            // Emit true deletions that precede this block (skip
            // modification old-versions — those are part of the
            // modification entry, not separate sidebar items).
            for del in context.precedingDeletions(before: node)
                where !del.isModificationOld {
                let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
                changes.append(DocumentChange(
                    id: del.changeID,
                    type: .deletion,
                    summary: del.summary,
                    sourceLine: block.sourceLine,
                    isConsecutive: consecutive
                ))
                sawUnchangedSinceLastChange = false
            }

            // Emit this block's own change (if any).
            if let annotation = context.annotation(for: node),
               let id = context.changeID(for: node) {
                let type: ChangeType = annotation == .inserted
                    ? .insertion : .modification
                let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
                changes.append(DocumentChange(
                    id: id,
                    type: type,
                    summary: DiffContext.blockSummary(block),
                    sourceLine: block.sourceLine,
                    isConsecutive: consecutive
                ))
                sawUnchangedSinceLastChange = false
            }

            lastSurvivingLine = block.sourceLine
        }

        // Trailing deletions — no following block.
        for del in context.trailingDeletions() where !del.isModificationOld {
            let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
            changes.append(DocumentChange(
                id: del.changeID,
                type: .deletion,
                summary: del.summary,
                sourceLine: lastSurvivingLine,
                isConsecutive: consecutive
            ))
            sawUnchangedSinceLastChange = false
        }

        return changes
    }
}

// MARK: - DocumentChange

/// A single change entry for the sidebar list.
public struct DocumentChange: Identifiable, Sendable {
    public let id: String
    public let type: ChangeType
    public let summary: String
    public let sourceLine: Int
    /// True when this change immediately follows the previous change
    /// with no unchanged block between them. Always false for the first
    /// change. Used by the sidebar to group consecutive changes.
    public let isConsecutive: Bool
}

/// The type of a document change.
public enum ChangeType: Sendable, Equatable {
    case insertion
    case deletion
    case modification
}
