import AppKit
import Foundation
import OSLog
import QuickLookUI
import WebKit
import MudCore
import MudConfiguration

private let log = Logger(
    subsystem: "org.josephpearson.Mud.QuickLook",
    category: "preview"
)

/// View-based Quick Look preview. Subclasses `NSViewController` and conforms
/// to `QLPreviewingController` so Finder can embed the preview directly into
/// the column-view preview pane (data-based `QLPreviewProvider` extensions
/// are only invoked for the spacebar window).
///
/// `@objc(MudPreviewProvider)` registers a stable Objective-C class name so
/// `NSExtensionPrincipalClass` in Info.plist resolves without depending on
/// Swift module-name mangling.
@objc(MudPreviewProvider)
final class MudPreviewProvider: NSViewController, QLPreviewingController {
    private let webView = WKWebView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )

    override func loadView() {
        webView.autoresizingMask = [.width, .height]
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        log.info("preparePreviewOfFile: \(url.path, privacy: .public)")
        let source = try String(contentsOf: url, encoding: .utf8)

        let config: MudConfiguration
        if let suite = UserDefaults(
            suiteName: MudConfiguration.appGroupSuiteName
        ) {
            config = MudConfiguration(defaults: suite)
        } else {
            log.error("app-group suite unavailable; falling back to defaults")
            config = MudConfiguration(defaults: .standard)
        }
        let snapshot = config.snapshot(
            defaultEnabledExtensions: Set(RenderExtension.registry.keys)
        )

        var options = RenderOptions()
        options.theme = snapshot.theme.rawValue
        options.baseURL = url
        options.standalone = true
        options.extensions = snapshot.enabledExtensions
        options.htmlClasses = snapshot.upModeHTMLClasses
        options.zoomLevel = snapshot.upModeZoomLevel
        options.blockRemoteContent = !snapshot.allowRemoteContent
        options.doccAlertMode = snapshot.doccAlertMode

        let html = MudCore.renderUpModeDocument(
            source,
            options: options,
            resolveImageSource: { imgSource, imgBase in
                ImageDataURI.encode(source: imgSource, baseURL: imgBase)
            }
        )

        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
