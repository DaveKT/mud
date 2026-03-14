Plan: Auto-Update via Sparkle
===============================================================================

> Status: Underway


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

All prerequisites are complete.

1. ~~**Generate EdDSA key pair**~~ — done via
   `Vendor/Sparkle/bin/generate_keys`. Public key added to `App/Info.plist` as
   `SUPublicEDKey`.
2. ~~**Store private key**~~ — stored as GitHub Actions secret
   `SPARKLE_PRIVATE_KEY`.
3. ~~**Website deploy access**~~ — SSH key pair generated, public key added to
   server. Stored as GitHub Actions secrets: `WEBSITE_SSH_KEY`,
   `WEBSITE_SSH_USER`, `WEBSITE_SSH_HOST`. Appcast destination directory exists
   on the server.
4. ~~**Download Sparkle 2 locally**~~ — `.github/scripts/update-sparkle`
   created and run. Sparkle 2.9.0 framework and CLI tools installed to
   `Vendor/Sparkle/` (git-ignored).


## Implementation

### 1. Build configurations and schemes ✓

Done. Four build configurations on the Mud app target:

- **Debug-AppStore / Release-AppStore** — no Sparkle references.
- **Debug-Direct / Release-Direct** — `SPARKLE` compilation condition,
  `-framework Sparkle` linker flag, `$(PROJECT_DIR)/Vendor/Sparkle` framework
  search path.

Two shared schemes: **Mud - Direct** (Debug-Direct / Release-Direct) and **Mud
\- AppStore** (Debug-AppStore / Release-AppStore).

Copy Files build phase embeds `Sparkle.framework`, with a belt-and-suspenders
Run Script that strips it for AppStore configurations.


### 2. Info.plist keys ✓

Done. Added `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` to
`App/Info.plist`. These keys are inert without the Sparkle framework, so they
are present in both configurations.


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

Sparkle displays per-release notes in its update dialog. Rather than embedding
HTML inline in the appcast, use `<sparkle:releaseNotesLink>` to point at hosted
HTML pages. This keeps the appcast simple and gives us web-browsable release
notes as a bonus.

**Source:** `Doc/RELEASES.md` (already exists in the repo). Each release gets a
`## vX.Y.Z` heading followed by prose describing what changed. This is written
by hand as part of the release workflow — it's not a mechanical changelog, it's
user-facing copy.

**Rendering:** a Ruby script (`.github/scripts/build-release-notes`) extracts
each version's section from `Doc/RELEASES.md` and calls the Mud CLI to render
it to HTML. It produces two outputs:

- `Site/releases/vX.Y.Z.html` — per-version release notes page
- `Site/releases/history.html` — full release history (the entire
  `Doc/RELEASES.md` rendered)

The `Site/` directory is committed to the repo. CI uploads its contents to the
website alongside the appcast.

**Local release workflow:**

1. Update `MARKETING_VERSION` in `App/Info.plist`
2. Add a section to `Doc/RELEASES.md` with compelling prose
3. Run `.github/scripts/build-release-notes` to generate `Site/releases/` HTML
4. Commit as: `VERSION: X.Y.Z`
5. Merge to the `main` branch
6. Tag the commit as `vX.Y.Z`
7. Push the tag to GitHub to trigger the release workflow


### 5. Release workflow scripts

The release workflow's Sparkle-related logic lives in scripts under
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

**`.github/scripts/build-release-notes`** — Ruby script that reads
`Doc/RELEASES.md`, extracts each version section, and renders HTML via the Mud
CLI. Produces `Site/releases/vX.Y.Z.html` for each version and
`Site/releases/history.html` for the full document.

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Usage: build-release-notes [mud-cli-path]
#
# Reads Doc/RELEASES.md, extracts per-version sections, and renders HTML
# to Site/releases/ using the Mud CLI.
#
# The Mud CLI path defaults to the bundled location in Mud.app. Override
# with the first argument for CI or non-standard installs.

require "fileutils"

RELEASES_PATH = "Doc/RELEASES.md"
OUTPUT_DIR = "Site/releases"

mud_cli = ARGV[0] || "/Applications/Mud.app/Contents/Helpers/mud"

abort "#{RELEASES_PATH} not found" unless File.exist?(RELEASES_PATH)
abort "Mud CLI not found at #{mud_cli}" unless File.executable?(mud_cli)

content = File.read(RELEASES_PATH)

# Extract version sections (## vX.Y.Z ... up to next ## or EOF)
sections = content.scan(/^(## v\S+.*?)(?=^## |\z)/m)

FileUtils.mkdir_p(OUTPUT_DIR)

sections.each do |match|
  section = match[0].strip
  version = section[/^## (v\S+)/, 1]
  next unless version

  outfile = File.join(OUTPUT_DIR, "#{version}.html")
  IO.popen([mud_cli, "-u"], "r+") do |io|
    io.write(section)
    io.close_write
    File.write(outfile, io.read)
  end
  puts "  #{outfile}"
end

# Full history
history_file = File.join(OUTPUT_DIR, "history.html")
IO.popen([mud_cli, "-u"], "r+") do |io|
  io.write(content)
  io.close_write
  File.write(history_file, io.read)
end
puts "  #{history_file}"
```

**`.github/scripts/build-appcast`** — given a signed DMG, generates an
`appcast.xml` containing a single item for the current release. Uses
`<sparkle:releaseNotesLink>` pointing at the hosted per-version HTML page.

The appcast always contains only the latest release. Sparkle checks whether the
appcast has a version newer than what's installed, so a single-item appcast
works for users on any older version. This avoids fetching and merging with a
previous appcast from the website — eliminating a network dependency and the
risk of silently losing previous entries if the server is unreachable.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage: build-appcast <dmg-path> <version> <build-number> <key-file>
#
# Outputs appcast.xml to stdout.
#
# Sparkle compares sparkle:version against CFBundleVersion (the build number),
# and displays sparkle:shortVersionString to the user.
#
# Example (local):
#   .github/scripts/build-appcast Mud-v1.2.0.dmg 1.2.0 42 ~/sparkle_key > appcast.xml
#
# Example (CI):
#   .github/scripts/build-appcast "$DMG" "$VERSION" "$BUILD" "$KEY_FILE" > appcast.xml

DMG="$1"
VERSION="$2"
BUILD="$3"
KEY_FILE="$4"

SIGN_UPDATE="Vendor/Sparkle/bin/sign_update"
DOWNLOAD_URL="https://github.com/joseph/mud/releases/download/v${VERSION}/$(basename "$DMG")"
NOTES_URL="https://apps.josephpearson.org/mud/releases/v${VERSION}.html"

# Sign the DMG
SIGNATURE=$("$SIGN_UPDATE" "$DMG" --ed-key-file "$KEY_FILE")
ED_SIG=$(echo "$SIGNATURE" | sed 's/.*edSignature="\([^"]*\)".*/\1/')
LENGTH=$(echo "$SIGNATURE" | sed 's/.*length="\([^"]*\)".*/\1/')

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mud</title>
    <item>
      <title>Version ${VERSION}</title>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <pubDate>$(date -R)</pubDate>
      <sparkle:releaseNotesLink>${NOTES_URL}</sparkle:releaseNotesLink>
      <enclosure
        url="${DOWNLOAD_URL}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}"
        length="${LENGTH}" />
    </item>
  </channel>
</rss>
EOF
```

All three scripts live in `.github/scripts/` (not in the git-ignored
`Vendor/Sparkle/` directory).


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

**Add appcast and site deploy steps after "Create GitHub release":**

```yaml
- name: Build and publish appcast and site
  env:
    SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
    WEBSITE_SSH_KEY: ${{ secrets.WEBSITE_SSH_KEY }}
    WEBSITE_SSH_USER: ${{ secrets.WEBSITE_SSH_USER }}
    WEBSITE_SSH_HOST: ${{ secrets.WEBSITE_SSH_HOST }}
  run: |
    VERSION=${{ steps.version.outputs.version }}
    TAG=${{ steps.version.outputs.tag }}
    DMG="Mud-${TAG}.dmg"

    # Write key files
    echo "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key"
    echo "$WEBSITE_SSH_KEY" > "$RUNNER_TEMP/deploy_key"
    chmod 600 "$RUNNER_TEMP/deploy_key"

    # Build appcast (single-item, no fetch needed)
    .github/scripts/build-appcast \
      "$DMG" "$VERSION" "${{ github.run_number }}" \
      "$RUNNER_TEMP/sparkle_key" \
      > appcast.xml

    # Publish appcast and release notes
    scp -i "$RUNNER_TEMP/deploy_key" -o StrictHostKeyChecking=no \
      appcast.xml \
      "${WEBSITE_SSH_USER}@${WEBSITE_SSH_HOST}:mud/appcast.xml"
    scp -i "$RUNNER_TEMP/deploy_key" -o StrictHostKeyChecking=no \
      -r Site/releases/ \
      "${WEBSITE_SSH_USER}@${WEBSITE_SSH_HOST}:mud/releases/"

    # Clean up
    rm -f "$RUNNER_TEMP/sparkle_key" "$RUNNER_TEMP/deploy_key"
```


### 7. Documentation

`Vendor/Sparkle/` added to `.gitignore`. ✓

Still to do: update `Doc/AGENTS.md` file quick reference to include:

- `CheckForUpdatesView.swift`
- `UpdateSettingsView.swift`
- `.github/scripts/update-sparkle`
- `.github/scripts/build-appcast`
- `.github/scripts/build-release-notes`
- `Doc/RELEASES.md`
- `Site/releases/`


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

| File                                    | Change                                                      | Status |
| --------------------------------------- | ----------------------------------------------------------- | ------ |
| `Vendor/Sparkle/`                       | Git-ignored; framework downloaded by script and CI          | ✓      |
| `Mud.xcodeproj/project.pbxproj`         | Build configs, schemes, framework embed phase, linker flags | ✓      |
| `App/Info.plist`                        | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`     | ✓      |
| `.gitignore`                            | Add `Vendor/Sparkle/`                                       | ✓      |
| `.github/scripts/update-sparkle`        | New — download Sparkle framework + CLI tools                | ✓      |
| `App/AppDelegate.swift`                 | `#if SPARKLE` updater controller init and property          |        |
| `App/MudApp.swift`                      | `#if SPARKLE` "Check for Updates..." menu item              |        |
| `App/CheckForUpdatesView.swift`         | New — menu button + view model (entire file `#if SPARKLE`)  |        |
| `App/Settings/SettingsView.swift`       | `.updates` pane (`#if SPARKLE`)                             |        |
| `App/Settings/UpdateSettingsView.swift` | New — update preferences pane (entire file `#if SPARKLE`)   |        |
| `Doc/RELEASES.md`                       | Release notes in Markdown (already exists)                  |        |
| `Site/releases/`                        | Pre-rendered release notes HTML (generated by Ruby script)  |        |
| `.github/scripts/build-release-notes`   | New — Ruby script: extract + render release notes via Mud   |        |
| `.github/scripts/build-appcast`         | New — sign DMG, output appcast XML with releaseNotesLink    |        |
| `.github/workflows/release.yml`         | Download Sparkle, Release-Direct, appcast + site deploy     |        |
| `Doc/AGENTS.md`                         | File quick reference                                        |        |


## Verification

### UI verification

1. Build with the **Mud - Direct** scheme — confirm "Check for Updates..."
   appears in app menu, and "Updates" appears in Settings sidebar.
2. Build with the **Mud - AppStore** scheme — confirm both are absent.
3. Inspect the App Store binary with `otool -L` — confirm no reference to
   `Sparkle.framework`.


### Local update flow (no publishing required)

Test the full update cycle without pushing a release to GitHub. The existing
EdDSA key pair (public key in `Info.plist`, private key in the developer's
Keychain from `generate_keys`) is used throughout.

1. **Write the private key to a file** — `build-appcast` needs the EdDSA
   private key that matches the `SUPublicEDKey` in `Info.plist`. Use the
   original key saved during prerequisite setup (stored as the
   `SPARKLE_PRIVATE_KEY` GitHub Actions secret). Write it to a temporary file:

   ```
   echo '<paste the private key>' > /tmp/sparkle_key
   ```

2. **Build a "current" (old) version** — this is the version already installed
   on the machine that will discover the update. Make two temporary changes
   before building:

   - In `App/Info.plist`, change `SUFeedURL` to
     `http://localhost:8080/appcast.xml` (so the installed app checks the local
     server, not production — Sparkle reads this from the bundle plist, so it
     must be baked in at build time).
   - In the Xcode project, select the **Mud** target → Build Settings → search
     for `MARKETING_VERSION`. Change it to something low (e.g. `0.9.0`) in the
     **Release-Direct** column.

   Then build and copy to `/Applications`:

   - Product → Archive (uses the Mud - Direct scheme).
   - In Organizer, click Distribute App → Direct Distribution → Export.
   - Copy the exported `Mud.app` to `/Applications`.

3. **Build the "new" version** — restore `SUFeedURL` in `App/Info.plist` to
   `https://apps.josephpearson.org/mud/appcast.xml` and `MARKETING_VERSION` to
   its real value (e.g. `1.0.0`). Archive and export again as above. This time,
   create a DMG from the exported app (the appcast signs the DMG, not the bare
   .app):

   ```
   mkdir -p /tmp/mud-dmg
   cp -R /path/to/exported/Mud.app /tmp/mud-dmg/
   hdiutil create -volname Mud -srcfolder /tmp/mud-dmg \
     -ov -format UDZO Mud-v1.0.0.dmg
   rm -rf /tmp/mud-dmg
   ```

4. **Create a local appcast** — use the `build-appcast` script. It needs a
   `CHANGELOG.md` entry matching the version:

   ```
   .github/scripts/build-appcast Mud-v1.0.0.dmg 1.0.0 2 /tmp/sparkle_key \
     > /tmp/appcast.xml
   ```

   The third argument (`2`) is the build number — it must be higher than the
   installed app's `CFBundleVersion` (`1`).

   Then edit `/tmp/appcast.xml` to change the download URL to
   `http://localhost:8080/Mud-v1.0.0.dmg`.

5. **Serve locally** — place the DMG and appcast in a directory and run:

   ```
   mkdir -p /tmp/mud-update
   cp Mud-v1.0.0.dmg /tmp/appcast.xml /tmp/mud-update/
   cd /tmp/mud-update && python3 -m http.server 8080
   ```

6. **Launch the old build** — run the installed 0.9.0 build from
   `/Applications`. Trigger "Check for Updates..." and verify Sparkle finds the
   new version, shows the release notes, downloads the DMG, and offers to
   install it.

7. **Clean up** — delete the temporary key file:

   ```
   rm -f /tmp/sparkle_key
   ```


### Production verification

1. Tag a real release — verify the workflow generates `appcast.xml` with
   release notes and uploads it to
   `https://apps.josephpearson.org/mud/appcast.xml`.
2. With the previous version installed, launch and trigger "Check for Updates"
   — verify Sparkle finds and offers the new version with the correct release
   notes.
