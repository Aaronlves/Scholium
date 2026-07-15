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

    public func loadUnclassified(relativePath: String) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.loadUnclassifiedDocument(relativePath: relativePath)
    }

    public func unclassifiedDocuments() async throws -> [NoteDocument] {
        let handle = try await reference.requireHandle()
        return try await handle.unclassifiedDocuments()
    }

    public func importUnclassifiedMarkdown(at sourceURL: URL) async throws -> URL {
        let handle = try await reference.requireHandle()
        return try await handle.importUnclassifiedMarkdown(at: sourceURL)
    }

    public func saveUnclassified(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        let handle = try await reference.requireHandle()
        return try await handle.saveUnclassifiedDocument(
            relativePath: relativePath,
            source: source,
            expectedRevision: expectedRevision
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

    /// Delegates exact-byte revision checking and source mutation to
    /// `VaultRepository`; the application layer does not reproduce it.
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

    public func versions(for id: VaultQualifiedNoteID) async throws -> [VaultVersion] {
        let handle = try await reference.requireHandle()
        return try await handle.versions(for: id)
    }

    public func restore(
        _ id: VaultQualifiedNoteID,
        versionID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        let handle = try await reference.requireHandle()
        return try await handle.restoreDocument(
            id,
            versionID: versionID,
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

    public func classifyUnclassified(
        _ relativePath: String,
        into slot: WorkspaceVaultSlot,
        destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> UnclassifiedClassificationCommit {
        let handle = try await reference.requireHandle()
        return try await handle.classifyUnclassifiedDocument(
            relativePath,
            into: slot,
            destinationRelativePath: destinationRelativePath,
            expectedRevision: expectedRevision
        )
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

    public func search(
        _ query: SearchQuery,
        scope: SearchScope = .workspace,
        limit: Int = 50
    ) async throws -> [SearchHit] {
        let handle = try await reference.requireHandle()
        return try await handle.search(query, scope: scope, limit: limit)
    }

    public func quickOpen(
        query: String,
        limit: Int = 40
    ) async throws -> [WorkspaceCatalogNote] {
        let handle = try await reference.requireHandle()
        return try await handle.quickOpen(query: query, limit: limit)
    }

    public func related(
        query: String,
        scope: SearchScope,
        excluding: Set<VaultQualifiedNoteID> = [],
        limit: Int = 12
    ) async throws -> [RelatedSearchItem] {
        let handle = try await reference.requireHandle()
        return try await handle.related(
            query: query,
            scope: scope,
            excluding: excluding,
            limit: limit
        )
    }
}

public actor ResearchOperations: ResearchUseCases {
    public nonisolated let skillsURL: URL
    public nonisolated let recoveryRecordsURL: URL
    private let reference: WorkspaceHandleReference

    init(
        reference: WorkspaceHandleReference,
        skillsURL: URL,
        recoveryRecordsURL: URL
    ) {
        self.reference = reference
        self.skillsURL = skillsURL
        self.recoveryRecordsURL = recoveryRecordsURL
    }

    public nonisolated static func inspectSkillDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin
    ) -> ResearchSkillPackage {
        ResearchSkillInspector.inspect(id: id, source: source, origin: origin)
    }

    public func snapshot() async throws -> WorkspaceResearchSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.researchSnapshot()
    }

    public func humanReview(noteID: UUID) async throws -> HumanReviewRecord? {
        let handle = try await reference.requireHandle()
        return try await handle.humanReview(noteID: noteID)
    }

    public func comments(noteID: UUID) async throws -> [ResearcherComment] {
        let handle = try await reference.requireHandle()
        return try await handle.comments(noteID: noteID)
    }

    @discardableResult
    public func addComment(
        to note: VaultQualifiedNoteID,
        text: String,
        anchor: ResearcherCommentAnchor? = nil,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.addComment(
            to: note,
            text: text,
            anchor: anchor,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    public func updateComment(
        noteID: UUID,
        commentID: UUID,
        text: String
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.updateComment(
            noteID: noteID,
            commentID: commentID,
            text: text
        )
    }

    @discardableResult
    public func setCommentResolved(
        noteID: UUID,
        commentID: UUID,
        resolved: Bool
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.setCommentResolved(
            noteID: noteID,
            commentID: commentID,
            resolved: resolved
        )
    }

    @discardableResult
    public func deleteComment(
        noteID: UUID,
        commentID: UUID
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.deleteComment(noteID: noteID, commentID: commentID)
    }

    @discardableResult
    public func reattachComment(
        to note: VaultQualifiedNoteID,
        commentID: UUID,
        anchor: ResearcherCommentAnchor,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.reattachComment(
            to: note,
            commentID: commentID,
            anchor: anchor,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    public func reattachComments(
        to note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.reattachComments(
            to: note,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    public func saveHumanReviewDraft(
        for note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.saveHumanReviewDraft(
            for: note,
            expectedRevision: expectedRevision,
            qualification: qualification,
            reviewNote: reviewNote
        )
    }

    @discardableResult
    public func completeHumanReview(
        for note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        let handle = try await reference.requireHandle()
        return try await handle.completeHumanReview(
            for: note,
            expectedRevision: expectedRevision,
            qualification: qualification,
            reviewNote: reviewNote
        )
    }

    public func dialogues(noteID: UUID) async throws -> [DialogueEntry] {
        let handle = try await reference.requireHandle()
        return try await handle.dialogues(noteID: noteID)
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

    public func dialogueResponseProfile() async throws -> DialogueResponseProfile {
        let handle = try await reference.requireHandle()
        return try await handle.dialogueResponseProfile()
    }

    public func settings() async throws -> TriptychSettings {
        let handle = try await reference.requireHandle()
        return try await handle.triptychSettings()
    }

    public func saveSettings(_ settings: TriptychSettings) async throws {
        let handle = try await reference.requireHandle()
        try await handle.saveTriptychSettings(settings)
    }

    public func saveDialogueResponseProfile(
        _ profile: DialogueResponseProfile
    ) async throws {
        let handle = try await reference.requireHandle()
        try await handle.saveDialogueResponseProfile(profile)
    }

    public func dialogueEntries() async throws -> [DialogueEntry] {
        let handle = try await reference.requireHandle()
        return try await handle.dialogueEntries()
    }

    public func dialogue(id: UUID) async throws -> DialogueEntry {
        let handle = try await reference.requireHandle()
        return try await handle.dialogue(id: id)
    }

    @discardableResult
    public func createDialogue(
        instruction: String,
        selectedNotes: [DialogueNoteReference],
        includedCommentIDs: Set<UUID>,
        requestedDestination: String? = nil,
        responseProfile: DialogueResponseProfile? = nil
    ) async throws -> DialoguePreparation {
        let handle = try await reference.requireHandle()
        return try await handle.createDialogue(
            instruction: instruction,
            selectedNotes: selectedNotes,
            includedCommentIDs: includedCommentIDs,
            requestedDestination: requestedDestination,
            responseProfile: responseProfile
        )
    }

    @discardableResult
    public func appendDialogueReply(
        _ reply: DialogueReply,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        let handle = try await reference.requireHandle()
        return try await handle.appendDialogueReply(reply, to: entryID)
    }

    @discardableResult
    public func appendDialogueFollowUpComment(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        let handle = try await reference.requireHandle()
        return try await handle.appendDialogueFollowUpComment(comment, to: entryID)
    }

    @discardableResult
    public func requestCritique(
        for work: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        scope: CritiqueRequestScope,
        lens: String = "",
        selectedRanges: String = "",
        additionalInstructions: String = ""
    ) async throws -> CritiquePreparation {
        let handle = try await reference.requireHandle()
        return try await handle.requestCritique(
            for: work,
            expectedRevision: expectedRevision,
            scope: scope,
            lens: lens,
            selectedRanges: selectedRanges,
            additionalInstructions: additionalInstructions
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
        mode: ResearchSkillMode = .dialogue,
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
}

/// Delivery-neutral access to the protected bundled research-guidance
/// catalog. Its private control root has no Triptych-local packages, so these
/// operations remain available before a workspace is configured.
public actor ResearchGuidanceOperations {
    private let store: ResearchSkillStore

    init(store: ResearchSkillStore) {
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
        mode: ResearchSkillMode = .dialogue,
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
