import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in allocator attribution for the current versioned standard 500-note QA
/// Triptych and short seed. Fixture revisions change the input; compare results
/// only with the same manifest SHA, not the historical 175100-byte baseline.
/// This is not an App footprint measurement.
@Suite(
    "Related cache attribution", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_CACHE_ATTRIBUTION"] == "1"))
struct RelatedContentCacheAttributionMeasurementTests {
    private struct RoleFixture {
        let folder: String
        let vault: RegisteredVault
    }

    private struct FixtureSourceIdentity: Encodable {
        let role: VaultRole
        let path: String
        let fingerprint: DocumentFingerprint
    }

    private let longSuffix = "\n\n" + (0..<512).map { "conceptualword_\($0)" }.joined(separator: " ") + "\n"

    @Test("Attribute actual short-seed background candidate and passage preparation")
    func shortSeedPreparation() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureRoot = repositoryRoot.appendingPathComponent("TestVaults", isDirectory: true)
        for isLong in [false, true] {
            let label = isLong ? "long" : "standard"
            let storage = repositoryRoot.appendingPathComponent(
                ".build/memory-cache/related-attribution/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: storage) }
            let roles = [
                RoleFixture(
                    folder: "01-analyses",
                    vault: .init(name: "Analyses", role: .sourceCorpus, canonicalPath: fixtureRoot.appendingPathComponent("01-analyses").path)),
                RoleFixture(
                    folder: "02-topics",
                    vault: .init(name: "Topics", role: .topicKnowledge, canonicalPath: fixtureRoot.appendingPathComponent("02-topics").path)),
                RoleFixture(
                    folder: "03-works", vault: .init(name: "Works", role: .draftProject, canonicalPath: fixtureRoot.appendingPathComponent("03-works").path)),
            ]
            let index = try TriptychSearchIndex(
                isolatedDatabaseURL: storage.appendingPathComponent("search.sqlite"), triptychID: UUID(),
                vaults: roles.map(\.vault))
            do {
                let fixture = try await populate(index: index, roles: roles, fixtureRoot: fixtureRoot, isLong: isLong)
                let baselineAllocated = allocatedBytes()
                let baselineSQLite = try #require(await index.sqlitePageCacheRetention)
                let seedPath = "QA Autosave A.md"
                let seed = try source(
                    role: roles[0], path: seedPath, fixtureRoot: fixtureRoot, isLong: isLong)
                let request = RelatedContentRequest(
                    seed: .init(noteID: .init(vaultID: roles[0].vault.id, relativePath: seedPath), source: seed.rawContent))
                let response = try await index.relatedMaterialSourceCandidates(request)
                let lexicalAllocated = allocatedBytes()
                let lexicalRetention = await index.relatedBackgroundPreparationRetention
                let lexicalSQLite = try #require(await index.sqlitePageCacheRetention)
                guard case .current(let generation) = response.availability else {
                    Issue.record("The standard QA fixture Search generation did not become current")
                    await index.shutdown()
                    return
                }
                let candidates = response.identityCandidates + response.lexicalCandidates
                let preparation = try await index.beginRelatedPassagePreparation(
                    request, candidates: candidates, generation: generation)
                var batch: [RelatedContentSource] = []
                var batchBytes = 0
                var preparedSources = 0
                var seen = Set<VaultQualifiedNoteID>()
                for candidate in candidates where seen.insert(candidate.note).inserted {
                    guard let role = roles.first(where: { $0.vault.id == candidate.note.vaultID }) else { continue }
                    let document = try source(
                        role: role, path: candidate.note.relativePath, fixtureRoot: fixtureRoot, isLong: isLong)
                    guard document.fingerprint == candidate.fingerprint else { continue }
                    batch.append(.init(candidate: candidate, document: document))
                    batchBytes += document.sourceBytes.count
                    preparedSources += 1
                    if batch.count == 16 || batchBytes >= 1_024 * 1_024 {
                        try await index.prepareRelatedPassages(preparation, sources: batch)
                        batch.removeAll(keepingCapacity: false)
                        batchBytes = 0
                    }
                }
                if !batch.isEmpty { try await index.prepareRelatedPassages(preparation, sources: batch) }
                batch.removeAll(keepingCapacity: false)
                let passageAllocated = allocatedBytes()
                let passageRetention = await index.relatedPassagePreparationRetention
                let passageStatistics = await index.relatedPassagePreparationStatistics
                let passageSQLite = try #require(await index.sqlitePageCacheRetention)
                print(
                    "Related cache attribution \(label): fixture=versioned-standard-QA "
                        + "fixtureSHA=\(fixture.sha256) sourceNotes=500 sourceBytes=\(fixture.sourceBytes) "
                        + "candidateRows=\(candidates.count) preparedSources=\(preparedSources) "
                        + "lexicalEntries=\(lexicalRetention.entries) lexicalEstimated=\(lexicalRetention.estimatedBytes) "
                        + "passageEntries=\(passageRetention.entries) passageEstimated=\(passageRetention.estimatedBytes) "
                        + "passageMisses=\(passageStatistics.misses) "
                        + "allocatorBaseline=\(baselineAllocated) allocatorAfterLexical=\(lexicalAllocated) "
                        + "allocatorAfterPassage=\(passageAllocated) "
                        + "sqliteReader=\(baselineSQLite.readerBytes),\(lexicalSQLite.readerBytes),\(passageSQLite.readerBytes) "
                        + "sqliteWriter=\(baselineSQLite.writerBytes),\(lexicalSQLite.writerBytes),\(passageSQLite.writerBytes)")
                #expect(preparedSources == Set(candidates.map(\.note)).count)
                #expect(passageRetention.entries > 0)
                #expect(passageStatistics.misses == preparedSources)
                #expect(lexicalRetention.estimatedBytes <= RelatedContentBackgroundPreparation.defaultMaximumByteCount)
                #expect(passageRetention.estimatedBytes <= RelatedContentSourceProjectionMemo.defaultMaximumByteCount)
            } catch {
                await index.shutdown()
                throw error
            }
            await index.shutdown()
        }
    }

    private func populate(
        index: TriptychSearchIndex, roles: [RoleFixture], fixtureRoot: URL, isLong: Bool
    ) async throws -> (sourceBytes: Int, sha256: String) {
        var documents: [SearchIndexDocument] = []
        var manifest: [FixtureSourceIdentity] = []
        var sourceBytes = 0
        for role in roles {
            let root = fixtureRoot.appendingPathComponent(role.folder, isDirectory: true)
            let enumerator = try #require(
                FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            let urls = enumerator.compactMap { $0 as? URL }
                .filter { $0.pathExtension.lowercased() == "md" }.sorted { $0.path < $1.path }
            for url in urls {
                let path = String(url.path.dropFirst(root.path.count + 1))
                let document = try source(role: role, path: path, fixtureRoot: fixtureRoot, isLong: isLong)
                sourceBytes += document.sourceBytes.count
                // Fixed role order and sorted paths identify the exact indexed
                // bytes, including BOM/newlines and the optional long suffix.
                manifest.append(
                    .init(role: role.vault.role, path: "\(role.folder)/\(path)", fingerprint: document.fingerprint))
                documents.append(
                    .init(
                        vaultID: role.vault.id, vaultName: role.vault.name,
                        vaultRole: role.vault.role, document: document))
            }
        }
        #expect(documents.count == 500)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fixtureSHA = DocumentFingerprint(data: try encoder.encode(manifest)).sha256
        _ = try await index.synchronize(documents)
        return (sourceBytes, fixtureSHA)
    }

    private func source(
        role: RoleFixture, path: String, fixtureRoot: URL, isLong: Bool
    ) throws -> NoteDocument {
        let url = fixtureRoot.appendingPathComponent(role.folder, isDirectory: true)
            .appendingPathComponent(path)
        let decoded = try #require(NoteDocument.decodeUTF8PreservingBOM(Data(contentsOf: url)))
        let content =
            isLong && !(role.folder == "01-analyses" && path == "QA Autosave A.md")
            ? decoded + longSuffix : decoded
        return NoteDocument(relativePath: path, rawContent: content)
    }

    private func allocatedBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }
}
