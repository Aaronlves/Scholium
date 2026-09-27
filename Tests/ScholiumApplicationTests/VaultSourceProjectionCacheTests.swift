import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Fresh-source catalog projection reuse")
struct VaultSourceProjectionCacheTests {
    @Test("A new catalog reuses Search coordinates while reading and parsing current source")
    func freshStartupHit() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        let firstSearch = try await fixture.index(first)
        #expect(firstSearch.projectedDocuments == 1)
        #expect(firstSearch.restoredSearchProjections == 0)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopenedSearch.projectedDocuments == 0)
        #expect(reopenedSearch.restoredSearchProjections == 1)
        #expect(reopened.projections.map(\.fingerprint) == [DocumentFingerprint(data: Data(fixture.source.utf8))])
        #expect(try Data(contentsOf: fixture.noteURL) == Data(fixture.source.utf8))
        #expect(reopened.sourceVersions == first.sourceVersions)
        #expect(reopened.fileMetadata == first.fileMetadata)
        #expect(reopened.projections == first.projections)
        #expect(try await fixture.projections(in: reopened) == fixture.projections(in: first))
    }

    @Test("Same-content atomic replacement reuses projections and refreshes observed file facts")
    func atomicReplacementRefreshesMetadata() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        _ = try await fixture.index(first)
        let oldVersion = try #require(first.sourceVersions[Fixture.path])
        try Data(fixture.source.utf8).write(to: fixture.noteURL, options: .atomic)
        let replacementDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: replacementDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        let reopenedSearch = try await fixture.index(reopened)
        let newVersion = try #require(reopened.sourceVersions[Fixture.path])
        let newMetadata = try #require(reopened.fileMetadata[Fixture.path])
        #expect(newVersion.fingerprint == oldVersion.fingerprint)
        #expect(newVersion.inode != oldVersion.inode)
        #expect(newMetadata.modificationDate == replacementDate)
        #expect(reopened.fileMetadata != first.fileMetadata)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopenedSearch.restoredSearchProjections == 1)
        #expect(reopenedSearch.projectedDocuments == 0)
        #expect(reopened.projections == first.projections)
        #expect(try await fixture.projections(in: reopened) == fixture.projections(in: first))
    }

    @Test("A same-size edit with restored mtime misses the cache and parses new authored links")
    func sameSizeEditWithRestoredMtime() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.catalog().snapshot(refreshFolders: false)
        _ = try await fixture.index(first)
        let oldMetadata = try #require(first.fileMetadata[Fixture.path])
        let oldDate = try #require(oldMetadata.modificationDate)
        let edited = fixture.source.replacingOccurrences(of: "Target", with: "NewOne")
        #expect(edited.utf8.count == fixture.source.utf8.count)
        try Data(edited.utf8).write(to: fixture.noteURL)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopenedSearch.restoredSearchProjections == 0)
        #expect(reopenedSearch.projectedDocuments == 1)
        #expect(reopened.projections.map(\.fingerprint) == [DocumentFingerprint(data: Data(edited.utf8))])
        #expect(reopened.projections.map(\.fingerprint) != first.projections.map(\.fingerprint))
        let projection = try #require(reopened.projections.first)
        #expect(projection.authoredLinks.map(\.target) == ["NewOne"])

        let clean = try await fixture.catalog(useCache: false).snapshot(refreshFolders: false)
        #expect(reopened.projections == clean.projections)
        #expect(try await fixture.projections(in: reopened) == fixture.projections(in: clean))
    }

    @Test("A deleted source cannot be restored from a persisted Search projection")
    func missingSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.index(fixture.catalog().snapshot(refreshFolders: false))
        #expect(fixture.hasPersistedProjection)
        try FileManager.default.removeItem(at: fixture.noteURL)

        let reopened = try await fixture.catalog().snapshot(refreshFolders: false)
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.projections.isEmpty)
        #expect(try await fixture.projections(in: reopened).isEmpty)
        #expect(reopenedSearch.restoredSearchProjections == 0)
    }

    @Test("A source replaced by a symlink cannot borrow the original cached projection")
    func symlinkSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.index(fixture.catalog().snapshot(refreshFolders: false))
        #expect(fixture.hasPersistedProjection)
        let outside = fixture.root.appendingPathComponent("Outside.md")
        let sentinel = Data(fixture.source.utf8)
        try sentinel.write(to: outside)
        try FileManager.default.removeItem(at: fixture.noteURL)
        try FileManager.default.createSymbolicLink(at: fixture.noteURL, withDestinationURL: outside)

        let catalog = try await fixture.catalog()
        let reopened = try await catalog.snapshot(refreshFolders: false)
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.projections.isEmpty)
        #expect(try await fixture.projections(in: reopened).isEmpty)
        #expect(reopenedSearch.restoredSearchProjections == 0)
        // Enumeration excludes symbolic links. A later path hint still cannot
        // bypass the repository's descriptor-relative source authorization.
        await #expect(throws: (any Error).self) {
            try await catalog.apply(upserts: [Fixture.path], deletions: [], refreshFolders: false)
        }
        #expect(try Data(contentsOf: outside) == sentinel)
        #expect(try await catalog.snapshot(refreshFolders: false).projections.isEmpty)
    }

    private struct Fixture {
        static let path = "Note.md"
        let root: URL
        let vaultURL: URL
        let supportURL: URL
        let vaultID: UUID
        let handle: WorkspaceHandle
        let source = "\u{FEFF}---\r\nsummary: 情感 résumé\r\n---\r\n# Émotion 😀\r\n\r\nAuthored [[Target]] and *freedom*.\r\n"

        var noteURL: URL { vaultURL.appendingPathComponent(Self.path) }
        var hasPersistedProjection: Bool {
            let directory = supportURL.appendingPathComponent(
                "Vaults/\(vaultID.uuidString)/source-projections-v1", isDirectory: true)
            return (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
                .contains { $0.hasSuffix(".projection.json") } == true
        }

        init() async throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/vault-source-projection-tests/\(UUID().uuidString)", isDirectory: true)
            vaultURL = root.appendingPathComponent("Vault", isDirectory: true)
            supportURL = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            try Data(source.utf8).write(to: vaultURL.appendingPathComponent(Self.path))
            let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
            let works = root.appendingPathComponent("Works", isDirectory: true)
            for directory in [analyses, works] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            // Configure via the Application boundary, then stop its native
            // watchers. These isolated catalog tests borrow only the existing
            // repository capability and use a separate, initially empty cache.
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: root.appendingPathComponent("Runtime Support", isDirectory: true),
                        workspaceRegistryStorageURL: root.appendingPathComponent("Registry", isDirectory: true))))
            do {
                handle = try await runtime.configureTriptych(
                    paperAnalysisURL: analyses, topicKnowledgeURL: vaultURL,
                    outputURL: works, portableContainerURL: root, triptychName: "Projection cache fixture")
                vaultID = try #require(handle.assignment.vault(for: .topicKnowledge)?.id)
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func catalog(useCache: Bool = true) async throws -> VaultSourceCatalog {
            let services = await handle.services
            let repository = try #require(services.repositories[vaultID])
            if useCache {
                return VaultSourceCatalog(
                    repository: repository, vaultRole: .topicKnowledge,
                    applicationSupportURL: supportURL, vaultID: vaultID)
            }
            return VaultSourceCatalog(repository: repository)
        }

        func index(_ snapshot: VaultSourceCatalogSnapshot) async throws -> (projectedDocuments: Int, restoredSearchProjections: Int) {
            let index = await handle.services.searchIndex
            let repository = try #require(await handle.services.repositories[vaultID])
            let generation = try await index.workspaceGeneration()
            // Clear only this stopped fixture runtime's disposable index so
            // the next publication must prepare the source-derived rows.
            _ = try await index.synchronizeManifest(
                [], workspaceGeneration: generation + 1,
                loadChanged: { _ in throw SearchIndexError.invalidDocuments("unexpected fixture source") },
                validateManifest: {})
            _ = try await index.synchronizeManifest(
                snapshot.projections.map { projection in
                    SearchIndexManifestEntry(
                        vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                        relativePath: projection.relativePath, stableNoteID: nil,
                        fingerprint: projection.fingerprint, hasBrokenLink: false)
                },
                sourceProjectionCaches: snapshot.searchProjectionCache.map { [vaultID: $0] } ?? [:],
                workspaceGeneration: generation + 2,
                loadChanged: { entry in
                    let loaded = try await repository.loadCatalogSource(relativePath: entry.relativePath)
                    guard loaded.version == snapshot.sourceVersions[entry.relativePath] else {
                        throw WorkspaceHydrationError.staleSnapshot
                    }
                    return SearchIndexDocument(
                        vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                        document: loaded.document)
                },
                validateManifest: {
                    for (path, version) in snapshot.sourceVersions {
                        guard try await repository.sourceVersionIsCurrent(relativePath: path, version: version)
                        else { throw WorkspaceHydrationError.staleSnapshot }
                    }
                })
            let measurement = try #require(await index.lastSynchronizationTimings)
            return (measurement.projectedDocuments, measurement.restoredSearchProjections)
        }

        func projections(in snapshot: VaultSourceCatalogSnapshot) async throws -> [String: SearchDocumentProjection] {
            let repository = try #require(await handle.services.repositories[vaultID])
            var result: [String: SearchDocumentProjection] = [:]
            for projection in snapshot.projections {
                let document = try await repository.load(relativePath: projection.relativePath)
                result[projection.relativePath] =
                    snapshot.searchProjectionCache?.load(for: document)
                    ?? SearchDocumentProjection(document: document)
            }
            return result
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
