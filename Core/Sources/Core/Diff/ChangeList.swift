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
                && context.precedingDeletions(before: node).isEmpty

            if isUnchanged {
                sawUnchangedSinceLastChange = true
                lastSurvivingLine = block.sourceLine
                continue
            }

            // Emit deletions that precede this block.
            for del in context.precedingDeletions(before: node) {
                let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
                let info = context.groupInfo(for: del.changeID)
                changes.append(DocumentChange(
                    id: del.changeID,
                    type: .deletion,
                    summary: del.summary,
                    sourceLine: block.sourceLine,
                    isConsecutive: consecutive,
                    groupID: info?.groupID ?? "",
                    groupIndex: info?.groupIndex ?? 0
                ))
                sawUnchangedSinceLastChange = false
            }

            // The block itself is unchanged — it breaks the
            // consecutive run even though it hosted deletions.
            if context.annotation(for: node) == nil {
                sawUnchangedSinceLastChange = true
                lastSurvivingLine = block.sourceLine
                continue
            }

            // Emit this block's own change.
            if let id = context.changeID(for: node) {
                let type: ChangeType = .insertion
                let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
                let info = context.groupInfo(for: id)
                changes.append(DocumentChange(
                    id: id,
                    type: type,
                    summary: DiffContext.blockSummary(block),
                    sourceLine: block.sourceLine,
                    isConsecutive: consecutive,
                    groupID: info?.groupID ?? "",
                    groupIndex: info?.groupIndex ?? 0
                ))
                sawUnchangedSinceLastChange = false
            }

            lastSurvivingLine = block.sourceLine
        }

        // Trailing deletions — no following block.
        for del in context.trailingDeletions() {
            let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
            let info = context.groupInfo(for: del.changeID)
            changes.append(DocumentChange(
                id: del.changeID,
                type: .deletion,
                summary: del.summary,
                sourceLine: lastSurvivingLine,
                isConsecutive: consecutive,
                groupID: info?.groupID ?? "",
                groupIndex: info?.groupIndex ?? 0
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
    /// The group this change belongs to (e.g. "group-1").
    public let groupID: String
    /// 1-based group index, used for badge numbering.
    public let groupIndex: Int
}

/// The type of a document change.
public enum ChangeType: Sendable, Equatable {
    case insertion
    case deletion
}
