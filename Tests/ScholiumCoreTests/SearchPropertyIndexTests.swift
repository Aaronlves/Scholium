import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Search v9 metadata and relationship filters")
struct SearchPropertyIndexTests {
    @Test("Authored YAML and managed metadata retain distinct provenance")
    func metadataPresenceEqualityAndProvenance() async throws {
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
        _ = try await index.synchronize([fixture.item(
            "Topic.md",
            source,
            metadataFields: [
                "aliases": .array([.string("Practical agency")]),
            ]
        )])

        let summary = try await index.testSearch(fixture.request("property:summary"))
        guard case .property(let summaryMatch) = try #require(
            summary.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Summary search did not expose structured provenance")
            return
        }
        let summaryKeyRange = try #require(summaryMatch.keySourceRange)
        #expect(sourceText(source, range: summaryKeyRange) == "summary")

        let keyword = try await index.testSearch(
            fixture.request("property:keywords=\"weakness of will\"")
        )
        guard case .property(let keywordMatch) = try #require(
            keyword.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Keyword search did not expose structured provenance")
            return
        }
        #expect(keywordMatch.valueSourceRanges.map { sourceText(source, range: $0) }
            == ["\"Weakness of Will\""])

        let alias = try await index.testSearch(
            fixture.request("property:aliases=\"practical agency\"")
        )
        guard case .property(let aliasMatch) = try #require(
            alias.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Managed aliases did not expose structured provenance")
            return
        }
        #expect(aliasMatch.keySourceRange == nil)
        #expect(aliasMatch.valueSourceRanges.isEmpty)
        #expect(alias.noteResults.first?.sourceRange == nil)

        #expect(try await index.testSearch(
            fixture.request("property:language")
        ).noteResults.isEmpty)
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

    @Test("Managed property-only metadata changes converge with a clean rebuild")
    func metadataIncrementalCleanRebuildParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let incremental = try fixture.index()
        let source = "---\nsummary: Agency map\nkeywords: [concept]\n---\nBody"
        let metadataCatalog = NoteMetadataCatalog(customFieldsByRole: [
            .topicKnowledge: [
                MetadataFieldDefinition(key: "argument_stage", valueKind: .text),
            ],
        ])
        _ = try await incremental.synchronize([fixture.item(
            "Topic.md",
            source,
            metadataFields: [
                "aliases": .array([.string("Practical agency")]),
                "argument_stage": .string("Greek"),
            ],
            metadataCatalog: metadataCatalog
        )])
        let edited = fixture.item(
            "Topic.md",
            source,
            metadataFields: [
                "aliases": .array([.string("Practical agency")]),
                "argument_stage": .string("Latin"),
            ],
            metadataCatalog: metadataCatalog
        )
        let updated = try await incremental.synchronize([edited])
        #expect(updated.disposition == .incrementallyUpdated)

        let clean = try fixture.index(
            at: fixture.root.appendingPathComponent("clean-search-v9.sqlite")
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
            #expect(incrementalResults.noteResults.map(\.relativePath)
                == cleanResults.noteResults.map(\.relativePath))
            #expect(incrementalResults.noteResults.map(\.primaryMatchReason)
                == cleanResults.noteResults.map(\.primaryMatchReason))
            #expect(incrementalResults.noteResults.map(\.sourceRange)
                == cleanResults.noteResults.map(\.sourceRange))
        }
    }

    @Test("Malformed YAML does not hide independent managed metadata")
    func malformedSourceDoesNotHideMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item(
            "Malformed.md",
            "---\nsummary: [unfinished\n---\nmalformed-body-term",
            metadataFields: ["aliases": .array([.string("Still managed")])]
        )])

        #expect(try await index.testSearch(
            fixture.request("property:aliases=\"still managed\"")
        ).noteResults.map(\.relativePath) == ["Malformed.md"])
        #expect(try await index.testSearch(
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
                metadataFields: ["aliases": .array([.string("provisional")])]
            )
        }
        documents.append(fixture.item(
            "zzzz-target.md",
            "shared-concept",
            metadataFields: ["aliases": .array([.string("settled")])]
        ))
        _ = try await index.synchronize(documents)

        let response = try await index.testSearch(
            fixture.request("shared-concept property:aliases=settled", limit: 1)
        )
        #expect(response.noteResults.map(\.relativePath) == ["zzzz-target.md"])
        #expect(response.noteResults.first?.matchReasons.contains { reason in
            if case .property = reason { return true }
            return false
        } == true)
    }

    @Test("Relationship candidates remain externally resolved and source attributed")
    func relationshipCandidateRestrictionAndProvenance() async throws {
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
        let occurrence = RelationshipSourceOccurrence(
            sourceNote: anchor,
            locator: SourceLocator(file: "Anchor.md", line: 8, column: 3),
            syntax: .vectorWikilink,
            vectorKind: .supports
        )
        let match = SearchRelationshipMatch(
            relation: .supports,
            direction: .fromNote,
            anchorIdentity: "Anchor",
            targetNote: target,
            occurrences: [occurrence]
        )

        let response = try await index.testSearch(
            fixture.request("autonomy from-note:Anchor relation:supports"),
            relationshipMatches: [target: match]
        )
        #expect(response.noteResults.map(\.relativePath) == ["Matched.md"])
        let hit = try #require(response.noteResults.first)
        let relationships: [SearchRelationshipMatch] = hit.matchReasons.compactMap { reason in
            guard case .relationship(let value) = reason else { return nil }
            return value
        }
        #expect(try #require(relationships.first).occurrences == [occurrence])
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
                .appendingPathComponent("search-v9-property-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            databaseURL = root.appendingPathComponent("search-v9.sqlite")
        }

        func index(at url: URL? = nil) throws -> TriptychSearchIndex {
            try TriptychSearchIndex(
                databaseURL: url ?? databaseURL,
                triptychID: triptychID
            )
        }

        func item(
            _ path: String,
            _ source: String,
            metadataFields: [String: YAMLValue]? = nil,
            metadataCatalog: NoteMetadataCatalog = .builtIn
        ) -> SearchIndexDocument {
            let metadata: NoteMetadataSnapshot? = metadataFields.map { fields in
                let record = NoteMetadataRecord(noteID: UUID(), fields: fields)
                return NoteMetadataSnapshot(
                    record: record,
                    revision: DocumentFingerprint(
                        data: (try? record.encodedPortableData()) ?? Data()
                    )
                )
            }
            return SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: source),
                metadata: metadata,
                metadataCatalog: metadataCatalog
            )
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
        guard let lowerUTF16 = source.utf16.index(
            source.utf16.startIndex,
            offsetBy: range.utf16LowerBound,
            limitedBy: source.utf16.endIndex
        ), let upperUTF16 = source.utf16.index(
            source.utf16.startIndex,
            offsetBy: range.utf16UpperBound,
            limitedBy: source.utf16.endIndex
        ), let lower = lowerUTF16.samePosition(in: source),
           let upper = upperUTF16.samePosition(in: source) else { return nil }
        return String(source[lower..<upper])
    }
}
