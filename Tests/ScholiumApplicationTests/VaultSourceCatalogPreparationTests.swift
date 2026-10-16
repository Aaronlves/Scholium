import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Immutable source catalog preparation and installation")
struct VaultSourceCatalogPreparationTests {
    @Test("Read APIs never parse or install an unprepared catalog")
    func readsRequireExplicitInstallation() async throws {
        try await withFixture { fixture in
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.snapshot() }
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.sourceInventory() }
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.publicationInventory() }
            let fingerprint = DocumentFingerprint(data: Fixture.source)
            #expect(await fixture.catalog.sourceVersion(relativePath: Fixture.path, fingerprint: fingerprint) == nil)

            let candidate = try await fixture.catalog.prepare(.ifNeeded)
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.snapshot() }
            let installed = try installedSnapshot(await fixture.catalog.install(candidate))
            #expect(installed.generation == 1)
            #expect(installed.measurement.enumeratedFiles == 1)
            #expect(installed.measurement.readFiles == 1)
            #expect(installed.measurement.parsedDocuments == 1)
            #expect(try await fixture.catalog.sourceInventory() == [Fixture.path: fingerprint])
            #expect(try await fixture.catalog.publicationInventory().fingerprints == [Fixture.path: fingerprint])
            #expect(try await fixture.catalog.snapshot().sourceVersions == installed.sourceVersions)
            #expect(try await fixture.catalog.validate(installed) == .current)
            #expect(await fixture.catalog.sourceVersion(relativePath: Fixture.path, fingerprint: fingerprint) != nil)
            #expect(try Data(contentsOf: fixture.noteURL) == Fixture.source)

            let measured = try await fixture.catalog.snapshot(consumePendingMeasurement: true)
            let consumed = try await fixture.catalog.snapshot(consumePendingMeasurement: true)
            #expect(measured.measurement == installed.measurement)
            #expect(consumed.measurement.readFiles == 0)
            #expect(consumed.measurement.parsedDocuments == 0)
            #expect(consumed.sourceVersions == installed.sourceVersions)
        }
    }

    @Test("An older prepared catalog cannot overwrite a newer installed delta")
    func olderCandidateCannotReplaceNewerDelta() async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let older = try await fixture.catalog.prepare(.fullReconcile)
            let replacement = Data("# New generation\n\nFresh [[Target]].\n".utf8)
            try replacement.write(to: fixture.noteURL, options: .atomic)
            let current = try await prepareAndInstall(
                fixture.catalog,
                .delta(
                    upserts: [Fixture.path], deletions: [], refreshFolders: false))
            #expect(current.generation == initial.generation + 1)
            #expect(current.measurement.readFiles == 1)
            #expect(current.measurement.parsedDocuments == 1)
            #expect(isSuperseded(try await fixture.catalog.install(older)))
            #expect(try await fixture.catalog.snapshot().sourceVersions == current.sourceVersions)
            #expect(try await fixture.catalog.validate(initial) == .superseded)
            #expect(try await fixture.catalog.validate(current) == .current)
            #expect(try Data(contentsOf: fixture.noteURL) == replacement)
        }
    }

    enum SourceDrift: CaseIterable, Sendable {
        case content, sameBytesReplacement, missingNote, addedNote, addedFolder
    }

    @Test("Installation rejects unwatched source and inventory drift", arguments: SourceDrift.allCases)
    func unwatchedDriftIsSuperseded(_ drift: SourceDrift) async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let candidate = try await fixture.catalog.prepare(.ifNeeded)
            switch drift {
            case .content:
                try Data("# Changed externally\n".utf8).write(to: fixture.noteURL)
            case .sameBytesReplacement:
                try Fixture.source.write(to: fixture.noteURL, options: .atomic)
            case .missingNote:
                try FileManager.default.removeItem(at: fixture.noteURL)
            case .addedNote:
                try Data("# Added\n".utf8).write(to: fixture.vaultURL.appendingPathComponent("Added.md"))
            case .addedFolder:
                try FileManager.default.createDirectory(
                    at: fixture.vaultURL.appendingPathComponent("Empty folder"), withIntermediateDirectories: false)
            }
            #expect(isSuperseded(try await fixture.catalog.install(candidate)))
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.snapshot() }
            #expect(await fixture.catalog.sourceVersion(relativePath: Fixture.path, fingerprint: DocumentFingerprint(data: Fixture.source)) == nil)
            let recovered = try await prepareAndInstall(fixture.catalog, .ifNeeded)
            #expect(recovered.generation == initial.generation + 1)
            #expect(try await fixture.catalog.validate(recovered) == .current)
            switch drift {
            case .content:
                #expect(recovered.sourceVersions[Fixture.path]?.fingerprint != initial.sourceVersions[Fixture.path]?.fingerprint)
            case .sameBytesReplacement:
                #expect(recovered.sourceVersions[Fixture.path]?.fingerprint == initial.sourceVersions[Fixture.path]?.fingerprint)
                #expect(recovered.sourceVersions[Fixture.path]?.inode != initial.sourceVersions[Fixture.path]?.inode)
            case .missingNote:
                #expect(recovered.projections.isEmpty)
            case .addedNote:
                #expect(Set(recovered.sourceVersions.keys) == [Fixture.path, "Added.md"])
            case .addedFolder:
                #expect(recovered.folders == [try VaultRelativeFolderPath("Empty folder")])
            }
        }
    }

    @Test("Cohort validation notices an unwatched edit before an immutable capture is used")
    func installedCohortValidationDetectsDrift() async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            try Data("# Changed after readiness\n".utf8).write(to: fixture.noteURL)
            #expect(try await fixture.catalog.validate(initial) == .superseded)
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.publicationInventory() }
            let repaired = try await prepareAndInstall(fixture.catalog, .ifNeeded)
            #expect(try await fixture.catalog.validate(repaired) == .current)
            #expect(repaired.sourceVersions != initial.sourceVersions)
        }
    }

    @Test("An invalidation retires a prepared candidate even if source bytes are unchanged")
    func reconciliationInvalidatesCandidate() async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let candidate = try await fixture.catalog.prepare(.ifNeeded)
            await fixture.catalog.requireFullReconcile()
            #expect(isSuperseded(try await fixture.catalog.install(candidate)))
            #expect(try await fixture.catalog.validate(initial) == .superseded)
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.sourceInventory() }
            let repaired = try await prepareAndInstall(fixture.catalog, .ifNeeded)
            #expect(repaired.generation == initial.generation)
            #expect(repaired.measurement.enumeratedFiles == 1)
            #expect(repaired.measurement.readFiles == 0)
        }
    }

    @Test("Candidate and immutable snapshot authority are bound to one catalog owner")
    func catalogOwnerIsNotInterchangeable() async throws {
        try await withFixture { fixture in
            let other = fixture.secondaryCatalog
            let candidate = try await fixture.catalog.prepare(.fullReconcile)
            await #expect(throws: VaultSourceCatalogError.foreignPreparation) { try await other.install(candidate) }
            let installed = try installedSnapshot(await fixture.catalog.install(candidate))
            await #expect(throws: VaultSourceCatalogError.foreignPreparation) { try await other.validate(installed) }
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await other.snapshot() }
        }
    }

    @Test("Final CAS prevents reentrant installation after validation has read source")
    func installationRepeatsCASAfterValidationSuspends() async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let candidate = try await fixture.catalog.prepare(.ifNeeded)
            let gate = ValidationGate()
            defer { Task { await gate.release() } }
            await fixture.catalog.setValidationBarrierForTesting { await gate.holdFirst() }
            let delayed = Task { try await fixture.catalog.install(candidate) }
            await gate.waitForArrival()
            let replacement = Data("# Newer while old validation was suspended\n".utf8)
            try replacement.write(to: fixture.noteURL, options: .atomic)
            let newer = try await prepareAndInstall(
                fixture.catalog,
                .delta(
                    upserts: [Fixture.path], deletions: [], refreshFolders: false))
            await gate.release()
            #expect(isSuperseded(try await delayed.value))
            let current = try await fixture.catalog.snapshot()
            #expect(current.generation == initial.generation + 1)
            #expect(current.sourceVersions == newer.sourceVersions)
            #expect(try await fixture.catalog.validate(newer) == .current)
            #expect(try Data(contentsOf: fixture.noteURL) == replacement)
        }
    }

    enum Retirement: CaseIterable, Sendable { case rootUnavailable, shutDown, cancelled }

    @Test("Root loss, shutdown and cancellation cannot publish a validated but suspended candidate", arguments: Retirement.allCases)
    func retirementDuringFinalValidation(_ retirement: Retirement) async throws {
        try await withFixture { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let replacement = Data("# Candidate must remain unpublished\n".utf8)
            try replacement.write(to: fixture.noteURL, options: .atomic)
            let candidate = try await fixture.catalog.prepare(
                .delta(
                    upserts: [Fixture.path], deletions: [], refreshFolders: false))
            let gate = ValidationGate()
            defer { Task { await gate.release() } }
            await fixture.catalog.setValidationBarrierForTesting { await gate.holdFirst() }
            let delayed = Task { try await fixture.catalog.install(candidate) }
            await gate.waitForArrival()
            switch retirement {
            case .rootUnavailable: await fixture.catalog.invalidateRootAuthority()
            case .shutDown: await fixture.catalog.shutdown()
            case .cancelled: delayed.cancel()
            }
            await gate.release()
            switch retirement {
            case .rootUnavailable:
                await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await delayed.value }
                await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await fixture.catalog.snapshot() }
                await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await fixture.catalog.validate(initial) }
                await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await fixture.catalog.prepare(.fullReconcile) }
            case .shutDown:
                await #expect(throws: VaultSourceCatalogError.shutDown) { try await delayed.value }
                await #expect(throws: VaultSourceCatalogError.shutDown) { try await fixture.catalog.snapshot() }
                await #expect(throws: VaultSourceCatalogError.shutDown) { try await fixture.catalog.validate(initial) }
                await #expect(throws: VaultSourceCatalogError.shutDown) { try await fixture.catalog.prepare(.fullReconcile) }
            case .cancelled:
                await #expect(throws: CancellationError.self) { try await delayed.value }
                let retained = try await fixture.catalog.snapshot()
                #expect(retained.generation == initial.generation)
                #expect(retained.sourceVersions == initial.sourceVersions)
                let repaired = try installedSnapshot(await fixture.catalog.install(candidate))
                #expect(repaired.generation == initial.generation + 1)
            }
            #expect(try Data(contentsOf: fixture.noteURL) == replacement)
        }
    }

    @Test("A replacement vault root never inherits a prepared source catalog")
    func rootReplacementFailsClosed() async throws {
        try await withFixture { fixture in
            _ = try await prepareAndInstall(fixture.catalog)
            let candidate = try await fixture.catalog.prepare(.ifNeeded)
            let retired = fixture.root.appendingPathComponent("Retired vault")
            try FileManager.default.moveItem(at: fixture.vaultURL, to: retired)
            try FileManager.default.createDirectory(at: fixture.vaultURL, withIntermediateDirectories: false)
            let replacement = Data("# Foreign root\n".utf8)
            try replacement.write(to: fixture.noteURL)
            await #expect {
                try await fixture.catalog.install(candidate)
            } throws: { error in
                if let error = error as? VaultSourceCatalogError, error == .rootUnavailable { return true }
                guard let error = error as? VaultRepositoryError, case .rootUnavailable = error else { return false }
                return true
            }
            await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await fixture.catalog.snapshot() }
            #expect(try Data(contentsOf: fixture.noteURL) == replacement)
            #expect(try Data(contentsOf: retired.appendingPathComponent(Fixture.path)) == Fixture.source)
        }
    }

    @Test("Cancellation during admission drains queued work without publishing or retaining raw sources")
    func cancelledPreparationReleasesBudget() async throws {
        let budget = VaultSourceProcessingBudget(maximumInFlightSourceByteCount: 1_024, reservationByteCount: 1_024)
        try await withFixture(processingBudget: budget) { fixture in
            let gate = ValidationGate()
            defer { Task { await gate.release() } }
            let holder = Task { try await budget.withReservation { await gate.holdFirst() } }
            await gate.waitForArrival()
            let preparation = Task { try await fixture.catalog.prepare(.fullReconcile) }
            for _ in 0..<10_000 {
                if await budget.statistics().queued == 1 { break }
                await Task.yield()
            }
            #expect(await budget.statistics().queued == 1)
            preparation.cancel()
            await #expect(throws: CancellationError.self) { try await preparation.value }
            #expect(await budget.statistics().queued == 0)
            #expect(await budget.statistics().reservedBytes == 1_024)
            await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await fixture.catalog.snapshot() }
            await gate.release()
            try await holder.value
            #expect(await budget.statistics().reservedBytes == 0)
            let installed = try await prepareAndInstall(fixture.catalog)
            #expect(installed.measurement.readFiles == 1)
            #expect(await budget.statistics().reservedBytes == 0)
        }
    }

    @Test("Delta and if-needed installation keep cache cleanup bounded to their own paths")
    func deltaDoesNotPruneUnrelatedCacheRecords() async throws {
        try await withFixture(useCache: true) { fixture in
            let initial = try await prepareAndInstall(fixture.catalog)
            let cache = try #require(initial.searchProjectionCache)
            let orphan = NoteDocument(relativePath: "Unrelated.md", rawContent: "# Disposable cache record\n")
            cache.store(SearchDocumentProjection(document: orphan), for: orphan)
            #expect(cache.load(for: orphan) != nil)
            _ = try await prepareAndInstall(fixture.catalog, .ifNeeded)
            #expect(cache.load(for: orphan) != nil)
            try Data("# Changed\n".utf8).write(to: fixture.noteURL)
            let changed = try await prepareAndInstall(
                fixture.catalog,
                .delta(
                    upserts: [Fixture.path], deletions: [], refreshFolders: false))
            #expect(cache.load(for: orphan) != nil)
            let services = await fixture.handle.services
            let repository = try #require(services.repositories[fixture.vaultID])
            let currentDocument = try await repository.load(relativePath: Fixture.path)
            cache.store(SearchDocumentProjection(document: currentDocument), for: currentDocument)
            #expect(cache.load(for: currentDocument) != nil)
            try FileManager.default.removeItem(at: fixture.noteURL)
            let candidate = try await fixture.catalog.prepare(
                .delta(
                    upserts: [], deletions: [Fixture.path], refreshFolders: false))
            #expect(cache.load(for: currentDocument) != nil)
            _ = try installedSnapshot(await fixture.catalog.install(candidate))
            #expect(cache.load(for: currentDocument) == nil)
            #expect(cache.load(for: orphan) != nil)
            #expect(try await fixture.catalog.validate(changed) == .superseded)
            _ = try await prepareAndInstall(fixture.catalog)
            #expect(cache.load(for: orphan) == nil)
        }
    }

    private func withFixture(
        useCache: Bool = false,
        processingBudget: VaultSourceProcessingBudget = .shared,
        _ operation: (Fixture) async throws -> Void
    ) async throws {
        let fixture = try await Fixture(useCache: useCache, processingBudget: processingBudget)
        do {
            try await operation(fixture)
        } catch {
            await fixture.shutdownAndRemove()
            throw error
        }
        await fixture.shutdownAndRemove()
    }

    private func prepareAndInstall(
        _ catalog: VaultSourceCatalog,
        _ preparation: VaultSourceCatalogPreparation = .fullReconcile
    ) async throws -> VaultSourceCatalogSnapshot {
        let prepared = try await catalog.prepare(preparation)
        return try installedSnapshot(await catalog.install(prepared))
    }

    private func installedSnapshot(_ installation: VaultSourceCatalog.Installation) throws -> VaultSourceCatalogSnapshot {
        guard case .installed(let snapshot) = installation else { throw FixtureError.unexpectedSupersession }
        return snapshot
    }

    private func isSuperseded(_ installation: VaultSourceCatalog.Installation) -> Bool {
        if case .superseded = installation { return true }
        return false
    }

    private enum FixtureError: Error { case unexpectedSupersession }

    private struct Fixture {
        static let path = "Note.md"
        static let source = Data(
            "\u{FEFF}---\r\nsummary: \"情感 re\u{301}sume\u{301}\"\r\nunknown: 'preserved'\r\n---\r\n# 😀 [[Target]]\r\nNo final newline".utf8)
        let root: URL
        let vaultURL: URL
        let handle: WorkspaceHandle
        let vaultID: UUID
        let catalog: VaultSourceCatalog
        let secondaryCatalog: VaultSourceCatalog
        var noteURL: URL { vaultURL.appendingPathComponent(Self.path) }

        init(useCache: Bool = false, processingBudget: VaultSourceProcessingBudget = .shared) async throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent(".build/catalog-preparation/\(UUID().uuidString)")
            vaultURL = root.appendingPathComponent("Vault")
            let support = root.appendingPathComponent("Application Support")
            let cacheSupport = root.appendingPathComponent("Catalog Cache", isDirectory: true)
            let topics = root.appendingPathComponent("Topics")
            let works = root.appendingPathComponent("Works")
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: support,
                        workspaceRegistryStorageURL: root.appendingPathComponent("Registry"))))
            do {
                for directory in [vaultURL, topics, works] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try Self.source.write(to: vaultURL.appendingPathComponent(Self.path))
                handle = try await runtime.configureTriptych(
                    paperAnalysisURL: vaultURL, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: root, triptychName: "Catalog preparation fixture")
                vaultID = try #require(handle.assignment.vault(for: .paperAnalysis)?.id)
                let services = await handle.services
                let repository = try #require(services.repositories[vaultID])
                if useCache {
                    try FileManager.default.createDirectory(at: cacheSupport, withIntermediateDirectories: true)
                }
                catalog = VaultSourceCatalog(
                    repository: repository,
                    searchProjectionCache: useCache
                        ? .init(applicationSupportURL: cacheSupport, vaultID: vaultID, role: .sourceCorpus) : nil,
                    processingBudget: processingBudget)
                secondaryCatalog = VaultSourceCatalog(repository: repository)
                // Borrow descriptor capabilities only after the configuring
                // runtime has stopped all native observation and background work.
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func shutdownAndRemove() async {
            await catalog.shutdown()
            await secondaryCatalog.shutdown()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private actor ValidationGate {
        private var arrived = false
        private var opened = false
        private var arrival: CheckedContinuation<Void, Never>?
        private var releaseContinuation: CheckedContinuation<Void, Never>?

        func holdFirst() async {
            guard !arrived else { return }
            arrived = true
            arrival?.resume()
            arrival = nil
            guard !opened else { return }
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitForArrival() async {
            guard !arrived else { return }
            await withCheckedContinuation { arrival = $0 }
        }

        func release() {
            opened = true
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }
}
