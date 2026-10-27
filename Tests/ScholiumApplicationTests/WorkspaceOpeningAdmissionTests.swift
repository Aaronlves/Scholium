import Foundation
import ScholiumContracts
import Synchronization
import Testing

@testable import ScholiumApplication
@testable import ScholiumCore

#if DEBUG
    @Suite("Opening index admission overlaps source preparation")
    struct WorkspaceOpeningAdmissionTests {
        @Test("Catalogs install while admission waits; the joined watermark precedes final cohort validation", .timeLimit(.minutes(1)))
        func catalogProgressAndFinalValidation() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let index = try TriptychSearchIndex(
                isolatedDatabaseURL: fixture.rootURL.appendingPathComponent("opening-admission.sqlite"), triptychID: fixture.assignment.id)
            let factory = OpeningAdmissionGate()
            let calls = OpeningAdmissionSignals()
            let completion = OpeningAdmissionCompletion()
            let owner = WorkspaceSearchIndexOwner(factory: {
                calls.recordCall()
                await factory.holdOnce()
                return index
            })
            var preparing: Task<(generation: UInt64, snapshots: [UUID: VaultSourceCatalogSnapshot]), Error>?
            do {
                _ = try await index.synchronizeManifest(
                    [], workspaceGeneration: 7,
                    loadChanged: { _ in throw OpeningAdmissionError.unexpectedSourceLoad }, validateManifest: {})
                let catalogs = try await catalogs(fixture, pool: pool)
                let validations = OpeningAdmissionValidations()
                for (id, catalog) in catalogs {
                    await catalog.setValidationBarrierForTesting { await validations.record(id) }
                }
                let task = Task {
                    try await prepare(fixture, catalogs: catalogs, owner: owner, completion: completion)
                }
                preparing = task
                try await waitForOpeningAdmission {
                    let factoryStarted = await factory.entered
                    let preparedOwners = await validations.ownerCount
                    return factoryStarted && preparedOwners == 3
                }
                for (id, catalog) in catalogs {
                    try await waitForOpeningAdmission { (try? await catalog.snapshot()) != nil }
                    #expect(await validations.count(id) == 1)
                }
                #expect(await completion.finished == false)
                let changedURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
                let changed = Data("\u{FEFF}# Changed during index admission\r\n\r\nExact e\u{301} 中文 😀 without final newline".utf8)
                try changed.write(to: changedURL, options: .atomic)
                await factory.release()
                let state = try await task.value
                #expect(state.generation == 8 && calls.callCount == 1)
                #expect(Set(state.snapshots.keys) == Set(catalogs.keys))
                #expect(
                    state.snapshots[fixture.analysisNoteID.vaultID]?.sourceVersions[fixture.analysisNoteID.relativePath]?.fingerprint
                        == DocumentFingerprint(data: changed))
                #expect(await validations.count(fixture.analysisNoteID.vaultID) >= 3)
                #expect(try Data(contentsOf: changedURL) == changed)
                await owner.shutdown()
                await index.shutdown()
                await pool.shutdown()
            } catch {
                await factory.release()
                preparing?.cancel()
                _ = await preparing?.result
                await owner.shutdown()
                await index.shutdown()
                await pool.shutdown()
                throw error
            }
        }

        @Test("Catalog failure cancels the shared factory before joining its suspended admission waiter", .timeLimit(.minutes(1)))
        func sourceFailureDrainsAdmission() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let databaseURL = fixture.rootURL.appendingPathComponent("opening-admission.sqlite")
            let index = try TriptychSearchIndex(isolatedDatabaseURL: databaseURL, triptychID: fixture.assignment.id)
            let factory = OpeningAdmissionGate()
            let failingCatalog = OpeningAdmissionGate()
            let completion = OpeningAdmissionCompletion()
            // Ignore cancellation until released, then return a real late index.
            // The existing owner must drain that successful factory result too.
            let owner = WorkspaceSearchIndexOwner(factory: {
                await factory.holdOnce()
                return index
            })
            var preparing: Task<(generation: UInt64, snapshots: [UUID: VaultSourceCatalogSnapshot]), Error>?
            do {
                let catalogs = try await catalogs(fixture, pool: pool)
                let failed = try #require(catalogs[fixture.analysisNoteID.vaultID])
                await failed.setValidationBarrierForTesting { await failingCatalog.holdOnce() }
                let original = try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath))
                let task = Task {
                    try await prepare(fixture, catalogs: catalogs, owner: owner, completion: completion)
                }
                preparing = task
                try await waitForOpeningAdmission {
                    let factoryStarted = await factory.entered
                    let catalogStarted = await failingCatalog.entered
                    return factoryStarted && catalogStarted
                }
                await failed.shutdown()
                await failingCatalog.release()
                try await waitForOpeningAdmission { factory.signals.isCancelled }
                #expect(await completion.finished == false)
                await factory.release()
                await #expect { _ = try await task.value } throws: { ($0 as? VaultSourceCatalogError) == .shutDown }
                #expect(await completion.finished)
                await owner.shutdown()
                await #expect(throws: SearchIndexError.self) { try await index.generation() }
                #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)) == original)
                let reopened = try TriptychSearchIndex(isolatedDatabaseURL: databaseURL, triptychID: fixture.assignment.id)
                do {
                    #expect(try await reopened.workspaceGeneration() == 0)
                    await reopened.shutdown()
                } catch {
                    await reopened.shutdown()
                    throw error
                }
                await pool.shutdown()
            } catch {
                await factory.release()
                await failingCatalog.release()
                preparing?.cancel()
                _ = await preparing?.result
                await owner.shutdown()
                await index.shutdown()
                await pool.shutdown()
                throw error
            }
        }

        @Test("Caller cancellation stops admission before suspended source children can report an error", .timeLimit(.minutes(1)))
        func callerCancellationDrainsAdmissionAndSources() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let databaseURL = fixture.rootURL.appendingPathComponent("opening-admission.sqlite")
            let index = try TriptychSearchIndex(isolatedDatabaseURL: databaseURL, triptychID: fixture.assignment.id)
            let factory = OpeningAdmissionGate()
            let sourceGates = Dictionary(uniqueKeysWithValues: fixture.assignment.vaults.values.map { ($0.id, OpeningAdmissionGate()) })
            let completion = OpeningAdmissionCompletion()
            let owner = WorkspaceSearchIndexOwner(factory: {
                // Return a real index even after cancellation; shutdown owns it.
                await factory.holdOnce()
                return index
            })
            var preparing: Task<(generation: UInt64, snapshots: [UUID: VaultSourceCatalogSnapshot]), Error>?
            do {
                let catalogs = try await catalogs(fixture, pool: pool)
                for (id, catalog) in catalogs {
                    let gate = try #require(sourceGates[id])
                    await catalog.setValidationBarrierForTesting { await gate.holdOnce() }
                }
                let sourceURLs = [
                    fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath),
                    fixture.topicsURL.appendingPathComponent("Freedom.md"),
                    fixture.worksURL.appendingPathComponent("Chapter.md"),
                ]
                let originals = try sourceURLs.map { (url: $0, bytes: try Data(contentsOf: $0)) }
                let task = Task {
                    try await prepare(fixture, catalogs: catalogs, owner: owner, completion: completion)
                }
                preparing = task
                try await waitForOpeningAdmission {
                    guard await factory.entered else { return false }
                    for gate in sourceGates.values {
                        guard await gate.entered else { return false }
                    }
                    return true
                }
                // Every child ignores cancellation while held. No child error
                // can reach the group's catch and cancel the factory for us.
                task.cancel()
                try await waitForOpeningAdmission { factory.signals.isCancelled }
                #expect(await completion.finished == false)
                await factory.release()
                // Admission can drain its late index, but source children still
                // prevent the helper from returning or releasing their owners.
                try await waitForOpeningAdmission {
                    do {
                        _ = try await index.generation()
                        return false
                    } catch { return true }
                }
                #expect(await completion.finished == false)
                for gate in sourceGates.values { await gate.release() }
                await #expect(throws: CancellationError.self) { _ = try await task.value }
                #expect(await completion.finished)
                await #expect(throws: SearchIndexError.self) { try await index.generation() }
                for source in originals { #expect(try Data(contentsOf: source.url) == source.bytes) }
                let reopened = try TriptychSearchIndex(isolatedDatabaseURL: databaseURL, triptychID: fixture.assignment.id)
                do {
                    #expect(try await reopened.workspaceGeneration() == 0)
                    await reopened.shutdown()
                } catch {
                    await reopened.shutdown()
                    throw error
                }
                await owner.shutdown()
                await pool.shutdown()
            } catch {
                await factory.release()
                for gate in sourceGates.values { await gate.release() }
                preparing?.cancel()
                _ = await preparing?.result
                await owner.shutdown()
                await index.shutdown()
                await pool.shutdown()
                throw error
            }
        }

        @Test("Progressive opening prepares only its selected vault and never resolves the index", .timeLimit(.minutes(1)))
        func progressiveKeepsAdmissionLazy() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            let calls = OpeningAdmissionSignals()
            let owner = WorkspaceSearchIndexOwner(factory: {
                calls.recordCall()
                throw OpeningAdmissionError.unexpectedAdmission
            })
            do {
                let catalogs = try await catalogs(fixture, pool: pool)
                let state = try await WorkspaceHandle.prepareInitialOpeningState(
                    assignment: fixture.assignment, catalogs: catalogs, slots: [.paperAnalysis],
                    indexOwner: owner, usesProgressiveOpening: true)
                #expect(state.generation == 1 && calls.callCount == 0)
                #expect(Set(state.snapshots.keys) == [fixture.analysisNoteID.vaultID])
                for (id, catalog) in catalogs where id != fixture.analysisNoteID.vaultID {
                    await #expect(throws: VaultSourceCatalogError.preparationRequired) { try await catalog.snapshot() }
                }
                await owner.shutdown()
                await pool.shutdown()
            } catch {
                await owner.shutdown()
                await pool.shutdown()
                throw error
            }
        }

        private func catalogs(_ fixture: ApplicationFixture, pool: WorkspaceVaultPool) async throws -> [UUID: VaultSourceCatalog] {
            var catalogs: [UUID: VaultSourceCatalog] = [:]
            for slot in WorkspaceVaultSlot.allCases {
                let vault = try #require(fixture.assignment.vault(for: slot))
                catalogs[vault.id] = try await pool.vault(for: vault).sourceCatalog
            }
            return catalogs
        }

        private func prepare(
            _ fixture: ApplicationFixture, catalogs: [UUID: VaultSourceCatalog], owner: WorkspaceSearchIndexOwner,
            completion: OpeningAdmissionCompletion
        ) async throws -> (generation: UInt64, snapshots: [UUID: VaultSourceCatalogSnapshot]) {
            do {
                let state = try await WorkspaceHandle.prepareInitialOpeningState(
                    assignment: fixture.assignment, catalogs: catalogs, slots: WorkspaceVaultSlot.allCases,
                    indexOwner: owner, usesProgressiveOpening: false)
                await completion.finish()
                return state
            } catch {
                await completion.finish()
                throw error
            }
        }
    }

    private enum OpeningAdmissionError: Error { case readinessTimeout, unexpectedSourceLoad, unexpectedAdmission }

    private func waitForOpeningAdmission(_ predicate: @Sendable () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else { throw OpeningAdmissionError.readinessTimeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private actor OpeningAdmissionCompletion {
        private(set) var finished = false
        func finish() { finished = true }
    }

    private actor OpeningAdmissionValidations {
        private var counts: [UUID: Int] = [:]
        var ownerCount: Int { counts.count }
        func record(_ id: UUID) { counts[id, default: 0] += 1 }
        func count(_ id: UUID) -> Int { counts[id] ?? 0 }
    }

    private final class OpeningAdmissionSignals: Sendable {
        private let state = Mutex((calls: 0, cancelled: false))
        var callCount: Int { state.withLock { $0.calls } }
        var isCancelled: Bool { state.withLock { $0.cancelled } }
        func recordCall() { state.withLock { $0.calls += 1 } }
        func cancel() { state.withLock { $0.cancelled = true } }
    }

    private actor OpeningAdmissionGate {
        nonisolated let signals = OpeningAdmissionSignals()
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        private(set) var entered = false
        func holdOnce() async {
            guard !entered else { return }
            entered = true
            let signals = signals
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if released { continuation.resume() } else { self.continuation = continuation }
                }
            } onCancel: {
                signals.cancel()
            }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
#endif
