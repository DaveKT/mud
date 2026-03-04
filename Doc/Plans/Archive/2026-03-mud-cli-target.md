Plan: Mud CLI target
===============================================================================

> Status: Complete


## Context

The original CLI feature embedded argument parsing and HTML rendering directly
in the Mud app binary, activated via symlink detection in `AppDelegate`. This
broke under sandboxing (no process spawning, no document opening via CLI args)
and left dead code in the app target for sandboxed builds.

The new approach separates concerns cleanly:

- `mud` (`App/CLI/main.swift`, Xcode target "Mud CLI") — a standalone Swift
  executable that renders Markdown to HTML
- `mud.sh` (`App/CLI/mud.sh`) — a shell dispatcher (the user-facing `mud`
  command) that routes to the `mud` CLI for rendering or to `open -a` for GUI
  use
- The Mud app binary has no CLI awareness whatsoever


## Bundle layout

```
Mud.app/
  Contents/
    MacOS/
      Mud              ← GUI app (no CLI code)
    Helpers/
      mud              ← CLI renderer ("Mud CLI" Xcode target, PRODUCT_NAME=mud)
    Resources/
      mud.sh           ← shell dispatcher (the installed symlink target)
      …
```

The CLI binary lives in `Contents/Helpers/` rather than `Contents/MacOS/` to
avoid a case-insensitive filename collision between `mud` and `Mud` on macOS's
default HFS+ filesystem.


## What changed

**New files:**

- `App/CLI/main.swift` — the `mud` CLI; argument parsing and rendering via
  MudCore, no AppKit or SwiftUI. Adapted from the removed
  `CommandLineInterface.swift`. Same flags (`-u`/ `-d`/ `-b`/ `-f`/ `--theme`/
  etc.), same exit codes (0/1/2), same `"mud: "` error prefix.

- `App/CLI/mud.sh` — resolves its own real path (following symlinks), then
  routes to `../Helpers/mud` when any rendering flag is present, or to
  `open -a "$BUNDLE"` for GUI mode. Piped stdin with no render flags is written
  to a temp file and opened in the GUI.

**Removed:**

- `App/CommandLineInterface.swift` — deleted entirely
- CLI detection blocks in `AppDelegate.applicationWillFinishLaunching`

**Updated:**

- `App/CommandLineInstaller.swift` — symlink target is now
  `Bundle.main.resourceURL + "mud.sh"` instead of `Bundle.main.executablePath`
- `App/Settings/CommandLineSettingsView.swift` — manual-install path display
  updated to match

**Xcode project:**

- New "Mud CLI" target (`com.apple.product-type.tool`), `PRODUCT_NAME = mud`,
  `MACOSX_DEPLOYMENT_TARGET = 14.0`, `ENABLE_HARDENED_RUNTIME = YES`,
  `ENABLE_APP_SANDBOX = NO`. Sources via filesystem-synchronized `App/CLI/`
  group (exceptions exclude `mud.sh` from the CLI target, adding it to Mud's
  resources instead). MudCore linked as a package product dependency.
- Mud app target: "Mud CLI" added as a target dependency; Copy Files phase
  (`dstSubfolderSpec = 1` / Wrapper, `dstPath = "Contents/Helpers"`) copies the
  `mud` product into the bundle. Run Script phase `chmod +x` ensures `mud.sh`
  is executable after the resources copy.


## Verification

### Bundle structure

```sh
ls Mud.app/Contents/MacOS/        # Mud (only)
ls Mud.app/Contents/Helpers/      # mud
ls -l Mud.app/Contents/Resources/mud.sh  # -rwxr-xr-x
```


### CLI directly

```sh
echo "# Hello" | Mud.app/Contents/Helpers/mud -u   # full HTML doc on stdout
Mud.app/Contents/Helpers/mud -d README.md | head -5 # syntax-highlighted HTML
Mud.app/Contents/Helpers/mud --version              # mud 0.1.0
Mud.app/Contents/Helpers/mud --help                 # usage text
Mud.app/Contents/Helpers/mud README.md              # exit 1 + usage (no mode)
```


### Dispatcher

```sh
Mud.app/Contents/Resources/mud.sh -u README.md | head -3   # renders via mud
echo "# Hi" | Mud.app/Contents/Resources/mud.sh -d         # stdin render
Mud.app/Contents/Resources/mud.sh README.md                # opens in GUI
Mud.app/Contents/Resources/mud.sh                          # opens Mud.app
```


### Symlink flow

```sh
ln -sf /path/to/Mud.app/Contents/Resources/mud.sh /tmp/test-mud
/tmp/test-mud -u README.md | head -3    # renders via mud CLI
/tmp/test-mud README.md                 # opens in GUI
```


### Settings pane

- Non-sandboxed: Install button symlinks to `mud.sh`; installed `mud` command
  works end-to-end.
- Sandboxed: manual-install instruction shows `.../Resources/mud.sh` path.


### App launch

`Mud.app` opens normally with no CLI-related console output.
