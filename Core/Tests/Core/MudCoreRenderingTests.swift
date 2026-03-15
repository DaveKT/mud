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
}
