import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Library note batches", .serialized)
@MainActor
struct LibraryNoteBatchTests {
    @Test("Earlier committed incoming-link rewrites advance the next selected revision")
    func exactRevisionChain() async throws {
        let request = request()
        let updated = DocumentFingerprint(data: Data("rewritten B".utf8))
        var seen: [NoteMutationTarget] = []
        let result = await LibraryNoteBatchExecution.move(
            request, toFolder: "Filed", isCurrent: { true },
            move: { target, destination in
                seen.append(target)
                if seen.count == 2 { #expect(target.revision == updated) }
                return .init(
                    committedValue: commit(
                        target, destination: destination,
                        rewrites: seen.count == 1
                            ? [
                                .init(
                                    note: request.targets[1].documentID, previousRevision: request.targets[1].revision,
                                    committedRevision: updated, rewrittenOccurrences: 1)
                            ] : []))
            }, didCommit: { _, _ in }, didFail: {})
        #expect(result.isComplete)
        #expect(seen.count == 3)
    }

    @Test("An incoming rewrite of an externally changed selected note never rebases the batch")
    func externalRevisionCannotBeAdopted() async {
        let request = request()
        var calls = 0
        let result = await LibraryNoteBatchExecution.move(
            request, toFolder: "Filed", isCurrent: { true },
            move: { target, destination in
                calls += 1
                return .init(
                    committedValue: commit(
                        target, destination: destination,
                        rewrites: [
                            .init(
                                note: request.targets[2].documentID,
                                previousRevision: DocumentFingerprint(data: Data("external".utf8)),
                                committedRevision: DocumentFingerprint(data: Data("external rewritten".utf8)), rewrittenOccurrences: 1)
                        ]))
            }, didCommit: { _, _ in }, didFail: {})
        #expect(calls == 1)
        #expect(result.items[0].status == .succeeded)
        #expect(result.items[1].status == .unattempted)
        if case .failed = result.items[2].status {} else { Issue.record("External revision must fail") }
        #expect(result.items[2].target.revision == request.targets[2].revision)
    }

    @Test("Leaving the source context after a durable commit retains success and stops remaining items")
    func cancellationAfterCommit() async {
        let request = request()
        var current = true
        let result = await LibraryNoteBatchExecution.move(
            request, toFolder: "Filed", isCurrent: { current },
            move: { target, destination in .init(committedValue: commit(target, destination: destination)) },
            didCommit: { _, _ in current = false }, didFail: {})
        #expect(result.items.map(\.status) == [.succeeded, .cancelled, .unattempted])
        #expect(result.retryTargets.count == 2)
    }

    @Test("Failure stops the batch and retains the preceding successful move")
    func stopAtFailure() async {
        let request = request()
        var calls = 0
        let result = await LibraryNoteBatchExecution.move(
            request, toFolder: "Filed", isCurrent: { true },
            move: { target, destination in
                calls += 1
                if calls == 2 { throw CocoaError(.fileWriteFileExists) }
                return .init(committedValue: commit(target, destination: destination))
            }, didCommit: { _, _ in }, didFail: {})
        #expect(calls == 2)
        #expect(result.items[0].status == .succeeded)
        #expect(result.items[2].status == .unattempted)
        #expect(result.retryTargets.map(\.stableNoteID) == Array(request.targets.dropFirst()).map(\.stableNoteID))
    }

    @Test("Trash recovery receipts distinguish moved, unknown, and never attempted sources")
    func trashReceiptOutcomes() {
        let request = request()
        let preview = SystemTrashDeletionPreview(
            triptychID: request.assignmentID,
            sources: request.targets.map {
                .init(
                    vaultID: request.vaultID, relativePath: $0.relativePath, kind: .note,
                    notes: [.init(noteID: $0.stableNoteID, relativePath: $0.relativePath, expectedRevision: $0.revision)])
            })
        let plan = SystemTrashDeletionPlan(
            preview: preview,
            sourceReceipts: [
                .init(targetID: preview.sources[0].id, progress: .movedToSystemTrash, resultingTrashPath: "/fixture/Trash/A.md"),
                .init(targetID: preview.sources[1].id, progress: .outcomeUnknown),
                .init(targetID: preview.sources[2].id, progress: .pending),
            ])
        let record = TriptychMutationRecoveryRecord(
            id: preview.id, triptychID: preview.triptychID, createdAt: Date(), failure: "fixture", files: [], systemTrashDeletionPlan: plan)
        let result = LibraryNoteBatchExecution.trashFailure(request, preview: preview, error: TriptychTransactionError.recoveryRequired(record))
        #expect(result.items[0].status == .succeeded)
        if case .outcomeUnknown = result.items[1].status {} else { Issue.record("Native uncertainty must remain explicit") }
        #expect(result.items[2].status == .unattempted)
        #expect(result.recoveryRequired)
        #expect(result.retryTargets.isEmpty)
    }

    @Test("Real moves preserve links between selected notes and do not overwrite an existing destination")
    func realMoveAndCollision() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/library-batch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        try FileManager.default.createDirectory(at: vaults[1].appendingPathComponent("Filed"), withIntermediateDirectories: true)
        let sourceFiles = ["A.md": "Alpha.\n", "B.md": "See [[A]].\n", "C.md": "Gamma.\n", "Filed/C.md": "Existing.\n"]
        for (path, text) in sourceFiles { try Data(text.utf8).write(to: vaults[1].appendingPathComponent(path)) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Batch fixture")
            let snapshot = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
            let targets = try ["A.md", "B.md", "C.md"].map { path in
                let note = try #require(snapshot.documents.first { $0.id.relativePath == path })
                return NoteMutationTarget(documentID: note.id, stableNoteID: try #require(note.stableIdentity.resolvedID), revision: note.fingerprint)
            }
            let request = LibraryNoteBatchRequest(assignmentID: capabilities.id, vaultID: snapshot.vault.id, targets: targets)
            let result = await LibraryNoteBatchExecution.move(
                request, toFolder: "Filed", isCurrent: { true },
                move: { try await capabilities.documents.move($0, to: $1) }, didCommit: { _, _ in }, didFail: {})
            #expect(result.succeededCount == 2, "\(result.items.map { ($0.target.relativePath, $0.status) }); warnings: \(result.warnings)")
            if case .failed = result.items[2].status {} else { Issue.record("Destination collision must fail") }
            #expect(!FileManager.default.fileExists(atPath: vaults[1].appendingPathComponent("A.md").path))
            #expect(!FileManager.default.fileExists(atPath: vaults[1].appendingPathComponent("B.md").path))
            #expect(try String(contentsOf: vaults[1].appendingPathComponent("Filed/C.md"), encoding: .utf8) == "Existing.\n")
            #expect(try String(contentsOf: vaults[1].appendingPathComponent("C.md"), encoding: .utf8) == "Gamma.\n")
            let movedB = try String(contentsOf: vaults[1].appendingPathComponent("Filed/B.md"), encoding: .utf8)
            #expect(movedB.contains("[[Filed/A]]"))
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    private func request() -> LibraryNoteBatchRequest {
        let vaultID = UUID()
        return .init(
            assignmentID: UUID(), vaultID: vaultID,
            targets: ["A.md", "B.md", "C.md"].map {
                .init(documentID: .init(vaultID: vaultID, relativePath: $0), stableNoteID: UUID(), revision: DocumentFingerprint(data: Data($0.utf8)))
            })
    }

    private func commit(
        _ target: NoteMutationTarget, destination: String, rewrites: [CoordinatedIncomingLinkRewriteResult] = []
    ) -> TriptychMoveCommit {
        .init(
            movedNote: target.documentID, destination: .init(vaultID: target.documentID.vaultID, relativePath: destination),
            previousRevision: target.revision, committedRevision: target.revision, graphGeneration: 1, rewrites: rewrites)
    }
}
