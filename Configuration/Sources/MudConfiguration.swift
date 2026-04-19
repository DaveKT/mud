import Foundation
import Security
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
    /// App-group suite name, resolved from the calling process's
    /// `com.apple.security.application-groups` entitlement. Xcode expands
    /// `$(TeamIdentifierPrefix)` in the entitlements file at signing time,
    /// so the runtime value is already Team-ID-prefixed — which macOS
    /// Sequoia+ requires for silent container access without a TCC prompt.
    /// The hardcoded fallback guards against `SecTask` failure (e.g. running
    /// unsigned in a test harness) and must match the entitlements file.
    public static let appGroupSuiteName: String = {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
            ),
            let groups = value as? [String],
            let first = groups.first
        else {
            return "XVL2AFNXH5.org.josephpearson.mud"
        }
        return first
    }()

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

// MARK: - Generic read/write helpers

extension MudConfiguration {
    /// Fan a write out to `defaults` (source of truth) and `mirror` (when
    /// present). Passing `nil` removes the key from both stores.
    func write(_ value: Any?, forKey key: Keys) {
        defaults.set(value, forKey: key.rawValue)
        mirror?.set(value, forKey: key.rawValue)
    }

    /// Overload for string-backed enums — persists the rawValue.
    func write<T: RawRepresentable>(_ value: T, forKey key: Keys) where T.RawValue == String {
        write(value.rawValue, forKey: key)
    }

    /// Read a `UserDefaults`-compatible value (Bool, Double, Int, String, …),
    /// falling back to `d` when the key is absent or of the wrong type.
    func read<T>(_ key: Keys, default d: T) -> T {
        defaults.object(forKey: key.rawValue) as? T ?? d
    }

    /// Read a string-backed enum, falling back to `d`.
    func read<T: RawRepresentable>(_ key: Keys, default d: T) -> T where T.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap(T.init(rawValue:)) ?? d
    }
}

// MARK: - Preferences

extension MudConfiguration {
    public var lighting: Lighting {
        get { read(.lighting, default: .auto) }
        nonmutating set { write(newValue, forKey: .lighting) }
    }

    public var theme: Theme {
        get { read(.theme, default: .earthy) }
        nonmutating set { write(newValue, forKey: .theme) }
    }

    public var upModeZoomLevel: Double {
        get { read(.upModeZoomLevel, default: 1.0) }
        nonmutating set { write(newValue, forKey: .upModeZoomLevel) }
    }

    public var downModeZoomLevel: Double {
        get { read(.downModeZoomLevel, default: 1.0) }
        nonmutating set { write(newValue, forKey: .downModeZoomLevel) }
    }

    public var sidebarVisible: Bool {
        get { read(.sidebarVisible, default: false) }
        nonmutating set { write(newValue, forKey: .sidebarVisible) }
    }

    public var sidebarPane: SidebarPane {
        get { read(.sidebarPane, default: .outline) }
        nonmutating set { write(newValue, forKey: .sidebarPane) }
    }

    public var trackChanges: Bool {
        get { read(.trackChanges, default: true) }
        nonmutating set { write(newValue, forKey: .trackChanges) }
    }

    public var inlineDeletions: Bool {
        get { read(.inlineDeletions, default: false) }
        nonmutating set { write(newValue, forKey: .inlineDeletions) }
    }

    public var quitOnClose: Bool {
        get { read(.quitOnClose, default: true) }
        nonmutating set { write(newValue, forKey: .quitOnClose) }
    }

    public var allowRemoteContent: Bool {
        get { read(.allowRemoteContent, default: true) }
        nonmutating set { write(newValue, forKey: .allowRemoteContent) }
    }

    public var doccAlertMode: DocCAlertMode {
        get { read(.doccAlertMode, default: .extended) }
        nonmutating set { write(newValue, forKey: .doccAlertMode) }
    }

    public var useHeadingAsTitle: Bool {
        get { read(.useHeadingAsTitle, default: true) }
        nonmutating set { write(newValue, forKey: .useHeadingAsTitle) }
    }

    public var wordDiffThreshold: Double {
        get { read(.wordDiffThreshold, default: 0.25) }
        nonmutating set { write(newValue, forKey: .wordDiffThreshold) }
    }

    public var floatingControlsPosition: FloatingControlsPosition {
        get { read(.floatingControlsPosition, default: .bottomCenter) }
        nonmutating set { write(newValue, forKey: .floatingControlsPosition) }
    }

    public var showGitWaypoints: Bool {
        get { read(.showGitWaypoints, default: false) }
        nonmutating set { write(newValue, forKey: .showGitWaypoints) }
    }
}

// MARK: - Parameterized accessors
//
// These stay as methods because their shape doesn't fit a bare property:
// `enabledExtensions` takes a caller-supplied default, and `ViewToggle`
// accessors are parameterized by the toggle itself.

extension MudConfiguration {
    /// Extensions. The default is supplied by the caller because
    /// MudConfiguration does not own the registry of available extensions.
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

    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        read(toggle.key, default: toggle.defaultValue)
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        write(enabled, forKey: toggle.key)
    }

    public var viewToggles: Set<ViewToggle> {
        get { Set(ViewToggle.allCases.filter { readViewToggle($0) }) }
        nonmutating set {
            for toggle in ViewToggle.allCases {
                writeViewToggle(toggle, enabled: newValue.contains(toggle))
            }
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
