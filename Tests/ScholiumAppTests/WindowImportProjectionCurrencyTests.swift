import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Committed import Library projection currency", .serialized)
@MainActor
struct WindowImportProjectionCurrencyTests {
    @Test("A committed import cannot retarget a newer staged Library role")
    func newerRoleSurvivesImportProjection() async throws {
        let fixture = try await ImportProjectionFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            try await verifyNewerRole(fixture)
        } catch {
            await fixture.shutdown()
            throw error
        }
        await fixture.shutdown()
    }

    private func verifyNewerRole(_ fixture: ImportProjectionFixture) async throws {
        let window = fixture.window
        let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
        let importedVault = try #require(window.currentRegisteredVault)
        let destination = try #require(capabilities.assignment.vault(for: .topicKnowledge))
        let request = window.discoveryController.beginLibraryRequest(
            workspaceSlot: .topicKnowledge, sourceScope: .library, presentation: .stagedReplacement)
        let staged = try await window.stageRegisteredVault(destination, slot: .topicKnowledge, libraryRequest: request)
        window.requestedWorkspaceSelection = .topicKnowledge
        let importedSource = "\u{FEFF}Exact imported 中文 😀。\r\n"
        let imported = WorkspaceNoteSnapshot(
            id: .init(vaultID: importedVault.id, relativePath: "Imported.md"), vaultRole: importedVault.role,
            stableIdentity: .resolved(UUID()), document: .init(relativePath: "Imported.md", rawContent: importedSource),
            fileMetadata: .init(byteCount: importedSource.utf8.count, creationDate: nil, modificationDate: nil),
            graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
        let originalSnapshots = try await capabilities.documents.snapshot()
        let snapshots = originalSnapshots.map { vault in
            guard vault.vault.id == importedVault.id else { return vault }
            return WorkspaceVaultSnapshot(
                slot: vault.slot, vault: vault.vault, pathComparisonPolicy: vault.pathComparisonPolicy,
                documents: vault.documents + [imported.summary], folders: vault.folders, identityRecovery: vault.identityRecovery)
        }
        let reads = ImportProjectionReadOperations(snapshots: snapshots)
        window.documentController.bind(to: reads)
        let mutations = ImportProjectionMutationOperations(document: imported.document)
        window.libraryMutationController.bind(to: mutations)
        let gate = ImportProjectionStyleGate()
        let styles = fixture.store.applicationRuntime.styles
        let styleHold = Task.detached { await styles.holdImportProjectionStyle(gate) }
        var importTask: Task<WindowMarkdownImportBatchOutcome, Error>?
        var cacheObserved = false
        let observation = window.workspaceProjectionController.$state.dropFirst().sink { state in
            if state.vaultSnapshotsByID[importedVault.id]?.documents.contains(where: { $0.id.relativePath == "Imported.md" }) == true {
                cacheObserved = true
            }
        }
        defer {
            observation.cancel()
            gate.release()
            importTask?.cancel()
            window.libraryMutationController.unbind()
        }
        do {
            try await waitUntil { gate.isHolding }
            importTask = Task { try await window.libraryMutationController.importMarkdownFiles([fixture.root.appendingPathComponent("Imported.md")]) }
            try await waitUntil { cacheObserved }
            // The real callback has published its cache and reaches its next actor await
            // before this main-actor waiter can run. Commit the already staged user role.
            _ = try window.commitStagedWorkspaceLibrarySelection(staged)
            window.shellState.selectLibraryWorkspace(.topicKnowledge)
            window.requestedWorkspaceSelection = nil
            let expectedNotes = window.notes
            gate.release()
            let outcome = try await #require(importTask).value
            #expect(await styleHold.value)
            #expect(outcome.documents.map(\.relativePath) == ["Imported.md"])
            #expect(window.currentRegisteredVault?.id == destination.id)
            #expect(window.shellState.selectedWorkspace == .topicKnowledge)
            #expect(window.notes == expectedNotes)
            #expect(window.noteSourceScope == .library)
            #expect(window.workspaceProjectionController.vaultSnapshot(id: importedVault.id)?.documents.contains(where: { $0.id == imported.id }) == true)
        } catch {
            gate.release()
            importTask?.cancel()
            _ = try? await importTask?.value
            _ = await styleHold.value
            throw error
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Import projection fixture did not reach its owned boundary")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

private final class ImportProjectionStyleGate: @unchecked Sendable {
    private let lock = NSLock()
    private let permit = DispatchSemaphore(value: 0)
    private var holding = false
    var isHolding: Bool {
        lock.lock()
        defer { lock.unlock() }
        return holding
    }
    func hold() -> Bool {
        lock.lock()
        holding = true
        lock.unlock()
        return permit.wait(timeout: .now() + 5) == .success
    }
    func release() { permit.signal() }
}

private extension StyleOperations {
    // Synchronous actor-local probe holds only this disposable runtime's configuration read.
    func holdImportProjectionStyle(_ gate: ImportProjectionStyleGate) -> Bool { gate.hold() }
}

@MainActor
private struct ImportProjectionFixture {
    let root: URL
    let store: WorkspaceStore
    let window: WindowModel
    static func make() async throws -> Self {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/import-projection-currency/\(UUID())")
        var store: WorkspaceStore?
        do {
            let triptych = root.appendingPathComponent("Triptych")
            let vaults = ["Analyses", "Topics", "Works"].map { triptych.appendingPathComponent($0) }
            for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
            try Data("# Origin\r\n".utf8).write(to: vaults[0].appendingPathComponent("Origin.md"))
            try Data("# Destination\n".utf8).write(to: vaults[1].appendingPathComponent("Destination.md"))
            let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
            store = created
            let capabilities = try await created.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: triptych, triptychName: "Import projection fixture")
            let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            window.documentController.rememberPresentationMode(.read)
            try await window.openNote("Origin.md")
            await window.waitForPendingDocumentTransitionsForTesting()
            // Freeze normal queued delivery; the test's injected snapshot owns the oracle.
            window.workspaceCancellables.removeAll()
            return .init(root: root, store: created, window: window)
        } catch {
            await store?.shutdownApplicationRuntime()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    func shutdown() async {
        window.windowCloseCoordinator.finalize()
        await store.shutdownApplicationRuntime()
    }
}

private struct ImportProjectionUnexpectedCall: Error {}

@MainActor
private final class ImportProjectionMutationOperations: LibraryMutationUseCases {
    let document: NoteDocument
    init(document: NoteDocument) { self.document = document }
    func importMarkdown(at sourceURL: URL, intoVault vaultID: UUID) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        .init(committedValue: document)
    }
    func createManagedNote(_ request: ManagedNoteCreationRequest) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func createUntitledFolder(inVault vaultID: UUID, parentRelativePath: String?) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
        throw CocoaError(.featureUnsupported)
    }
    func prepareFolderSystemTrash(inVault vaultID: UUID, relativePath: String) async throws -> SystemTrashDeletionPreview {
        throw CocoaError(.featureUnsupported)
    }
    func duplicate(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        throw CocoaError(.featureUnsupported)
    }
    func move(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func moveFolder(inVault vaultID: UUID, from sourceRelativePath: String, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<
        FolderMoveCommit
    > {
        throw CocoaError(.featureUnsupported)
    }
    func prepareSystemTrash(_ target: NoteMutationTarget) async throws -> SystemTrashDeletionPreview { throw CocoaError(.featureUnsupported) }
    func moveToSystemTrash(_ preview: SystemTrashDeletionPreview) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        throw CocoaError(.featureUnsupported)
    }
    func recoverInterruptedTransactions() async throws -> [String] { [] }
}

@MainActor
private final class ImportProjectionReadOperations: DocumentUseCases {
    var snapshots: [WorkspaceVaultSnapshot]
    private(set) var loadedIDs: [VaultQualifiedNoteID] = []
    private(set) var commitCalls = 0

    init(snapshots: [WorkspaceVaultSnapshot]) { self.snapshots = snapshots }

    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview { throw ImportProjectionUnexpectedCall() }
    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws -> WorkspaceMutationOutcome<NoteRestructureCommit> {
        throw ImportProjectionUnexpectedCall()
    }
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw ImportProjectionUnexpectedCall() }
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> { throw ImportProjectionUnexpectedCall() }
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> { throw ImportProjectionUnexpectedCall() }
    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> { throw ImportProjectionUnexpectedCall() }
    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview { throw ImportProjectionUnexpectedCall() }
    func duplicate(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw ImportProjectionUnexpectedCall() }
    func move(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw ImportProjectionUnexpectedCall() }
    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview { throw ImportProjectionUnexpectedCall() }
    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> { throw ImportProjectionUnexpectedCall() }
    func recoverInterruptedTransactions() async throws -> [String] { throw ImportProjectionUnexpectedCall() }
    func snapshot() async throws -> [WorkspaceVaultSnapshot] { snapshots }
    func hydrate(_ expected: WorkspaceNoteSummary) async throws -> WorkspaceNoteSnapshot { throw ImportProjectionUnexpectedCall() }
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        loadedIDs.append(id)
        throw ImportProjectionUnexpectedCall()
    }
    func exportImages(
        for note: VaultQualifiedNoteID,
        markdownSource: String
    ) async throws -> [String: RenderedMarkdownImage] { throw ImportProjectionUnexpectedCall() }
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func unavailableIndexedImagePaths(in markdownSource: String) async throws -> [String] { throw ImportProjectionUnexpectedCall() }
    func sourceAttachment(for destination: String, target: SourceAttachmentTarget) async throws -> DocumentAttachmentSnapshot? {
        throw ImportProjectionUnexpectedCall()
    }
    func documentAttachments(
        for target: SourceAttachmentTarget
    ) async throws -> [DocumentAttachmentSnapshot] { throw ImportProjectionUnexpectedCall() }
    func prepareDocumentAttachment(
        at sourceURL: URL,
        to target: SourceAttachmentTarget,
        management: DocumentAttachmentManagement
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func prepareAuthoredDocumentAttachment(
        at selectedURL: URL, destination: String, for target: SourceAttachmentTarget,
        expectedSourceFingerprint: DocumentFingerprint
    ) async throws -> PreparedSourceAttachment { throw ImportProjectionUnexpectedCall() }
    func prepareDocumentAttachmentPreview(
        attachmentID: UUID,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw ImportProjectionUnexpectedCall() }
    func prepareSourceImagePreview(
        destination: String,
        source: String,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw ImportProjectionUnexpectedCall() }
    func releaseDocumentAttachmentPreview(
        accessToken: UUID
    ) async {}
    func rollbackSourceAttachment(
        _ preparation: PreparedSourceAttachment
    ) async throws { throw ImportProjectionUnexpectedCall() }
    func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw ImportProjectionUnexpectedCall() }
    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw ImportProjectionUnexpectedCall() }
    func commit(_ target: NoteMutationTarget, changeSet: NoteChangeSet) async throws -> SaveResult {
        commitCalls += 1
        throw ImportProjectionUnexpectedCall()
    }
    func save(
        _ target: NoteMutationTarget,
        changeSet: NoteChangeSet
    ) async throws -> WorkspaceMutationOutcome<SaveResult> { throw ImportProjectionUnexpectedCall() }
    func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw ImportProjectionUnexpectedCall() }
    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] { throw ImportProjectionUnexpectedCall() }
    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent { throw ImportProjectionUnexpectedCall() }
    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL { throw ImportProjectionUnexpectedCall() }
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> { throw ImportProjectionUnexpectedCall() }
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> { throw ImportProjectionUnexpectedCall() }
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog { throw ImportProjectionUnexpectedCall() }
}
