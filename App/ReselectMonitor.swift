import SwiftUI

/// An invisible `NSViewRepresentable` that detects clicks on the
/// already-selected row in a `List(selection:)` and fires a callback.
///
/// SwiftUI's List does not re-fire `onChange` when the user clicks a
/// row that is already selected. This view works around that limitation
/// by installing a local `NSEvent` monitor for left-mouse-down.
///
/// Place as `.background(ReselectMonitor(...))` on the List.
///
/// For lists with `DisclosureGroup`, pass a `guardValue` that tracks
/// expand/collapse state. If it changes between the click and the
/// deferred check, the callback is suppressed.
struct ReselectMonitor: NSViewRepresentable {
    var selection: String?
    var guardValue: AnyHashable?
    var onReselect: (String) -> Void

    func makeNSView(context: Context) -> ReselectMonitorView {
        ReselectMonitorView()
    }

    func updateNSView(_ nsView: ReselectMonitorView, context: Context) {
        nsView.currentSelection = selection
        nsView.guardValue = guardValue
        nsView.onReselect = onReselect
    }

    static func dismantleNSView(
        _ nsView: ReselectMonitorView, coordinator: ()
    ) {
        nsView.removeMonitor()
    }
}

/// The backing AppKit view for `ReselectMonitor`.
final class ReselectMonitorView: NSView {
    var currentSelection: String?
    var guardValue: AnyHashable?
    var onReselect: ((String) -> Void)?

    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        } else {
            removeMonitor()
        }
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: - Private

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] event in
            self?.handleMouseDown(event)
            return event
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        // Ignore double-clicks (would select-then-reselect).
        guard event.clickCount == 1 else { return }

        guard currentSelection != nil,
              let window = self.window,
              event.window === window
        else { return }

        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return }

        let selBefore = currentSelection
        let guardBefore = guardValue

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // A new row was selected — don't interfere.
            guard self.currentSelection == selBefore else { return }

            // Guard state changed (e.g. disclosure toggle) — don't act.
            if let guardBefore, self.guardValue != guardBefore { return }

            if let selBefore {
                self.onReselect?(selBefore)
            }
        }
    }
}
