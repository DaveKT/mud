import Testing
@testable import MudCore

@Suite("FrontMatterExtractor")
struct FrontMatterExtractorTests {

    // MARK: - Detection and extraction

    @Test func standardFrontMatter() {
        let input = "---\ntitle: Hello\nauthor: Jane\n---\n\n# Heading\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello\nauthor: Jane")
        #expect(result?.body == "\n# Heading\n")
        #expect(result?.lineCount == 4)
    }

    @Test func emptyFrontMatter() {
        let input = "---\n---\n\nBody text\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "")
        #expect(result?.body == "\nBody text\n")
        #expect(result?.lineCount == 2)
    }

    @Test func closingWithDots() {
        let input = "---\ntitle: Hello\n...\n\nBody\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello")
    }

    @Test func noClosingDelimiter() {
        let input = "---\ntitle: Hello\nauthor: Jane\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result == nil)
    }

    @Test func notOnLineOne() {
        let input = "\n---\ntitle: Hello\n---\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result == nil)
    }

    @Test func textBeforeDelimiter() {
        let input = "Some text\n---\ntitle: Hello\n---\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result == nil)
    }

    @Test func trailingWhitespaceOnDelimiters() {
        let input = "---  \ntitle: Hello\n---  \n\nBody\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello")
    }

    @Test func windowsLineEndings() {
        let input = "---\r\ntitle: Hello\r\n---\r\n\r\nBody\r\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello")
    }

    @Test func noFrontMatter() {
        let input = "# Just a heading\n\nSome body text.\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result == nil)
    }

    @Test func frontMatterOnly() {
        let input = "---\ntitle: Hello\n---\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello")
    }

    @Test func frontMatterOnlyNoTrailingNewline() {
        let input = "---\ntitle: Hello\n---"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result != nil)
        #expect(result?.yaml == "title: Hello")
    }

    @Test func thematicBreakLaterInDocument() {
        let input = "# Heading\n\n---\n\nMore text\n"
        let result = FrontMatterExtractor.extract(from: input)
        #expect(result == nil)
    }

    // MARK: - Top-level key parsing

    @Test func simpleKeyValuePairs() {
        let yaml = "title: My Document\nauthor: Jane Doe\ndate: 2026-04-08"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 3)
        #expect(keys[0].key == "title")
        #expect(keys[0].value == .scalar("My Document"))
        #expect(keys[1].key == "author")
        #expect(keys[1].value == .scalar("Jane Doe"))
        #expect(keys[2].key == "date")
        #expect(keys[2].value == .scalar("2026-04-08"))
    }

    @Test func inlineArray() {
        let yaml = "tags: [swift, markdown, preview]"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 1)
        #expect(keys[0].key == "tags")
        #expect(keys[0].value == .inlineArray(["swift", "markdown", "preview"]))
    }

    @Test func blockArray() {
        let yaml = "tags:\n  - swift\n  - markdown\n  - preview"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 1)
        #expect(keys[0].key == "tags")
        #expect(keys[0].value == .block("  - swift\n  - markdown\n  - preview"))
    }

    @Test func nestedMapping() {
        let yaml = "config:\n  nested:\n    key: value\n    other: thing"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 1)
        #expect(keys[0].key == "config")
        #expect(keys[0].value == .block(
            "  nested:\n    key: value\n    other: thing"))
    }

    @Test func multiLineScalarLiteral() {
        let yaml = "description: |\n  First line\n  Second line"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 1)
        #expect(keys[0].key == "description")
        #expect(keys[0].value == .block("|\n  First line\n  Second line"))
    }

    @Test func multiLineScalarFolded() {
        let yaml = "description: >\n  First line\n  Second line"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 1)
        #expect(keys[0].key == "description")
        #expect(keys[0].value == .block(">\n  First line\n  Second line"))
    }

    @Test func quotedValuesPreserved() {
        let yaml = "title: \"My Document\"\nsubtitle: 'Another Title'"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 2)
        #expect(keys[0].value == .scalar("\"My Document\""))
        #expect(keys[1].value == .scalar("'Another Title'"))
    }

    @Test func commentLinesBetweenKeys() {
        let yaml = "title: Hello\n# This is a comment\nauthor: Jane"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 2)
        #expect(keys[0].key == "title")
        #expect(keys[1].key == "author")
    }

    @Test func allCommentsReturnsEmpty() {
        let yaml = "# Just a comment\n# Another comment"
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.isEmpty)
    }

    @Test func emptyInputReturnsEmpty() {
        let keys = FrontMatterExtractor.parseTopLevelKeys("")
        #expect(keys.isEmpty)
    }

    @Test func mixedSimpleAndComplex() {
        let yaml = """
            title: Hello
            tags: [a, b]
            config:
              key: value
            draft: true
            """
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)
        #expect(keys.count == 4)
        #expect(keys[0].value == .scalar("Hello"))
        #expect(keys[1].value == .inlineArray(["a", "b"]))
        #expect(keys[2].value == .block("  key: value"))
        #expect(keys[3].value == .scalar("true"))
    }
}
