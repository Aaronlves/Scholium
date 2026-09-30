import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("External Markdown snapshot import")
struct MarkdownSnapshotImportTests {
    @Test("Import uses captured unsaved bytes, preserves the external file, and never replaces collisions")
    func capturedSourceAndCollision() async throws {
        try await withFixture { fixture, handle in
            let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let originalURL = fixture.rootURL.appendingPathComponent("Capture.markdown")
            let original = Data("# Original on disk\n".utf8)
            try original.write(to: originalURL)
            let occupiedURL = fixture.topicsURL.appendingPathComponent("Capture.md")
            let occupied = Data("# Existing Note\n".utf8)
            try occupied.write(to: occupiedURL)
            let captured =
                Data([0xEF, 0xBB, 0xBF])
                + Data("---\r\ncustom: 'retain this'\r\n---\r\n# Unsaved edit".utf8)

            let first = try await handle.documents.importMarkdown(
                preferredFilename: originalURL.lastPathComponent,
                sourceData: captured,
                intoVault: topicsID
            )
            let second = try await handle.documents.importMarkdown(
                preferredFilename: originalURL.lastPathComponent,
                sourceData: captured,
                intoVault: topicsID
            )

            #expect(first.committedValue.relativePath == "Capture 2.md")
            #expect(second.committedValue.relativePath == "Capture 3.md")
            #expect(first.committedValue.sourceBytes == captured)
            #expect(second.committedValue.sourceBytes == captured)
            #expect(try Data(contentsOf: originalURL) == original)
            #expect(try Data(contentsOf: occupiedURL) == occupied)
            for outcome in [first, second] {
                let document = outcome.committedValue
                #expect(try Data(contentsOf: fixture.topicsURL.appendingPathComponent(document.relativePath)) == captured)
                #expect(outcome.derivedRefreshWarning == nil)
                #expect(outcome.identityRecoveryWarning == nil)
            }
            let snapshot = try await handle.snapshot()
            let firstProjection = try #require(snapshot.document(id: .init(vaultID: topicsID, relativePath: first.committedValue.relativePath)))
            let secondProjection = try #require(snapshot.document(id: .init(vaultID: topicsID, relativePath: second.committedValue.relativePath)))
            #expect(firstProjection.fingerprint == DocumentFingerprint(data: captured))
            #expect(secondProjection.fingerprint == DocumentFingerprint(data: captured))
            let firstIdentity = try #require(firstProjection.stableIdentity.resolvedID)
            let secondIdentity = try #require(secondProjection.stableIdentity.resolvedID)
            #expect(firstIdentity != secondIdentity)
        }
    }

    @Test("Path import accepts Markdown extension and preserves original bytes without a final newline")
    func pathImportNormalizesMarkdownExtension() async throws {
        try await withFixture { fixture, handle in
            let worksID = try #require(fixture.assignment.vault(for: .output)?.id)
            let sourceURL = fixture.rootURL.appendingPathComponent("外部材料.MARKDOWN")
            let source =
                Data([0xEF, 0xBB, 0xBF])
                + Data("---\r\nunknown: [unparsed source material\r\n---\r\n# Exact source".utf8)
            try source.write(to: sourceURL)

            let imported = try await handle.documents.importMarkdown(
                at: sourceURL,
                intoVault: worksID
            ).committedValue

            #expect(imported.relativePath == "外部材料.md")
            #expect(imported.sourceBytes == source)
            #expect(try Data(contentsOf: sourceURL) == source)
            #expect(try Data(contentsOf: fixture.worksURL.appendingPathComponent(imported.relativePath)) == source)
            #expect(!FileManager.default.fileExists(atPath: fixture.worksURL.appendingPathComponent("外部材料.MARKDOWN").path))
            let published = try #require(try await handle.snapshot().document(id: .init(vaultID: worksID, relativePath: imported.relativePath)))
            #expect(published.fingerprint == imported.fingerprint)
            #expect(published.stableIdentity.resolvedID != nil)
        }
    }

    @Test("Invalid UTF-8 snapshot is rejected before creating any Note")
    func invalidUTF8IsRejected() async throws {
        try await withFixture { fixture, handle in
            let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let before = try await handle.snapshot()

            await #expect(throws: DocumentImportError.unsupportedSource("Invalid.md")) {
                _ = try await handle.documents.importMarkdown(
                    preferredFilename: "Invalid.md",
                    sourceData: Data([0xFF, 0xFE, 0x00]),
                    intoVault: topicsID
                )
            }

            #expect(!FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Invalid.md").path))
            let after = try await handle.snapshot()
            #expect(after.vaults.flatMap(\.documents).map(\.id) == before.vaults.flatMap(\.documents).map(\.id))
            #expect(try await handle.research.recoveryRecords().isEmpty)
        }
    }

    @Test("Failed import readback durably identifies its collision-selected destination")
    func uncertainReadbackHasExactRecoveryTarget() async throws {
        try await withFixture { fixture, handle in
            let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let occupiedURL = fixture.topicsURL.appendingPathComponent("Recovery.md")
            let occupied = Data("# Existing Note\n".utf8)
            try occupied.write(to: occupiedURL)
            let repositories = await handle.services.repositories
            let repository = try #require(repositories[topicsID])
            let external = Data("# Concurrently replaced imported copy\r\n".utf8)
            await repository.setImportReadbackHookForTesting { url in
                try external.write(to: url, options: .atomic)
            }
            let intended = Data([0xEF, 0xBB, 0xBF]) + Data("# Intended import\r\n".utf8)
            var recorded: TriptychMutationRecoveryRecord?
            do {
                _ = try await handle.documents.importMarkdown(
                    preferredFilename: "Recovery.markdown",
                    sourceData: intended,
                    intoVault: topicsID
                )
                Issue.record("An unverified imported copy was reported as committed.")
            } catch let error as TriptychTransactionError {
                guard case .recoveryRequired(let record) = error else {
                    Issue.record("Unexpected import recovery error: \(error)")
                    return
                }
                recorded = record
            }
            await repository.setImportReadbackHookForTesting(nil)
            let record = try #require(recorded)
            #expect(record.operation == .noteCreation)
            #expect(record.managedCreation?.target == .init(vaultID: topicsID, relativePath: "Recovery 2.md"))
            #expect(record.files.first?.intendedRevision == DocumentFingerprint(data: intended))
            #expect(record.files.first?.observedRevision == DocumentFingerprint(data: external))
            #expect(record.files.first?.state == .externallyChanged)
            #expect(try await handle.research.recoveryRecords().map(\.id) == [record.id])
            #expect(try Data(contentsOf: occupiedURL) == occupied)
            #expect(try Data(contentsOf: fixture.topicsURL.appendingPathComponent("Recovery 2.md")) == external)
            #expect(!FileManager.default.fileExists(atPath: fixture.topicsURL.appendingPathComponent("Recovery 3.md").path))
        }
    }

    @Test("An unreadable imported copy after failed identity rollback creates durable recovery")
    func uncertainIdentityRollbackHasDurableRecovery() async throws {
        try await withFixture { fixture, handle in
            let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let gate = ImportSourceGate()
            await handle.setManagedCreationPostSourceBarrierForTesting { await gate.pause() }
            let source = Data("# Intended copy\r\n".utf8)
            let importing = Task {
                try await handle.documents.importMarkdown(
                    preferredFilename: "Identity Recovery.md", sourceData: source, intoVault: topicsID
                )
            }
            do {
                try #require(await gate.waitUntilArrived())
                let foreign = try #require(
                    try await handle.services.controlStore.identity(
                        forVaultID: topicsID,
                        relativePath: "Identity Recovery.md",
                        fingerprint: DocumentFingerprint(data: source)
                    ))
                let target = fixture.topicsURL.appendingPathComponent("Identity Recovery.md")
                try FileManager.default.removeItem(at: target)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                await gate.release()
                var recorded: TriptychMutationRecoveryRecord?
                do {
                    _ = try await importing.value
                    Issue.record("An unreadable imported copy was reported as committed.")
                } catch let error as TriptychTransactionError {
                    guard case .recoveryRequired(let record) = error else {
                        Issue.record("Unexpected identity rollback recovery error: \(error)")
                        await handle.setManagedCreationPostSourceBarrierForTesting(nil)
                        return
                    }
                    recorded = record
                }
                await handle.setManagedCreationPostSourceBarrierForTesting(nil)
                let record = try #require(recorded)
                #expect(record.managedCreation?.target == .init(vaultID: topicsID, relativePath: "Identity Recovery.md"))
                #expect(record.managedCreation?.reservedIdentityID != foreign.id)
                #expect(record.files.first?.state == .unreadable)
                #expect(record.files.first?.intendedRevision == DocumentFingerprint(data: source))
                #expect(try await handle.research.recoveryRecords().map(\.id) == [record.id])
                #expect(try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
            } catch {
                await gate.release()
                _ = try? await importing.value
                await handle.setManagedCreationPostSourceBarrierForTesting(nil)
                throw error
            }
        }
    }

    private func withFixture(
        _ operation: @Sendable (ApplicationFixture, WorkspaceHandle) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/MarkdownSnapshotImportTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await ApplicationFixture.make(rootURL: root)
        let runtime = WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    assignments: [fixture.assignment]
                )))
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            try await operation(fixture, handle)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private actor ImportSourceGate {
        private var arrived = false
        private var paused: CheckedContinuation<Void, Never>?
        private var arrival: CheckedContinuation<Bool, Never>?

        func pause() async {
            arrived = true
            arrival?.resume(returning: true)
            arrival = nil
            await withCheckedContinuation { paused = $0 }
        }

        func waitUntilArrived() async -> Bool {
            if arrived { return true }
            let timeout = Task {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                timeoutArrival()
            }
            defer { timeout.cancel() }
            return await withCheckedContinuation { arrival = $0 }
        }

        private func timeoutArrival() {
            arrival?.resume(returning: false)
            arrival = nil
        }

        func release() {
            paused?.resume()
            paused = nil
        }
    }
}
