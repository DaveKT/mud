Plan: CLI Standalone Flag
===============================================================================

> Status: Planning


## Context

The CLI's `--browser` flag produces self-contained HTML (images embedded as
data URIs, extension scripts inlined) but always opens the result in a browser.
There's no way to get that same self-contained output on stdout. This means
generating a portable HTML file requires `--browser` and then manually saving
the temp file. A `--standalone` flag would give stdout the same self-contained
treatment.


## Changes

### 1. Argument parsing — `App/CLI/main.swift`

Add a `--standalone` flag (no short form) alongside the existing `--browser`:

```
case "--standalone":
    standalone = true
```

Add `var standalone = false` next to `var browser = false` (line 14).


### 2. Render function — `App/CLI/main.swift`

In the `render()` function, the existing `browser` guard at lines 154-160
becomes:

```swift
let standalone = browser || standalone

if standalone {
    options.standalone = true
    options.extensions = Set(RenderExtension.registry.keys)
}

let imageResolver: ((_ source: String, _ baseURL: URL) -> String?)? =
    standalone
    ? { source, base in ImageDataURI.encode(source: source, baseURL: base) }
    : nil
```

No other rendering changes needed — `--standalone` and `--browser` produce
identical HTML; they differ only in output destination.


### 3. Output path — unchanged

The existing output routing already handles this. When `browser` is false
(including when `standalone` is true), HTML goes to stdout (lines 106, 129). No
changes needed here.


### 4. Usage text — `App/CLI/main.swift`

Add `--standalone` to the Options section of `printUsage()`:

```
--standalone   Self-contained output (images embedded as data URIs)
```


### 5. CLI guide — `Doc/Guides/command-line.md`

Add a "Standalone output" section after "Browser output", documenting:

```sh
mud -u --standalone README.md > output.html
mud -d --standalone README.md > output.html
```

Add `--standalone` to the rendering flags table.


## Verification

```sh
# A markdown file with a local image reference:
mud -u --standalone Doc/Guides/plan-workflows.md > /tmp/test.html

# Confirm the image is a data URI, not a relative path:
grep 'data:image' /tmp/test.html

# Compare against --browser output (should be identical HTML):
mud -u --browser Doc/Guides/plan-workflows.md
# (save from browser, diff)

# Confirm --standalone without -u/-d still errors:
mud --standalone README.md

# Confirm plain -u still produces relative image paths:
mud -u Doc/Guides/plan-workflows.md | grep -c 'data:image'
# (should be 0)
```
