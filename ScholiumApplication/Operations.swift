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

    public func create(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        let handle = try await reference.requireHandle()
        return try await handle.createDocument(id, content: content)
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
}

public actor ResearchOperations:
    ResearchRecordUseCases,
    ResearchConfigurationUseCases,
    ResearchActionUseCases,
    ResearchSourceAccessUseCases
{
    public nonisolated let recoveryRecordsURL: URL
    let reference: WorkspaceHandleReference
    private let functionCoordinator: ResearchFunctionCoordinator

    init(
        reference: WorkspaceHandleReference,
        functionCoordinator: ResearchFunctionCoordinator,
        recoveryRecordsURL: URL,
    ) {
        self.reference = reference
        self.functionCoordinator = functionCoordinator
        self.recoveryRecordsURL = recoveryRecordsURL
    }

    // Protected execution seams remain internal so owning tests can exercise
    // containment, exact revisions, recovery, and Fidelity without restoring a
    // public Function API or CLI route.
    func availableProtectedFunctions(
        for target: ResearchFunctionTarget
    ) async throws -> [ResearchFunctionAvailability] {
        let handle = try await reference.requireHandle()
        return try await functionCoordinator.researchFunctionAvailability(
            for: target,
            host: handle
        )
    }

    func protectedMaterialCandidates(
        for target: ResearchFunctionTarget,
        function: ResearchFunctionID
    ) async throws -> [ResearchFunctionMaterialCandidate] {
        let handle = try await reference.requireHandle()
        return try await functionCoordinator.researchFunctionMaterialCandidates(
            for: target,
            function: function,
            host: handle
        )
    }

    func prepareProtectedFunction(
        _ request: ResearchFunctionRequest
    ) async throws -> ResearchFunctionPreparation {
        let handle = try await reference.requireHandle()
        let preparation = try await functionCoordinator.prepareResearchFunction(
            request,
            host: handle
        )
        return try functionCoordinator.attachingAgentActions(to: preparation)
    }

    func protectedFunctionRun(id: UUID) async throws -> ResearchFunctionPreparation {
        let handle = try await reference.requireHandle()
        let preparation = try await functionCoordinator.researchFunctionRun(
            id: id,
            host: handle
        )
        return try functionCoordinator.attachingAgentActions(to: preparation)
    }

    func completeProtectedFunction(
        _ submission: ResearchFunctionCompletionSubmission
    ) async throws -> ResearchFunctionCompletion {
        let handle = try await reference.requireHandle()
        let completion = try await functionCoordinator.completeProtectedFunction(
            submission,
            host: handle
        )
        return functionCoordinator.attachingAgentActions(to: completion)
    }

    func cancelProtectedFunction(runID: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await functionCoordinator.cancelProtectedFunction(
            runID: runID,
            host: handle
        )
    }

    func finishProtectedDiscussion(runID: UUID) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await functionCoordinator.finishProtectedDiscussion(
            runID: runID,
            host: handle
        )
    }

    public func sourceAccess(
        for target: ResearchFunctionTarget
    ) async throws -> ResearchSourceAccessStatus {
        let handle = try await reference.requireHandle()
        return try await handle.researchSourceAccessStatus(for: target)
    }

    public func bindSourceAccess(
        _ request: ResearchSourceBindingRequest
    ) async throws -> ResearchSourceReference {
        let handle = try await reference.requireHandle()
        return try await handle.bindResearchSourceAccess(request)
    }

    public func removeSourceAccess(
        for target: ResearchFunctionTarget
    ) async throws {
        let handle = try await reference.requireHandle()
        try await handle.removeResearchSourceAccess(for: target)
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
        return try await handle.settle(
            note,
            expectedRevision: expectedRevision,
            rationale: rationale
        )
    }

    public func activeDiscussions(
        noteID: UUID?
    ) async throws -> [PortableResearchDiscussion] {
        let handle = try await reference.requireHandle()
        return try await handle.activeDiscussions(noteID: noteID)
    }

    public func activeDiscussion(id: UUID) async throws -> PortableResearchDiscussion {
        let handle = try await reference.requireHandle()
        return try await handle.activeDiscussion(id: id)
    }

    public func activeDiscussionIfPresent(
        id: UUID
    ) async throws -> PortableResearchDiscussion? {
        let handle = try await reference.requireHandle()
        return try await handle.activeDiscussionIfPresent(id: id)
    }

    @discardableResult
    public func createDiscussion(
        target: ResearchFunctionTarget,
        focalNotes: [ResearchFunctionMaterial],
        passage: CommentAnchor?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        let handle = try await reference.requireHandle()
        return try await handle.createDiscussion(
            target: target,
            focalNotes: focalNotes,
            passage: passage,
            researcherMessage: researcherMessage
        )
    }

    @discardableResult
    public func createComment(
        target: ResearchFunctionTarget,
        lineReference: ResearchLineReference,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        let handle = try await reference.requireHandle()
        return try await handle.createComment(
            target: target,
            lineReference: lineReference,
            researcherMessage: researcherMessage
        )
    }

    @discardableResult
    public func appendDiscussionStatement(
        discussionID: UUID,
        author: PortableResearchStatementAuthor,
        attribution: String,
        text: String,
        passage: CommentAnchor? = nil
    ) async throws -> PortableResearchDiscussion {
        let handle = try await reference.requireHandle()
        return try await handle.appendDiscussionStatement(
            discussionID: discussionID,
            author: author,
            attribution: attribution,
            text: text,
            passage: passage
        )
    }

    @discardableResult
    public func finishDiscussion(
        discussionID: UUID
    ) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await handle.finishDiscussion(discussionID: discussionID)
    }

    public func finishedResearchRecords(
        noteID: UUID?
    ) async throws -> [PortableResearchRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.finishedResearchRecords(noteID: noteID)
    }

    public func saveResearcherResponse(
        recordID: UUID,
        draft: ResearcherResponseDraft,
        expectedEvaluationRevision: UUID?,
        expectedMethodFeedbackRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await handle.saveResearcherResponse(
            recordID: recordID,
            draft: draft,
            expectedEvaluationRevision: expectedEvaluationRevision,
            expectedMethodFeedbackRevision: expectedMethodFeedbackRevision,
            expectedResultFingerprint: expectedResultFingerprint
        )
    }

    public func researchRecordChangeState(
        recordID: UUID
    ) async throws -> ResearchRecordChangeState {
        let handle = try await reference.requireHandle()
        return try await handle.researchRecordChangeState(recordID: recordID)
    }

    public func markCurrentNoteReviewed(
        noteID: UUID,
        expectedRevision: DocumentFingerprint,
        expectedRecordSourceManifestHash: String
    ) async throws -> PortableResearchNoteReview {
        let handle = try await reference.requireHandle()
        return try await handle.markCurrentNoteReviewed(
            noteID: noteID,
            expectedRevision: expectedRevision,
            expectedRecordSourceManifestHash: expectedRecordSourceManifestHash
        )
    }

    public func undoResearchRecordChanges(
        recordID: UUID,
        selectedNoteIDs: Set<UUID>,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> ResearchRecordChangesUndoResult {
        let handle = try await reference.requireHandle()
        return try await handle.undoResearchRecordChanges(
            recordID: recordID,
            selectedNoteIDs: selectedNoteIDs,
            expectedResultFingerprint: expectedResultFingerprint
        )
    }

    public func setResearchRecordRecommendationDisposition(
        recordID: UUID,
        recommendationID: UUID,
        status: ResearchLiteratureRecommendationDispositionStatus
    ) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await handle.setResearchRecordRecommendationDisposition(
            recordID: recordID,
            recommendationID: recommendationID,
            status: status
        )
    }

    public func setResearchRecordRecommendationNote(
        recordID: UUID,
        recommendationID: UUID,
        note: String?
    ) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await handle.setResearchRecordRecommendationNote(
            recordID: recordID,
            recommendationID: recommendationID,
            note: note
        )
    }

    public func deleteResearchRecordPermanently(id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.deleteResearchRecordPermanently(id: id)
    }

    public func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ExactSourceComparison {
        let handle = try await reference.requireHandle()
        return try await handle.researchRecordComparison(
            recordID: recordID,
            noteID: noteID
        )
    }

    public func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        let handle = try await reference.requireHandle()
        return try await handle.critique(workNoteID: workNoteID)
    }

    public func critique(
        critiqueRelativePath: String
    ) async throws -> CritiqueAssociation? {
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
        return try await handle.saveTriptychSettings(
            settings,
            expectedRevision: expectedRevision
        )
    }

    public func saveSettingsOutcome(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> WorkspaceMutationOutcome<TriptychSettingsSnapshot> {
        let handle = try await reference.requireHandle()
        return try await handle.saveTriptychSettingsOutcome(
            settings,
            expectedRevision: expectedRevision
        )
    }

    public func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.recoveryRecords()
    }

    public func resolveRecoveryRecord(_ id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.resolveRecoveryRecord(id)
    }

    public func availableActions(
        for target: ResearchActionNoteSnapshot
    ) async throws -> [ResearchActionAvailability] {
        let handle = try await reference.requireHandle()
        return try await handle.researchActionAvailability(for: target)
    }

    public func prepareAction(
        _ request: ResearchActionExecutionRequest
    ) async throws -> ResearchActionPreparation {
        let handle = try await reference.requireHandle()
        return try await handle.prepareResearchAction(request)
    }

    public func materialCandidates(
        for target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID
    ) async throws -> [ResearchActionNoteSnapshot] {
        let handle = try await reference.requireHandle()
        return try await handle.researchActionMaterialCandidates(
            for: target,
            actionID: actionID
        )
    }

    public func actionRun(id: UUID) async throws -> ResearchActionPreparation {
        let handle = try await reference.requireHandle()
        return try await handle.researchActionRun(id: id)
    }

    public func cancelAction(runID: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await functionCoordinator.cancelAction(runID: runID, host: handle)
    }

    public func prepareResynthesis(
        _ request: ResearchActionExecutionRequest,
        context: MaterialChangedSinceUseAttentionContext
    ) async throws -> ResearchActionPreparation {
        let handle = try await reference.requireHandle()
        return try await handle.prepareResearchResynthesis(
            request,
            context: context
        )
    }

    public func citationMethodStatus() async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.researchCitationMethodStatus()
    }

    public func activateCitationMethod(
        selection: ResearchCitationMethodSelection,
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.activateResearchCitationMethod(
            selection,
            expectedConfigurationRevision: expectedConfigurationRevision
        )
    }

    public func clearCitationMethod(
        expectedConfigurationRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.clearResearchCitationMethod(
            expectedConfigurationRevision: expectedConfigurationRevision
        )
    }

}
