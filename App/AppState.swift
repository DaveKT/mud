import Foundation
import Combine
import MudConfiguration
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting
    @Published var theme: Theme
    @Published var viewToggles: Set<ViewToggle>
    @Published var upModeZoomLevel: Double
    @Published var downModeZoomLevel: Double
    @Published var sidebarVisible: Bool
    @Published var sidebarPane: SidebarPane
    @Published var trackChanges: Bool
    @Published var inlineDeletions: Bool
    @Published var quitOnClose: Bool
    @Published var allowRemoteContent: Bool
    @Published var enabledExtensions: Set<String>
    @Published var doccAlertMode: DocCAlertMode
    @Published var useHeadingAsTitle: Bool
    var openSettingsAction: (() -> Void)?
    @Published var wordDiffThreshold: Double
    @Published var floatingControlsPosition: FloatingControlsPosition
    @Published var showGitWaypoints: Bool

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
        self.enabledExtensions = config.readEnabledExtensions(
            defaultValue: Set(RenderExtension.registry.keys)
        )
        self.doccAlertMode = config.readDoccAlertMode()
        self.useHeadingAsTitle = config.readUseHeadingAsTitle()
        self.wordDiffThreshold = config.readWordDiffThreshold()
        self.floatingControlsPosition = config.readFloatingControlsPosition()
        self.showGitWaypoints = config.readShowGitWaypoints()
    }

    func saveLighting(_ lighting: Lighting) {
        MudConfiguration.shared.writeLighting(lighting)
    }

    func saveTheme(_ theme: Theme) {
        MudConfiguration.shared.writeTheme(theme)
    }

    func saveZoomLevels() {
        MudConfiguration.shared.writeUpModeZoomLevel(upModeZoomLevel)
        MudConfiguration.shared.writeDownModeZoomLevel(downModeZoomLevel)
    }

    func saveSidebarVisible() {
        MudConfiguration.shared.writeSidebarVisible(sidebarVisible)
    }

    func saveSidebarPane() {
        MudConfiguration.shared.writeSidebarPane(sidebarPane)
    }

    func saveTrackChanges(_ value: Bool) {
        MudConfiguration.shared.writeTrackChanges(value)
    }

    func saveInlineDeletions() {
        MudConfiguration.shared.writeInlineDeletions(inlineDeletions)
    }

    func saveQuitOnClose() {
        MudConfiguration.shared.writeQuitOnClose(quitOnClose)
    }

    func saveAllowRemoteContent() {
        MudConfiguration.shared.writeAllowRemoteContent(allowRemoteContent)
    }

    func saveEnabledExtensions() {
        MudConfiguration.shared.writeEnabledExtensions(enabledExtensions)
    }

    func saveDoccAlertMode() {
        MudConfiguration.shared.writeDoccAlertMode(doccAlertMode)
    }

    func saveUseHeadingAsTitle() {
        MudConfiguration.shared.writeUseHeadingAsTitle(useHeadingAsTitle)
    }

    func saveWordDiffThreshold() {
        MudConfiguration.shared.writeWordDiffThreshold(wordDiffThreshold)
    }

    func saveFloatingControlsPosition() {
        MudConfiguration.shared.writeFloatingControlsPosition(floatingControlsPosition)
    }

    func saveShowGitWaypoints() {
        MudConfiguration.shared.writeShowGitWaypoints(showGitWaypoints)
    }

    func toggle(_ option: ViewToggle) {
        if viewToggles.contains(option) {
            viewToggles.remove(option)
        } else {
            viewToggles.insert(option)
        }
        option.save(viewToggles.contains(option))
    }
}
