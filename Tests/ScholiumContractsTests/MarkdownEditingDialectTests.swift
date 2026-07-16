import Foundation
import ScholiumContracts
import Testing

@Suite("Markdown editing dialect")
struct MarkdownEditingDialectTests {
    @Test("Dialect is a complete deterministic projection of Contracts authorities")
    func dialectProjection() throws {
        let dialect = MarkdownEditingDialect.current

        #expect(dialect.version == 1)
        #expect(dialect.callouts.map(\.identifier) == [
            "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
        ])
        #expect(dialect.callouts.first { $0.identifier == "orient" }?.aliases == ["mini"])
        #expect(dialect.callouts.first { $0.identifier == "state" }?.aliases.contains("objection") == true)
        #expect(dialect.vectorLinkOperators.map(\.marker) == ["", "+", "-", "?"])
        #expect(dialect.vectorLinkOperators.map(\.kind) == [
            .neutral, .supportsTarget, .supportedByTarget, .incompatible,
        ])

        let encoded = try JSONEncoder().encode(dialect)
        #expect(try JSONDecoder().decode(MarkdownEditingDialect.self, from: encoded) == dialect)
    }

    @Test("Every advertised alias resolves to its advertised canonical identifier")
    func aliasesResolve() {
        for callout in MarkdownEditingDialect.current.callouts {
            #expect(CalloutSemanticVocabulary.canonicalIdentifier(for: callout.identifier) == callout.identifier)
            for alias in callout.aliases {
                #expect(CalloutSemanticVocabulary.canonicalIdentifier(for: alias) == callout.identifier)
            }
        }
    }

    @Test("Exact-source fixture catalog preserves hostile source forms")
    func exactSourceFixtureCatalog() throws {
        let url = try #require(Bundle.module.url(
            forResource: "exact-source-fixtures",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        #expect(fixtures.count >= 12)
        #expect(fixtures.contains { $0.source.hasPrefix("\u{FEFF}") })
        #expect(fixtures.contains { $0.source.contains("\r\n") })
        #expect(fixtures.contains { $0.source.contains("<!--") && $0.source.contains("%%") })
        #expect(fixtures.contains { $0.source.contains("مرحبا") })
        #expect(fixtures.contains { $0.selections.count > 1 })
    }

    @Test("Shared semantic fixtures match the canonical parser")
    func semanticParityFixtures() throws {
        let url = try #require(Bundle.module.url(
            forResource: "semantic-parity-fixtures",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let fixtures = try JSONDecoder().decode([SemanticFixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            let semantic = MarkdownSemanticDocument(parsing: NoteDocument(
                relativePath: "Fixture.md",
                rawContent: fixture.source
            ))
            #expect(semantic.callouts.map(\.kind) == fixture.callouts)
            #expect(semantic.links.map { LinkFixture(
                target: $0.target,
                vectorKind: $0.vectorKind?.rawValue
            ) } == fixture.links)
            #expect(semantic.footnoteDefinitions.map(\.identifier) == fixture.footnoteDefinitions)
            #expect(semantic.footnoteReferences.map(\.identifier) == fixture.footnoteReferences)
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let source: String
        let selections: [[Int]]
    }

    private struct SemanticFixture: Decodable {
        let name: String
        let source: String
        let callouts: [String]
        let links: [LinkFixture]
        let footnoteDefinitions: [String]
        let footnoteReferences: [String]
    }

    private struct LinkFixture: Codable, Equatable {
        let target: String
        let vectorKind: String?
    }
}
