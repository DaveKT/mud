import Foundation
import MudCore

/// Centralized read/write layer for every persisted user preference.
///
/// Production code uses `MudConfiguration.shared`, which is backed by the
/// app-group `UserDefaults` suite so the main app and the Quick Look
/// extension see the same store. Tests create their own instance with a
/// hermetic per-test suite.
public struct MudConfiguration: @unchecked Sendable {
    public static let suiteName = "group.org.josephpearson.mud"

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Production instance — reads and writes the app-group suite.
    public static let shared = MudConfiguration(
        defaults: UserDefaults(suiteName: suiteName)!
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
        /// before the move to the app-group suite. Used by migration only;
        /// will be removed in a follow-up release.
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

// MARK: - Read/write methods

extension MudConfiguration {
    // Lighting
    public func readLighting() -> Lighting {
        let raw = defaults.string(forKey: Keys.lighting.rawValue) ?? ""
        return Lighting(rawValue: raw) ?? .auto
    }
    public func writeLighting(_ value: Lighting) {
        defaults.set(value.rawValue, forKey: Keys.lighting.rawValue)
    }

    // Theme
    public func readTheme() -> Theme {
        let raw = defaults.string(forKey: Keys.theme.rawValue) ?? ""
        return Theme(rawValue: raw) ?? .earthy
    }
    public func writeTheme(_ value: Theme) {
        defaults.set(value.rawValue, forKey: Keys.theme.rawValue)
    }

    // Zoom levels
    public func readUpModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.upModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeUpModeZoomLevel(_ value: Double) {
        defaults.set(value, forKey: Keys.upModeZoomLevel.rawValue)
    }
    public func readDownModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.downModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeDownModeZoomLevel(_ value: Double) {
        defaults.set(value, forKey: Keys.downModeZoomLevel.rawValue)
    }

    // Sidebar
    public func readSidebarVisible() -> Bool {
        defaults.object(forKey: Keys.sidebarVisible.rawValue) as? Bool ?? false
    }
    public func writeSidebarVisible(_ value: Bool) {
        defaults.set(value, forKey: Keys.sidebarVisible.rawValue)
    }
    public func readSidebarPane() -> SidebarPane {
        let raw = defaults.string(forKey: Keys.sidebarPane.rawValue) ?? ""
        return SidebarPane(rawValue: raw) ?? .outline
    }
    public func writeSidebarPane(_ value: SidebarPane) {
        defaults.set(value.rawValue, forKey: Keys.sidebarPane.rawValue)
    }

    // Change tracking
    public func readTrackChanges() -> Bool {
        defaults.object(forKey: Keys.trackChanges.rawValue) as? Bool ?? true
    }
    public func writeTrackChanges(_ value: Bool) {
        defaults.set(value, forKey: Keys.trackChanges.rawValue)
    }
    public func readInlineDeletions() -> Bool {
        defaults.object(forKey: Keys.inlineDeletions.rawValue) as? Bool ?? false
    }
    public func writeInlineDeletions(_ value: Bool) {
        defaults.set(value, forKey: Keys.inlineDeletions.rawValue)
    }

    // Quit on close
    public func readQuitOnClose() -> Bool {
        defaults.object(forKey: Keys.quitOnClose.rawValue) as? Bool ?? true
    }
    public func writeQuitOnClose(_ value: Bool) {
        defaults.set(value, forKey: Keys.quitOnClose.rawValue)
    }

    // Remote content
    public func readAllowRemoteContent() -> Bool {
        defaults.object(forKey: Keys.allowRemoteContent.rawValue) as? Bool ?? true
    }
    public func writeAllowRemoteContent(_ value: Bool) {
        defaults.set(value, forKey: Keys.allowRemoteContent.rawValue)
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
        defaults.set(Array(value), forKey: Keys.enabledExtensions.rawValue)
    }

    // DocC alert mode (enum lives in MudCore)
    public func readDoccAlertMode() -> DocCAlertMode {
        let raw = defaults.string(forKey: Keys.doccAlertMode.rawValue) ?? ""
        return DocCAlertMode(rawValue: raw) ?? .extended
    }
    public func writeDoccAlertMode(_ value: DocCAlertMode) {
        defaults.set(value.rawValue, forKey: Keys.doccAlertMode.rawValue)
    }

    // Heading as title
    public func readUseHeadingAsTitle() -> Bool {
        defaults.object(forKey: Keys.useHeadingAsTitle.rawValue) as? Bool ?? true
    }
    public func writeUseHeadingAsTitle(_ value: Bool) {
        defaults.set(value, forKey: Keys.useHeadingAsTitle.rawValue)
    }

    // Word diff threshold
    public func readWordDiffThreshold() -> Double {
        defaults.object(forKey: Keys.wordDiffThreshold.rawValue) as? Double ?? 0.25
    }
    public func writeWordDiffThreshold(_ value: Double) {
        defaults.set(value, forKey: Keys.wordDiffThreshold.rawValue)
    }

    // Floating controls
    public func readFloatingControlsPosition() -> FloatingControlsPosition {
        let raw = defaults.string(forKey: Keys.floatingControlsPosition.rawValue) ?? ""
        return FloatingControlsPosition(rawValue: raw) ?? .bottomCenter
    }
    public func writeFloatingControlsPosition(_ value: FloatingControlsPosition) {
        defaults.set(value.rawValue, forKey: Keys.floatingControlsPosition.rawValue)
    }

    // Git waypoints
    public func readShowGitWaypoints() -> Bool {
        defaults.object(forKey: Keys.showGitWaypoints.rawValue) as? Bool ?? false
    }
    public func writeShowGitWaypoints(_ value: Bool) {
        defaults.set(value, forKey: Keys.showGitWaypoints.rawValue)
    }

    // View toggles. Singular pair is primary; the plural wraps it.
    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        defaults.object(forKey: toggle.key.rawValue) as? Bool ?? toggle.defaultValue
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        defaults.set(enabled, forKey: toggle.key.rawValue)
    }
    public func readViewToggles() -> Set<ViewToggle> {
        Set(ViewToggle.allCases.filter { readViewToggle($0) })
    }
}

// MARK: - Reset

extension MudConfiguration {
    /// Remove every Mud preference from this instance's suite. Used by the
    /// Debugging settings pane in debug builds.
    public func reset() {
        for key in Keys.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
