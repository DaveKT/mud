/// Detects and extracts YAML frontmatter from Markdown text, and
/// provides lightweight top-level key parsing for table rendering.
///
/// Front-matter must begin at line 1 with `---`, followed by a
/// newline, and be closed by `---` or `...` on its own line.
public enum FrontMatterExtractor {

    /// The result of frontmatter extraction.
    public struct Result {
        /// The raw YAML content between the opening and closing
        /// delimiters (without the delimiter lines themselves).
        public let yaml: String

        /// The Markdown content after the closing delimiter.
        public let body: String

        /// The number of source lines consumed by frontmatter
        /// (opening delimiter + content + closing delimiter).
        public let lineCount: Int
    }

    /// A parsed top-level YAML value.
    public enum FrontMatterValue: Equatable {
        /// A single-line scalar (e.g., `title: My Document`).
        /// Quoted values are preserved verbatim.
        case scalar(String)

        /// An inline array (e.g., `tags: [swift, markdown]`).
        case inlineArray([String])

        /// A multi-line or complex value (block arrays, nested
        /// mappings, literal/folded scalars). The raw indented
        /// YAML text is preserved.
        case block(String)
    }

    /// A parsed top-level key-value pair.
    public struct KeyValue {
        public let key: String
        public let value: FrontMatterValue
    }

    // MARK: - Detection and extraction

    /// Extracts YAML frontmatter from a Markdown string.
    ///
    /// Returns `nil` if no valid frontmatter is detected.
    /// Normalizes `\r\n` to `\n` before scanning.
    public static func extract(from markdown: String) -> Result? {
        // Normalize \r\n → \n. Swift treats \r\n as a single
        // grapheme cluster, so splitting on "\n" alone won't work.
        let normalized = markdown.replacingOccurrences(
            of: "\r\n", with: "\n")
        let lines = normalized.split(
            separator: "\n", omittingEmptySubsequences: false)

        guard !lines.isEmpty,
              isDelimiter(lines[0], opening: true)
        else { return nil }

        for i in 1..<lines.count {
            if isDelimiter(lines[i], opening: false) {
                let yaml = lines[1..<i].joined(separator: "\n")
                let body = lines[(i + 1)...].joined(separator: "\n")
                return Result(
                    yaml: yaml, body: body, lineCount: i + 1)
            }
        }

        return nil
    }

    // MARK: - Top-level key parsing

    /// Parses top-level YAML keys from a raw YAML string.
    ///
    /// Returns an empty array if no keys are found (e.g., the
    /// frontmatter is all comments or empty).
    public static func parseTopLevelKeys(
        _ yaml: String
    ) -> [KeyValue] {
        guard !yaml.isEmpty else { return [] }

        var result: [KeyValue] = []
        var currentKey: String?
        var currentValue: String = ""
        var continuationLines: [String] = []

        for line in yaml.split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })

            // Comment-only line at top level.
            if trimmed.hasPrefix("#") && !line.hasPrefix(" ")
                && !line.hasPrefix("\t")
            {
                // Top-level comment — skip, don't attach to any key.
                continue
            }

            // Continuation line (indented).
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if currentKey != nil {
                    continuationLines.append(String(line))
                }
                continue
            }

            // New top-level key — flush previous.
            if let key = currentKey {
                result.append(KeyValue(
                    key: key,
                    value: buildValue(
                        currentValue, continuation: continuationLines)))
            }

            // Parse key: value.
            if let colonIndex = line.firstIndex(of: ":"),
               colonIndex > line.startIndex
            {
                let key = String(line[..<colonIndex]).trimmingCharacters(
                    in: .whitespaces)
                let afterColon = line[line.index(after: colonIndex)...]
                    .trimmingCharacters(in: .whitespaces)
                currentKey = key
                currentValue = afterColon
                continuationLines = []
            } else {
                // Line doesn't look like a key — reset.
                currentKey = nil
                currentValue = ""
                continuationLines = []
            }
        }

        // Flush last key.
        if let key = currentKey {
            result.append(KeyValue(
                key: key,
                value: buildValue(
                    currentValue, continuation: continuationLines)))
        }

        return result
    }

    // MARK: - Private

    /// Checks whether a line is a frontmatter delimiter.
    ///
    /// Delimiters must start with `---` (or `...` for closing) at
    /// column 1 — no leading whitespace. Trailing whitespace is
    /// accepted.
    private static func isDelimiter(
        _ line: some StringProtocol, opening: Bool
    ) -> Bool {
        var content = line[...]
        // Trim only trailing whitespace.
        while content.last == " " || content.last == "\t" {
            content = content.dropLast()
        }
        if content == "---" { return true }
        if !opening && content == "..." { return true }
        return false
    }

    /// Builds a `FrontMatterValue` from a first-line value string
    /// and any continuation lines.
    private static func buildValue(
        _ firstLine: String,
        continuation: [String]
    ) -> FrontMatterValue {
        if continuation.isEmpty {
            return parseScalarOrInlineArray(firstLine)
        }

        // Has continuation lines — build block value.
        if firstLine.isEmpty {
            return .block(continuation.joined(separator: "\n"))
        }
        return .block(
            ([firstLine] + continuation).joined(separator: "\n"))
    }

    /// Parses a single-line value as either an inline array or
    /// a scalar.
    private static func parseScalarOrInlineArray(
        _ value: String
    ) -> FrontMatterValue {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            let inner = trimmed.dropFirst().dropLast()
            let elements = inner.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return .inlineArray(elements)
        }
        return .scalar(trimmed)
    }
}
