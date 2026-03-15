import Markdown

/// A parsed Markdown document. Parse once, reuse for rendering,
/// heading extraction, and title extraction.
public struct ParsedMarkdown {
    let document: Document
    public let markdown: String
    public let headings: [OutlineHeading]

    /// The plain text of the first heading, or `nil` if the document
    /// has no headings.
    public var title: String? { headings.first?.text }

    public init(_ markdown: String) {
        self.markdown = markdown
        self.document = MarkdownParser.parse(markdown)
        var extractor = HeadingExtractor()
        extractor.visit(document)
        self.headings = extractor.headings
    }
}
