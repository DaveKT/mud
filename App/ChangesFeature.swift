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

    @State private var showMenu = false

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
        HStack(spacing: 8) {
            let hasChanges = !groups.isEmpty

            Button { showMenu.toggle() } label: {
                HStack(spacing: 4) {
                    ChangesBadge(count: groups.count, color: badgeColor)
                    Text(statusText)
                        .fixedSize()
                    Spacer()

                    if !hasChanges {
                        Image(systemName: "document.badge.clock")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(1/6), in: ContainerRelativeShape())
                .contentShape(ContainerRelativeShape())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showMenu) {
                ChangesSincePopover(
                    changeTracker: changeTracker,
                    changeColors: changeColors,
                    isPresented: $showMenu)
            }

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
        if let time = changeTracker.activeWaypointTimestamp
            .map(\.shortTimestamp) {
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
            return .secondary.opacity(1/3)
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
}

// MARK: - Changes Since Popover

private struct ChangesSincePopover: View {
    @ObservedObject var changeTracker: ChangeTracker
    let changeColors: [String: String]
    @Binding var isPresented: Bool

    private var items: [ChangeMenuItem] {
        changeTracker.menuItems()
    }

    /// Primary item (first): "since last accepted" or "since document opened".
    private var primaryItem: ChangeMenuItem? {
        items.first
    }

    /// Time-bucketed reload waypoints (middle section).
    private var timeBucketItems: [ChangeMenuItem] {
        items.dropFirst().filter { $0.label != "since document opened" }
    }

    /// "Since document opened" at the bottom, when distinct from primary.
    private var documentOpenedItem: ChangeMenuItem? {
        guard items.count >= 2 else { return nil }
        let last = items.last!
        return last.label == "since document opened" ? last : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let item = primaryItem {
                menuItemRow(item)
            }

            if !timeBucketItems.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                ForEach(Array(timeBucketItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Spacer()
                            .frame(height: 4)
                    }
                    menuItemRow(item)
                }
            }

            if let item = documentOpenedItem {
                Divider()
                    .padding(.vertical, 4)
                menuItemRow(item)
            }
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Menu item row

    @ViewBuilder
    private func menuItemRow(_ item: ChangeMenuItem) -> some View {
        if item.isActive {
            menuItemContent(item)
        } else {
            Button {
                changeTracker.selectBaseline(item.id)
                isPresented = false
            } label: {
                menuItemContent(item)
            }
            .buttonStyle(.plain)
        }
    }

    private func menuItemContent(_ item: ChangeMenuItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ChangesBadge(
                count: item.changeCount,
                color: badgeColor(for: item))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .font(.callout)
                Text("… at \(item.timestamp.shortTimestamp)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)

            Spacer()

            if item.isActive {
                Image(systemName: "checkmark")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private func badgeColor(for item: ChangeMenuItem) -> Color {
        if item.changeCount == 0 {
            return .secondary.opacity(1/3)
        }
        if item.hasInsertions && item.hasDeletions {
            return Color(cssHex: changeColors["change-mix"])
        }
        if item.hasDeletions {
            return Color(cssHex: changeColors["change-del"])
        }
        return Color(cssHex: changeColors["change-ins"])
    }
}
