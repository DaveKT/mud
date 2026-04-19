import Foundation
import MudCore

/// A one-shot read of the preferences a Quick Look preview (or any other
/// non-reactive consumer) needs. Built from `MudPreferences.snapshot()`.
///
/// The surface area covers only the fields that flow into `RenderOptions`.
/// Preferences that don't affect a preview (lighting, sidebar state,
/// quit-on-close, etc.) are deliberately omitted.
public struct MudPreferencesSnapshot: Sendable {
    public let theme: Theme
    public let upModeZoomLevel: Double
    public let viewToggles: Set<ViewToggle>
    public let allowRemoteContent: Bool
    public let enabledExtensions: Set<String>
    public let doccAlertMode: DocCAlertMode

    public init(
        theme: Theme,
        upModeZoomLevel: Double,
        viewToggles: Set<ViewToggle>,
        allowRemoteContent: Bool,
        enabledExtensions: Set<String>,
        doccAlertMode: DocCAlertMode
    ) {
        self.theme = theme
        self.upModeZoomLevel = upModeZoomLevel
        self.viewToggles = viewToggles
        self.allowRemoteContent = allowRemoteContent
        self.enabledExtensions = enabledExtensions
        self.doccAlertMode = doccAlertMode
    }

    /// CSS classes derived from the Up-mode-relevant view toggles.
    /// Down-mode-only toggles (code header, auto-expand changes) are excluded.
    public var upModeHTMLClasses: Set<String> {
        let upModeToggles: Set<ViewToggle> = [
            .readableColumn, .wordWrap, .lineNumbers,
        ]
        return Set(
            viewToggles
                .intersection(upModeToggles)
                .map(\.className)
        )
    }
}

extension MudPreferences {
    public func snapshot(defaultEnabledExtensions: Set<String> = []) -> MudPreferencesSnapshot {
        MudPreferencesSnapshot(
            theme: theme,
            upModeZoomLevel: upModeZoomLevel,
            viewToggles: viewToggles,
            allowRemoteContent: allowRemoteContent,
            enabledExtensions: readEnabledExtensions(defaultValue: defaultEnabledExtensions),
            doccAlertMode: doccAlertMode
        )
    }
}
