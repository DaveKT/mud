Plan: MudConfiguration Module
===============================================================================

> Status: Underway

Extract the user-preference persistence layer out of `AppState` into a new
Swift package module, `MudConfiguration`, that is shared by the main app and
the upcoming Quick Look extension (see
[2026-04-quicklook-extension.md](./2026-04-quicklook-extension.md)).

`AppState` keeps its `@Published` topology and remains the reactive owner of
runtime state. MudConfiguration owns key strings, default values, the typed
enums backing user-facing preferences, and the read/write helpers that touch
`UserDefaults`. All preference storage moves into a single app-group container
so the extension can read a stable snapshot.


## Goals

- One central home for everything the app persists to `UserDefaults`. No more
  scattered key strings and inline default literals.
- Single source of truth for the app group's UserDefaults suite — both the main
  app and the Quick Look extension read and write the same store.
- Provide a one-shot `Snapshot` value the extension can read without owning any
  reactive state.
- Per-key migration from `UserDefaults.standard` to the app-group suite, run
  once on app launch.


## Non-goals

- Replacing or restructuring `AppState`. AppState keeps its `@Published`
  properties and Combine sinks. MudConfiguration sits underneath as the
  persistence layer.
- Hiding `UserDefaults` behind a property wrapper (e.g. `@MudPref`). Explicit
  read/write methods keep migration visible and stay grep-friendly. Property
  wrappers add a layer of magic that is harder to use from the snapshot path.
- Live update propagation from the suite to the extension. Each preview reads
  the snapshot at request time. Live updates are a non-goal of the QL plan.
- Observability hooks (KVO, Combine publishers) on MudConfiguration itself.
  AppState's existing `@Published` properties already drive the UI.


## Module structure

A new sibling Swift package next to `Core/`:

```
Configuration/
  Package.swift
  Sources/Configuration/
    MudConfiguration.swift              — struct, `.shared`, read/write helpers
    MudConfigurationSnapshot.swift      — value type for extension consumption
    MudConfigurationMigration.swift     — one-time migration from .standard
    Theme.swift                         — moved from App/
    ViewToggle.swift                    — moved from App/
    SidebarPane.swift                   — moved from App/AppState.swift
    FloatingControlsPosition.swift      — moved from App/
    Mode.swift                          — moved from App/
    Lighting.swift                      — bare enum, moved from App/
  Tests/Configuration/
    MudConfigurationTests.swift           — round-trips, defaults, reset, catalog
    MudConfigurationMigrationTests.swift  — legacy-to-new key migration
    MudConfigurationSnapshotTests.swift   — snapshot + upModeHTMLClasses
```

All preference types sit directly under `Sources/Configuration/` — no nested
folder. (A `Keys/` subdirectory would collide with the `MudConfiguration.Keys`
enum defined in the Public API below.)

Package product: `MudConfiguration`. Depends on `MudCore` (for
`DocCAlertMode`). Foundation only — no AppKit, no SwiftUI.


## Dependency arrow

```
App ─┬─▶ MudConfiguration ─▶ MudCore
     └─▶ MudCore

QuickLookExtension ─┬─▶ MudConfiguration ─▶ MudCore
                    └─▶ MudCore
```

No cycles. MudCore stays platform-independent and unaware of UserDefaults.


## What moves into MudConfiguration

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

Move the bare enum into MudConfiguration so `Lighting` can be persisted via a
typed `readLighting()` / `writeLighting(_:)` pair like every other pref. The
AppKit/SwiftUI methods stay in App/ as a `Lighting+AppKit.swift` extension
file. No change at call sites — `lighting.appearance`,
`lighting.colorScheme(...)`, `lighting.toggled()` are still available wherever
App/ is in scope.

Moving the entire type (including the AppKit methods) into MudConfiguration
would force the module to import AppKit and SwiftUI, which would break the
Foundation-only boundary and add unnecessary weight to the Quick Look
extension's link graph.


### Stays in MudCore

- `DocCAlertMode` — owned by MudCore because it controls parser behavior.
  MudConfiguration imports MudCore and round-trips the type through its
  read/write helpers. Moving `DocCAlertMode` into MudConfiguration would invert
  the dependency arrow (`MudCore → MudConfiguration`), coupling the pure
  rendering library to the persistence layer for a modest consolidation win.
  Not worth it.


## Key naming convention

All keys use **lowercase-with-hyphens**, no prefix, no leading underscore.

Rationale:

- The suite domain (`group.org.josephpearson.mud`) already namespaces every key
  — an app-level prefix like `Mud-` is structurally redundant. Apple's own
  first-party apps don't prefix keys within their own domains.
- macOS first-party precedent for the lowercase-with-hyphens style: the Dock
  (`com.apple.dock`) uses `tilesize`, `autohide`, `static-only`,
  `autohide-time-modifier`, `show-recents`; the screenshot service
  (`com.apple.screencapture`) uses `location`, `disable-shadow`,
  `include-date`.

This supersedes the old `Mud-Theme` / `Mud-readableColumn` mix. Migration from
the legacy keys is covered below.


## Key catalog

Every key currently written by the app. After this work, every key lives in the
suite (`group.org.josephpearson.mud`). The "Legacy key" column shows the name
the value was persisted under in `UserDefaults.standard` before this change —
used only by the one-time migration walker.

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

### Shape: instance type with `.shared`

`MudConfiguration` is a `struct` that holds the `UserDefaults` instance it
reads and writes. Production code uses `MudConfiguration.shared`. Tests create
their own instance with a hermetic per-test suite. This mirrors `URLSession` /
`JSONDecoder` — a familiar pattern for parallel-safe tests.

```swift
public struct MudConfiguration {
    public static let suiteName = "group.org.josephpearson.mud"

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Production instance — reads and writes the app-group suite.
    public static let shared = MudConfiguration(
        defaults: UserDefaults(suiteName: suiteName)!
    )
}
```

All read/write methods below are **instance methods** on `MudConfiguration`.
Call sites in App/ and the extension go through `MudConfiguration.shared`.


### Keys

Key strings live in a `String`-backed `CaseIterable` enum on
`MudConfiguration`. The Swift identifier is camelCase (what the language
requires for readable case names); the `rawValue` is the persistence string.
`legacyStandardKey` is used by migration only — it can be stripped in a
follow-up release once existing installs have migrated.

```swift
extension MudConfiguration {
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
        /// before the move to the app-group suite. Used by migration only.
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

Explicit methods, one pair per key. Each method handles the type round-trip
(raw values for enums, `object(forKey:) as? T` for nullable scalars so the
hard-coded default applies only when the key is genuinely absent).

The examples below cover the patterns an implementer will meet: a type defined
in MudConfiguration (`Theme`, `Lighting`), a type imported from MudCore
(`DocCAlertMode`), a scalar, and the `ViewToggle` shape (singular primary,
plural convenience).

```swift
extension MudConfiguration {
    // Enum defined in MudConfiguration:
    public func readTheme() -> Theme {
        let raw = defaults.string(forKey: Keys.theme.rawValue) ?? ""
        return Theme(rawValue: raw) ?? .earthy
    }
    public func writeTheme(_ value: Theme) {
        defaults.set(value.rawValue, forKey: Keys.theme.rawValue)
    }

    public func readLighting() -> Lighting {
        let raw = defaults.string(forKey: Keys.lighting.rawValue) ?? ""
        return Lighting(rawValue: raw) ?? .auto
    }
    public func writeLighting(_ value: Lighting) {
        defaults.set(value.rawValue, forKey: Keys.lighting.rawValue)
    }

    // Enum imported from MudCore:
    public func readDoccAlertMode() -> DocCAlertMode {
        let raw = defaults.string(forKey: Keys.doccAlertMode.rawValue) ?? ""
        return DocCAlertMode(rawValue: raw) ?? .extended
    }
    public func writeDoccAlertMode(_ value: DocCAlertMode) {
        defaults.set(value.rawValue, forKey: Keys.doccAlertMode.rawValue)
    }

    // Scalar:
    public func readUpModeZoomLevel() -> Double {
        defaults.object(forKey: Keys.upModeZoomLevel.rawValue) as? Double ?? 1.0
    }
    public func writeUpModeZoomLevel(_ value: Double) {
        defaults.set(value, forKey: Keys.upModeZoomLevel.rawValue)
    }

    // ViewToggle — singular pair is primary (mirrors today's
    // ViewToggle.isEnabled / save(_:)). The plural convenience wraps it.
    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        defaults.object(forKey: toggle.key.rawValue) as? Bool
            ?? toggle.defaultValue
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        defaults.set(enabled, forKey: toggle.key.rawValue)
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
public struct MudConfigurationSnapshot {
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

extension MudConfiguration {
    public func snapshot() -> MudConfigurationSnapshot {
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

The snapshot covers only the fields a Quick Look preview consumes (i.e. the
fields that flow into `RenderOptions`). Other prefs (lighting, sidebar state,
quit-on-close, etc.) are not in the snapshot — the extension never reads them.

If a future helper or extension needs more fields, add them here. The
snapshot's surface area can grow without affecting AppState's call sites.


### Migration

```swift
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
            if defaults.object(forKey: key.rawValue) != nil { continue }
            guard let value = standard.object(forKey: key.legacyStandardKey)
                else { continue }
            defaults.set(value, forKey: key.rawValue)
            standard.removeObject(forKey: key.legacyStandardKey)
        }
    }
}
```

Called once from the app's `init` sequence (e.g. `AppDelegate` or
`MudApp.init()`) as `MudConfiguration.shared.migrate()`, before
`AppState.shared` is first touched. The extension does not run migration — its
own `UserDefaults.standard` is a different domain, so there is nothing to
migrate from. If migration has not yet run, the snapshot returns hard-coded
defaults; this is the documented edge case covered in the QL plan.


### Reset

```swift
extension MudConfiguration {
    /// Remove every Mud preference from this instance's suite. Used by the
    /// Debugging settings pane in debug builds (via `.shared.reset()`).
    public func reset() {
        for key in Keys.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
```

Replaces the current per-key reset logic in `DebuggingSettingsView` with a
single call. Walking `Keys.allCases` means new prefs are reset automatically as
they're added.


## AppState changes

`AppState` keeps every `@Published` property it has today. The diff is purely
in the persistence layer:

- Remove the `Self.fooKey` constants — they live in `MudConfiguration.Keys`.
- Remove the `defaults.object(forKey:) as? Bool ?? true` style construction in
  `init()`. Replace with `MudConfiguration.shared.readFoo()` calls.
- Replace each `saveFoo()` body with a single call to
  `MudConfiguration.shared.writeFoo(...)`.

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

// After: MudConfiguration owns both. The new "theme" key lives in the suite.
@Published var theme: Theme

private init() {
    self.theme = MudConfiguration.shared.readTheme()
}
func saveTheme(_ theme: Theme) {
    MudConfiguration.shared.writeTheme(theme)
}
```

`ViewToggle.isEnabled` / `ViewToggle.save(_:)` likewise become thin wrappers
that delegate to `MudConfiguration.shared.readViewToggle(_:)` /
`MudConfiguration.shared.writeViewToggle(_:enabled:)`.


## Tests

Swift Testing (matching `MudCoreTests`'s `import Testing` / `@Test` / `@Suite`
conventions). Three test files, split by concern. Every test creates its own
`MudConfiguration` instance with a hermetic per-test suite so Swift Testing's
default parallel execution is safe.


### Helper

```swift
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
```


### `MudConfigurationTests.swift`

Round-trips and defaults:

- For each type shape, write → read returns the written value: enum defined in
  MudConfiguration (`Theme`, `Lighting`), enum imported from MudCore
  (`DocCAlertMode`), `Double`, `Bool`, `[String]`, `SidebarPane`,
  `FloatingControlsPosition`, and `ViewToggle` (singular + plural).
- Read on an empty suite returns the hard-coded default — not `false` / `0` /
  empty string. Covers the `object(forKey:) as? T ?? default` pattern.
- Read when the stored raw string doesn't match any enum case returns the
  default (confirms `Type(rawValue:) ?? default`, not force-unwrap).
- `reset()` after writes → snapshot returns all defaults.

Key-catalog invariants (cheap tripwires for someone adding a case later):

- `Keys.allCases.count` matches the catalog.
- All `rawValue`s are distinct.
- All `legacyStandardKey`s are distinct.


### `MudConfigurationMigrationTests.swift`

Migration takes both a source (`from standard:`) and an implicit destination
(the instance's own suite). Tests pass their own stand-in `.standard` so the
real standard defaults are never touched.

- Key absent in both stores → no change; snapshot returns default.
- Legacy key in the stand-in `.standard` only → migrated to suite under the new
  name; the legacy key is removed from the stand-in.
- New key in the suite only → no-op.
- Both present (partial migration from a prior run) → suite wins; legacy key is
  removed from `.standard`.
- Running `migrate()` twice in a row is idempotent (no diff after second call).
- Type-specific migrations — at least one per shape: `Mud-Theme` (String),
  `Mud-readableColumn` (Bool), `Mud-UpModeZoomLevel` (Double),
  `Mud-EnabledExtensions` (`[String]`).


### `MudConfigurationSnapshotTests.swift`

- Snapshot of an empty suite returns all hard-coded defaults.
- After individual writes, `snapshot()` reflects each field exactly.
- `upModeHTMLClasses` derivation: given a specific `Set<ViewToggle>`, the
  returned class names are correct (`.readableColumn → "is-readable-column"`,
  etc.), and down-mode-only toggles are excluded.


### Not tested

- Thread safety — `UserDefaults` handles it.
- Persistence across process restarts — `UserDefaults` handles it.
- Observability — we said no KVO/Combine on MudConfiguration; nothing to test.
- Cross-process visibility between the app and the QL extension — a runtime
  integration concern, not a unit test. Verified by running the extension
  against a real dev build.


## Order of work

1. Create the `Configuration/` Swift package, declare `MudConfiguration`
   product, add MudCore dependency.
2. Move the platform-independent enums into `Sources/Configuration/`. Split
   `Lighting` — bare enum into the module, AppKit/SwiftUI extension stays in
   App/ as `Lighting+AppKit.swift`. Update App/ imports.
3. Land `MudConfiguration` (struct with `.shared`), `Keys`, and read/write
   methods. Land `MudConfigurationTests.swift`.
4. Land `migrate(from:)`. Land `MudConfigurationMigrationTests.swift`.
5. Refactor `AppState` and `ViewToggle` to call `MudConfiguration.shared`.
   Smoke-test the running app. `DebuggingSettingsView` switches to
   `MudConfiguration.shared.reset()`.
6. Add `MudConfigurationSnapshot` and the `snapshot()` instance method. Land
   `MudConfigurationSnapshotTests.swift`. (Used by the QL extension in the
   sibling plan.)
7. Add the app-group entitlement to the main-app target. The suite begins
   working immediately; existing users' settings migrate on next launch.

Steps 1–5 are landable independently of the QL plan; the app continues to work
the same way, just persisting through a centralized layer. Steps 6–7 unblock
the QL extension.


## Follow-up cleanup

After at least one release has shipped with migration in place and the
population of existing installs has had a chance to upgrade, remove:

- `Keys.legacyStandardKey` — no longer referenced.
- `MudConfiguration.migrate(from:)` and its call site.

Users who upgrade past that cleanup release from a pre-migration version lose
their settings (falling back to defaults). Acceptable on the assumption that
the migration release is pinned as a minimum supported version for a release or
two before removal.
