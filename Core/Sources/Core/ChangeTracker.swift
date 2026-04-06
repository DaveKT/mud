import Foundation
import Combine

// MARK: - Waypoint

public struct Waypoint: Identifiable {
    public enum Kind { case initial, reload, accept }
    public let id = UUID()
    public let parsed: ParsedMarkdown
    public let timestamp: Date
    public let kind: Kind
}

// MARK: - Change Menu Item

public struct ChangeMenuItem: Identifiable {
    public let id: UUID
    public let label: String
    public let timestamp: Date
    public let changeCount: Int
    public let isActive: Bool
    public let hasInsertions: Bool
    public let hasDeletions: Bool
}

// MARK: - Change Tracker

public class ChangeTracker: ObservableObject {
    @Published public private(set) var waypoints: [Waypoint] = []
    @Published public private(set) var changes: [DocumentChange] = []
    @Published public var selectedChangeID: String?
    @Published public private(set) var activeBaselineID: UUID?

    /// The most recent content passed to `update(_:)`.
    public private(set) var currentParsed: ParsedMarkdown?

    private var cachedMenuItems: [ChangeMenuItem]?

    /// Minimum interval between stored `.reload` waypoints.
    static let reloadCoalesceInterval: TimeInterval = 60

    /// Maximum age for `.reload` waypoints before pruning.
    static let reloadMaxAge: TimeInterval = 15 * 60

    public init() {}

    // MARK: - Active baseline

    /// The waypoint used as the diff baseline. Also accessible as
    /// `activeWaypoint` for compatibility with RenderOptions.waypoint.
    public var activeBaseline: ParsedMarkdown? {
        if let id = activeBaselineID,
           let waypoint = waypoints.first(where: { $0.id == id }) {
            return waypoint.parsed
        }
        // Fall back to most recent .accept, then .initial.
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return accept.parsed
        }
        return waypoints.first(where: { $0.kind == .initial })?.parsed
    }

    /// Alias for `activeBaseline`, used by `DocumentContentView`.
    public var activeWaypoint: ParsedMarkdown? { activeBaseline }

    /// The timestamp of the active baseline (for bar display).
    public var activeWaypointTimestamp: Date? {
        if let id = activeBaselineID,
           let waypoint = waypoints.first(where: { $0.id == id }) {
            return waypoint.timestamp
        }
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return accept.timestamp
        }
        return waypoints.first(where: { $0.kind == .initial })?.timestamp
    }

    // MARK: - Update

    /// Called on each file load. On the first call, creates the initial
    /// waypoint (no changes). On subsequent calls, diffs against the
    /// active baseline and updates the change list.
    public func update(_ parsed: ParsedMarkdown) {
        update(parsed, at: Date())
    }

    /// Testable variant that accepts a timestamp.
    func update(_ parsed: ParsedMarkdown, at now: Date) {
        currentParsed = parsed
        cachedMenuItems = nil

        if waypoints.isEmpty {
            waypoints.append(Waypoint(
                parsed: parsed, timestamp: now, kind: .initial))
        } else {
            // Skip if content is identical to any existing waypoint.
            let isDuplicate = waypoints.contains { $0.parsed == parsed }

            // Throttle: skip if the most recent .reload is < 60s old.
            let tooSoon = waypoints.last(where: { $0.kind == .reload })
                .map { now.timeIntervalSince($0.timestamp) < Self.reloadCoalesceInterval }
                ?? false

            if !isDuplicate && !tooSoon {
                waypoints.append(Waypoint(
                    parsed: parsed, timestamp: now, kind: .reload))
            }

            // Prune .reload waypoints older than 15 minutes.
            waypoints.removeAll { waypoint in
                waypoint.kind == .reload
                    && now.timeIntervalSince(waypoint.timestamp) > Self.reloadMaxAge
            }

            // Diff against the active baseline.
            if let baseline = activeBaseline {
                changes = MudCore.computeChanges(old: baseline, new: parsed)
            }
        }
    }

    // MARK: - Select baseline

    /// Selects a waypoint as the diff baseline and recomputes changes.
    public func selectBaseline(_ id: UUID?) {
        activeBaselineID = id
        cachedMenuItems = nil
        if let current = currentParsed, let baseline = activeBaseline {
            changes = MudCore.computeChanges(old: baseline, new: current)
        } else {
            changes = []
        }
        selectedChangeID = nil
    }

    // MARK: - Accept

    /// Accepts the current content as a new waypoint. Clears all changes
    /// until the next file modification.
    public func accept() {
        guard currentParsed != nil else { return }
        acceptAt(Date())
    }

    /// Testable variant that accepts a timestamp.
    func acceptAt(_ now: Date) {
        guard let current = currentParsed else { return }

        // Replace existing .accept waypoint, or append.
        if let index = waypoints.firstIndex(where: { $0.kind == .accept }) {
            waypoints[index] = Waypoint(
                parsed: current, timestamp: now, kind: .accept)
        } else {
            waypoints.append(Waypoint(
                parsed: current, timestamp: now, kind: .accept))
        }

        changes = []
        selectedChangeID = nil
        activeBaselineID = nil
        cachedMenuItems = nil
    }

    // MARK: - Menu items

    /// Time thresholds for bucketed menu entries (in minutes).
    static let timeThresholds: [Int] = [1, 2, 3, 4, 5, 10, 15]

    /// Returns menu items for the "Changes since…" picker.
    /// Results are cached until the next `update()` or `accept()`.
    public func menuItems() -> [ChangeMenuItem] {
        menuItems(at: Date())
    }

    /// Testable variant that accepts a timestamp.
    func menuItems(at now: Date) -> [ChangeMenuItem] {
        if let cached = cachedMenuItems { return cached }
        let items = computeMenuItems(at: now)
        cachedMenuItems = items
        return items
    }

    private func computeMenuItems(at now: Date) -> [ChangeMenuItem] {
        guard let current = currentParsed else { return [] }

        var items: [ChangeMenuItem] = []
        var usedWaypointIDs: Set<UUID> = []

        // 1. "Since last accepted" or "Since document opened"
        let acceptWaypoint = waypoints.last(where: { $0.kind == .accept })
        let initialWaypoint = waypoints.first(where: { $0.kind == .initial })
        let primaryWaypoint = acceptWaypoint ?? initialWaypoint

        if let wp = primaryWaypoint {
            let label = acceptWaypoint != nil
                ? "since last accepted" : "since document opened"
            let diff = diffSummary(from: wp.parsed, to: current)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
            usedWaypointIDs.insert(wp.id)
        }

        // Reserve the initial waypoint so time buckets don't claim it
        // (it appears at the bottom when distinct from the primary).
        if let wp = initialWaypoint {
            usedWaypointIDs.insert(wp.id)
        }

        // 2. Time-bucketed waypoints
        for minutes in Self.timeThresholds {
            let threshold = now.addingTimeInterval(
                -TimeInterval(minutes * 60))
            // Most recent waypoint older than the threshold.
            guard let wp = waypoints.last(where: {
                $0.timestamp <= threshold
            }) else { continue }
            guard !usedWaypointIDs.contains(wp.id) else { continue }

            let label = "since \(minutes) minute\(minutes == 1 ? "" : "s") ago"
            let diff = diffSummary(from: wp.parsed, to: current)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
            usedWaypointIDs.insert(wp.id)
        }

        // 3. "Since document opened" at the bottom (if distinct from primary)
        if acceptWaypoint != nil, let wp = initialWaypoint,
           wp.id != primaryWaypoint?.id {
            let diff = diffSummary(from: wp.parsed, to: current)
            items.append(ChangeMenuItem(
                id: wp.id, label: "since document opened",
                timestamp: wp.timestamp, changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
        }

        return items
    }

    private struct DiffSummary {
        let groupCount: Int
        let hasInsertions: Bool
        let hasDeletions: Bool
    }

    private func diffSummary(
        from old: ParsedMarkdown, to new: ParsedMarkdown
    ) -> DiffSummary {
        let changes = MudCore.computeChanges(old: old, new: new)
        let groups = ChangeGroup.build(from: changes)
        return DiffSummary(
            groupCount: groups.count,
            hasInsertions: changes.contains { $0.type == .insertion },
            hasDeletions: changes.contains { $0.type == .deletion })
    }

    private func isActiveBaseline(_ waypoint: Waypoint) -> Bool {
        if let id = activeBaselineID {
            return waypoint.id == id
        }
        // Default baseline: most recent .accept, then .initial.
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return waypoint.id == accept.id
        }
        return waypoint.kind == .initial
    }
}
