import Foundation

extension MudPreferences {
    /// One-time rename of legacy `Mud-*` keys to the lowercase-hyphen names,
    /// performed in place inside `defaults`. The new key wins when both are
    /// present; either way, the legacy key is removed. Idempotent. Will be
    /// deleted in a follow-up release once installs have had a chance to
    /// migrate.
    public func migrateLegacyKeys() {
        for key in Keys.allCases {
            guard let legacyValue = defaults.object(forKey: key.legacyStandardKey)
            else { continue }
            if defaults.object(forKey: key.rawValue) == nil {
                defaults.set(legacyValue, forKey: key.rawValue)
            }
            defaults.removeObject(forKey: key.legacyStandardKey)
        }
    }

    /// Copy every `defaults` value into `mirror`. Picks up any `defaults
    /// write` changes the user made while the app was not running, and
    /// removes mirror keys whose source value has since been cleared. No-op
    /// when the instance has no mirror.
    public func syncMirror() {
        guard let mirror else { return }
        for key in Keys.allCases {
            let value = defaults.object(forKey: key.rawValue)
            mirror.set(value, forKey: key.rawValue)
        }
    }

    /// Convenience called by the app at launch. Renames legacy keys first,
    /// then fans the (possibly renamed) values out to the mirror, so the
    /// mirror reflects the post-rename source of truth.
    public func migrate() {
        migrateLegacyKeys()
        syncMirror()
    }
}
