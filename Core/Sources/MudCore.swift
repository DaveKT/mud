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
        upVisitor.alertDetector.docCAlertMode = options.docCAlertMode
        upVisitor.showInlineDeletions = options.showInlineDeletions
        if let waypoint = options.waypoint {
            upVisitor.diffContext = DiffContext(
                old: waypoint, new: parsed,
                wordDiffThreshold: options.wordDiffThreshold)
        }
        upVisitor.visit(parsed.document)
        upVisitor.emitTrailingDeletions()

        if let yaml = parsed.frontMatter {
            return renderFrontMatterHTML(yaml) + upVisitor.result
        }
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
        let fmRendered = downVisitor.renderFrontMatterLines(
            markdown: parsed.markdown,
            lineCount: parsed.frontMatterLineCount)
        if let waypoint = options.waypoint {
            let matches = BlockMatcher.match(old: waypoint, new: parsed)
            return downVisitor.highlightWithChanges(
                new: parsed.body, old: waypoint.body,
                matches: matches,
                docCAlertMode: options.docCAlertMode,
                wordDiffThreshold: options.wordDiffThreshold,
                frontMatterRendered: fmRendered)
        }
        return downVisitor.highlight(
            parsed.body, docCAlertMode: options.docCAlertMode,
            frontMatterRendered: fmRendered)
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
        renderDownToHTML(ParsedMarkdown(text), options: options)
    }

    /// Renders Markdown text to a complete HTML document for Down mode.
    public static func renderDownModeDocument(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        renderDownModeDocument(ParsedMarkdown(text), options: options)
    }

    // MARK: - Frontmatter rendering

    /// Renders YAML frontmatter as a collapsible HTML block for
    /// Up mode. Parses top-level keys into a table; falls back to
    /// a raw code block if no keys are found.
    private static func renderFrontMatterHTML(_ yaml: String) -> String {
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)

        var html = "<details class=\"mud-frontmatter\">"
        html += "<summary>Frontmatter</summary>"

        if keys.isEmpty {
            html += "<pre><code class=\"language-yaml\">"
            html += HTMLEscaping.escape(yaml)
            html += "</code></pre>"
        } else {
            html += "<table class=\"mud-frontmatter-table\">"
            for kv in keys {
                html += "<tr>"
                html += "<th class=\"fm-key\">"
                html += HTMLEscaping.escape(kv.key)
                html += "</th><td>"
                switch kv.value {
                case .scalar(let v):
                    html += HTMLEscaping.escape(v)
                case .inlineArray(let items):
                    html += HTMLEscaping.escape(items.joined(separator: ", "))
                case .block(let raw):
                    html += "<pre>"
                    html += HTMLEscaping.escape(raw)
                    html += "</pre>"
                }
                html += "</td></tr>"
            }
            html += "</table>"
        }

        html += "</details>"
        return html
    }
}
