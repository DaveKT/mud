import AppKit
import CoreGraphics
import CoreText
import Foundation
import MudCore
import OSLog
import QuickLookThumbnailing

private let log = Logger(
    subsystem: "org.josephpearson.Mud.Thumbnail",
    category: "thumbnail"
)

// Geometry on the 768×1024 (3:4 portrait) reference canvas. The canvas
// is filled flat with `cardColor` — no separate page-silhouette layer,
// since Finder wraps the reply in its own paper chrome and we're using
// the whole rect as the card body. `textRect` is the writable interior;
// long headings wrap and flow down, and the ones that reach the drip
// get visually swallowed by the overlay.
private let canvasSize = CGSize(width: 768, height: 1024)
private let textRect = CGRect(x: 72, y: 144, width: 624, height: 880)
private let fontSizeRef: CGFloat = 96

private let cardColor = NSColor(
    red: 0xE6 / 255.0, green: 0xE6 / 255.0, blue: 0xE6 / 255.0, alpha: 1
)

// Heading ink matches the drip body.
private let headingColor = NSColor(
    red: 0x7A / 255.0, green: 0x4A / 255.0, blue: 0x2A / 255.0, alpha: 1
)

/// Quick Look thumbnail provider for Markdown files. Fills a 3:4
/// portrait canvas (768×1024 reference) with a flat grey card colour,
/// draws the document's first heading, then composites
/// `thumbnail-dynamic.png` (the muddy-drip overlay) on top. The drip
/// visually swallows any heading text that flows into its territory, so
/// long headings wrap naturally without extra clipping. Finder's
/// paper-sheet chrome wraps the reply at the same portrait aspect.
///
/// `@objc(MudThumbnailProvider)` stabilizes the Obj-C class name so
/// `NSExtensionPrincipalClass` in Info.plist resolves without depending
/// on Swift module-name mangling (matches the `MudPreviewProvider`
/// pattern).
@objc(MudThumbnailProvider)
final class MudThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        let url = request.fileURL
        log.info("""
            provideThumbnail: \(url.path, privacy: .public) \
            maximumSize=\(request.maximumSize.width)x\(request.maximumSize.height) \
            scale=\(request.scale)
            """)

        let heading = firstHeading(in: url)
            ?? url.deletingPathExtension().lastPathComponent

        guard let overlay = loadBundledImage(named: "thumbnail-dynamic") else {
            log.error("thumbnail-dynamic.png missing from bundle")
            handler(nil, nil)
            return
        }

        let size = fittedSize(in: request.maximumSize)
        log.info("replying with size=\(size.width)x\(size.height)")
        let reply = QLThumbnailReply(contextSize: size) {
            drawThumbnail(overlay: overlay, heading: heading, size: size)
            return true
        }
        handler(reply, nil)
    }
}

/// Largest 3:4-portrait size that fits inside the system-requested
/// bounding box. `QLFileThumbnailRequest.maximumSize` is a max — the
/// reply bitmap's aspect ratio drives how Finder shapes the paper
/// chrome, so returning a portrait size gets us a portrait thumbnail.
private func fittedSize(in maxSize: CGSize) -> CGSize {
    let aspect = canvasSize.width / canvasSize.height
    if maxSize.width / maxSize.height > aspect {
        return CGSize(
            width: (maxSize.height * aspect).rounded(),
            height: maxSize.height
        )
    } else {
        return CGSize(
            width: maxSize.width,
            height: (maxSize.width / aspect).rounded()
        )
    }
}

private func firstHeading(in url: URL) -> String? {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }
    let trimmed = MudCore.extractHeadings(source)
        .first?.text
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed?.isEmpty ?? true) ? nil : trimmed
}

private func loadBundledImage(named name: String) -> CGImage? {
    guard
        let url = Bundle.main.url(forResource: name, withExtension: "png"),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
}

private func drawThumbnail(
    overlay: CGImage, heading: String, size: CGSize
) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.interpolationQuality = .high
    let fullRect = CGRect(origin: .zero, size: size)

    cardColor.setFill()
    context.fill(fullRect)

    // CG origin is bottom-left; reference coordinates are top-down, so
    // y becomes `size.height - (y + height) * scale`. `size` is always
    // 3:4 portrait so scaling by height is uniform.
    let scale = size.height / canvasSize.height
    let textPath = CGRect(
        x: textRect.origin.x * scale,
        y: size.height - (textRect.origin.y + textRect.height) * scale,
        width: textRect.width * scale,
        height: textRect.height * scale
    )

    let font = NSFont.systemFont(ofSize: fontSizeRef * scale, weight: .bold)
    let attributed = NSAttributedString(string: heading, attributes: [
        .font: font,
        .foregroundColor: headingColor,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(
        attributed as CFAttributedString
    )
    let path = CGPath(rect: textPath, transform: nil)
    let ctFrame = CTFramesetterCreateFrame(
        framesetter, CFRange(location: 0, length: 0), path, nil
    )
    CTFrameDraw(ctFrame, context)

    context.draw(overlay, in: fullRect)
}
