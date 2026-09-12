import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Search v10 metadata and direct-link filters")
struct SearchPropertyIndexTests {
    @Test("Property results retain exact YAML provenance")
    func propertyPresenceEqualityAndProvenance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = """
            ---
            summary: A source about akrasia
            keywords: [Akrasia, "Weakness of Will"]
            language: Retired YAML value
            ---
            Body
            """
        _ = try await index.synchronize([
            fixture.item(
                "Topic.md",
                source,
                authoredFields: [
                    "aliases": .array([.string("Practical agency")])
                ]
            )
        ])

        let summary = try await index.testSearch(fixture.request("property:summary"))
        guard
            case .property(let summaryMatch) = try #require(
                summary.noteResults.first?.primaryMatchReason
            )
        else {
            Issue.record("Summary search did not expose structured provenance")
            return
        }
        let summaryKeyRange = try #require(summaryMatch.keySourceRange)
        #expect(sourceText(source, range: summaryKeyRange) == "summary")

        let keyword = try await index.testSearch(
            fixture.request("property:keywords=\"weakness of will\"")
        )
        guard
            case .property(let keywordMatch) = try #require(
                keyword.noteResults.first?.primaryMatchReason
            )
        else {
            Issue.record("Keyword search did not expose structured provenance")
            return
        }
        #expect(
            keywordMatch.valueSourceRanges.map { sourceText(source, range: $0) }
                == ["\"Weakness of Will\""])

        let alias = try await index.testSearch(
            fixture.request("property:aliases=\"practical agency\"")
        )
        guard
            case .property(let aliasMatch) = try #require(
                alias.noteResults.first?.primaryMatchReason
            )
        else {
            Issue.record("Managed aliases did not expose structured provenance")
            return
        }
        #expect(aliasMatch.keySourceRange != nil)
        #expect(!aliasMatch.valueSourceRanges.isEmpty)
        #expect(alias.noteResults.first?.sourceRange != nil)

        #expect(
            try await index.testSearch(
                fixture.request("property:language")
            ).noteResults.map(\.relativePath) == ["Topic.md"])
    }

    @Test("Keyword lexical hits retain their exact YAML member range")
    func keywordLexicalRangeDoesNotDependOnTextUniqueness() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = """
            ---
            summary: Ethics
            keywords: [Ethics, Ethics]
            ---
            Body
            """
        _ = try await index.synchronize([fixture.item("Topic.md", source)])

        let response = try await index.testSearch(fixture.request("keyword:ethics"))
        let range = try #require(response.noteResults.first?.sourceRange)
        #expect(range.line == 3)
        #expect(sourceText(source, range: range) == "Ethics")
    }

    @Test("Escaped YAML keywords fall back to the complete authored scalar range")
    func escapedKeywordLexicalRangeIsComplete() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = """
            ---
            keywords: ["\\u0041gency"]
            ---
            Body
            """
        _ = try await index.synchronize([fixture.item("Topic.md", source)])

        let response = try await index.testSearch(fixture.request("keyword:agency"))
        let range = try #require(response.noteResults.first?.sourceRange)
        #expect(sourceText(source, range: range) == "\"\\u0041gency\"")
    }

    @Test("Authored property-only changes converge with a clean rebuild")
    func propertyIncrementalCleanRebuildParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let incremental = try fixture.index()
        let source = "---\nsummary: Agency map\nkeywords: [concept]\n---\nBody"
        _ = try await incremental.synchronize([
            fixture.item(
                "Topic.md",
                source,
                authoredFields: [
                    "aliases": .array([.string("Practical agency")]),
                    "argument_stage": .string("Greek"),
                ]
            )
        ])
        let edited = fixture.item(
            "Topic.md",
            source,
            authoredFields: [
                "aliases": .array([.string("Practical agency")]),
                "argument_stage": .string("Latin"),
            ]
        )
        let updated = try await incremental.synchronize([edited])
        #expect(updated.disposition == .incrementallyUpdated)

        let clean = try fixture.index(
            at: fixture.root.appendingPathComponent("clean-search-v10.sqlite")
        )
        _ = try await clean.synchronize([edited])
        for query in [
            "property:aliases",
            "property:argument_stage=Greek",
            "property:argument_stage=Latin",
            "summary:agency",
        ] {
            let incrementalResults = try await incremental.testSearch(fixture.request(query))
            let cleanResults = try await clean.testSearch(fixture.request(query))
            #expect(
                incrementalResults.noteResults.map(\.relativePath)
                    == cleanResults.noteResults.map(\.relativePath))
            #expect(
                incrementalResults.noteResults.map(\.primaryMatchReason)
                    == cleanResults.noteResults.map(\.primaryMatchReason))
            #expect(
                incrementalResults.noteResults.map(\.sourceRange)
                    == cleanResults.noteResults.map(\.sourceRange))
        }
    }

    @Test("Malformed YAML cannot supply properties while body search remains available")
    func malformedSourceKeepsBodySearch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(
                "Malformed.md",
                "---\nsummary: [unfinished\n---\nmalformed-body-term",
                authoredFields: ["aliases": .array([.string("Still managed")])]
            )
        ])

        #expect(
            try await index.testSearch(
                fixture.request("property:aliases=\"still managed\"")
            ).noteResults.map(\.relativePath) == [])
        #expect(
            try await index.testSearch(
                fixture.request("malformed-body-term")
            ).noteResults.map(\.relativePath) == ["Malformed.md"])
    }

    @Test("Lexical and metadata AND does not lose a late matching candidate")
    func metadataFilterHasNoCandidateCutoff() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        var documents = (0..<2_000).map { number in
            fixture.item(
                String(format: "Background/%04d.md", number),
                "shared-concept shared-concept",
                authoredFields: ["aliases": .array([.string("provisional")])]
            )
        }
        documents.append(
            fixture.item(
                "zzzz-target.md",
                "shared-concept",
                authoredFields: ["aliases": .array([.string("settled")])]
            ))
        _ = try await index.synchronize(documents)

        let response = try await index.testSearch(
            fixture.request("shared-concept property:aliases=settled", limit: 1)
        )
        #expect(response.noteResults.map(\.relativePath) == ["zzzz-target.md"])
        #expect(
            response.noteResults.first?.matchReasons.contains { reason in
                if case .property = reason { return true }
                return false
            } == true)
    }

    @Test("Direct-link candidates remain externally resolved and source attributed")
    func linkCandidateRestrictionAndProvenance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item("Matched.md", "# Matched\n\nautonomy"),
            fixture.item("Excluded.md", "# Excluded\n\nautonomy"),
        ])
        let anchor = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Anchor.md"
        )
        let target = VaultQualifiedNoteID(
            vaultID: fixture.vault.id,
            relativePath: "Matched.md"
        )
        let authored = try #require(
            MarkdownSemanticDocument(
                parsing: NoteDocument(
                    relativePath: "Anchor.md",
                    rawContent: "# Anchor\n\n[[Matched]]{{A direct reason.}}\n"
                )
            ).links.first)
        let occurrence = SearchLinkOccurrence(sourceNote: anchor, occurrence: authored)
        let match = SearchLinkMatch(
            direction: .fromNote,
            anchorIdentity: "Anchor",
            targetNote: target,
            occurrences: [occurrence]
        )

        let response = try await index.testSearch(
            fixture.request("autonomy from-note:Anchor"),
            linkMatches: [target: match]
        )
        #expect(response.noteResults.map(\.relativePath) == ["Matched.md"])
        let hit = try #require(response.noteResults.first)
        let links: [SearchLinkMatch] = hit.matchReasons.compactMap { reason in
            guard case .link(let value) = reason else { return nil }
            return value
        }
        #expect(try #require(links.first).occurrences == [occurrence])
    }

    @Test("Link annotations are an independent visible-text field with exact source provenance")
    func linkAnnotationLexicalField() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = """
            # Annotated

            Intro [[Hidden Destination#claim|visible link]]{{First **annotated reason** with [[Hidden Evidence|visible evidence]].

            Second line.}} tail prose.
            """
        _ = try await index.synchronize([fixture.item("Annotated.md", source)])

        let annotation = try await index.testSearch(
            fixture.request(#"link_annotation:"annotated reason""#)
        )
        let hit = try #require(annotation.noteResults.first)
        #expect(hit.matchedField == .linkAnnotation)
        #expect(sourceText(source, range: try #require(hit.sourceRange)) == "annotated reason")

        #expect(
            try await index.testSearch(
                fixture.request("visible evidence")
            ).noteResults.first?.matchedField == .linkAnnotation)
        #expect(
            try await index.testSearch(
                fixture.request("visible link tail prose")
            ).noteResults.map(\.relativePath) == ["Annotated.md"])
        #expect(
            try await index.testSearch(
                fixture.request(#""Hidden Destination""#)
            ).noteResults.isEmpty)
        #expect(
            try await index.testSearch(
                fixture.request(#""Hidden Evidence""#)
            ).noteResults.isEmpty)
    }

    @Test("Custom YAML filters compose with lexical search and retain exact source provenance")
    func customYAMLSearch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source =
            "---\n\"研究 问题\": 行动理由\nyear: 1962\nflag: true\nitems: [ethics, 42, false, null]\nsummary: >-\n  practical\n  agency\n---\nA unique argument"
        _ = try await index.synchronize([fixture.item("Custom.md", source), fixture.item("Other.md", "A unique argument")])
        for query in [
            #"property:"研究 问题"="行动理由""#, "property:year=1962", "property:flag=true", "property:items=42", "property:items=false", "unique property:year=1962",
            #"property:summary="practical agency""#, "summary:agency",
        ] {
            let result = try await index.testSearch(fixture.request(query))
            let hit = try #require(result.noteResults.first)
            #expect(result.noteResults.map(\.relativePath) == ["Custom.md"])
            #expect(hit.sourceRange != nil)
        }
        #expect(try await index.testSearch(fixture.request("property:items=null")).noteResults.isEmpty)
        #expect(try await index.testSearch(fixture.request("property:year=196")).noteResults.isEmpty)
    }

    @Test("Duplicate YAML keys cannot produce independent property authorities")
    func duplicateKeysDoNotInventValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item("Topic.md", "---\naliases: [First]\naliases: [Second]\n---\nBody")])
        for query in ["property:aliases=First", "property:aliases=Second"] {
            #expect(try await index.testSearch(fixture.request(query)).noteResults.isEmpty)
        }
    }

    @Test("Custom YAML edits and removal converge with a clean index without touching source")
    func customYAMLIncrementalParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item("Custom.md", "---\ncustom: old\n---\nBody")])
        for (number, source) in ["---\ncustom: new\nsummary: |\n  exact text\n---\nBody", "---\ncustom: [broken\n---\nBody", "Body"].enumerated() {
            let item = fixture.item("Custom.md", source)
            _ = try await index.synchronize([item])
            let clean = try fixture.index(at: fixture.root.appendingPathComponent("clean-\(number).sqlite"))
            _ = try await clean.synchronize([item])
            for query in ["property:custom", "property:custom=old", "property:custom=new", "summary:exact", "Body"] {
                let incremental = try await index.testSearch(fixture.request(query))
                let rebuilt = try await clean.testSearch(fixture.request(query))
                #expect(incremental.noteResults.map(\.relativePath) == rebuilt.noteResults.map(\.relativePath))
                #expect(incremental.noteResults.map(\.primaryMatchReason) == rebuilt.noteResults.map(\.primaryMatchReason))
                #expect(incremental.noteResults.map(\.sourceRange) == rebuilt.noteResults.map(\.sourceRange))
                if query == "property:custom=old" { #expect(incremental.noteResults.isEmpty) }
            }
        }
    }

    private final class Fixture: @unchecked Sendable {
        let root: URL
        let databaseURL: URL
        let triptychID = UUID()
        let vault = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixtures/topics"
        )

        init() throws {
            root = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("search-v10-property-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            databaseURL = root.appendingPathComponent("search-v10.sqlite")
        }

        func index(at url: URL? = nil) throws -> TriptychSearchIndex {
            try TriptychSearchIndex(
                databaseURL: url ?? databaseURL,
                triptychID: triptychID
            )
        }

        func item(_ path: String, _ source: String, authoredFields: [String: YAMLValue]? = nil) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: sourceFixture(source, fields: authoredFields)))
        }

        func request(_ query: String, limit: Int = 100) -> SearchRequest {
            SearchRequest(
                query: query,
                presentationScope: .triptych,
                executionScope: .triptych,
                limit: limit
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func sourceText(_ source: String, range: SearchSourceRange) -> String? {
        guard
            let lowerUTF16 = source.utf16.index(
                source.utf16.startIndex,
                offsetBy: range.utf16LowerBound,
                limitedBy: source.utf16.endIndex
            ),
            let upperUTF16 = source.utf16.index(
                source.utf16.startIndex,
                offsetBy: range.utf16UpperBound,
                limitedBy: source.utf16.endIndex
            ), let lower = lowerUTF16.samePosition(in: source),
            let upper = upperUTF16.samePosition(in: source)
        else { return nil }
        return String(source[lower..<upper])
    }
}
