import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content focused identity lifecycle")
struct RelatedContentIdentityLifecycleTests {
    @Test(
        "Unsampled focused names follow alias removal, restoration, filename changes and deletion across index lifecycles",
        arguments: [0, RelatedContentContract.maximumIdentityCandidates])
    func identityChanges(identityLimit: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // Place the name between sampled pairs, rather than at the preserved tail.
        // The seed source cannot supply an accidental second candidate channel.
        let context = (0..<100).map { "context\($0)" }
        let focus = (Array(context.prefix(2)) + ["celadon"] + Array(context.dropFirst(2))).joined(separator: " ")
        let sampled = RelatedContentQueryTerms.terms(in: focus, limit: RelatedContentContract.maximumFocusSeedTerms)
        #expect(sampled.count == RelatedContentContract.maximumFocusSeedTerms)
        try #require(!sampled.contains("celadon"))
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: fixture.vault.id, relativePath: "Draft.md"), source: "An unrelated draft.",
                focuses: [.init(kind: .researchRequest, text: focus)]),
            identityLimit: identityLimit)
        let control = fixture.item("Control.md", "Context98 context99 remain the independent local control.")
        let initial = fixture.item("Glossary.md", fixture.body, alias: "celadon")
        let noAlias = fixture.item("Glossary.md", fixture.body)
        let title = fixture.item("Celadon.md", fixture.body)
        let noTitle = fixture.item("Catalog.md", fixture.body)
        let stages: [(String, [SearchIndexDocument], Set<String>)] = [
            ("initial", [initial, control], ["Glossary.md", "Control.md"]),
            ("alias-removed", [noAlias, control], ["Control.md"]),
            ("alias-restored", [initial, control], ["Glossary.md", "Control.md"]),
            ("renamed-title", [title, control], ["Celadon.md", "Control.md"]),
            ("title-removed", [noTitle, control], ["Control.md"]),
            ("deleted", [control], ["Control.md"]),
        ]
        let incremental = try fixture.index()
        for (name, documents, expectedPaths) in stages {
            _ = try await incremental.synchronize(documents)
            let current = try await fixture.evaluate(incremental, request: request, documents: documents)
            #expect(Set(current.map(\.candidate.note.relativePath)) == expectedPaths)

            let reopened = try fixture.index()
            #expect(try await fixture.evaluate(reopened, request: request, documents: documents) == current)
            let rebuilt = try fixture.index(name: "rebuilt-\(name).sqlite")
            _ = try await rebuilt.synchronize(Array(documents.reversed()))
            #expect(try await fixture.evaluate(rebuilt, request: request, documents: documents) == current)
        }
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/identity-lifecycle")
        let body = "Celadon names a synthetic specimen."

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/related-identity-lifecycle-tests/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func item(_ path: String, _ body: String, alias: String? = nil) -> SearchIndexDocument {
            let properties = alias.map { "---\r\naliases: [\($0)]\r\n---\r\n\r\n" } ?? ""
            let document = NoteDocument(relativePath: path, rawContent: "\u{FEFF}" + properties + body + "\r\n")
            return .init(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: document)
        }

        func index(name: String = "index.sqlite") throws -> TriptychSearchIndex {
            try .init(databaseURL: root.appendingPathComponent(name), triptychID: triptychID, vaults: [vault])
        }

        func evaluate(_ index: TriptychSearchIndex, request: RelatedContentRequest, documents: [SearchIndexDocument]) async throws
            -> [RelatedContentPassage]
        {
            let response = try await index.relatedMaterialSourceCandidates(request)
            if request.identityLimit == 0 { #expect(response.identityCandidates.isEmpty) }
            var seen = Set<VaultQualifiedNoteID>()
            let candidates = (response.identityCandidates + response.lexicalCandidates).filter { seen.insert($0.note).inserted }
            let sources = try candidates.map { candidate in
                let current = try #require(
                    documents.first { $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath })
                #expect(candidate.fingerprint == current.document.fingerprint)
                return RelatedContentSource(candidate: candidate, document: current.document)
            }
            let direct = try TriptychSearchIndex.relatedPassages(request, sources: sources)
            #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == direct)
            #expect(try await index.relatedPassages(request, sources: sources) == direct)

            let generation = try #require(await index.generation())
            let preparation = try await index.beginRelatedPassagePreparation(request, candidates: candidates, generation: generation)
            try await index.prepareRelatedPassages(preparation, sources: sources)
            #expect(try await index.relatedPassages(request, sources: sources) == direct)
            for passage in direct {
                let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
                let range = try #require(
                    Range(
                        NSRange(
                            location: passage.range.utf16LowerBound,
                            length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: original.document.rawContent))
                #expect(Data(passage.source.utf8) == Data(original.document.rawContent[range].utf8))
                #expect(passage.candidate.fingerprint == original.document.fingerprint)
                #expect(passage.candidate.vaultRole == vault.role)
            }
            return direct
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
