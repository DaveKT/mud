import SwiftUI

/// An invisible `NSViewRepresentable` that enables click-to-deselect on
/// `List(selection:)` rows.
///
/// Place as `.background(DeselectMonitor(selection: $sel))` on the List.
/// Works by installing a local `NSEvent` monitor for left-mouse-down.
/// When a click lands within the List's bounds and the selection doesn't
/// change on the next run-loop tick, the monitor clears the selection.
///
/// For lists with `DisclosureGroup` (where clicking a disclosure arrow
/// should NOT deselect), pass a `guardValue` that tracks expand/collapse
/// state. If it changes between the click and the deferred check,
/// deselection is suppressed.
struct DeselectMonitor: NSViewRepresentable {
    @Binding var selection: String?
    var guardValue: AnyHashable?

    func makeNSView(context: Context) -> DeselectMonitorView {
        DeselectMonitorView()
    }

    func updateNSView(_ nsView: DeselectMonitorView, context: Context) {
        nsView.currentSelection = selection
        nsView.guardValue = guardValue
        nsView.selectionBinding = $selection
    }

    static func dismantleNSView(
        _ nsView: DeselectMonitorView, coordinator: ()
    ) {
        nsView.removeMonitor()
    }
}

/// The backing AppKit view for `DeselectMonitor`.
final class DeselectMonitorView: NSView {
    var currentSelection: String?
    var guardValue: AnyHashable?
    var selectionBinding: Binding<String?>?

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
        // Ignore double-clicks (would select-then-deselect).
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

            // Guard state changed (e.g. disclosure toggle) — don't deselect.
            if let guardBefore, self.guardValue != guardBefore { return }

            self.selectionBinding?.wrappedValue = nil
        }
    }
}
