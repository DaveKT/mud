import Testing
@testable import MudCore

@Suite("MudCore Rendering")
struct MudCoreRenderingTests {
    // MARK: - Auto-title in Up mode

    @Test func upModeAutoTitleFromHeading() {
        let parsed = ParsedMarkdown("# Welcome\n\nBody text.")
        let html = MudCore.renderUpModeDocument(parsed)
        #expect(html.contains("<title>Welcome</title>"))
    }

    @Test func upModeAutoTitleEmptyWhenNoHeading() {
        let parsed = ParsedMarkdown("No headings here.")
        let html = MudCore.renderUpModeDocument(parsed)
        #expect(html.contains("<title></title>"))
    }

    @Test func upModeExplicitTitleOverridesHeading() {
        let parsed = ParsedMarkdown("# Heading")
        var opts = RenderOptions()
        opts.title = "Override"
        let html = MudCore.renderUpModeDocument(parsed, options: opts)
        #expect(html.contains("<title>Override</title>"))
        #expect(!html.contains("<title>Heading</title>"))
    }

    // MARK: - Auto-title in Down mode

    @Test func downModeAutoTitleFromHeading() {
        let parsed = ParsedMarkdown("# Welcome\n\nBody text.")
        let html = MudCore.renderDownModeDocument(parsed)
        #expect(html.contains("<title>Welcome</title>"))
    }

    @Test func downModeExplicitTitleOverridesHeading() {
        let parsed = ParsedMarkdown("# Heading")
        var opts = RenderOptions()
        opts.title = "Override"
        let html = MudCore.renderDownModeDocument(parsed, options: opts)
        #expect(html.contains("<title>Override</title>"))
    }

    // MARK: - String convenience wrappers

    @Test func stringWrapperMatchesParsedMarkdown() {
        let markdown = "# Test\n\nParagraph."
        let fromString = MudCore.renderUpModeDocument(markdown)
        let fromParsed = MudCore.renderUpModeDocument(ParsedMarkdown(markdown))
        #expect(fromString == fromParsed)
    }

    @Test func stringWrapperAutoTitle() {
        let html = MudCore.renderUpModeDocument("# Auto\n\nBody.")
        #expect(html.contains("<title>Auto</title>"))
    }

    // MARK: - Frontmatter in Up mode

    @Test func upModeWithFrontMatterRendersTable() {
        let parsed = ParsedMarkdown(
            "---\ntitle: Hello\nauthor: Jane\n---\n\n# Heading")
        let html = MudCore.renderUpToHTML(parsed)
        #expect(html.contains("mud-frontmatter"))
        #expect(html.contains("<details"))
        #expect(html.contains("title"))
        #expect(html.contains("author"))
    }

    @Test func upModeWithoutFrontMatterNoTable() {
        let parsed = ParsedMarkdown("# Just a heading\n\nBody.")
        let html = MudCore.renderUpToHTML(parsed)
        #expect(!html.contains("mud-frontmatter"))
    }

    @Test func upModeFrontMatterFallbackToCodeBlock() {
        let parsed = ParsedMarkdown("---\n# just comments\n---\n\nBody")
        let html = MudCore.renderUpToHTML(parsed)
        #expect(html.contains("mud-frontmatter"))
        #expect(html.contains("<pre"))
    }

    @Test func upModeBodyRenderedNormally() {
        let parsed = ParsedMarkdown(
            "---\ntitle: X\n---\n\n# Real Heading\n\nParagraph.")
        let html = MudCore.renderUpToHTML(parsed)
        #expect(html.contains("<h1"))
        #expect(html.contains("Real Heading"))
        #expect(html.contains("<p>Paragraph.</p>"))
    }

    // MARK: - Frontmatter in Down mode

    @Test func downModeWithFrontMatterLineRoles() {
        let parsed = ParsedMarkdown(
            "---\ntitle: Hello\n---\n\n# Heading\n")
        let html = MudCore.renderDownToHTML(parsed)
        #expect(html.contains("fm-fence"))
        #expect(html.contains("fm-code"))
    }

    @Test func downModeWithoutFrontMatterNoRoles() {
        let parsed = ParsedMarkdown("# Heading\n\nBody.\n")
        let html = MudCore.renderDownToHTML(parsed)
        #expect(!html.contains("fm-fence"))
        #expect(!html.contains("fm-code"))
    }

    @Test func downModeFrontMatterContinuousLineNumbers() {
        let parsed = ParsedMarkdown(
            "---\ntitle: Hello\n---\n\n# Heading\n")
        let html = MudCore.renderDownToHTML(parsed)
        // Frontmatter is 3 lines, then blank line + heading = 5 lines
        #expect(html.contains("<span class=\"ln\">1</span>"))
        #expect(html.contains("<span class=\"ln\">2</span>"))
        #expect(html.contains("<span class=\"ln\">3</span>"))
        #expect(html.contains("<span class=\"ln\">4</span>"))
        #expect(html.contains("<span class=\"ln\">5</span>"))
    }
}
