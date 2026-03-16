import Foundation
import Combine
import MudCore

// MARK: - Waypoint

struct Waypoint: Identifiable {
    let id = UUID()
    let parsed: ParsedMarkdown
    let timestamp: Date
}

// MARK: - Change Tracker

class ChangeTracker: ObservableObject {
    @Published private(set) var waypoints: [Waypoint] = []
    @Published private(set) var changes: [DocumentChange] = []
    @Published var selectedChangeID: String?

    /// The most recent content passed to `update(_:)`.
    private(set) var currentParsed: ParsedMarkdown?

    /// The active waypoint's ParsedMarkdown (for RenderOptions).
    var activeWaypoint: ParsedMarkdown? {
        waypoints.last?.parsed
    }

    /// The timestamp of the active waypoint (for sidebar display).
    var activeWaypointTimestamp: Date? {
        waypoints.last?.timestamp
    }

    /// Called on each file load. On the first call, creates the initial
    /// waypoint (no changes). On subsequent calls, diffs against the
    /// active waypoint and updates the change list.
    func update(_ parsed: ParsedMarkdown) {
        currentParsed = parsed
        if waypoints.isEmpty {
            waypoints.append(Waypoint(parsed: parsed, timestamp: Date()))
        } else if let old = activeWaypoint {
            changes = MudCore.computeChanges(old: old, new: parsed)
        }
    }

    /// Accepts the current content as a new waypoint. Clears all changes
    /// until the next file modification.
    func accept() {
        guard let current = currentParsed else { return }
        waypoints.append(Waypoint(parsed: current, timestamp: Date()))
        changes = []
        selectedChangeID = nil
    }
}
