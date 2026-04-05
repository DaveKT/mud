import SwiftUI
import MudCore

// MARK: - Changes Badge

private struct ChangesBadge: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(Color(nsColor: .controlBackgroundColor))
            .frame(minWidth: 22, minHeight: 22)
            .background(color, in: Circle())
    }
}

// MARK: - Changes Bar View

struct ChangesBar: View {
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared
    @Environment(\.controlActiveState) private var controlActiveState
    var onSelectChange: ([String]) -> Void

    private var groups: [ChangeGroup] {
        ChangeGroup.build(from: changeTracker.changes)
    }

    private var currentGroupIndex: Int? {
        guard let selectedID = changeTracker.selectedChangeID else {
            return nil
        }
        return groups.firstIndex { $0.changeIDs.contains(selectedID) }
    }

    var body: some View {
        activeBody
    }

    private var activeBody: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ChangesBadge(count: groups.count, color: badgeColor)

                Menu {
                    if let time = formattedTimestamp {
                        Text("Since \(time)")
                    }
                } label: {
                    Text(statusText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.1), in: ContainerRelativeShape())

            let hasChanges = !groups.isEmpty

            if groups.count >= 2 {
                Button("Previous Change", systemImage: "chevron.left", action: previousGroup)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
            }

            if hasChanges {
                Button("Next Change", systemImage: "chevron.right", action: nextGroup)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
            }

            if hasChanges {
                Button("Accept Changes", systemImage: "checkmark", action: changeTracker.accept)
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                    .modify { button in
                        if controlActiveState == .key {
                            button.buttonStyle(.borderedProminent)
                        } else {
                            button.buttonStyle(.bordered)
                        }
                    }
            }
        }
        .padding(8)
        .containerShape(Capsule())
        .frame(maxWidth: 320)
        .animation(.easeInOut(duration: 0.15), value: groups.count)
    }

    // MARK: - Navigation

    private func nextGroup() {
        guard !groups.isEmpty else { return }
        let nextIndex: Int
        if let current = currentGroupIndex {
            nextIndex = (current + 1) % groups.count
        } else {
            nextIndex = 0
        }
        selectGroup(at: nextIndex)
    }

    private func previousGroup() {
        guard !groups.isEmpty else { return }
        let prevIndex: Int
        if let current = currentGroupIndex {
            prevIndex = (current - 1 + groups.count) % groups.count
        } else {
            prevIndex = groups.count - 1
        }
        selectGroup(at: prevIndex)
    }

    private func selectGroup(at index: Int) {
        let group = groups[index]
        changeTracker.selectedChangeID = group.changeIDs.first
        onSelectChange(group.changeIDs)
    }

    // MARK: - Display helpers

    private var statusText: String {
        let noun = groups.count == 1 ? "change" : "changes"
        if let time = formattedTimestamp {
            return "\(noun) since \(time)"
        }
        return "\(noun)"
    }

    private var changeColors: [String: String] {
        Color.cssProperties(
            from: HTMLTemplate.changesCSS,
            dark: appState.lighting.isDark()
        )
    }

    private var badgeColor: Color {
        if groups.isEmpty {
            return .secondary.opacity(0.5)
        }
        let hasInsertions = changeTracker.changes.contains {
            $0.type == .insertion
        }
        let hasDeletions = changeTracker.changes.contains {
            $0.type == .deletion
        }
        let colors = changeColors
        if hasInsertions && hasDeletions {
            return Color(cssHex: colors["change-mix"])
        }
        if hasDeletions {
            return Color(cssHex: colors["change-del"])
        }
        return Color(cssHex: colors["change-ins"])
    }

    private var formattedTimestamp: String? {
        guard let date = changeTracker.activeWaypointTimestamp else {
            return nil
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            return formatter.string(from: date).lowercased()
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

