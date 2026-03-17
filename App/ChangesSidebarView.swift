import SwiftUI
import MudCore

struct ChangesSidebarView: View {
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared
    var onSelectChange: ([String]) -> Void

    var body: some View {
        if !appState.trackChangesEnabled {
            disabledState
        } else if changeTracker.isPaused {
            pausedState
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
        VStack(spacing: 0) {
            statusBar
            List(groups, selection: $selectedGroupID) { group in
                ChangeGroupRow(group: group)
                    .tag(group.id)
            }
            .listStyle(.sidebar)
            .onChange(of: selectedGroupID) { _, newValue in
                guard let id = newValue,
                      let group = groups.first(where: { $0.id == id })
                else { return }
                changeTracker.selectedChangeID = group.changeIDs.first
                onSelectChange(group.changeIDs)
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Accept") {
                changeTracker.accept()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusText: String {
        let count = changeTracker.changes.count
        let noun = count == 1 ? "change" : "changes"
        if let time = formattedTimestamp {
            return "\(count) \(noun) since \(time)"
        }
        return "\(count) \(noun)"
    }

    // MARK: - Empty state (0 changes, not paused)

    private var emptyState: some View {
        VStack(spacing: 0) {
            emptyStatusBar
            Spacer()
        }
    }

    private var emptyStatusBar: some View {
        HStack {
            Text(emptyStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Pause") {
                changeTracker.isPaused = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyStatusText: String {
        if let time = formattedTimestamp {
            return "0 changes since \(time)"
        }
        return "0 changes"
    }

    // MARK: - Disabled state (global toggle off)

    private var disabledState: some View {
        VStack {
            ContentUnavailableView(
                "Changes Hidden",
                systemImage: "eye.slash",
                description: Text("Enable in\nMud > Settings > General.")
            )
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Paused state (per-document)

    private var pausedState: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Track Changes is paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Resume") {
                    changeTracker.isPaused = false
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Spacer()
        }
    }

    // MARK: - Timestamp formatting

    private var formattedTimestamp: String? {
        guard let date = changeTracker.activeWaypointTimestamp else {
            return nil
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
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
    /// Summary text from the first change.
    let summary: String
    /// Number of individual changes in this group.
    let count: Int

    static func build(from changes: [DocumentChange]) -> [ChangeGroup] {
        guard let first = changes.first else { return [] }

        var groups: [ChangeGroup] = []
        var ids = [first.id]
        var types = [first.type]
        var summary = first.summary

        for change in changes.dropFirst() {
            if change.isConsecutive {
                ids.append(change.id)
                types.append(change.type)
            } else {
                groups.append(makeGroup(ids: ids, types: types, summary: summary))
                ids = [change.id]
                types = [change.type]
                summary = change.summary
            }
        }
        groups.append(makeGroup(ids: ids, types: types, summary: summary))
        return groups
    }

    private static func makeGroup(
        ids: [String], types: [ChangeType], summary: String
    ) -> ChangeGroup {
        let hasInsertions = types.contains(.insertion)
        let hasDeletions = types.contains(.deletion)
        let isMixed = hasInsertions && hasDeletions
        let type: ChangeType = hasInsertions ? .insertion : .deletion
        return ChangeGroup(
            id: ids[0], changeIDs: ids, type: type,
            isMixed: isMixed, summary: summary, count: ids.count)
    }
}

// MARK: - Change group row

private struct ChangeGroupRow: View {
    let group: ChangeGroup

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(group.summary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if group.count > 1 {
                    Text("(\(group.count))")
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            groupIcon
        }
    }

    private var groupIcon: some View {
        let (name, color) = iconInfo
        return Image(systemName: name)
            .foregroundStyle(color)
    }

    private var iconInfo: (String, Color) {
        if group.isMixed { return ("pencil.circle", .blue) }
        switch group.type {
        case .insertion: return ("plus.circle", .green)
        case .deletion:  return ("minus.circle", .red)
        }
    }
}
