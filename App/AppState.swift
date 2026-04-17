import Foundation
import Combine
import MudConfiguration
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting {
        didSet { MudConfiguration.shared.lighting = lighting }
    }
    @Published var theme: Theme {
        didSet { MudConfiguration.shared.theme = theme }
    }
    @Published var viewToggles: Set<ViewToggle> {
        didSet { MudConfiguration.shared.viewToggles = viewToggles }
    }
    @Published var upModeZoomLevel: Double {
        didSet { MudConfiguration.shared.upModeZoomLevel = upModeZoomLevel }
    }
    @Published var downModeZoomLevel: Double {
        didSet { MudConfiguration.shared.downModeZoomLevel = downModeZoomLevel }
    }
    @Published var sidebarVisible: Bool {
        didSet { MudConfiguration.shared.sidebarVisible = sidebarVisible }
    }
    @Published var sidebarPane: SidebarPane {
        didSet { MudConfiguration.shared.sidebarPane = sidebarPane }
    }
    @Published var trackChanges: Bool {
        didSet { MudConfiguration.shared.trackChanges = trackChanges }
    }
    @Published var inlineDeletions: Bool {
        didSet { MudConfiguration.shared.inlineDeletions = inlineDeletions }
    }
    @Published var quitOnClose: Bool {
        didSet { MudConfiguration.shared.quitOnClose = quitOnClose }
    }
    @Published var allowRemoteContent: Bool {
        didSet { MudConfiguration.shared.allowRemoteContent = allowRemoteContent }
    }
    @Published var doccAlertMode: DocCAlertMode {
        didSet { MudConfiguration.shared.doccAlertMode = doccAlertMode }
    }
    @Published var useHeadingAsTitle: Bool {
        didSet { MudConfiguration.shared.useHeadingAsTitle = useHeadingAsTitle }
    }
    @Published var wordDiffThreshold: Double {
        didSet { MudConfiguration.shared.wordDiffThreshold = wordDiffThreshold }
    }
    @Published var floatingControlsPosition: FloatingControlsPosition {
        didSet { MudConfiguration.shared.floatingControlsPosition = floatingControlsPosition }
    }
    @Published var showGitWaypoints: Bool {
        didSet { MudConfiguration.shared.showGitWaypoints = showGitWaypoints }
    }
    @Published var enabledExtensions: Set<String> {
        didSet { MudConfiguration.shared.writeEnabledExtensions(enabledExtensions) }
    }

    private init() {
        // Rename any legacy `Mud-*` keys to the lowercase-hyphen names inside
        // UserDefaults.standard, then fan the current values out to the
        // app-group mirror so the Quick Look extension sees a fresh snapshot.
        MudConfiguration.shared.migrate()

        let config = MudConfiguration.shared
        self.lighting = config.lighting
        self.theme = config.theme
        self.viewToggles = config.viewToggles
        self.upModeZoomLevel = config.upModeZoomLevel
        self.downModeZoomLevel = config.downModeZoomLevel
        self.sidebarVisible = config.sidebarVisible
        self.sidebarPane = config.sidebarPane
        self.trackChanges = config.trackChanges
        self.inlineDeletions = config.inlineDeletions
        self.quitOnClose = config.quitOnClose
        self.allowRemoteContent = config.allowRemoteContent
        self.doccAlertMode = config.doccAlertMode
        self.useHeadingAsTitle = config.useHeadingAsTitle
        self.wordDiffThreshold = config.wordDiffThreshold
        self.floatingControlsPosition = config.floatingControlsPosition
        self.showGitWaypoints = config.showGitWaypoints
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
