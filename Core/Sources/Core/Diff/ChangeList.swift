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

        for block in newBlocks {
            let node = block.markup

            // Emit true deletions that precede this block (skip
            // modification old-versions — those are part of the
            // modification entry, not separate sidebar items).
            for del in context.precedingDeletions(before: node)
                where !del.isModificationOld {
                changes.append(DocumentChange(
                    id: del.changeID,
                    type: .deletion,
                    summary: del.summary,
                    sourceLine: block.sourceLine
                ))
            }

            // Emit this block's own change (if any).
            if let annotation = context.annotation(for: node),
               let id = context.changeID(for: node) {
                let type: ChangeType = annotation == .inserted
                    ? .insertion : .modification
                changes.append(DocumentChange(
                    id: id,
                    type: type,
                    summary: DiffContext.blockSummary(block),
                    sourceLine: block.sourceLine
                ))
            }

            lastSurvivingLine = block.sourceLine
        }

        // Trailing deletions — no following block.
        for del in context.trailingDeletions() where !del.isModificationOld {
            changes.append(DocumentChange(
                id: del.changeID,
                type: .deletion,
                summary: del.summary,
                sourceLine: lastSurvivingLine
            ))
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
}

/// The type of a document change.
public enum ChangeType: Sendable, Equatable {
    case insertion
    case deletion
    case modification
}
