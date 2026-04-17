import Foundation

extension MudConfiguration {
    /// Per-key copy from a legacy standard-defaults store into this instance's
    /// suite. Also handles the rename from legacy `Mud-*` keys to the new
    /// lowercase-hyphen naming. Idempotent — safe to run on every launch.
    ///
    /// The `standard` parameter defaults to `UserDefaults.standard` so
    /// production callers can use `MudConfiguration.shared.migrate()`. Tests
    /// pass their own stand-in so they can exercise migration without
    /// touching the real standard defaults.
    public func migrate(from standard: UserDefaults = .standard) {
        for key in Keys.allCases {
            guard let legacyValue = standard.object(forKey: key.legacyStandardKey)
            else { continue }
            if defaults.object(forKey: key.rawValue) == nil {
                defaults.set(legacyValue, forKey: key.rawValue)
            }
            standard.removeObject(forKey: key.legacyStandardKey)
        }
    }
}
