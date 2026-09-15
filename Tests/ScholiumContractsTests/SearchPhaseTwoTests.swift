import Foundation
import ScholiumContracts
import Testing

@Suite("Paragraph syntax and literal term insertion")
struct SearchPhaseTwoTests {
    @Test(arguments: ["paragraph:(alpha)", "author:Teroni AND paragraph:((emotion OR feeling) NOT sensation)", "NOT paragraph:(alpha AND beta)"])
    func accepted(_ query: String) throws {
        let ast = try #require(SearchQueryParser.parse(query).ast)
        #expect(try JSONDecoder().decode(SearchQueryAST.self, from: JSONEncoder().encode(ast)) == ast)
    }
    @Test(arguments: [
        "paragraph:alpha", "paragraph:(NOT alpha)", "paragraph:(alpha OR NOT beta)", "paragraph:(title:alpha)", "paragraph:(property:status)",
        "paragraph:(from-note:Alpha)", "paragraph:(paragraph:(alpha))", "title:(paragraph:(alpha))",
    ])
    func rejected(_ query: String) { #expect(!SearchQueryParser.parse(query).isValid) }

    @Test("Paragraph occurrences require a positive branch and completion keeps its text-only context")
    func scopeAndCompletion() throws {
        for (query, valid) in [("paragraph:(alpha)", true), ("NOT paragraph:(alpha)", false), ("alpha NOT paragraph:(beta)", true)] {
            let ast = try #require(SearchQueryParser.parse(query).ast)
            #expect((ast.scopeDiagnostic(scope: .thisNote, queryUTF16Count: query.utf16.count) == nil) == valid)
        }
        #expect(SearchCapabilities.current.completions(for: "para", scope: .thisNote).first?.replacementText == "paragraph:(")
        #expect(SearchCapabilities.current.completions(for: "paragraph:(tit", scope: .triptych).isEmpty)
        #expect(SearchCapabilities.current.completions(for: "paragraph:(alpha O", scope: .triptych).contains { $0.replacementText == "paragraph:(alpha OR " })
    }
    @Test("Researcher terms are literal, visible and independent of subsequent group edits")
    func literalInsertion() throws {
        let group = SearchTermGroup(name: "Alternatives", terms: ["实践理由", "practical reason", "NOT", "a\"b\\c"])
        let inserted = try group.insertion(in: "paragraph:() AND author:Teroni", caretUTF16: "paragraph:(".utf16.count)
        #expect(SearchQueryParser.parse(inserted.replacementText).isValid)
        #expect(inserted.replacementText.hasSuffix(") AND author:Teroni"))
        #expect(inserted.replacementText.contains("\"NOT\""))
        let ast = try #require(SearchQueryParser.parse(group.queryText).ast)
        #expect(ast.positiveLexicalClauses.count == 4)
        let edited = SearchTermGroup(id: group.id, name: group.name, terms: ["changed"])
        #expect(!inserted.replacementText.contains(edited.terms[0]))
        #expect(throws: SearchTermGroupError.insertion) { try group.insertion(in: "title:alpha", caretUTF16: 8) }
        #expect(throws: SearchTermGroupError.insertion) { try group.insertion(in: "😀", caretUTF16: 1) }
        #expect(throws: SearchTermGroupError.invalid) { try SearchTermGroup(name: "Too many", terms: Array(repeating: "alpha", count: 25)).validate() }
    }
}
