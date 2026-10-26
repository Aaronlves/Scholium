import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("System-Trash publication currency", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct WindowSystemTrashPublicationTests {
    @Test(
        "A departed origin cannot publish cache, selection or warnings after suspended Trash work",
        arguments: SystemTrashPublicationBoundary.allCases, Departure.allCases)
    func departedPublicationCannotTouchCurrentWindow(boundary: SystemTrashPublicationBoundary, departure: Departure) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let gate = PublicationGate()
        let window = fixture.window
        var didHold = false
        window.systemTrashPublicationBarrierForTesting = { reached in
            guard reached == boundary, !didHold else { return }
            didHold = true
            await gate.hold()
        }
        let publication = Task {
            defer { gate.finish() }
            await window.publishSystemTrashResult(fixture.preview, outcome: fixture.outcome)
        }
        do {
            await gate.waitUntilEntered()
            try #require(gate.didEnter)
            switch departure {
            case .runtimeReplacement:
                try await fixture.replaceRuntime()
            case .finalized:
                window.windowCloseCoordinator.finalize()
            }
            let generation = window.sourceMutationGeneration
            let selection = window.documentController.selectedDocument
            let tabs = window.documentTabController.tabs.map(\.id)
            let issues = window.shellState.operationIssues.map(\.id)
            let cached = window.workspaceProjectionController.vaultSnapshot(id: fixture.vaultID)?.documents.map(\.fingerprint)
            gate.release()
            await publication.value
            #expect(window.sourceMutationGeneration == generation)
            #expect(window.documentController.selectedDocument == selection)
            #expect(window.documentTabController.tabs.map(\.id) == tabs)
            #expect(window.shellState.operationIssues.map(\.id) == issues)
            #expect(window.workspaceProjectionController.vaultSnapshot(id: fixture.vaultID)?.documents.map(\.fingerprint) == cached)
            #expect(!FileManager.default.fileExists(atPath: fixture.deleted.path))
            #expect(try Data(contentsOf: fixture.neighbor) == fixture.currentNeighborBytes)
            await fixture.shutdown()
        } catch {
            publication.cancel()
            gate.release()
            await publication.value
            await fixture.shutdown()
            throw error
        }
    }

    @Test("Current Trash publication closes only the proved removed page and reports retained cleanup")
    func currentPublicationCompletes() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        do {
            await fixture.window.publishSystemTrashResult(fixture.preview, outcome: fixture.outcome)
            #expect(fixture.window.documentController.selectedDocument?.relativePath == "Neighbor.md")
            #expect(fixture.window.documentTabController.tabs.map(\.document.relativePath) == ["Neighbor.md"])
            #expect(fixture.window.shellState.operationIssues.count == 1)
            #expect(fixture.window.shellState.operationIssues.first?.kind == .warning)
            #expect(!FileManager.default.fileExists(atPath: fixture.deleted.path))
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @Test(
        "Batch completion presents only into its current binding and originating sheet",
        arguments: BatchResultKind.allCases, BatchPresentationContext.allCases)
    func batchCompletionPreservesNewerPresentation(kind: BatchResultKind, context: BatchPresentationContext) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let window = fixture.window
        let source = fixture.preview.sources[0]
        let note = source.notes[0]
        let target = NoteMutationTarget(
            documentID: .init(vaultID: source.vaultID, relativePath: note.relativePath),
            stableNoteID: note.noteID, revision: note.expectedRevision)
        let other = NoteMutationTarget(
            documentID: .init(vaultID: source.vaultID, relativePath: "Other.md"),
            stableNoteID: UUID(), revision: note.expectedRevision)
        let targets = kind == .partial ? [target, other] : [target]
        let request = LibraryNoteBatchRequest(
            id: fixture.preview.id, assignmentID: fixture.preview.triptychID,
            vaultID: source.vaultID, targets: targets)
        let result = LibraryNoteBatchOutcome(
            request: request, operation: .systemTrash,
            items: targets.enumerated().map { index, target in
                .init(target: target, destinationRelativePath: nil, status: index == 0 ? .succeeded : .failed("Synthetic refusal"))
            }, recoveryRequired: false, warnings: kind == .warning ? ["Synthetic cleanup warning"] : [])
        window.libraryMutationController.lastBatchOutcome = result
        window.presentationRouter.present(.libraryBatchTrash(fixture.preview))
        let origin = window.presentationRouter.sheet?.id
        switch context {
        case .current: break
        case .newerRoute: window.presentationRouter.present(.transactionRecovery)
        case .departedBinding: window.libraryMutationController.bind(to: fixture.capabilities.libraryMutations)
        }
        let before = window.presentationRouter.sheet?.id
        if context == .newerRoute {
            window.presentLibraryBatchOutcome(result)
        } else {
            window.presentLibraryBatchOutcome(result, if: origin)
        }
        if context == .current {
            #expect(window.presentationRouter.sheet?.id == (kind == .clean ? nil : WindowSheetRoute.libraryNoteBatch(request).id))
        } else {
            #expect(window.presentationRouter.sheet?.id == before, "Old completion changed a newer or departed presentation")
        }
        await fixture.shutdown()
    }

    enum BatchResultKind: CaseIterable, Sendable { case clean, warning, partial }
    enum BatchPresentationContext: CaseIterable, Sendable { case current, newerRoute, departedBinding }

    enum Departure: CaseIterable, Sendable { case runtimeReplacement, finalized }

    @MainActor
    private final class Fixture {
        let root: URL
        let store: WorkspaceStore
        let window: WindowModel
        let capabilities: WindowWorkspaceCapabilities
        let preferences: ChatSidebarPreferenceFixture
        let preview: SystemTrashDeletionPreview
        let outcome: WorkspaceMutationOutcome<SystemTrashDeletionCommit>
        let deleted: URL
        let neighbor: URL
        var currentNeighborBytes = Data("Neighbor original.\n".utf8)
        var vaultID: UUID { preview.sources[0].vaultID }

        init(
            root: URL, store: WorkspaceStore, window: WindowModel, capabilities: WindowWorkspaceCapabilities,
            preferences: ChatSidebarPreferenceFixture, preview: SystemTrashDeletionPreview, deleted: URL, neighbor: URL
        ) {
            self.root = root
            self.store = store
            self.window = window
            self.capabilities = capabilities
            self.preferences = preferences
            self.preview = preview
            self.deleted = deleted
            self.neighbor = neighbor
            let plan = SystemTrashDeletionPlan(
                preview: preview,
                sourceReceipts: preview.sources.map {
                    .init(targetID: $0.id, progress: .movedToSystemTrash, resultingTrashPath: "/synthetic/Trash/Deleted.md")
                })
            let record = TriptychMutationRecoveryRecord(
                id: preview.id, triptychID: preview.triptychID,
                createdAt: Date(), failure: "Synthetic completed cleanup", files: [], systemTrashDeletionPlan: plan)
            outcome = .init(
                committedValue: .init(
                    planID: preview.id, noteIDs: Array(preview.affectedNoteIDs),
                    originalRelativePaths: ["Deleted.md"], resultingTrashPaths: [], pendingCleanupRecovery: record))
        }

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/trash-publication-currency/\(UUID())", isDirectory: true)
            let triptych = root.appendingPathComponent("Triptych", isDirectory: true)
            let roots = ["Analyses", "Topics", "Works"].map { triptych.appendingPathComponent($0, isDirectory: true) }
            let preferences = ChatSidebarPreferenceFixture(enabled: false)
            var store: WorkspaceStore?
            do {
                for directory in roots { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                let deleted = roots[1].appendingPathComponent("Deleted.md")
                let neighbor = roots[1].appendingPathComponent("Neighbor.md")
                try Data("Disposable deleted source.\n".utf8).write(to: deleted)
                try Data("Neighbor original.\n".utf8).write(to: neighbor)
                let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true))
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: roots[0], topicKnowledgeURL: roots[1],
                    outputURL: roots[2], portableContainerURL: triptych, triptychName: "Trash publication fixture")
                let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id, chatSidebarPreferences: preferences.preferences)
                await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
                try await window.openWorkspaceVault(.topicKnowledge)
                window.documentController.rememberPresentationMode(.read)
                try await window.openNote("Neighbor.md")
                try await window.openNote("Deleted.md", tabActivation: .place(.newTab))
                let note = try #require(window.currentNote?.workspaceSnapshot)
                let stableID = try #require(note.stableIdentity.resolvedID)
                let preview = SystemTrashDeletionPreview(
                    triptychID: capabilities.id,
                    sources: [
                        .init(
                            vaultID: note.id.vaultID, relativePath: note.id.relativePath, kind: .note,
                            notes: [.init(noteID: stableID, relativePath: note.id.relativePath, expectedRevision: note.fingerprint)])
                    ])
                // Only disposable source is removed, with no native Trash call.
                // Stop automatic window delivery so the publication under test owns
                // tab cleanup; Application still supplies the real fresh snapshot.
                window.workspaceCancellables.removeAll()
                try FileManager.default.removeItem(at: deleted)
                _ = try await capabilities.discovery.refresh()
                return Fixture(
                    root: root, store: created, window: window, capabilities: capabilities,
                    preferences: preferences, preview: preview, deleted: deleted, neighbor: neighbor)
            } catch {
                await store?.shutdownApplicationRuntime()
                preferences.cleanup()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func replaceRuntime() async throws {
            currentNeighborBytes = Data("New activation exact source. 中文 😀\r\n".utf8)
            try currentNeighborBytes.write(to: neighbor)
            let fresh = try await capabilities.discovery.refresh()
            let next = WindowWorkspaceCapabilities(
                id: capabilities.id,
                runtimeIdentity: .init(triptychID: capabilities.id, activationID: UUID()), assignment: capabilities.assignment,
                documents: capabilities.documents, libraryMutations: capabilities.libraryMutations,
                discovery: capabilities.discovery, research: capabilities.research, agentCollaboration: capabilities.agentCollaboration,
                changes: capabilities.changes, openingPresentationDidComplete: capabilities.openingPresentationDidComplete)
            window.adoptWorkspaceActivation(.init(kind: .replacement(previous: capabilities.runtimeIdentity), capabilities: next, snapshot: fresh))
            #expect(window.windowWorkspaceController.activeCapabilities?.runtimeIdentity == next.runtimeIdentity)
        }

        func shutdown() async {
            window.systemTrashPublicationBarrierForTesting = nil
            window.windowCloseCoordinator.finalize()
            await store.shutdownApplicationRuntime()
        }

        func remove() {
            preferences.cleanup()
            try? FileManager.default.removeItem(at: root)
        }
    }
}

@MainActor
private final class PublicationGate {
    private let arrival = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var didEnter = false
    func hold() async {
        guard !released else { return }
        await withCheckedContinuation {
            continuation = $0
            didEnter = true
            arrival.continuation.yield(())
        }
    }
    func waitUntilEntered() async { for await _ in arrival.stream { break } }
    func finish() { arrival.continuation.finish() }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
        finish()
    }
}
