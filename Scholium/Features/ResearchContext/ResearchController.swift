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
        case "actions", "functions": self = .actions
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

    func discussionHistory(noteID: UUID) async throws -> [DialogueEntry] {
        try await requireOperations().discussionHistory(noteID: noteID)
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try await requireOperations().critique(workNoteID: workNoteID)
    }

    func commentExchanges(noteID: UUID) async throws -> [CommentExchange] {
        try await requireOperations().commentExchanges(noteID: noteID)
    }

    @discardableResult
    func createCommentExchange(
        _ exchange: CommentExchange
    ) async throws -> CommentExchange {
        try await requireOperations().createCommentExchange(exchange)
    }

    @discardableResult
    func appendCommentExchangeTurn(
        exchangeID: UUID,
        turn: CommentExchangeTurn
    ) async throws -> CommentExchange {
        try await requireOperations().appendCommentExchangeTurn(
            exchangeID: exchangeID,
            turn: turn
        )
    }

    @discardableResult
    func finishCommentExchange(exchangeID: UUID) async throws -> CommentExchange {
        try await requireOperations().finishCommentExchange(exchangeID: exchangeID)
    }

    @discardableResult
    func finishDiscussion(runID: UUID) async throws -> ResearchActivityEvent {
        try await requireOperations().finishDiscussion(runID: runID)
    }

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

    func discussResponseProfile() async throws -> DialogueResponseProfile {
        try await requireOperations().discussResponseProfile()
    }

    func settings() async throws -> TriptychSettings {
        try await requireOperations().settings()
    }

    func saveSettings(_ settings: TriptychSettings) async throws {
        try await requireOperations().saveSettings(settings)
    }

    func saveDiscussResponseProfile(_ profile: DialogueResponseProfile) async throws {
        try await requireOperations().saveDiscussResponseProfile(profile)
    }

    func discussionRecords() async throws -> [DialogueEntry] {
        try await requireOperations().discussionRecords()
    }

    func discussion(id: UUID) async throws -> DialogueEntry {
        try await requireOperations().discussion(id: id)
    }

    @discardableResult
    func appendDiscussionReply(
        _ reply: DialogueReply,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try await requireOperations().appendDiscussionReply(reply, to: entryID)
    }

    @discardableResult
    func appendDiscussionFollowUp(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try await requireOperations().appendDiscussionFollowUp(comment, to: entryID)
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
        projectFunctionRuns()
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
