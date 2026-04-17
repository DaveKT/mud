import Foundation
import Testing
import MudCore
@testable import MudConfiguration

@Suite("MudConfiguration")
struct MudConfigurationTests {
    // MARK: - Round-trips

    @Test func themeRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeTheme(.blues)
        #expect(tc.config.readTheme() == .blues)
    }

    @Test func lightingRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeLighting(.dark)
        #expect(tc.config.readLighting() == .dark)
    }

    @Test func doccAlertModeRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeDoccAlertMode(.off)
        #expect(tc.config.readDoccAlertMode() == .off)
    }

    @Test func doubleRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeUpModeZoomLevel(1.5)
        #expect(tc.config.readUpModeZoomLevel() == 1.5)
    }

    @Test func boolRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeTrackChanges(false)
        #expect(tc.config.readTrackChanges() == false)
    }

    @Test func stringArrayRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        let all: Set<String> = ["alpha", "beta", "gamma"]
        tc.config.writeEnabledExtensions(["alpha", "gamma"])
        let read = tc.config.readEnabledExtensions(defaultValue: all)
        #expect(read == ["alpha", "gamma"])
    }

    @Test func sidebarPaneRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeSidebarPane(.changes)
        #expect(tc.config.readSidebarPane() == .changes)
    }

    @Test func floatingControlsPositionRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeFloatingControlsPosition(.topRight)
        #expect(tc.config.readFloatingControlsPosition() == .topRight)
    }

    @Test func viewToggleSingularRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeViewToggle(.readableColumn, enabled: false)
        #expect(tc.config.readViewToggle(.readableColumn) == false)
    }

    @Test func viewTogglePluralRoundTrip() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.writeViewToggle(.lineNumbers, enabled: false)
        tc.config.writeViewToggle(.wordWrap, enabled: true)
        tc.config.writeViewToggle(.codeHeader, enabled: false)
        tc.config.writeViewToggle(.autoExpandChanges, enabled: true)
        let set = tc.config.readViewToggles()
        #expect(set == [.readableColumn, .wordWrap, .autoExpandChanges])
    }

    // MARK: - Defaults on empty suite

    @Test func emptySuiteLightingDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readLighting() == .auto)
    }

    @Test func emptySuiteThemeDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readTheme() == .earthy)
    }

    @Test func emptySuiteDoccAlertDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readDoccAlertMode() == .extended)
    }

    @Test func emptySuiteZoomDefaults() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readUpModeZoomLevel() == 1.0)
        #expect(tc.config.readDownModeZoomLevel() == 1.0)
    }

    @Test func emptySuiteBoolDefaults() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        // Bool prefs must not fall back to `false` on an empty suite —
        // the object(forKey:) as? Bool ?? default pattern matters here.
        #expect(tc.config.readTrackChanges() == true)
        #expect(tc.config.readInlineDeletions() == false)
        #expect(tc.config.readQuitOnClose() == true)
        #expect(tc.config.readAllowRemoteContent() == true)
        #expect(tc.config.readUseHeadingAsTitle() == true)
        #expect(tc.config.readShowGitWaypoints() == false)
        #expect(tc.config.readSidebarVisible() == false)
    }

    @Test func emptySuiteWordDiffThresholdDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readWordDiffThreshold() == 0.25)
    }

    @Test func emptySuiteFloatingControlsDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readFloatingControlsPosition() == .bottomCenter)
    }

    @Test func emptySuiteSidebarPaneDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readSidebarPane() == .outline)
    }

    @Test func emptySuiteEnabledExtensionsReturnsDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        let all: Set<String> = ["alpha", "beta"]
        #expect(tc.config.readEnabledExtensions(defaultValue: all) == all)
    }

    @Test func emptySuiteViewToggleDefaults() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        #expect(tc.config.readViewToggle(.readableColumn) == false)
        #expect(tc.config.readViewToggle(.lineNumbers) == true)
        #expect(tc.config.readViewToggle(.wordWrap) == true)
        #expect(tc.config.readViewToggle(.codeHeader) == true)
        #expect(tc.config.readViewToggle(.autoExpandChanges) == false)
    }

    // MARK: - Unknown enum raw values fall back to the default

    @Test func unknownThemeRawFallsBackToDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.defaults.set("not-a-theme", forKey: MudConfiguration.Keys.theme.rawValue)
        #expect(tc.config.readTheme() == .earthy)
    }

    @Test func unknownLightingRawFallsBackToDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.defaults.set("nope", forKey: MudConfiguration.Keys.lighting.rawValue)
        #expect(tc.config.readLighting() == .auto)
    }

    @Test func unknownDoccAlertRawFallsBackToDefault() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.defaults.set("xyz", forKey: MudConfiguration.Keys.doccAlertMode.rawValue)
        #expect(tc.config.readDoccAlertMode() == .extended)
    }

    // MARK: - Reset

    @Test func resetClearsEveryKey() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeTheme(.blues)
        tc.config.writeLighting(.dark)
        tc.config.writeUpModeZoomLevel(2.0)
        tc.config.writeTrackChanges(false)
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.reset()
        #expect(tc.config.readTheme() == .earthy)
        #expect(tc.config.readLighting() == .auto)
        #expect(tc.config.readUpModeZoomLevel() == 1.0)
        #expect(tc.config.readTrackChanges() == true)
        #expect(tc.config.readViewToggle(.readableColumn) == false)
    }

    @Test func resetClearsMirror() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }
        tc.config.writeTheme(.blues)
        tc.config.writeUpModeZoomLevel(2.0)
        tc.config.writeViewToggle(.readableColumn, enabled: true)

        tc.config.reset()

        let mirror = tc.config.mirror!
        for key in MudConfiguration.Keys.allCases {
            #expect(mirror.object(forKey: key.rawValue) == nil)
        }
    }

    // MARK: - Mirror fan-out

    @Test func writesLandInBothDefaultsAndMirror() {
        let tc = TestConfiguration()
        defer { tc.tearDown() }

        tc.config.writeTheme(.blues)
        tc.config.writeUpModeZoomLevel(1.5)
        tc.config.writeTrackChanges(false)
        tc.config.writeEnabledExtensions(["alpha", "beta"])
        tc.config.writeViewToggle(.readableColumn, enabled: true)

        #expect(
            tc.config.defaults.string(forKey: MudConfiguration.Keys.theme.rawValue)
                == "blues"
        )
        #expect(
            tc.config.mirror!.string(forKey: MudConfiguration.Keys.theme.rawValue)
                == "blues"
        )
        #expect(
            tc.config.mirror!.object(forKey: MudConfiguration.Keys.upModeZoomLevel.rawValue)
                as? Double == 1.5
        )
        #expect(
            tc.config.mirror!.object(forKey: MudConfiguration.Keys.trackChanges.rawValue)
                as? Bool == false
        )
        #expect(
            (tc.config.mirror!.array(forKey: MudConfiguration.Keys.enabledExtensions.rawValue)
                as? [String]).map(Set.init) == ["alpha", "beta"]
        )
        #expect(
            tc.config.mirror!.object(forKey: MudConfiguration.Keys.readableColumn.rawValue)
                as? Bool == true
        )
    }

    @Test func mirrorBackedReadMatchesDefaults() {
        // Simulate the Quick Look extension: a second MudConfiguration whose
        // `defaults` points at the main instance's mirror suite. It should
        // read back whatever the app just wrote.
        let tc = TestConfiguration()
        defer { tc.tearDown() }

        tc.config.writeTheme(.riot)
        tc.config.writeUpModeZoomLevel(1.25)
        tc.config.writeAllowRemoteContent(false)
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.writeViewToggle(.lineNumbers, enabled: false)

        let readerAsExtension = MudConfiguration(defaults: tc.config.mirror!)

        #expect(readerAsExtension.readTheme() == .riot)
        #expect(readerAsExtension.readUpModeZoomLevel() == 1.25)
        #expect(readerAsExtension.readAllowRemoteContent() == false)
        #expect(readerAsExtension.readViewToggle(.readableColumn) == true)
        #expect(readerAsExtension.readViewToggle(.lineNumbers) == false)
    }

    @Test func writesWithoutMirrorDoNotFanOut() {
        // The extension's own MudConfiguration has no mirror. Writes should
        // still work; they just don't fan out anywhere.
        let suiteName = "test.mud.nomirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = MudConfiguration(defaults: defaults)
        config.writeTheme(.blues)

        #expect(config.readTheme() == .blues)
        #expect(config.mirror == nil)
    }

    // MARK: - Key-catalog invariants

    @Test func keyCatalogCount() {
        #expect(MudConfiguration.Keys.allCases.count == 21)
    }

    @Test func keyRawValuesAreDistinct() {
        let raws = MudConfiguration.Keys.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }

    @Test func legacyKeysAreDistinct() {
        let legacy = MudConfiguration.Keys.allCases.map(\.legacyStandardKey)
        #expect(Set(legacy).count == legacy.count)
    }
}
