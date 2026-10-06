import Foundation
import ScholiumContracts
import Testing

@Suite("Search lexical normalization and quoted values")
struct SearchLexicalConsistencyTests {
    @Test(
        "Index and candidate query share exact lexical comparison",
        arguments: [
            ("λόγος", "λογοσ"), ("λο\u{301}γος", "λογοσ"), ("CAFÉ", "cafe"),
            ("İ", "i"), ("ѝ", "и"), ("ﬃ", "ffi"), ("𐐀", "𐐨"),
        ]
    )
    func lexicalNormalization(_ source: String, _ expected: String) {
        #expect(SearchTextNormalization.lexicalNormalize(source) == expected)
        #expect(SearchTokenization.indexText(source) == expected)
        #expect(SearchTokenization.queryTokens(for: source) == [expected])
    }

    @Test("Mixed scripts normalize before symmetric CJK projection")
    func mixedScriptNormalization() {
        #expect(SearchTokenization.indexText("ά自由Élan") == "α自由elan α 自 由 自由 elan")
        #expect(SearchTokenization.queryTokens(for: "ά自由Élan") == ["α", "自由", "elan"])
        #expect(SearchTokenization.queryTokens(for: "自由→λόγος") == ["自由", "λογοσ"])
        #expect(SearchTokenization.indexText("→ ¬ 🦉") == "")
    }

    @Test("Identity keys and parsed source values retain accents and punctuation")
    func identityDistinction() throws {
        #expect(SearchTextNormalization.normalize("Élan λόγος İ") == "élan λόγοσ i\u{307}")
        #expect(SearchTokenization.vocabularyTerms(in: "CAFÉ λόγος") == ["café", "λόγοσ"])
        let query = #"title:"Élan λόγος""#
        let ast = try #require(SearchQueryParser.parse(query).ast)
        #expect(ast.identityNeedle == "élan λόγοσ")
        #expect(ast.positiveLexicalClauses.first?.value == .phrase("élan λόγοσ"))
        #expect(ast.positiveLexicalClauses.first?.sourceRange == 0..<query.utf16.count)
    }

    @Test(
        "Unescaped interior quotes fail closed across every quoted value owner",
        arguments: [
            #"body:"agency"OR"absent""#, #"body:"a""b""#, #""a""b""#,
            #"title:("a""b")"#, #"paragraph:("a""b")"#,
            #"property:"status""key"=draft"#, #"property:status="draft""revised""#,
            #"property:"status"="draft"OR"revised""#, #"from-note:"A""B""#,
            #"to-note:"A"OR"B""#,
        ]
    )
    func malformedQuotedValue(_ query: String) throws {
        let result = SearchQueryParser.parse(query)
        #expect(result.ast == nil)
        let issue = try #require(result.diagnostics.first)
        #expect(issue.reason == .partialQuotedValue)
        #expect(issue.code == .unsupportedSyntax)
        #expect(result.diagnostics.count == 1)
        #expect(issue.utf16LowerBound >= 0)
        #expect(issue.utf16UpperBound <= query.utf16.count)
    }

    @Test("Quoted syntax diagnostics retain the complete original UTF-16 token range")
    func malformedQuotedRange() throws {
        let prefix = "自由 OR "
        let token = #"body:"agency"OR"absent""#
        let result = SearchQueryParser.parse(prefix + token)
        let issue = try #require(result.diagnostics.first)
        #expect(issue.reason == .partialQuotedValue)
        #expect(issue.utf16LowerBound == prefix.utf16.count)
        #expect(issue.utf16UpperBound == (prefix + token).utf16.count)
    }

    @Test("Escaped quotes and backslashes remain literal in phrases and quoted property keys")
    func escapedQuotedValues() throws {
        let lexical = try #require(SearchQueryParser.parse(#"body:"\"agency\" \\ OR""#).ast)
        #expect(lexical.positiveLexicalClauses.first?.value == .phrase(#""agency" \ or"#))
        let property = try #require(SearchQueryParser.parse(#"property:"研究\"问题\\"="\"行动\"\\理由""#).ast)
        guard case .property(let clause) = try #require(property.clauses.first) else {
            Issue.record("Expected a quoted Property equality")
            return
        }
        #expect(clause.key == #"研究"问题\"#)
        #expect(clause.value == #""行动"\理由"#)
        let link = try #require(SearchQueryParser.parse(#"from-note:"A\"B\\C""#).ast)
        #expect(link.linkQueries.first?.noteIdentity == #"a"b\c"#)
        #expect(SearchQueryParser.parse(#"body:"agency" OR body:"absent""#).isValid)
        #expect(SearchQueryParser.parse(#"body:"agency OR absent""#).isValid)
    }
}
