import Combine
import Foundation
import ScholiumContracts

enum ResearchInspectorMode: String, CaseIterable, Identifiable, Sendable {
    case links
    case related

    var id: Self { self }

    init(restoring rawValue: String?) {
        self = rawValue.flatMap(Self.init(rawValue:)) ?? .links
    }

    var interfaceTitleResource: LocalizedStringResource {
        switch self {
        case .links: "Links"
        case .related: "Related Material"
        }
    }

    var systemImage: String {
        switch self {
        case .links: "link"
        case .related: "text.magnifyingglass"
        }
    }
}

struct ResearchInspectorState: Equatable, Sendable {
    var mode: ResearchInspectorMode = .links
    var isVisible = false
}

/// The narrow application ports consumed by the per-window research feature.
/// Permission and source capabilities remain with their
/// dedicated controllers and never enter this bundle.
struct ResearchControllerCapabilities: Sendable {
    let triptychID: UUID
    let documents: any DocumentUseCases
    let research: any ResearchUseCases
    let agentCollaboration: any AgentCollaborationUseCases
    let changes: any DocumentChangeUseCases
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
    @Published private(set) var pendingChanges: [DocumentChangeSummary]?
    @Published private(set) var pendingChangesError: String?
    @Published private(set) var documentChangesRevision: UInt64 = 0
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
    private var pendingChangesRefreshTask: Task<Void, Never>?
    private var pendingChangesRefreshGeneration: UInt64 = 0
    private var observedDocumentChangesGeneration: UInt64?
    private var documentSelectionObservation: AnyCancellable?

    init(
        shellState: WindowShellState = WindowShellState(),
        selectedDocuments: AnyPublisher<WindowSelectedDocument?, Never> = Empty().eraseToAnyPublisher(),
        intentHandler: @escaping IntentHandler = { _ in }
    ) {
        self.shellState = shellState
        self.intentHandler = intentHandler
        // Consume the incoming selection synchronously: @Published delivers it
        // before DocumentController stores it, so never reread that property here.
        documentSelectionObservation =
            selectedDocuments
            .map { $0?.editingTarget }
            .removeDuplicates()
            .sink { [weak self] _ in self?.relatedMaterials.reset() }
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
        pendingChangesRefreshTask?.cancel()
        relatedMaterials.cancel()
        agentChangesRefreshGeneration &+= 1
        pendingChangesRefreshGeneration &+= 1
        observedDocumentChangesGeneration = snapshot?.documentChangesGeneration
        if self.capabilities?.triptychID != capabilities.triptychID {
            linksInspector.reset()
            relatedMaterials.reset()
        }
        self.capabilities = capabilities
        agentChanges = nil
        agentChangesError = nil
        pendingChanges = nil
        pendingChangesError = nil
        errorMessage = nil
        if let snapshot { receive(snapshot) }
        scheduleAgentChangesRefresh()
        scheduleDocumentChangesRefresh()
    }

    func unbind() {
        relatedMaterials.reset()
        agentChangesRefreshTask?.cancel()
        pendingChangesRefreshTask?.cancel()
        agentChangesRefreshTask = nil
        pendingChangesRefreshTask = nil
        agentChangesRefreshGeneration &+= 1
        pendingChangesRefreshGeneration &+= 1
        observedDocumentChangesGeneration = nil
        capabilities = nil
        researchSnapshot = nil
        agentChanges = nil
        agentChangesError = nil
        pendingChanges = nil
        pendingChangesError = nil
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

    func scheduleDocumentChangesRefresh() {
        pendingChangesRefreshTask?.cancel()
        pendingChangesRefreshTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.loadDocumentChanges()
        }
    }

    func noteDocumentChangesInvalidated() {
        documentChangesRevision &+= 1
        scheduleDocumentChangesRefresh()
    }

    func observeDocumentChangesGeneration(_ generation: UInt64) {
        guard observedDocumentChangesGeneration != generation else { return }
        observedDocumentChangesGeneration = generation
        noteDocumentChangesInvalidated()
    }

    @discardableResult
    func loadDocumentChanges() async throws -> [DocumentChangeSummary] {
        pendingChangesRefreshGeneration &+= 1
        let generation = pendingChangesRefreshGeneration
        guard let operations = capabilities?.changes else {
            throw ScholiumApplicationError.noWorkspaceConfigured
        }
        do {
            let changes = try await operations.pendingChanges()
            try Task.checkCancellation()
            guard generation == pendingChangesRefreshGeneration else { throw CancellationError() }
            pendingChanges = changes
            pendingChangesError = nil
            return changes
        } catch {
            guard generation == pendingChangesRefreshGeneration else { throw error }
            if !(error is CancellationError) { pendingChangesError = error.localizedDescription }
            throw error
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
        intentHandler(
            .openDocument(
                WindowDocumentRoute(
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
            throw ScholiumApplicationError.noWorkspaceConfigured
        }
        return research
    }

    private func requireDocuments() throws -> any DocumentUseCases {
        guard let documents = capabilities?.documents else {
            throw ScholiumApplicationError.noWorkspaceConfigured
        }
        return documents
    }

    private func requireAgentCollaboration() throws -> any AgentCollaborationUseCases {
        guard let agentCollaboration = capabilities?.agentCollaboration else {
            throw ScholiumApplicationError.noWorkspaceConfigured
        }
        return agentCollaboration
    }

}
