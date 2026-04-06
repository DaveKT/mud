Plan: Git Waypoints
===============================================================================

> Status: Planning


## Context

The "Changes since…" menu currently shows time-based waypoints (reload
snapshots) and the initial/accepted baselines. For documents tracked in Git, we
can show much richer history: the staged version, the last committed version,
recent commits, and the first commit. This gives users an easy way to diff
their current edits against any point in the file's Git history.

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

```
 (7) changes since last accepted
     … at 10:19am
─────────────────────────────────
 (3) changes since 1 minute ago
     … at 10:32am
─────────────────────────────────
(11) changes since document opened
     … at 9:52am
─────────────────────────────────  ← new section
 (2) since last staged
 (4) since commit abc1234
     … Fix heading levels
     … at 9am yesterday
 (7) since commit def5678
     … Refactor image handling
     … at 3pm March 27
(12) since commit 0a1b2c3
     … Initial commit
     … at 12am March 13
```

Git entries that would show 0 changes are omitted. "since last staged" is also
omitted when the index content matches HEAD (no staged changes to speak of).


## Design

### External waypoints in Core

Rather than adding git-specific `Waypoint.Kind` cases, add a generic
`.external(label: String, detail: String?)` kind. Core stays git-agnostic — it
just knows that some waypoints come from outside the normal reload flow. The
App layer creates these waypoints with git-specific labels.

This means git waypoints flow through the existing pipeline: `menuItems()`,
`selectBaseline(_:)`, and `activeBaseline` all work unchanged. No parallel
types or selection paths needed.


### ChangeMenuItem additions

Add two fields:

- `detail: String?` — optional second-line text (commit message for git items,
  nil for time-based items). Commit timestamps use the existing `timestamp`
  field and `shortTimestamp` formatter.
- `isExternal: Bool` — true for external waypoints, used by the popover to
  split them into a separate section


### GitProvider in App

A new class that runs `git` commands via `Process` and returns `[Waypoint]`
with `.external` kind. Runs off the main thread. Called after each
`loadFromDisk()` when the feature is enabled.


## Implementation

### Step 1: Expand Waypoint.Kind and ChangeMenuItem (Core)

**`Core/Sources/Core/ChangeTracker.swift`**

1. Add `.external(label: String, detail: String?)` to `Waypoint.Kind`.

2. Add `detail: String?` and `isExternal: Bool` to `ChangeMenuItem` (default
   `nil` and `false`).

3. Add methods to manage external waypoints:

   ```swift
   public func setExternalWaypoints(_ waypoints: [Waypoint]) {
       self.waypoints.removeAll { if case .external = $0.kind { true } else { false } }
       self.waypoints.append(contentsOf: waypoints)
       cachedMenuItems = nil
       // Reset baseline if it pointed to a now-removed external waypoint.
       if let id = activeBaselineID,
          !self.waypoints.contains(where: { $0.id == id }) {
           selectBaseline(nil)
       }
   }
   ```

4. Update `computeMenuItems()` to append an external section after the existing
   sections. For each external waypoint, compute the diff and skip if
   `groupCount == 0`. Set `isExternal: true` and populate `detail`.


### Step 2: Add setting to AppState

**`App/AppState.swift`**

- `@Published var showGitWaypoints: Bool` (default `false`)
- Key: `"Mud-ShowGitWaypoints"`
- `saveShowGitWaypoints()` method
- The property and its persistence are unconditional (no `#if`). The flag gates
  the code that _acts on_ the setting, not the setting itself.


### Step 3: Add toggle in DebuggingSettingsView

**`App/Settings/DebuggingSettingsView.swift`**

In the "Change tracking" section, add a toggle wrapped in `#if GIT_PROVIDER`:

```swift
#if GIT_PROVIDER
Toggle(isOn: /* binding */) {
    Text("Git waypoints")
    Text("Show comparisons against git history in the changes menu.")
}
#endif
```


### Step 4: Create GitProvider

**`App/GitProvider.swift`** (new file, entire file wrapped in
`#if GIT_PROVIDER`)

```
GitProvider
├── init(fileURL: URL)
├── queryWaypoints(currentContent: String) -> [Waypoint]
└── private helpers
    ├── repoRoot() throws -> URL
    ├── relativePath(in repoRoot: URL) -> String
    ├── run(_ args: [String], in dir: URL) throws -> String
    ├── stagedContent(relativePath:dir:) throws -> String
    ├── recentCommits(relativePath:dir:limit:) throws -> [CommitInfo]
    └── contentAtCommit(hash:relativePath:dir:) throws -> String
```

`CommitInfo` is a lightweight struct: `hash`, `date`, `message`.

**Git commands:**

| Purpose           | Command                                           |
| ----------------- | ------------------------------------------------- |
| Repo root         | `git rev-parse --show-toplevel`                   |
| Staged content    | `git show :<relative-path>`                       |
| Staged mtime      | `git ls-files --debug -- <path>` (parse `mtime:`) |
| Recent commits    | `git log --format=%H%x00%aI%x00%s -n 5 -- <path>` |
| Content at commit | `git show <hash>:<relative-path>`                 |

**`queryWaypoints` algorithm:**

1. Get repo root. Bail if not in a git repo.

2. Compute relative path.

3. Fetch staged content and commit log (can be concurrent).

4. For each commit hash, fetch content via `git show`.

5. Build waypoints, deduplicating by content:

   - **Staged**: include only if staged content differs from both
     `currentContent` and HEAD content.
   - **Commits** (reverse chronological): include if content differs from
     `currentContent` and from all previously included contents.

6. Return `[Waypoint]` with `.external(label:detail:)` kind.

All entries use the existing `shortTimestamp` formatter for timestamps. Staged
gets its timestamp from the index mtime (the file's modification time when it
was staged — retrieved via `git ls-files --debug`). Commits get theirs from the
author date in the log output.

| Entry  | Label                        | Detail line 1 | Detail line 2         |
| ------ | ---------------------------- | ------------- | --------------------- |
| Staged | `"since last staged"`        | (none)        | `at {shortTimestamp}` |
| Commit | `"since commit {shortHash}"` | `{message}`   | `at {shortTimestamp}` |

Short hash = first 7 characters.


### Step 5: Wire up in DocumentContentView

**`App/DocumentContentView.swift`**

After `changeTracker.update(parsed)` in `loadFromDisk()`, call
`refreshGitWaypoints`. The entire method is wrapped in `#if GIT_PROVIDER`:

```swift
#if GIT_PROVIDER
private func refreshGitWaypoints(for text: String) {
    guard appState.showGitWaypoints,
          !fileURL.isBundleResource else {
        changeTracker.setExternalWaypoints([])
        return
    }
    let url = fileURL
    let tracker = changeTracker
    Task.detached {
        let provider = GitProvider(fileURL: url)
        let waypoints = provider.queryWaypoints(currentContent: text)
        await MainActor.run {
            tracker.setExternalWaypoints(waypoints)
        }
    }
}
#endif
```

Also observe `appState.$showGitWaypoints` — when toggled off, clear external
waypoints immediately.


### Step 6: Update ChangesSincePopover

**`App/ChangesFeature.swift`**

Add a computed property for git items:

```swift
private var gitItems: [ChangeMenuItem] {
    items.filter { $0.isExternal }
}
```

Exclude external items from `timeBucketItems` and `documentOpenedItem`.

Add a git section to the body (after "since document opened"):

```swift
if !gitItems.isEmpty {
    Divider().padding(.vertical, 4)
    ForEach(...) { item in
        menuItemRow(item)
    }
}
```

Update `menuItemContent` to handle external items. Git commit items show two
detail lines (message + timestamp); staged items show no detail; regular items
show only the timestamp:

```swift
if let detail = item.detail {
    Text("… \(detail)")
        .font(.caption).foregroundStyle(.secondary)
    Text("… at \(item.timestamp.shortTimestamp)")
        .font(.caption).foregroundStyle(.secondary)
} else if !item.isExternal {
    Text("… at \(item.timestamp.shortTimestamp)")
        .font(.caption).foregroundStyle(.secondary)
}
```


### Step 7: Update AGENTS.md

Add `GitProvider.swift` to the App key files section.


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


## Performance

- Git queries run on a detached task (no main-thread blocking)
- Results are cached via the existing `cachedMenuItems` mechanism
- `setExternalWaypoints` invalidates the cache; next popover open recomputes
- Git is re-queried on each `loadFromDisk()` (file change or manual reload) —
  this is the right cadence since git state may change between reloads
- Total git process calls per refresh: ~6-8 (repo root, log, first commit,
  staged content, plus content at each commit hash)


## Testing

- **ChangeTracker tests**: `setExternalWaypoints` adds/removes/replaces
  external waypoints; menu includes external section; 0-change externals
  omitted; baseline reset when external waypoint removed
- **GitProvider tests**: create a temp git repo in setUp, verify waypoints for
  staged/committed/historical content; verify deduplication; verify empty
  result for non-git directories
- **Manual testing**: open a git-tracked .md file with the toggle on; verify
  popover shows git section; select a git waypoint and verify diff renders;
  toggle off and verify section disappears; test with untracked file
