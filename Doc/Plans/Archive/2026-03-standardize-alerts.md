Plan: Standardize Alerts
===============================================================================

> Status: Complete


## Context

Mud renders alerts from two syntaxes: GFM (`[!NOTE]`) and DocC (`Note:`). The
prior implementation covered five GFM types and six DocC categories, but they
were not consistently aligned:

- `[!STATUS]` was missing from GFM (only the DocC form existed).
- `ToDo:` mapped to `.note` (should be `.status`) via the catch-all.
- Extended DocC aliases (e.g. `Remark:`, `Bug:`, `Experiment:`) were always
  rendered with no way to disable them.
- Down Mode showed all blockquotes with the same plain `md-blockquote` style,
  regardless of alert type.


## Definitions

**Common alerts** — the six canonical categories, each with a GFM and DocC
form:

| Category  | GFM            | DocC core form |
| --------- | -------------- | -------------- |
| Note      | `[!NOTE]`      | `Note:`        |
| Tip       | `[!TIP]`       | `Tip:`         |
| Important | `[!IMPORTANT]` | `Important:`   |
| Status    | `[!STATUS]`    | `Status:`      |
| Warning   | `[!WARNING]`   | `Warning:`     |
| Caution   | `[!CAUTION]`   | `Caution:`     |

**Extended DocC aliases** — non-canonical DocC asides that map to a common
category. Toggleable, on by default.

| Common category | Extended aliases                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Note            | Remark, Complexity, Author, Authors, Copyright, Date, Since, Version, SeeAlso, MutatingVariant, NonMutatingVariant |
| Status          | ToDo                                                                                                               |
| Tip             | Experiment                                                                                                         |
| Important       | Attention                                                                                                          |
| Warning         | Precondition, Postcondition, Requires, Invariant                                                                   |
| Caution         | Bug, Throws, Error                                                                                                 |

When extended alerts are disabled, extended aliases render as plain
blockquotes. Core aliases always render as styled alerts.


## Phase 1: Core rendering ✓

Extracted alert detection from `UpHTMLVisitor` into a new shared
`AlertDetector` struct with a `showExtendedAlerts` flag and separate `coreMap`
/ `extendedMap` lookups. Added `[!STATUS]` to the GFM tag list. Fixed DocC
mapping: `ToDo` → `.status`, `MutatingVariant` / `NonMutatingVariant` → `.note`
explicitly. `UpHTMLVisitor` now holds a stored `AlertDetector` and delegates
all blockquote detection to it.


## Phase 2: Settings and app wiring ✓

Added `showExtendedAlerts: Bool = true` to the four public `MudCore` render
functions. Wired the flag through `AppState` (persisted in `UserDefaults`) →
`DocumentContentView` (included in `displayContentID`) → both render calls.
Added a "Show extended DocC alerts" toggle in `UpModeSettingsView`.


## Phase 3: Down Mode ✓

`DownHTMLVisitor.EventCollector` now holds an `AlertDetector` (passed in from
`highlightAsTable(_:showExtendedAlerts:)`). `visitBlockQuote` applies
`md-blockquote md-alert-<category>` to detected alerts and emits `md-alert-tag`
spans over the `>` markers and tag text. Alert color custom properties moved
from `mud-up.css` into `mud.css` so both modes share them. `mud-down.css` gains
per-category `md-alert-tag` color rules.


## Files changed

| File                                                | Change                                                      |
| --------------------------------------------------- | ----------------------------------------------------------- |
| `Core/Sources/Core/Rendering/AlertDetector.swift`   | New. Shared detection logic                                 |
| `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`   | Remove private detection; use `AlertDetector`               |
| `Core/Sources/Core/Rendering/DownHTMLVisitor.swift` | Detect alerts in `visitBlockQuote`; emit `md-alert-tag`     |
| `Core/Sources/Core/MudCore.swift`                   | Add `showExtendedAlerts` parameter to four public functions |
| `App/MudApp.swift`                                  | Add `showExtendedAlerts` published property + persistence   |
| `App/DocumentContentView.swift`                     | Include flag in `displayContentID`; pass to renderers       |
| `App/Settings/UpModeSettingsView.swift`             | Add extended-alerts toggle                                  |
| `Core/Sources/Core/Resources/mud.css`               | Move alert color variables here (shared between modes)      |
| `Core/Sources/Core/Resources/mud-down.css`          | Alert `md-alert-tag` color rules per category               |
