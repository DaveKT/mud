import Foundation
@testable import MudPreferences

/// Fresh, hermetic MudPreferences for one test, with its own `defaults`
/// and `mirror` suites. Call `tearDown()` at the end of each test to remove
/// both on-disk domains.
struct TestPreferences {
    let defaultsSuiteName: String
    let mirrorSuiteName: String
    let config: MudPreferences

    init() {
        let id = UUID().uuidString
        self.defaultsSuiteName = "test.mud.defaults.\(id)"
        self.mirrorSuiteName = "test.mud.mirror.\(id)"
        self.config = MudPreferences(
            defaults: UserDefaults(suiteName: defaultsSuiteName)!,
            mirror: UserDefaults(suiteName: mirrorSuiteName)!
        )
    }

    func tearDown() {
        // Flush any pending writes so cfprefsd has no backlog that could
        // recreate the plist after we drop the domain.
        config.defaults.synchronize()
        config.mirror?.synchronize()
        // `removePersistentDomain` alone leaves cfprefsd holding cached state
        // that gets re-flushed to `~/Library/Preferences/<suite>.plist` after
        // tearDown returns. Shelling out to `defaults delete` routes through
        // cfprefsd and drops the domain definitively. The file-removal below
        // catches the rare case where no `defaults` binary write happened
        // (e.g. an empty test) and cfprefsd left a stub plist behind.
        Self.deleteSuite(defaultsSuiteName)
        Self.deleteSuite(mirrorSuiteName)
        Self.removePlist(forSuite: defaultsSuiteName)
        Self.removePlist(forSuite: mirrorSuiteName)
    }

    private static func deleteSuite(_ name: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["delete", name]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    private static func removePlist(forSuite suiteName: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
            .appendingPathComponent("\(suiteName).plist")
        try? FileManager.default.removeItem(at: url)
    }
}
