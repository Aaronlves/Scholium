import ScholiumContracts
import Combine
import Foundation

enum ResearchInspectorMode: String, CaseIterable, Identifiable, Sendable {
    case overview
    case connect
    case actions

    var id: Self { self }

    init(restoring rawValue: String?) {
        switch rawValue?.lowercased() {
        case "connect", "connections", "incoming", "outgoing": self = .connect
        case "actions": self = .actions
        case "overview", "research", "relationships", .none: self = .overview
        default: self = .overview
        }
    }

    var interfaceTitleResource: LocalizedStringResource {
        switch self {
        case .overview: "Overview"
        case .connect: "Connect"
        case .actions: "Actions"
        }
    }
}

struct ResearchInspectorState: Equatable, Sendable {
    var mode: ResearchInspectorMode = .overview
    var isVisible = false
}

/// Per-window owner for research-context data and Action presentation.
/// Inspector visibility and mode belong to the surrounding workspace window,
/// so changing the selected document tab doesn't change the shell.
/// Research records and checkpoints remain borrowed from Application.
@MainActor
final class ResearchController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    @Published private(set) var activeDocument: VaultNoteReference?
    @Published private(set) var records: WorkspaceResearchSnapshot?
    @Published private(set) var errorMessage: String?
    @Published var checkpointListingError: String?
    @Published var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] = []
    @Published var transactionRecoveryError: String?

    let actions = ResearchActionController()
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
        actions.objectWillChange
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
    /// this window's independent Inspector and Action presentation state.
    func bind(to operations: any ResearchUseCases, snapshot: WorkspaceSnapshot? = nil) {
        self.operations = operations
        errorMessage = nil
        if let snapshot { receive(snapshot) }
    }

    func unbind() {
        operations = nil
        actions.unbind()
        bibliography.unbind()
        records = nil
        errorMessage = nil
    }

    func researchSnapshot() async throws -> WorkspaceResearchSnapshot {
        try await requireOperations().snapshot()
    }

    func refreshResearchProjection() async throws {
        let operations = try requireOperations()
        let current = try await operations.snapshot()
        let active = try await operations.activeDiscussions(noteID: nil)
        let finished = try await operations.finishedResearchRecords(noteID: nil)
        records = WorkspaceResearchSnapshot(
            settlements: current.settlements,
            activeDiscussions: active,
            finishedResearchRecords: finished,
            pendingResearchStates: current.pendingResearchStates,
            critiques: current.critiques,
            checkpointListing: current.checkpointListing,
            recoveryRecords: current.recoveryRecords,
            healthIssues: current.healthIssues
        )
        errorMessage = nil
    }

    @discardableResult
    func settle(
        _ note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        try await requireOperations().settle(
            note,
            expectedRevision: expectedRevision,
            rationale: rationale
        )
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try await requireOperations().critique(workNoteID: workNoteID)
    }

    func activeDiscussions(noteID: UUID?) async throws -> [PortableResearchDiscussion] {
        try await requireOperations().activeDiscussions(noteID: noteID)
    }

    func activeDiscussion(id: UUID) async throws -> PortableResearchDiscussion {
        try await requireOperations().activeDiscussion(id: id)
    }

    func setResearchRecordPinned(
        id: UUID,
        isPinned: Bool
    ) async throws -> PortableResearchRecord {
        try await requireOperations().setResearchRecordPinned(
            id: id,
            isPinned: isPinned
        )
    }

    func deleteResearchRecordPermanently(id: UUID) async throws {
        let operations = try requireOperations()
        do {
            try await operations.deleteResearchRecordPermanently(id: id)
            try await refreshRecordProjection(
                after: "The permanent Research Record deletion"
            )
        } catch let committed as ScholiumApplicationError
            where committed.durableMutationWasCommitted {
            do { try await refreshResearchProjection() } catch { throw committed }
            let remains = records?.finishedResearchRecords.contains { $0.id == id } == true
            guard !remains else { throw committed }
        }
    }

    func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ResearchRecordComparison {
        try await requireOperations().researchRecordComparison(
            recordID: recordID,
            noteID: noteID
        )
    }

    private func refreshRecordProjection(after operation: String) async throws {
        do {
            try await refreshResearchProjection()
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: operation,
                reason: error.localizedDescription
            )
        }
    }

    func activeDiscussionIfPresent(id: UUID) async throws -> PortableResearchDiscussion? {
        try await requireOperations().activeDiscussionIfPresent(id: id)
    }

    @discardableResult
    func createDiscussion(
        target: ResearchFunctionTarget,
        focalNotes: [ResearchFunctionMaterial] = [],
        passage: CommentAnchor?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        try await requireOperations().createDiscussion(
            target: target,
            focalNotes: focalNotes,
            passage: passage,
            researcherMessage: researcherMessage
        )
    }

    @discardableResult
    func createComment(
        target: ResearchFunctionTarget,
        lineReference: ResearchLineReference,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion {
        try await requireOperations().createComment(
            target: target,
            lineReference: lineReference,
            researcherMessage: researcherMessage
        )
    }

    func discussionAgentInstructions(id: UUID) async throws -> String {
        try await requireOperations().actionRun(id: id).instructions
    }

    @discardableResult
    func appendDiscussionStatement(
        discussionID: UUID,
        author: PortableResearchStatementAuthor,
        attribution: String,
        text: String,
        passage: CommentAnchor? = nil
    ) async throws -> PortableResearchDiscussion {
        try await requireOperations().appendDiscussionStatement(
            discussionID: discussionID,
            author: author,
            attribution: attribution,
            text: text,
            passage: passage
        )
    }

    @discardableResult
    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord {
        try await requireOperations().finishDiscussion(discussionID: discussionID)
    }

    @discardableResult
    func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation? {
        try await requireOperations().critique(critiqueRelativePath: critiqueRelativePath)
    }

    @discardableResult
    func setCritiqueFindingDisposition(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String?,
        noTextChangeRationale: String?,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        try await requireOperations().setCritiqueFindingDisposition(
            workNote: workNote,
            roundID: roundID,
            findingID: findingID,
            decision: decision,
            rationale: rationale,
            noTextChangeRationale: noTextChangeRationale,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func completeCritiqueRound(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation {
        try await requireOperations().completeCritiqueRound(
            workNote: workNote,
            roundID: roundID,
            expectedRevision: expectedRevision
        )
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

    func settings() async throws -> TriptychSettings {
        try await requireOperations().settings()
    }

    func saveSettings(_ settings: TriptychSettings) async throws {
        try await requireOperations().saveSettings(settings)
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
        mode: ResearchSkillMode = .discuss,
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
    }

    func selectInspectorMode(_ mode: ResearchInspectorMode) {
        peripheralPresentation.selectInspectorMode(mode)
    }

    func showResearchInspector(_ isVisible: Bool) {
        peripheralPresentation.showResearchInspector(isVisible)
    }

    func restoreInspector(storedMode: String?, isVisible: Bool?) {
        peripheralPresentation.restoreInspector(
            storedMode: storedMode,
            isVisible: isVisible
        )
    }

    func requestPresentAction(
        _ actionID: ResearchActionID,
        target: VaultNoteReference,
        presentationID: UUID
    ) {
        intentHandler(.presentResearchAction(ResearchActionPanelRoute(
            target: target,
            actionID: actionID,
            presentationID: presentationID
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
        actions.dismiss()
        bibliography.unbind()
    }

    func receive(_ snapshot: WorkspaceSnapshot) {
        records = snapshot.research
        errorMessage = nil
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
