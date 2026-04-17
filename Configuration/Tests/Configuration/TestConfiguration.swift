import Foundation
@testable import MudConfiguration

/// Fresh, hermetic MudConfiguration for one test. Call `tearDown()` at the
/// end of each test to remove the on-disk domain.
struct TestConfiguration {
    let suiteName: String
    let config: MudConfiguration

    init() {
        self.suiteName = "test.mud.\(UUID().uuidString)"
        self.config = MudConfiguration(
            defaults: UserDefaults(suiteName: suiteName)!
        )
    }

    func tearDown() {
        config.defaults.removePersistentDomain(forName: suiteName)
    }
}
