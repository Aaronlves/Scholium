import ScholiumContracts
import Combine
import Foundation

enum ResearchInspectorMode: String, CaseIterable, Identifiable, Sendable {
    case about
    case links
    case related

    var id: Self { self }

    init(restoring rawValue: String?) {
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .about
    }

    var interfaceTitleResource: LocalizedStringResource {
        switch self {
        case .about: "About"
        case .links: "Links"
        case .related: "Related Material"
        }
    }

    var systemImage: String {
        switch self {
        case .about: "info.circle"
        case .links: "link"
        case .related: "text.magnifyingglass"
        }
    }
}

struct ResearchInspectorState: Equatable, Sendable {
    var mode: ResearchInspectorMode = .about
    var isVisible = false
}

/// The narrow application ports consumed by the per-window research feature.
/// Permission and source-access capabilities remain with their
/// dedicated controllers and never enter this bundle.
struct ResearchControllerCapabilities: Sendable {
    let triptychID: UUID
    let documents: any DocumentUseCases
    let research: any ResearchUseCases
    let agentCollaboration: any AgentCollaborationUseCases
    let recoveryRecordsURL: URL
}

/// Per-window owner for researcher-authored research context and capability
/// access. External Agent conversation lifecycle is outside the App.
/// Inspector visibility and mode belong to the surrounding workspace window,
/// so changing the selected document tab doesn't change the shell.
/// Research state remains borrowed from Application.
@MainActor
final class ResearchController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void

    let linksInspector = LinksInspectorSession()
    let relatedMaterials = RelatedMaterialsSession()

    @Published private(set) var researchSnapshot: WorkspaceResearchSnapshot?
    @Published private(set) var agentChanges: [AgentChange]?
    @Published private(set) var agentChangesError: String?
    @Published private(set) var errorMessage: String?
    @Published var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] = []
    @Published var transactionRecoveryError: String?
    @Published var interruptedSaveRecoveries: [InterruptedSaveRecovery] = []
    @Published var interruptedSaveRecoveryError: String?

    private let intentHandler: IntentHandler
    private let shellState: WindowShellState
    private var capabilities: ResearchControllerCapabilities?
    private var agentChangesRefreshTask: Task<Void, Never>?
    private var agentChangesRefreshGeneration: UInt64 = 0

    init(
        shellState: WindowShellState = WindowShellState(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        self.shellState = shellState
        self.intentHandler = intentHandler
    }

    var inspector: ResearchInspectorState {
        shellState.inspector
    }

    /// Borrows the capabilities selected by WorkspaceStore while retaining
    /// this window's independent Inspector presentation state.
    func bind(
        to capabilities: ResearchControllerCapabilities,
        snapshot: WorkspaceSnapshot? = nil
    ) {
        agentChangesRefreshTask?.cancel()
        relatedMaterials.cancel()
        agentChangesRefreshGeneration &+= 1
        if self.capabilities?.triptychID != capabilities.triptychID {
            linksInspector.reset()
            relatedMaterials.reset()
        }
        self.capabilities = capabilities
        agentChanges = nil
        agentChangesError = nil
        errorMessage = nil
        if let snapshot { receive(snapshot) }
        scheduleAgentChangesRefresh()
    }

    func unbind() {
        relatedMaterials.reset()
        agentChangesRefreshTask?.cancel()
        agentChangesRefreshTask = nil
        agentChangesRefreshGeneration &+= 1
        capabilities = nil
        researchSnapshot = nil
        agentChanges = nil
        agentChangesError = nil
        errorMessage = nil
        transactionRecoveryRecords = []
        transactionRecoveryError = nil
        interruptedSaveRecoveries = []
        interruptedSaveRecoveryError = nil
    }

    func researchSnapshot() async throws -> WorkspaceResearchSnapshot {
        try await requireResearch().snapshot()
    }

    func refreshResearchProjection() async throws {
        researchSnapshot = try await requireResearch().snapshot()
        errorMessage = nil
    }

    func scheduleAgentChangesRefresh() {
        agentChangesRefreshTask?.cancel()
        agentChangesRefreshTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.loadAgentChanges()
        }
    }

    @discardableResult
    func loadAgentChanges() async throws -> [AgentChange] {
        agentChangesRefreshGeneration &+= 1
        let generation = agentChangesRefreshGeneration
        let operations = try requireAgentCollaboration()
        do {
            let changes = try await operations.agentChanges()
            try Task.checkCancellation()
            guard generation == agentChangesRefreshGeneration else {
                throw CancellationError()
            }
            agentChanges = changes
            agentChangesError = nil
            return changes
        } catch {
            guard generation == agentChangesRefreshGeneration else {
                throw error
            }
            if !(error is CancellationError) {
                agentChangesError = error.localizedDescription
            }
            throw error
        }
    }

    @discardableResult
    func settle(
        _ note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord {
        try await requireResearch().settle(
            note,
            expectedRevision: expectedRevision,
            rationale: rationale
        )
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try await requireResearch().critique(workNoteID: workNoteID)
    }

    @discardableResult
    func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation? {
        try await requireResearch().critique(critiqueRelativePath: critiqueRelativePath)
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
        try await requireResearch().setCritiqueFindingDisposition(
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
        try await requireResearch().completeCritiqueRound(
            workNote: workNote,
            roundID: roundID,
            expectedRevision: expectedRevision
        )
    }

    func settings() async throws -> TriptychSettingsSnapshot {
        try await requireResearch().settings()
    }

    func settingsLoadState() async throws -> TriptychSettingsLoadState {
        try await requireResearch().settingsLoadState()
    }

    func saveSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot {
        try await requireResearch().saveSettings(
            settings,
            expectedRevision: expectedRevision
        )
    }

    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord] {
        try await requireResearch().recoveryRecords()
    }

    func resolveRecoveryRecord(_ id: UUID) async throws {
        try await requireResearch().resolveRecoveryRecord(id)
    }

    func loadInterruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery] {
        try await requireDocuments().interruptedSaveRecoveries()
    }

    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent {
        try await requireDocuments().interruptedSaveRecoveryContent(recovery)
    }

    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL {
        try await requireDocuments().prepareInterruptedSaveRecoveryLocation(recovery)
    }

    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit> {
        try await requireDocuments().restoreInterruptedSaveRecovery(recovery)
    }

    var recoveryRecordsURL: URL? {
        capabilities?.recoveryRecordsURL
    }

    func selectInspectorMode(_ mode: ResearchInspectorMode) {
        shellState.selectInspectorMode(mode)
    }

    func showResearchInspector(_ isVisible: Bool) {
        shellState.showResearchInspector(isVisible)
    }

    func restoreInspector(
        modesByWorkspace: [WorkspaceVaultSlot: String],
        isVisible: Bool?
    ) {
        shellState.restoreInspector(
            modesByWorkspace: modesByWorkspace,
            isVisible: isVisible
        )
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

    func requestEditAtSource(_ reference: VaultNoteReference, line: Int) {
        intentHandler(.revealSourceLocator(vaultID: reference.vaultID, locator: SourceLocator(
            file: reference.relativePath, line: line, column: 1
        )))
    }

    func reset() {
        relatedMaterials.reset()
        transactionRecoveryRecords = []
        transactionRecoveryError = nil
        interruptedSaveRecoveries = []
        interruptedSaveRecoveryError = nil
    }

    func receive(_ snapshot: WorkspaceSnapshot) {
        researchSnapshot = snapshot.research
        errorMessage = nil
    }

    private func requireResearch() throws -> any ResearchUseCases {
        guard let research = capabilities?.research else {
            throw ScholiumApplicationError.critiqueStoreUnavailable(
                "No workspace is active."
            )
        }
        return research
    }

    private func requireDocuments() throws -> any DocumentUseCases {
        guard let documents = capabilities?.documents else {
            throw ScholiumApplicationError.critiqueStoreUnavailable(
                "No workspace is active."
            )
        }
        return documents
    }

    private func requireAgentCollaboration() throws -> any AgentCollaborationUseCases {
        guard let agentCollaboration = capabilities?.agentCollaboration else {
            throw ScholiumApplicationError.critiqueStoreUnavailable(
                "No workspace is active."
            )
        }
        return agentCollaboration
    }

}
