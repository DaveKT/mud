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
        config.defaults.removePersistentDomain(forName: defaultsSuiteName)
        config.mirror?.removePersistentDomain(forName: mirrorSuiteName)
    }
}
