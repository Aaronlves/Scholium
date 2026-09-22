import Foundation
import SQLite3
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Batched related-content candidates")
struct RelatedContentCandidateBatchTests {
    @Test("Batch reads retain complete lexical pools, exact channel reasons, filters and limits")
    func candidatesAndReasons() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        let documents = fixture.documents
        let update = try await index.synchronize(documents)
        let request = fixture.request()
        let result = try await index.relatedMaterialSourceCandidates(request)

        #expect(result.requestID == request.id)
        #expect(result.seedFingerprint == request.seed.fingerprint)
        #expect(result.freshnessToken == .triptych(update.generation))
        #expect(result.identityCandidates.map(\.note.relativePath) == ["Alpha.md", "Beta.md"])
        #expect(!result.identityHasMore)
        #expect(result.lexicalHasMore)
        #expect(Set(result.lexicalCandidates.map(\.note.relativePath)) == ["Alpha.md", "Beta.md", "Gamma.md", "Delta.md"])
        #expect(result.lexicalCandidates.count > request.lexicalLimit)
        #expect(
            result.identityCandidates.first?.reason
                == .identityMention(
                    .init(mentions: [
                        .init(seedKind: .selectedPassage, identityKind: .title, matchedIdentity: "Alpha")
                    ])))
        let beta = try #require(result.identityCandidates.first { $0.note.relativePath == "Beta.md" })
        #expect(
            beta.reason
                == .identityMention(
                    .init(mentions: [
                        .init(seedKind: .selectedPassage, identityKind: .alias, matchedIdentity: "Zeta"),
                        .init(seedKind: .selectedPassage, identityKind: .alias, matchedIdentity: "Émotion"),
                    ])))
        let gamma = try #require(result.lexicalCandidates.first { $0.note.relativePath == "Gamma.md" })
        #expect(
            gamma.reason
                == .lexicalOverlap(
                    .init(
                        matchedFields: [.body],
                        seedMatches: [
                            .init(seedKind: .selectedPassage, terms: ["needle"]),
                            .init(seedKind: .sourceNote, terms: ["needle"]),
                        ])))
        for candidate in result.identityCandidates + result.lexicalCandidates {
            let source = try #require(
                documents.first {
                    $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath
                })
            #expect(candidate.fingerprint == source.document.fingerprint)
            #expect(candidate.vaultRole == source.vaultRole)
            #expect(candidate.note != request.seed.noteID)
        }

        let filtered = try await index.relatedMaterialSourceCandidates(fixture.request(roles: [.analysis], identityLimit: 1))
        #expect(filtered.identityCandidates == Array(result.identityCandidates.prefix(1)))
        #expect(Set(filtered.lexicalCandidates.map(\.note.relativePath)) == ["Alpha.md", "Gamma.md"])
        #expect(!filtered.identityHasMore)
        let limited = try await index.relatedMaterialSourceCandidates(fixture.request(identityLimit: 1))
        #expect(limited.identityCandidates == Array(result.identityCandidates.prefix(1)))
        #expect(limited.identityHasMore)
        #expect(limited.lexicalCandidates == result.lexicalCandidates)
        let identityDisabled = try await index.relatedMaterialSourceCandidates(fixture.request(identityLimit: 0))
        #expect(identityDisabled.identityCandidates.isEmpty)
        #expect(!identityDisabled.identityHasMore)
        #expect(identityDisabled.lexicalCandidates == result.lexicalCandidates)
        let lexicalDisplayDisabled = try await index.relatedMaterialSourceCandidates(fixture.request(lexicalLimit: 0))
        #expect(lexicalDisplayDisabled.lexicalCandidates == result.lexicalCandidates)
        #expect(lexicalDisplayDisabled.lexicalHasMore)
    }

    @Test("Alias replacement, rename and removal match complete candidate reasons after rebuild and reopen")
    func incrementalAndRebuild() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let before = try await index.relatedMaterialSourceCandidates(fixture.request())
        let changed = [
            fixture.item(fixture.analyses, "Alpha.md", "needle revised."),
            fixture.item(fixture.topics, "Beta.md", "---\naliases: [Absent]\n---\nneedle revised."),
            fixture.item(fixture.works, "Renamed.md", "needle renamed."),
        ]
        _ = try await index.synchronize(changed)
        let incremental = try await index.relatedMaterialSourceCandidates(fixture.request())
        #expect(incremental.identityCandidates.map(\.note.relativePath) == ["Alpha.md"])
        #expect(Set(incremental.lexicalCandidates.map(\.note.relativePath)) == ["Alpha.md", "Beta.md", "Renamed.md"])
        #expect(incremental.identityCandidates.first?.fingerprint != before.identityCandidates.first?.fingerprint)
        let rebuilt = try fixture.index(name: "rebuilt.sqlite")
        _ = try await rebuilt.synchronize(Array(changed.reversed()))
        let clean = try await rebuilt.relatedMaterialSourceCandidates(fixture.request())
        let reopened = try fixture.index()
        let persisted = try await reopened.relatedMaterialSourceCandidates(fixture.request())
        for actual in [clean, persisted] {
            #expect(actual.identityCandidates == incremental.identityCandidates)
            #expect(actual.lexicalCandidates == incremental.lexicalCandidates)
            #expect(actual.identityHasMore == incremental.identityHasMore)
            #expect(actual.lexicalHasMore == incremental.lexicalHasMore)
            #expect(actual.state == incremental.state)
        }
    }

    enum Damage: Sendable {
        case payload, checksum, negativeLength
    }

    @Test(
        "Batched reads retain corruption failures in identity-enabled and lexical-only requests",
        arguments: [Damage.payload, .checksum, .negativeLength], [0, 1])
    func corruption(damage: Damage, identityLimit: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item(fixture.analyses, "Alpha.md", "needle material.")])
        let mutation: String
        switch damage {
        case .payload:
            // A matching checksum still must not authorize undecodable payload.
            let checksum = RelatedContentSourceProjection.checksum(Data([0]))
            mutation = "related_lexical = X'00', related_lexical_hash = '\(checksum)'"
        case .checksum:
            mutation = "related_lexical_hash = 'incorrect'"
        case .negativeLength:
            mutation = "source_utf16_count = -1"
        }
        try fixture.execute("UPDATE search_documents SET \(mutation);")
        do {
            _ = try await index.relatedMaterialSourceCandidates(fixture.request(identityLimit: identityLimit))
            Issue.record("A corrupt candidate must fail the whole read transaction")
        } catch SearchIndexError.corruptDatabase {
            // The existing decoder's error, not a partial candidate response.
        }
    }

    @Test("Invalid required metadata is skipped before payload and source-length validation")
    func invalidMetadataRemainsSkipped() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([fixture.item(fixture.analyses, "Alpha.md", "needle material.")])
        try fixture.execute("UPDATE search_documents SET vault_id = 'invalid', source_utf16_count = -1, related_lexical_hash = 'incorrect';")
        let result = try await index.relatedMaterialSourceCandidates(fixture.request())
        #expect(result.state == .empty)
        #expect(result.identityCandidates.isEmpty)
        #expect(result.lexicalCandidates.isEmpty)
    }

    @Test("A zero-score FTS candidate still validates its persisted lexical projection")
    func zeroScoreProjectionValidation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize([
            fixture.item(fixture.analyses, "needle/Metadata.md", "Unrelated material.")
        ])
        let request = fixture.request(identityLimit: 0)
        let valid = try await index.relatedMaterialSourceCandidates(request)
        #expect(valid.lexicalCandidates.isEmpty)
        try fixture.execute("UPDATE search_documents SET related_lexical_hash = 'incorrect';")
        do {
            _ = try await index.relatedMaterialSourceCandidates(request)
            Issue.record("Zero score must not bypass candidate projection validation")
        } catch SearchIndexError.corruptDatabase {
        }
    }

    @Test("Cancelled candidate reads publish no response and leave the next transaction usable")
    func cancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let request = fixture.request()
        let before = try await index.relatedMaterialSourceCandidates(request)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await index.relatedMaterialSourceCandidates(request)
        }
        do {
            _ = try await cancelled.value
            Issue.record("A cancelled candidate read must not return candidates")
        } catch is CancellationError {
        }
        let after = try await index.relatedMaterialSourceCandidates(request)
        #expect(after == before)
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")
        let other = RegisteredVault(name: "Other", role: .other, canonicalPath: "/fixtures/other")

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/related-content-candidate-batches/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var documents: [SearchIndexDocument] {
            [
                item(analyses, "Alpha.md", "needle ordinary."),
                item(topics, "Beta.md", "---\naliases: [Émotion, Zeta, Zeta]\n---\nneedle ordinary."),
                item(analyses, "Gamma.md", "needle ordinary."),
                item(works, "Delta.md", "needle ordinary."),
                // FTS sees this path, but the ranking fields have no positive match.
                item(analyses, "needle/Metadata.md", "Unrelated material."),
                item(works, "Draft.md", "needle Alpha Zeta Émotion saved revision."),
                item(other, "Excluded.md", "needle Alpha Zeta Émotion."),
            ]
        }

        func item(_ vault: RegisteredVault, _ path: String, _ source: String) -> SearchIndexDocument {
            .init(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: path, rawContent: source))
        }

        func request(
            roles: [RelatedContentCandidateRole] = RelatedContentCandidateRole.allCases,
            identityLimit: Int = 3, lexicalLimit: Int = 1
        ) -> RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: works.id, relativePath: "Draft.md"), source: "needle surrounding",
                    focuses: [.init(kind: .selectedPassage, text: "needle Alpha Zeta E\u{301}motion")]),
                candidateRoles: roles, identityLimit: identityLimit, lexicalLimit: lexicalLimit)
        }

        func index(name: String = "search.sqlite") throws -> TriptychSearchIndex {
            try .init(
                databaseURL: root.appendingPathComponent(name), triptychID: triptychID,
                vaults: [analyses, topics, works, other])
        }

        func execute(_ sql: String) throws {
            var database: OpaquePointer?
            let opened = sqlite3_open_v2(root.appendingPathComponent("search.sqlite").path, &database, SQLITE_OPEN_READWRITE, nil)
            defer { sqlite3_close(database) }
            try #require(opened == SQLITE_OK)
            try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
