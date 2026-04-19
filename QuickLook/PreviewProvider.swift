import CoreGraphics
import Foundation
import OSLog
import QuickLookUI
import MudCore
import MudConfiguration

private let log = Logger(
    subsystem: "org.josephpearson.Mud.QuickLook",
    category: "preview"
)

/// Quick Look preview provider for Markdown. Mirrors the CLI's `--browser`
/// path: self-contained HTML, inlined image data URIs, every registered
/// render extension available. Reads preferences from the app-group suite
/// written by the main app.
///
/// `@objc(MudPreviewProvider)` registers a stable Objective-C class name so
/// `NSExtensionPrincipalClass` in Info.plist resolves without depending on
/// Swift module-name mangling.
@objc(MudPreviewProvider)
final class MudPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest
    ) async throws -> QLPreviewReply {
        log.info("providePreview called for \(request.fileURL.path, privacy: .public)")
        let fileURL = request.fileURL

        let source = try String(contentsOf: fileURL, encoding: .utf8)

        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 600)
        ) { _ in
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
            options.baseURL = fileURL
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
            return Data(html.utf8)
        }
        return reply
    }
}
