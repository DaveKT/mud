import Testing
@testable import MudCore

@Suite("ParsedMarkdown")
struct ParsedMarkdownTests {
    // MARK: - Title extraction

    @Test func titleFromFirstHeading() {
        let parsed = ParsedMarkdown("# Hello\n\nBody text")
        #expect(parsed.title == "Hello")
    }

    @Test func titleFromSecondLevelHeading() {
        let parsed = ParsedMarkdown("## Sub-heading\n\nBody")
        #expect(parsed.title == "Sub-heading")
    }

    @Test func firstHeadingWinsRegardlessOfLevel() {
        let parsed = ParsedMarkdown("## Sub\n\n# Main")
        #expect(parsed.title == "Sub")
    }

    @Test func titleStripsInlineMarkup() {
        let parsed = ParsedMarkdown("# Hello **world**")
        #expect(parsed.title == "Hello world")
    }

    @Test func titleNilWhenNoHeadings() {
        let parsed = ParsedMarkdown("Just a paragraph.\n\nAnother one.")
        #expect(parsed.title == nil)
    }

    @Test func titleNilForEmptyDocument() {
        let parsed = ParsedMarkdown("")
        #expect(parsed.title == nil)
    }

    // MARK: - Headings

    @Test func headingsPopulated() {
        let parsed = ParsedMarkdown("# One\n\n## Two\n\n### Three")
        #expect(parsed.headings.count == 3)
        #expect(parsed.headings[0].text == "One")
        #expect(parsed.headings[1].text == "Two")
        #expect(parsed.headings[2].text == "Three")
    }

    @Test func headingsEmptyForNoHeadings() {
        let parsed = ParsedMarkdown("No headings here.")
        #expect(parsed.headings.isEmpty)
    }

    // MARK: - Markdown preservation

    @Test func markdownPropertyPreservesOriginal() {
        let source = "# Title\n\nSome **bold** text."
        let parsed = ParsedMarkdown(source)
        #expect(parsed.markdown == source)
    }
}
