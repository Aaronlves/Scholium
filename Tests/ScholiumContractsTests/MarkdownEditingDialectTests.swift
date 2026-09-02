import Foundation
import ScholiumContracts
import Testing

@Suite("Markdown editing dialect")
struct MarkdownEditingDialectTests {
    @Test("Dialect is a complete deterministic projection of Contracts authorities")
    func dialectProjection() throws {
        let dialect = MarkdownEditingDialect.current

        #expect(dialect.version == 5)
        #expect(dialect.callouts.map(\.identifier) == [
            "orient", "cite", "connect", "state", "illustrate", "quote", "flag",
        ])
        #expect(dialect.callouts.first { $0.identifier == "orient" }?.aliases == ["mini"])
        #expect(dialect.callouts.first { $0.identifier == "state" }?.aliases.contains("objection") == true)
        #expect(dialect.linkAnnotation.openingDelimiter == "{{")
        #expect(dialect.linkAnnotation.closingDelimiter == "}}")
        #expect(dialect.linkAnnotation.escapeCharacter == "\\")
        #expect(dialect.linkAnnotation.allowsMultiline)
        #expect(!dialect.linkAnnotation.allowsNesting)
        #expect(dialect.footnotes.namedReferenceOpening == "[^")
        #expect(dialect.footnotes.namedReferenceClosing == "]")
        #expect(dialect.footnotes.definitionSeparator == ":")
        #expect(dialect.footnotes.inlineOpening == "^[")
        #expect(dialect.footnotes.continuationIndentSpaces == 2)
        #expect(dialect.footnotes.allowsTabContinuation)
        #expect(dialect.footnotes.caseSensitiveIdentifiers)
        #expect(dialect.footnotes.ordinalByFirstReference)
        #expect(dialect.mathematics.inlineDelimiter == "$")
        #expect(dialect.mathematics.displayDelimiter == "$$")
        #expect(dialect.mathematics.singleDollarInline)

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
                annotation: $0.annotation?.markdown
            ) } == fixture.links)
            #expect(semantic.footnoteDefinitions.map(\.identifier) == fixture.footnoteDefinitions)
            #expect(semantic.footnoteDefinitions.map(\.content) == fixture.footnoteDefinitionContents)
            #expect(semantic.footnoteReferences.map(\.identifier) == fixture.footnoteReferences)
            #expect(semantic.mathExpressions.map { MathFixture(
                kind: $0.kind.rawValue,
                content: $0.content
            ) } == fixture.mathExpressions)
            let source = fixture.source as NSString
            #expect(semantic.callouts.map { source.substring(with: $0.headerSpan.nsRange) }
                == fixture.sourceSlices.calloutHeaders)
            #expect(semantic.links.map { source.substring(with: $0.span.nsRange) }
                == fixture.sourceSlices.links)
            #expect(semantic.footnoteDefinitions.map { source.substring(with: $0.span.nsRange) }
                == fixture.sourceSlices.footnoteDefinitions)
            #expect(semantic.footnoteReferences.map { source.substring(with: $0.span.nsRange) }
                == fixture.sourceSlices.footnoteReferences)
            #expect(semantic.mathExpressions.map { expression in
                MathSourceSlice(
                    source: source.substring(with: expression.span.nsRange),
                    content: source.substring(with: expression.contentSpan.nsRange)
                )
            } == fixture.sourceSlices.mathExpressions)
        }
    }

    @Test("Shared base-syntax fixtures match exact CommonMark and GFM source spans")
    func baseSyntaxParityFixtures() throws {
        let url = try #require(Bundle.module.url(
            forResource: "base-syntax-parity-fixtures",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        let fixtures = try JSONDecoder().decode([BaseSyntaxFixture].self, from: Data(contentsOf: url))
        for fixture in fixtures {
            let semantic = MarkdownSemanticDocument(parsing: NoteDocument(
                relativePath: "Fixture.md",
                rawContent: fixture.source
            ))
            let source = fixture.source as NSString
            let blocks = semantic.blocks.map {
                LocatedSyntax(
                    kind: $0.kind.rawValue,
                    from: $0.span.utf16LowerBound,
                    to: $0.span.utf16UpperBound,
                    source: source.substring(with: $0.span.nsRange)
                )
            }.sorted(by: LocatedSyntax.precedes)
            let inlines = semantic.inlines.map {
                LocatedSyntax(
                    kind: $0.kind.rawValue,
                    from: $0.span.utf16LowerBound,
                    to: $0.span.utf16UpperBound,
                    source: source.substring(with: $0.span.nsRange)
                )
            }.sorted(by: LocatedSyntax.precedes)
            #expect(blocks == fixture.blocks)
            #expect(inlines == fixture.inlines)
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
        let footnoteDefinitionContents: [String]
        let footnoteReferences: [String]
        let mathExpressions: [MathFixture]
        let sourceSlices: SourceSlices
    }

    private struct BaseSyntaxFixture: Decodable {
        let name: String
        let source: String
        let blocks: [LocatedSyntax]
        let inlines: [LocatedSyntax]
    }

    private struct LocatedSyntax: Decodable, Equatable {
        let kind: String
        let from: Int
        let to: Int
        let source: String

        static func precedes(_ left: Self, _ right: Self) -> Bool {
            if left.from != right.from { return left.from < right.from }
            if left.to != right.to { return left.to > right.to }
            return left.kind < right.kind
        }
    }

    private struct LinkFixture: Codable, Equatable {
        let target: String
        let annotation: String?
    }

    private struct MathFixture: Codable, Equatable {
        let kind: String
        let content: String
    }

    private struct SourceSlices: Decodable {
        let calloutHeaders: [String]
        let links: [String]
        let footnoteDefinitions: [String]
        let footnoteReferences: [String]
        let mathExpressions: [MathSourceSlice]
    }

    private struct MathSourceSlice: Decodable, Equatable {
        let source: String
        let content: String
    }
}
