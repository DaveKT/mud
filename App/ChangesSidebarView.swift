import SwiftUI
import MudCore

struct ChangesSidebarView: View {
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared
    var onSelectChange: ([String]) -> Void

    var body: some View {
        if !appState.trackChangesEnabled {
            disabledState
        } else if changeTracker.changes.isEmpty {
            emptyState
        } else {
            changeList
        }
    }

    // MARK: - Grouping

    private var groups: [ChangeGroup] {
        ChangeGroup.build(from: changeTracker.changes)
    }

    // MARK: - Change list

    @State private var selectedGroupID: String?

    private var changeList: some View {
        List(groups, selection: $selectedGroupID) { group in
            ChangeGroupRow(group: group)
                .tag(group.id)
        }
        .listStyle(.sidebar)
        .background(ReselectMonitor(
            selection: selectedGroupID,
            onReselect: { id in
                guard let group = groups.first(
                    where: { $0.id == id }
                ) else { return }
                onSelectChange(group.changeIDs)
            }
        ))
        .onChange(of: selectedGroupID) { _, newValue in
            if let id = newValue,
               let group = groups.first(where: { $0.id == id }) {
                changeTracker.selectedChangeID = group.changeIDs.first
                onSelectChange(group.changeIDs)
            } else {
                changeTracker.selectedChangeID = nil
                onSelectChange([])
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            ContentUnavailableView(
                "No Changes",
                systemImage: "checkmark.circle",
                description: Text("Changes will appear when the file is modified.")
            )
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Disabled state (global toggle off)

    private var disabledState: some View {
        VStack {
            ContentUnavailableView {
                Label("Changes Hidden", systemImage: "eye.slash")
            } description: {
                HStack(spacing: 0) {
                    Button("Show changes") {
                        appState.trackChangesEnabled = true
                    }
                    .buttonStyle(.link)
                    Text(" in document.")
                }
            }
            Spacer()
        }
        .padding(.top, 16)
    }

}

// MARK: - Change group

/// A group of consecutive changes with no unchanged block between them.
struct ChangeGroup: Identifiable {
    /// The first change's ID (used as the group's stable identity).
    let id: String
    /// All change IDs in this group.
    let changeIDs: [String]
    /// The primary change type in the group.
    let type: ChangeType
    /// True when the group contains both insertions and deletions.
    let isMixed: Bool
    /// 1-based group index, matching the overlay badge number.
    let groupIndex: Int
    /// Per-change summaries and types, for multi-line display.
    let members: [MemberInfo]

    /// Number of individual changes in this group.
    var count: Int { members.count }

    /// A single change within a group.
    struct MemberInfo {
        let type: ChangeType
        let summary: String
    }

    static func build(from changes: [DocumentChange]) -> [ChangeGroup] {
        // Group by the pre-computed groupID from DiffContext.
        // Preserve document order (first occurrence of each groupID).
        var order: [String] = []
        var buckets: [String: [DocumentChange]] = [:]

        for change in changes {
            if buckets[change.groupID] == nil {
                order.append(change.groupID)
            }
            buckets[change.groupID, default: []].append(change)
        }

        return order.compactMap { gid in
            guard let members = buckets[gid], let first = members.first
            else { return nil }
            let hasIns = members.contains { $0.type == .insertion }
            let hasDel = members.contains { $0.type == .deletion }
            let isMixed = (hasIns && hasDel)
                || members.contains(where: \.isMixed)
            return ChangeGroup(
                id: gid,
                changeIDs: members.map(\.id),
                type: hasIns ? .insertion : .deletion,
                isMixed: isMixed,
                groupIndex: first.groupIndex,
                members: members.map {
                    MemberInfo(type: $0.type, summary: $0.summary)
                }
            )
        }
    }
}

// MARK: - Change group row

private struct ChangeGroupRow: View {
    let group: ChangeGroup
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            groupBadge
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(
                    Array(displayLines.enumerated()), id: \.offset
                ) { _, line in
                    lineView(line)
                }
            }
        }
    }

    // MARK: - Display lines

    /// A line in the condensed preview: either a member's summary
    /// or a "and N more" overflow note.
    private enum DisplayLine {
        case member(ChangeGroup.MemberInfo)
        case overflow(count: Int, type: ChangeType)
    }

    /// Condenses members into display lines, capping each
    /// consecutive run of the same type at 2 lines (3 if that
    /// would leave exactly 1 overflowed).
    private var displayLines: [DisplayLine] {
        var lines: [DisplayLine] = []
        var i = 0
        let members = group.members
        while i < members.count {
            // Find the end of this consecutive run of the same type.
            let runType = members[i].type
            var runEnd = i + 1
            while runEnd < members.count
                    && members[runEnd].type == runType {
                runEnd += 1
            }
            let runLength = runEnd - i

            if runLength <= 3 {
                // Show all members in the run.
                for j in i..<runEnd {
                    lines.append(.member(members[j]))
                }
            } else {
                // Show first 2, then overflow summary.
                lines.append(.member(members[i]))
                lines.append(.member(members[i + 1]))
                lines.append(.overflow(
                    count: runLength - 2, type: runType))
            }
            i = runEnd
        }
        return lines
    }

    // MARK: - Line views

    @ViewBuilder
    private func lineView(_ line: DisplayLine) -> some View {
        switch line {
        case .member(let member):
            memberLine(member)
        case .overflow(let count, let type):
            overflowLine(count: count, type: type)
        }
    }

    private func memberLine(_ member: ChangeGroup.MemberInfo) -> some View {
        HStack(spacing: 3) {
            Text(member.type == .insertion ? "+" : "−")
                .fontWeight(.bold)
                .foregroundStyle(
                    member.type == .insertion
                        ? changeColor("change-ins")
                        : changeColor("change-del")
                )
                .frame(width: 10, alignment: .center)
            Text(member.summary.isEmpty ? "—" : member.summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func overflowLine(
        count: Int, type: ChangeType
    ) -> some View {
        let noun = type == .insertion
            ? (count == 1 ? "insertion" : "insertions")
            : (count == 1 ? "deletion" : "deletions")
        return Text("and \(count) more \(noun)")
            .font(.callout)
            .italic()
            .foregroundStyle(.tertiary)
            .padding(.leading, 13)
    }

    private var groupBadge: some View {
        Text("\(group.groupIndex)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(
                appState.lighting.isDark() ? .black : .white
            )
            .frame(minWidth: 18, minHeight: 18)
            .background(badgeColor, in: Circle())
    }

    private var badgeColor: Color {
        if group.isMixed { return changeColor("change-mix") }
        switch group.type {
        case .insertion: return changeColor("change-ins")
        case .deletion:  return changeColor("change-del")
        }
    }

    private func changeColor(_ key: String) -> Color {
        let colors = Color.cssProperties(
            from: HTMLTemplate.changesCSS,
            dark: appState.lighting.isDark()
        )
        return Color(cssHex: colors[key])
    }
}
