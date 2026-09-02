import ScholiumContracts
import Foundation
import ScholiumCore

actor WorkspaceHandleReference {
    private let workspaceID: UUID
    private weak var handle: WorkspaceHandle?

    init(workspaceID: UUID) {
        self.workspaceID = workspaceID
    }

    func bind(_ handle: WorkspaceHandle) {
        self.handle = handle
    }

    func requireHandle() throws -> WorkspaceHandle {
        guard let handle else {
            throw ScholiumApplicationError.workspaceShutDown(workspaceID)
        }
        return handle
    }
}

public actor DocumentOperations: DocumentUseCases {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func snapshot() async throws -> [WorkspaceVaultSnapshot] {
        let handle = try await reference.requireHandle()
        return try await handle.snapshot().vaults
    }

    public func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.loadDocument(id)
    }

    public func metadata(
        _ id: VaultQualifiedNoteID
    ) async throws -> NoteMetadataSnapshot? {
        let handle = try await reference.requireHandle()
        return try await handle.noteMetadata(id)
    }

    public func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog {
        let handle = try await reference.requireHandle()
        return try await handle.documentPreviewCatalog(
            source: source,
            sourceFingerprint: sourceFingerprint,
            graphGeneration: graphGeneration
        )
    }

    public func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let handle = try await reference.requireHandle()
        return try await handle.importMarkdown(
            at: sourceURL,
            intoVault: vaultID
        )
    }

    public func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        let handle = try await reference.requireHandle()
        return try await handle.importImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    public func rollbackImageAttachment(
        _ preparation: PreparedImageAttachment
    ) async throws {
        let handle = try await reference.requireHandle()
        try await handle.rollbackImageAttachment(preparation)
    }

    public func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        let handle = try await reference.requireHandle()
        return try await handle.indexImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    public func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        let handle = try await reference.requireHandle()
        return try await handle.importPastedImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    public func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        let handle = try await reference.requireHandle()
        return try await handle.importPastedImageAttachment(
            data: data,
            preferredFilename: preferredFilename,
            for: note
        )
    }

    public func unavailableIndexedImagePaths(
        in markdownSource: String
    ) async throws -> [String] {
        let handle = try await reference.requireHandle()
        return try await handle.unavailableIndexedImagePaths(
            in: markdownSource
        )
    }

    public func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let handle = try await reference.requireHandle()
        return try await handle.importMarkdownSource(source, at: id)
    }

    public func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.createManagedNote(request)
    }

    public func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
        let handle = try await reference.requireHandle()
        return try await handle.createUntitledFolder(
            inVault: vaultID,
            parentRelativePath: parentRelativePath
        )
    }

    public func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.moveFolder(
            inVault: vaultID,
            from: sourceRelativePath,
            to: destinationRelativePath
        )
    }

    public func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview {
        let handle = try await reference.requireHandle()
        return try await handle.prepareFolderSystemTrash(
            inVault: vaultID,
            relativePath: relativePath
        )
    }

    public func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let handle = try await reference.requireHandle()
        return try await handle.duplicateDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    public func duplicate(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let handle = try await reference.requireHandle()
        return try await handle.duplicateDocument(
            target,
            to: destinationRelativePath
        )
    }

    /// Commits exact source without waiting for disposable workspace
    /// projections. This is the editor autosave completion boundary.
    public func commit(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        let handle = try await reference.requireHandle()
        return try await handle.commitDocument(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
    }

    /// Delegates exact-byte revision checking and waits for the matching
    /// derived generation required by same-generation workflow consumers.
    public func save(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<SaveResult> {
        let handle = try await reference.requireHandle()
        return try await handle.saveDocument(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
    }

    public func saveMetadata(
        _ id: VaultQualifiedNoteID,
        fields: [String: YAMLValue],
        expectedRevision: DocumentFingerprint?
    ) async throws -> WorkspaceMutationOutcome<NoteMetadataSnapshot> {
        let handle = try await reference.requireHandle()
        return try await handle.saveNoteMetadata(
            id,
            fields: fields,
            expectedRevision: expectedRevision
        )
    }

    public func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.moveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    public func move(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.moveDocument(
            target,
            to: destinationRelativePath
        )
    }

    public func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview {
        let handle = try await reference.requireHandle()
        return try await handle.prepareSystemTrash(target)
    }

    public func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.moveToSystemTrash(preview)
    }

    public func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] {
        let handle = try await reference.requireHandle()
        return try await handle.interruptedSaveRecoveries()
    }

    public func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        let handle = try await reference.requireHandle()
        return try await handle.interruptedSaveRecoveryContent(recovery)
    }

    public func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL {
        let handle = try await reference.requireHandle()
        return try await handle.prepareInterruptedSaveRecoveryLocation(recovery)
    }

    public func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> {
        let handle = try await reference.requireHandle()
        return try await handle.restoreInterruptedSaveRecovery(recovery)
    }

    /// Completes or reports durable lifecycle work left by an interrupted
    /// prior process. Each vault is attempted independently so one damaged
    /// recovery record does not prevent inspection of the others.
    public func recoverInterruptedTransactions() async throws -> [String] {
        let handle = try await reference.requireHandle()
        return await handle.recoverInterruptedDocumentTransactions()
    }

    @discardableResult
    public func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> {
        let handle = try await reference.requireHandle()
        return try await handle.resolveIdentity(ambiguity, candidateID: candidateID)
    }

}

public actor DiscoveryOperations: DiscoveryUseCases {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func snapshot() async throws -> WorkspaceDiscoverySnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.snapshot().discovery
    }

    /// Re-reads the fixed assignment's current source bytes and republishes a
    /// complete generation. It never changes snapshot-mode membership.
    @discardableResult
    public func refresh() async throws -> WorkspaceSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.refresh()
    }

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        let handle = try await reference.requireHandle()
        return try await handle.search(request)
    }

    public func unifiedSearch(
        _ request: UnifiedSearchRequest
    ) async throws -> UnifiedSearchResponse {
        let handle = try await reference.requireHandle()
        return try await handle.unifiedSearch(request)
    }

    public func links(
        for note: VaultQualifiedNoteID,
        direction: WorkspaceLinkDirection
    ) async throws -> [LinkGraphEdge] {
        try await graphQueries().links(for: note, direction: direction)
    }

    public func linkDiagnostics() async throws -> [LinkGraphDiagnostic] {
        try await graphQueries().diagnostics()
    }

    private func graphQueries() async throws -> WorkspaceGraphQueries {
        let handle = try await reference.requireHandle()
        return WorkspaceGraphQueries(catalog: try await handle.snapshot().discovery.catalog)
    }
}


/// Researcher-owned judgments and recovery operations that remain inside the
/// App after external conversation and workflow ownership moved to the host.
public actor ResearchOperations: ResearchUseCases {
    public nonisolated let recoveryRecordsURL: URL
    let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference, recoveryRecordsURL: URL) {
        self.reference = reference
        self.recoveryRecordsURL = recoveryRecordsURL
    }

    public func snapshot() async throws -> WorkspaceResearchSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.researchSnapshot()
    }

    @discardableResult
    public func settle(
        _ note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        let handle = try await reference.requireHandle()
        return try await handle.settle(note, expectedRevision: expectedRevision, rationale: rationale)
    }

    public func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        let handle = try await reference.requireHandle()
        return try await handle.critique(workNoteID: workNoteID)
    }

    public func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation? {
        let handle = try await reference.requireHandle()
        return try await handle.critique(critiqueRelativePath: critiqueRelativePath)
    }

    public func setCritiqueFindingDisposition(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String?,
        noTextChangeRationale: String?,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let handle = try await reference.requireHandle()
        return try await handle.setCritiqueFindingDisposition(
            workNote: workNote,
            roundID: roundID,
            findingID: findingID,
            decision: decision,
            rationale: rationale,
            noTextChangeRationale: noTextChangeRationale,
            expectedRevision: expectedRevision
        )
    }

    public func completeCritiqueRound(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        let handle = try await reference.requireHandle()
        return try await handle.completeCritiqueRound(
            workNote: workNote,
            roundID: roundID,
            expectedRevision: expectedRevision
        )
    }

    public func settings() async throws -> TriptychSettingsSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.triptychSettings()
    }

    public func settingsLoadState() async throws -> TriptychSettingsLoadState {
        let handle = try await reference.requireHandle()
        return try await handle.triptychSettingsLoadState()
    }

    public func saveSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveTriptychSettings(settings, expectedRevision: expectedRevision)
    }

    public func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.recoveryRecords()
    }

    public func resolveRecoveryRecord(_ id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.resolveRecoveryRecord(id)
    }
}
