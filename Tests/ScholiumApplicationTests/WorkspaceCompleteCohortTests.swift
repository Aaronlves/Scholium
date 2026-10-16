import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

#if DEBUG
    @Suite("Complete workspace source-cohort admission")
    struct WorkspaceCompleteCohortTests {
        @Test("A complete refresh admits each Library once and consumes its exact installed measurement", arguments: [false, true])
        func oneAdmissionPerLibrary(changesOneNote: Bool) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
            do {
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                let initial = try await handle.snapshot()
                let original = try await handle.documents.load(fixture.analysisNoteID)
                let source =
                    changesOneNote
                    ? "\u{FEFF}# Updated cohort\r\n\r\nExact e\u{301} 中文 😀 without final newline"
                    : original.rawContent
                let sourceURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
                if changesOneNote { try Data(source.utf8).write(to: sourceURL, options: .atomic) }
                let admissions = CohortAdmissionCounts()
                let catalogs = await handle.services.sourceCatalogs
                for (vaultID, catalog) in catalogs {
                    await catalog.setValidationBarrierForTesting { await admissions.record(vaultID) }
                }
                let refreshed = try await handle.refresh(
                    publication: changesOneNote ? .sourceCommitted(fixture.analysisNoteID, .save) : .explicit,
                    sourceCatalogPreparation: changesOneNote
                        ? .delta([fixture.analysisNoteID.vaultID: .init(upserts: [fixture.analysisNoteID.relativePath])])
                        : .fullReconcile)
                for (vaultID, catalog) in catalogs {
                    #expect(await admissions.count(vaultID) == 1)
                    let consumed = try await catalog.snapshot(consumePendingMeasurement: true)
                    #expect(consumed.measurement.readFiles == 0)
                    #expect(consumed.measurement.parsedDocuments == 0)
                    await catalog.setValidationBarrierForTesting(nil)
                }
                let measurement = await handle.latestRefreshMeasurement
                #expect(measurement.readFiles == (changesOneNote ? 1 : 0))
                #expect(measurement.parsedDocuments == (changesOneNote ? 1 : 0))
                #expect(measurement.projectedDocuments == (changesOneNote ? 1 : 0))
                #expect(refreshed.phase.isComplete)
                #expect(refreshed.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: source))
                #expect(
                    refreshed.document(id: fixture.analysisNoteID)?.stableIdentity
                        == initial.document(id: fixture.analysisNoteID)?.stableIdentity)
                #expect(refreshed.discovery.catalog.graph?.sourceManifestHash == refreshed.discovery.searchGeneration?.sourceManifestHash)
                #expect(try Data(contentsOf: sourceURL) == Data(source.utf8))
                #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
        }

        @Test("Live delta and if-needed cohorts validate once without full source preparation", arguments: [false, true])
        func liveDeltaAndIfNeededAdmission(changesOneNote: Bool) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            // Use the production Handle factory in live mode with the existing
            // snapshot pool/access capabilities. Native Vault events cannot
            // race this test's independent count of one explicit admission.
            let pool = WorkspaceVaultPool(applicationSupportURL: fixture.applicationSupportURL, mode: .snapshot)
            do {
                let handle = try await WorkspaceHandle.open(
                    assignment: fixture.assignment, mode: .live,
                    applicationSupportURL: fixture.applicationSupportURL,
                    windowSessionStore: .init(applicationSupportURL: fixture.applicationSupportURL),
                    vaultPool: pool, zotero: ZoteroOperations(applicationSupportURL: fixture.applicationSupportURL),
                    access: .snapshot, openingVault: nil)
                do {
                    let initial = try await handle.snapshot()
                    #expect(handle.mode == .live)
                    #expect(initial.phase.isComplete)
                    let original = try await handle.documents.load(fixture.analysisNoteID)
                    let source =
                        changesOneNote
                        ? "\u{FEFF}# Live delta\r\n\r\nExact e\u{301} 中文 😀 without final newline"
                        : original.rawContent
                    let sourceURL = fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath)
                    if changesOneNote { try Data(source.utf8).write(to: sourceURL, options: .atomic) }
                    let admissions = CohortAdmissionCounts()
                    let catalogs = await handle.services.sourceCatalogs
                    for (vaultID, catalog) in catalogs {
                        await catalog.setValidationBarrierForTesting { await admissions.record(vaultID) }
                    }
                    // Explicit publication avoids liveInventory's no-change
                    // fast return while preserving the real preparation policy.
                    let refreshed = try await handle.refresh(
                        publication: .explicit,
                        sourceCatalogPreparation: changesOneNote
                            ? .delta([fixture.analysisNoteID.vaultID: .init(upserts: [fixture.analysisNoteID.relativePath])])
                            : SourceCatalogPreparation.none)
                    let measurement = await handle.latestRefreshMeasurement
                    #expect(measurement.enumeratedFiles == 0)
                    #expect(measurement.readFiles == (changesOneNote ? 1 : 0))
                    #expect(measurement.parsedDocuments == (changesOneNote ? 1 : 0))
                    #expect(measurement.projectedDocuments == (changesOneNote ? 1 : 0))
                    for (vaultID, catalog) in catalogs {
                        #expect(await admissions.count(vaultID) == 1)
                        await catalog.setValidationBarrierForTesting(nil)
                    }
                    #expect(refreshed.phase.isComplete)
                    #expect(refreshed.document(id: fixture.analysisNoteID)?.fingerprint == DocumentFingerprint(content: source))
                    #expect(
                        refreshed.document(id: fixture.analysisNoteID)?.stableIdentity
                            == initial.document(id: fixture.analysisNoteID)?.stableIdentity)
                    #expect(refreshed.discovery.catalog.graph?.sourceManifestHash == refreshed.discovery.searchGeneration?.sourceManifestHash)
                    #expect(try Data(contentsOf: sourceURL) == Data(source.utf8))
                    await handle.shutdown()
                } catch {
                    await handle.shutdown()
                    throw error
                }
                await pool.shutdown()
            } catch {
                await pool.shutdown()
                throw error
            }
        }

        enum Retirement: CaseIterable, Equatable, Sendable { case cancelled, rootUnavailable, shutDown }

        @Test(
            "A cancelled or retired partial cohort releases its exact admission lease",
            .timeLimit(.minutes(1)), arguments: Retirement.allCases)
        func failedCohortReleasesAdmission(_ retirement: Retirement) async throws {
            let fixture = try await makeFixture()
            defer { fixture.remove() }
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
            do {
                let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
                let initial = try await handle.snapshot()
                let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
                let catalog = try #require(await handle.services.sourceCatalogs[topicsID])
                let gate = CohortAdmissionGate()
                // Analyses installs first. Suspend the next Library's final
                // validation to exercise cleanup after a partial installation.
                await catalog.setValidationBarrierForTesting { await gate.holdOnce() }
                let generation = try await handle.services.searchIndex.workspaceGeneration()
                let refresh = Task {
                    try await handle.performRefreshCycle(
                        requestID: RefreshRequestID(rawValue: generation + 1),
                        payloads: [
                            .init(
                                publication: .explicit,
                                failureDisposition: .failed(affectedVaultIDs: []),
                                sourceCatalogPreparation: .fullReconcile)
                        ])
                }
                do {
                    try await withTaskCancellationHandler {
                        try #require(await gate.waitUntilArrived())
                        #expect(await handle.sourceOperationGate.refreshCycleIsActive)
                        switch retirement {
                        case .cancelled: refresh.cancel()
                        case .rootUnavailable: await catalog.invalidateRootAuthority()
                        case .shutDown: await catalog.shutdown()
                        }
                        await gate.release()
                        switch retirement {
                        case .cancelled:
                            await #expect(throws: CancellationError.self) { try await refresh.value }
                        case .rootUnavailable:
                            await #expect(throws: VaultSourceCatalogError.rootUnavailable) { try await refresh.value }
                        case .shutDown:
                            await #expect(throws: VaultSourceCatalogError.shutDown) { try await refresh.value }
                        }
                        #expect(!(await handle.sourceOperationGate.refreshCycleIsActive))
                        #expect(!(await handle.sourceOperationGate.sourceMutationIsActive))
                        #expect(await handle.sourceOperationGate.waitingCount == 0)
                        #expect(try await handle.snapshot().sourceInventoryRevision == initial.sourceInventoryRevision)
                        #expect(try await handle.services.searchIndex.generation() == initial.discovery.searchGeneration)
                        let available = try await handle.acquireWorkspaceSourceOperation(.sourceMutation)
                        await handle.releaseWorkspaceSourceOperation(available)
                    } onCancel: {
                        refresh.cancel()
                        Task { await gate.release() }
                    }
                    await catalog.setValidationBarrierForTesting(nil)
                    if retirement == .cancelled {
                        let recovered = try await handle.discovery.refresh()
                        #expect(recovered.phase.isComplete)
                        #expect(recovered.sourceInventoryRevision == initial.sourceInventoryRevision + 1)
                    }
                } catch {
                    refresh.cancel()
                    await gate.release()
                    _ = await refresh.result
                    await catalog.setValidationBarrierForTesting(nil)
                    throw error
                }
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
        }

        private func makeFixture() async throws -> ApplicationFixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
            return try await ApplicationFixture.make(
                rootURL: repository.appendingPathComponent(".build/complete-cohort-tests/\(UUID().uuidString)"))
        }
    }

    private actor CohortAdmissionCounts {
        private var counts: [UUID: Int] = [:]
        func record(_ vaultID: UUID) { counts[vaultID, default: 0] += 1 }
        func count(_ vaultID: UUID) -> Int { counts[vaultID, default: 0] }
    }

    private actor CohortAdmissionGate {
        private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var didArrive = false

        func holdOnce() async {
            guard !didArrive else { return }
            didArrive = true
            arrival.continuation.yield(())
            arrival.continuation.finish()
            var iterator = releaseSignal.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func waitUntilArrived() async -> Bool {
            var iterator = arrival.stream.makeAsyncIterator()
            return await iterator.next() != nil
        }

        func release() {
            releaseSignal.continuation.yield(())
            releaseSignal.continuation.finish()
            arrival.continuation.finish()
        }
    }
#endif
