import Dispatch
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Identical observer-free candidate workload can be copied into the pinned
/// baseline checkout. Source, results and cache admission are asserted; only
/// aggregate milliseconds and counts enter the diagnostic output.
@Suite(
    "Related lexical pool latency", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_LEXICAL_LATENCY"] == "1"))
struct RelatedContentLexicalPoolLatencyMeasurementTests {
    private struct RoleFixture {
        let folder: String
        let vault: RegisteredVault
    }

    private let longSuffix = "\n\n" + (0..<512).map { "conceptualword_\($0)" }.joined(separator: " ") + "\n"

    @Test("Measure observer-free cold and repeated lexical candidate queries")
    func observerFreeLatency() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repository.appendingPathComponent("TestVaults", isDirectory: true)
        for isLong in [false, true] {
            let label = isLong ? "long" : "standard"
            let storage = repository.appendingPathComponent(
                ".build/memory-stability/lexical-latency/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: storage) }
            let roles = roles(fixture: fixture)
            let index = try TriptychSearchIndex(
                databaseURL: storage.appendingPathComponent("search.sqlite"), triptychID: UUID(),
                vaults: roles.map(\.vault))
            let sourceBytes = try await populate(index: index, roles: roles, fixture: fixture, isLong: isLong)
            #expect(sourceBytes == (isLong ? 4_975_480 : 175_100))
            let seedPath = "QA Autosave A.md"
            let seed = try source(role: roles[0], path: seedPath, fixture: fixture, isLong: isLong)
            let request = RelatedContentRequest(
                seed: .init(noteID: .init(vaultID: roles[0].vault.id, relativePath: seedPath), source: seed.rawContent))
            var expected: [RelatedContentCandidate]?
            for scan in 0..<4 {
                let start = DispatchTime.now().uptimeNanoseconds
                let response = try await index.relatedMaterialSourceCandidates(request)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if let expected { #expect(response.lexicalCandidates == expected) } else { expected = response.lexicalCandidates }
                #expect((response.identityCandidates + response.lexicalCandidates).count == 499)
                let retention = await index.relatedBackgroundPreparationRetention
                print(
                    "Related lexical latency \(label): scan=\(scan) sourceBytes=\(sourceBytes) "
                        + "candidateRows=499 ms=\(String(format: "%.2f", elapsed)) "
                        + "storedEntries=\(retention.entries) storedEstimate=\(retention.estimatedBytes)")
            }
        }
    }

    private func roles(fixture: URL) -> [RoleFixture] {
        [
            RoleFixture(
                folder: "01-analyses",
                vault: .init(
                    name: "Analyses", role: .sourceCorpus,
                    canonicalPath: fixture.appendingPathComponent("01-analyses").path)),
            RoleFixture(
                folder: "02-topics",
                vault: .init(
                    name: "Topics", role: .topicKnowledge,
                    canonicalPath: fixture.appendingPathComponent("02-topics").path)),
            RoleFixture(
                folder: "03-works",
                vault: .init(
                    name: "Works", role: .draftProject,
                    canonicalPath: fixture.appendingPathComponent("03-works").path)),
        ]
    }

    private func populate(
        index: TriptychSearchIndex, roles: [RoleFixture], fixture: URL, isLong: Bool
    ) async throws -> Int {
        var documents: [SearchIndexDocument] = []
        var sourceBytes = 0
        for role in roles {
            let root = fixture.appendingPathComponent(role.folder, isDirectory: true)
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            let urls = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
            for url in urls {
                let path = String(url.path.dropFirst(root.path.count + 1))
                let note = try source(role: role, path: path, fixture: fixture, isLong: isLong)
                sourceBytes += note.sourceBytes.count
                documents.append(
                    .init(
                        vaultID: role.vault.id, vaultName: role.vault.name,
                        vaultRole: role.vault.role, document: note))
            }
        }
        #expect(documents.count == 500)
        _ = try await index.synchronize(documents)
        return sourceBytes
    }

    private func source(
        role: RoleFixture, path: String, fixture: URL, isLong: Bool
    ) throws -> NoteDocument {
        let url = fixture.appendingPathComponent(role.folder, isDirectory: true).appendingPathComponent(path)
        let decoded = try #require(NoteDocument.decodeUTF8PreservingBOM(Data(contentsOf: url)))
        let content =
            isLong && !(role.folder == "01-analyses" && path == "QA Autosave A.md")
            ? decoded + longSuffix : decoded
        return NoteDocument(relativePath: path, rawContent: content)
    }
}
