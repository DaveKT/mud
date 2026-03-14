RELEASES
===============================================================================

## v1.1.0

- Settings dialog with sidebar navigation and panes for General, Theme,
  Markdown, Up Mode, Down Mode, Command Line, and Debugging
- Theme preview cards in Settings with visual color swatches
- Card-based lighting selector in General settings
- Up Mode setting to block loading of remote content
- Sandbox-aware command line settings: manual `ln -s` instructions when
  sandboxed, automatic installer otherwise
- GFM alerts and DocC-style asides (Note, Tip, Important, Warning, Caution)
- Special "Status" aside with deep orange styling and pulse icon
- "Error" recognized as a DocC-style aside
- Emoji shortcode support in Up mode (`:shortcode:` → emoji)
- Mermaid diagram rendering in Up mode
- CLI tool: separate "Mud CLI" target for command-line HTML output
- CLI tool: `-v` reports the main Mud.app version number
- CLI tool: when sandboxed, strips executable assets and adapts settings pane
- Error page displayed when documents can't be opened
- Help menu item and bundled README opened on first launch
- Table of contents sidebar: extra space for disclosure chevrons, decoupled
  empty-state view from sidebar layout
- FileWatcher no longer fires onChange after genuine file deletion
- Window frame restored after content and toolbar setup
- "Enter Full Screen" hidden from View menu


## v1.0.0

- Initial release.
