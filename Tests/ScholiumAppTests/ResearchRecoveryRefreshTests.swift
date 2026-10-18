import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Research recovery refresh", .serialized)
@MainActor
struct ResearchRecoveryRefreshTests {
    enum Departure: CaseIterable {
        case sameTriptychRebind, differentTriptychRebind, reset, unbind, cancellation
    }

    @Test(
        "A departed recovery request cannot republish late success or failure",
        arguments: Departure.allCases)
    func departedInterruptedRead(_ departure: Departure) async throws {
        for fails in [false, true] {
            let controller = ResearchController()
            let operations = RecoveryOperations()
            let gate = RecoveryReadGate<[InterruptedSaveRecovery]>()
            operations.interruptedLoad = { try await gate.read() }
            let triptychID = UUID()
            controller.bind(to: capabilities(operations, triptychID: triptychID))
            let pending = Task { await controller.refreshTransactionRecoveryRecords() }
            defer {
                gate.complete(.failure(CancellationError()))
                pending.cancel()
                controller.unbind()
            }
            try await gate.waitUntilReading()
            switch departure {
            case .sameTriptychRebind:
                controller.bind(to: capabilities(RecoveryOperations(), triptychID: triptychID))
            case .differentTriptychRebind:
                controller.bind(to: capabilities(RecoveryOperations(), triptychID: UUID()))
            case .reset:
                controller.reset()
            case .unbind:
                controller.unbind()
            case .cancellation:
                pending.cancel()
            }
            gate.complete(fails ? .failure(RecoveryReadFailure()) : .success([recovery("Earlier.md")]))
            await pending.value
            #expect(controller.interruptedSaveRecoveries.isEmpty)
            #expect(controller.interruptedSaveRecoveryError == nil)
        }
    }

    @Test("An older interrupted read cannot overwrite a newer refresh", arguments: [false, true])
    func newestRequestWins(earlierFails: Bool) async throws {
        let controller = ResearchController()
        let operations = RecoveryOperations()
        let gate = RecoveryReadGate<[InterruptedSaveRecovery]>()
        let current = recovery("Current.md")
        var reads = 0
        operations.interruptedLoad = {
            reads += 1
            if reads == 1 { return try await gate.read() }
            return [current]
        }
        controller.bind(to: capabilities(operations))
        let earlier = Task { await controller.refreshTransactionRecoveryRecords() }
        defer {
            gate.complete(.failure(CancellationError()))
            earlier.cancel()
            controller.unbind()
        }
        try await gate.waitUntilReading()
        await controller.refreshTransactionRecoveryRecords()
        #expect(controller.interruptedSaveRecoveries.map(\.id) == [current.id])
        gate.complete(
            earlierFails ? .failure(RecoveryReadFailure()) : .success([recovery("Earlier.md")]))
        await earlier.value
        #expect(controller.interruptedSaveRecoveries.map(\.id) == [current.id])
        #expect(controller.interruptedSaveRecoveryError == nil)
    }

    @Test("Rebinding during transaction inspection never retargets its interrupted-save read")
    func firstReadDeparture() async throws {
        let controller = ResearchController()
        let original = RecoveryOperations()
        let replacement = RecoveryOperations()
        let gate = RecoveryReadGate<[TriptychMutationRecoveryRecord]>()
        original.transactionLoad = { try await gate.read() }
        var interruptedReads = 0
        for operations in [original, replacement] {
            operations.interruptedLoad = {
                interruptedReads += 1
                return []
            }
        }
        controller.bind(to: capabilities(original))
        let pending = Task { await controller.refreshTransactionRecoveryRecords() }
        defer {
            gate.complete(.failure(CancellationError()))
            pending.cancel()
            controller.unbind()
        }
        try await gate.waitUntilReading()
        controller.bind(to: capabilities(replacement))
        gate.complete(.success([]))
        await pending.value
        #expect(interruptedReads == 0)
        #expect(controller.interruptedSaveRecoveries.isEmpty)
        #expect(controller.interruptedSaveRecoveryError == nil)
    }

    @Test(
        "Current interrupted-save success and failure remain inspectable independently of operation records"
    )
    func currentResultsAndIndependentFailures() async {
        let controller = ResearchController()
        let operations = RecoveryOperations()
        let current = recovery("Current.md")
        operations.transactionLoad = { throw RecoveryReadFailure() }
        operations.interruptedLoad = { [current] }
        controller.bind(to: capabilities(operations))
        defer { controller.unbind() }
        await controller.refreshTransactionRecoveryRecords()
        #expect(controller.transactionRecoveryError != nil)
        #expect(controller.interruptedSaveRecoveries.map(\.id) == [current.id])
        #expect(controller.interruptedSaveRecoveryError == nil)

        operations.interruptedLoad = { throw RecoveryReadFailure() }
        await controller.refreshTransactionRecoveryRecords()
        #expect(controller.interruptedSaveRecoveries.isEmpty)
        #expect(controller.interruptedSaveRecoveryError != nil)

        operations.transactionLoad = { [] }
        operations.interruptedLoad = { [current] }
        await controller.refreshTransactionRecoveryRecords()
        #expect(controller.transactionRecoveryError == nil)
        #expect(controller.interruptedSaveRecoveries.map(\.id) == [current.id])
        #expect(controller.interruptedSaveRecoveryError == nil)
    }

    @Test(
        "Departed retained-citation inspection cannot republish copies or errors",
        arguments: Departure.allCases)
    func departedRetainedCitationRead(_ departure: Departure) async throws {
        for fails in [false, true] {
            let controller = ResearchController()
            let operations = RecoveryOperations()
            let gate = RecoveryReadGate<[ZoteroCitationPairRecovery]>()
            operations.retainedCitationLoad = { try await gate.read() }
            let triptychID = UUID()
            controller.bind(to: capabilities(operations, triptychID: triptychID))
            let pending = Task {
                await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
            }
            defer {
                gate.complete(.failure(CancellationError()))
                pending.cancel()
                controller.unbind()
            }
            try await gate.waitUntilReading()
            switch departure {
            case .sameTriptychRebind:
                controller.bind(to: capabilities(RecoveryOperations(), triptychID: triptychID))
            case .differentTriptychRebind:
                controller.bind(to: capabilities(RecoveryOperations(), triptychID: UUID()))
            case .reset:
                controller.reset()
            case .unbind:
                controller.unbind()
            case .cancellation:
                pending.cancel()
            }
            gate.complete(
                fails ? .failure(RecoveryReadFailure()) : .success([citationRecovery("Earlier.md")]))
            await pending.value
            #expect(controller.retainedCitationRecoveries.isEmpty)
            #expect(controller.retainedCitationRecoveryError == nil)
            if case .cancellation = departure {
                var unexpectedReads = 0
                operations.retainedCitationLoad = {
                    unexpectedReads += 1
                    return []
                }
                await controller.refreshTransactionRecoveryRecords()
                #expect(unexpectedReads == 0)
            }
        }
    }

    @Test(
        "A background refresh carries unfinished retained-citation inspection to a visible result",
        arguments: [false, true])
    func backgroundRefreshCarriesRetainedCitationInspection(inspectionFails: Bool) async throws {
        let controller = ResearchController()
        let operations = RecoveryOperations()
        let gate = RecoveryReadGate<[ZoteroCitationPairRecovery]>()
        let current = citationRecovery("Current.md")
        var reads = 0
        operations.retainedCitationLoad = {
            reads += 1
            if reads == 1 { return try await gate.read() }
            if inspectionFails { throw RecoveryReadFailure() }
            return [current]
        }
        controller.bind(to: capabilities(operations))
        let earlier = Task {
            await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        }
        defer {
            gate.complete(.failure(CancellationError()))
            earlier.cancel()
            controller.unbind()
        }
        try await gate.waitUntilReading()
        await controller.refreshTransactionRecoveryRecords()
        #expect(reads == 2)
        #expect(controller.retainedCitationRecoveries == (inspectionFails ? [] : [current]))
        #expect((controller.retainedCitationRecoveryError != nil) == inspectionFails)

        gate.complete(.success([citationRecovery("Earlier.md")]))
        await earlier.value
        #expect(controller.retainedCitationRecoveries == (inspectionFails ? [] : [current]))
        #expect((controller.retainedCitationRecoveryError != nil) == inspectionFails)

        await controller.refreshTransactionRecoveryRecords()
        #expect(reads == 2)
    }

    @Test(
        "An older retained-citation read cannot replace newer copies or publish a stale error",
        arguments: [false, true])
    func newestRetainedCitationRequestWins(earlierFails: Bool) async throws {
        let controller = ResearchController()
        let operations = RecoveryOperations()
        let gate = RecoveryReadGate<[ZoteroCitationPairRecovery]>()
        let current = citationRecovery("Current.md")
        var reads = 0
        operations.retainedCitationLoad = {
            reads += 1
            if reads == 1 { return try await gate.read() }
            return [current]
        }
        controller.bind(to: capabilities(operations))
        let earlier = Task {
            await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        }
        defer {
            gate.complete(.failure(CancellationError()))
            earlier.cancel()
            controller.unbind()
        }
        try await gate.waitUntilReading()
        await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        #expect(controller.retainedCitationRecoveries == [current])
        gate.complete(
            earlierFails ? .failure(RecoveryReadFailure()) : .success([citationRecovery("Earlier.md")]))
        await earlier.value
        #expect(controller.retainedCitationRecoveries == [current])
        #expect(controller.retainedCitationRecoveryError == nil)
    }

    @Test("Completed citation copies remain separate from pending recovery and fail independently")
    func retainedCitationInspectionIsIndependent() async {
        let controller = ResearchController()
        let operations = RecoveryOperations()
        let retained = citationRecovery("Completed.md")
        operations.transactionLoad = { throw RecoveryReadFailure() }
        operations.interruptedLoad = { throw RecoveryReadFailure() }
        var retainedReads = 0
        operations.retainedCitationLoad = {
            retainedReads += 1
            return [retained]
        }
        controller.bind(to: capabilities(operations))
        defer { controller.unbind() }
        await controller.refreshTransactionRecoveryRecords()
        #expect(retainedReads == 0)
        #expect(controller.retainedCitationRecoveries.isEmpty)
        #expect(controller.retainedCitationRecoveryError == nil)
        await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        #expect(retainedReads == 1)
        #expect(controller.retainedCitationRecoveries == [retained])
        #expect(controller.retainedCitationRecoveryError == nil)
        #expect(controller.transactionRecoveryRecords.isEmpty)
        #expect(controller.interruptedSaveRecoveries.isEmpty)
        #expect(controller.transactionRecoveryError != nil)
        #expect(controller.interruptedSaveRecoveryError != nil)

        let pending = recovery("Interrupted.md")
        operations.transactionLoad = { [] }
        operations.interruptedLoad = { [pending] }
        operations.retainedCitationLoad = { throw RecoveryReadFailure() }
        await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        #expect(controller.retainedCitationRecoveries.isEmpty)
        #expect(controller.retainedCitationRecoveryError != nil)
        #expect(controller.transactionRecoveryError == nil)
        #expect(controller.interruptedSaveRecoveries == [pending])
        #expect(controller.interruptedSaveRecoveryError == nil)

        operations.retainedCitationLoad = { [retained] }
        await controller.refreshTransactionRecoveryRecords(includeRetainedCitationCopies: true)
        #expect(controller.retainedCitationRecoveries == [retained])
        #expect(controller.retainedCitationRecoveryError == nil)
    }

    private func capabilities(_ operations: RecoveryOperations, triptychID: UUID = UUID())
        -> ResearchControllerCapabilities
    {
        ResearchControllerCapabilities(
            triptychID: triptychID, documents: operations, research: operations,
            agentCollaboration: operations, changes: operations,
            recoveryRecordsURL: URL(fileURLWithPath: "/unused/synthetic-recovery-records"))
    }

    private func recovery(_ path: String) -> InterruptedSaveRecovery {
        InterruptedSaveRecovery(
            id: .init(vaultID: UUID(), transactionID: UUID()), relativePath: path,
            expectedRevision: .init(content: "expected"), candidateRevision: .init(content: "candidate"),
            createdAt: Date(), retainedReason: "Synthetic interruption", sourceState: .expectedRevision)
    }

    private func citationRecovery(_ path: String) -> ZoteroCitationPairRecovery {
        ZoteroCitationPairRecovery(
            triptychID: UUID(), noteID: UUID(), vaultID: UUID(), relativePath: path,
            sourceBefore: Data("before".utf8), sourceAfter: Data("after".utf8),
            companionBefore: nil, companionAfter: nil, companionRequiredBefore: false)
    }
}

private struct RecoveryReadFailure: Error {}

@MainActor
private final class RecoveryReadGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?

    func read() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilReading() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while continuation == nil {
            try #require(
                ContinuousClock.now < deadline, "The recovery request never reached its controlled read.")
            await Task.yield()
        }
    }

    func complete(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

@MainActor
private final class RecoveryOperations: DocumentUseCases, ResearchUseCases,
    AgentCollaborationUseCases, DocumentChangeUseCases
{
    var transactionLoad: @MainActor () async throws -> [TriptychMutationRecoveryRecord] = { [] }
    var interruptedLoad: @MainActor () async throws -> [InterruptedSaveRecovery] = { [] }
    var retainedCitationLoad: @MainActor () async throws -> [ZoteroCitationPairRecovery] = { [] }

    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws
        -> NoteRestructurePreview
    { throw RecoveryReadFailure() }
    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws
        -> WorkspaceMutationOutcome<NoteRestructureCommit>
    {
        throw RecoveryReadFailure()
    }
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw RecoveryReadFailure() }
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        throw RecoveryReadFailure()
    }
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
        throw RecoveryReadFailure()
    }
    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> { throw RecoveryReadFailure() }
    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview { throw RecoveryReadFailure() }
    func duplicate(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw RecoveryReadFailure() }
    func move(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw RecoveryReadFailure() }
    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview { throw RecoveryReadFailure() }
    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        throw RecoveryReadFailure()
    }
    func recoverInterruptedTransactions() async throws -> [String] { throw RecoveryReadFailure() }
    func snapshot() async throws -> [WorkspaceVaultSnapshot] { throw RecoveryReadFailure() }
    func hydrate(_ expected: WorkspaceNoteSummary) async throws -> WorkspaceNoteSnapshot {
        throw RecoveryReadFailure()
    }
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument { throw RecoveryReadFailure() }
    func exportImages(
        for note: VaultQualifiedNoteID,
        markdownSource: String
    ) async throws -> [String: RenderedMarkdownImage] { throw RecoveryReadFailure() }
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw RecoveryReadFailure() }
    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw RecoveryReadFailure() }
    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw RecoveryReadFailure() }
    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment { throw RecoveryReadFailure() }
    func unavailableIndexedImagePaths(in markdownSource: String) async throws -> [String] {
        throw RecoveryReadFailure()
    }
    func sourceAttachment(for destination: String, target: SourceAttachmentTarget) async throws
        -> DocumentAttachmentSnapshot?
    { throw RecoveryReadFailure() }
    func documentAttachments(
        for target: SourceAttachmentTarget
    ) async throws -> [DocumentAttachmentSnapshot] { throw RecoveryReadFailure() }
    func prepareDocumentAttachment(
        at sourceURL: URL,
        to target: SourceAttachmentTarget,
        management: DocumentAttachmentManagement
    ) async throws -> PreparedSourceAttachment { throw RecoveryReadFailure() }
    func prepareDocumentAttachmentPreview(
        attachmentID: UUID,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw RecoveryReadFailure() }
    func prepareSourceImagePreview(
        destination: String,
        source: String,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease { throw RecoveryReadFailure() }
    func releaseDocumentAttachmentPreview(
        accessToken: UUID
    ) async {}
    func rollbackSourceAttachment(
        _ preparation: PreparedSourceAttachment
    ) async throws { throw RecoveryReadFailure() }
    func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw RecoveryReadFailure() }
    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> { throw RecoveryReadFailure() }
    func commit(_ target: NoteMutationTarget, changeSet: NoteChangeSet) async throws -> SaveResult {
        throw RecoveryReadFailure()
    }
    func save(
        _ target: NoteMutationTarget,
        changeSet: NoteChangeSet
    ) async throws -> WorkspaceMutationOutcome<SaveResult> { throw RecoveryReadFailure() }
    func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> { throw RecoveryReadFailure() }
    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] {
        try await interruptedLoad()
    }
    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent { throw RecoveryReadFailure() }
    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL { throw RecoveryReadFailure() }
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> {
        throw RecoveryReadFailure()
    }
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> { throw RecoveryReadFailure() }
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog { throw RecoveryReadFailure() }
    func snapshot() async throws -> WorkspaceResearchSnapshot { throw RecoveryReadFailure() }
    func settings() async throws -> TriptychSettingsSnapshot { throw RecoveryReadFailure() }
    func settingsLoadState() async throws -> TriptychSettingsLoadState { throw RecoveryReadFailure() }
    func settingsRecoverySnapshot() async throws -> TriptychSettingsRecoverySnapshot {
        throw RecoveryReadFailure()
    }
    func resetSettingsToDefaults(
        expectedRevision: SettingsRevision?
    ) async throws -> TriptychSettingsRecoveryResult { throw RecoveryReadFailure() }
    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try await transactionLoad()
    }
    func retainedCitationRecoveries() async throws -> [ZoteroCitationPairRecovery] {
        try await retainedCitationLoad()
    }
    func resolveRecoveryRecord(_ id: UUID) async throws { throw RecoveryReadFailure() }
    func currentNoteSource(noteID: UUID) async throws -> AgentNoteSource {
        throw RecoveryReadFailure()
    }
    func currentNoteContext(noteID: UUID, expectedFingerprint: DocumentFingerprint) async throws
        -> AgentNoteContext
    { throw RecoveryReadFailure() }
    func createNote(_ request: ManagedNoteCreationRequest, admission: AgentMutationAdmission?)
        async throws
        -> AgentNoteCreationResult
    { throw RecoveryReadFailure() }
    func updateNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate,
        admission: AgentMutationAdmission?
    ) async throws -> AgentNoteUpdateResult { throw RecoveryReadFailure() }
    func trashNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint,
        admission: AgentMutationAdmission?
    ) async throws -> AgentNoteTrashResult { throw RecoveryReadFailure() }
    func agentChanges() async throws -> [AgentChange] { [] }
    func agentChangeReview(id: UUID) async throws -> AgentChangeReview { throw RecoveryReadFailure() }
    func undoAgentChange(
        id: UUID,
        expectedAfterFingerprint: DocumentFingerprint,
        admission: AgentMutationAdmission?
    ) async throws -> AgentChangeUndoResult { throw RecoveryReadFailure() }
    func pendingChanges() async throws -> [DocumentChangeSummary] { throw RecoveryReadFailure() }
    func changeReview(noteID: UUID) async throws -> DocumentChangeReview {
        throw RecoveryReadFailure()
    }
    func markReviewed(capture: DocumentChangeCapture) async throws -> ReviewedDocumentChange {
        throw RecoveryReadFailure()
    }
    func reviewedHistory() async throws -> [ReviewedDocumentChange] { throw RecoveryReadFailure() }
    func reviewedChange(id: UUID) async throws -> ReviewedDocumentChangeDetail {
        throw RecoveryReadFailure()
    }
    func deleteReviewedHistory(ids: [UUID]) async throws { throw RecoveryReadFailure() }
    func clearReviewedHistory() async throws { throw RecoveryReadFailure() }
    func retention() async throws -> DocumentChangeRetention { throw RecoveryReadFailure() }
    func setRetention(_ retention: DocumentChangeRetention) async throws {
        throw RecoveryReadFailure()
    }
    func historyUsage() async throws -> DocumentChangeHistoryUsage { throw RecoveryReadFailure() }
}
