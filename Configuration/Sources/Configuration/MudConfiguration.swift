import Foundation
import MudCore

/// Centralized read/write layer for every persisted user preference.
///
/// Production code uses `MudConfiguration.shared`. `defaults` is the source of
/// truth — `UserDefaults.standard` for the app so that `defaults write
/// org.josephpearson.mud …` from the command line Just Works — and `mirror` is
/// the app-group suite, which receives a fan-out copy of every write so the
/// Quick Look extension can read a stable snapshot. Tests construct their own
/// instance with hermetic per-test suites.
public struct MudConfiguration: @unchecked Sendable {
    public static let appGroupSuiteName = "group.org.josephpearson.mud"

    let defaults: UserDefaults
    let mirror: UserDefaults?

    public init(defaults: UserDefaults, mirror: UserDefaults? = nil) {
        self.defaults = defaults
        self.mirror = mirror
    }

    /// Production instance — reads and writes `.standard`, mirrors writes into
    /// the app-group suite for the Quick Look extension.
    public static let shared = MudConfiguration(
        defaults: .standard,
        mirror: UserDefaults(suiteName: appGroupSuiteName)!
    )
}

extension MudConfiguration {
    public enum Keys: String, CaseIterable {
        case lighting                 = "lighting"
        case theme                    = "theme"
        case upModeZoomLevel          = "up-mode-zoom-level"
        case downModeZoomLevel        = "down-mode-zoom-level"
        case sidebarVisible           = "sidebar-visible"
        case sidebarPane              = "sidebar-pane"
        case trackChanges             = "track-changes"
        case inlineDeletions          = "inline-deletions"
        case quitOnClose              = "quit-on-close"
        case allowRemoteContent       = "allow-remote-content"
        case enabledExtensions        = "enabled-extensions"
        case doccAlertMode            = "docc-alert-mode"
        case useHeadingAsTitle        = "use-heading-as-title"
        case wordDiffThreshold        = "word-diff-threshold"
        case floatingControlsPosition = "floating-controls-position"
        case showGitWaypoints         = "show-git-waypoints"
        case readableColumn           = "readable-column"
        case lineNumbers              = "line-numbers"
        case wordWrap                 = "word-wrap"
        case codeHeader               = "code-header"
        case autoExpandChanges        = "auto-expand-changes"

        /// The key this value was persisted under in `UserDefaults.standard`
        /// before the lowercase-hyphen rename. Used by migration only; will be
        /// removed in a follow-up release.
        var legacyStandardKey: String {
            switch self {
            case .lighting:                 return "Mud-Lighting"
            case .theme:                    return "Mud-Theme"
            case .upModeZoomLevel:          return "Mud-UpModeZoomLevel"
            case .downModeZoomLevel:        return "Mud-DownModeZoomLevel"
            case .sidebarVisible:           return "Mud-SidebarVisible"
            case .sidebarPane:              return "Mud-SidebarPane"
            case .trackChanges:             return "Mud-TrackChanges"
            case .inlineDeletions:          return "Mud-InlineDeletions"
            case .quitOnClose:              return "Mud-QuitOnClose"
            case .allowRemoteContent:       return "Mud-AllowRemoteContent"
            case .enabledExtensions:        return "Mud-EnabledExtensions"
            case .doccAlertMode:            return "Mud-DoccAlertMode"
            case .useHeadingAsTitle:        return "Mud-UseHeadingAsTitle"
            case .wordDiffThreshold:        return "Mud-WordDiffThreshold"
            case .floatingControlsPosition: return "Mud-FloatingControlsPosition"
            case .showGitWaypoints:         return "Mud-ShowGitWaypoints"
            case .readableColumn:           return "Mud-readableColumn"
            case .lineNumbers:              return "Mud-lineNumbers"
            case .wordWrap:                 return "Mud-wordWrap"
            case .codeHeader:               return "Mud-codeHeader"
            case .autoExpandChanges:        return "Mud-autoExpandChanges"
            }
        }
    }
}

// MARK: - Write helper

extension MudConfiguration {
    /// Fan a write out to `defaults` (source of truth) and `mirror` (when
    /// present). Passing `nil` removes the key from both stores.
    func write(_ value: Any?, forKey key: Keys) {
        defaults.set(value, forKey: key.rawValue)
        mirror?.set(value, forKey: key.rawValue)
    }
}

// MARK: - Read/write methods

extension MudConfiguration {
    // Lighting
    public func readLighting() -> Lighting {
        let raw = defaults.string(forKey: Keys.lighting.rawValue) ?? ""
        return Lighting(rawValue: raw) ?? .auto
    }
    public func writeLighting(_ value: Lighting) {
        write(value.rawValue, forKey: .lighting)
    }

    // Theme
    public func readTheme() -> Theme {
        let raw = defaults.string(forKey: Keys.theme.rawValue) ?? ""
        return Theme(rawValue: raw) ?? .earthy
    }
    public func writeTheme(_ value: Theme) {
        write(value.rawValue, forKey: .theme)
    }

    // Zoom levels
    public func readUpModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.upModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeUpModeZoomLevel(_ value: Double) {
        write(value, forKey: .upModeZoomLevel)
    }
    public func readDownModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.downModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeDownModeZoomLevel(_ value: Double) {
        write(value, forKey: .downModeZoomLevel)
    }

    // Sidebar
    public func readSidebarVisible() -> Bool {
        defaults.object(forKey: Keys.sidebarVisible.rawValue) as? Bool ?? false
    }
    public func writeSidebarVisible(_ value: Bool) {
        write(value, forKey: .sidebarVisible)
    }
    public func readSidebarPane() -> SidebarPane {
        let raw = defaults.string(forKey: Keys.sidebarPane.rawValue) ?? ""
        return SidebarPane(rawValue: raw) ?? .outline
    }
    public func writeSidebarPane(_ value: SidebarPane) {
        write(value.rawValue, forKey: .sidebarPane)
    }

    // Change tracking
    public func readTrackChanges() -> Bool {
        defaults.object(forKey: Keys.trackChanges.rawValue) as? Bool ?? true
    }
    public func writeTrackChanges(_ value: Bool) {
        write(value, forKey: .trackChanges)
    }
    public func readInlineDeletions() -> Bool {
        defaults.object(forKey: Keys.inlineDeletions.rawValue) as? Bool ?? false
    }
    public func writeInlineDeletions(_ value: Bool) {
        write(value, forKey: .inlineDeletions)
    }

    // Quit on close
    public func readQuitOnClose() -> Bool {
        defaults.object(forKey: Keys.quitOnClose.rawValue) as? Bool ?? true
    }
    public func writeQuitOnClose(_ value: Bool) {
        write(value, forKey: .quitOnClose)
    }

    // Remote content
    public func readAllowRemoteContent() -> Bool {
        defaults.object(forKey: Keys.allowRemoteContent.rawValue) as? Bool ?? true
    }
    public func writeAllowRemoteContent(_ value: Bool) {
        write(value, forKey: .allowRemoteContent)
    }

    // Extensions. The default is supplied by the caller because
    // MudConfiguration does not own the registry of available extensions.
    public func readEnabledExtensions(defaultValue: Set<String>) -> Set<String> {
        guard let stored = defaults.array(forKey: Keys.enabledExtensions.rawValue)
                as? [String] else {
            return defaultValue
        }
        return Set(stored).intersection(defaultValue)
    }
    public func writeEnabledExtensions(_ value: Set<String>) {
        write(Array(value), forKey: .enabledExtensions)
    }

    // DocC alert mode (enum lives in MudCore)
    public func readDoccAlertMode() -> DocCAlertMode {
        let raw = defaults.string(forKey: Keys.doccAlertMode.rawValue) ?? ""
        return DocCAlertMode(rawValue: raw) ?? .extended
    }
    public func writeDoccAlertMode(_ value: DocCAlertMode) {
        write(value.rawValue, forKey: .doccAlertMode)
    }

    // Heading as title
    public func readUseHeadingAsTitle() -> Bool {
        defaults.object(forKey: Keys.useHeadingAsTitle.rawValue) as? Bool ?? true
    }
    public func writeUseHeadingAsTitle(_ value: Bool) {
        write(value, forKey: .useHeadingAsTitle)
    }

    // Word diff threshold
    public func readWordDiffThreshold() -> Double {
        defaults.object(forKey: Keys.wordDiffThreshold.rawValue) as? Double ?? 0.25
    }
    public func writeWordDiffThreshold(_ value: Double) {
        write(value, forKey: .wordDiffThreshold)
    }

    // Floating controls
    public func readFloatingControlsPosition() -> FloatingControlsPosition {
        let raw = defaults.string(forKey: Keys.floatingControlsPosition.rawValue) ?? ""
        return FloatingControlsPosition(rawValue: raw) ?? .bottomCenter
    }
    public func writeFloatingControlsPosition(_ value: FloatingControlsPosition) {
        write(value.rawValue, forKey: .floatingControlsPosition)
    }

    // Git waypoints
    public func readShowGitWaypoints() -> Bool {
        defaults.object(forKey: Keys.showGitWaypoints.rawValue) as? Bool ?? false
    }
    public func writeShowGitWaypoints(_ value: Bool) {
        write(value, forKey: .showGitWaypoints)
    }

    // View toggles. Singular pair is primary; the plural wraps it.
    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        defaults.object(forKey: toggle.key.rawValue) as? Bool ?? toggle.defaultValue
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        write(enabled, forKey: toggle.key)
    }
    public func readViewToggles() -> Set<ViewToggle> {
        Set(ViewToggle.allCases.filter { readViewToggle($0) })
    }
    public func writeViewToggles(_ toggles: Set<ViewToggle>) {
        for toggle in ViewToggle.allCases {
            writeViewToggle(toggle, enabled: toggles.contains(toggle))
        }
    }
}

// MARK: - Reset

extension MudConfiguration {
    /// Remove every Mud preference from this instance's `defaults` and, when
    /// present, from `mirror`. Used by the Debugging settings pane in debug
    /// builds. Clearing the mirror synchronously matters because the Quick
    /// Look extension reads it on the next preview request.
    public func reset() {
        for key in Keys.allCases {
            write(nil, forKey: key)
        }
    }
}
