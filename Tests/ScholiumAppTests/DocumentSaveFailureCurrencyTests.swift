import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Document save failure currency", .serialized)
@MainActor
struct DocumentSaveFailureCurrencyTests {
    enum ReadResult: CaseIterable, Equatable {
        case current, latestTyping, supersededSuccess, supersededFailure
    }

    @Test("Save failure reads preserve newer conflict publications", arguments: ReadResult.allCases)
    func conflictReadCurrency(_ result: ReadResult) async throws {
        let vaultID = UUID()
        let noteID = UUID()
        let original = note(vaultID: vaultID, noteID: noteID, source: "\u{FEFF}---\r\ntitle: Retained\r\n---\r\nA claim 🦉.\r\n")
        let older = note(vaultID: vaultID, noteID: noteID, source: original.document.rawContent + "Older disk revision.\r\n")
        let newer = note(vaultID: vaultID, noteID: noteID, source: original.document.rawContent + "Newer disk revision e\u{301}.\r\n")
        let draft = original.document.rawContent + "Unsaved researcher thought e\u{301}.\r\n"
        let gate = SaveFailureReadGate()
        let operations = SaveFailureReadOperations(gate: gate)
        let controller = DocumentController()
        controller.bind(to: operations)
        controller.installOpenedDocument(original, vaultName: "Analyses", vaultRole: .sourceCorpus)
        let selected = try #require(controller.selectedDocument)
        let session = controller.session(for: selected.editingTarget)
        let editor = session.editorSession
        editor.loadDocument(original.document.rawContent, documentID: editor.bridgeDocumentID, mode: .source)
        try #require(
            editor.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: EditorSourceOffsetMap(source: editor.checkedSource).editorUTF16Length,
                        insert: draft.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: draft)
                ],
                baseGeneration: 0, resultingGeneration: 1))
        session.editingSource = draft
        session.preparePresentationMode(.source)
        let failure = VaultRepositoryError.conflict(expected: original.fingerprint, current: older.fingerprint)
        session.activeSaveTask = Task { @MainActor in throw failure }
        let receipt = EditorSaveCommitReceipt()
        session.activeSaveCommitReceipt = receipt
        var commits: [NoteDocument] = []
        let pending = Task { @MainActor in
            await #expect(throws: VaultRepositoryError.self) {
                try await controller.flushForExternalOperation(
                    session: session, target: selected.editingTarget, onCommitted: { commits.append($0) })
            }
        }
        defer {
            gate.complete(.failure(CancellationError()))
            pending.cancel()
            session.cancelScheduledWork()
            controller.unbind()
        }
        do {
            try await gate.waitUntilReading()
            #expect(!session.isSavingEdit)
            #expect(operations.loadedIDs == [original.id])
            var retainedDraft = draft
            if result == .latestTyping {
                let insertion = "New checked input e\u{301}.\r\n"
                let generation = editor.generation
                let offset = EditorSourceOffsetMap(source: editor.checkedSource).editorUTF16Length
                try #require(
                    editor.acceptEditorChanges(
                        [.init(from: offset, to: offset, insert: insertion.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: insertion)],
                        baseGeneration: generation, resultingGeneration: generation + 1))
                retainedDraft += insertion
                session.editingSource = retainedDraft
            }
            var expectedConflict: DocumentConflictSnapshot?
            if result == .supersededSuccess || result == .supersededFailure {
                controller.recordCommittedSnapshot(newer, vaultName: "Analyses", vaultRole: .sourceCorpus)
                let publishedConflict = try #require(session.conflict)
                expectedConflict = publishedConflict
                #expect(publishedConflict.diskRevision == newer.fingerprint)
                #expect(Data(publishedConflict.editorSource.utf8) == Data(draft.utf8))
            }
            gate.complete(result == .supersededFailure ? .failure(UnexpectedSaveFailureProbeCall()) : .success(older.document))
            _ = await pending.value
            let conflict = try #require(session.conflict)
            if let expectedConflict {
                #expect(conflict == expectedConflict)
                #expect(conflict.diskRevision == newer.fingerprint)
                #expect(Data(conflict.diskSource.utf8) == newer.document.sourceBytes)
            } else {
                #expect(conflict.diskRevision == older.fingerprint)
                #expect(Data(conflict.diskSource.utf8) == older.document.sourceBytes)
            }
            #expect(Data(conflict.editorSource.utf8) == Data(retainedDraft.utf8))
            #expect(Data(session.retainedExactSource.utf8) == Data(retainedDraft.utf8))
            #expect(Data(session.editingSource.utf8) == Data(retainedDraft.utf8))
            #expect(session.editingRevision == original.fingerprint)
            #expect(session.hasUnsavedChanges)
            #expect(session.editError != nil)
            #expect(!session.canRetrySave)
            #expect(operations.commitCalls == 0)
            #expect(commits.isEmpty && receipt.document == nil)
            #expect(controller.selectedDocument == selected)
        } catch {
            gate.complete(.failure(CancellationError()))
            pending.cancel()
            _ = await pending.value
            throw error
        }
    }

    private func note(vaultID: UUID, noteID: UUID, source: String) -> WorkspaceNoteSnapshot {
        let document = NoteDocument(relativePath: "Retained.md", rawContent: source)
        return WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath),
            stableIdentity: .resolved(noteID), document: document,
            fileMetadata: WorkspaceFileMetadata(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
    }
}

private struct UnexpectedSaveFailureProbeCall: Error {}

@MainActor
private final class SaveFailureReadGate {
    private var continuation: CheckedContinuation<NoteDocument, Error>?
    private var resolution: Result<NoteDocument, Error>?
    private(set) var didBegin = false

    func read() async throws -> NoteDocument {
        try Task.checkCancellation()
        didBegin = true
        if let resolution { return try resolution.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilReading() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !didBegin {
            try #require(ContinuousClock.now < deadline, "The save failure never reached its controlled disk read.")
            await Task.yield()
        }
    }

    func complete(_ result: Result<NoteDocument, Error>) {
        guard resolution == nil else { return }
        resolution = result
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private final class SaveFailureReadOperations: DocumentUseCases {
    let gate: SaveFailureReadGate
    private(set) var loadedIDs: [VaultQualifiedNoteID] = []
    private(set) var commitCalls = 0

    init(gate: SaveFailureReadGate) { self.gate = gate }

    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview { throw UnexpectedSaveFailureProbeCall() }
    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws -> WorkspaceMutationOutcome<NoteRestructureCommit> {
        throw UnexpectedSaveFailureProbeCall()
    }
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw UnexpectedSaveFailureProbeCall() }
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> { throw UnexpectedSaveFailureProbeCall() }
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> { throw UnexpectedSaveFailureProbeCall() }
    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> { throw UnexpectedSaveFailureProbeCall() }
    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview { throw UnexpectedSaveFailureProbeCall() }
    func duplicate(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw UnexpectedSaveFailureProbeCall() }
    func move(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw UnexpectedSaveFailureProbeCall() }
    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview { throw UnexpectedSaveFailureProbeCall() }
    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> { throw UnexpectedSaveFailureProbeCall() }
    func recoverInterruptedTransactions() async throws -> [String] { throw UnexpectedSaveFailureProbeCall() }
    func snapshot() async throws -> [WorkspaceVaultSnapshot] { throw UnexpectedSaveFailureProbeCall() }
    func hydrate(_ expected: WorkspaceNoteSummary) async throws -> WorkspaceNoteSnapshot { throw UnexpectedSaveFailureProbeCall() }
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        loadedIDs.append(id)
        return try await gate.read()
    }
    func exportImages(
        for note: VaultQualifiedNoteID,
        markdownSource: String
    ) async throws -> [String: RenderedMarkdownImage] { throw UnexpectedSaveFailureProbeCall() }
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func unavailableIndexedImagePaths(in markdownSource: String) async throws -> [String] { throw UnexpectedSaveFailureProbeCall() }
    func sourceAttachment(for destination: String, target: SourceAttachmentTarget) async throws -> DocumentAttachmentSnapshot? {
        throw UnexpectedSaveFailureProbeCall()
    }
    func documentAttachments(
        for target: SourceAttachmentTarget
    ) async throws -> [DocumentAttachmentSnapshot] { throw UnexpectedSaveFailureProbeCall() }
    func prepareDocumentAttachment(
        at sourceURL: URL,
        to target: SourceAttachmentTarget,
        management: DocumentAttachmentManagement
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func prepareAuthoredDocumentAttachment(
        at selectedURL: URL, destination: String, for target: SourceAttachmentTarget,
        expectedSourceFingerprint: DocumentFingerprint
    ) async throws -> PreparedSourceAttachment { throw UnexpectedSaveFailureProbeCall() }
    func prepareDocumentAttachmentPreview(
        attachmentID: UUID,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw UnexpectedSaveFailureProbeCall() }
    func prepareSourceImagePreview(
        destination: String,
        source: String,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw UnexpectedSaveFailureProbeCall() }
    func releaseDocumentAttachmentPreview(
        accessToken: UUID
    ) async {}
    func rollbackSourceAttachment(
        _ preparation: PreparedSourceAttachment
    ) async throws { throw UnexpectedSaveFailureProbeCall() }
    func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw UnexpectedSaveFailureProbeCall() }
    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw UnexpectedSaveFailureProbeCall() }
    func commit(_ target: NoteMutationTarget, changeSet: NoteChangeSet) async throws -> SaveResult {
        commitCalls += 1
        throw UnexpectedSaveFailureProbeCall()
    }
    func save(
        _ target: NoteMutationTarget,
        changeSet: NoteChangeSet
    ) async throws -> WorkspaceMutationOutcome<SaveResult> { throw UnexpectedSaveFailureProbeCall() }
    func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw UnexpectedSaveFailureProbeCall() }
    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] { throw UnexpectedSaveFailureProbeCall() }
    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent { throw UnexpectedSaveFailureProbeCall() }
    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL { throw UnexpectedSaveFailureProbeCall() }
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> { throw UnexpectedSaveFailureProbeCall() }
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> { throw UnexpectedSaveFailureProbeCall() }
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog { throw UnexpectedSaveFailureProbeCall() }
}
