import ScholiumContracts
import Combine
import Foundation

struct ResearchInspectorState: Equatable, Sendable {
    var modeRawValue = "connections"
    var showsResearchInspector = false
}

/// Per-window owner for research-context data and function presentation.
/// Inspector visibility and mode belong to the surrounding workspace window,
/// so changing the selected document tab doesn't change the shell.
/// Research records and checkpoints remain borrowed from Application.
@MainActor
final class ResearchController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    @Published private(set) var activeDocument: VaultNoteReference?
    @Published private(set) var records: WorkspaceResearchSnapshot?
    @Published private(set) var errorMessage: String?
    @Published var researchRecordRequestGeneration: UInt64 = 0
    @Published var dialogueInitialNotes: Set<VaultQualifiedNoteID> = []
    @Published var checkpointListingError: String?
    @Published var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] = []
    @Published var transactionRecoveryError: String?

    let functions = ResearchFunctionController()
    let bibliography = RecommendedBibliographyController()

    private let intentHandler: IntentHandler
    private let peripheralPresentation: WindowPeripheralPresentationState
    private var operations: (any ResearchUseCases)?
    private var cancellables: Set<AnyCancellable> = []

    init(
        peripheralPresentation: WindowPeripheralPresentationState = WindowPeripheralPresentationState(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        self.peripheralPresentation = peripheralPresentation
        self.intentHandler = intentHandler
        peripheralPresentation.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        functions.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        bibliography.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var inspector: ResearchInspectorState {
        peripheralPresentation.inspector
    }

    /// Borrows the capabilities selected by WorkspaceStore while retaining
    /// this window's independent inspector and function presentation state.
    func bind(to operations: any ResearchUseCases, snapshot: WorkspaceSnapshot? = nil) {
        self.operations = operations
        errorMessage = nil
        if let snapshot { receive(snapshot) }
    }

    func unbind() {
        operations = nil
        functions.unbind()
        bibliography.unbind()
        records = nil
        errorMessage = nil
    }

    func researchSnapshot() async throws -> WorkspaceResearchSnapshot {
        try await requireOperations().snapshot()
    }

    func humanReview(noteID: UUID) async throws -> HumanReviewRecord? {
        try await requireOperations().humanReview(noteID: noteID)
    }

    func dialogueHistory(noteID: UUID) async throws -> [DialogueEntry] {
        try await requireOperations().dialogues(noteID: noteID)
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try await requireOperations().critique(workNoteID: workNoteID)
    }

    func comments(noteID: UUID) async throws -> [ResearcherComment] {
        try await requireOperations().comments(noteID: noteID)
    }

    @discardableResult
    func addComment(
        to note: VaultQualifiedNoteID,
        text: String,
        anchor: ResearcherCommentAnchor,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        try await requireOperations().addComment(
            to: note,
            text: text,
            anchor: anchor,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func updateComment(
        noteID: UUID,
        commentID: UUID,
        text: String
    ) async throws -> HumanReviewRecord {
        try await requireOperations().updateComment(
            noteID: noteID,
            commentID: commentID,
            text: text
        )
    }

    @discardableResult
    func setCommentResolved(
        noteID: UUID,
        commentID: UUID,
        resolved: Bool
    ) async throws -> HumanReviewRecord {
        try await requireOperations().setCommentResolved(
            noteID: noteID,
            commentID: commentID,
            resolved: resolved
        )
    }

    @discardableResult
    func deleteComment(
        noteID: UUID,
        commentID: UUID
    ) async throws -> HumanReviewRecord {
        try await requireOperations().deleteComment(noteID: noteID, commentID: commentID)
    }

    @discardableResult
    func reattachComment(
        to note: VaultQualifiedNoteID,
        commentID: UUID,
        anchor: ResearcherCommentAnchor,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        try await requireOperations().reattachComment(
            to: note,
            commentID: commentID,
            anchor: anchor,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func reattachComments(
        to note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> HumanReviewRecord {
        try await requireOperations().reattachComments(
            to: note,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func saveHumanReviewDraft(
        for note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        try await requireOperations().saveHumanReviewDraft(
            for: note,
            expectedRevision: expectedRevision,
            qualification: qualification,
            reviewNote: reviewNote
        )
    }

    @discardableResult
    func completeHumanReview(
        for note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        qualification: NoteQualification?,
        reviewNote: String
    ) async throws -> HumanReviewRecord {
        try await requireOperations().completeHumanReview(
            for: note,
            expectedRevision: expectedRevision,
            qualification: qualification,
            reviewNote: reviewNote
        )
    }

    func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation? {
        try await requireOperations().critique(critiqueRelativePath: critiqueRelativePath)
    }

    @discardableResult
    func createCheckpoint(
        name: String,
        kind: TriptychCheckpointKind = .manual
    ) async throws -> TriptychCheckpoint {
        try await requireOperations().createCheckpoint(name: name, kind: kind)
    }

    func checkpoints() async throws -> TriptychCheckpointListing {
        try await requireOperations().checkpoints()
    }

    func noteCheckpoints(
        for note: VaultQualifiedNoteID
    ) async throws -> [TriptychCheckpoint] {
        try await requireOperations().noteCheckpoints(for: note)
    }

    func checkpointNoteContent(
        _ checkpointID: UUID,
        note: VaultQualifiedNoteID
    ) async throws -> String {
        try await requireOperations().checkpointNoteContent(checkpointID, note: note)
    }

    func checkpointComparison(
        _ checkpointID: UUID
    ) async throws -> [TriptychCheckpointChange] {
        try await requireOperations().checkpointComparison(checkpointID)
    }

    @discardableResult
    func restoreNote(
        _ note: VaultQualifiedNoteID,
        from checkpointID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychCheckpointRestoreResult {
        try await requireOperations().restoreNote(
            note,
            from: checkpointID,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func restoreCheckpoint(
        _ checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection
    ) async throws -> TriptychCheckpointRestoreResult {
        try await requireOperations().restoreCheckpoint(checkpointID, selection: selection)
    }

    func dialogueResponseProfile() async throws -> DialogueResponseProfile {
        try await requireOperations().dialogueResponseProfile()
    }

    func settings() async throws -> TriptychSettings {
        try await requireOperations().settings()
    }

    func saveSettings(_ settings: TriptychSettings) async throws {
        try await requireOperations().saveSettings(settings)
    }

    func saveDialogueResponseProfile(_ profile: DialogueResponseProfile) async throws {
        try await requireOperations().saveDialogueResponseProfile(profile)
    }

    func dialogueEntries() async throws -> [DialogueEntry] {
        try await requireOperations().dialogueEntries()
    }

    func dialogue(id: UUID) async throws -> DialogueEntry {
        try await requireOperations().dialogue(id: id)
    }

    @discardableResult
    func appendDialogueReply(
        _ reply: DialogueReply,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try await requireOperations().appendDialogueReply(reply, to: entryID)
    }

    @discardableResult
    func appendDialogueFollowUpComment(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try await requireOperations().appendDialogueFollowUpComment(comment, to: entryID)
    }

    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try await requireOperations().recoveryRecords()
    }

    func resolveRecoveryRecord(_ id: UUID) async throws {
        try await requireOperations().resolveRecoveryRecord(id)
    }

    var recoveryRecordsURL: URL? {
        operations?.recoveryRecordsURL
    }

    func prepareCheckpointsLocation() async throws -> URL {
        try await requireOperations().prepareCheckpointsLocation()
    }

    var skillsURL: URL? {
        operations?.skillsURL
    }

    func skills() async throws -> [ResearchSkillPackage] {
        try await requireOperations().skills()
    }

    func skillCatalog() async throws -> ResearchSkillCatalog {
        try await requireOperations().skillCatalog()
    }

    func skillPackage(id: String) async throws -> ResearchSkillPackage {
        try await requireOperations().skillPackage(id: id)
    }

    func createSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        try await requireOperations().createSkill(id: id, source: source)
    }

    func duplicateBundledSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        try await requireOperations().duplicateBundledSkill(id: id, as: newID)
    }

    func saveSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try await requireOperations().saveSkill(
            id: id,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func renameSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try await requireOperations().renameSkill(
            id: id,
            to: newID,
            expectedRevision: expectedRevision
        )
    }

    func deleteSkill(
        id: String,
        expectedRevision: DocumentFingerprint
    ) async throws {
        try await requireOperations().deleteSkill(id: id, expectedRevision: expectedRevision)
    }

    func skillResourcePaths(id: String) async throws -> [String] {
        try await requireOperations().skillResourcePaths(id: id)
    }

    func skillResource(id: String, relativePath: String) async throws -> String {
        try await requireOperations().skillResource(id: id, relativePath: relativePath)
    }

    func skillInstructionAssembly(
        mode: ResearchSkillMode = .dialogue,
        requestedSkillIDs: [String] = [],
        mixedPhases: [ResearchSkillAssemblyPhase] = []
    ) async throws -> String {
        try await requireOperations().skillInstructionAssembly(
            mode: mode,
            requestedSkillIDs: requestedSkillIDs,
            mixedPhases: mixedPhases
        )
    }

    func resolveWorkflow(
        _ contract: ResearchWorkflowContract
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try await requireOperations().resolveWorkflow(contract)
    }

    func setActiveDocument(_ reference: VaultNoteReference?) {
        guard activeDocument != reference else { return }
        activeDocument = reference
        projectFunctionRuns()
    }

    func selectInspectorMode(_ rawValue: String) {
        peripheralPresentation.selectInspectorMode(rawValue)
    }

    func showResearchInspector(_ isVisible: Bool) {
        peripheralPresentation.showResearchInspector(isVisible)
    }

    func restoreInspector(modeRawValue: String?, isVisible: Bool?) {
        peripheralPresentation.restoreInspector(
            modeRawValue: modeRawValue,
            isVisible: isVisible
        )
    }

    func requestPresentFunction(
        _ function: ResearchFunctionID,
        target: VaultNoteReference,
        presentationID: UUID,
        focusCommentComposer: Bool = false
    ) {
        intentHandler(.presentResearchFunction(ResearchFunctionPanelRoute(
            target: target,
            function: function,
            presentationID: presentationID,
            focusCommentComposer: focusCommentComposer
        )))
    }

    func requestOpen(
        _ reference: VaultNoteReference,
        sourceLine: Int? = nil
    ) {
        intentHandler(.openDocument(WindowDocumentRoute(
            reference: reference,
            sourceLocator: sourceLine.map {
                SourceLocator(
                    file: reference.relativePath,
                    line: $0,
                    column: 1
                )
            }
        )))
    }

    func reset() {
        activeDocument = nil
        functions.dismiss()
        bibliography.unbind()
    }

    func receive(_ snapshot: WorkspaceSnapshot) {
        records = snapshot.research
        projectFunctionRuns()
        errorMessage = nil
    }

    private func projectFunctionRuns() {
        let noteID = activeDocument?.stableNoteID.flatMap(UUID.init(uuidString:))
        functions.receive(records?.functionRuns ?? [], targetNoteID: noteID)
    }

    private func requireOperations() throws -> any ResearchUseCases {
        guard let operations else {
            throw ScholiumApplicationError.researchStoreUnavailable(
                "No workspace is active."
            )
        }
        return operations
    }

}
