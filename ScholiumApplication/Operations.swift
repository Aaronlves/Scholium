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
    ) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.importMarkdown(
            at: sourceURL,
            intoVault: vaultID
        )
    }

    public func create(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.createDocument(id, content: content)
    }

    public func create(_ request: DocumentCreationRequest) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.createDocument(request)
    }

    public func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.createUntitledNote(
            inVault: vaultID,
            folderRelativePath: folderRelativePath
        )
    }

    public func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> VaultRelativeFolderPath {
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
    ) async throws -> FolderMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.moveFolder(
            inVault: vaultID,
            from: sourceRelativePath,
            to: destinationRelativePath
        )
    }

    public func moveFolderToTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> FolderMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.moveFolderToTrash(
            inVault: vaultID,
            relativePath: relativePath
        )
    }

    public func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.duplicateDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
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
    ) async throws -> SaveResult {
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
    ) async throws -> TriptychMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.moveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    public func setAside(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.setAsideDocument(
            id,
            expectedRevision: expectedRevision
        )
    }

    public func moveToTrash(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.moveDocumentToTrash(
            id,
            expectedRevision: expectedRevision
        )
    }

    public func putBack(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let handle = try await reference.requireHandle()
        return try await handle.putBackDocument(
            id,
            expectedRevision: expectedRevision
        )
    }

    public func deletePermanently(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> PermanentDeletionCommit {
        let handle = try await reference.requireHandle()
        return try await handle.deleteDocumentPermanently(
            id,
            expectedRevision: expectedRevision
        )
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
    ) async throws -> NoteIdentityRecord {
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

    public func related(
        query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding: Set<VaultQualifiedNoteID> = [],
        limit: Int = 12
    ) async throws -> RelatedSearchResponse {
        let handle = try await reference.requireHandle()
        return try await handle.related(
            query: query,
            scope: scope,
            searchGeneration: searchGeneration,
            excluding: excluding,
            limit: limit
        )
    }
}

public actor ResearchOperations: ResearchUseCases {
    public nonisolated let skillsURL: URL
    public nonisolated let recoveryRecordsURL: URL
    let reference: WorkspaceHandleReference
    private let functionCoordinator: ResearchFunctionCoordinator
    private let bibliographyCoordinator: RecommendedBibliographyCoordinator

    init(
        reference: WorkspaceHandleReference,
        functionCoordinator: ResearchFunctionCoordinator,
        skillsURL: URL,
        recoveryRecordsURL: URL,
    ) {
        self.reference = reference
        self.functionCoordinator = functionCoordinator
        bibliographyCoordinator = RecommendedBibliographyCoordinator(reference: reference)
        self.skillsURL = skillsURL
        self.recoveryRecordsURL = recoveryRecordsURL
    }

    public nonisolated static func inspectSkillDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin
    ) -> ResearchSkillPackage {
        ResearchSkillTransactionCoordinator.inspectDraft(id: id, source: source, origin: origin)
    }

    public func inspectSkillDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin
    ) async -> ResearchSkillPackage {
        let inspected = Self.inspectSkillDraft(id: id, source: source, origin: origin)
        guard origin == .triptych,
              let handle = try? await reference.requireHandle(),
              let persistedSkills = try? await handle.services.researchSkillStore.skills(),
              let persisted = persistedSkills.first(where: {
                  $0.id == id && $0.origin == origin
              }) else {
            return inspected
        }
        let packageBoundaryIssues = persisted.validationIssues.filter { issue in
            issue.contains("protected Scholium package")
                && !inspected.validationIssues.contains(issue)
        }
        return inspected.addingValidationIssues(packageBoundaryIssues)
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

    func prepareProtectedAutomaticFidelity(
        parentRunID: UUID
    ) async throws -> AutomaticFidelityPreparation {
        let handle = try await reference.requireHandle()
        let preparation = try await functionCoordinator.prepareAutomaticFidelity(
            parentRunID: parentRunID,
            host: handle
        )
        return try await functionCoordinator.attachingAgentActions(
            to: preparation,
            host: handle
        )
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

    public func recommendations() async throws -> RecommendedBibliographyProjection? {
        try await bibliographyCoordinator.recommendations()
    }

    public func recommendationOverview() async throws -> RecommendedBibliographyOverview {
        try await bibliographyCoordinator.overview()
    }

    public func prepareRecommendation(
        _ request: RecommendedBibliographyRequest
    ) async throws -> RecommendedBibliographyPreparation {
        try await bibliographyCoordinator.prepare(request)
    }

    public func recommendationRequest(
        id: UUID
    ) async throws -> RecommendedBibliographyPreparation {
        try await bibliographyCoordinator.request(id: id)
    }

    public func completeRecommendation(
        _ submission: RecommendedBibliographyCompletionSubmission
    ) async throws -> RecommendedBibliographyProjection {
        try await bibliographyCoordinator.complete(submission)
    }

    public func cancelRecommendation(id: UUID) async throws {
        try await bibliographyCoordinator.cancel(id: id)
    }

    public func dismissRecommendation(requestID: UUID, candidateID: UUID) async throws {
        try await bibliographyCoordinator.dismiss(
            requestID: requestID,
            candidateID: candidateID
        )
    }

    public func bibliographyMethodStatus() async throws -> RecommendedBibliographyMethodStatus {
        try await bibliographyCoordinator.methodStatus()
    }

    public func setBibliographyMethod(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> RecommendedBibliographyMethodStatus {
        try await bibliographyCoordinator.setMethod(
            packageID: packageID,
            expectedBindingRevision: expectedBindingRevision
        )
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

    public func recoveryPolicy() async throws -> ResearchRecoveryPolicySnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.recoveryPolicy()
    }

    public func prepareRecoveryPolicyChange(
        _ retention: SettledSnapshotRetention,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchRecoveryPolicyChangePreview {
        let handle = try await reference.requireHandle()
        return try await handle.prepareRecoveryPolicyChange(
            retention,
            expectedRevision: expectedRevision
        )
    }

    public func applyRecoveryPolicyChange(
        _ preview: ResearchRecoveryPolicyChangePreview
    ) async throws -> ResearchRecoveryPolicyApplyOutcome {
        let handle = try await reference.requireHandle()
        return try await handle.applyRecoveryPolicyChange(preview)
    }

    public func settledSnapshots(
        noteID: UUID?
    ) async throws -> [SettledRevisionSnapshot] {
        let handle = try await reference.requireHandle()
        return try await handle.settledSnapshots(noteID: noteID)
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

    public func setResearchRecordPinned(
        id: UUID,
        isPinned: Bool
    ) async throws -> PortableResearchRecord {
        let handle = try await reference.requireHandle()
        return try await handle.setResearchRecordPinned(id: id, isPinned: isPinned)
    }

    public func deleteResearchRecordPermanently(id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.deleteResearchRecordPermanently(id: id)
    }

    public func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ResearchRecordComparison {
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

    @discardableResult
    public func createCheckpoint(
        name: String,
        kind: TriptychCheckpointKind = .manual
    ) async throws -> TriptychCheckpoint {
        let handle = try await reference.requireHandle()
        return try await handle.createCheckpoint(name: name, kind: kind)
    }

    public func prepareCheckpointsLocation() async throws -> URL {
        let handle = try await reference.requireHandle()
        return try await handle.prepareCheckpointsLocation()
    }

    public func checkpoints() async throws -> TriptychCheckpointListing {
        let handle = try await reference.requireHandle()
        return try await handle.checkpoints()
    }

    public func noteCheckpoints(
        for note: VaultQualifiedNoteID
    ) async throws -> [TriptychCheckpoint] {
        let handle = try await reference.requireHandle()
        return try await handle.noteCheckpoints(for: note)
    }

    public func checkpointNoteContent(
        _ checkpointID: UUID,
        note: VaultQualifiedNoteID
    ) async throws -> String {
        let handle = try await reference.requireHandle()
        return try await handle.checkpointNoteContent(checkpointID, note: note)
    }

    public func checkpointComparison(
        _ checkpointID: UUID
    ) async throws -> [TriptychCheckpointChange] {
        let handle = try await reference.requireHandle()
        return try await handle.checkpointComparison(checkpointID)
    }

    @discardableResult
    public func restoreNote(
        _ note: VaultQualifiedNoteID,
        from checkpointID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychCheckpointRestoreResult {
        let handle = try await reference.requireHandle()
        return try await handle.restoreNote(
            note,
            from: checkpointID,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    public func restoreCheckpoint(
        _ checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection
    ) async throws -> TriptychCheckpointRestoreResult {
        let handle = try await reference.requireHandle()
        return try await handle.restoreCheckpoint(checkpointID, selection: selection)
    }

    public func settings() async throws -> TriptychSettings {
        let handle = try await reference.requireHandle()
        return try await handle.triptychSettings()
    }

    public func saveSettings(_ settings: TriptychSettings) async throws {
        let handle = try await reference.requireHandle()
        try await handle.saveTriptychSettings(settings)
    }

    public func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.recoveryRecords()
    }

    public func resolveRecoveryRecord(_ id: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.resolveRecoveryRecord(id)
    }

    public func skills() async throws -> [ResearchSkillPackage] {
        let handle = try await reference.requireHandle()
        return try await handle.skills()
    }

    public func skillCatalog() async throws -> ResearchSkillCatalog {
        let handle = try await reference.requireHandle()
        return try await handle.skillCatalog()
    }

    public func skillPackage(id: String) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.skillPackage(id: id)
    }

    public func createSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.createSkill(id: id, source: source)
    }

    public func duplicateBundledSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.duplicateBundledSkill(id: id, as: newID)
    }

    public func saveSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.saveSkill(
            id: id,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    public func renameSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.renameSkill(
            id: id,
            to: newID,
            expectedRevision: expectedRevision
        )
    }

    public func deleteSkill(
        id: String,
        expectedRevision: DocumentFingerprint
    ) async throws {
        let handle = try await reference.requireHandle()
        try await handle.deleteSkill(id: id, expectedRevision: expectedRevision)
    }

    public func skillResourcePaths(id: String) async throws -> [String] {
        let handle = try await reference.requireHandle()
        return try await handle.skillResourcePaths(id: id)
    }

    public func skillResource(id: String, relativePath: String) async throws -> String {
        let handle = try await reference.requireHandle()
        return try await handle.skillResource(id: id, relativePath: relativePath)
    }

    public func skillInstructionAssembly(
        mode: ResearchSkillMode = .discuss,
        requestedSkillIDs: [String] = [],
        mixedPhases: [ResearchSkillAssemblyPhase] = []
    ) async throws -> String {
        let handle = try await reference.requireHandle()
        return try await handle.skillInstructionAssembly(
            mode: mode,
            requestedSkillIDs: requestedSkillIDs,
            mixedPhases: mixedPhases
        )
    }

    public func resolveWorkflow(
        _ contract: ResearchWorkflowContract
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        let handle = try await reference.requireHandle()
        return try await handle.resolveWorkflow(contract)
    }

    public func workingMethodBindings()
        async throws -> ResearchWorkingMethodBindingSnapshot?
    {
        let handle = try await reference.requireHandle()
        return try await handle.workingMethodBindings()
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

    public func prepareActionFidelity(
        parentRunID: UUID
    ) async throws -> ResearchActionFidelityPreparation {
        let handle = try await reference.requireHandle()
        return try await handle.prepareResearchActionFidelity(parentRunID: parentRunID)
    }

    public func completeAction(
        _ submission: ResearchActionCompletionSubmission
    ) async throws -> ResearchActionCompletion {
        let handle = try await reference.requireHandle()
        return try await handle.completeResearchAction(submission)
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

    public func actionProfiles() async throws -> ResearchActionProfileSnapshot? {
        let handle = try await reference.requireHandle()
        return try await handle.actionProfiles()
    }

    public func saveActionProfile(
        _ binding: ResearchActionProfileBinding,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveActionProfile(
            binding,
            expectedDocumentRevision: expectedDocumentRevision
        )
    }

    public func removeActionProfile(
        actionID: ResearchActionID,
        expectedDocumentRevision: DocumentFingerprint
    ) async throws -> ResearchActionProfileSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.removeActionProfile(
            actionID: actionID,
            expectedDocumentRevision: expectedDocumentRevision
        )
    }

    public func saveActionProfileDocument(
        _ document: ResearchActionProfileDocument,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveActionProfileDocument(
            document,
            expectedDocumentRevision: expectedDocumentRevision
        )
    }

    public func installDefaultWorkingMethods()
        async throws -> ResearchWorkingMethodBindingSnapshot
    {
        let handle = try await reference.requireHandle()
        return try await handle.installDefaultWorkingMethods()
    }

    public func saveWorkingMethod(
        for actionID: ResearchActionID,
        source: String,
        expectedPackageRevision: DocumentFingerprint,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        let handle = try await reference.requireHandle()
        return try await handle.saveWorkingMethod(
            for: actionID,
            source: source,
            expectedPackageRevision: expectedPackageRevision,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func disableWorkingMethod(
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.disableWorkingMethod(
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func activateResearcherSkill(
        packageID: String,
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.activateResearcherSkill(
            packageID: packageID,
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func restoreBundledWorkingMethod(
        for actionID: ResearchActionID,
        expectedPackageState: ResearchWorkingMethodExpectedPackageState,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodRestoreOutcome {
        let handle = try await reference.requireHandle()
        return try await handle.restoreBundledWorkingMethod(
            for: actionID,
            expectedPackageState: expectedPackageState,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func citationMethodStatus() async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.researchCitationMethodStatus()
    }

    public func activateCitationMethod(
        selection: ResearchCitationMethodSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.activateResearchCitationMethod(
            selection,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func clearCitationMethod(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.clearResearchCitationMethod(
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func adoptBundledCitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus {
        let handle = try await reference.requireHandle()
        return try await handle.adoptBundledCitationStarter(
            expectedBindingRevision: expectedBindingRevision
        )
    }

    public func prepareSkillMaintenance(
        _ request: ResearchSkillMaintenanceRequest
    ) async throws -> ResearchSkillMaintenancePreparation {
        let handle = try await reference.requireHandle()
        return try await handle.services.researchSkillMaintenanceStore.prepare(request)
    }

    public func applySkillMaintenance(
        _ preparation: ResearchSkillMaintenancePreparation,
        confirmationToken: ResearchSkillMaintenanceConfirmationToken
    ) async throws -> ResearchSkillMaintenanceApplyOutcome {
        let handle = try await reference.requireHandle()
        return try await handle.applyCoordinatedSkillMaintenance(
            preparation,
            confirmationToken: confirmationToken
        )
    }

    public func restoreSkillMaintenance(
        snapshotID: UUID,
        expectedCurrentState: ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome {
        let handle = try await reference.requireHandle()
        return try await handle.restoreCoordinatedSkillMaintenance(
            snapshotID: snapshotID,
            expectedCurrentState: expectedCurrentState
        )
    }

    public func skillMaintenanceSnapshots(
        packageID: String? = nil
    ) async throws -> ResearchSkillMaintenanceSnapshotListing {
        let handle = try await reference.requireHandle()
        return try await handle.services.researchSkillMaintenanceStore.snapshots(
            packageID: packageID
        )
    }

}

extension WorkspaceHandle {
    fileprivate func applyCoordinatedSkillMaintenance(
        _ preparation: ResearchSkillMaintenancePreparation,
        confirmationToken: ResearchSkillMaintenanceConfirmationToken
    ) async throws -> ResearchSkillMaintenanceApplyOutcome {
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillMaintenanceStore.apply(
            preparation,
            confirmationToken: confirmationToken
        )
    }

    fileprivate func restoreCoordinatedSkillMaintenance(
        snapshotID: UUID,
        expectedCurrentState: ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome {
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        return try await services.researchSkillMaintenanceStore.restore(
            snapshotID: snapshotID,
            expectedCurrentState: expectedCurrentState
        )
    }
}

/// Delivery-neutral access to the protected bundled research-guidance
/// catalog. Its private control root has no Triptych-local packages, so these
/// operations remain available before a workspace is configured.
public actor ResearchGuidanceOperations {
    private let store: ResearchSkillTransactionCoordinator

    init(store: ResearchSkillTransactionCoordinator) {
        self.store = store
    }

    public func skills() async throws -> [ResearchSkillPackage] {
        try await store.skills()
    }

    public func catalog() async throws -> ResearchSkillCatalog {
        try await store.catalog()
    }

    public func package(id: String) async throws -> ResearchSkillPackage {
        try await store.package(id: id)
    }

    public func resourcePaths(id: String) async throws -> [String] {
        try await store.resourcePaths(id: id)
    }

    public func resource(id: String, relativePath: String) async throws -> String {
        try await store.resource(id: id, relativePath: relativePath)
    }

    public func instructionAssembly(
        mode: ResearchSkillMode = .discuss,
        requestedSkillIDs: [String] = [],
        mixedPhases: [ResearchSkillAssemblyPhase] = []
    ) async throws -> String {
        try await store.instructionAssembly(
            mode: mode,
            requestedSkillIDs: requestedSkillIDs,
            mixedPhases: mixedPhases
        )
    }

    public func resolveWorkflow(
        _ contract: ResearchWorkflowContract
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try await ResearchWorkflowAssembler.resolve(contract, store: store)
    }
}
