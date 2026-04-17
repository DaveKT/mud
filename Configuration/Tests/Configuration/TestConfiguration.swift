import Foundation
@testable import MudConfiguration

/// Fresh, hermetic MudConfiguration for one test, with its own `defaults`
/// and `mirror` suites. Call `tearDown()` at the end of each test to remove
/// both on-disk domains.
struct TestConfiguration {
    let defaultsSuiteName: String
    let mirrorSuiteName: String
    let config: MudConfiguration

    init() {
        let id = UUID().uuidString
        self.defaultsSuiteName = "test.mud.defaults.\(id)"
        self.mirrorSuiteName = "test.mud.mirror.\(id)"
        self.config = MudConfiguration(
            defaults: UserDefaults(suiteName: defaultsSuiteName)!,
            mirror: UserDefaults(suiteName: mirrorSuiteName)!
        )
    }

    func tearDown() {
        config.defaults.removePersistentDomain(forName: defaultsSuiteName)
        config.mirror?.removePersistentDomain(forName: mirrorSuiteName)
    }
}
