Plan: Auto-Update via Sparkle
===============================================================================

> Status: Planning


## Context

Mud's direct distribution (Developer ID signed, notarized DMGs via GitHub
Releases) has no update mechanism. Users must manually check for new releases.
The conventional solution for macOS apps outside the App Store is Sparkle 2.

The Mac App Store build must not contain Sparkle at all — Apple rejects apps
that bundle update frameworks, even if the code is never called. This rules out
SPM (which unconditionally links and embeds the dynamic framework for all build
configurations). Instead, Sparkle is embedded manually with per-configuration
linker flags, so the App Store binary never references it.


## Approach

Embed Sparkle 2 as a manually managed framework (git-ignored, downloaded in CI)
with per-configuration build settings. Create four build configurations:
Debug-AppStore, Release-AppStore (for App Store), and Debug-Direct,
Release-Direct (for direct distribution). Only the Direct configurations link
and embed the framework. All Sparkle-related code is wrapped in `#if SPARKLE`.
Two Xcode schemes select the appropriate configurations.

On launch (Sparkle builds only), initialize the updater. Add a "Check for
Updates..." menu item and an "Updates" settings pane. Modify the release
workflow to EdDSA-sign the DMG and publish an appcast with release notes.


## Prerequisites (manual, one-time)

1. **Generate EdDSA key pair** using Sparkle's `generate_keys` tool.
2. **Store private key** as GitHub Actions secret `SPARKLE_PRIVATE_KEY`.
3. **Website deploy access** — generate a dedicated SSH key pair for CI
   deployment. Add the public key to the hosting server's `authorized_keys`.
   Store as GitHub Actions secrets: `WEBSITE_SSH_KEY` (private key),
   `WEBSITE_SSH_USER` (username), `WEBSITE_SSH_HOST` (hostname). Ensure the
   appcast destination directory exists on the server.
4. **Download Sparkle 2 locally** — run `.github/scripts/update-sparkle` (see
   section 5) to fetch and extract `Sparkle.framework` and CLI tools into
   `Vendor/Sparkle/`. This directory is git-ignored; CI downloads it fresh each
   build.


## Implementation

### 1. Build configurations and schemes

**Build configurations** — rename the existing Debug and Release configurations
to Debug-AppStore and Release-AppStore. Duplicate them to create Debug-Direct
and Release-Direct. Then set the following build settings on the Direct
configurations only:

| Build setting                         | Debug-Direct / Release-Direct only  |
| ------------------------------------- | ----------------------------------- |
| `SWIFT_ACTIVE_COMPILATION_CONDITIONS` | Add `SPARKLE`                       |
| `OTHER_LDFLAGS`                       | Add `-framework Sparkle`            |
| `FRAMEWORK_SEARCH_PATHS`              | Add `$(PROJECT_DIR)/Vendor/Sparkle` |

Leave Debug-AppStore and Release-AppStore unchanged — they never reference
Sparkle.

**Schemes:**

- **Mud - Direct** — uses Debug-Direct (Run) and Release-Direct (Archive). For
  direct distribution builds.
- **Mud - AppStore** — uses Debug-AppStore (Run) and Release-AppStore
  (Archive). For Mac App Store submissions.

**Embed framework** — add a Copy Files build phase (Destination: Frameworks)
that copies `Sparkle.framework` into the app bundle, with a Run Script
condition that skips the copy for non-Sparkle configurations:

```bash
if [ "$CONFIGURATION" = "Debug-AppStore" ] || [ "$CONFIGURATION" = "Release-AppStore" ]; then
    rm -rf "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle.framework"
fi
```

This is a belt-and-suspenders safety net — the App Store configurations don't
link Sparkle, so the framework would be dead weight even if accidentally
copied.


### 2. Info.plist keys

Add to `App/Info.plist`:

- `SUFeedURL` → `https://apps.josephpearson.org/mud/appcast.xml`
- `SUPublicEDKey` → _(generated public key)_
- `SUEnableAutomaticChecks` → `true`

These keys are inert without the Sparkle framework, so they can be present in
both configurations.


### 3. App code (4 files)

All Sparkle imports and usage are wrapped in `#if SPARKLE`. In App Store
builds, this code compiles out entirely.

**`App/AppDelegate.swift`** — Conditionally import Sparkle. In
`applicationDidFinishLaunching`, create `SPUStandardUpdaterController`. Expose
the `SPUUpdater` instance via a property.

```swift
#if SPARKLE
import Sparkle
#endif

// On AppDelegate:
#if SPARKLE
private var updaterController: SPUStandardUpdaterController?
var updater: SPUUpdater? { updaterController?.updater }
#endif

// In applicationDidFinishLaunching:
#if SPARKLE
updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)
#endif
```

**`App/CheckForUpdatesView.swift`** _(new)_ — Standard Sparkle 2 + SwiftUI
pattern: a view model that observes `updater.canCheckForUpdates` via Combine,
and a `Button` view for the menu item. The entire file is wrapped in
`#if SPARKLE`.

```swift
#if SPARKLE
import SwiftUI
import Sparkle
import Combine

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let updater: SPUUpdater?
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater?) {
        self.updater = updater
        cancellable = updater?.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func checkForUpdates() { updater?.checkForUpdates() }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater?) {
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") { viewModel.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}
#endif
```

**`App/MudApp.swift`** — Add "Check for Updates..." after the Settings item,
guarded by `#if SPARKLE`:

```swift
CommandGroup(replacing: .appSettings) {
    Button("Settings...") { ... }
        .keyboardShortcut(",", modifiers: .command)

    #if SPARKLE
    CheckForUpdatesView(updater: appDelegate.updater)
    #endif
}
```

**`App/Settings/SettingsView.swift`** — Add `.updates` case to `SettingsPane`.
Use a computed `visibleCases` that conditionally includes it via `#if SPARKLE`.
Wire up `UpdateSettingsView` in the detail switch.

**`App/Settings/UpdateSettingsView.swift`** _(new)_ — Settings pane with:

- Toggle: "Automatically check for updates" (bound to
  `updater.automaticallyChecksForUpdates`)
- Toggle: "Automatically download updates" (bound to
  `updater.automaticallyDownloadsUpdates`)
- "Check Now" button

The entire file is wrapped in `#if SPARKLE`. Follows the established pattern:
`Form { ... }.formStyle(.grouped).padding(.top, -18)`.


### 4. Release notes

Sparkle displays per-release notes in its update dialog. The appcast XML
supports an inline `<description>` element per release item containing HTML.

**Source:** maintain a `CHANGELOG.md` at the repo root. Each release gets a
`## Version X.Y.Z` heading with a bulleted list of changes. The workflow
extracts the section for the current tag, renders it to HTML, and embeds it in
the appcast.

```markdown
## Version 1.2.0

- Added table of contents sidebar
- Fixed scroll position preservation when toggling modes
- Improved syntax highlighting for Swift code blocks
```

The workflow step (see below) uses `sed` to extract the relevant section and
`cmark-gfm` (available on GitHub Actions runners) to convert it to HTML.


### 5. Release workflow scripts

The release workflow's Sparkle-related logic lives in two scripts under
`.github/scripts/`, testable locally outside of CI.

**`.github/scripts/update-sparkle`** — downloads a Sparkle release and extracts
the framework and CLI tools. Used by both developers (for the framework) and CI
(for the framework + `sign_update` tool). Accepts an optional version argument
(defaults to `2.9.0`).

```bash
#!/usr/bin/env bash
set -euo pipefail

SPARKLE_VERSION="${1:-2.9.0}"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

echo "Downloading Sparkle ${SPARKLE_VERSION}..."
TMPDIR=$(mktemp -d)
curl -sL -o "${TMPDIR}/sparkle.tar.xz" "$URL"
tar xf "${TMPDIR}/sparkle.tar.xz" -C "$TMPDIR"

mkdir -p Vendor/Sparkle
rm -rf Vendor/Sparkle/Sparkle.framework
cp -R "${TMPDIR}/Sparkle.framework" Vendor/Sparkle/

mkdir -p Vendor/Sparkle/bin
cp "${TMPDIR}/bin/sign_update" Vendor/Sparkle/bin/
cp "${TMPDIR}/bin/generate_keys" Vendor/Sparkle/bin/

rm -rf "$TMPDIR"
echo "Sparkle ${SPARKLE_VERSION} installed to Vendor/Sparkle/"
```

**`.github/scripts/build-appcast`** — given a signed DMG, generates or updates
an `appcast.xml`. Designed to be run locally for testing or from CI. Reads
release notes from `CHANGELOG.md`.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: build-appcast <dmg-path> <version> <key-file> [existing-appcast]
#
# Outputs appcast.xml to stdout.
#
# Example (local):
#   .github/scripts/build-appcast Mud-v1.2.0.dmg 1.2.0 ~/sparkle_key > appcast.xml
#
# Example (CI):
#   .github/scripts/build-appcast "$DMG" "$VERSION" "$KEY_FILE" "$EXISTING" > appcast.xml

DMG="$1"
VERSION="$2"
KEY_FILE="$3"
EXISTING="${4:-}"

SIGN_UPDATE="Vendor/Sparkle/bin/sign_update"
DOWNLOAD_URL="https://github.com/joseph/mud/releases/download/v${VERSION}/$(basename "$DMG")"

# Sign the DMG
SIGNATURE=$("$SIGN_UPDATE" "$DMG" --ed-key-file "$KEY_FILE")
ED_SIG=$(echo "$SIGNATURE" | sed 's/.*edSignature="\([^"]*\)".*/\1/')
LENGTH=$(echo "$SIGNATURE" | sed 's/.*length="\([^"]*\)".*/\1/')

# Extract release notes from CHANGELOG.md
NOTES_MD=$(sed -n "/^## Version ${VERSION}$/,/^## /{/^## Version ${VERSION}$/d;/^## /!p}" \
  CHANGELOG.md 2>/dev/null || true)
if command -v cmark-gfm &>/dev/null; then
  NOTES_HTML=$(echo "$NOTES_MD" | cmark-gfm --extension table,autolink,strikethrough)
else
  # Fallback: wrap in <pre> if cmark-gfm isn't available
  NOTES_HTML="<pre>${NOTES_MD}</pre>"
fi

# Build XML item
ITEM="    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <pubDate>$(date -R)</pubDate>
      <description><![CDATA[${NOTES_HTML}]]></description>
      <enclosure
        url=\"${DOWNLOAD_URL}\"
        type=\"application/octet-stream\"
        sparkle:edSignature=\"${ED_SIG}\"
        length=\"${LENGTH}\" />
    </item>"

# Insert into existing appcast or create new one
if [ -n "$EXISTING" ] && [ -f "$EXISTING" ] && grep -q '<channel>' "$EXISTING"; then
  sed "/<\/channel>/i\\
${ITEM}" "$EXISTING"
else
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mud</title>
${ITEM}
  </channel>
</rss>
EOF
fi
```

Both scripts are added to `.gitignore` exceptions (the `Vendor/Sparkle/`
directory itself is ignored, but the scripts live in `.github/scripts/`).


### 6. Release workflow changes

Modify `.github/workflows/release.yml`:

**Update the scheme references** — the old `-scheme Mud` no longer exists.
Update both the "Resolve packages" and "Archive" steps:

```yaml
- name: Resolve packages
  run: |
    xcodebuild -resolvePackageDependencies \
      -project Mud.xcodeproj \
      -scheme "Mud - Direct"
```

```yaml
- name: Archive
  run: |
    xcodebuild archive \
      -project Mud.xcodeproj \
      -scheme "Mud - Direct" \
      -configuration Release-Direct \
      -archivePath "$RUNNER_TEMP/Mud.xcarchive" \
      CODE_SIGN_STYLE=Manual \
      "CODE_SIGN_IDENTITY=Developer ID Application" \
      DEVELOPMENT_TEAM=XVL2AFNXH5
```

Note: the `ENABLE_APP_SANDBOX=NO` command-line override that was in the
original workflow is no longer needed — the `Release-Direct` build
configuration now sets `ENABLE_APP_SANDBOX = NO` at the project level, along
with its own entitlements file (`App/MudDirect.entitlements`).

**Add a "Download Sparkle" step before "Resolve packages"** — this provides
both the framework (for the build) and `sign_update` (for appcast generation):

```yaml
- name: Download Sparkle
  run: .github/scripts/update-sparkle
```

**Add appcast steps after "Create GitHub release":**

```yaml
- name: Build and publish appcast
  env:
    SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
    WEBSITE_SSH_KEY: ${{ secrets.WEBSITE_SSH_KEY }}
    WEBSITE_SSH_USER: ${{ secrets.WEBSITE_SSH_USER }}
    WEBSITE_SSH_HOST: ${{ secrets.WEBSITE_SSH_HOST }}
  run: |
    VERSION=${GITHUB_REF#refs/tags/v}
    TAG=${GITHUB_REF#refs/tags/}
    DMG="Mud-${TAG}.dmg"

    # Write key files
    echo "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key"
    echo "$WEBSITE_SSH_KEY" > "$RUNNER_TEMP/deploy_key"
    chmod 600 "$RUNNER_TEMP/deploy_key"

    # Fetch existing appcast
    curl -sL -o "$RUNNER_TEMP/existing_appcast.xml" \
      "https://apps.josephpearson.org/mud/appcast.xml" 2>/dev/null || true

    # Build appcast
    .github/scripts/build-appcast \
      "$DMG" "$VERSION" "$RUNNER_TEMP/sparkle_key" \
      "$RUNNER_TEMP/existing_appcast.xml" \
      > appcast.xml

    # Publish
    scp -i "$RUNNER_TEMP/deploy_key" -o StrictHostKeyChecking=no \
      appcast.xml \
      "${WEBSITE_SSH_USER}@${WEBSITE_SSH_HOST}:mud/appcast.xml"

    # Clean up
    rm -f "$RUNNER_TEMP/sparkle_key" "$RUNNER_TEMP/deploy_key"
```


### 7. Documentation

Update `Doc/AGENTS.md` file quick reference to include:

- `CheckForUpdatesView.swift`
- `UpdateSettingsView.swift`
- `.github/scripts/update-sparkle`
- `.github/scripts/build-appcast`

Add to `.gitignore`:

```
Vendor/Sparkle/
```


## Why not SPM?

Sparkle's SPM package ships as a pre-built dynamic framework. When added via
SPM, Xcode unconditionally links and embeds the framework for all build
configurations — there is no per-configuration toggle. The Mach-O binary gets
an `LC_LOAD_DYLIB` load command referencing `Sparkle.framework`, which means:

- Stripping the framework from the bundle post-build causes a dyld crash at
  launch.
- Weak linking doesn't help — Apple rejects apps that weak-link frameworks they
  don't ship.
- SPM package traits (SE-0450) can't gate binary targets per build
  configuration.

Manual framework embedding with per-configuration `OTHER_LDFLAGS` is the
standard solution. The App Store binary never links Sparkle — no load command,
no framework in the bundle, no rejection.


## Files changed

| File                                    | Change                                                      |
| --------------------------------------- | ----------------------------------------------------------- |
| `Vendor/Sparkle/`                       | Git-ignored; framework downloaded by script and CI          |
| `Mud.xcodeproj/project.pbxproj`         | Build configs, schemes, framework embed phase, linker flags |
| `App/Info.plist`                        | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`     |
| `App/AppDelegate.swift`                 | `#if SPARKLE` updater controller init and property          |
| `App/MudApp.swift`                      | `#if SPARKLE` "Check for Updates..." menu item              |
| `App/CheckForUpdatesView.swift`         | New — menu button + view model (entire file `#if SPARKLE`)  |
| `App/Settings/SettingsView.swift`       | `.updates` pane (`#if SPARKLE`)                             |
| `App/Settings/UpdateSettingsView.swift` | New — update preferences pane (entire file `#if SPARKLE`)   |
| `CHANGELOG.md`                          | New — per-release notes in Markdown                         |
| `.gitignore`                            | Add `Vendor/Sparkle/`                                       |
| `.github/scripts/update-sparkle`        | New — download Sparkle framework + CLI tools                |
| `.github/scripts/build-appcast`         | New — sign DMG, extract release notes, output appcast XML   |
| `.github/workflows/release.yml`         | Download Sparkle, use Release-Sparkle config, build appcast |
| `Doc/AGENTS.md`                         | File quick reference                                        |


## Verification

### UI verification

1. Build with the **Mud - Direct** scheme — confirm "Check for Updates..."
   appears in app menu, and "Updates" appears in Settings sidebar.
2. Build with the **Mud - AppStore** scheme — confirm both are absent.
3. Inspect the App Store binary with `otool -L` — confirm no reference to
   `Sparkle.framework`.


### Local update flow (no publishing required)

Test the full update cycle without pushing a release to GitHub or an appcast to
Dreamhost:

1. **Generate a key pair** — run Sparkle's `generate_keys` tool. Note the
   public key.

2. **Build a "current" version** — set `CFBundleShortVersionString` to
   something low (e.g. `0.9.0`). Build, archive, and export a Developer ID
   signed DMG. Install it to `/Applications`.

3. **Build the "new" version** — restore the real version number. Build and
   export a second DMG.

4. **Create a local appcast** — use `sign_update` on the new DMG and construct
   an `appcast.xml` with the signature, length, and a `http://localhost:8080/`
   download URL.

5. **Serve locally** — place the DMG and `appcast.xml` in a directory and run:

   ```
   python3 -m http.server 8080
   ```

6. **Point the app at the local feed** — pass a launch argument:
   `-SUFeedURL http://localhost:8080/appcast.xml`.

7. **Launch the old build** — trigger "Check for Updates..." and verify Sparkle
   finds the new version, shows the release notes, downloads the DMG, and
   offers to install it.


### Production verification

1. Tag a real release — verify the workflow generates `appcast.xml` with
   release notes and uploads it to
   `https://apps.josephpearson.org/mud/appcast.xml`.
2. With the previous version installed, launch and trigger "Check for Updates"
   — verify Sparkle finds and offers the new version with the correct release
   notes.
