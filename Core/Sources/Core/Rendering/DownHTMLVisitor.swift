import Foundation
import Markdown

/// Produces syntax-highlighted HTML from raw Markdown source by
/// walking the swift-markdown AST and wrapping recognized nodes in
/// `<span class="md-*">` tags.  All source text is HTML-escaped in
/// the output.
public struct DownHTMLVisitor: Sendable {

    public init() {}

    /// Returns a `<div class="down-lines">` container with one
    /// flex-row per source line, line numbers, syntax-highlight
    /// spans, and scrollable code-block regions.
    public func highlight(
        _ markdown: String,
        doccAlertMode: DocCAlertMode = .extended
    ) -> String {
        let result = highlightLines(markdown, doccAlertMode: doccAlertMode)
        return buildLayout(
            result.rendered, codeBlocks: result.codeBlocks)
    }

    /// Renders with change-tracking markers for Down mode.
    ///
    /// Highlights both old and new markdown, builds a `LineDiffMap`
    /// from block matches, and produces a layout that interleaves
    /// deleted old-doc lines and annotates inserted/modified new-doc
    /// lines.
    func highlightWithChanges(
        new newMarkdown: String,
        old oldMarkdown: String,
        matches: [BlockMatch],
        doccAlertMode: DocCAlertMode = .extended
    ) -> String {
        let newResult = highlightLines(
            newMarkdown, doccAlertMode: doccAlertMode)
        let oldResult = highlightLines(
            oldMarkdown, doccAlertMode: doccAlertMode)
        let diffMap = LineDiffMap(matches: matches)
        return buildLayoutWithChanges(
            newResult.rendered,
            codeBlocks: newResult.codeBlocks,
            diffMap: diffMap,
            oldRendered: oldResult.rendered)
    }

    // MARK: - Phase 1+2: Highlight lines

    private struct HighlightResult {
        let rendered: [String]
        let codeBlocks: [CodeBlockInfo]
    }

    /// Runs Phase 1 (AST event collection) and Phase 2 (per-line
    /// rendering) without building the final layout.
    private func highlightLines(
        _ markdown: String,
        doccAlertMode: DocCAlertMode
    ) -> HighlightResult {
        // Phase 1: Collect span events and code block info.
        let doc = MarkdownParser.parse(markdown)
        let sourceLines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map { Array($0.utf8) }

        var alertDetector = AlertDetector()
        alertDetector.doccAlertMode = doccAlertMode
        var collector = EventCollector(sourceLines: sourceLines)
        collector.alertDetector = alertDetector
        collector.visit(doc)
        var events = collector.events
        events.sort()

        // Phase 2: Render per-line HTML content strings.
        let lines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
        let lineCount = markdown.hasSuffix("\n") && !lines.isEmpty
            ? lines.count - 1
            : max(lines.count, 1)
        let rendered = renderLineContent(
            lines: lines, lineCount: lineCount,
            events: events, codeBlocks: collector.codeBlocks)

        return HighlightResult(
            rendered: rendered, codeBlocks: collector.codeBlocks)
    }

    // MARK: - SpanEvent

    private struct SpanEvent: Comparable {
        let line: Int32
        let column: Int32
        let isClose: Bool
        let depth: Int32
        let cssClass: String

        static func < (lhs: SpanEvent, rhs: SpanEvent) -> Bool {
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            if lhs.column != rhs.column {
                return lhs.column < rhs.column
            }
            // Close before open at the same position.
            if lhs.isClose != rhs.isClose { return lhs.isClose }
            // Inner closes first; outer opens first.
            return lhs.isClose
                ? lhs.depth > rhs.depth
                : lhs.depth < rhs.depth
        }
    }

    private struct CodeBlockInfo {
        let isFenced: Bool
        let contentFirstLine: Int
        let contentLastLine: Int
        let highlightedLines: [String]

        var hasContent: Bool { contentFirstLine <= contentLastLine }
    }

    // MARK: - Phase 1: Collect events from the AST

    private struct EventCollector: MarkupWalker {
        let sourceLines: [[UInt8]]
        var events: [SpanEvent] = []
        var codeBlocks: [CodeBlockInfo] = []
        var alertDetector = AlertDetector()

        // -- Container nodes --

        mutating func visitHeading(_ heading: Heading) {
            emitContainer(heading, cssClass: "md-heading")
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            let depth = Self.nodeDepth(blockQuote)
            if let (category, _) = alertDetector.detectGFMAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                let tag = "[!\(category.rawValue.uppercased())]"
                emitAlertTagSpan(in: blockQuote, tagLen: tag.utf8.count,
                                 depth: depth)
            } else if let (category, _, _) = alertDetector.detectDocCAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                if let aside = Aside(blockQuote,
                                     tagRequirement: .requireAnyLengthTag) {
                    emitAlertTagSpan(in: blockQuote,
                                     tagLen: aside.kind.rawValue.utf8.count + 1,
                                     depth: depth)
                }
            } else {
                emitContainer(blockQuote, cssClass: "md-blockquote")
            }
        }

        /// Emits a 1-character `md-alert-tag` span over the `>` marker
        /// on every line of the blockquote.
        private mutating func emitAlertMarkers(
            in blockQuote: BlockQuote, depth: Int32
        ) {
            guard let range = blockQuote.range else { return }
            let col = range.lowerBound.column
            for line in range.lowerBound.line...range.upperBound.line {
                emitSpan("md-alert-tag", depth: depth + 1,
                         from: (line: line, column: col),
                         to:   (line: line, column: col + 1))
            }
        }

        /// Emits a nested `md-alert-tag` span covering the tag text
        /// (e.g. `[!NOTE]` or `Note:`) on the first line of a blockquote.
        private mutating func emitAlertTagSpan(
            in blockQuote: BlockQuote, tagLen: Int, depth: Int32
        ) {
            guard let para = Array(blockQuote.children).first as? Paragraph,
                  let textNode = Array(para.children).first as? Text,
                  let range = textNode.range else { return }
            let line = range.lowerBound.line
            let col  = range.lowerBound.column
            emitSpan("md-alert-tag", depth: depth + 2,
                     from: (line: line, column: col),
                     to:   (line: line, column: col + tagLen))
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            emitContainer(emphasis, cssClass: "md-emphasis")
        }

        mutating func visitStrong(_ strong: Strong) {
            emitContainer(strong, cssClass: "md-strong")
        }

        mutating func visitLink(_ link: Markdown.Link) {
            emitContainer(link, cssClass: "md-link")
        }

        mutating func visitImage(_ image: Image) {
            emitContainer(image, cssClass: "md-image")
        }

        mutating func visitStrikethrough(
            _ strikethrough: Strikethrough
        ) {
            emitContainer(strikethrough, cssClass: "md-strikethrough")
        }

        mutating func visitTable(_ table: Table) {
            emitContainer(table, cssClass: "md-table")
        }

        mutating func visitListItem(_ listItem: ListItem) {
            if listItem.checkbox != nil {
                emitContainer(listItem, cssClass: "md-task")
            } else {
                descendInto(listItem)
            }
        }

        // -- Leaf nodes --

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            guard let range = codeBlock.range else { return }
            let depth = Self.nodeDepth(codeBlock)
            let fenceLen = measureFence(at: range.lowerBound)

            if fenceLen > 0 {
                // -- Fenced code block: fence / content / fence --

                // Opening fence line.
                let openLineLen = lineLen(range.lowerBound.line)
                emitSpan("md-code-fence", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (range.lowerBound.line,
                              openLineLen + 1))

                // Content lines (between the fences), if any.
                let firstContent = range.lowerBound.line + 1
                let lastContent = range.upperBound.line - 1
                var highlighted: [String] = []
                if firstContent <= lastContent {
                    let lastLen = lineLen(lastContent)
                    emitSpan("md-code-block", depth: depth,
                             from: (firstContent, 1),
                             to: (lastContent,
                                  max(lastLen, 1) + 1))

                    if let html = CodeHighlighter.highlight(
                        codeBlock.code,
                        language: codeBlock.language)
                    {
                        highlighted = HTMLLineSplitter
                            .splitByLine(html)
                    }
                }

                // Closing fence line.
                let closeLineLen = lineLen(range.upperBound.line)
                emitSpan("md-code-fence", depth: depth,
                         from: (range.upperBound.line, 1),
                         to: (range.upperBound.line,
                              closeLineLen + 1))

                // Info string (language name) on the opening
                // fence, nested inside md-code-fence.
                if let lang = codeBlock.language, !lang.isEmpty {
                    let infoCol = range.lowerBound.column + fenceLen
                    emitSpan("md-code-info", depth: depth + 1,
                             from: (range.lowerBound.line, infoCol),
                             to: (range.lowerBound.line,
                                  infoCol + lang.utf8.count))
                }

                // Always record for layout, even when empty.
                codeBlocks.append(CodeBlockInfo(
                    isFenced: true,
                    contentFirstLine: firstContent,
                    contentLastLine: lastContent,
                    highlightedLines: highlighted))

            } else {
                // -- Indented code block: content only --
                let lineCount = codeBlock.code.lazy
                    .filter { $0 == "\n" }.count
                let lastLine = range.lowerBound.line
                    + max(lineCount, 1) - 1
                let lastLen = lineLen(lastLine)
                emitSpan("md-code-block", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (lastLine, lastLen + 1))

                codeBlocks.append(CodeBlockInfo(
                    isFenced: false,
                    contentFirstLine: range.lowerBound.line,
                    contentLastLine: lastLine,
                    highlightedLines: []))
            }
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            emitLeaf(inlineCode, cssClass: "md-code")
        }

        mutating func visitThematicBreak(
            _ thematicBreak: ThematicBreak
        ) {
            emitLeaf(thematicBreak, cssClass: "md-hr")
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) {
            emitLeaf(html, cssClass: "md-html")
        }

        mutating func visitInlineHTML(_ html: InlineHTML) {
            emitLeaf(html, cssClass: "md-html")
        }

        // -- Helpers --

        /// Emit open event, descend into children, emit close event.
        private mutating func emitContainer(
            _ node: some Markup, cssClass: String
        ) {
            guard let range = node.range else {
                descendInto(node)
                return
            }
            let depth = Self.nodeDepth(node)
            events.append(SpanEvent(
                line: Int32(range.lowerBound.line),
                column: Int32(range.lowerBound.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            descendInto(node)
            events.append(SpanEvent(
                line: Int32(range.upperBound.line),
                column: Int32(range.upperBound.column) + 1,
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// Emit open and close events for a leaf node (no children).
        private mutating func emitLeaf(
            _ node: some Markup, cssClass: String
        ) {
            guard let range = node.range else { return }
            let depth = Self.nodeDepth(node)
            events.append(SpanEvent(
                line: Int32(range.lowerBound.line),
                column: Int32(range.lowerBound.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            events.append(SpanEvent(
                line: Int32(range.upperBound.line),
                column: Int32(range.upperBound.column) + 1,
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// Emit an open/close event pair for a span at explicit
        /// (line, column) positions.
        private mutating func emitSpan(
            _ cssClass: String, depth: Int32,
            from open: (line: Int, column: Int),
            to close: (line: Int, column: Int)
        ) {
            events.append(SpanEvent(
                line: Int32(open.line),
                column: Int32(open.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            events.append(SpanEvent(
                line: Int32(close.line),
                column: Int32(close.column),
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// UTF-8 byte length of a source line (1-based line number).
        private func lineLen(_ line: Int) -> Int {
            let idx = line - 1
            guard idx >= 0, idx < sourceLines.count else { return 0 }
            return sourceLines[idx].count
        }

        private static func nodeDepth(_ node: some Markup) -> Int32 {
            var depth: Int32 = 0
            var current = node.parent
            while current != nil {
                depth += 1
                current = current?.parent
            }
            return depth
        }

        /// Count consecutive fence characters (backtick or tilde) at
        /// the given source position to determine fence length.
        private func measureFence(
            at location: SourceLocation
        ) -> Int {
            let lineIdx = location.line - 1
            guard lineIdx >= 0, lineIdx < sourceLines.count else {
                return 0
            }
            let line = sourceLines[lineIdx]
            let colIdx = location.column - 1
            guard colIdx >= 0, colIdx < line.count else { return 0 }

            let fenceChar = line[colIdx]
            guard fenceChar == 0x60 || fenceChar == 0x7E else {
                return 0  // Not a backtick or tilde
            }
            var len = 0
            while colIdx + len < line.count,
                  line[colIdx + len] == fenceChar {
                len += 1
            }
            return len
        }
    }

    // MARK: - Phase 2: Render per-line HTML content

    /// Produces one HTML content string per source line by applying
    /// span events (or substituting highlight.js output for code
    /// blocks).  Knows nothing about layout or line numbers.
    private func renderLineContent(
        lines: [Substring],
        lineCount: Int,
        events: [SpanEvent],
        codeBlocks: [CodeBlockInfo]
    ) -> [String] {
        var rendered: [String] = []
        rendered.reserveCapacity(lineCount)
        var openSpans: [String] = []
        var ei = 0

        for lineIdx in 0..<lineCount {
            let lineNum = Int32(lineIdx + 1)
            var content = ""

            // Reopen spans carried from the previous line.
            for cls in openSpans {
                content += "<span class=\"\(cls)\">"
            }

            // Emit line content — highlighted or escaped.
            if let highlighted = highlightedLine(
                lineNum, codeBlocks: codeBlocks)
            {
                // Process span events at line start (e.g.
                // md-code-block open) before the content.
                while ei < events.count,
                      events[ei].line == lineNum,
                      events[ei].column <= 1
                {
                    emitTag(events[ei], to: &content,
                            openSpans: &openSpans)
                    ei += 1
                }
                content += highlighted
            } else if lineIdx < lines.count {
                emitLineContent(
                    lines[lineIdx], lineNum: lineNum,
                    events: events, ei: &ei,
                    result: &content, openSpans: &openSpans)
            }

            // Flush events past end of visible content (close tags).
            while ei < events.count, events[ei].line == lineNum {
                emitTag(events[ei], to: &content,
                        openSpans: &openSpans)
                ei += 1
            }

            // Close all open spans at the line boundary.
            for _ in openSpans { content += "</span>" }

            rendered.append(content)
        }

        return rendered
    }

    /// Emit one line's content, escaping text in segments between
    /// event positions rather than byte-by-byte.
    private func emitLineContent(
        _ line: Substring,
        lineNum: Int32,
        events: [SpanEvent],
        ei: inout Int,
        result: inout String,
        openSpans: inout [String]
    ) {
        let utf8 = line.utf8
        let lineLen = Int32(utf8.count)
        var segStart = utf8.startIndex
        var col: Int32 = 1

        // Process events whose column falls within the line.
        while ei < events.count,
              events[ei].line == lineNum,
              events[ei].column <= lineLen
        {
            let targetCol = events[ei].column
            if targetCol > col {
                let segEnd = utf8.index(
                    segStart, offsetBy: Int(targetCol - col))
                result += HTMLEscaping.escape(
                    String(line[segStart..<segEnd]))
                segStart = segEnd
                col = targetCol
            }
            emitTag(events[ei], to: &result,
                    openSpans: &openSpans)
            ei += 1
        }

        // Emit remaining content after the last event.
        if segStart < utf8.endIndex {
            result += HTMLEscaping.escape(String(line[segStart...]))
        }
    }

    private func emitTag(
        _ event: SpanEvent,
        to result: inout String,
        openSpans: inout [String]
    ) {
        if event.isClose {
            result += "</span>"
            if let idx = openSpans.lastIndex(of: event.cssClass) {
                openSpans.remove(at: idx)
            }
        } else {
            result += "<span class=\"\(event.cssClass)\">"
            openSpans.append(event.cssClass)
        }
    }

    private func highlightedLine(
        _ lineNum: Int32,
        codeBlocks: [CodeBlockInfo]
    ) -> String? {
        let n = Int(lineNum)
        for cb in codeBlocks {
            guard !cb.highlightedLines.isEmpty,
                  n >= cb.contentFirstLine,
                  n <= cb.contentLastLine
            else { continue }
            let idx = n - cb.contentFirstLine
            return idx < cb.highlightedLines.count
                ? cb.highlightedLines[idx] : nil
        }
        return nil
    }

    // MARK: - Phase 3: Build structural layout

    /// Wraps rendered line content in the div-based layout with
    /// line numbers, `.dc-fence` / `.dc-code` classes, and
    /// `.dc-scroll` wrappers around code block regions.
    private func buildLayout(
        _ rendered: [String],
        codeBlocks: [CodeBlockInfo]
    ) -> String {
        // Build a lookup of line roles from code block metadata.
        let roles = lineRoles(
            lineCount: rendered.count, codeBlocks: codeBlocks)

        var html = "<div class=\"down-lines\">"
        var inScroll = false

        for (i, content) in rendered.enumerated() {
            let lineNum = i + 1
            let role = roles[i]

            // Open dc-scroll wrapper before the first fence/code line.
            if (role == .fence || role == .code) && !inScroll {
                html += "<div class=\"dc-scroll\">"
                inScroll = true
            }

            // Line div with role-specific class.
            switch role {
            case .regular:
                html += "<div class=\"dl\">"
            case .fence:
                html += "<div class=\"dl dc-fence\">"
            case .code:
                html += "<div class=\"dl dc-code\">"
            }

            html += "<span class=\"ln\">\(lineNum)</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"

            // Close dc-scroll wrapper after the last fence/code line.
            if inScroll {
                let nextRole = i + 1 < roles.count
                    ? roles[i + 1] : .regular
                if nextRole != .fence && nextRole != .code {
                    html += "</div>"
                    inScroll = false
                }
            }
        }

        html += "</div>"
        return html
    }

    private enum LineRole {
        case regular, fence, code
    }

    /// Classifies each source line based on code block metadata.
    private func lineRoles(
        lineCount: Int,
        codeBlocks: [CodeBlockInfo]
    ) -> [LineRole] {
        var roles = [LineRole](repeating: .regular, count: lineCount)
        for cb in codeBlocks {
            if cb.hasContent {
                for line in cb.contentFirstLine...cb.contentLastLine {
                    let idx = line - 1
                    if idx >= 0, idx < lineCount {
                        roles[idx] = .code
                    }
                }
            }
            if cb.isFenced {
                let openFence = cb.contentFirstLine - 2
                let closeFence = cb.contentLastLine
                if openFence >= 0, openFence < lineCount {
                    roles[openFence] = .fence
                }
                if closeFence >= 0, closeFence < lineCount {
                    roles[closeFence] = .fence
                }
            }
        }
        return roles
    }

    // MARK: - Phase 3 (diff-aware): Build layout with changes

    /// Variant of `buildLayout` that interleaves deleted old-doc lines
    /// and annotates inserted/modified new-doc lines.
    private func buildLayoutWithChanges(
        _ rendered: [String],
        codeBlocks: [CodeBlockInfo],
        diffMap: LineDiffMap,
        oldRendered: [String]
    ) -> String {
        let roles = lineRoles(
            lineCount: rendered.count, codeBlocks: codeBlocks)

        var html = "<div class=\"down-lines\">"
        var inScroll = false
        var groupIdx = 0

        for (i, content) in rendered.enumerated() {
            let lineNum = i + 1
            let role = roles[i]

            // Emit deletion groups that precede this line.
            while groupIdx < diffMap.deletionGroups.count,
                  diffMap.deletionGroups[groupIdx].beforeNewLine <= lineNum
            {
                emitDeletionGroup(
                    diffMap.deletionGroups[groupIdx],
                    oldRendered: oldRendered, to: &html)
                groupIdx += 1
            }

            // Open dc-scroll wrapper before the first fence/code line.
            if (role == .fence || role == .code) && !inScroll {
                html += "<div class=\"dc-scroll\">"
                inScroll = true
            }

            // Line div: combine role class with optional change class.
            let roleClass: String
            switch role {
            case .regular: roleClass = "dl"
            case .fence:   roleClass = "dl dc-fence"
            case .code:    roleClass = "dl dc-code"
            }

            if let annotation = diffMap.annotation(forLine: lineNum) {
                html += "<div class=\"\(roleClass) dl-ins\""
                html += " data-change-id=\"\(annotation.changeID)\">"
            } else {
                html += "<div class=\"\(roleClass)\">"
            }

            html += "<span class=\"ln\">\(lineNum)</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"

            // Close dc-scroll wrapper after the last fence/code line.
            if inScroll {
                let nextRole = i + 1 < roles.count
                    ? roles[i + 1] : .regular
                if nextRole != .fence && nextRole != .code {
                    html += "</div>"
                    inScroll = false
                }
            }
        }

        // Trailing deletion groups.
        while groupIdx < diffMap.deletionGroups.count {
            emitDeletionGroup(
                diffMap.deletionGroups[groupIdx],
                oldRendered: oldRendered, to: &html)
            groupIdx += 1
        }

        html += "</div>"
        return html
    }

    /// Emits a deletion group's lines into the HTML output.
    private func emitDeletionGroup(
        _ group: DeletionGroup,
        oldRendered: [String],
        to html: inout String
    ) {
        for oldLine in group.oldLineRange {
            let oldIdx = oldLine - 1
            let content = oldIdx >= 0 && oldIdx < oldRendered.count
                ? oldRendered[oldIdx] : ""
            html += "<div class=\"dl dl-del\""
            html += " data-change-id=\"\(group.changeID)\">"
            html += "<span class=\"ln\">\u{2013}</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"
        }
    }

}
