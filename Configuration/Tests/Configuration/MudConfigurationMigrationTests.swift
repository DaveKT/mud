import Foundation
import Testing
@testable import MudConfiguration

@Suite("MudConfiguration migration")
struct MudConfigurationMigrationTests {
    /// A stand-in for `UserDefaults.standard` backed by its own suite domain,
    /// so migration tests never touch the real standard defaults.
    struct Standard {
        let suiteName: String
        let defaults: UserDefaults

        init() {
            self.suiteName = "test.mud.legacy.\(UUID().uuidString)"
            self.defaults = UserDefaults(suiteName: suiteName)!
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test func noopWhenBothStoresEmpty() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readTheme() == .earthy)
        #expect(tc.config.readLighting() == .auto)
    }

    @Test func migratesLegacyThemeAndRemovesFromStandard() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set("blues", forKey: "Mud-Theme")
        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readTheme() == .blues)
        #expect(std.defaults.object(forKey: "Mud-Theme") == nil)
    }

    @Test func migratesLegacyBool() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set(false, forKey: "Mud-readableColumn")
        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readViewToggle(.readableColumn) == false)
        #expect(std.defaults.object(forKey: "Mud-readableColumn") == nil)
    }

    @Test func migratesLegacyDouble() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set(1.75, forKey: "Mud-UpModeZoomLevel")
        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readUpModeZoomLevel() == 1.75)
        #expect(std.defaults.object(forKey: "Mud-UpModeZoomLevel") == nil)
    }

    @Test func migratesLegacyStringArray() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set(["alpha", "beta"], forKey: "Mud-EnabledExtensions")
        tc.config.migrate(from: std.defaults)

        let all: Set<String> = ["alpha", "beta", "gamma"]
        #expect(tc.config.readEnabledExtensions(defaultValue: all) == ["alpha", "beta"])
        #expect(std.defaults.object(forKey: "Mud-EnabledExtensions") == nil)
    }

    @Test func newKeyOnlyInSuiteIsLeftAlone() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        tc.config.writeTheme(.riot)
        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readTheme() == .riot)
    }

    @Test func suiteWinsWhenBothPresent() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set("blues", forKey: "Mud-Theme")
        tc.config.writeTheme(.riot)

        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readTheme() == .riot)
        // Legacy key is still cleared from the standard store so re-running
        // migration won't bring it back.
        #expect(std.defaults.object(forKey: "Mud-Theme") == nil)
    }

    @Test func migrateIsIdempotent() {
        let tc = TestConfiguration()
        let std = Standard()
        defer { tc.tearDown(); std.tearDown() }

        std.defaults.set("blues", forKey: "Mud-Theme")
        std.defaults.set(1.5, forKey: "Mud-UpModeZoomLevel")

        tc.config.migrate(from: std.defaults)
        let themeAfterFirst = tc.config.readTheme()
        let zoomAfterFirst = tc.config.readUpModeZoomLevel()

        tc.config.migrate(from: std.defaults)

        #expect(tc.config.readTheme() == themeAfterFirst)
        #expect(tc.config.readUpModeZoomLevel() == zoomAfterFirst)
    }
}
