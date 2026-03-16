import SwiftUI
import MudCore

struct ChangesSidebarView: View {
    @ObservedObject var changeTracker: ChangeTracker
    var onSelectChange: (String) -> Void

    var body: some View {
        if changeTracker.changes.isEmpty {
            emptyState
        } else {
            changeList
        }
    }

    // MARK: - Change list

    private var changeList: some View {
        VStack(spacing: 0) {
            statusBar
            List(changeTracker.changes, selection: $changeTracker.selectedChangeID) { change in
                ChangeRow(change: change)
                    .tag(change.id)
            }
            .listStyle(.sidebar)
            .onChange(of: changeTracker.selectedChangeID) { _, newValue in
                guard let id = newValue else { return }
                onSelectChange(id)
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
                acceptChanges()
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            ContentUnavailableView(
                "No Changes",
                systemImage: "checkmark.circle",
                description: Text(emptyDescription)
            )
            Spacer()
        }
        .padding(.top, 16)
    }

    private var emptyDescription: String {
        if let time = formattedTimestamp {
            return "No changes since \(time)"
        }
        return "This document has no changes."
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

    // MARK: - Actions

    private func acceptChanges() {
        changeTracker.accept()
    }
}

// MARK: - Change Row

private struct ChangeRow: View {
    let change: DocumentChange

    var body: some View {
        Label {
            Text(change.summary)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            changeIcon
        }
    }

    private var changeIcon: some View {
        let (name, color) = iconInfo
        return Image(systemName: name)
            .foregroundStyle(color)
    }

    private var iconInfo: (String, Color) {
        switch change.type {
        case .insertion:    return ("plus.circle", .green)
        case .deletion:     return ("minus.circle", .red)
        case .modification: return ("pencil.circle", .blue)
        }
    }
}
