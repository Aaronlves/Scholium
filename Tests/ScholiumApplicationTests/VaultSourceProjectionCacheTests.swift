import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Fresh-source catalog projection reuse")
struct VaultSourceProjectionCacheTests {
    @Test("Oversized source fails a refresh without replacing the trustworthy catalog")
    func oversizedSourceRetainsCatalog() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let catalog = try await fixture.catalog(useCache: false)
        let original = try await preparedSnapshot(catalog)
        let oversizedURL = fixture.vaultURL.appendingPathComponent("Large.md")
        let oversized = Data(repeating: 0x20, count: VaultSourceReadLimits.maximumNoteByteCount + 1)
        try oversized.write(to: oversizedURL)
        await #expect {
            _ = try await catalog.prepare(.fullReconcile)
        } throws: { error in
            guard let error = error as? VaultRepositoryError,
                case .sourceTooLarge(let path, let maximum) = error
            else { return false }
            return path == "Large.md" && maximum == VaultSourceReadLimits.maximumNoteByteCount
        }
        let retained = try await catalog.snapshot()
        #expect(retained.generation == original.generation)
        #expect(retained.projections == original.projections)
        #expect(retained.sourceVersions == original.sourceVersions)
        #expect(try Data(contentsOf: oversizedURL) == oversized)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(fixture.source.utf8))
        // Once the external participant makes its source processable, the
        // catalog can publish the complete new generation normally.
        try Data("Available again\n".utf8).write(to: oversizedURL)
        _ = try await preparedSnapshot(catalog)
        let recovered = try await catalog.snapshot()
        #expect(recovered.generation == original.generation + 1)
        #expect(recovered.projections.map(\.relativePath).sorted() == ["Large.md", Fixture.path])
    }

    @Test("Parallel catalogs process near-limit Notes under one aggregate source budget")
    func sharedNearLimitSourceBudget() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let source = Data(repeating: 0x20, count: VaultSourceReadLimits.maximumNoteByteCount - 1)
        for number in 0..<4 {
            try source.write(to: fixture.vaultURL.appendingPathComponent("Large-\(number).md"))
        }
        let budget = VaultSourceProcessingBudget()
        let first = try await fixture.catalog(useCache: false, processingBudget: budget)
        let second = try await fixture.catalog(useCache: false, processingBudget: budget)
        async let firstSnapshot = preparedSnapshot(first)
        async let secondSnapshot = preparedSnapshot(second)
        let snapshots = try await (firstSnapshot, secondSnapshot)
        #expect(snapshots.0.projections.count == 5)
        #expect(snapshots.1.projections == snapshots.0.projections)
        #expect(snapshots.0.measurement.parsedDocuments == 5)
        #expect(snapshots.1.measurement.parsedDocuments == 5)
        let complete = await budget.statistics()
        #expect(complete.peakReservedBytes > 0)
        #expect(complete.peakReservedBytes <= VaultSourceReadLimits.maximumInFlightSourceByteCount)
        #expect(complete.reservedBytes == 0)
        #expect(complete.queued == 0)
    }

    @Test("A new catalog reads exact source and restores compact Catalog without semantic parsing")
    func freshStartupHit() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.snapshot()
        let firstSearch = try await fixture.index(first)
        #expect(firstSearch.projectedDocuments == 1)
        #expect(firstSearch.restoredSearchProjections == 0)
        #expect(first.measurement.parsedDocuments == 1)
        #expect(first.measurement.restoredCatalogProjections == 0)

        let reopened = try await fixture.snapshot()
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 0)
        #expect(reopened.measurement.restoredCatalogProjections == 1)
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
        let first = try await fixture.snapshot()
        _ = try await fixture.index(first)
        let oldVersion = try #require(first.sourceVersions[Fixture.path])
        try Data(fixture.source.utf8).write(to: fixture.noteURL, options: .atomic)
        let replacementDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: replacementDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.snapshot()
        let reopenedSearch = try await fixture.index(reopened)
        let newVersion = try #require(reopened.sourceVersions[Fixture.path])
        let newMetadata = try #require(reopened.fileMetadata[Fixture.path])
        #expect(newVersion.fingerprint == oldVersion.fingerprint)
        #expect(newVersion.inode != oldVersion.inode)
        #expect(newMetadata.modificationDate == replacementDate)
        #expect(reopened.fileMetadata != first.fileMetadata)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 0)
        #expect(reopened.measurement.restoredCatalogProjections == 1)
        #expect(reopenedSearch.restoredSearchProjections == 1)
        #expect(reopenedSearch.projectedDocuments == 0)
        #expect(reopened.projections == first.projections)
        #expect(try await fixture.projections(in: reopened) == fixture.projections(in: first))
    }

    @Test("A damaged compact record reparses fresh source and repairs only disposable state")
    func damagedCatalogRecomputes() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.snapshot()
        let record = try #require(
            FileManager.default.contentsOfDirectory(at: fixture.cacheDirectory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasSuffix(".catalog.plist") })
        try Data("damaged disposable record".utf8).write(to: record)
        let recomputed = try await fixture.snapshot()
        #expect(recomputed.measurement.readFiles == 1)
        #expect(recomputed.measurement.parsedDocuments == 1)
        #expect(recomputed.measurement.restoredCatalogProjections == 0)
        #expect(recomputed.projections == first.projections)
        #expect(recomputed.sourceVersions == first.sourceVersions)
        let restored = try await fixture.snapshot()
        #expect(restored.measurement.readFiles == 1)
        #expect(restored.measurement.parsedDocuments == 0)
        #expect(restored.measurement.restoredCatalogProjections == 1)
        #expect(restored.projections == first.projections)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(fixture.source.utf8))
    }

    @Test("Unavailable cache storage recomputes exact-source Catalog without changing source success")
    func unavailableCacheRecomputes() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let unavailable = Data("unavailable disposable cache directory".utf8)
        let vaults = fixture.supportURL.appendingPathComponent("Vaults")
        try unavailable.write(to: vaults)
        let first = try await fixture.snapshot()
        let reopened = try await fixture.snapshot()
        #expect(first.measurement.readFiles == 1 && first.measurement.parsedDocuments == 1)
        #expect(reopened.measurement.readFiles == 1 && reopened.measurement.parsedDocuments == 1)
        #expect(first.measurement.restoredCatalogProjections == 0 && reopened.measurement.restoredCatalogProjections == 0)
        #expect(first.projections == reopened.projections)
        #expect(first.sourceVersions == reopened.sourceVersions)
        #expect(try Data(contentsOf: vaults) == unavailable)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(fixture.source.utf8))
    }

    @Test("Restored Catalog candidates still reject source drift at installation and reparse current links")
    func restoredCandidateCannotPublishAfterSourceDrift() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.snapshot()
        let catalog = try await fixture.catalog()
        let candidate = try await catalog.prepare(.fullReconcile)
        let changed = fixture.source.replacingOccurrences(of: "[[Target]]", with: "[[Edited]]")
        try Data(changed.utf8).write(to: fixture.noteURL, options: .atomic)
        guard case .superseded = try await catalog.install(candidate) else {
            Issue.record("A restored candidate published after its exact source changed")
            return
        }
        await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await catalog.snapshot() }
        let fresh = try await preparedSnapshot(catalog)
        #expect(fresh.measurement.readFiles == 1)
        #expect(fresh.measurement.parsedDocuments == 1)
        #expect(fresh.measurement.restoredCatalogProjections == 0)
        #expect(fresh.projections.first?.authoredLinks.map(\.target) == ["Edited"])
        #expect(fresh.sourceVersions != first.sourceVersions)
        #expect(try Data(contentsOf: fixture.noteURL) == Data(changed.utf8))
    }

    @Test("A same-size edit with restored mtime misses the cache and parses new authored links")
    func sameSizeEditWithRestoredMtime() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        let first = try await fixture.snapshot()
        _ = try await fixture.index(first)
        let oldMetadata = try #require(first.fileMetadata[Fixture.path])
        let oldDate = try #require(oldMetadata.modificationDate)
        let edited = fixture.source.replacingOccurrences(of: "Target", with: "NewOne")
        #expect(edited.utf8.count == fixture.source.utf8.count)
        try Data(edited.utf8).write(to: fixture.noteURL)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate], ofItemAtPath: fixture.noteURL.path)

        let reopened = try await fixture.snapshot()
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.measurement.readFiles == 1)
        #expect(reopened.measurement.parsedDocuments == 1)
        #expect(reopenedSearch.restoredSearchProjections == 0)
        #expect(reopenedSearch.projectedDocuments == 1)
        #expect(reopened.projections.map(\.fingerprint) == [DocumentFingerprint(data: Data(edited.utf8))])
        #expect(reopened.projections.map(\.fingerprint) != first.projections.map(\.fingerprint))
        let projection = try #require(reopened.projections.first)
        #expect(projection.authoredLinks.map(\.target) == ["NewOne"])

        let clean = try await fixture.snapshot(useCache: false)
        #expect(reopened.projections == clean.projections)
        #expect(try await fixture.projections(in: reopened) == fixture.projections(in: clean))
    }

    @Test("A deleted source cannot be restored from a persisted Search projection")
    func missingSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.index(fixture.snapshot())
        #expect(fixture.hasPersistedProjection)
        try FileManager.default.removeItem(at: fixture.noteURL)

        let reopened = try await fixture.snapshot()
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.projections.isEmpty)
        #expect(try await fixture.projections(in: reopened).isEmpty)
        #expect(reopenedSearch.restoredSearchProjections == 0)
    }

    @Test("A source replaced by a symlink cannot borrow the original cached projection")
    func symlinkSource() async throws {
        let fixture = try await Fixture()
        defer { fixture.remove() }
        _ = try await fixture.index(fixture.snapshot())
        #expect(fixture.hasPersistedProjection)
        let outside = fixture.root.appendingPathComponent("Outside.md")
        let sentinel = Data(fixture.source.utf8)
        try sentinel.write(to: outside)
        try FileManager.default.removeItem(at: fixture.noteURL)
        try FileManager.default.createSymbolicLink(at: fixture.noteURL, withDestinationURL: outside)

        let catalog = try await fixture.catalog()
        let reopened = try await preparedSnapshot(catalog)
        let reopenedSearch = try await fixture.index(reopened)
        #expect(reopened.projections.isEmpty)
        #expect(try await fixture.projections(in: reopened).isEmpty)
        #expect(reopenedSearch.restoredSearchProjections == 0)
        // Enumeration excludes symbolic links. A later path hint still cannot
        // bypass the repository's descriptor-relative source authorization.
        await #expect(throws: (any Error).self) {
            _ = try await catalog.prepare(.delta(upserts: [Fixture.path], deletions: [], refreshFolders: false))
        }
        #expect(try Data(contentsOf: outside) == sentinel)
        #expect(try await catalog.snapshot().projections.isEmpty)
    }

    private func preparedSnapshot(_ catalog: VaultSourceCatalog) async throws -> VaultSourceCatalogSnapshot {
        let prepared = try await catalog.prepare(.fullReconcile)
        guard case .installed(let snapshot) = try await catalog.install(prepared) else {
            throw FixtureError.unexpectedSupersession
        }
        return snapshot
    }

    private enum FixtureError: Error { case unexpectedSupersession }

    private struct Fixture {
        static let path = "Note.md"
        let root: URL
        let vaultURL: URL
        let supportURL: URL
        let vaultID: UUID
        let handle: WorkspaceHandle
        let source = "\u{FEFF}---\r\nsummary: 情感 résumé\r\n---\r\n# Émotion 😀\r\n\r\nAuthored [[Target]] and *freedom*.\r\n"

        var noteURL: URL { vaultURL.appendingPathComponent(Self.path) }
        var cacheDirectory: URL {
            supportURL.appendingPathComponent("Vaults/\(vaultID.uuidString)/source-projections-v1", isDirectory: true)
        }
        var hasPersistedProjection: Bool {
            return (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path))?
                .contains { $0.hasSuffix(".projection.plist") } == true
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

        func catalog(
            useCache: Bool = true,
            processingBudget: VaultSourceProcessingBudget = .shared
        ) async throws -> VaultSourceCatalog {
            let services = await handle.services
            let repository = try #require(services.repositories[vaultID])
            if useCache {
                return VaultSourceCatalog(
                    repository: repository, vaultRole: .topicKnowledge,
                    applicationSupportURL: supportURL, vaultID: vaultID)
            }
            return VaultSourceCatalog(repository: repository, processingBudget: processingBudget)
        }

        func snapshot(useCache: Bool = true) async throws -> VaultSourceCatalogSnapshot {
            let catalog = try await catalog(useCache: useCache)
            let prepared = try await catalog.prepare(.fullReconcile)
            guard case .installed(let snapshot) = try await catalog.install(prepared) else {
                throw FixtureError.unexpectedSupersession
            }
            return snapshot
        }

        func index(_ snapshot: VaultSourceCatalogSnapshot) async throws -> (projectedDocuments: Int, restoredSearchProjections: Int) {
            // The bootstrap runtime is closed. Each publication borrows a new
            // Application-owned index and drains it before fixture deletion.
            // Its own bootstrap caches are separate from the cache under test.
            let indexSupport = root.appendingPathComponent("Index Runtime Support", isDirectory: true)
            try FileManager.default.createDirectory(at: indexSupport, withIntermediateDirectories: true)
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: indexSupport,
                        assignments: [handle.assignment])))
            do {
                let indexHandle = try await runtime.openWorkspace(id: handle.assignment.id)
                let index = try await indexHandle.services.searchIndex
                let repository = try #require(await handle.services.repositories[vaultID])
                let generation = try await index.workspaceGeneration()
                // Force the next publication to prepare the rows using the
                // freshly captured source versions and cache under test.
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
                await runtime.shutdown()
                return (measurement.projectedDocuments, measurement.restoredSearchProjections)
            } catch {
                await runtime.shutdown()
                throw error
            }
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
