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

            let codeDiff = context.codeBlockDiff(for: node)
            let isUnchanged = context.annotation(for: node) == nil
                && context.precedingDeletions(before: node).isEmpty
                && codeDiff == nil

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
                    groupIndex: info?.groupIndex ?? 0,
                    isMixed: info?.isMixed ?? false
                ))
                sawUnchangedSinceLastChange = false
            }

            // Check for code block with line-level diff.
            if let codeDiff {
                emitCodeBlockChanges(
                    codeDiff, sourceLine: block.sourceLine,
                    changes: &changes,
                    sawUnchangedSinceLastChange: &sawUnchangedSinceLastChange)
                lastSurvivingLine = block.sourceLine
                continue
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
                    groupIndex: info?.groupIndex ?? 0,
                    isMixed: info?.isMixed ?? false
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
                groupIndex: info?.groupIndex ?? 0,
                isMixed: info?.isMixed ?? false
            ))
            sawUnchangedSinceLastChange = false
        }

        return changes
    }

    /// Emits `DocumentChange` entries for each line group in a
    /// code block diff.
    private static func emitCodeBlockChanges(
        _ codeDiff: CodeBlockDiff, sourceLine: Int,
        changes: inout [DocumentChange],
        sawUnchangedSinceLastChange: inout Bool
    ) {
        // Collect line groups. Each group shares a change ID and
        // group ID; we emit one DocumentChange per group.
        var currentGroupID: String?
        var currentChangeID: String?
        var currentGroupIndex: Int = 0
        var hasDel = false
        var hasIns = false
        var summaryLine: String?

        func flushGroup() {
            guard let changeID = currentChangeID,
                  let groupID = currentGroupID
            else { return }
            let type: ChangeType
            if hasDel && hasIns {
                // Mixed — emit as insertion (the visible part).
                type = .insertion
            } else if hasDel {
                type = .deletion
            } else {
                type = .insertion
            }
            let consecutive = !changes.isEmpty && !sawUnchangedSinceLastChange
            changes.append(DocumentChange(
                id: changeID,
                type: type,
                summary: summaryLine ?? "",
                sourceLine: sourceLine,
                isConsecutive: consecutive,
                groupID: groupID,
                groupIndex: currentGroupIndex,
                isMixed: hasDel && hasIns
            ))
            sawUnchangedSinceLastChange = false
        }

        for line in codeDiff.lines {
            guard let changeID = line.changeID,
                  let groupID = line.groupID
            else {
                // Unchanged line — breaks consecutive run.
                if currentChangeID != nil {
                    flushGroup()
                    currentChangeID = nil
                    currentGroupID = nil
                    hasDel = false
                    hasIns = false
                    summaryLine = nil
                }
                sawUnchangedSinceLastChange = true
                continue
            }

            if changeID != currentChangeID {
                // New group.
                if currentChangeID != nil { flushGroup() }
                currentChangeID = changeID
                currentGroupID = groupID
                currentGroupIndex = line.groupIndex ?? 0
                hasDel = false
                hasIns = false
                summaryLine = nil
            }

            switch line.annotation {
            case .deleted:
                hasDel = true
                if summaryLine == nil {
                    summaryLine = summaryFromHTML(line.highlightedHTML)
                }
            case .inserted:
                hasIns = true
                if summaryLine == nil {
                    summaryLine = summaryFromHTML(line.highlightedHTML)
                }
            case .unchanged:
                break
            }
        }

        // Flush last group.
        if currentChangeID != nil { flushGroup() }
    }

    /// Strips HTML tags and truncates to ~60 characters.
    private static func summaryFromHTML(_ html: String) -> String {
        let text = html
            .replacingOccurrences(
                of: "<[^>]+>", with: "",
                options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard text.count > 60 else { return text }
        let prefix = text.prefix(60)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
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
    /// True when the group contains both deletions and insertions
    /// (from DiffContext), even if only one type is emitted as a
    /// DocumentChange (e.g. mermaid replacements suppress the deletion).
    public let isMixed: Bool
}

/// The type of a document change.
public enum ChangeType: Sendable, Equatable {
    case insertion
    case deletion
}
