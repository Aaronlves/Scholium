import Foundation

/// Researcher-maintained input text, never a synonym rule or an executable query macro.
public struct SearchTermGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let terms: [String]

    public init(id: UUID = UUID(), name: String, terms: [String]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.terms = terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 80, !name.contains(where: \.isNewline),
            (1...24).contains(terms.count),
            terms.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 512 && !$0.contains(where: \.isNewline) })
        else {
            throw SearchTermGroupError.invalid
        }
    }

    public var queryText: String {
        "("
            + terms.map { value in
                "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }.joined(separator: " OR ") + ")"
    }

    /// Insert literal alternatives at a UTF-16 caret. Validate the complete visible query
    /// so an invalid insertion never replaces the existing draft or introduces hidden state.
    public func insertion(in query: String, caretUTF16: Int) throws -> SearchCompletion {
        try validate()
        guard caretUTF16 >= 0, caretUTF16 <= query.utf16.count,
            let position = caretUTF16 == query.utf16.count ? query.endIndex : query.indices.first(where: { $0.utf16Offset(in: query) == caretUTF16 }),
            !SearchQueryParser.completionTokens(query).contains(where: { $0.range.lowerBound < caretUTF16 && caretUTF16 < $0.range.upperBound })
        else {
            throw SearchTermGroupError.insertion
        }
        let before = String(query[..<position])
        let after = String(query[position...])
        let leading = before.last.map { $0.isWhitespace || "(:".contains($0) ? "" : " " } ?? ""
        let trailing = after.first.map { $0.isWhitespace || $0 == ")" ? "" : " " } ?? ""
        let inserted = leading + queryText + trailing
        let replacement = before + inserted + after
        guard SearchQueryParser.parse(replacement).isValid else { throw SearchTermGroupError.insertion }
        return SearchCompletion(
            replacementText: replacement, displayText: name, detail: "Literal alternatives", caretUTF16: before.utf16.count + inserted.utf16.count)
    }
}

public enum SearchTermGroupError: String, Error, LocalizedError, Sendable {
    case invalid, unreadable, changed, insertion
    public var errorDescription: String? {
        switch self {
        case .invalid: "Use a name of up to 80 characters and 1–24 terms, each on one line and up to 512 characters."
        case .unreadable: "Term groups could not be read. Their stored data has been preserved."
        case .changed: "This term group changed elsewhere. Reload before editing it."
        case .insertion: "Place the caret between complete conditions or inside an empty text group before inserting terms."
        }
    }
}
