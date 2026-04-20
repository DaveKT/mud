import Foundation
import Combine
import MudPreferences
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting {
        didSet { MudPreferences.shared.lighting = lighting }
    }
    @Published var theme: Theme {
        didSet { MudPreferences.shared.theme = theme }
    }
    @Published var viewToggles: Set<ViewToggle> {
        didSet { MudPreferences.shared.viewToggles = viewToggles }
    }
    @Published var upModeZoomLevel: Double {
        didSet { MudPreferences.shared.upModeZoomLevel = upModeZoomLevel }
    }
    @Published var downModeZoomLevel: Double {
        didSet { MudPreferences.shared.downModeZoomLevel = downModeZoomLevel }
    }
    @Published var sidebarEnabled: Bool {
        didSet { MudPreferences.shared.sidebarEnabled = sidebarEnabled }
    }
    @Published var sidebarPane: SidebarPane {
        didSet { MudPreferences.shared.sidebarPane = sidebarPane }
    }
    @Published var changesEnabled: Bool {
        didSet { MudPreferences.shared.changesEnabled = changesEnabled }
    }
    @Published var changesShowInlineDeletions: Bool {
        didSet { MudPreferences.shared.changesShowInlineDeletions = changesShowInlineDeletions }
    }
    @Published var quitOnClose: Bool {
        didSet { MudPreferences.shared.quitOnClose = quitOnClose }
    }
    @Published var upModeAllowRemoteContent: Bool {
        didSet { MudPreferences.shared.upModeAllowRemoteContent = upModeAllowRemoteContent }
    }
    @Published var markdownDocCAlertMode: DocCAlertMode {
        didSet { MudPreferences.shared.markdownDocCAlertMode = markdownDocCAlertMode }
    }
    @Published var uiUseHeadingAsTitle: Bool {
        didSet { MudPreferences.shared.uiUseHeadingAsTitle = uiUseHeadingAsTitle }
    }
    @Published var changesWordDiffThreshold: Double {
        didSet { MudPreferences.shared.changesWordDiffThreshold = changesWordDiffThreshold }
    }
    @Published var uiFloatingControlsPosition: FloatingControlsPosition {
        didSet { MudPreferences.shared.uiFloatingControlsPosition = uiFloatingControlsPosition }
    }
    @Published var changesShowGitWaypoints: Bool {
        didSet { MudPreferences.shared.changesShowGitWaypoints = changesShowGitWaypoints }
    }
    @Published var enabledExtensions: Set<String> {
        didSet { MudPreferences.shared.writeEnabledExtensions(enabledExtensions) }
    }

    private init() {
        // Rename any legacy `Mud-*` keys to the lowercase-hyphen names inside
        // UserDefaults.standard, then fan the current values out to the
        // app-group mirror so the Quick Look extension sees a fresh snapshot.
        MudPreferences.shared.migrate()

        let config = MudPreferences.shared
        self.lighting = config.lighting
        self.theme = config.theme
        self.viewToggles = config.viewToggles
        self.upModeZoomLevel = config.upModeZoomLevel
        self.downModeZoomLevel = config.downModeZoomLevel
        self.sidebarEnabled = config.sidebarEnabled
        self.sidebarPane = config.sidebarPane
        self.changesEnabled = config.changesEnabled
        self.changesShowInlineDeletions = config.changesShowInlineDeletions
        self.quitOnClose = config.quitOnClose
        self.upModeAllowRemoteContent = config.upModeAllowRemoteContent
        self.markdownDocCAlertMode = config.markdownDocCAlertMode
        self.uiUseHeadingAsTitle = config.uiUseHeadingAsTitle
        self.changesWordDiffThreshold = config.changesWordDiffThreshold
        self.uiFloatingControlsPosition = config.uiFloatingControlsPosition
        self.changesShowGitWaypoints = config.changesShowGitWaypoints
        self.enabledExtensions = config.readEnabledExtensions(
            defaultValue: Set(RenderExtension.registry.keys)
        )
    }

    func toggle(_ option: ViewToggle) {
        if viewToggles.contains(option) {
            viewToggles.remove(option)
        } else {
            viewToggles.insert(option)
        }
    }
}
