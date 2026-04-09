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

    // MARK: - Frontmatter

    @Test func frontMatterPopulated() {
        let source = "---\ntitle: Hello\n---\n\n# Heading\n\nBody"
        let parsed = ParsedMarkdown(source)
        #expect(parsed.frontMatter == "title: Hello")
    }

    @Test func bodyExcludesFrontMatter() {
        let source = "---\ntitle: Hello\n---\n\n# Heading\n\nBody"
        let parsed = ParsedMarkdown(source)
        #expect(parsed.body == "\n# Heading\n\nBody")
        #expect(parsed.body != parsed.markdown)
    }

    @Test func titleFromBodyNotFrontMatter() {
        let source = "---\ntitle: YAML Title\n---\n\n# Real Heading"
        let parsed = ParsedMarkdown(source)
        #expect(parsed.title == "Real Heading")
    }

    @Test func noFrontMatterIsNil() {
        let source = "# Heading\n\nBody text."
        let parsed = ParsedMarkdown(source)
        #expect(parsed.frontMatter == nil)
        #expect(parsed.body == source)
    }

    @Test func headingsUnaffectedByFrontMatter() {
        let withFM = ParsedMarkdown("---\ntitle: X\n---\n\n# One\n\n## Two")
        let withoutFM = ParsedMarkdown("# One\n\n## Two")
        #expect(withFM.headings.count == withoutFM.headings.count)
        #expect(withFM.headings[0].text == "One")
        #expect(withFM.headings[1].text == "Two")
    }
}
