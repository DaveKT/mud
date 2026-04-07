Plan: Git Waypoints
===============================================================================

> Status: Complete


## Context

The "Changes since…" menu currently shows time-based waypoints (reload
snapshots) and the initial/accepted baselines. For documents tracked in Git, we
can show much richer history: the staged version and recent commits. This gives
users an easy way to diff their current edits against any point in the file's
Git history.

This is an optional, experimental feature. It requires a non-sandboxed build
and an explicit opt-in via the Debugging settings. Sandboxed builds cannot run
`git`, so the feature is hidden entirely.

All git-related code is compiled out of App Store builds using a `GIT_PROVIDER`
build flag, following the same pattern as `#if SPARKLE` for the auto-update
feature. This avoids App Store review concerns about `Process` usage and
`/usr/bin/git` string literals in the binary. The flag is defined only in the
Direct distribution build configurations.


## Menu structure

When enabled and the file is in a Git repository, a new section appears at the
bottom of the popover. Only entries with actual differences are shown:

A new git section appears after "since document opened" with a divider. It
shows a "since last staged" entry (when it has changes) and up to 5 recent
commits with change counts, commit messages (`bubble` icon), and timestamps
(`calendar` icon). Commit entries are always shown (even with 0 changes) so the
full history is visible.


## Design

### External waypoints in Core

A generic `.external(label: String, detail: String?)` waypoint kind keeps Core
git-agnostic. Git waypoints flow through the existing `menuItems()`,
`selectBaseline(_:)`, and `activeBaseline` pipeline unchanged.


### ChangeMenuItem additions

Two fields: `detail: String?` (commit message for git items) and
`isExternal: Bool` (for popover section splitting). Both default to `nil` /
`false`, so existing call sites are untouched.


### GitProvider in App

`GitProvider` runs `git` commands via `Process` and returns `[Waypoint]` with
`.external` kind. Runs off the main thread. Called after each `loadFromDisk()`
when the feature is enabled.


## Implementation

### Step 1: Expand Waypoint.Kind and ChangeMenuItem (Core) ✓

Added `.external(label:detail:)` to `Waypoint.Kind` (with explicit `Equatable`
conformance). Added `detail` and `isExternal` fields to `ChangeMenuItem` with
an explicit `public init` (defaults preserve backward compatibility). Added
`setExternalWaypoints(_:)` to `ChangeTracker`. Updated `computeMenuItems()` to
append an external section (0-change filter temporarily disabled). Fixed
time-bucket query to skip external waypoints. Waypoint gained an explicit
`public init` for cross-module construction. Tests added.


### Step 2: Add setting to AppState ✓

Added `showGitWaypoints: Bool` (default `false`) with key
`"Mud-ShowGitWaypoints"` and `saveShowGitWaypoints()` method. Unconditional —
no `#if` guard on the property itself.


### Step 3: Add toggle in DebuggingSettingsView ✓

"Git waypoints" toggle in the "Change tracking" section, wrapped in
`#if GIT_PROVIDER`.


### Step 4: Create GitProvider ✓

New `App/GitProvider.swift`, entire file wrapped in `#if GIT_PROVIDER`.
Queries: repo root, staged content + index mtime, recent commits (up to 5),
content at each commit. Deduplicates by content. Uses git's `%x00` format
escape (not a literal null byte) for field separation in log output. The staged
waypoint is only emitted when it produces at least one block-level change group
against the current content (checked via `MudCore.computeChanges`).


### Step 5: Wire up in DocumentContentView ✓

`refreshGitWaypoints(for:)` called after `changeTracker.update(parsed)` in
`loadFromDisk()`. Observes `appState.$showGitWaypoints` to refresh or clear.
All wrapped in `#if GIT_PROVIDER`.


### Step 6: Update ChangesSincePopover ✓

Popover splits items into non-external (sections 1–3) and external (git
section). Git items appear after "since document opened" with a divider.
Timestamp lines use a `calendar` icon; commit message lines use a `bubble` icon
(both as HStack with 4pt spacing). Commit items show two detail lines (message
\+ timestamp); staged items show only timestamp.


### Step 7: Update AGENTS.md ✓

Added `GitProvider.swift` to the App key files section.


### Step 8: Build flag ✓

`GIT_PROVIDER` added to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in both
Debug-Direct and Release-Direct configurations in the Xcode project file.


## Edge cases

- **git not installed**: `Process` throws → `queryWaypoints` returns `[]`
- **File not tracked**: `git show` / `git log` fail → returns `[]`
- **File newly created (no commits)**: only staged waypoint possible
- **Detached HEAD**: works fine, `HEAD` still resolves
- **File renamed**: renames within the commit window may miss older history
- **Shallow clone**: shows whatever history is available
- **Feature toggled off**: `setExternalWaypoints([])` clears immediately
- **Active baseline was git waypoint that disappeared**: `setExternalWaypoints`
  resets baseline to default
- **Null bytes in Process args**: use git's `%x00` format escape, not literal
  `\u{0000}` (which truncates C strings)


## Performance

- Git queries run on a detached task (no main-thread blocking)
- Results are cached via the existing `cachedMenuItems` mechanism
- `setExternalWaypoints` invalidates the cache; next popover open recomputes
- Git is re-queried on each `loadFromDisk()` (file change or manual reload) —
  this is the right cadence since git state may change between reloads
- Total git process calls per refresh: ~6-8 (repo root, log, staged content,
  staged mtime, plus content at each commit hash)
