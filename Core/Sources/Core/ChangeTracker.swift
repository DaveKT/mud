import Foundation
import Combine

// MARK: - Waypoint

public struct Waypoint: Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case initial, reload, accept
        /// A waypoint injected from outside the normal reload flow (e.g. git).
        case external(label: String, detail: String?)
    }
    public let id = UUID()
    public let parsed: ParsedMarkdown
    public let timestamp: Date
    public let kind: Kind

    public init(parsed: ParsedMarkdown, timestamp: Date, kind: Kind) {
        self.parsed = parsed
        self.timestamp = timestamp
        self.kind = kind
    }
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
    public let detail: String?
    public let isExternal: Bool

    public init(
        id: UUID, label: String, timestamp: Date, changeCount: Int,
        isActive: Bool, hasInsertions: Bool, hasDeletions: Bool,
        detail: String? = nil, isExternal: Bool = false
    ) {
        self.id = id
        self.label = label
        self.timestamp = timestamp
        self.changeCount = changeCount
        self.isActive = isActive
        self.hasInsertions = hasInsertions
        self.hasDeletions = hasDeletions
        self.detail = detail
        self.isExternal = isExternal
    }
}

// MARK: - Change Tracker

public class ChangeTracker: ObservableObject {
    @Published public private(set) var waypoints: [Waypoint] = []
    @Published public private(set) var changes: [DocumentChange] = []
    @Published public var selectedChangeID: String?
    @Published public private(set) var activeBaselineID: UUID?

    /// The most recent content passed to `update(_:)`.
    public private(set) var currentParsed: ParsedMarkdown?

    /// Per-waypoint diff summary cache. Cleared when content or waypoints
    /// change; time-bucket assignment and labels are recomputed every call.
    private var diffCache: [UUID: DiffSummary] = [:]

    /// Recent `.reload` waypoints within this window are replaced when a
    /// new reload arrives — collapses rapid-fire saves into one snapshot.
    static let reloadCoalesceInterval: TimeInterval = 5

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
        diffCache = [:]

        if waypoints.isEmpty {
            waypoints.append(Waypoint(
                parsed: parsed, timestamp: now, kind: .initial))
        } else {
            // Skip if content is identical to any existing waypoint.
            let isDuplicate = waypoints.contains { $0.parsed == parsed }

            if !isDuplicate {
                // Drop recent .reload waypoints superseded by this one.
                let coalesceThreshold = now.addingTimeInterval(
                    -Self.reloadCoalesceInterval)
                waypoints.removeAll { waypoint in
                    waypoint.kind == .reload
                        && waypoint.timestamp >= coalesceThreshold
                }
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
        diffCache = [:]
    }

    // MARK: - External waypoints

    /// Replaces all external waypoints (e.g. from git) with the given set.
    /// If the active baseline pointed to a now-removed external waypoint,
    /// resets to the default baseline.
    public func setExternalWaypoints(_ waypoints: [Waypoint]) {
        self.waypoints.removeAll { if case .external = $0.kind { true } else { false } }
        self.waypoints.append(contentsOf: waypoints)
        diffCache = [:]

        // Reset baseline if it pointed to a removed external waypoint.
        if let id = activeBaselineID,
           !self.waypoints.contains(where: { $0.id == id }) {
            selectBaseline(nil)
        }
    }

    // MARK: - Menu items

    /// Time thresholds for bucketed menu entries (in minutes).
    static let timeThresholds: [Int] = [1, 2, 3, 4, 5, 10, 15]

    /// Returns menu items for the "Changes since…" picker.
    /// Time-bucket assignment is recomputed each call so relative labels
    /// stay accurate; per-waypoint diffs are cached until content changes.
    public func menuItems() -> [ChangeMenuItem] {
        menuItems(at: Date())
    }

    /// Testable variant that accepts a timestamp.
    func menuItems(at now: Date) -> [ChangeMenuItem] {
        computeMenuItems(at: now)
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
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
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

        // 2. Time-bucketed waypoints (iterate high-to-low so each waypoint
        //    is claimed by its most accurate bucket, not the smallest one).
        let timeBucketStart = items.count
        for minutes in Self.timeThresholds.reversed() {
            let threshold = now.addingTimeInterval(
                -TimeInterval(minutes * 60))
            // Most recent non-external waypoint older than the threshold.
            guard let wp = waypoints.last(where: {
                if case .external = $0.kind { return false }
                return $0.timestamp <= threshold
            }) else { continue }
            guard !usedWaypointIDs.contains(wp.id) else { continue }

            let label = "since \(minutes) minute\(minutes == 1 ? "" : "s") ago"
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
            usedWaypointIDs.insert(wp.id)
        }
        // Reverse so the menu shows smallest-to-largest.
        items[timeBucketStart...].reverse()

        // 3. "Since document opened" at the bottom (if distinct from primary)
        if acceptWaypoint != nil, let wp = initialWaypoint,
           wp.id != primaryWaypoint?.id {
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: "since document opened",
                timestamp: wp.timestamp, changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
        }

        // 4. External waypoints (e.g. git). Only shown when they have changes.
        let externals = waypoints.filter {
            if case .external = $0.kind { true } else { false }
        }
        for wp in externals {
            guard case .external(let label, let detail) = wp.kind else {
                continue
            }
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveBaseline(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions,
                detail: detail, isExternal: true))
        }

        return items
    }

    private struct DiffSummary {
        let groupCount: Int
        let hasInsertions: Bool
        let hasDeletions: Bool
    }

    private func diffSummary(
        from old: ParsedMarkdown, to new: ParsedMarkdown,
        waypointID: UUID
    ) -> DiffSummary {
        if let cached = diffCache[waypointID] { return cached }
        let changes = MudCore.computeChanges(old: old, new: new)
        let groups = ChangeGroup.build(from: changes)
        let summary = DiffSummary(
            groupCount: groups.count,
            hasInsertions: changes.contains { $0.type == .insertion },
            hasDeletions: changes.contains { $0.type == .deletion })
        diffCache[waypointID] = summary
        return summary
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
