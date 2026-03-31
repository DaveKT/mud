// MudCore - Shared Markdown rendering library for the Mud app

import Foundation

/// Entry point for MudCore functionality.
public enum MudCore {
    public static let version = "1.0.0"

    private static let downVisitor = DownHTMLVisitor()

    // MARK: - ParsedMarkdown API

    /// Renders a parsed Markdown document to HTML body content.
    public static func renderUpToHTML(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var upVisitor = UpHTMLVisitor()
        upVisitor.baseURL = options.baseURL
        upVisitor.resolveImageSource = resolveImageSource
        upVisitor.alertDetector.doccAlertMode = options.doccAlertMode
        upVisitor.showInlineDeletions = options.showInlineDeletions
        if let waypoint = options.waypoint {
            upVisitor.diffContext = DiffContext(old: waypoint, new: parsed)
        }
        upVisitor.visit(parsed.document)
        upVisitor.emitTrailingDeletions()
        return upVisitor.result
    }

    /// Renders a parsed Markdown document to a complete HTML document
    /// with styles. When `options.title` is empty, the title is
    /// auto-extracted from the first heading.
    public static func renderUpModeDocument(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var options = options
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        let body = renderUpToHTML(parsed, options: options,
                                  resolveImageSource: resolveImageSource)
        return HTMLTemplate.wrapUp(body: body, options: options)
    }

    /// Renders a parsed Markdown document to HTML for Down mode (body only).
    public static func renderDownToHTML(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init()
    ) -> String {
        if let waypoint = options.waypoint {
            let matches = BlockMatcher.match(old: waypoint, new: parsed)
            return downVisitor.highlightWithChanges(
                new: parsed.markdown, old: waypoint.markdown,
                matches: matches,
                doccAlertMode: options.doccAlertMode)
        }
        return downVisitor.highlight(
            parsed.markdown, doccAlertMode: options.doccAlertMode)
    }

    /// Renders a parsed Markdown document to a complete HTML document
    /// for Down mode. When `options.title` is empty, the title is
    /// auto-extracted from the first heading.
    public static func renderDownModeDocument(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init()
    ) -> String {
        var options = options
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        let bodyHTML = renderDownToHTML(parsed, options: options)
        return HTMLTemplate.wrapDown(bodyHTML: bodyHTML, options: options)
    }

    // MARK: - String convenience API

    /// Renders Markdown text to HTML body content.
    public static func renderUpToHTML(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        renderUpToHTML(ParsedMarkdown(markdown), options: options,
                       resolveImageSource: resolveImageSource)
    }

    /// Renders Markdown text to a complete HTML document with styles.
    public static func renderUpModeDocument(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        renderUpModeDocument(ParsedMarkdown(markdown), options: options,
                             resolveImageSource: resolveImageSource)
    }

    // MARK: - Change tracking

    /// Computes a list of changes between two parsed Markdown documents
    /// for the sidebar change list.
    public static func computeChanges(
        old: ParsedMarkdown, new: ParsedMarkdown
    ) -> [DocumentChange] {
        ChangeList.computeChanges(old: old, new: new)
    }

    /// Extracts headings from a Markdown string for the outline sidebar.
    public static func extractHeadings(_ markdown: String) -> [OutlineHeading] {
        ParsedMarkdown(markdown).headings
    }

    /// Renders Markdown text to HTML for Down mode (body only).
    public static func renderDownToHTML(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        if options.waypoint != nil {
            return renderDownToHTML(
                ParsedMarkdown(text), options: options)
        }
        return downVisitor.highlight(
            text, doccAlertMode: options.doccAlertMode)
    }

    /// Renders Markdown text to a complete HTML document for Down mode.
    public static func renderDownModeDocument(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        renderDownModeDocument(ParsedMarkdown(text), options: options)
    }
}
