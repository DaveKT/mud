Plan: CLI Standalone Flag
===============================================================================

> Status: Complete


## Context

The CLI's `--browser` flag produces self-contained HTML (images embedded as
data URIs, extension scripts inlined) but always opens the result in a browser.
There was no way to get that same self-contained output on stdout. A
`--standalone` flag was added to give stdout the same self-contained treatment.


## Changes

Added `--standalone` to the CLI argument parser. In the render function,
`--browser` now implies `--standalone`, and both share the same rendering path:
setting `options.standalone = true`, enabling all extensions, and wiring up the
image data-URI resolver. Output destination remains unchanged — `--browser`
writes to a temp file and opens it; `--standalone` alone writes to stdout.

Updated the usage text and the CLI guide (`Doc/Guides/command-line.md`) with a
new "Standalone output" section and a flags table entry.

Also gave the `copyCode` extension its own `'unsafe-inline'` CSP source so the
copy button works in standalone exports independently of mermaid.
