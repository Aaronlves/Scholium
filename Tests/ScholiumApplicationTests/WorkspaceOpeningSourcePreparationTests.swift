import Foundation
import ScholiumContracts
import Synchronization
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Opening prepares independent source catalogs concurrently")
    struct WorkspaceOpeningSourcePreparationTests {
        @Test("All vaults advance independently and final cohort validation retries an earlier installed source", .timeLimit(.minutes(1)))
        func independentProgressAndFinalValidation() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let gate = OpeningSourcePreparationGate()
            let completion = OpeningSourcePreparationCompletion()
            var opening: Task<WorkspaceHandle, Error>?
            do {
                let catalogs = try await prepareCatalogs(fixture, pool: pool, gate: gate)
                let analysisID = fixture.analysisNoteID.vaultID
                let analysis = try #require(catalogs[analysisID])
                let originals = try sourceBytes(fixture)
                let task = Task { try await open(fixture, pool: pool, completion: completion) }
                opening = task
                try await waitForOpeningPreparation { await gate.arrivedCount == 3 }
                #expect(await completion.finished == false)
                await gate.release(analysisID)
                try await waitForOpeningPreparation { (try? await analysis.snapshot()) != nil }
                #expect(await gate.heldCount == 2)
                #expect(await completion.finished == false)

                let changedURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
                let changed = Data("\u{FEFF}# Changed after one Catalog installed\r\n\r\nExact e\u{301} 中文 😀 without final newline".utf8)
                try changed.write(to: changedURL, options: .atomic)
                await gate.releaseAll()
                let handle = try await task.value
                let snapshot = try await handle.snapshot()
                #expect(snapshot.phase.isComplete)
                #expect(snapshot.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(data: changed))
                #expect(snapshot.discovery.catalog.graph?.sourceManifestHash == snapshot.discovery.searchGeneration?.sourceManifestHash)
                #expect(snapshot.vaults.map(\.vault.id) == WorkspaceVaultSlot.allCases.compactMap { fixture.assignment.vault(for: $0)?.id })
                #expect(await gate.arrivals(for: analysisID) >= 3)
                #expect(try await handle.documents.load(fixture.analysisNoteID).sourceBytes == changed)
                for source in originals {
                    #expect(try Data(contentsOf: source.url) == (source.url == changedURL ? changed : source.bytes))
                }
                await handle.shutdown()
                await pool.shutdown()
            } catch {
                await gate.releaseAll()
                opening?.cancel()
                if let opening, case .success(let handle) = await opening.result { await handle.shutdown() }
                await pool.shutdown()
                throw error
            }
        }

        @Test("A failed vault cancels and joins siblings before opening releases its source owners", .timeLimit(.minutes(1)))
        func failureJoinsOtherVaults() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let gate = OpeningSourcePreparationGate()
            let completion = OpeningSourcePreparationCompletion()
            var opening: Task<WorkspaceHandle, Error>?
            do {
                let catalogs = try await prepareCatalogs(fixture, pool: pool, gate: gate)
                let failedID = fixture.analysisNoteID.vaultID
                let failed = try #require(catalogs[failedID])
                let survivors = Set(catalogs.keys).subtracting([failedID])
                let originals = try sourceBytes(fixture)
                let task = Task { try await open(fixture, pool: pool, completion: completion) }
                opening = task
                try await waitForOpeningPreparation { await gate.arrivedCount == 3 }
                await failed.shutdown()
                await gate.release(failedID)
                // Siblings deliberately stay suspended after receiving cancellation.
                // Observing their cancellation proves the group has seen the error.
                try await waitForOpeningPreparation { survivors.allSatisfy(gate.cancellations.contains) }
                #expect(await gate.heldCount == 2)
                #expect(await completion.finished == false)
                await gate.releaseAll()
                await #expect { _ = try await task.value } throws: { ($0 as? VaultSourceCatalogError) == .shutDown }
                #expect(await completion.finished)
                if case .success(let handle) = await task.result { await handle.shutdown() }
                for source in originals { #expect(try Data(contentsOf: source.url) == source.bytes) }
                await pool.shutdown()
                #expect(await pool.runtimeCount == 0)
            } catch {
                await gate.releaseAll()
                opening?.cancel()
                if let opening, case .success(let handle) = await opening.result { await handle.shutdown() }
                await pool.shutdown()
                throw error
            }
        }

        private func prepareCatalogs(
            _ fixture: ApplicationFixture, pool: WorkspaceVaultPool, gate: OpeningSourcePreparationGate
        ) async throws -> [UUID: VaultSourceCatalog] {
            var catalogs: [UUID: VaultSourceCatalog] = [:]
            for slot in WorkspaceVaultSlot.allCases {
                let vault = try #require(fixture.assignment.vault(for: slot))
                let pooled = try await pool.vault(for: vault)
                let catalog = pooled.sourceCatalog
                await catalog.setValidationBarrierForTesting { await gate.holdFirst(vault.id) }
                catalogs[vault.id] = catalog
            }
            return catalogs
        }

        private func open(
            _ fixture: ApplicationFixture, pool: WorkspaceVaultPool, completion: OpeningSourcePreparationCompletion
        ) async throws -> WorkspaceHandle {
            do {
                let handle = try await WorkspaceHandle.open(
                    assignment: fixture.assignment, mode: .snapshot,
                    applicationSupportURL: fixture.applicationSupportURL,
                    windowSessionStore: .init(applicationSupportURL: fixture.applicationSupportURL),
                    vaultPool: pool, zotero: ZoteroOperations(applicationSupportURL: fixture.applicationSupportURL), access: .snapshot)
                await completion.finish()
                return handle
            } catch {
                await completion.finish()
                throw error
            }
        }

        private func sourceBytes(_ fixture: ApplicationFixture) throws -> [(url: URL, bytes: Data)] {
            try [
                fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath),
                fixture.topicsURL.appendingPathComponent("Freedom.md"),
                fixture.worksURL.appendingPathComponent("Chapter.md"),
            ].map { (url: $0, bytes: try Data(contentsOf: $0)) }
        }
    }

    private enum OpeningSourcePreparationError: Error { case readinessTimeout }

    private func waitForOpeningPreparation(_ predicate: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw OpeningSourcePreparationError.readinessTimeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private actor OpeningSourcePreparationCompletion {
        private(set) var finished = false
        func finish() { finished = true }
    }

    private final class OpeningSourcePreparationCancellations: Sendable {
        private let cancelled = Mutex<Set<UUID>>([])
        func record(_ id: UUID) { _ = cancelled.withLock { $0.insert(id) } }
        func contains(_ id: UUID) -> Bool { cancelled.withLock { $0.contains(id) } }
    }

    private actor OpeningSourcePreparationGate {
        nonisolated let cancellations = OpeningSourcePreparationCancellations()
        private var counts: [UUID: Int] = [:]
        private var held: [UUID: CheckedContinuation<Void, Never>] = [:]
        private var released: Set<UUID> = []
        private var allReleased = false
        var arrivedCount: Int { counts.count }
        var heldCount: Int { held.count }
        func arrivals(for id: UUID) -> Int { counts[id] ?? 0 }

        func holdFirst(_ id: UUID) async {
            counts[id, default: 0] += 1
            guard counts[id] == 1, !allReleased, !released.contains(id) else { return }
            let cancellations = cancellations
            await withTaskCancellationHandler {
                await withCheckedContinuation { held[id] = $0 }
            } onCancel: {
                cancellations.record(id)
            }
        }

        func release(_ id: UUID) {
            released.insert(id)
            held.removeValue(forKey: id)?.resume()
        }

        func releaseAll() {
            allReleased = true
            let continuations = Array(held.values)
            held.removeAll()
            for continuation in continuations { continuation.resume() }
        }
    }
#endif
