Plan: Quick Look Extension
===============================================================================

> Status: Underway

Add a macOS Quick Look extension so Finder's space-bar preview of a Markdown
file shows Mud's Mark Up rendering. Deliberately minimal — no interactive
controls, no mode toggle, no settings UI.


## Goals

- Preview `.md` (and friends) in Finder with Mud's rendered output
- Reuse MudCore — no separate rendering path
- Preview-relevant preferences follow the main app (theme, zoom, view toggles,
  allow-remote-content, enabled extensions, DocC alert mode)


## Non-goals

- Mode toggle (Mark Up / Mark Down). The app does that.
- Custom chrome — buttons, tabs, sidebar
- Live settings updates while the preview is open
- Find, outline, change tracking, anything interactive
- Honoring the app's lighting override (bright/dark). The rendered HTML only
  expresses `@media (prefers-color-scheme: dark)`, and the app's bright/dark
  override is applied via `NSAppearance` on the window — a knob Quick Look
  doesn't give us. Previews follow system lighting. Revisit if/when MudCore
  gains a class-based lighting override.
- Thumbnail provider. `QLThumbnailProvider` is a separate extension point,
  invoked by Finder's icon-preview pipeline rather than the spacebar preview.
  It's the natural follow-up once this plan ships, in its own plan.


## Approach — `QLPreviewProvider`, not `QLPreviewingController`

Two Quick Look paths exist. We pick the data-based one:

- **`QLPreviewProvider`** (chosen) — return HTML bytes in a `QLPreviewReply`.
  The system renders. No custom AppKit views.
- **`QLPreviewingController`** — own an `NSViewController` and `WKWebView`.
  Required only for interactive controls. Not needed here. Worth noting as a
  fallback: it's also the only path that gives us a configurable
  `WKUserContentController`, so if the sandboxed QL WebView ever rejects our
  inlined JS (mermaid, highlight.js) we'd be forced back onto it.

System chrome (filename, share, "Open with Mud") is drawn by Quick Look and is
free. Nothing else is needed.


### Debugging gotcha — third-party UTI-claim pollution

During bring-up we spent many hours chasing a bug where our extension (and
every other third-party `.md` Quick Look previewer on the machine) was never
invoked. Finder rendered plain text; the log stream showed Apple's built-in
`QLPreviewGenerationExtension` plus `com.apple.qldisplay.Text` winning the
selection every time. Neither `QLPreviewProvider` nor `QLPreviewingController`
overcame it.

Root cause: **MacVim** had been installed and was declaring `UTExportedType`
ownership of `net.daringfireball.markdown` in its Info.plist, with a
conformance override that pinned the UTI as `public.plain-text`. Because
exports win over imports in LaunchServices, MacVim's (incorrect) ownership
claim overrode the actual Markdown UTI conformance chain, and Quick Look
happily routed `.md` straight to the plain-text display bundle — bypassing any
previewer, including Apple's own, that would otherwise handle it.

Only an explicit UTI exporter with a claim conflict can cause this, but once it
happens the symptoms are indistinguishable from "Tahoe broke third-party QL."
If future debugging shows the same pattern (extension registered, log stream
shows `QLPreviewGenerationExtension` + `com.apple.qldisplay.Text` always
winning, and _other_ known-working `.md` previewers also fail), look at
`lsregister -dump` for rogue exporters of the UTI.


## New target

- `QuickLook/` — `.appex` target, principal class conforming to
  `QLPreviewProvider`
- Bundle ID `org.josephpearson.Mud.QuickLook` — must be a child of the main
  app's bundle ID for macOS to auto-discover the extension
- Links `MudCore` (rendering) and `MudConfiguration` (shared preference
  snapshot — see
  [2026-04-mud-configuration.md](./2026-04-mud-configuration.md))
- Bundled into `Mud.app/Contents/PlugIns/`


## Extension `Info.plist`

```xml
  <key>NSExtension</key>
  <dict>
      <key>NSExtensionPointIdentifier</key>
      <string>com.apple.quicklook.preview</string>
      <key>NSExtensionPrincipalClass</key>
      <string>$(PRODUCT_MODULE_NAME).PreviewProvider</string>
      <key>NSExtensionAttributes</key>
      <dict>
          <key>QLIsDataBasedPreview</key>
          <true/>
          <key>QLSupportedContentTypes</key>
          <array>
              <string>net.daringfireball.markdown</string>
          </array>
          <key>QLSupportsSearchableItems</key>
          <false/>
      </dict>
  </dict>
```

`QLIsDataBasedPreview = true` is required for `QLPreviewProvider` extensions
and signals the data-based path to the system.


## Implementation sketch

Mirrors the CLI's browser-export path (`App/CLI/main.swift:140-174`):
standalone HTML, inlined image data URIs, registered render extensions.

```swift
  final class PreviewProvider: QLPreviewProvider {
      func providePreview(for request: QLFilePreviewRequest)
          async throws -> QLPreviewReply
      {
          let source = try String(contentsOf: request.fileURL, encoding: .utf8)
          let reply = QLPreviewReply(
              dataOfContentType: .html,
              contentSize: CGSize(width: 800, height: 600)
          ) { _ in
              let suite = UserDefaults(
                  suiteName: MudConfiguration.appGroupSuiteName
              )!
              let snapshot = MudConfiguration(defaults: suite).snapshot(
                  defaultEnabledExtensions: Set(RenderExtension.registry.keys)
              )
              var options = RenderOptions()
              options.theme = snapshot.theme.rawValue
              options.baseURL = request.fileURL
              options.standalone = true
              options.extensions = snapshot.enabledExtensions
              options.htmlClasses = snapshot.upModeHTMLClasses
              options.zoomLevel = snapshot.upModeZoomLevel
              options.blockRemoteContent = !snapshot.allowRemoteContent
              options.doccAlertMode = snapshot.doccAlertMode
              let html = MudCore.renderUpModeDocument(
                  source, options: options,
                  resolveImageSource: { source, base in
                      ImageDataURI.encode(source: source, baseURL: base)
                  })
              return Data(html.utf8)
          }
          return reply
      }
  }
```

Notes on the sketch:

- `baseURL` is the file URL itself. `ImageDataURI.encode` calls
  `deletingLastPathComponent()` internally.
- `standalone = true` makes `HTMLTemplate.wrapUp` inline scripts (including
  mermaid) that would otherwise be loaded at runtime by the app's `WKWebView`.
  `enabledExtensions` mirrors the user's choice from the main app, so a user
  who has disabled mermaid sees no mermaid in previews either.
- `upModeHTMLClasses` is computed by `MudConfigurationSnapshot` from the
  Up-mode-relevant view toggles (readable column, word wrap, line numbers).
  Down-mode-only toggles are not relevant — the extension renders Up mode only.
- The snapshot is read once per preview request. Live updates are a non-goal;
  see `MudConfiguration` plan for the rationale.


## Image handling

Use base64 inlining via `ImageDataURI.encode` — the same path the CLI's
`--browser` mode already uses. The alternative (`QLPreviewReply.attachments`
with `cid:` URLs) would require a parallel image-extraction pass and a
different `resolveImageSource` closure. We'd gain nothing since the base64 path
is tested and self-contained.

Remote images are left as-is by `ImageDataURI.isExternal`. The CSP set by
`HTMLTemplate.wrapUp` already allows `https:` image sources when
`blockRemoteContent` is false (the default) — no change needed.


## Settings via app group

Extensions can't read the main app's `UserDefaults` directly. The full design
of the shared preference layer is described in
[2026-04-mud-configuration.md](./2026-04-mud-configuration.md). The QL
extension only consumes one piece of that module:
`MudConfiguration.snapshot()`, which returns a value type containing every
field that flows into `RenderOptions` for an Up-mode preview.

What this plan depends on:

- The app-group entitlement `group.org.josephpearson.mud` on both the main app
  target and the extension target.
- All preference storage moved into the app-group `UserDefaults` suite (so the
  extension reads the same values the user sees in the main app).
- One-time per-key migration from `UserDefaults.standard` into the suite, run
  on app launch.

Edge case worth noting: if a user installs the upgrade and triggers a Quick
Look preview _before_ launching the main app, migration has not yet run, the
suite is empty, and the snapshot returns hard-coded defaults. Documented
tradeoff — accepted on the basis that users typically launch the app to install
it. If the preview looks wrong on first use, launching the app once fixes it.

If a user changes theme while a preview is open, the next preview picks up the
change; the current one does not (live updates are a non-goal).


### No runtime prompt

There is no "access data from other apps" prompt for this setup. That prompt is
the TCC consent for `com.apple.security.temporary-exception.shared-preference`
(reading another app's `CFPreferences` domain) — a different mechanism. App
groups between an app and its own extension, signed by the same team ID, share
a container silently — this is the documented behavior of the App Groups
entitlement, not a loophole.


## Entitlements

Extension (sandboxed — required for Quick Look extensions):

- `com.apple.security.app-sandbox`
- `com.apple.security.application-groups` = `[<group-id>]`

The Markdown file itself is handed to the extension by Quick Look — no
file-access entitlement is needed for it. The open question is _sibling_ files:
images referenced from the document that live next to it, in subdirectories, or
in ancestor directories. `ImageDataURI.encode` opens those files to inline them
as data URIs, and the sandbox has to permit it.

Options, in order of preference:

1. The file URL Quick Look hands us is security-scoped to its enclosing
   directory, and a `startAccessingSecurityScopedResource()` call on the parent
   URL is enough to read images alongside and below the document. If true, no
   entitlement is needed.
2. Fall back to a temporary absolute-path exception:
   `com.apple.security.temporary-exception.files.absolute-path.read-only = ["/"]`.
   Read-only, but broad. Reach for this only if option 1 fails in the spike.

`com.apple.security.files.user-selected.read-only` is _not_ added — that
entitlement applies to files the user chose through `NSOpenPanel`, not to URLs
handed over by the Quick Look extension point.


## UTI declarations

The extension declares `net.daringfireball.markdown` as its only supported
content type (see `Info.plist` above). `public.markdown` is not a real UTI —
we'd be inventing one. The main app already imports
`net.daringfireball.markdown` in `App/Info.plist`, so no change there.


## Distribution

- **App Store** — extension ships bundled. Both targets carry the app-group
  entitlement, both signed by the same team — no runtime prompt.
- **Direct distribution** — same bundle. Extension is sandboxed; main app is
  not. The main app needs the app-group entitlement added so its non-sandboxed
  process can still write to the group container.


## Xcode target setup

Source, Info.plist, and entitlements are committed under `QuickLook/`. The
Xcode side has to be done interactively:

1. **New target** — File → New → Target → macOS → _Quick Look Preview
   Extension_. Product name `QuickLook`, Team = same as Mud, Bundle ID
   `org.josephpearson.Mud.QuickLook`, language Swift. Xcode will generate a
   `PreviewViewController.swift` and a storyboard for the (unused)
   `QLPreviewingController` path.

2. **Strip the scaffolding** — delete `PreviewViewController.swift`,
   `MainInterface.storyboard`, and Xcode's generated `Info.plist` and
   `.entitlements`. Add the committed `QuickLook/PreviewProvider.swift`,
   `Info.plist`, and `QuickLook.entitlements` to the new target.

3. **Build settings on the target** —

   - `INFOPLIST_FILE = QuickLook/Info.plist`
   - `CODE_SIGN_ENTITLEMENTS = QuickLook/QuickLook.entitlements`
   - `MACOSX_DEPLOYMENT_TARGET = 14.0` (match the main app)
   - `SWIFT_VERSION` = whatever the main app uses

   The product module name will be `QuickLook` — this shadows Apple's
   `QuickLook.framework` module name. Harmless as long as nothing else in the
   project does `import QuickLook` (our extension uses `import QuickLookUI`).

4. **Dependencies** — link `MudCore` and `MudConfiguration` (both Swift
   packages already in the project).

5. **Embed** — on the _Mud_ target's _Frameworks, Libraries, and Embedded
   Content_ (or a _Copy Files_ build phase with destination `PlugIns`), include
   `QuickLook.appex` so it lands at `Mud.app/Contents/PlugIns/QuickLook.appex`.

6. **Verify the NSExtension wiring** — after a build, the bundled `Info.plist`
   should list `NSExtensionPrincipalClass = QuickLook.PreviewProvider` and
   `QLSupportedContentTypes` = `[net.daringfireball.markdown]`.


## Shared version number

macOS rejects an app extension whose `CFBundleShortVersionString` doesn't match
the containing app's. Adding the QL target surfaced that the project's
`MARKETING_VERSION` is duplicated across every target × configuration in
`project.pbxproj` — eight entries today, twelve after this target is added —
and any drift produces either a build-time warning or a launch-time reject.

The release workflow shields release builds from drift:
`.github/workflows/ release.yml` derives `VERSION` from the git tag and passes
`MARKETING_VERSION=$VERSION` as an `xcodebuild` command-line override. Command-
line overrides apply to all targets in the build, regardless of what the
pbxproj says. Drift only bites local Xcode builds and UI archives.

Deferred fix, lightweight option:

1. Add `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` to the four configs of
   the _project-level_ build configuration list (`PBXProject "Mud"`).
2. Delete both from every target-level config.
3. Targets inherit the project value when they don't override. The release
   workflow's command-line override still wins at release time.
4. After this change, don't touch the "Version" or "Build" fields in any
   target's General tab in Xcode — editing those writes a target-level override
   that silently re-shadows the project default.

We don't go with an xcconfig file: more ceremony, another file to remember when
adding a new target, and no benefit over the project-level setting while we're
still a single-project build.


## Testing

`qlmanage` is a poor fit for modern QL extensions. It predates the
app-extension model, and since Sequoia its `-m` listing can't see third-party
`.appex` extensions at all — only legacy, now-deprecated `qlgenerator` bundles.
Its `-g` flag points at a qlgenerator path and is meaningless for a `.appex`.
`-p somefile.md` may still reach a `QLPreviewProvider` via the real pipeline,
but developer reports across recent macOS versions are inconsistent. Don't
build the test loop on it.

The reliable loop is Finder + logs + a debugger attach:

1. Copy `Mud.app` into `/Applications` and launch it once so LaunchServices
   registers the bundled `.appex`.

2. `qlmanage -r && killall Finder` between changes to clear stale state.
   (`qlmanage -r` and `qlmanage -r cache` still work in Tahoe for server and
   thumbnail-cache resets.)

3. Spacebar-preview the fixture in Finder — this is the actual path users
   exercise.

4. In a second terminal, stream logs for the QL subsystem and the extension
   bundle ID:

   ```
     log stream --predicate \
       'subsystem == "com.apple.quicklook" \
        || subsystem == "org.josephpearson.Mud.QuickLook"'
   ```

5. For breakpoints and stepping, attach Xcode to the running
   `com.apple.quicklook.ui.extension.Preview` process and trigger a preview.

Fixtures worth keeping under `Tests/QuickLookFixtures/`:

- `plain.md` — text-only, sanity-check the fast path
- `relative-images.md` — sibling, subdirectory, and parent-directory image
  references — exercises the entitlement story above
- `remote-images.md` — verifies the CSP and `blockRemoteContent` wiring
- `mermaid.md` — confirms the standalone JS path survives inside QL's WebView
- `first-preview.md` — preview-before-launch case where the app-group suite is
  empty; output should use hard-coded defaults without crashing


## Open questions

- Is the absolute-path read-only exception needed, or does the sandbox grant
  sibling-file read access given the file URL we've been handed? Test during
  spike — prefer no exception.
