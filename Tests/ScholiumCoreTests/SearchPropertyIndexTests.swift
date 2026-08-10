import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Search v7 property and relationship filters")
struct SearchPropertyIndexTests {
    @Test("Top-level property presence and exact strings retain typed source provenance")
    func propertyPresenceEqualityAndSourceRanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let source = """
        ---
        language: Ancient   Greek
        Language: Latin
        aliases: [Akrasia, "Weakness of Will"]
        concept: "  ÉTHIQUE  "
        count: 3
        blank: ""
        empty_list: []
        mixed: [Greek, 3]
        nested:
          language: Greek
        ---
        A source about akrasia.
        """
        _ = try await index.synchronize([fixture.item("Topic.md", source)])

        let presence = try await index.testSearch(fixture.request("property:language"))
        let presenceHit = try #require(presence.noteResults.first)
        #expect(presence.noteResults.map(\.relativePath) == ["Topic.md"])
        guard case .property(let presenceMatch) = presenceHit.primaryMatchReason else {
            Issue.record("Property-only Search did not expose property provenance")
            return
        }
        #expect(presenceMatch.mode == .presence)
        #expect(presenceMatch.valueKind == .string)
        #expect(!presenceMatch.isEmpty)
        #expect(sourceText(source, range: presenceMatch.keySourceRange) == "language")

        let emptyPresence = try await index.testSearch(fixture.request("property:blank"))
        guard case .property(let emptyMatch) = try #require(
            emptyPresence.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Empty Property presence did not expose its state")
            return
        }
        #expect(emptyMatch.valueKind == .string)
        #expect(emptyMatch.isEmpty)

        let emptySequence = try await index.testSearch(
            fixture.request("property:empty_list")
        )
        guard case .property(let emptySequenceMatch) = try #require(
            emptySequence.noteResults.first?.primaryMatchReason
        ) else {
            Issue.record("Empty sequence presence did not expose its state")
            return
        }
        #expect(emptySequenceMatch.valueKind == .stringSequence)
        #expect(emptySequenceMatch.isEmpty)

        let scalar = try await index.testSearch(
            fixture.request("property:language=\"  ANCIENT Greek  \"")
        )
        let scalarHit = try #require(scalar.noteResults.first)
        guard case .property(let scalarMatch) = scalarHit.primaryMatchReason else {
            Issue.record("Exact property Search did not expose value provenance")
            return
        }
        #expect(scalarMatch.mode == .exactStringValue)
        #expect(scalarMatch.normalizedValue == "ancient greek")
        #expect(scalarMatch.valueSourceRanges.map { sourceText(source, range: $0) }
            == ["Ancient   Greek"])
        #expect(scalarHit.sourceRange == scalarMatch.valueSourceRanges.first)

        let sequence = try await index.testSearch(
            fixture.request("property:aliases=\"weakness of will\"")
        )
        let sequenceHit = try #require(sequence.noteResults.first)
        guard case .property(let sequenceMatch) = sequenceHit.primaryMatchReason else {
            Issue.record("String-array Search did not expose member provenance")
            return
        }
        #expect(sequenceMatch.valueSourceRanges.map { sourceText(source, range: $0) }
            == ["\"Weakness of Will\""])

        #expect(try await index.testSearch(
            fixture.request("property:Language=latin")
        ).noteResults.count == 1)
        #expect(try await index.testSearch(
            fixture.request("property:LANGUAGE=latin")
        ).noteResults.isEmpty)
        let nonString = try await index.testSearch(fixture.request("property:count=3"))
        let mixed = try await index.testSearch(fixture.request("property:mixed=Greek"))
        let nested = try await index.testSearch(fixture.request("property:nested=Greek"))
        let foldedDiacritic = try await index.testSearch(
            fixture.request("property:concept=ethique")
        )
        #expect(nonString.noteResults.isEmpty)
        #expect(mixed.noteResults.isEmpty)
        #expect(nested.noteResults.isEmpty)
        #expect(foldedDiacritic.noteResults.isEmpty)
        #expect(try await index.testSearch(
            fixture.request("property:concept=\" éthique \"")
        ).noteResults.count == 1)
    }

    @Test("Property changes converge with a clean rebuild")
    func propertyIncrementalCleanRebuildParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let incremental = try fixture.index()
        let original = fixture.item(
            "Topic.md",
            "---\nsummary: Greek inheritance map\nlanguage: Greek\nstatus: provisional\n---\nconcept"
        )
        _ = try await incremental.synchronize([original])
        let edited = fixture.item(
            "Topic.md",
            "---\nsummary: Latin agency map\nlanguage: Latin\nstatus: settled\n---\nconcept"
        )
        _ = try await incremental.synchronize([edited])

        let clean = try fixture.index(
            at: fixture.root.appendingPathComponent("clean-search-v7.sqlite")
        )
        _ = try await clean.synchronize([edited])

        for query in [
            "property:language",
            "property:language=Greek",
            "property:language=Latin",
            "concept property:status=settled",
            "summary:agency",
            "summary:inheritance",
        ] {
            let incrementalResults = try await incremental.testSearch(fixture.request(query))
            let cleanResults = try await clean.testSearch(fixture.request(query))
            #expect(incrementalResults.noteResults.map(\.relativePath)
                == cleanResults.noteResults.map(\.relativePath))
            #expect(incrementalResults.noteResults.map(\.primaryMatchReason)
                == cleanResults.noteResults.map(\.primaryMatchReason))
            #expect(incrementalResults.noteResults.map(\.sourceRange)
                == cleanResults.noteResults.map(\.sourceRange))
            #expect(incrementalResults.noteResults.map(\.fingerprint)
                == cleanResults.noteResults.map(\.fingerprint))
        }
        #expect(try await incremental.generation()?.sourceManifestHash
            == clean.generation()?.sourceManifestHash)
    }

    @Test("Malformed and duplicate YAML fail closed only for property projection")
    func ambiguousPropertySourcesFailClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(
                "Malformed.md",
                "---\nlanguage: [Greek\n---\nmalformed-body-term"
            ),
            fixture.item(
                "Duplicate.md",
                "---\nlanguage: Greek\nlanguage: Latin\n---\nduplicate-body-term"
            ),
        ])

        #expect(try await index.testSearch(
            fixture.request("property:language")
        ).noteResults.isEmpty)
        #expect(try await index.testSearch(
            fixture.request("malformed-body-term")
        ).noteResults.map(\.relativePath) == ["Malformed.md"])
        #expect(try await index.testSearch(
            fixture.request("duplicate-body-term")
        ).noteResults.map(\.relativePath) == ["Duplicate.md"])
    }

    @Test("Lexical and property AND does not lose a late matching candidate")
    func propertyFilterHasNoCandidateCutoff() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        var documents = (0..<2_000).map { number in
            fixture.item(
                String(format: "Background/%04d.md", number),
                "---\nstatus: provisional\n---\nshared-concept shared-concept"
            )
        }
        documents.append(fixture.item(
            "zzzz-target.md",
            "---\nstatus: settled\n---\nshared-concept"
        ))
        _ = try await index.synchronize(documents)

        let response = try await index.testSearch(
            fixture.request("shared-concept property:status=settled", limit: 1)
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
        let relationship = try #require(relationships.first)
        #expect(relationship.targetNote == target)
        #expect(relationship.occurrences == [occurrence])
        #expect(relationship.occurrences.first?.sourceNote == anchor)
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
                .appendingPathComponent("search-v7-property-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            databaseURL = root.appendingPathComponent("search-v7.sqlite")
        }

        func index(at url: URL? = nil) throws -> TriptychSearchIndex {
            try TriptychSearchIndex(
                databaseURL: url ?? databaseURL,
                triptychID: triptychID
            )
        }

        func item(_ path: String, _ source: String) -> SearchIndexDocument {
            SearchIndexDocument(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                document: NoteDocument(relativePath: path, rawContent: source)
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
