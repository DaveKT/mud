import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var hasBeenShown = false

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        // An empty toolbar is needed for NavigationSplitView to populate
        // its title and items into the unified titlebar.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.contentViewController = NSHostingController(
            rootView: SettingsView()
        )

        self.init(window: window)
    }

    func openSettings() {
        showWindow(nil)
        if !hasBeenShown {
            window?.center()
            hasBeenShown = true
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
