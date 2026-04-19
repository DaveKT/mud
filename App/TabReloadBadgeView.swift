import AppKit

/// A brown dot shown in `NSWindowTab.accessoryView` to indicate that a tab's
/// document reloaded while the window was not key. Uses a dynamic color that
/// resolves to a darker saddle-brown in light mode and a lighter tan in dark
/// mode, tracking the tab's effective appearance. The view is wider than the
/// dot so it leaves a few pixels of trailing padding inside the tab.
final class TabReloadBadgeView: NSView {
    private static let dotSize: CGFloat = 8
    private static let trailingPadding: CGFloat = 4
    private static let viewWidth: CGFloat = dotSize + trailingPadding + 1
    private static let viewHeight: CGFloat = dotSize + 2

    private static let dotColor = NSColor(name: nil) { appearance in
        let darkMatches: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark,
        ]
        let isDark = appearance.bestMatch(from: darkMatches) != nil
        return isDark
            ? NSColor(srgbRed: 0.851, green: 0.722, blue: 0.486, alpha: 1)
            : NSColor(srgbRed: 0.545, green: 0.353, blue: 0.169, alpha: 1)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.viewWidth, height: Self.viewHeight))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.viewWidth),
            heightAnchor.constraint(equalToConstant: Self.viewHeight),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.viewWidth, height: Self.viewHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dotRect = NSRect(x: 1, y: 1, width: Self.dotSize, height: Self.dotSize)
        Self.dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
