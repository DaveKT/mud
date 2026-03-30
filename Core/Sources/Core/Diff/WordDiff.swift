import Markdown

/// A span in a word-level diff result.
enum WordSpan: Equatable {
    case unchanged(String)
    case inserted(String)
    case deleted(String)

    var text: String {
        switch self {
        case .unchanged(let t), .inserted(let t), .deleted(let t): return t
        }
    }

    var isUnchanged: Bool {
        if case .unchanged = self { return true } else { return false }
    }

    var isInserted: Bool {
        if case .inserted = self { return true } else { return false }
    }

    var isDeleted: Bool {
        if case .deleted = self { return true } else { return false }
    }
}

/// The result of a word-level diff, providing span lists for both sides.
///
/// `forNew` uses new-side token text in unchanged spans (for the blue
/// block, which walks the new AST). `forOld` uses old-side token text
/// (for the red block, which walks the old AST). The two lists have
/// the same structure — same sequence of unchanged/deleted/inserted —
/// but may differ in trailing whitespace on unchanged spans when a
/// word's position relative to the end of the text changes.
struct WordDiffResult {
    let forNew: [WordSpan]
    let forOld: [WordSpan]
}

/// Word-level diffing and inline structure comparison.
enum WordDiff {
    /// Computes a word-level diff between two plain-text strings.
    ///
    /// Tokenization splits on whitespace boundaries. Whitespace attaches
    /// to the preceding token (e.g., `"hello "` and `"world"`). Tokens
    /// are compared by their trimmed word content so that trailing
    /// whitespace differences (e.g., a word at the end of one text vs
    /// the middle of the other) do not cause false mismatches.
    ///
    /// Returns two span lists: `forNew` (for the blue block, using
    /// new-side token text) and `forOld` (for the red block, using
    /// old-side token text).
    static func diff(old: String, new: String) -> WordDiffResult {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        guard !oldTokens.isEmpty || !newTokens.isEmpty else {
            return WordDiffResult(forNew: [], forOld: [])
        }
        if oldTokens.isEmpty {
            let spans = newTokens.map { WordSpan.inserted($0) }
            return WordDiffResult(forNew: spans, forOld: spans)
        }
        if newTokens.isEmpty {
            let spans = oldTokens.map { WordSpan.deleted($0) }
            return WordDiffResult(forNew: spans, forOld: spans)
        }

        // Wrap tokens for trimmed comparison.
        let oldWrapped = oldTokens.map { DiffToken($0) }
        let newWrapped = newTokens.map { DiffToken($0) }

        // Use CollectionDifference to find the shortest edit script.
        let cdiff = newWrapped.difference(from: oldWrapped)

        var removedOld = Set<Int>()
        var insertedNew = Set<Int>()

        for change in cdiff {
            switch change {
            case .remove(let offset, _, _): removedOld.insert(offset)
            case .insert(let offset, _, _): insertedNew.insert(offset)
            }
        }

        // Find unchanged pairs (anchors) by walking both sequences
        // and skipping removed/inserted indices.
        var anchors: [(old: Int, new: Int)] = []
        var oi = 0, ni = 0
        while oi < oldTokens.count && ni < newTokens.count {
            if removedOld.contains(oi) { oi += 1; continue }
            if insertedNew.contains(ni) { ni += 1; continue }
            anchors.append((old: oi, new: ni))
            oi += 1; ni += 1
        }

        // Build both result lists: deletions before insertions within
        // each gap, anchors between gaps.
        var forNew: [WordSpan] = []
        var forOld: [WordSpan] = []

        let boundaries =
            [(-1, -1)]
            + anchors.map { ($0.old, $0.new) }
            + [(oldTokens.count, newTokens.count)]

        for i in 0..<(boundaries.count - 1) {
            let (prevOld, prevNew) = boundaries[i]
            let (nextOld, nextNew) = boundaries[i + 1]

            // Deleted tokens in this gap.
            for oi in (prevOld + 1)..<nextOld
                where removedOld.contains(oi) {
                forNew.append(.deleted(oldTokens[oi]))
                forOld.append(.deleted(oldTokens[oi]))
            }

            // Inserted tokens in this gap.
            for ni in (prevNew + 1)..<nextNew
                where insertedNew.contains(ni) {
                forNew.append(.inserted(newTokens[ni]))
                forOld.append(.inserted(newTokens[ni]))
            }

            // Emit the anchor (skip the terminal sentinel).
            if i + 1 < boundaries.count - 1 {
                let newText = newTokens[nextNew]
                let oldText = oldTokens[nextOld]
                forNew.append(.unchanged(newText))
                forOld.append(.unchanged(oldText))

                // If the old token has more trailing whitespace than
                // the new (e.g., "that " vs "that" at end of text),
                // emit the excess as a deleted span in forNew so the
                // blue block shows a space before deleted words.
                let oldWS = trailingWhitespaceCount(oldText)
                let newWS = trailingWhitespaceCount(newText)
                if oldWS > newWS {
                    forNew.append(.deleted(
                        String(oldText.suffix(oldWS - newWS))))
                }
            }
        }

        return WordDiffResult(
            forNew: factorOutSubstitutionWhitespace(forNew),
            forOld: factorOutSubstitutionWhitespace(forOld)
        )
    }

    /// Returns true if two markup nodes have the same inline formatting
    /// structure (ignoring text content).
    ///
    /// Compares only the sequence and nesting of formatting containers
    /// (Strong, Emphasis, InlineCode, Link, etc.). Text, SoftBreak,
    /// and LineBreak nodes are ignored — they carry content, not
    /// structure. If the formatting structure diverges, returns false
    /// and the caller falls back to block-level highlighting.
    static func hasMatchingStructure(
        _ old: Markup, _ new: Markup
    ) -> Bool {
        let oldFormatting = old.children.filter(isFormattingNode)
        let newFormatting = new.children.filter(isFormattingNode)
        guard oldFormatting.count == newFormatting.count else {
            return false
        }
        for (o, n) in zip(oldFormatting, newFormatting) {
            guard formattingTypeMatches(o, n) else { return false }
            // Recurse into formatting containers (except InlineCode,
            // which is a leaf with no structural children).
            if !(o is InlineCode) && !hasMatchingStructure(o, n) {
                return false
            }
        }
        return true
    }

    /// Returns true if a node is a formatting container (not a
    /// text-content leaf like Text, SoftBreak, or LineBreak).
    private static func isFormattingNode(_ node: Markup) -> Bool {
        node is Strong || node is Emphasis || node is Strikethrough
            || node is InlineCode || node is Link || node is Image
    }

    /// Returns true if two formatting nodes have the same type.
    private static func formattingTypeMatches(
        _ a: Markup, _ b: Markup
    ) -> Bool {
        switch (a, b) {
        case (is Strong, is Strong),
             (is Emphasis, is Emphasis),
             (is Strikethrough, is Strikethrough),
             (is InlineCode, is InlineCode),
             (is Link, is Link),
             (is Image, is Image):
            return true
        default:
            return false
        }
    }

    // MARK: - Whitespace normalization

    /// For consecutive deleted+inserted pairs, factors out common
    /// trailing whitespace as a separate unchanged span. This prevents
    /// the trailing space from being highlighted inside `<del>`/`<ins>`
    /// when only the word changed, not the space after it.
    private static func factorOutSubstitutionWhitespace(
        _ spans: [WordSpan]
    ) -> [WordSpan] {
        var result: [WordSpan] = []
        var i = 0
        while i < spans.count {
            if i + 1 < spans.count,
               case .deleted(let delText) = spans[i],
               case .inserted(let insText) = spans[i + 1] {
                let common = commonTrailingWhitespace(delText, insText)
                if !common.isEmpty {
                    let trimDel = String(delText.dropLast(common.count))
                    let trimIns = String(insText.dropLast(common.count))
                    if !trimDel.isEmpty { result.append(.deleted(trimDel)) }
                    if !trimIns.isEmpty { result.append(.inserted(trimIns)) }
                    result.append(.unchanged(common))
                    i += 2
                    continue
                }
            }
            result.append(spans[i])
            i += 1
        }
        return result
    }

    /// Returns the common trailing whitespace of two strings,
    /// matched from the end.
    private static func commonTrailingWhitespace(
        _ a: String, _ b: String
    ) -> String {
        var common = ""
        for (ac, bc) in zip(a.reversed(), b.reversed()) {
            if ac == bc && ac.isWhitespace {
                common = String(ac) + common
            } else {
                break
            }
        }
        return common
    }

    /// Counts trailing whitespace characters in a string.
    private static func trailingWhitespaceCount(_ text: String) -> Int {
        var count = 0
        for c in text.reversed() {
            if c.isWhitespace { count += 1 } else { break }
        }
        return count
    }

    // MARK: - Tokenization

    /// Splits text into word tokens with trailing whitespace attached
    /// to the preceding word. For example, `"the quick fox"` becomes
    /// `["the ", "quick ", "fox"]`.
    ///
    /// Runs of multiple whitespace characters attach to the preceding
    /// token. Leading whitespace (before any word) forms its own token.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var inWhitespace = false

        for char in text {
            if char.isWhitespace {
                current.append(char)
                inWhitespace = true
            } else {
                if inWhitespace {
                    tokens.append(current)
                    current = String(char)
                    inWhitespace = false
                } else {
                    current.append(char)
                }
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}

// MARK: - DiffToken

/// A token wrapper that compares by trimmed word content, so that
/// trailing whitespace differences (e.g., `"fox "` vs `"fox"`) do
/// not prevent matching.
private struct DiffToken: Hashable {
    let text: String
    let word: String

    init(_ text: String) {
        self.text = text
        self.word = text.trimmingCharacters(in: .whitespaces)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.word == rhs.word
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(word)
    }
}
