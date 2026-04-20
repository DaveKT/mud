Plan: Preference Key Conventions
===============================================================================

> Status: Planning

Normalize every `UserDefaults` key the app writes, and the Swift identifiers
that reference them, under a small set of rules: lowercase-hyphen persistence
strings, feature-based grouping, imperative shape for Bool preferences,
past-tense shape for internal state. Folds in the four legacy `Mud-*` keys
still outside `MudPreferences`, renames keys that don't fit the conventions,
establishes grouping prefixes for feature-scoped keys, and aligns Swift case
names with the grouped persistence strings.


## Context

The MudPreferences module (see
[2026-04-mud-preferences.md](./2026-04-mud-preferences.md)) landed most of the
`UserDefaults` work: 21 preference keys under a lowercase-hyphen convention
with a one-shot migration from the old `Mud-PascalCase` names. That module
hasn't shipped yet, so every persistence string is still up for revision.

An audit surfaces four opportunities:

1. **Four app-owned keys still use the legacy form.** They aren't preferences —
   they're internal bookkeeping — and were skipped by the MudPreferences
   migration.

2. **Bool preference keys use three different word-class shapes.** Seven use
   imperative verb-noun (`track-changes`, `show-git-waypoints`, etc.); two use
   state adjectives (`sidebar-visible`, `readable-column`); three use bare
   nouns (`line-numbers`, `word-wrap`, `code-header`).

3. **Keys sit in a flat namespace.** As the app grows, a feature-scoped prefix
   (`changes.*`, `up-mode.*`) helps explain what each key affects at a glance
   and gives future keys an obvious home.

4. **Swift case names are flat even as persistence grows groups.** Aligning
   Swift identifiers to the grouped shape gives one mental model across layers.


## Conventions

### Persistence string shape

| Data shape              | Rule                     | Example                      |
| ----------------------- | ------------------------ | ---------------------------- |
| Non-Bool preference     | noun or noun phrase      | `theme`                      |
| Bool preference         | **imperative verb-noun** | `changes.show-git-waypoints` |
| Master-switch Bool      | `.enabled` suffix        | `changes.enabled`            |
| Bool internal state     | past-tense state         | `internal.has-launched`      |
| Non-Bool internal state | noun phrase              | `internal.window-frame`      |

The two Bool tenses pair with their grammatical roles: preferences express what
_should happen_ (imperative), internal state records what _has happened_ (past
tense).

`.enabled` is the one exception to the imperative rule — it names the single
master-switch slot for a feature group. A group with no Bool master (e.g.
`up-mode.*`) simply omits it.


### Grouping

Keys are grouped by the feature they affect. Groups are dot-separated prefixes
in the persistence string. Top-level keys (no prefix) are **app-global
stylistic or behavioral selections** — `theme`, `lighting`, `quit-on-close`,
`enabled-extensions`. Everything else sits under a group; `internal.*` is the
reserved group for app-owned bookkeeping.

Rule for creating a group: two or more keys share a coherent theme narrower
than "the whole app." One-key groups are fine when they anticipate near-term
growth (`markdown.*`).


### Swift identifier alignment

Swift case names mirror the grouped persistence string: dots become camelCase
boundaries. `<group>.<name>` → `<group><Name>`. Acronyms recognisable as proper
nouns keep their native casing in Swift (`DocC` stays `DocC`). In kebab-case
persistence strings this distinction is lost (`markdown.docc-alert-mode`), and
that's fine — `doc-c-alert-mode` reads worse than `docc-alert-mode`.

The rule applies layer-by-layer depending on whether the layer stores many
unrelated prefs or whether its scope is already implied by the type:

- **Grouped layers** — any type that holds multiple unrelated prefs.
  `MudPreferences.Keys`, the `MudPreferences` accessor namespace,
  `MudPreferencesSnapshot`, and `AppState`. Group prefixes applied in Swift.

- **Scope-implied layers** — types whose entire purpose is one narrow concern.
  `RenderOptions`, `AlertDetector`, `DownHTMLVisitor` are all
  markdown-rendering-scoped, so they drop the `markdown.` prefix. The only
  rename there is the DocC casing fix: `doccAlertMode` → `docCAlertMode`.

Two specific exceptions to the basic rule:

1. **`internal.*` keeps its Swift case name unprefixed even in the grouped
   layers.** `internal` is a Swift access-modifier keyword that reads awkwardly
   as a compound identifier prefix, and the `MudPreferences.Keys` enum already
   provides module-level separation. So `internal.has-launched` → `hasLaunched`
   (not `internalHasLaunched`) in every Swift layer.

2. **`ViewToggle` enum cases stay unchanged.** `ViewToggle` is a UI-surface
   enum used in menu bindings and settings toggles; its case names
   (`readableColumn`, `lineNumbers`, `wordWrap`, `codeHeader`,
   `autoExpandChanges`) match user-facing labels and shouldn't bloat with group
   prefixes. Only the `ViewToggle.key` mapping updates to return the renamed
   `MudPreferences.Keys` case.


## Key catalog

25 keys total. "Default" column gives the hard-coded default when the key is
absent from storage. "Change" column shows what's new or renamed since the
MudPreferences-module plan.


### `changes.*` — diff display and change-tracking

| Swift case                   | Persistence string              | Default | Legacy key              | Change |
| ---------------------------- | ------------------------------- | ------- | ----------------------- | ------ |
| `changesEnabled`             | `changes.enabled`               | `true`  | `Mud-TrackChanges`      | rename |
| `changesShowInlineDeletions` | `changes.show-inline-deletions` | `false` | `Mud-InlineDeletions`   | rename |
| `changesShowGitWaypoints`    | `changes.show-git-waypoints`    | `false` | `Mud-ShowGitWaypoints`  | rename |
| `changesAutoExpandGroups`    | `changes.auto-expand-groups`    | `false` | `Mud-autoExpandChanges` | rename |
| `changesWordDiffThreshold`   | `changes.word-diff-threshold`   | `0.25`  | `Mud-WordDiffThreshold` | rename |

`auto-expand-groups`: the thing being expanded is change _groups_, not
individual changes — and "changes" would be redundant with the group prefix.


### `up-mode.*` — rendered-HTML view options

| Swift case                 | Persistence string             | Default | Legacy key               | Change |
| -------------------------- | ------------------------------ | ------- | ------------------------ | ------ |
| `upModeZoomLevel`          | `up-mode.zoom-level`           | `1.0`   | `Mud-UpModeZoomLevel`    | rename |
| `upModeAllowRemoteContent` | `up-mode.allow-remote-content` | `true`  | `Mud-AllowRemoteContent` | rename |
| `upModeShowCodeHeader`     | `up-mode.show-code-header`     | `true`  | `Mud-codeHeader`         | rename |


### `down-mode.*` — source view options

| Swift case                | Persistence string            | Default | Legacy key              | Change |
| ------------------------- | ----------------------------- | ------- | ----------------------- | ------ |
| `downModeZoomLevel`       | `down-mode.zoom-level`        | `1.0`   | `Mud-DownModeZoomLevel` | rename |
| `downModeShowLineNumbers` | `down-mode.show-line-numbers` | `true`  | `Mud-lineNumbers`       | rename |
| `downModeWrapLines`       | `down-mode.wrap-lines`        | `true`  | `Mud-wordWrap`          | rename |


### `sidebar.*` — sidebar state

| Swift case       | Persistence string | Default    | Legacy key           | Change |
| ---------------- | ------------------ | ---------- | -------------------- | ------ |
| `sidebarEnabled` | `sidebar.enabled`  | `false`    | `Mud-SidebarVisible` | rename |
| `sidebarPane`    | `sidebar.pane`     | `.outline` | `Mud-SidebarPane`    | rename |


### `markdown.*` — parser options

| Swift case              | Persistence string         | Default     | Legacy key          | Change |
| ----------------------- | -------------------------- | ----------- | ------------------- | ------ |
| `markdownDocCAlertMode` | `markdown.docc-alert-mode` | `.extended` | `Mud-DoccAlertMode` | rename |

Single-key group established in anticipation of other parser toggles (Mermaid,
footnotes, etc.). `DocC` keeps proper-noun casing in Swift; the persistence
string stays `docc-alert-mode` for readability.


### `ui.*` — UI chrome and cross-mode layout

| Swift case                   | Persistence string              | Default         | Legacy key                     | Change |
| ---------------------------- | ------------------------------- | --------------- | ------------------------------ | ------ |
| `uiUseHeadingAsTitle`        | `ui.use-heading-as-title`       | `true`          | `Mud-UseHeadingAsTitle`        | rename |
| `uiFloatingControlsPosition` | `ui.floating-controls-position` | `.bottomCenter` | `Mud-FloatingControlsPosition` | rename |
| `uiShowReadableColumn`       | `ui.show-readable-column`       | `false`         | `Mud-readableColumn`           | rename |

Scope: chrome/layout _configuration_ (what's shown, where it sits, how it's
framed). Not "anything visual" — `theme` and `lighting` stay top-level as
app-global style selections.


### `internal.*` — app-owned bookkeeping

| Swift case       | Persistence string          | Default | Legacy key           | Change |
| ---------------- | --------------------------- | ------- | -------------------- | ------ |
| `hasLaunched`    | `internal.has-launched`     | `false` | `Mud-HasLaunched`    | new    |
| `windowFrame`    | `internal.window-frame`     | `nil`   | `Mud-WindowFrame`    | new    |
| `cliInstalled`   | `internal.cli-installed`    | `false` | `Mud-CLIInstalled`   | new    |
| `cliSymlinkPath` | `internal.cli-symlink-path` | `nil`   | `Mud-CLISymlinkPath` | new    |

Swift case names stay unprefixed per the `internal.*` exception. Mirroring:
these route through the same `write(_:forKey:)` helper as the preferences, so
they fan out into the app-group suite. The Quick Look extension ignores them.
Harmless.


### Top-level — app-global selections

| Swift case          | Persistence string   | Default           | Legacy key              |
| ------------------- | -------------------- | ----------------- | ----------------------- |
| `lighting`          | `lighting`           | `.auto`           | `Mud-Lighting`          |
| `theme`             | `theme`              | `.earthy`         | `Mud-Theme`             |
| `quitOnClose`       | `quit-on-close`      | `true`            | `Mud-QuitOnClose`       |
| `enabledExtensions` | `enabled-extensions` | (caller-supplied) | `Mud-EnabledExtensions` |


## UI label change

`App/Settings/DownModeSettingsView.swift:15` — the "Word wrap" toggle label is
renamed to "Wrap lines" to match the new key name and to read as a direct
imperative.


## Migration

Since MudPreferences hasn't shipped, `legacyStandardKey` for every renamed key
points straight from `Mud-*` to the final new persistence string — no
intermediate alias is needed for public installs. Developers running pre-merge
dev builds may have the old intermediate names (e.g. `sidebar-visible`,
`track-changes`) persisted locally; these become orphans after merge and can be
cleared with `defaults delete org.josephpearson.Mud <old-name>` as needed.

`MudPreferencesMigration.swift` itself needs no code changes —
`migrateLegacyKeys()` walks `Keys.allCases` and renames anything with a
`legacyStandardKey` entry; the rename is driven entirely by updating the enum.


## `MudPreferences.swift` changes

Rename every case in the `Keys` enum, update its `rawValue`, and set its
`legacyStandardKey` per the catalog. Add the four new cases for `hasLaunched`,
`windowFrame`, `cliInstalled`, `cliSymlinkPath`.

Rename each accessor property in lockstep. The full accessor rename list,
defaults preserved:

| Old                        | New                          | Type                       | Default         |
| -------------------------- | ---------------------------- | -------------------------- | --------------- |
| `lighting`                 | `lighting`                   | `Lighting`                 | `.auto`         |
| `theme`                    | `theme`                      | `Theme`                    | `.earthy`       |
| `upModeZoomLevel`          | `upModeZoomLevel`            | `Double`                   | `1.0`           |
| `downModeZoomLevel`        | `downModeZoomLevel`          | `Double`                   | `1.0`           |
| `sidebarVisible`           | `sidebarEnabled`             | `Bool`                     | `false`         |
| `sidebarPane`              | `sidebarPane`                | `SidebarPane`              | `.outline`      |
| `trackChanges`             | `changesEnabled`             | `Bool`                     | `true`          |
| `inlineDeletions`          | `changesShowInlineDeletions` | `Bool`                     | `false`         |
| `quitOnClose`              | `quitOnClose`                | `Bool`                     | `true`          |
| `allowRemoteContent`       | `upModeAllowRemoteContent`   | `Bool`                     | `true`          |
| `doccAlertMode`            | `markdownDocCAlertMode`      | `DocCAlertMode`            | `.extended`     |
| `useHeadingAsTitle`        | `uiUseHeadingAsTitle`        | `Bool`                     | `true`          |
| `wordDiffThreshold`        | `changesWordDiffThreshold`   | `Double`                   | `0.25`          |
| `floatingControlsPosition` | `uiFloatingControlsPosition` | `FloatingControlsPosition` | `.bottomCenter` |
| `showGitWaypoints`         | `changesShowGitWaypoints`    | `Bool`                     | `false`         |

Parameterised accessors stay by name — `readEnabledExtensions(defaultValue:)`,
`writeEnabledExtensions(_:)`, `readViewToggle(_:)`,
`writeViewToggle(_:enabled:)`, and the `viewToggles: Set<ViewToggle>` property.

Add four new accessors for the internal keys:

```swift
public var hasLaunched: Bool {
  get { read(.hasLaunched, default: false) }
  nonmutating set { write(newValue, forKey: .hasLaunched) }
}

public var windowFrame: String? {
  get { defaults.string(forKey: Keys.windowFrame.rawValue) }
  nonmutating set { write(newValue, forKey: .windowFrame) }
}

public var cliInstalled: Bool {
  get { read(.cliInstalled, default: false) }
  nonmutating set { write(newValue, forKey: .cliInstalled) }
}

public var cliSymlinkPath: String? {
  get { defaults.string(forKey: Keys.cliSymlinkPath.rawValue) }
  nonmutating set { write(newValue, forKey: .cliSymlinkPath) }
}
```


## `ViewToggle.swift` changes

Enum cases unchanged: `readableColumn`, `lineNumbers`, `wordWrap`,
`codeHeader`, `autoExpandChanges`. The `className` mapping unchanged. Only the
`key` switch updates to return the renamed `MudPreferences.Keys` cases:

| `ViewToggle` case   | New `Keys` case           |
| ------------------- | ------------------------- |
| `readableColumn`    | `uiShowReadableColumn`    |
| `lineNumbers`       | `downModeShowLineNumbers` |
| `wordWrap`          | `downModeWrapLines`       |
| `codeHeader`        | `upModeShowCodeHeader`    |
| `autoExpandChanges` | `changesAutoExpandGroups` |


## `MudPreferencesSnapshot.swift` changes

`MudPreferencesSnapshot` is a grouped layer — it stores multiple unrelated
prefs and mirrors AppState's shape. Rename fields in lockstep with the
`MudPreferences` accessors:

| Old                  | New                        |
| -------------------- | -------------------------- |
| `allowRemoteContent` | `upModeAllowRemoteContent` |
| `doccAlertMode`      | `markdownDocCAlertMode`    |

Unchanged: `theme`, `upModeZoomLevel`, `viewToggles`, `enabledExtensions`.
Update the `init(...)` signature, body, and the
`snapshot(defaultEnabledExtensions:)` call inside the `MudPreferences`
extension.

`upModeHTMLClasses` stays — it's a computed property that reads `viewToggles`,
not any of the renamed fields.


## `AppState.swift` changes

Every `@Published` property that mirrors a renamed `MudPreferences` accessor
takes the new Swift case name. Full rename list:

| Old `@Published`           | New `@Published`             |
| -------------------------- | ---------------------------- |
| `sidebarVisible`           | `sidebarEnabled`             |
| `trackChanges`             | `changesEnabled`             |
| `inlineDeletions`          | `changesShowInlineDeletions` |
| `allowRemoteContent`       | `upModeAllowRemoteContent`   |
| `doccAlertMode`            | `markdownDocCAlertMode`      |
| `useHeadingAsTitle`        | `uiUseHeadingAsTitle`        |
| `wordDiffThreshold`        | `changesWordDiffThreshold`   |
| `floatingControlsPosition` | `uiFloatingControlsPosition` |
| `showGitWaypoints`         | `changesShowGitWaypoints`    |

Unchanged: `modeInActiveTab`, `lighting`, `theme`, `viewToggles`,
`upModeZoomLevel`, `downModeZoomLevel`, `sidebarPane`, `quitOnClose`,
`enabledExtensions`.

Each renamed property's `didSet` body and the corresponding `init()` line
update to the renamed `MudPreferences.shared` accessor.


## MudCore changes

Only one rename: `doccAlertMode` → `docCAlertMode` (DocC proper-noun casing).
The `markdown.` group prefix is _not_ applied here — `RenderOptions` and the
rendering pipeline types are scope-implied layers.

Sites:

- `Core/Sources/RenderOptions.swift:17` — field `doccAlertMode: DocCAlertMode`.
- `Core/Sources/RenderOptions.swift:38` — the `contentIdentity` string
  interpolates `doccAlertMode.rawValue`.
- `Core/Sources/Rendering/AlertDetector.swift:53` — property
  `var doccAlertMode: DocCAlertMode = .extended`.
- `Core/Sources/Rendering/AlertDetector.swift:127,135` — internal reads of
  `doccAlertMode`.
- `Core/Sources/Rendering/DownHTMLVisitor.swift:17,20,36,41,43,66,75` — method
  parameter `doccAlertMode:` on `highlight(_:doccAlertMode:)` and
  `highlightWithChanges(_:_:doccAlertMode:)`, plus internal uses.
- `Core/Sources/MudCore.swift:22,68,73` — call-site references to
  `options.doccAlertMode` and `doccAlertMode:` parameter labels.

Test call sites to update:

- `Core/Tests/DownHTMLVisitorTests.swift:220,225,232,238` — labels on
  `highlight(_:doccAlertMode:)` calls.
- `Core/Tests/UpHTMLVisitorTests.swift:317,325` — `opts.doccAlertMode`
  assignments.

No other `RenderOptions` fields collide with group names — verified against the
current `RenderOptions` shape (`title`, `baseURL`, `theme`, `standalone`,
`blockRemoteContent`, `extensions`, `htmlClasses`, `zoomLevel`, `waypoint`,
`showInlineDeletions`, `wordDiffThreshold`). None need renaming.

The type `DocCAlertMode` already has correct casing and is unchanged.


## App call-site changes

`App/AppDelegate.swift`:

- Remove the `hasLaunchedKey` constant (line 102).
- `isFirstLaunch()` reads and writes `MudPreferences.shared.hasLaunched`.

`App/DocumentWindowController.swift`:

- Remove the `frameKey` constant (line 22).
- Frame restore (line 49) reads `MudPreferences.shared.windowFrame`.
- Frame save (line 339) assigns to `MudPreferences.shared.windowFrame`.

`App/CommandLineInstaller.swift`:

- Remove `installedKey` and `symlinkPathKey` constants (lines 5–6).
- `isInstalled` reads `MudPreferences.shared.cliInstalled`.
- `installedPath` reads `MudPreferences.shared.cliSymlinkPath`.
- `recordInstall` assigns to both.

`App/DocumentContentView.swift:41,45`:

- `opts.doccAlertMode = appState.doccAlertMode` →
  `opts.docCAlertMode = appState.markdownDocCAlertMode`.
- `opts.showInlineDeletions = appState.inlineDeletions` →
  `opts.showInlineDeletions = appState.changesShowInlineDeletions`.

`App/Settings/DownModeSettingsView.swift:15`:

- Toggle label: `"Word wrap"` → `"Wrap lines"`.

`App/Settings/*.swift`: every `$appState.<oldName>` binding updates to the
renamed `@Published` property. Specifically:

- `ChangesSettingsView.swift:10,14,22` — `$appState.inlineDeletions` →
  `$appState.changesShowInlineDeletions`; `$appState.showGitWaypoints` →
  `$appState.changesShowGitWaypoints`.
- `UpModeSettingsView.swift` — any reference to `$appState.allowRemoteContent`
  → `$appState.upModeAllowRemoteContent`.
- `MarkdownSettingsView.swift` — `$appState.doccAlertMode` →
  `$appState.markdownDocCAlertMode`.
- `GeneralSettingsView.swift` — `$appState.useHeadingAsTitle` →
  `$appState.uiUseHeadingAsTitle`; `$appState.quitOnClose` unchanged;
  `$appState.floatingControlsPosition` →
  `$appState.uiFloatingControlsPosition`.
- `ChangesSettingsView.swift` — `$appState.trackChanges` →
  `$appState.changesEnabled`; `$appState.wordDiffThreshold` →
  `$appState.changesWordDiffThreshold`.

`App/MudApp.swift`: menu-command bindings referencing renamed `AppState`
properties update accordingly. ViewToggle-based bindings (`.readableColumn`,
etc.) are unchanged — `ViewToggle` cases kept their names.

`App/DocumentWindowController.swift`: any direct reads of
`AppState.shared.sidebarVisible` → `.sidebarEnabled`, plus the
`AppState.shared.$viewToggles` Combine sink (line 133) — no rename needed for
that.

`QuickLook/PreviewProvider.swift:63`:

- `options.doccAlertMode = snapshot.doccAlertMode` →
  `options.docCAlertMode = snapshot.markdownDocCAlertMode`.

Note the asymmetry here: `snapshot` uses the grouped name
(`markdownDocCAlertMode`) because `MudPreferencesSnapshot` is a grouped layer;
`options` uses the unprefixed name (`docCAlertMode`) because `RenderOptions` is
scope-implied. The fresh agent should not try to make these match — the
asymmetry is intentional.


## Tests

Every test function whose name starts with (or contains) an old Swift case name
renames in lockstep to use the new case name. Concretely:

`Preferences/Tests/MudPreferencesTests.swift`:

- `doccAlertModeRoundTrip` → `markdownDocCAlertModeRoundTrip`.
- `floatingControlsPositionRoundTrip` → `uiFloatingControlsPositionRoundTrip`.
- `emptySuiteDoccAlertDefault` → `emptySuiteMarkdownDocCAlertDefault`.
- `emptySuiteWordDiffThresholdDefault` →
  `emptySuiteChangesWordDiffThresholdDefault`.
- `emptySuiteFloatingControlsDefault` → `emptySuiteUIFloatingControlsDefault`.
- `unknownDoccAlertRawFallsBackToDefault` →
  `unknownMarkdownDocCAlertRawFallsBackToDefault`.
- Body-level references to renamed `MudPreferences` accessors and `Keys` cases
  update accordingly (e.g. `tc.config.doccAlertMode` →
  `tc.config.markdownDocCAlertMode`; `MudPreferences.Keys.doccAlertMode` →
  `.markdownDocCAlertMode`).
- Update the key-catalog count assertion from `21` to `25` (line 296).
- Add round-trip coverage for the four new internal keys: Bool defaults to
  `false`; `String?` defaults to `nil`; writing `nil` clears the key; mirror
  fan-out works for all four.

`Preferences/Tests/MudPreferencesSnapshotTests.swift`:

- Field references update: `snap.doccAlertMode` → `snap.markdownDocCAlertMode`;
  `snap.allowRemoteContent` → `snap.upModeAllowRemoteContent`.
- `init(...)` calls in fixtures update to the new argument labels.

`Preferences/Tests/MudPreferencesMigrationTests.swift`:

- Add one legacy-rename case per new internal key: `Mud-HasLaunched`,
  `Mud-WindowFrame`, `Mud-CLIInstalled`, `Mud-CLISymlinkPath`.
- Spot-check at least one rename of an existing key (e.g. `Mud-TrackChanges` →
  `changes.enabled`) to confirm the grouped persistence string receives the
  migrated value.
- `legacyRenameMovesThemeAndRemovesOldKey` and similar legacy-specific tests:
  verify body asserts still reference the current legacy names (`Mud-*`) —
  those are unchanged.

`Core/Tests/DownHTMLVisitorTests.swift`, `Core/Tests/UpHTMLVisitorTests.swift`:

- Update call-site references to `doccAlertMode:` parameter label and
  `opts.doccAlertMode` → `docCAlertMode`.


## Doc updates

`Doc/AGENTS.md` line 334 — "configuration (theme, baseURL, doccAlertMode,
etc.)" updates to `docCAlertMode`.


## Order of work

1. **`MudPreferences.swift`**: rename every `Keys` case, update `rawValue` and
   `legacyStandardKey`, add the four `internal.*` cases. Rename each accessor
   property in lockstep; add accessors for the new cases.
2. **`ViewToggle.swift`**: update the `key` switch to return the renamed `Keys`
   cases. Cases themselves and `className` unchanged.
3. **`MudPreferencesSnapshot.swift`**: rename `allowRemoteContent` →
   `upModeAllowRemoteContent` and `doccAlertMode` → `markdownDocCAlertMode` on
   the struct, the `init`, and the `snapshot(defaultEnabledExtensions:)`
   extension.
4. **`AppState.swift`**: rename the nine listed `@Published` properties and
   update their `didSet` bodies and `init()` assignments.
5. **MudCore**: rename `RenderOptions.doccAlertMode` → `.docCAlertMode` and
   propagate through `AlertDetector`, `DownHTMLVisitor`, `MudCore.swift`, and
   MudCore tests.
6. **App call sites**: update the settings panes, `MudApp.swift`,
   `DocumentContentView.swift`, `QuickLook/PreviewProvider.swift`,
   `DocumentWindowController.swift`. Replace the four direct- `UserDefaults`
   call sites in `AppDelegate.swift`, `DocumentWindowController.swift`, and
   `CommandLineInstaller.swift` with `MudPreferences.shared` accessors.
7. **UI label**: `DownModeSettingsView.swift:15` "Word wrap" → "Wrap lines".
8. **Tests**: rename test functions and body references; bump catalog count to
   `25`; add round-trip + migration tests for the four new keys.
9. **Docs**: update `Doc/AGENTS.md` line 334.
10. **Smoke test**: launch a dev build with legacy `Mud-*` keys seeded into
    `.standard`; verify migration to the final names, app behavior unchanged,
    and the Quick Look preview reads expected values from the mirror.


## Follow-up cleanup

Same schedule as the main MudPreferences plan: once a release has shipped with
migration in place and installs have upgraded, strip every `legacyStandardKey`
entry along with `migrateLegacyKeys()`. `syncMirror()` stays — it still serves
the external `defaults write` while-app-not-running case.
