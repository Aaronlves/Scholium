import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content from Works")
struct RelatedContentWorksTests {
    @Test("Default retrieval includes other Works as writing while excluding the active Note")
    func includesOtherWorks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let request = fixture.request()
        #expect(request.candidateRoles == [.analysis, .topic, .work])
        let response = try await index.relatedMaterialSourceCandidates(request)
        #expect(response.state == .current)
        #expect(Set(response.lexicalCandidates.map(\.vaultRole)) == [.sourceCorpus, .topicKnowledge, .draftProject])
        #expect(!(response.identityCandidates + response.lexicalCandidates).contains { $0.note == request.seed.noteID })
        let sources = fixture.sources(response.lexicalCandidates)
        let passages = try await index.relatedPassages(request, sources: sources)
        #expect(Set(passages.map { $0.candidate.note.relativePath }) == ["Analysis.md", "Topic.md", "Earlier Argument.md"])
        let writing = try #require(passages.first { $0.candidate.note.relativePath == "Earlier Argument.md" })
        #expect(writing.candidate.vaultRole == .draftProject)
        #expect(writing.candidate.note.vaultID == fixture.works.id)
        #expect(writing.source == "我在此比较 freedom 与 autonomy，作为尚待检验的个人论证。")
        // A lexical discovery reason and the original Works role survive
        // retrieval; the author's draft is never relabeled as an Analysis.
        guard case .lexicalOverlap(let reason) = writing.candidate.reason else {
            Issue.record("Expected a lexical discovery reason for the author's writing")
            return
        }
        #expect(reason.seedMatches.contains { $0.seedKind == .selectedPassage })
        try fixture.verifySource(writing)
    }

    @Test("Explicit role filters govern both indexed candidates and current-source passages")
    func explicitRoles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.index()
        _ = try await index.synchronize(fixture.documents)
        let all = try await index.relatedMaterialSourceCandidates(fixture.request())
        let allSources = fixture.sources(all.lexicalCandidates)
        let roleSelections: [[RelatedContentCandidateRole]] = [[.analysis], [.topic], [.work], [.analysis, .work]]
        for roles in roleSelections {
            let request = fixture.request(roles: roles)
            let expectedRoles = Set(roles.map(\.vaultRole))
            let response = try await index.relatedMaterialSourceCandidates(request)
            #expect(response.state == .current)
            #expect(Set(response.lexicalCandidates.map(\.vaultRole)) == expectedRoles)
            let passages = try await index.relatedPassages(request, sources: allSources)
            #expect(Set(passages.map { $0.candidate.vaultRole }) == expectedRoles)
            #expect(passages.allSatisfy { $0.candidate.note != request.seed.noteID })
            for passage in passages { try fixture.verifySource(passage) }
        }
        let emptyRequest = fixture.request(roles: [])
        let empty = try await index.relatedMaterialSourceCandidates(emptyRequest)
        #expect(empty.state == .invalidSeed)
        #expect(empty.lexicalCandidates.isEmpty && empty.identityCandidates.isEmpty)
        #expect(try await index.relatedPassages(emptyRequest, sources: allSources).isEmpty)
    }

    @Test("Works retain exact source revisions and reject stale candidate bytes")
    func currentRevisionAndSelfExclusion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let work = try #require(fixture.documents.first { $0.relativePath == "Earlier Argument.md" })
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: work.vaultID, relativePath: work.relativePath),
            vaultRole: work.vaultRole, title: "Earlier Argument", fingerprint: work.document.fingerprint,
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
        let source = RelatedContentSource(candidate: candidate, document: work.document)
        let request = fixture.request(roles: [.work])
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: [source])
        #expect(passages.count == 1)
        try fixture.verifySource(try #require(passages.first))
        let changed = NoteDocument(relativePath: work.relativePath, rawContent: work.document.rawContent + "\r\nChanged writing.\r\n")
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: [.init(candidate: candidate, document: changed)]).isEmpty)
        let ownNoteRequest = RelatedContentRequest(
            seed: .init(
                noteID: candidate.note, source: "Unsaved freedom autonomy writing.",
                focuses: [.init(kind: .selectedPassage, text: "freedom autonomy")]))
        #expect(try TriptychSearchIndex.relatedPassages(ownNoteRequest, sources: [source]).isEmpty)
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let works = RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/fixtures/works")

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent(".build/related-content-works/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        var documents: [SearchIndexDocument] {
            [
                item(analyses, "Analysis.md", "Freedom and autonomy are compared in this analysis."),
                item(topics, "Topic.md", "Freedom and autonomy name different concepts in this topic."),
                item(works, "Current.md", "Freedom autonomy freedom autonomy should never recommend this active Note to itself."),
                item(works, "Earlier Argument.md", "\u{FEFF}# Earlier Argument 😀\r\n\r\n我在此比较 freedom 与 autonomy，作为尚待检验的个人论证。\r\n"),
            ]
        }

        func item(_ vault: RegisteredVault, _ path: String, _ text: String) -> SearchIndexDocument {
            .init(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: path, rawContent: text))
        }

        func index() throws -> TriptychSearchIndex {
            try .init(databaseURL: root.appendingPathComponent("search.sqlite"), triptychID: triptychID, vaults: [analyses, topics, works])
        }

        func request(roles: [RelatedContentCandidateRole] = RelatedContentCandidateRole.allCases) -> RelatedContentRequest {
            .init(
                seed: .init(
                    noteID: .init(vaultID: works.id, relativePath: "Current.md"), source: "Unsaved freedom autonomy writing.",
                    focuses: [.init(kind: .selectedPassage, text: "freedom autonomy")]), candidateRoles: roles)
        }

        func sources(_ candidates: [RelatedContentCandidate]) -> [RelatedContentSource] {
            candidates.compactMap { candidate in
                guard let item = documents.first(where: { $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath }) else {
                    return nil
                }
                return .init(candidate: candidate, document: item.document)
            }
        }

        func verifySource(_ passage: RelatedContentPassage) throws {
            let item = try #require(documents.first { $0.vaultID == passage.candidate.note.vaultID && $0.relativePath == passage.candidate.note.relativePath })
            #expect(passage.candidate.fingerprint == item.document.fingerprint)
            #expect(passage.candidate.vaultRole == item.vaultRole)
            let range = try #require(
                Range(
                    NSRange(location: passage.range.utf16LowerBound, length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: item.document.rawContent))
            #expect(String(item.document.rawContent[range]) == passage.source)
            #expect(passage.range.line == 1 + item.document.rawContent[..<range.lowerBound].utf8.filter { $0 == 10 }.count)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
