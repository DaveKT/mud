import Foundation
import Markdown

/// AST → web HTML visitor. Walks a swift-markdown `Document` and
/// emits HTML matching cmark-gfm output for visual parity.
///
/// Heading IDs are generated during the walk using `SlugGenerator`,
/// eliminating the need for regex post-processing.
struct UpHTMLVisitor: MarkupWalker {
    var result = ""

    /// Base URL of the document being rendered (typically its file URL).
    var baseURL: URL?

    /// Optional transform applied to each image `src` during rendering.
    /// Called with the original source string and the document base URL.
    /// Return a replacement URL string, or `nil` to keep the original.
    var resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?

    // Heading slug deduplication.
    private var slugTracker = SlugGenerator.Tracker()

    // List tightness state (saved/restored for nesting).
    private var inTightList = false

    // Table rendering state.
    private var tableColumnAlignments: [Table.ColumnAlignment?] = []
    private var currentCellColumn = 0
    private var inTableHead = false

    var alertDetector = AlertDetector()

    // MARK: - Block containers

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let (category, title) = alertDetector.detectGFMAlert(blockQuote) {
            emitAlertOpen(category)
            emitAlertTitle(category, title)
            emitGFMAlertContent(blockQuote, category: category)
            result += "</blockquote>\n"
        } else if let (category, title, content) = alertDetector.detectDocCAlert(blockQuote) {
            emitAlertOpen(category)
            emitDocCAlertTitleAndContent(category, title, content)
            result += "</blockquote>\n"
        } else {
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let prev = inTightList
        inTightList = !Self.isLooseList(orderedList)
        if orderedList.startIndex != 1 {
            result += "<ol start=\"\(orderedList.startIndex)\">\n"
        } else {
            result += "<ol>\n"
        }
        descendInto(orderedList)
        result += "</ol>\n"
        inTightList = prev
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let prev = inTightList
        inTightList = !Self.isLooseList(unorderedList)
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
        inTightList = prev
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if inTightList {
            result += "<li>"
        } else {
            result += "<li>\n"
        }
        if let checkbox = listItem.checkbox {
            result += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked {
                result += " checked=\"\""
            }
            result += " /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    // MARK: - Block leaves

    mutating func visitHeading(_ heading: Heading) {
        let level = heading.level
        let slug = slugTracker.slug(for: heading.plainText)
        result += "<h\(level) id=\"\(slug)\">"
        descendInto(heading)
        result += "</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if inTightList && paragraph.parent is ListItem {
            descendInto(paragraph)
            result += "\n"
        } else {
            result += "<p>"
            descendInto(paragraph)
            result += "</p>\n"
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }
        if let lang {
            result += "<pre><code class=\"language-"
            result += HTMLEscaping.escape(lang)
            result += "\">"
        } else {
            result += "<pre><code>"
        }
        if let highlighted = CodeHighlighter.highlight(
            codeBlock.code, language: lang
        ) {
            result += highlighted
        } else {
            result += HTMLEscaping.escape(codeBlock.code)
        }
        result += "</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr />\n"
    }

    // MARK: - Table

    mutating func visitTable(_ table: Table) {
        tableColumnAlignments = table.columnAlignments
        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
        tableColumnAlignments = []
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        inTableHead = true
        currentCellColumn = 0
        result += "<thead>\n<tr>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard tableBody.childCount > 0 else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentCellColumn = 0
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        let tag = inTableHead ? "th" : "td"
        let alignment = currentCellColumn < tableColumnAlignments.count
            ? tableColumnAlignments[currentCellColumn]
            : nil
        if let alignment {
            let value: String
            switch alignment {
            case .left:   value = "left"
            case .center: value = "center"
            case .right:  value = "right"
            }
            result += "<\(tag) align=\"\(value)\">"
        } else {
            result += "<\(tag)>"
        }
        descendInto(tableCell)
        result += "</\(tag)>\n"
        currentCellColumn += 1
    }

    // MARK: - Inline containers

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        descendInto(strikethrough)
        result += "</del>"
    }

    mutating func visitLink(_ link: Markdown.Link) {
        result += "<a href=\"\(HTMLEscaping.escape(link.destination ?? ""))\""
        if let title = link.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.escape(title))\""
        }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        var src = image.source ?? ""
        if let baseURL, let resolve = resolveImageSource,
           let resolved = resolve(src, baseURL) {
            src = resolved
        }
        result += "<img src=\"\(HTMLEscaping.escape(src))\""
        result += " alt=\"\(HTMLEscaping.escape(image.plainText))\""
        if let title = image.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.escape(title))\""
        }
        result += " />"
    }

    // MARK: - Inline leaves

    mutating func visitText(_ text: Text) {
        result += HTMLEscaping.escape(
            EmojiShortcodes.replaceShortcodes(in: text.string)
        )
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>"
        result += HTMLEscaping.escape(inlineCode.code)
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        result += html.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    // MARK: - Alerts

    /// Emits the content of a GFM alert, stripping the `[!TYPE]` tag
    /// from the first paragraph. Walks the first paragraph's inline
    /// children directly: skips the tag Text node (emitting any
    /// trailing content on the same line), skips a following SoftBreak,
    /// then visits remaining inlines and subsequent block children.
    private mutating func emitGFMAlertContent(
        _ blockQuote: BlockQuote, category: AlertCategory
    ) {
        let tag = "[!\(category.rawValue.uppercased())]"
        let children = Array(blockQuote.children)
        guard let firstPara = children.first as? Paragraph else {
            return
        }

        let inlines = Array(firstPara.children)
        var index = 0
        var opened = false

        // Strip the [!TYPE] tag from the first Text node.
        if let tagNode = inlines.first as? Text {
            index = 1
            let after = String(
                tagNode.string.dropFirst(tag.count)
                    .drop(while: { $0 == " " })
            )
            if !after.isEmpty {
                opened = true
                result += "<p>"
                result += HTMLEscaping.escape(after)
            }
            // Skip SoftBreak that separates the tag line from content.
            if index < inlines.count && inlines[index] is SoftBreak {
                index += 1
            }
        }

        // Visit remaining inlines from the first paragraph.
        if index < inlines.count {
            if !opened { result += "<p>"; opened = true }
            for i in index..<inlines.count { visit(inlines[i]) }
        }
        if opened { result += "</p>\n" }

        // Visit remaining block children after the first paragraph.
        for child in children.dropFirst() { visit(child) }
    }

    /// Emits the opening `<blockquote>` tag with alert CSS classes.
    private mutating func emitAlertOpen(_ category: AlertCategory) {
        result += "<blockquote class=\"alert \(category.cssClass)\">\n"
    }

    /// Emits the alert title paragraph with icon and text.
    private mutating func emitAlertTitle(
        _ category: AlertCategory, _ title: String
    ) {
        result += "<p class=\"alert-title\">"
        result += category.icon
        result += HTMLEscaping.escape(title)
        result += "</p>\n"
    }

    /// Concatenated plain text of an array of inline markup nodes,
    /// used for the length check before inlining same-line content.
    private static func plainTextOf(_ nodes: [any Markup]) -> String {
        nodes.map { node -> String in
            if let t = node as? Text { return t.string }
            if let c = node as? InlineCode { return c.code }
            return plainTextOf(Array(node.children))
        }.joined()
    }

    /// Returns true if same-line content qualifies to be bolded in an aside
    /// title: non-empty and under 60 characters.
    private static func shouldInlineSameLine(_ plainText: String) -> Bool {
        return !plainText.isEmpty && plainText.count < 60
    }

    /// Emits the title and body content for a DocC aside. When the
    /// same-line content (before the first SoftBreak) is under 60
    /// characters, it is bolded on the title line; otherwise all
    /// content blocks are rendered roman in separate paragraphs.
    private mutating func emitDocCAlertTitleAndContent(
        _ category: AlertCategory,
        _ title: String,
        _ content: [BlockMarkup]
    ) {
        var sameLine: [any Markup] = []
        var restInlines: [any Markup] = []

        if let firstPara = content.first as? Paragraph {
            let inlines = Array(firstPara.children)
            if let sbIdx = inlines.firstIndex(where: { $0 is SoftBreak }) {
                sameLine = Array(inlines[..<sbIdx])
                restInlines = Array(inlines[(sbIdx + 1)...])
            } else {
                sameLine = inlines
            }
        }

        let shouldInline = Self.shouldInlineSameLine(Self.plainTextOf(sameLine))

        result += "<p class=\"alert-title\">"
        result += category.icon
        result += HTMLEscaping.escape(title)
        if shouldInline {
            result += ": <strong>"
            for node in sameLine { visit(node) }
            result += "</strong>"
        }
        result += "</p>\n"

        if shouldInline {
            emitAlertBody(restInlines: restInlines, remainingBlocks: Array(content.dropFirst()))
        } else {
            for block in content { visit(block) }
        }
    }

    /// Emits the roman body of an aside: restInlines (if any) in a `<p>`,
    /// then each remaining block visited normally.
    private mutating func emitAlertBody(
        restInlines: [any Markup],
        remainingBlocks: [any Markup]
    ) {
        if !restInlines.isEmpty {
            result += "<p>"
            for node in restInlines { visit(node) }
            result += "</p>\n"
        }
        for block in remainingBlocks { visit(block) }
    }

    /// A list is loose if any blank lines appear between consecutive
    /// list items or between block children within a list item.
    /// Uses source positions to detect gaps.
    private static func isLooseList(_ list: some Markup) -> Bool {
        var prevItemContentEnd: Int?
        for child in list.children {
            guard let range = child.range else { continue }
            // Blank line between consecutive items.
            if let prev = prevItemContentEnd,
               range.lowerBound.line > prev + 1 {
                return true
            }
            // Use the last child block's end, not the item's own range,
            // because swift-markdown extends the item range to include
            // trailing blank lines.
            if let item = child as? ListItem,
               let lastChild = item.children.reversed().first,
               let lastRange = lastChild.range {
                prevItemContentEnd = lastRange.upperBound.line
            } else {
                prevItemContentEnd = range.upperBound.line
            }

            // Blank line between block children within an item.
            if let item = child as? ListItem {
                var prevBlockEnd: Int?
                for block in item.children {
                    guard let br = block.range else { continue }
                    if let prev = prevBlockEnd,
                       br.lowerBound.line > prev + 1 {
                        return true
                    }
                    prevBlockEnd = br.upperBound.line
                }
            }
        }
        return false
    }
}
