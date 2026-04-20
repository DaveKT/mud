Plan: Preference Key Conventions
===============================================================================

> Status: Complete

Normalize every `UserDefaults` key the app writes, and the Swift identifiers
that reference them, under a small set of rules: lowercase-hyphen persistence
strings, feature-based grouping, imperative shape for Bool preferences,
past-tense shape for internal state. Folded in the four legacy `Mud-*` keys
still outside `MudPreferences`, renamed keys that didn't fit the conventions,
established grouping prefixes for feature-scoped keys, and aligned Swift case
names with the grouped persistence strings.


## What shipped

- 25 preference keys under a grouped, lowercase-hyphen convention (`changes.*`,
  `up-mode.*`, `down-mode.*`, `sidebar.*`, `markdown.*`, `ui.*`, `internal.*`,
  plus four top-level app-global keys).
- Four keys formerly written directly to `UserDefaults.standard`
  (`hasLaunched`, `windowFrame`, `cliInstalled`, `cliSymlinkPath`) now route
  through `MudPreferences` under the `internal.*` group.
- Bool preferences use imperative verb-noun shape
  (`changes.show-git-waypoints`); internal Bool state uses past-tense
  (`internal.has-launched`); master-switch Bools use the `.enabled` suffix.
- Swift identifiers mirror the grouped persistence strings in grouped layers
  (`MudPreferences`, `AppState`, `MudPreferencesSnapshot`), and drop the group
  prefix in scope-implied layers (`RenderOptions`, `AlertDetector`,
  `DownHTMLVisitor`, `ViewToggle`).
- DocC casing fix: `doccAlertMode` → `docCAlertMode` everywhere in Swift.
- Down Mode's "Word wrap" toggle is labelled "Wrap lines" to match the new key
  name and to read as a direct imperative.
- Legacy `Mud-*` keys rename in place on launch via the existing
  `migrateLegacyKeys()` path; no code changes to the migration machinery — the
  rename is driven entirely by updating the enum's `legacyStandardKey`.


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
  rename there was the DocC casing fix: `doccAlertMode` → `docCAlertMode`.

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
   prefixes. Only the `ViewToggle.key` mapping updated to return the renamed
   `MudPreferences.Keys` case.


## Key catalog

25 keys total. "Default" column gives the hard-coded default when the key is
absent from storage.


### `changes.*` — diff display and change-tracking

| Swift case                   | Persistence string              | Default | Legacy key              |
| ---------------------------- | ------------------------------- | ------- | ----------------------- |
| `changesEnabled`             | `changes.enabled`               | `true`  | `Mud-TrackChanges`      |
| `changesShowInlineDeletions` | `changes.show-inline-deletions` | `false` | `Mud-InlineDeletions`   |
| `changesShowGitWaypoints`    | `changes.show-git-waypoints`    | `false` | `Mud-ShowGitWaypoints`  |
| `changesAutoExpandGroups`    | `changes.auto-expand-groups`    | `false` | `Mud-autoExpandChanges` |
| `changesWordDiffThreshold`   | `changes.word-diff-threshold`   | `0.25`  | `Mud-WordDiffThreshold` |

`auto-expand-groups`: the thing being expanded is change _groups_, not
individual changes — and "changes" would be redundant with the group prefix.


### `up-mode.*` — rendered-HTML view options

| Swift case                 | Persistence string             | Default | Legacy key               |
| -------------------------- | ------------------------------ | ------- | ------------------------ |
| `upModeZoomLevel`          | `up-mode.zoom-level`           | `1.0`   | `Mud-UpModeZoomLevel`    |
| `upModeAllowRemoteContent` | `up-mode.allow-remote-content` | `true`  | `Mud-AllowRemoteContent` |
| `upModeShowCodeHeader`     | `up-mode.show-code-header`     | `true`  | `Mud-codeHeader`         |


### `down-mode.*` — source view options

| Swift case                | Persistence string            | Default | Legacy key              |
| ------------------------- | ----------------------------- | ------- | ----------------------- |
| `downModeZoomLevel`       | `down-mode.zoom-level`        | `1.0`   | `Mud-DownModeZoomLevel` |
| `downModeShowLineNumbers` | `down-mode.show-line-numbers` | `true`  | `Mud-lineNumbers`       |
| `downModeWrapLines`       | `down-mode.wrap-lines`        | `true`  | `Mud-wordWrap`          |


### `sidebar.*` — sidebar state

| Swift case       | Persistence string | Default    | Legacy key           |
| ---------------- | ------------------ | ---------- | -------------------- |
| `sidebarEnabled` | `sidebar.enabled`  | `false`    | `Mud-SidebarVisible` |
| `sidebarPane`    | `sidebar.pane`     | `.outline` | `Mud-SidebarPane`    |


### `markdown.*` — parser options

| Swift case              | Persistence string         | Default     | Legacy key          |
| ----------------------- | -------------------------- | ----------- | ------------------- |
| `markdownDocCAlertMode` | `markdown.docc-alert-mode` | `.extended` | `Mud-DoccAlertMode` |

Single-key group established in anticipation of other parser toggles (Mermaid,
footnotes, etc.). `DocC` keeps proper-noun casing in Swift; the persistence
string stays `docc-alert-mode` for readability.


### `ui.*` — UI chrome and cross-mode layout

| Swift case                   | Persistence string              | Default         | Legacy key                     |
| ---------------------------- | ------------------------------- | --------------- | ------------------------------ |
| `uiUseHeadingAsTitle`        | `ui.use-heading-as-title`       | `true`          | `Mud-UseHeadingAsTitle`        |
| `uiFloatingControlsPosition` | `ui.floating-controls-position` | `.bottomCenter` | `Mud-FloatingControlsPosition` |
| `uiShowReadableColumn`       | `ui.show-readable-column`       | `false`         | `Mud-readableColumn`           |

Scope: chrome/layout _configuration_ (what's shown, where it sits, how it's
framed). Not "anything visual" — `theme` and `lighting` stay top-level as
app-global style selections.


### `internal.*` — app-owned bookkeeping

| Swift case       | Persistence string          | Default | Legacy key           |
| ---------------- | --------------------------- | ------- | -------------------- |
| `hasLaunched`    | `internal.has-launched`     | `false` | `Mud-HasLaunched`    |
| `windowFrame`    | `internal.window-frame`     | `nil`   | `Mud-WindowFrame`    |
| `cliInstalled`   | `internal.cli-installed`    | `false` | `Mud-CLIInstalled`   |
| `cliSymlinkPath` | `internal.cli-symlink-path` | `nil`   | `Mud-CLISymlinkPath` |

Swift case names stay unprefixed per the `internal.*` exception. These route
through the same `write(_:forKey:)` helper as the preferences, so they fan out
into the app-group suite. The Quick Look extension ignores them. Harmless.


### Top-level — app-global selections

| Swift case          | Persistence string   | Default           | Legacy key              |
| ------------------- | -------------------- | ----------------- | ----------------------- |
| `lighting`          | `lighting`           | `.auto`           | `Mud-Lighting`          |
| `theme`             | `theme`              | `.earthy`         | `Mud-Theme`             |
| `quitOnClose`       | `quit-on-close`      | `true`            | `Mud-QuitOnClose`       |
| `enabledExtensions` | `enabled-extensions` | (caller-supplied) | `Mud-EnabledExtensions` |


## Intentional Swift asymmetry

`MudPreferencesSnapshot` uses `markdownDocCAlertMode` because it's a grouped
layer (holds many unrelated prefs). `RenderOptions` uses `docCAlertMode`
without the `markdown` prefix because its entire scope is markdown rendering —
a `markdown.` prefix on every field would be redundant. The handoff in
`QuickLook/PreviewProvider.swift` and `App/DocumentContentView.swift` crosses
that boundary:

```swift
options.docCAlertMode = snapshot.markdownDocCAlertMode
```

That asymmetry is intentional. The name differs because the layer's scope
differs.


## Migration

Since MudPreferences hadn't shipped, every `legacyStandardKey` entry points
directly from the `Mud-*` legacy name to the final grouped persistence string —
no intermediate alias for public installs. Developers who were running
pre-merge dev builds with the intermediate-format keys (e.g. `sidebar-visible`,
`track-changes`) have orphaned entries that can be cleared with
`defaults delete org.josephpearson.Mud <old-name>` as needed.

`MudPreferencesMigration.swift` itself needed no code changes —
`migrateLegacyKeys()` walks `Keys.allCases` and renames anything with a
`legacyStandardKey` entry; the rename was driven entirely by updating the enum.


## Follow-up cleanup

Same schedule as the main MudPreferences plan: once a release has shipped with
migration in place and installs have upgraded, strip every `legacyStandardKey`
entry along with `migrateLegacyKeys()`. `syncMirror()` stays — it still serves
the external `defaults write` while-app-not-running case.
