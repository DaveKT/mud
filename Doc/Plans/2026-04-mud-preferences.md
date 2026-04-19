Plan: MudPreferences Module
===============================================================================

> Status: Underway

Extract the user-preference persistence layer out of `AppState` into a new
Swift package module, `MudPreferences`, that is shared by the main app and the
upcoming Quick Look extension (see
[2026-04-quicklook-extension.md](./2026-04-quicklook-extension.md)).

`AppState` keeps its `@Published` topology and remains the reactive owner of
runtime state. MudPreferences owns key strings, default values, the typed enums
backing user-facing preferences, and the read/write helpers that touch
`UserDefaults`. Preferences remain in `UserDefaults.standard` — the domain the
user's own `defaults write org.josephpearson.mud …` commands target — and
MudPreferences mirrors every write into an app-group suite so the Quick Look
extension can read a stable snapshot.


## Goals

- One central home for everything the app persists to `UserDefaults`. No more
  scattered key strings and inline default literals.
- Keep `UserDefaults.standard` as the source of truth. Mud is a developer tool
  and users should be able to set preferences via
  `defaults write org.josephpearson.mud …` without wrestling with the long,
  space-laden path of the app group's Group Containers plist.
- Every write mirrors into the app-group suite (`group.org.josephpearson.mud`)
  so the Quick Look extension has a separate, shared, readable copy.
- Provide a one-shot `Snapshot` value the extension can read without owning any
  reactive state.
- Per-key legacy rename (`Mud-Theme` → `theme`) inside `UserDefaults.standard`,
  plus a one-shot sync from standard into the app-group suite on app launch.


## Non-goals

- Replacing or restructuring `AppState`. AppState keeps its `@Published`
  properties and Combine sinks. MudPreferences sits underneath as the
  persistence layer.
- Hiding `UserDefaults` behind a property wrapper (e.g. `@MudPref`). Explicit
  read/write methods keep migration visible and stay grep-friendly. Property
  wrappers add a layer of magic that is harder to use from the snapshot path.
- Live propagation of external `defaults write` changes made while the app is
  running. The app-group mirror refreshes at launch and on every subsequent
  in-app write; anyone using `defaults write` to poke at a hidden preference
  while the app is running should restart the app for the Quick Look extension
  to see the change. Documented, not fixed.
- Observability hooks (KVO, Combine publishers) on MudPreferences itself.
  AppState's existing `@Published` properties already drive the UI.
- Supporting multiple writer targets. The mirror direction (standard as source
  of truth, app-group suite as read-only copy for the extension) is chosen
  because `defaults write org.josephpearson.mud …` is a concrete day-one
  developer affordance. A hypothetical second writer — a sibling app, menu bar
  agent, preferences daemon — that wrote directly to the app-group suite would
  have its writes silently overwritten on the main app's next write, because
  the main app reads `.standard`, not the suite. Flipping the mirror direction
  would fix that but would break CLI override of UI-set preferences across
  launches, because the launch-time sync can't distinguish a fresh
  `defaults write` from a stale value the second writer already superseded.
  Without per-key timestamps you can have at most two of: (1) absorb external
  `defaults write` on launch, (2) preserve second-writer writes across
  launches, (3) no conflict resolution. We pick (1) and (3). If a second writer
  ever materializes, it should use real coordination (Darwin notifications,
  XPC) rather than silently contending at the UserDefaults layer.


## Module structure

A new sibling Swift package next to `Core/`:

```
Preferences/
  Package.swift
  Sources/Preferences/
    MudPreferences.swift              — struct, `.shared`, read/write helpers
    MudPreferencesSnapshot.swift      — value type for extension consumption
    MudPreferencesMigration.swift     — legacy rename + mirror sync
    Theme.swift                         — moved from App/
    ViewToggle.swift                    — moved from App/
    SidebarPane.swift                   — moved from App/AppState.swift
    FloatingControlsPosition.swift      — moved from App/
    Mode.swift                          — moved from App/
    Lighting.swift                      — bare enum, moved from App/
  Tests/Preferences/
    MudPreferencesTests.swift           — round-trips, defaults, reset, catalog, mirror fan-out
    MudPreferencesMigrationTests.swift  — legacy rename + mirror sync
    MudPreferencesSnapshotTests.swift   — snapshot + upModeHTMLClasses
```

All preference types sit directly under `Sources/Preferences/` — no nested
folder. (A `Keys/` subdirectory would collide with the `MudPreferences.Keys`
enum defined in the Public API below.)

Package product: `MudPreferences`. Depends on `MudCore` (for `DocCAlertMode`).
Foundation only — no AppKit, no SwiftUI.


## Dependency arrow

```
App ─┬─▶ MudPreferences ─▶ MudCore
     └─▶ MudCore

QuickLookExtension ─┬─▶ MudPreferences ─▶ MudCore
                    └─▶ MudCore
```

No cycles. MudCore stays platform-independent and unaware of UserDefaults.


## What moves into MudPreferences

### Typed enums

These have no platform dependencies and are pure preference shapes:

- `Theme` (currently `App/Theme.swift`)
- `ViewToggle` (currently `App/ViewToggle.swift`)
- `SidebarPane` (currently nested in `App/AppState.swift`)
- `FloatingControlsPosition` (currently `App/FloatingControlsPosition.swift`)
- `Mode` (currently `App/Mode.swift`)
- `Lighting` — the bare enum only; see below


### Lighting split

Today's `Lighting` type bundles two unrelated concerns:

- A bare enum (`bright` / `dark` / `auto`) — a pref shape with no platform
  dependency.
- AppKit/SwiftUI behavior — `appearance: NSAppearance?`,
  `colorScheme(environment:)`, `systemIsDark`, `toggled()` (which consumes
  `systemIsDark`).

Move the bare enum into MudPreferences so `Lighting` can be persisted via a
typed `readLighting()` / `writeLighting(_:)` pair like every other pref. The
AppKit/SwiftUI methods stay in App/ as a `Lighting+AppKit.swift` extension
file. No change at call sites — `lighting.appearance`,
`lighting.colorScheme(...)`, `lighting.toggled()` are still available wherever
App/ is in scope.

Moving the entire type (including the AppKit methods) into MudPreferences would
force the module to import AppKit and SwiftUI, which would break the
Foundation-only boundary and add unnecessary weight to the Quick Look
extension's link graph.


### Stays in MudCore

- `DocCAlertMode` — owned by MudCore because it controls parser behavior.
  MudPreferences imports MudCore and round-trips the type through its
  read/write helpers. Moving `DocCAlertMode` into MudPreferences would invert
  the dependency arrow (`MudCore → MudPreferences`), coupling the pure
  rendering library to the persistence layer for a modest consolidation win.
  Not worth it.


## Key naming convention

All keys use **lowercase-with-hyphens**, no prefix, no leading underscore.

Rationale:

- The bundle domain (`org.josephpearson.mud`) already namespaces every key — an
  app-level prefix like `Mud-` is structurally redundant. Apple's own
  first-party apps don't prefix keys within their own domains.
- macOS first-party precedent for the lowercase-with-hyphens style: the Dock
  (`com.apple.dock`) uses `tilesize`, `autohide`, `static-only`,
  `autohide-time-modifier`, `show-recents`; the screenshot service
  (`com.apple.screencapture`) uses `location`, `disable-shadow`,
  `include-date`.

This supersedes the old `Mud-Theme` / `Mud-readableColumn` mix. Migration from
the legacy keys is covered below.


## Key catalog

Every key currently written by the app. After this work, every key lives under
`org.josephpearson.mud` in `UserDefaults.standard` (source of truth) and is
mirrored into `group.org.josephpearson.mud` for the extension. The "Legacy key"
column shows the name the value was persisted under in `UserDefaults.standard`
before this change — used only by the one-time rename.

| Key                          | Type                       | Default         | Legacy key (standard)          |
| ---------------------------- | -------------------------- | --------------- | ------------------------------ |
| `lighting`                   | `Lighting`                 | `.auto`         | `Mud-Lighting`                 |
| `theme`                      | `Theme`                    | `.earthy`       | `Mud-Theme`                    |
| `up-mode-zoom-level`         | `Double`                   | `1.0`           | `Mud-UpModeZoomLevel`          |
| `down-mode-zoom-level`       | `Double`                   | `1.0`           | `Mud-DownModeZoomLevel`        |
| `sidebar-visible`            | `Bool`                     | `false`         | `Mud-SidebarVisible`           |
| `sidebar-pane`               | `SidebarPane`              | `.outline`      | `Mud-SidebarPane`              |
| `track-changes`              | `Bool`                     | `true`          | `Mud-TrackChanges`             |
| `inline-deletions`           | `Bool`                     | `false`         | `Mud-InlineDeletions`          |
| `quit-on-close`              | `Bool`                     | `true`          | `Mud-QuitOnClose`              |
| `allow-remote-content`       | `Bool`                     | `true`          | `Mud-AllowRemoteContent`       |
| `enabled-extensions`         | `[String]`                 | all registered  | `Mud-EnabledExtensions`        |
| `docc-alert-mode`            | `DocCAlertMode`            | `.extended`     | `Mud-DoccAlertMode`            |
| `use-heading-as-title`       | `Bool`                     | `true`          | `Mud-UseHeadingAsTitle`        |
| `word-diff-threshold`        | `Double`                   | `0.25`          | `Mud-WordDiffThreshold`        |
| `floating-controls-position` | `FloatingControlsPosition` | `.bottomCenter` | `Mud-FloatingControlsPosition` |
| `show-git-waypoints`         | `Bool`                     | `false`         | `Mud-ShowGitWaypoints`         |
| `readable-column`            | `Bool` (ViewToggle)        | `true`          | `Mud-readableColumn`           |
| `line-numbers`               | `Bool` (ViewToggle)        | `true`          | `Mud-lineNumbers`              |
| `word-wrap`                  | `Bool` (ViewToggle)        | `true`          | `Mud-wordWrap`                 |
| `code-header`                | `Bool` (ViewToggle)        | `true`          | `Mud-codeHeader`               |
| `auto-expand-changes`        | `Bool` (ViewToggle)        | `false`         | `Mud-autoExpandChanges`        |


## Public API

### Shape: two UserDefaults instances

`MudPreferences` is a `struct` holding two `UserDefaults` — a `defaults` used
for reads and writes (the source of truth) and an optional `mirror` that
receives a fan-out copy of every write. Production code in the app uses
`MudPreferences.shared`, which points `defaults` at `.standard` and `mirror` at
the app-group suite. The Quick Look extension constructs its own instance with
`defaults` pointing at the suite and no mirror — it never writes, and the one
value-type it consumes is `MudPreferencesSnapshot`.

```swift
public struct MudPreferences {
    public static let appGroupSuiteName = "group.org.josephpearson.mud"

    let defaults: UserDefaults
    let mirror: UserDefaults?

    public init(defaults: UserDefaults, mirror: UserDefaults? = nil) {
        self.defaults = defaults
        self.mirror = mirror
    }

    /// Production instance — reads and writes `.standard`, mirrors writes
    /// into the app-group suite for the Quick Look extension.
    public static let shared = MudPreferences(
        defaults: .standard,
        mirror: UserDefaults(suiteName: appGroupSuiteName)!
    )
}
```

The Quick Look extension builds its instance with:

```swift
MudPreferences(
    defaults: UserDefaults(suiteName: MudPreferences.appGroupSuiteName)!
)
```

All read/write methods below are **instance methods** on `MudPreferences`. Call
sites in App/ go through `MudPreferences.shared`.


### Keys

Key strings live in a `String`-backed `CaseIterable` enum on `MudPreferences`.
The Swift identifier is camelCase (what the language requires for readable case
names); the `rawValue` is the persistence string. `legacyStandardKey` is used
by migration only — it can be stripped in a follow-up release once existing
installs have migrated.

```swift
extension MudPreferences {
    enum Keys: String, CaseIterable {
        case lighting                 = "lighting"
        case theme                    = "theme"
        case upModeZoomLevel          = "up-mode-zoom-level"
        case downModeZoomLevel        = "down-mode-zoom-level"
        case sidebarVisible           = "sidebar-visible"
        case sidebarPane              = "sidebar-pane"
        case trackChanges             = "track-changes"
        case inlineDeletions          = "inline-deletions"
        case quitOnClose              = "quit-on-close"
        case allowRemoteContent       = "allow-remote-content"
        case enabledExtensions        = "enabled-extensions"
        case doccAlertMode            = "docc-alert-mode"
        case useHeadingAsTitle        = "use-heading-as-title"
        case wordDiffThreshold        = "word-diff-threshold"
        case floatingControlsPosition = "floating-controls-position"
        case showGitWaypoints         = "show-git-waypoints"
        case readableColumn           = "readable-column"
        case lineNumbers              = "line-numbers"
        case wordWrap                 = "word-wrap"
        case codeHeader               = "code-header"
        case autoExpandChanges        = "auto-expand-changes"

        /// The key this value was persisted under in UserDefaults.standard
        /// before the lowercase-hyphen rename. Used by migration only.
        var legacyStandardKey: String {
            switch self {
            case .readableColumn:    return "Mud-readableColumn"
            case .lineNumbers:       return "Mud-lineNumbers"
            case .wordWrap:          return "Mud-wordWrap"
            case .codeHeader:        return "Mud-codeHeader"
            case .autoExpandChanges: return "Mud-autoExpandChanges"
            case .lighting:          return "Mud-Lighting"
            case .theme:             return "Mud-Theme"
            case .upModeZoomLevel:   return "Mud-UpModeZoomLevel"
            case .downModeZoomLevel: return "Mud-DownModeZoomLevel"
            case .sidebarVisible:    return "Mud-SidebarVisible"
            case .sidebarPane:       return "Mud-SidebarPane"
            case .trackChanges:      return "Mud-TrackChanges"
            case .inlineDeletions:   return "Mud-InlineDeletions"
            case .quitOnClose:       return "Mud-QuitOnClose"
            case .allowRemoteContent: return "Mud-AllowRemoteContent"
            case .enabledExtensions: return "Mud-EnabledExtensions"
            case .doccAlertMode:     return "Mud-DoccAlertMode"
            case .useHeadingAsTitle: return "Mud-UseHeadingAsTitle"
            case .wordDiffThreshold: return "Mud-WordDiffThreshold"
            case .floatingControlsPosition: return "Mud-FloatingControlsPosition"
            case .showGitWaypoints:  return "Mud-ShowGitWaypoints"
            }
        }
    }
}
```


### Per-key read/write methods

Reads hit `defaults`. Writes fan out — they set both `defaults` and, when
present, `mirror`. A private helper keeps the per-key methods tight:

```swift
extension MudPreferences {
    private func write(_ value: Any?, forKey key: Keys) {
        defaults.set(value, forKey: key.rawValue)
        mirror?.set(value, forKey: key.rawValue)
    }
}
```

The examples below cover the patterns an implementer will meet: a type defined
in MudPreferences (`Theme`, `Lighting`), a type imported from MudCore
(`DocCAlertMode`), a scalar, and the `ViewToggle` shape (singular primary,
plural convenience).

```swift
extension MudPreferences {
    // Enum defined in MudPreferences:
    public func readTheme() -> Theme {
        let raw = defaults.string(forKey: Keys.theme.rawValue) ?? ""
        return Theme(rawValue: raw) ?? .earthy
    }
    public func writeTheme(_ value: Theme) {
        write(value.rawValue, forKey: .theme)
    }

    public func readLighting() -> Lighting {
        let raw = defaults.string(forKey: Keys.lighting.rawValue) ?? ""
        return Lighting(rawValue: raw) ?? .auto
    }
    public func writeLighting(_ value: Lighting) {
        write(value.rawValue, forKey: .lighting)
    }

    // Enum imported from MudCore:
    public func readDoccAlertMode() -> DocCAlertMode {
        let raw = defaults.string(forKey: Keys.doccAlertMode.rawValue) ?? ""
        return DocCAlertMode(rawValue: raw) ?? .extended
    }
    public func writeDoccAlertMode(_ value: DocCAlertMode) {
        write(value.rawValue, forKey: .doccAlertMode)
    }

    // Scalar:
    public func readUpModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.upModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeUpModeZoomLevel(_ value: Double) {
        write(value, forKey: .upModeZoomLevel)
    }

    // ViewToggle — singular pair is primary (mirrors today's
    // ViewToggle.isEnabled / save(_:)). The plural convenience wraps it.
    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        defaults.object(forKey: toggle.key.rawValue) as? Bool
            ?? toggle.defaultValue
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        write(enabled, forKey: toggle.key)
    }
    public func readViewToggles() -> Set<ViewToggle> {
        Set(ViewToggle.allCases.filter { readViewToggle($0) })
    }

    // ... one pair per remaining row in the key catalog
}
```

`ViewToggle.key` returns the matching `Keys` case for each toggle (e.g.
`.readableColumn → Keys.readableColumn`); `defaultValue` is the existing
per-case default. Both live on `ViewToggle` itself now that it has moved into
the module.


### Snapshot for the extension

```swift
public struct MudPreferencesSnapshot {
    public let theme: Theme
    public let upModeZoomLevel: Double
    public let viewToggles: Set<ViewToggle>
    public let allowRemoteContent: Bool
    public let enabledExtensions: Set<String>
    public let doccAlertMode: DocCAlertMode

    /// CSS classes derived from the Up-mode-relevant view toggles.
    public var upModeHTMLClasses: Set<String> { /* readable column,
        word wrap, line numbers */ }
}

extension MudPreferences {
    public func snapshot() -> MudPreferencesSnapshot {
        .init(
            theme: readTheme(),
            upModeZoomLevel: readUpModeZoomLevel(),
            viewToggles: readViewToggles(),
            allowRemoteContent: readAllowRemoteContent(),
            enabledExtensions: readEnabledExtensions(),
            doccAlertMode: readDoccAlertMode()
        )
    }
}
```

`snapshot()` always reads from `defaults` — in the app that's `.standard`, in
the extension that's the app-group suite. Same code, same read path, just aimed
at different stores.

The snapshot covers only the fields a Quick Look preview consumes (i.e. the
fields that flow into `RenderOptions`). Other prefs (lighting, sidebar state,
quit-on-close, etc.) are not in the snapshot — the extension never reads them.

If a future helper or extension needs more fields, add them here. The
snapshot's surface area can grow without affecting AppState's call sites.


### Migration

Migration runs in two phases, both idempotent. The app calls
`MudPreferences.shared.migrate()` once on launch. Tests can invoke each phase
independently.

```swift
extension MudPreferences {
    /// One-time legacy key rename inside `defaults` (e.g. `Mud-Theme` →
    /// `theme`). Idempotent — an already-present new key short-circuits.
    public func migrateLegacyKeys() {
        for key in Keys.allCases {
            if defaults.object(forKey: key.rawValue) != nil { continue }
            guard let value = defaults.object(forKey: key.legacyStandardKey)
                else { continue }
            defaults.set(value, forKey: key.rawValue)
            defaults.removeObject(forKey: key.legacyStandardKey)
        }
    }

    /// Copy every current `defaults` value into `mirror`. Picks up any
    /// `defaults write` changes the user made while the app was not running,
    /// and removes any mirror keys whose source value has since been cleared.
    /// No-op when the instance has no mirror.
    public func syncMirror() {
        guard let mirror else { return }
        for key in Keys.allCases {
            let value = defaults.object(forKey: key.rawValue)
            mirror.set(value, forKey: key.rawValue)
        }
    }

    /// Convenience called by the app at launch. Rename legacy keys first,
    /// then sync — so the mirror reflects the post-rename source of truth.
    public func migrate() {
        migrateLegacyKeys()
        syncMirror()
    }
}
```

Called once from the app's `init` sequence (e.g. `AppDelegate` or
`MudApp.init()`) as `MudPreferences.shared.migrate()`, before `AppState.shared`
is first touched. The extension does not run migration — it has no mirror and
no legacy keys to rename. If the app has never launched since installation, the
suite is empty and the extension falls back to hard-coded defaults; this is the
documented edge case covered in the QL plan.


### Reset

```swift
extension MudPreferences {
    /// Remove every Mud preference from this instance's `defaults` and, if
    /// present, from `mirror`. Used by the Debugging settings pane in debug
    /// builds (via `.shared.reset()`).
    public func reset() {
        for key in Keys.allCases {
            write(nil, forKey: key)
        }
    }
}
```

`write(nil, forKey:)` removes the key from both stores — `UserDefaults.set`
documents passing `nil` as equivalent to `removeObject(forKey:)`. Clearing the
mirror synchronously matters because the extension reads it immediately; if we
left the mirror populated, the Quick Look preview would see stale values until
the next app launch.

Walking `Keys.allCases` means new prefs are reset automatically as they're
added.


## AppState changes

`AppState` keeps every `@Published` property it has today. The diff is purely
in the persistence layer:

- Remove the `Self.fooKey` constants — they live in `MudPreferences.Keys`.
- Remove the `defaults.object(forKey:) as? Bool ?? true` style construction in
  `init()`. Replace with `MudPreferences.shared.readFoo()` calls.
- Replace each `saveFoo()` body with a single call to
  `MudPreferences.shared.writeFoo(...)`.

Example before/after (note the key rename is invisible to `AppState` — all call
sites speak in types, not key strings):

```swift
// Before: AppState owns the key string and the default.
private static let themeKey = "Mud-Theme"
@Published var theme: Theme

private init() {
    let raw = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
    self.theme = Theme(rawValue: raw) ?? .earthy
}
func saveTheme(_ theme: Theme) {
    UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
}

// After: MudPreferences owns both. The renamed key sits in .standard
// under `theme` and is mirrored into the app-group suite on write.
@Published var theme: Theme

private init() {
    self.theme = MudPreferences.shared.readTheme()
}
func saveTheme(_ theme: Theme) {
    MudPreferences.shared.writeTheme(theme)
}
```

`ViewToggle.isEnabled` / `ViewToggle.save(_:)` likewise become thin wrappers
that delegate to `MudPreferences.shared.readViewToggle(_:)` /
`MudPreferences.shared.writeViewToggle(_:enabled:)`.


## Tests

Swift Testing (matching `MudCoreTests`'s `import Testing` / `@Test` / `@Suite`
conventions). Three test files, split by concern. Every test creates its own
`MudPreferences` instance with a hermetic per-test `defaults` suite, and most
also supply a hermetic per-test `mirror` suite, so Swift Testing's default
parallel execution is safe.


### Helper

```swift
@testable import MudPreferences

/// Fresh, hermetic MudPreferences for one test, with its own defaults and
/// mirror suites. Call `tearDown()` at the end of each test to remove both
/// on-disk domains.
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
```

Tests that exercise the extension's read path (no mirror) build a second
`MudPreferences` whose `defaults` is the first instance's mirror suite.


### `MudPreferencesTests.swift`

Round-trips and defaults:

- For each type shape, write → read returns the written value: enum defined in
  MudPreferences (`Theme`, `Lighting`), enum imported from MudCore
  (`DocCAlertMode`), `Double`, `Bool`, `[String]`, `SidebarPane`,
  `FloatingControlsPosition`, and `ViewToggle` (singular + plural).
- Read on an empty suite returns the hard-coded default — not `false` / `0` /
  empty string. Covers the `object(forKey:) as? T ?? default` pattern.
- Read when the stored raw string doesn't match any enum case returns the
  default (confirms `Type(rawValue:) ?? default`, not force-unwrap).
- `reset()` after writes → snapshot returns all defaults, and both `defaults`
  and `mirror` are cleared.

Mirror fan-out:

- After every write method, the new value is present in both `defaults` and
  `mirror` under the same key.
- A `MudPreferences` built with `mirror: nil` still reads and writes cleanly;
  writes simply don't fan out.
- Reading from a second `MudPreferences` whose `defaults` points at the first
  instance's mirror returns the same values — the extension read path matches
  what the app wrote.

Key-catalog invariants (cheap tripwires for someone adding a case later):

- `Keys.allCases.count` matches the catalog.
- All `rawValue`s are distinct.
- All `legacyStandardKey`s are distinct.


### `MudPreferencesMigrationTests.swift`

Legacy rename (`migrateLegacyKeys()`) — source and destination are both
`defaults`:

- Neither legacy nor new key present → no change; snapshot returns default.
- Legacy key present, new key absent → value renamed in place; legacy key
  removed.
- New key present, legacy absent → no-op.
- Both present → new key wins; legacy key is removed.
- Idempotent: running twice in a row leaves the store in the same state.
- Type-specific migrations — at least one per shape: `Mud-Theme` (String),
  `Mud-readableColumn` (Bool), `Mud-UpModeZoomLevel` (Double),
  `Mud-EnabledExtensions` (`[String]`).

Mirror sync (`syncMirror()`):

- With a mirror: every key present in `defaults` is copied to `mirror`.
- Keys absent in `defaults` result in the corresponding mirror key being
  removed (set-nil behavior), so the mirror never retains stale state.
- Without a mirror: no-op, no crash.
- Idempotent.

End-to-end (`migrate()`):

- Populate a legacy key in `defaults`, run `migrate()`, assert the value lands
  at the renamed key in `defaults` and is also present in `mirror`.


### `MudPreferencesSnapshotTests.swift`

- Snapshot of an empty suite returns all hard-coded defaults.
- After individual writes, `snapshot()` reflects each field exactly.
- `upModeHTMLClasses` derivation: given a specific `Set<ViewToggle>`, the
  returned class names are correct (`.readableColumn → "is-readable-column"`,
  etc.), and down-mode-only toggles are excluded.
- Snapshot from a mirror-backed `MudPreferences` (simulating the extension)
  equals the snapshot from the defaults-backed `MudPreferences` after the same
  sequence of writes.


### Not tested

- Thread safety — `UserDefaults` handles it.
- Persistence across process restarts — `UserDefaults` handles it.
- Observability — we said no KVO/Combine on MudPreferences; nothing to test.
- Cross-process visibility between the app and the QL extension — a runtime
  integration concern, not a unit test. Verified by running the extension
  against a real dev build.
- Live handling of external `defaults write` changes made while the app is
  running. Documented as restart-required behavior.


## Order of work

The move-to-suite version of this plan already landed. The diff from the
current code to the revised (mirror-to-suite) design:

1. `MudPreferences.init` gains a `mirror: UserDefaults? = nil` parameter. Add
   the `mirror` stored property.
2. `MudPreferences.shared` flips: `defaults` becomes `.standard`, `mirror`
   holds `UserDefaults(suiteName: appGroupSuiteName)!`.
3. Add the private `write(_:forKey:)` helper. Route every existing write method
   through it so the mirror receives every write.
4. Replace the current `migrate(from:)` with `migrateLegacyKeys()` (in-place
   rename inside `defaults`) and `syncMirror()` (fan-out into the mirror). Keep
   a `migrate()` convenience that runs both; the existing launch call site is
   unchanged.
5. `reset()` routes through `write(nil, forKey:)` so it clears both stores.
6. Update `MudPreferencesMigrationTests` for the new shape. Add the mirror
   fan-out assertions to `MudPreferencesTests` and the mirror-backed snapshot
   assertion to `MudPreferencesSnapshotTests`.
7. Smoke-test the running app: launch with existing `Mud-*` keys in
   `.standard`, confirm they rename correctly and that the app-group suite ends
   up populated.

The app-group entitlement and the Package.swift wiring landed in the earlier
round and do not need revisiting.


## Follow-up cleanup

After at least one release has shipped with migration in place and the
population of existing installs has had a chance to upgrade, remove:

- `Keys.legacyStandardKey` — no longer referenced.
- `MudPreferences.migrateLegacyKeys()` and its call in `migrate()`.

`syncMirror()` stays — it still serves the "user did `defaults write` while the
app wasn't running" case that motivated the whole mirror design.

Users who upgrade past that cleanup release from a pre-migration version lose
their settings (falling back to defaults). Acceptable on the assumption that
the migration release is pinned as a minimum supported version for a release or
two before removal.
