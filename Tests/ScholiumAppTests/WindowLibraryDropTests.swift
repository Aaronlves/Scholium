import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Window-owned Library drops")
@MainActor
struct WindowLibraryDropTests {
    @Test("A Note drop reserves its identity immediately and releases it after commit")
    func noteDropCompletion() async throws {
        let fixture = DropFixture()
        let controller = fixture.controller
        let task = try #require(controller.requestNoteDrop(fixture.note, to: "Filed/Note.md"))
        #expect(controller.pendingNoteDrops == [SidebarNoteDragItem(fixture.note).id])
        #expect(controller.hasActiveLibraryMutation)
        #expect(controller.requestNoteDrop(fixture.note, to: "Other/Note.md") == nil)
        await task.value
        #expect(fixture.operations.noteMoves == ["Filed/Note.md"])
        #expect(fixture.committedNotes == 1)
        #expect(controller.pendingNoteDrops.isEmpty)
        #expect(!controller.hasActiveLibraryMutation)
        #expect(fixture.errors.isEmpty)
    }

    @Test("Folder drop commits through the existing folder operation owner")
    func folderDropCompletion() async throws {
        let fixture = DropFixture()
        let task = try #require(fixture.controller.requestFolderDrop(fixture.folder, to: "Filed/Folder"))
        #expect(fixture.controller.pendingFolderDrops == [SidebarFolderDragItem(fixture.folder).id])
        #expect(fixture.controller.requestFolderDrop(fixture.folder, to: "Other/Folder") == nil)
        await task.value
        #expect(fixture.operations.folderMoves == ["Filed/Folder"])
        #expect(fixture.committedFolders == 1)
        #expect(fixture.controller.pendingFolderDrops.isEmpty)
        #expect(!fixture.controller.isMutatingFolder)
    }

    @Test("Drop failures retain one error and clear the pending operation", arguments: [false, true])
    func dropFailure(folder: Bool) async throws {
        let fixture = DropFixture()
        fixture.operations.shouldFail = true
        let task = try #require(folder
            ? fixture.controller.requestFolderDrop(fixture.folder, to: "Filed/Folder")
            : fixture.controller.requestNoteDrop(fixture.note, to: "Filed/Note.md"))
        await task.value
        #expect(fixture.errors.count == 1)
        #expect(fixture.errors.first?.contains(folder ? "folder" : "note") == true)
        #expect(fixture.recoveryRefreshes == 1)
        #expect(fixture.controller.pendingNoteDrops.isEmpty)
        #expect(fixture.controller.pendingFolderDrops.isEmpty)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("Late cancelled cleanup cannot clear a replacement drop for the same Note")
    func cancellationPreservesReplacement() async throws {
        let fixture = DropFixture()
        let firstGate = DropFlushGate()
        fixture.flush = { await firstGate.suspend() }
        let first = try #require(fixture.controller.requestNoteDrop(fixture.note, to: "First/Note.md"))
        await firstGate.waitUntilSuspended()
        fixture.controller.cancelAll()
        #expect(fixture.controller.pendingNoteDrops.isEmpty)

        let secondGate = DropFlushGate()
        fixture.flush = { await secondGate.suspend() }
        let second = try #require(fixture.controller.requestNoteDrop(fixture.note, to: "Second/Note.md"))
        await secondGate.waitUntilSuspended()
        firstGate.resume()
        await first.value
        #expect(fixture.controller.pendingNoteDrops == [SidebarNoteDragItem(fixture.note).id])
        #expect(fixture.controller.hasActiveLibraryMutation)
        #expect(fixture.operations.noteMoves.isEmpty)
        #expect(fixture.errors.isEmpty)

        secondGate.resume()
        await second.value
        #expect(fixture.operations.noteMoves == ["Second/Note.md"])
        #expect(fixture.controller.pendingNoteDrops.isEmpty)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }

    @Test("A changed workspace during editor flush cannot execute the old drop", arguments: [false, true])
    func changedWorkspaceStopsDrop(folder: Bool) async throws {
        let fixture = DropFixture()
        let gate = DropFlushGate()
        fixture.flush = { await gate.suspend() }
        let task = try #require(folder
            ? fixture.controller.requestFolderDrop(fixture.folder, to: "Filed/Folder")
            : fixture.controller.requestNoteDrop(fixture.note, to: "Filed/Note.md"))
        await gate.waitUntilSuspended()
        fixture.context = .init(assignmentID: UUID(), vault: fixture.vault, sourceScope: .library)
        gate.resume()
        await task.value
        #expect(fixture.operations.noteMoves.isEmpty)
        #expect(fixture.operations.folderMoves.isEmpty)
        #expect(fixture.errors.isEmpty)
        #expect(fixture.controller.pendingNoteDrops.isEmpty)
        #expect(fixture.controller.pendingFolderDrops.isEmpty)
        #expect(!fixture.controller.isMutatingFolder)
    }

    @Test("Batch execution and cross-vault targets cannot admit a single drop")
    func admissionBounds() {
        let fixture = DropFixture()
        fixture.controller.isBatchWorking = true
        #expect(fixture.controller.requestNoteDrop(fixture.note, to: "Filed/Note.md") == nil)
        #expect(fixture.controller.requestFolderDrop(fixture.folder, to: "Filed/Folder") == nil)
        fixture.controller.isBatchWorking = false
        #expect(fixture.controller.requestFolderDrop(.init(vaultID: UUID(), relativePath: "Folder"), to: "Filed/Folder") == nil)
        #expect(!fixture.controller.hasActiveLibraryMutation)
    }
}

@MainActor
private final class DropFlushGate {
    private var suspended: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation {
            suspended = $0
            arrival?.resume()
            arrival = nil
        }
    }

    func waitUntilSuspended() async {
        guard suspended == nil else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func resume() {
        suspended?.resume()
        suspended = nil
    }
}

@MainActor
private final class DropFixture {
    let vault = RegisteredVault(name: "Disposable", role: .topicKnowledge, canonicalPath: "/unused/disposable")
    let operations = DropOperations()
    var context: WindowLibraryMutationContext?
    var errors: [String] = []
    var committedNotes = 0
    var committedFolders = 0
    var recoveryRefreshes = 0
    var flush: @MainActor () async -> Void = {}

    lazy var note = NoteMutationTarget(
        documentID: .init(vaultID: vault.id, relativePath: "Note.md"),
        stableNoteID: UUID(), revision: DocumentFingerprint(content: "Exact source\n"))
    var folder: FolderMutationTarget { .init(vaultID: vault.id, relativePath: "Folder") }
    lazy var controller: WindowLibraryMutationController = {
        let controller = WindowLibraryMutationController(dependencies: .init(
            context: { [unowned self] in context },
            enqueueDocumentTransition: { _, _, _ in },
            flushEditors: { [unowned self] _ in await flush() },
            flushActiveTarget: { [unowned self] _ in await flush() },
            expectedRevision: { $0.revision }, captureBatchTargets: { $0 },
            committedNoteCreated: { _, _ in }, committedFolderCreated: { _ in },
            committedFolderMoved: { [unowned self] _ in committedFolders += 1 },
            committedNoteDuplicated: { _, _, _ in },
            committedNoteMoved: { [unowned self] _, _ in committedNotes += 1 },
            committedSystemTrash: { _, _ in }, importedDocumentsCommitted: { _ in },
            presentImportOutcome: { _ in }, presentSystemTrash: { _ in }, clearPresentedAlert: {},
            reportError: { [unowned self] in errors.append($0) }, reportInformation: { _ in },
            refreshTransactionRecovery: { [unowned self] in recoveryRefreshes += 1 }))
        controller.bind(to: operations)
        return controller
    }()

    init() { context = .init(assignmentID: UUID(), vault: vault, sourceScope: .library) }
}

@MainActor
private final class DropOperations: LibraryMutationUseCases {
    var shouldFail = false
    var noteMoves: [String] = []
    var folderMoves: [String] = []

    func move(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        noteMoves.append(destinationRelativePath)
        return .init(committedValue: .init(
            movedNote: target.documentID,
            destination: .init(vaultID: target.documentID.vaultID, relativePath: destinationRelativePath),
            previousRevision: target.revision, committedRevision: target.revision, graphGeneration: 1, rewrites: []))
    }

    func moveFolder(inVault vaultID: UUID, from sourceRelativePath: String, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        folderMoves.append(destinationRelativePath)
        return .init(committedValue: .init(
            vaultID: vaultID, sourceFolder: try .init(sourceRelativePath), destinationFolder: try .init(destinationRelativePath),
            graphGeneration: 1, noteMoves: [], rewrites: []))
    }

    func importMarkdown(at sourceURL: URL, intoVault vaultID: UUID) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw CocoaError(.featureUnsupported) }
    func createManagedNote(_ request: ManagedNoteCreationRequest) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> { throw CocoaError(.featureUnsupported) }
    func createUntitledFolder(inVault vaultID: UUID, parentRelativePath: String?) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> { throw CocoaError(.featureUnsupported) }
    func prepareFolderSystemTrash(inVault vaultID: UUID, relativePath: String) async throws -> SystemTrashDeletionPreview { throw CocoaError(.featureUnsupported) }
    func duplicate(_ target: NoteMutationTarget, to destinationRelativePath: String) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw CocoaError(.featureUnsupported) }
    func prepareSystemTrash(_ target: NoteMutationTarget) async throws -> SystemTrashDeletionPreview { throw CocoaError(.featureUnsupported) }
    func moveToSystemTrash(_ preview: SystemTrashDeletionPreview) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> { throw CocoaError(.featureUnsupported) }
    func recoverInterruptedTransactions() async throws -> [String] { [] }
}
