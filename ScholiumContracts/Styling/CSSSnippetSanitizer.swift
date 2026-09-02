import Foundation

public struct CSSSnippetProjection: Sendable, Equatable {
    public let readCSS: String
    public let livePreviewCSS: String

    public init(readCSS: String, livePreviewCSS: String) {
        self.readCSS = readCSS
        self.livePreviewCSS = livePreviewCSS
    }
}

public enum CSSSnippetSanitizationError: LocalizedError, Equatable {
    case tooLarge
    case forbiddenConstruct(String)
    case malformed(String)
    case unsupportedSelector(String)
    case unsupportedProperty(String)

    public var errorDescription: String? {
        switch self {
        case .tooLarge:
            "The CSS snippet is larger than 1 MB."
        case .forbiddenConstruct(let construct):
            "The CSS snippet contains a forbidden construct: \(construct)."
        case .malformed(let reason):
            "The CSS snippet is malformed: \(reason)."
        case .unsupportedSelector(let selector):
            "The selector is not supported by Scholium: \(selector)."
        case .unsupportedProperty(let property):
            "The CSS property is not supported by Scholium: \(property)."
        }
    }
}

/// Parses and scopes the deliberately small CSS surface that Scholium exposes
/// to research workspaces. This is not a browser CSS validator: unsupported or
/// ambiguous syntax is rejected instead of being passed through to WebKit.
public enum CSSSnippetSanitizer {
    public static let maximumUTF8Size = 1_048_576
    /// Human-readable snippet names are configuration labels, never markup.
    /// Normalize them so a name can never become an HTML or CSS construct
    /// even if a future consumer reintroduces names into generated output.
    public static let maximumSnippetNameLength = 120

    private static let protectedSelectorFragments = [
        "scholium-callout", "footnote", "review", "diagnostic", "provenance",
        "source-warning", "data-scholium-protected", "researcher-comment", "scholium-preview",
        "workflow-gate", "cm-live-callout", "scholium-link-annotation",
        "cm-live-link-annotation"
    ]

    private static let allowedElements: Set<String> = [
        "body", "main", "h1", "h2", "h3", "h4", "h5", "h6", "p", "a",
        "mark", "blockquote", "ul", "ol", "li", "table", "thead", "tbody",
        "tr", "th", "td", "pre", "code", "hr", "strong", "em"
    ]

    private static let allowedClasses: Set<String> = [
        "scholium-document", "scholium-highlight"
    ]

    private static let allowedProperties: Set<String> = [
        "color", "background", "background-color", "font-family", "font-size",
        "font-style", "font-weight", "font-variant", "line-height",
        "letter-spacing", "word-spacing", "text-align", "text-decoration",
        "text-decoration-color", "text-decoration-style", "text-indent",
        "text-transform", "max-width", "margin", "margin-block",
        "margin-block-start", "margin-block-end", "margin-inline",
        "margin-inline-start", "margin-inline-end", "padding", "padding-block",
        "padding-block-start", "padding-block-end", "padding-inline",
        "padding-inline-start", "padding-inline-end", "border", "border-color",
        "border-style", "border-width", "border-radius", "box-shadow",
        "list-style", "list-style-position"
    ]

    private static let liveSelectorMap: [String: [String]] = [
        "body": [".cm-editor.scholium-live-mode .cm-content"],
        "main": [".cm-editor.scholium-live-mode .cm-content"],
        ".scholium-document": [".cm-editor.scholium-live-mode .cm-content"],
        "h1": [".scholium-live-mode .cm-live-h1"],
        "h2": [".scholium-live-mode .cm-live-h2"],
        "h3": [".scholium-live-mode .cm-live-h3"],
        "h4": [".scholium-live-mode .cm-live-h4"],
        "h5": [".scholium-live-mode .cm-live-h5"],
        "h6": [".scholium-live-mode .cm-live-h6"],
        "p": [".scholium-live-mode .cm-live-paragraph"],
        "a": [".scholium-live-mode .cm-live-link", ".scholium-live-mode .cm-live-wikilink"],
        "mark": [".scholium-live-mode .cm-live-highlight"],
        ".scholium-highlight": [".scholium-live-mode .cm-live-highlight"],
        "blockquote": [".scholium-live-mode .cm-live-quote"],
        "pre": [".scholium-live-mode .cm-live-code-block"],
        "code": [".scholium-live-mode .cm-live-code"],
        "hr": [".scholium-live-mode .cm-live-rule"],
        "strong": [".scholium-live-mode .cm-live-strong"],
        "em": [".scholium-live-mode .cm-live-emphasis"]
    ]

    public static func sanitize(_ source: String) throws -> CSSSnippetProjection {
        guard source.utf8.count <= maximumUTF8Size else { throw CSSSnippetSanitizationError.tooLarge }
        let lower = source.lowercased()
        for forbidden in ["@import", "url(", "!important", "expression(", "javascript:", "file:", "</style", "<script"] {
            if lower.contains(forbidden) {
                throw CSSSnippetSanitizationError.forbiddenConstruct(forbidden)
            }
        }
        guard !source.contains("<"), !source.contains(">") else {
            throw CSSSnippetSanitizationError.forbiddenConstruct("HTML delimiter")
        }

        let commentFree = try removeComments(from: source)
        let rules = try parseRules(from: commentFree)
        var readRules: [String] = []
        var liveRules: [String] = []

        for rule in rules {
            let declarations = try sanitizeDeclarations(rule.declarations)
            let selectors = try splitSelectors(rule.selector)
            let readSelectors = try selectors.map(scopeReadSelector)
            let liveSelectors = selectors.flatMap(scopeLiveSelector)
            readRules.append("\(readSelectors.joined(separator: ",\n")) {\n\(declarations)\n}")
            if !liveSelectors.isEmpty {
                liveRules.append("\(liveSelectors.joined(separator: ",\n")) {\n\(declarations)\n}")
            }
        }
        return CSSSnippetProjection(
            readCSS: readRules.joined(separator: "\n\n"),
            livePreviewCSS: liveRules.joined(separator: "\n\n")
        )
    }

    /// Normalizes a machine-local CSS snippet display name for safe storage
    /// and presentation. Control characters, HTML delimiters, and Unicode
    /// line separators are removed (never interpreted), leading/trailing
    /// whitespace is trimmed, and the result is bounded in length. An empty
    /// result falls back to ``fallback`` so callers never persist an empty
    /// label.
    public static func normalizedSnippetName(
        _ requestedName: String,
        fallback: String
    ) -> String {
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmed.filter { character in
            !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
                && character != "<"
                && character != ">"
                && character != "\u{2028}"
                && character != "\u{2029}"
        }
        let normalized = String(filtered.prefix(maximumSnippetNameLength))
        return normalized.isEmpty ? fallback : normalized
    }

    private struct Rule {
        let selector: String
        let declarations: String
    }

    private static func removeComments(from source: String) throws -> String {
        var result = ""
        var index = source.startIndex
        while index < source.endIndex {
            if source[index...].hasPrefix("/*") {
                guard let end = source[index...].range(of: "*/") else {
                    throw CSSSnippetSanitizationError.malformed("an unterminated comment")
                }
                result.append(" ")
                index = end.upperBound
            } else {
                result.append(source[index])
                index = source.index(after: index)
            }
        }
        return result
    }

    private static func parseRules(from source: String) throws -> [Rule] {
        var rules: [Rule] = []
        var index = source.startIndex
        while true {
            while index < source.endIndex, source[index].isWhitespace { index = source.index(after: index) }
            guard index < source.endIndex else { break }
            let selectorStart = index
            guard let open = source[index...].firstIndex(of: "{") else {
                throw CSSSnippetSanitizationError.malformed("a rule has no opening brace")
            }
            let selector = source[selectorStart..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selector.isEmpty else { throw CSSSnippetSanitizationError.malformed("an empty selector") }
            guard !selector.hasPrefix("@") else {
                throw CSSSnippetSanitizationError.forbiddenConstruct(selector)
            }
            let declarationStart = source.index(after: open)
            guard let close = source[declarationStart...].firstIndex(of: "}") else {
                throw CSSSnippetSanitizationError.malformed("a rule has no closing brace")
            }
            let declarations = String(source[declarationStart..<close])
            if declarations.contains("{") {
                throw CSSSnippetSanitizationError.forbiddenConstruct("nested or at-rule block")
            }
            rules.append(Rule(selector: String(selector), declarations: declarations))
            index = source.index(after: close)
        }
        return rules
    }

    private static func splitSelectors(_ selectorList: String) throws -> [String] {
        let selectors = selectorList.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !selectors.isEmpty, selectors.allSatisfy({ !$0.isEmpty }) else {
            throw CSSSnippetSanitizationError.malformed("an empty selector")
        }
        return selectors
    }

    private static func validateSelector(_ selector: String) throws {
        let lower = selector.lowercased()
        if protectedSelectorFragments.contains(where: lower.contains) {
            throw CSSSnippetSanitizationError.forbiddenConstruct("protected selector \(selector)")
        }
        for forbidden in ["#", "*", "[", "]", ":", "+", "~", "(", ")", "{"] where selector.contains(forbidden) {
            throw CSSSnippetSanitizationError.unsupportedSelector(selector)
        }
        let compounds = selector.split(whereSeparator: { $0.isWhitespace || $0 == ">" }).map(String.init)
        guard !compounds.isEmpty else { throw CSSSnippetSanitizationError.unsupportedSelector(selector) }
        for compound in compounds {
            if compound.hasPrefix(".") {
                guard allowedClasses.contains(String(compound.dropFirst())) else {
                    throw CSSSnippetSanitizationError.unsupportedSelector(selector)
                }
            } else if !allowedElements.contains(compound.lowercased()) {
                throw CSSSnippetSanitizationError.unsupportedSelector(selector)
            }
        }
    }

    private static func scopeReadSelector(_ selector: String) throws -> String {
        try validateSelector(selector)
        if selector == ".scholium-document" || selector.hasPrefix(".scholium-document ") {
            return selector
        }
        if selector == "body" || selector == "main" { return ".scholium-document" }
        return ".scholium-document \(selector)"
    }

    private static func scopeLiveSelector(_ selector: String) -> [String] {
        let normalized = selector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mapped = liveSelectorMap[normalized] { return mapped }
        if normalized.hasPrefix(".scholium-document ") {
            let suffix = String(normalized.dropFirst(".scholium-document ".count))
            return liveSelectorMap[suffix] ?? []
        }
        return []
    }

    private static func sanitizeDeclarations(_ source: String) throws -> String {
        var declarations: [String] = []
        for raw in source.split(separator: ";", omittingEmptySubsequences: true) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let colon = text.firstIndex(of: ":") else {
                throw CSSSnippetSanitizationError.malformed("a declaration has no colon: \(text)")
            }
            let property = text[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !property.isEmpty, !value.isEmpty else {
                throw CSSSnippetSanitizationError.malformed("an empty property or value")
            }
            guard allowedProperties.contains(property) || property.hasPrefix("--scholium-user-") else {
                throw CSSSnippetSanitizationError.unsupportedProperty(property)
            }
            if property == "font-size", isZeroCSSLength(value) {
                throw CSSSnippetSanitizationError.forbiddenConstruct(
                    "font-size that hides document content"
                )
            }
            let lowerValue = value.lowercased()
            if ["url(", "!important", "expression(", "javascript:", "file:", "@"].contains(where: lowerValue.contains) {
                throw CSSSnippetSanitizationError.forbiddenConstruct("value for \(property)")
            }
            declarations.append("  \(property): \(value);")
        }
        guard !declarations.isEmpty else {
            throw CSSSnippetSanitizationError.malformed("an empty declaration block")
        }
        return declarations.joined(separator: "\n")
    }

    /// CSS opacity compounds through ancestors and cannot be repaired on a
    /// protected descendant, so it is deliberately absent from the supported
    /// property set. Zero font sizes receive a second, value-level guard while
    /// useful nonzero document typography remains available.
    private static func isZeroCSSLength(_ value: String) -> Bool {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
        let pattern = #"^[+-]?(?:0+(?:\.0*)?|\.0+)(?:px|pt|pc|em|rem|ex|ch|vw|vh|vmin|vmax|%)?$"#
        return compact.range(of: pattern, options: .regularExpression) != nil
    }
}
