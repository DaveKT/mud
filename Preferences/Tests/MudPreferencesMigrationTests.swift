import Foundation
import Testing
@testable import MudPreferences

@Suite("MudPreferences migration")
struct MudPreferencesMigrationTests {
    // MARK: - migrateLegacyKeys — in-place rename inside `defaults`

    @Test func legacyRenameNoopWhenStoreEmpty() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.migrateLegacyKeys()

        #expect(tc.config.theme == .earthy)
        #expect(tc.config.lighting == .auto)
    }

    @Test func legacyRenameMovesThemeAndRemovesOldKey() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set("blues", forKey: "Mud-Theme")
        tc.config.migrateLegacyKeys()

        #expect(tc.config.theme == .blues)
        #expect(tc.config.defaults.object(forKey: "Mud-Theme") == nil)
    }

    @Test func legacyRenameMovesBool() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set(false, forKey: "Mud-readableColumn")
        tc.config.migrateLegacyKeys()

        #expect(tc.config.readViewToggle(.readableColumn) == false)
        #expect(tc.config.defaults.object(forKey: "Mud-readableColumn") == nil)
    }

    @Test func legacyRenameMovesDouble() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set(1.75, forKey: "Mud-UpModeZoomLevel")
        tc.config.migrateLegacyKeys()

        #expect(tc.config.upModeZoomLevel == 1.75)
        #expect(tc.config.defaults.object(forKey: "Mud-UpModeZoomLevel") == nil)
    }

    @Test func legacyRenameMovesStringArray() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set(["alpha", "beta"], forKey: "Mud-EnabledExtensions")
        tc.config.migrateLegacyKeys()

        let all: Set<String> = ["alpha", "beta", "gamma"]
        #expect(
            tc.config.readEnabledExtensions(defaultValue: all) == ["alpha", "beta"]
        )
        #expect(tc.config.defaults.object(forKey: "Mud-EnabledExtensions") == nil)
    }

    @Test func legacyRenameLeavesNewKeyAlone() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .riot
        tc.config.migrateLegacyKeys()

        #expect(tc.config.theme == .riot)
    }

    @Test func legacyRenameNewKeyWinsWhenBothPresent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set("blues", forKey: "Mud-Theme")
        tc.config.theme = .riot

        tc.config.migrateLegacyKeys()

        #expect(tc.config.theme == .riot)
        // The legacy key is still cleared so re-running migration won't keep
        // finding it.
        #expect(tc.config.defaults.object(forKey: "Mud-Theme") == nil)
    }

    @Test func legacyRenameIsIdempotent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set("blues", forKey: "Mud-Theme")
        tc.config.defaults.set(1.5, forKey: "Mud-UpModeZoomLevel")

        tc.config.migrateLegacyKeys()
        let themeAfterFirst = tc.config.theme
        let zoomAfterFirst = tc.config.upModeZoomLevel

        tc.config.migrateLegacyKeys()

        #expect(tc.config.theme == themeAfterFirst)
        #expect(tc.config.upModeZoomLevel == zoomAfterFirst)
    }

    // MARK: - syncMirror — fan-out copy from `defaults` into `mirror`

    @Test func syncMirrorCopiesEveryPresentKey() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        // Set values directly on `defaults` to simulate external
        // `defaults write` changes made while the app was not running.
        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.defaults.set(1.5, forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
        tc.config.defaults.set(false, forKey: MudPreferences.Keys.trackChanges.rawValue)

        tc.config.syncMirror()

        let mirror = tc.config.mirror!
        #expect(
            mirror.string(forKey: MudPreferences.Keys.theme.rawValue) == "blues"
        )
        #expect(
            mirror.object(forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
                as? Double == 1.5
        )
        #expect(
            mirror.object(forKey: MudPreferences.Keys.trackChanges.rawValue)
                as? Bool == false
        )
    }

    @Test func syncMirrorClearsStaleValueWhenSourceIsAbsent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.mirror!.set("riot", forKey: MudPreferences.Keys.theme.rawValue)
        // `defaults` does not have a `theme` key.

        tc.config.syncMirror()

        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.theme.rawValue) == nil
        )
    }

    @Test func syncMirrorWithoutMirrorIsNoop() {
        let suiteName = "test.mud.nomirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = MudPreferences(defaults: defaults)
        config.syncMirror() // must not crash
    }

    @Test func syncMirrorIsIdempotent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.syncMirror()
        let first = tc.config.mirror!.string(
            forKey: MudPreferences.Keys.theme.rawValue
        )
        tc.config.syncMirror()
        let second = tc.config.mirror!.string(
            forKey: MudPreferences.Keys.theme.rawValue
        )
        #expect(first == second)
    }

    // MARK: - migrate — end-to-end (legacy rename + mirror sync)

    @Test func migrateRenamesLegacyKeyAndPopulatesMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set("blues", forKey: "Mud-Theme")

        tc.config.migrate()

        #expect(tc.config.theme == .blues)
        #expect(tc.config.defaults.object(forKey: "Mud-Theme") == nil)
        #expect(
            tc.config.mirror!.string(forKey: MudPreferences.Keys.theme.rawValue)
                == "blues"
        )
    }

    @Test func migratePicksUpExternalDefaultsWrite() {
        // Simulates: user ran `defaults write org.josephpearson.mud theme
        // riot` while the app was not running. The value sits on the new
        // key in `defaults` already (no rename needed); `migrate()` just
        // needs to fan it out to the mirror so the QL extension sees it.
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.defaults.set("riot", forKey: MudPreferences.Keys.theme.rawValue)

        tc.config.migrate()

        #expect(
            tc.config.mirror!.string(forKey: MudPreferences.Keys.theme.rawValue)
                == "riot"
        )
    }
}
