import Foundation
import ScholiumContracts
import Testing

@Suite("Boolean Search language")
struct SearchExpressionTests {
    @Test(
        "Precedence, exclusion and field inheritance use one expression",
        arguments: [
            ("alpha OR beta AND gamma", true), ("(alpha OR beta) AND gamma", false),
            ("alpha -beta", false), ("alpha NOT gamma", true), ("NOT NOT alpha", true),
            ("NOT(alpha OR beta)", false), ("title:(alpha OR (beta NOT gamma))", true),
            ("or AND not", false),
        ])
    func expressions(_ query: String, _ expected: Bool) throws {
        let ast = try #require(SearchQueryParser.parse(query).ast)
        let result = ast.expression.evaluate {
            guard case .lexical(let value) = $0 else { return .no }
            return ["alpha", "beta"].contains(value.value.text) ? .yes : .no
        }
        #expect((result.truth == .yes) == expected)
        if query.hasPrefix("title:") {
            #expect(ast.positiveLexicalClauses.allSatisfy { $0.field == .title })
        }
    }

    @Test("A failed alternative contributes no match witness")
    func witnesses() throws {
        let ast = try #require(SearchQueryParser.parse("alpha OR (beta AND gamma)").ast)
        let result = ast.expression.evaluate {
            guard case .lexical(let value) = $0 else { return .no }
            return value.value.text == "gamma" ? .no : .yes
        }
        #expect(result.truth == .yes)
        #expect(ast.matched(by: result).positiveLexicalClauses.map(\.value.text) == ["alpha"])
    }

    @Test("Unknown is preserved through NOT and only known successful alternatives provide evidence")
    func unknown() throws {
        let examples: [(String, SearchTruth)] = [
            ("NOT property:status", .unknown), ("alpha OR property:status", .yes),
            ("alpha AND property:status", .unknown), ("beta AND property:status", .no),
            ("beta OR property:status", .unknown), ("NOT NOT property:status", .unknown),
        ]
        for (query, expected) in examples {
            let ast = try #require(SearchQueryParser.parse(query).ast)
            let result = ast.expression.evaluate {
                if case .property = $0 { return .unknown }
                if case .lexical(let value) = $0, value.value.text == "alpha" { return .yes }
                return .no
            }
            #expect(result.truth == expected)
            #expect(result.matches.allSatisfy { if case .property = $0.clause { false } else { true } })
        }
    }

    @Test(
        "Malformed expressions never become a valid partial query",
        arguments: [
            "alpha OR", "AND alpha", "()", "title:()", "(alpha", "alpha)", "alpha(beta)", "(alpha)(beta)",
            "title:(alpha OR body:beta)", "property:status=(draft OR revised)", "alpha OR kind:note",
            "NOT kind:note", "kind:note kind:note", "alpha NEAR beta", "-(alpha OR)", "OR",
        ])
    func invalid(_ query: String) { #expect(!SearchQueryParser.parse(query).isValid) }

    @Test("Group depth is bounded and quoted delimiters stay literal")
    func boundaries() throws {
        #expect(SearchQueryParser.parse(String(repeating: "(", count: 8) + "alpha" + String(repeating: ")", count: 8)).isValid)
        #expect(!SearchQueryParser.parse(String(repeating: "(", count: 9) + "alpha" + String(repeating: ")", count: 9)).isValid)
        let ast = try #require(SearchQueryParser.parse(#"title:"OR (not)" OR "-alpha""#).ast)
        #expect(ast.positiveLexicalClauses.map(\.value.text) == ["or (not)", "-alpha"])
        let roundTrip = try JSONDecoder().decode(SearchQueryAST.self, from: JSONEncoder().encode(ast))
        #expect(roundTrip == ast)
    }

    @Test("Current-note alternatives each require a positive occurrence")
    func occurrenceScope() throws {
        for (query, valid) in [("alpha AND NOT beta", true), ("alpha OR NOT beta", false), ("NOT NOT alpha", true), ("kind:note", false)] {
            let ast = try #require(SearchQueryParser.parse(query).ast)
            #expect((ast.scopeDiagnostic(scope: .thisNote, queryUTF16Count: query.utf16.count) == nil) == valid)
            #expect(ast.scopeDiagnostic(scope: .triptych, queryUTF16Count: query.utf16.count) == nil)
        }
    }

    @Test("Completion keeps following syntax and the inherited field")
    func completion() throws {
        let query = "callout:(ci OR flag) AND body:中文😀"
        let caret = "callout:(ci".utf16.count
        let completion = try #require(SearchCapabilities.current.completions(for: query, scope: .triptych, caretUTF16: caret).first)
        #expect(completion.replacementText == "callout:(cite OR flag) AND body:中文😀")
        #expect(completion.caretUTF16 == "callout:(cite".utf16.count)
        let property = "property:sta=draft AND beta"
        let keys = SearchCompletionContext(propertyKeys: ["status"])
        #expect(
            SearchCapabilities.current.completions(for: property, scope: .triptych, context: keys, caretUTF16: "property:sta".utf16.count)
                .first?.replacementText == "property:status=draft AND beta")
        #expect(
            SearchCapabilities.current.completions(for: "tit:alpha OR beta", scope: .triptych, caretUTF16: 3).first?.replacementText == "title:alpha OR beta")
        #expect(SearchCapabilities.current.completions(for: "property:(sta", scope: .triptych, context: keys).isEmpty)
        #expect(SearchCapabilities.current.completions(for: "", scope: .triptych).isEmpty)
        #expect(SearchCapabilities.current.completions(for: "alpha beta", scope: .triptych, caretUTF16: 6).contains { $0.replacementText == "alpha OR beta" })
        #expect(SearchCapabilities.current.completions(for: "alpha O", scope: .triptych).contains { $0.replacementText == "alpha OR " })
        #expect(SearchCapabilities.current.completions(for: "(alpha ", scope: .triptych).contains { $0.displayText == ")" })
    }
}
