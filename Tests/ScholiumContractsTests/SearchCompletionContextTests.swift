import ScholiumContracts
import Testing

@Suite("Search completion literal and paragraph context")
struct SearchCompletionContextTests {
    private let vocabulary = SearchCompletionContext(
        lexicalTerms: [
            SearchCompletionTerm(text: "intentionality", fields: [.body]),
            SearchCompletionTerm(text: "intention", fields: [.title]),
            SearchCompletionTerm(text: "title", fields: [.body]),
            SearchCompletionTerm(text: "café", fields: [.body]),
        ])

    @Test("Paragraph vocabulary completion preserves the surrounding expression and native caret")
    func paragraphVocabulary() throws {
        let query = "paragraph:(inten OR reason) AND author:Teroni"
        let caret = "paragraph:(inten".utf16.count
        #expect(
            SearchCapabilities.current.lexicalCompletionLookup(for: query, scope: .triptych, caretUTF16: caret)
                == SearchCompletionLookup(partial: "inten"))
        let completion = try #require(
            SearchCapabilities.current.completions(for: query, scope: .triptych, context: vocabulary, caretUTF16: caret)
                .first { $0.displayText == "intentionality" })
        #expect(completion.replacementText == "paragraph:(intentionality OR reason) AND author:Teroni")
        #expect(completion.caretUTF16 == "paragraph:(intentionality".utf16.count)
        #expect(SearchQueryParser.parse(completion.replacementText).isValid)

        let textOnly = SearchCapabilities.current.completions(for: "paragraph:(tit", scope: .triptych, context: vocabulary)
        #expect(textOnly.map(\.replacementText) == ["paragraph:(title"])
        #expect(SearchCapabilities.current.completions(for: "paragraph:(body:inten", scope: .triptych, context: vocabulary).isEmpty)
        #expect(SearchCapabilities.current.lexicalCompletionLookup(for: "paragraph:(body:inten", scope: .triptych) == nil)
    }

    @Test(
        "Open and closed quoted values request the literal vocabulary prefix",
        arguments: [#""inten"#, #""inten""#, #"body:"inten"#, #"body:"inten""#, #"body:("inten"#, #"paragraph:("inten"#]
    )
    func quotedLookup(_ query: String) throws {
        let lookup = try #require(SearchCapabilities.current.lexicalCompletionLookup(for: query, scope: .triptych))
        #expect(lookup.partial == "inten")
        #expect(lookup.field == (query.hasPrefix("body:") ? .body : nil))
    }

    @Test(
        "Quoted replacement keeps phrase intent, inherited fields and following query text",
        arguments: ["", "body:", "body:(", "paragraph:("]
    )
    func quotedReplacement(_ prefix: String) throws {
        let suffix = (prefix.hasSuffix("(") ? ")" : "") + " OR author:Teroni"
        let query = prefix + #""inten""# + suffix
        let caret = (prefix + #""inten"#).utf16.count
        let completion = try #require(
            SearchCapabilities.current.completions(for: query, scope: .triptych, context: vocabulary, caretUTF16: caret)
                .first { $0.replacementText == prefix + #""intentionality""# + suffix })
        #expect(completion.caretUTF16 == (prefix + #""intentionality""#).utf16.count)
        #expect(SearchQueryParser.parse(completion.replacementText).isValid)
        if prefix.hasPrefix("body:") {
            #expect(
                !SearchCapabilities.current.completions(for: query, scope: .triptych, context: vocabulary, caretUTF16: caret)
                    .contains { $0.replacementText.contains(#""intention""#) })
        }
        let openQuery = prefix + #""inten"#
        #expect(
            SearchCapabilities.current.completions(for: openQuery, scope: .triptych, context: vocabulary)
                .contains { $0.replacementText == prefix + #""intentionality""# })
    }

    @Test("A colon inside a quoted token is literal while replacing at an earlier caret")
    func quotedColon() throws {
        let query = #""inten:legacy" AND body:reason"#
        let completion = try #require(
            SearchCapabilities.current.completions(
                for: query, scope: .triptych, context: vocabulary, caretUTF16: #""inten"#.utf16.count
            )
            .first { $0.displayText == #""intentionality""# })
        #expect(completion.replacementText == #""intentionality" AND body:reason"#)
        #expect(completion.caretUTF16 == #""intentionality""#.utf16.count)
        #expect(SearchQueryParser.parse(completion.replacementText).isValid)
    }

    @Test("Quoted completion uses normalized vocabulary without losing spelling or Unicode caret positions")
    func unicodeReplacement() throws {
        let query = #""自由😀" OR body:("CAFE" OR reason)"#
        let prefix = #""自由😀" OR body:("CAF"#
        let completion = try #require(
            SearchCapabilities.current.completions(
                for: query, scope: .triptych, context: vocabulary, caretUTF16: prefix.utf16.count
            ).first)
        #expect(completion.replacementText == #""自由😀" OR body:("café" OR reason)"#)
        #expect(completion.caretUTF16 == #""自由😀" OR body:("café""#.utf16.count)
        let parsed = try #require(SearchQueryParser.parse(completion.replacementText).ast)
        #expect(parsed.positiveLexicalClauses.contains { $0.field == .body && $0.value == .phrase("café") })
    }

    @Test(
        "Quoted lookup delegates literal escape decoding to the Search parser",
        arguments: [(#""inten\""#, #"inten""#), (#""inten\\"#, #"inten\"#), (#"body:"inten\""#, #"inten""#)]
    )
    func escapedLookup(_ query: String, _ decoded: String) throws {
        let lookup = try #require(SearchCapabilities.current.lexicalCompletionLookup(for: query, scope: .triptych))
        #expect(lookup.partial == decoded)
    }

    @Test(
        "Malformed literals and explicit prefixes do not acquire vocabulary replacements",
        arguments: [#""inten\q"#, #""inten\"#, #""inten""tail"#, #""inten"*"#, "inten*", "AND", "OR", "NOT"]
    )
    func invalidLexicalLookup(_ query: String) {
        #expect(SearchCapabilities.current.lexicalCompletionLookup(for: query, scope: .triptych) == nil)
        #expect(
            !SearchCapabilities.current.completions(for: query, scope: .triptych, context: vocabulary)
                .contains { $0.detail == "Search term" })
    }

    @Test("Multiple words inside a quoted draft never become a one-word completion")
    func noPhraseExpansion() {
        for query in [#""practical inten"#, #"body:"practical inten"#, #"paragraph:("practical inten"#] {
            #expect(SearchCapabilities.current.completions(for: query, scope: .triptych, context: vocabulary).isEmpty)
        }
    }
}
