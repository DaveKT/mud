import Foundation
import Combine
import MudConfiguration
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting {
        didSet { MudConfiguration.shared.writeLighting(lighting) }
    }
    @Published var theme: Theme {
        didSet { MudConfiguration.shared.writeTheme(theme) }
    }
    @Published var viewToggles: Set<ViewToggle> {
        didSet { MudConfiguration.shared.writeViewToggles(viewToggles) }
    }
    @Published var upModeZoomLevel: Double {
        didSet { MudConfiguration.shared.writeUpModeZoomLevel(upModeZoomLevel) }
    }
    @Published var downModeZoomLevel: Double {
        didSet { MudConfiguration.shared.writeDownModeZoomLevel(downModeZoomLevel) }
    }
    @Published var sidebarVisible: Bool {
        didSet { MudConfiguration.shared.writeSidebarVisible(sidebarVisible) }
    }
    @Published var sidebarPane: SidebarPane {
        didSet { MudConfiguration.shared.writeSidebarPane(sidebarPane) }
    }
    @Published var trackChanges: Bool {
        didSet { MudConfiguration.shared.writeTrackChanges(trackChanges) }
    }
    @Published var inlineDeletions: Bool {
        didSet { MudConfiguration.shared.writeInlineDeletions(inlineDeletions) }
    }
    @Published var quitOnClose: Bool {
        didSet { MudConfiguration.shared.writeQuitOnClose(quitOnClose) }
    }
    @Published var allowRemoteContent: Bool {
        didSet { MudConfiguration.shared.writeAllowRemoteContent(allowRemoteContent) }
    }
    @Published var doccAlertMode: DocCAlertMode {
        didSet { MudConfiguration.shared.writeDoccAlertMode(doccAlertMode) }
    }
    @Published var useHeadingAsTitle: Bool {
        didSet { MudConfiguration.shared.writeUseHeadingAsTitle(useHeadingAsTitle) }
    }
    @Published var wordDiffThreshold: Double {
        didSet { MudConfiguration.shared.writeWordDiffThreshold(wordDiffThreshold) }
    }
    @Published var floatingControlsPosition: FloatingControlsPosition {
        didSet { MudConfiguration.shared.writeFloatingControlsPosition(floatingControlsPosition) }
    }
    @Published var showGitWaypoints: Bool {
        didSet { MudConfiguration.shared.writeShowGitWaypoints(showGitWaypoints) }
    }
    @Published var enabledExtensions: Set<String> {
        didSet { MudConfiguration.shared.writeEnabledExtensions(enabledExtensions) }
    }

    var openSettingsAction: (() -> Void)?

    private init() {
        // Copy any legacy Mud-* keys from UserDefaults.standard into the
        // app-group suite before reading any preference. Runs exactly once
        // per install because `AppState.shared` is a singleton.
        MudConfiguration.shared.migrate()

        let config = MudConfiguration.shared
        self.lighting = config.readLighting()
        self.theme = config.readTheme()
        self.viewToggles = config.readViewToggles()
        self.upModeZoomLevel = config.readUpModeZoomLevel()
        self.downModeZoomLevel = config.readDownModeZoomLevel()
        self.sidebarVisible = config.readSidebarVisible()
        self.sidebarPane = config.readSidebarPane()
        self.trackChanges = config.readTrackChanges()
        self.inlineDeletions = config.readInlineDeletions()
        self.quitOnClose = config.readQuitOnClose()
        self.allowRemoteContent = config.readAllowRemoteContent()
        self.doccAlertMode = config.readDoccAlertMode()
        self.useHeadingAsTitle = config.readUseHeadingAsTitle()
        self.wordDiffThreshold = config.readWordDiffThreshold()
        self.floatingControlsPosition = config.readFloatingControlsPosition()
        self.showGitWaypoints = config.readShowGitWaypoints()
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
