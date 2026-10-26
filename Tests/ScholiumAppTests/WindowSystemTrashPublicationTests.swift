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

    enum BatchBrowseBoundary: CaseIterable, Equatable, Sendable { case committedResult, cacheRead }

    @Test(
        "Browsing another vault after batch Trash commits retains tab cleanup and pending recovery",
        arguments: BatchBrowseBoundary.allCases)
    func batchTrashBrowseRetainsCommittedCleanup(boundary: BatchBrowseBoundary) async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let gate = PublicationGate()
        let window = fixture.window
        let operations = CompletionOperations()
        operations.pendingCleanupRecovery = fixture.outcome.committedValue.pendingCleanupRecovery
        let recovery = try #require(operations.pendingCleanupRecovery)
        let recoveryURL = try #require(window.researchController.recoveryRecordsURL)
        try #require(recoveryURL.path.hasPrefix(fixture.root.path + "/"))
        // Seed only this disposable fixture's public Codable record. The
        // Application reader below validates it; delivery tests never import
        // or construct the internal Core recovery owner.
        let records = recoveryURL.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let recordURL = records.appendingPathComponent(recovery.id.uuidString.lowercased() + ".json")
        try #require(FileManager.default.createFile(atPath: recordURL.path, contents: JSONEncoder().encode(recovery), attributes: [.posixPermissions: 0o600]))
        let persisted = try await window.researchController.recoveryRecords()
        try #require(persisted.contains { $0 == recovery })
        let neighbor = try #require(window.documentTabController.tabs.first { $0.document.relativePath == "Neighbor.md" })
        window.selectDocumentTab(withID: neighbor.id)
        await window.waitForDocumentTransitions()
        await window.libraryRevealTask?.value
        try #require(window.documentController.selectedDocument?.relativePath == "Neighbor.md")
        try #require(window.documentTabController.tabs.contains { $0.document.relativePath == "Deleted.md" })
        if boundary == .committedResult {
            operations.afterTrashCommit = { await gate.hold() }
        } else {
            var didHold = false
            window.systemTrashPublicationBarrierForTesting = { reached in
                guard reached == .cacheRead, !didHold else { return }
                didHold = true
                await gate.hold()
            }
        }
        window.libraryMutationController.bind(to: operations)
        let binding = window.libraryMutationController.bindingID
        let runtime = try #require(window.windowWorkspaceController.activeCapabilities?.runtimeIdentity)
        let assignment = try #require(window.workspaceAssignment?.id)
        let batch = Task {
            defer { gate.finish() }
            return await window.libraryMutationController.executeNotesSystemTrash(fixture.preview)
        }
        do {
            await gate.waitUntilEntered()
            try #require(gate.didEnter)
            #expect(operations.committedPlans == [fixture.preview.id])
            try #require(window.libraryMutationController.bindingID == binding)
            try #require(window.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime)
            try #require(window.workspaceAssignment?.id == assignment)
            let browsed = try #require(window.workspaceAssignment?.vault(for: .paperAnalysis))
            try await window.prepareWorkspaceSelection(.paperAnalysis, sourceScope: .library)
            try #require(window.currentRegisteredVault?.id == browsed.id)
            try #require(window.discoveryController.library.workspaceSlot == .paperAnalysis)
            try #require(window.libraryMutationController.bindingID == binding)
            try #require(window.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtime)
            try #require(window.workspaceAssignment?.id == assignment)
            gate.release()
            let outcome = await batch.value

            #expect(outcome.succeededCount == fixture.preview.affectedNoteIDs.count && outcome.retryTargets.isEmpty)
            #expect(outcome.recoveryRequired)
            #expect(operations.committedPlans == [fixture.preview.id])
            #expect(window.documentTabController.tabs.map(\.document.relativePath) == ["Neighbor.md"])
            #expect(window.documentController.selectedDocument?.relativePath == "Neighbor.md")
            #expect(window.currentRegisteredVault?.id == browsed.id)
            #expect(window.discoveryController.library.workspaceSlot == .paperAnalysis)
            #expect(window.researchController.transactionRecoveryRecords.contains { $0.id == recovery.id })
            #expect(window.shellState.operationIssues.count == 1)
            #expect(window.shellState.operationIssues.first?.kind == .warning)
            #expect(!FileManager.default.fileExists(atPath: fixture.deleted.path))
            #expect(try Data(contentsOf: fixture.neighbor) == fixture.currentNeighborBytes)
            await fixture.shutdown()
        } catch {
            batch.cancel()
            gate.release()
            _ = await batch.value
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
