import Foundation

public protocol DocumentUseCases: Sendable {
    func snapshot() async throws -> [WorkspaceVaultSnapshot]
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument
    func loadUnclassified(relativePath: String) async throws -> NoteDocument
    func unclassifiedDocuments() async throws -> [NoteDocument]
    func importUnclassifiedMarkdown(at sourceURL: URL) async throws -> URL
    func saveUnclassified(relativePath: String, source: String, expectedRevision: DocumentFingerprint) async throws -> NoteDocument
    func create(_ id: VaultQualifiedNoteID, content: String) async throws -> NoteDocument
    func create(_ request: DocumentCreationRequest) async throws -> NoteDocument
    /// Creates an empty note at the first unoccupied default path in `folderRelativePath`.
    func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> NoteDocument
    /// Creates the first unoccupied default folder in `parentRelativePath`.
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> VaultRelativeFolderPath
    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> FolderMoveCommit
    func moveFolderToTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> FolderMoveCommit
    func duplicate(_ id: VaultQualifiedNoteID, to destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> NoteDocument
    func save(_ id: VaultQualifiedNoteID, changeSet: NoteChangeSet, expectedRevision: DocumentFingerprint) async throws -> SaveResult
    func move(_ id: VaultQualifiedNoteID, to destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func setAside(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func moveToTrash(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func putBack(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func deletePermanently(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> PermanentDeletionCommit
    func recoverInterruptedTransactions() async throws -> [String]
    func classifyUnclassified(_ relativePath: String, into slot: WorkspaceVaultSlot, destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> UnclassifiedClassificationCommit
    func resolveIdentity(_ ambiguity: NoteIdentityAmbiguity, candidateID: UUID?) async throws -> NoteIdentityRecord
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog
}

public extension DocumentUseCases {
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog {
        return DocumentPreviewCatalog(
            graphGeneration: graphGeneration,
            source: source,
            sourceFingerprint: sourceFingerprint,
            links: []
        )
    }
}

public protocol DiscoveryUseCases: Sendable {
    func snapshot() async throws -> WorkspaceDiscoverySnapshot
    func refresh() async throws -> WorkspaceSnapshot
    func search(_ request: SearchRequest) async throws -> SearchResponse
    func related(
        query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding: Set<VaultQualifiedNoteID>,
        limit: Int
    ) async throws -> RelatedSearchResponse
}

public protocol ResearchRecordUseCases: Sendable {
    func snapshot() async throws -> WorkspaceResearchSnapshot
    func settle(
        _ note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord
    func activeDiscussions(noteID: UUID?) async throws -> [PortableResearchDiscussion]
    func activeDiscussion(id: UUID) async throws -> PortableResearchDiscussion
    func activeDiscussionIfPresent(id: UUID) async throws -> PortableResearchDiscussion?
    func createDiscussion(
        target: ResearchFunctionTarget,
        focalNotes: [ResearchFunctionMaterial],
        passage: CommentAnchor?,
        researcherMessage: String
    ) async throws -> PortableResearchDiscussion
    func appendDiscussionStatement(
        discussionID: UUID,
        author: PortableResearchStatementAuthor,
        attribution: String,
        text: String,
        passage: CommentAnchor?
    ) async throws -> PortableResearchDiscussion
    func finishDiscussion(discussionID: UUID) async throws -> PortableResearchRecord
    func finishedResearchRecords(noteID: UUID?) async throws -> [PortableResearchRecord]
    func critique(workNoteID: UUID) async throws -> CritiqueAssociation?
    func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation?
    func setCritiqueFindingDisposition(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        rationale: String?,
        noTextChangeRationale: String?,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation
    func completeCritiqueRound(
        workNote: VaultQualifiedNoteID,
        roundID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> CritiqueAssociation
    func discussResponseProfile() async throws -> DialogueResponseProfile
    func settings() async throws -> TriptychSettings
    func saveSettings(_ settings: TriptychSettings) async throws
    func saveDiscussResponseProfile(_ profile: DialogueResponseProfile) async throws
    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord]
    func resolveRecoveryRecord(_ id: UUID) async throws
}

public protocol ResearchCheckpointUseCases: Sendable {
    func createCheckpoint(name: String, kind: TriptychCheckpointKind) async throws -> TriptychCheckpoint
    func prepareCheckpointsLocation() async throws -> URL
    func checkpoints() async throws -> TriptychCheckpointListing
    func noteCheckpoints(for note: VaultQualifiedNoteID) async throws -> [TriptychCheckpoint]
    func checkpointNoteContent(_ checkpointID: UUID, note: VaultQualifiedNoteID) async throws -> String
    func checkpointComparison(_ checkpointID: UUID) async throws -> [TriptychCheckpointChange]
    func restoreNote(_ note: VaultQualifiedNoteID, from checkpointID: UUID, expectedRevision: DocumentFingerprint) async throws -> TriptychCheckpointRestoreResult
    func restoreCheckpoint(_ checkpointID: UUID, selection: TriptychCheckpointRestoreSelection) async throws -> TriptychCheckpointRestoreResult
}

public protocol ResearchSkillUseCases: Sendable {
    func skills() async throws -> [ResearchSkillPackage]
    func skillCatalog() async throws -> ResearchSkillCatalog
    func skillPackage(id: String) async throws -> ResearchSkillPackage
    func createSkill(id: String, source: String) async throws -> ResearchSkillPackage
    func duplicateBundledSkill(id: String, as newID: String) async throws -> ResearchSkillPackage
    func saveSkill(id: String, source: String, expectedRevision: DocumentFingerprint) async throws -> ResearchSkillPackage
    func renameSkill(id: String, to newID: String, expectedRevision: DocumentFingerprint) async throws -> ResearchSkillPackage
    func deleteSkill(id: String, expectedRevision: DocumentFingerprint) async throws
    func skillResourcePaths(id: String) async throws -> [String]
    func skillResource(id: String, relativePath: String) async throws -> String
    func skillInstructionAssembly(mode: ResearchSkillMode, requestedSkillIDs: [String], mixedPhases: [ResearchSkillAssemblyPhase]) async throws -> String
    func resolveWorkflow(_ contract: ResearchWorkflowContract) async throws -> ResolvedResearchWorkflowEnvelope
    /// Delivery-neutral draft validation. Presentation must not parse YAML or
    /// invoke `ResearchSkillInspector` directly.
    func inspectSkillDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin
    ) async -> ResearchSkillPackage
    func researchFunctionSkillBindingStatus(
        for function: ResearchFunctionID
    ) async throws -> ResearchFunctionSkillBindingStatus
    func saveResearchFunctionSkillSelection(
        _ selection: ResearchFunctionSkillSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus
    func clearResearchFunctionSkillSelection(
        for function: ResearchFunctionID,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus
    func citationMethodStatus() async throws -> ResearchCitationMethodStatus
    func activateCitationMethod(
        selection: ResearchCitationMethodSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    func clearCitationMethod(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    func adoptBundledCitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchCitationMethodStatus
    func prepareSkillMaintenance(
        _ request: ResearchSkillMaintenanceRequest
    ) async throws -> ResearchSkillMaintenancePreparation
    func applySkillMaintenance(
        _ preparation: ResearchSkillMaintenancePreparation,
        confirmationToken: ResearchSkillMaintenanceConfirmationToken
    ) async throws -> ResearchSkillMaintenanceApplyOutcome
    func skillMaintenanceSnapshots(
        packageID: String?
    ) async throws -> ResearchSkillMaintenanceSnapshotListing
    func restoreSkillMaintenance(
        snapshotID: UUID,
        expectedCurrentState: ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome
    func actionProfiles() async throws -> ResearchActionProfileSnapshot?
    func saveActionProfile(
        _ binding: ResearchActionProfileBinding,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot
    func removeActionProfile(
        actionID: ResearchActionID,
        expectedDocumentRevision: DocumentFingerprint
    ) async throws -> ResearchActionProfileSnapshot
    func saveActionProfileDocument(
        _ document: ResearchActionProfileDocument,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot
}

/// App-wide installation spans one or more Triptychs and therefore belongs to
/// the runtime rather than one active window's `ResearchUseCases` value.
public protocol ResearchSkillInstallationUseCases: Sendable {
    func stageResearcherSkillInstallation(
        from directoryURL: URL
    ) async throws -> ResearchSkillInstallationPreparation

    func installResearcherSkill(
        _ preparation: ResearchSkillInstallationPreparation,
        to triptychIDs: [UUID]
    ) async throws -> ResearchSkillInstallationOutcome

    func discardResearcherSkillInstallation(preparationID: UUID) async
}

public protocol ResearchFunctionUseCases: Sendable {
    func availableFunctions(
        for target: ResearchFunctionTarget
    ) async throws -> [ResearchFunctionAvailability]

    func materialCandidates(
        for target: ResearchFunctionTarget,
        function: ResearchFunctionID
    ) async throws -> [ResearchFunctionMaterialCandidate]

    func prepareFunction(
        _ request: ResearchFunctionRequest
    ) async throws -> ResearchFunctionPreparation

    func functionRun(
        id: UUID
    ) async throws -> ResearchFunctionPreparation

    func prepareAutomaticFidelity(
        parentRunID: UUID
    ) async throws -> AutomaticFidelityPreparation

    func completeFunction(
        _ submission: ResearchFunctionCompletionSubmission
    ) async throws -> ResearchFunctionCompletion

    func finishDiscussion(
        runID: UUID
    ) async throws -> PortableResearchRecord

    func cancelFunction(
        runID: UUID
    ) async throws

}

public protocol ResearchActionUseCases: Sendable {
    func availableActions(
        for target: ResearchActionNoteSnapshot
    ) async throws -> [ResearchActionAvailability]

    func prepareAction(
        _ request: ResearchActionExecutionRequest
    ) async throws -> ResearchActionPreparation
}

public protocol ResearchSourceAccessUseCases: Sendable {
    func sourceAccess(
        for target: ResearchFunctionTarget
    ) async throws -> ResearchSourceAccessStatus

    func bindSourceAccess(
        _ request: ResearchSourceBindingRequest
    ) async throws -> ResearchSourceReference

    func removeSourceAccess(
        for target: ResearchFunctionTarget
    ) async throws
}

/// Workspace-level research capabilities used by one window activation.
/// Feature leaves should prefer the smallest component protocol they need.
public protocol ResearchUseCases:
    ResearchRecordUseCases,
    ResearchCheckpointUseCases,
    ResearchSkillUseCases,
    ResearchFunctionUseCases,
    ResearchActionUseCases,
    ResearchSourceAccessUseCases,
    RecommendedBibliographyUseCases
{
    var skillsURL: URL { get }
    var recoveryRecordsURL: URL { get }
    var legacyResearchDataURL: URL { get }
}

public protocol SettingsUseCases: Sendable {
    func availableWorkspaces() async throws -> [TriptychAssignment]
    func registeredVaults() async throws -> [RegisteredVault]
    func defaultWorkspace() async throws -> TriptychAssignment
}

public protocol StyleUseCases: Sendable {
    func styleSnapshot() async throws -> StyleSnapshot
    func createAppearanceProfile(named name: String) async throws -> StyleSnapshot
    func selectAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func updateAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot
    func renameAppearanceProfile(_ id: UUID, to name: String) async throws -> StyleSnapshot
    func duplicateAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func removeAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func importStyleSnippet(from sourceURL: URL) async throws -> StyleSnapshot
    func setStyleSnippetEnabled(_ enabled: Bool, id: UUID) async throws -> StyleSnapshot
    func moveStyleSnippet(_ id: UUID, by offset: Int) async throws -> StyleSnapshot
    func renameStyleSnippet(_ id: UUID, to name: String) async throws -> StyleSnapshot
    func duplicateStyleSnippet(_ id: UUID) async throws -> StyleSnapshot
    func reloadStyleSnippet(_ id: UUID) async throws -> StyleSnapshot
    func removeStyleSnippet(_ id: UUID) async throws -> StyleSnapshot
    func disableAllStyleSnippets() async throws -> StyleSnapshot
    func enterStyleSafeMode(reason: String) async throws -> StyleSnapshot
    func managedStyleSnippetURL(_ id: UUID) async throws -> URL?
    func managedStylesLocation() async throws -> URL
    func obsidianAppearance(at vaultRootURL: URL) async -> ObsidianAppearanceSnapshot?
}

public struct ObsidianAppearanceSnapshot: Codable, Hashable, Sendable {
    public let vaultName: String?
    public let theme: String?
    public let showLineNumbers: Bool?
    public let defaultViewMode: String?
    public let attachmentFolderPath: String?
    public let newLinkFormat: String?

    public init(
        vaultName: String? = nil,
        theme: String? = nil,
        showLineNumbers: Bool? = nil,
        defaultViewMode: String? = nil,
        attachmentFolderPath: String? = nil,
        newLinkFormat: String? = nil
    ) {
        self.vaultName = vaultName
        self.theme = theme
        self.showLineNumbers = showLineNumbers
        self.defaultViewMode = defaultViewMode
        self.attachmentFolderPath = attachmentFolderPath
        self.newLinkFormat = newLinkFormat
    }
}

public protocol ZoteroUseCases: Sendable {
    var descriptor: ZoteroMCPTransportDescriptor { get }
    func report(environment: [String: String]) -> ZoteroMCPTransportReport
    func probe(environment: [String: String], timeout: TimeInterval) async -> ZoteroMCPTransportReport
    func handle(requestData: Data) async -> Data?
    func libraryInfo() async -> ZoteroLibraryInfo
    func refreshLibraryInfo() async throws -> ZoteroLibraryInfo
    func clearConnectionHistory() async throws
}

public protocol WorkspaceEventStreaming: Sendable {
    func events() async -> AsyncStream<WorkspaceEvent>
}

public struct StyleSnapshot: Codable, Hashable, Sendable {
    public let appearanceProfiles: [DocumentAppearanceProfile]
    public let selectedAppearanceProfileID: UUID?
    public let snippets: [CSSSnippetRecord]
    public let validationErrors: [UUID: String]
    public let readCSS: String
    public let livePreviewCSS: String
    public let safeModeReason: String?
    public let storeError: String?
    public let canModify: Bool

    public init(
        appearanceProfiles: [DocumentAppearanceProfile],
        selectedAppearanceProfileID: UUID?,
        snippets: [CSSSnippetRecord],
        validationErrors: [UUID: String],
        readCSS: String,
        livePreviewCSS: String,
        safeModeReason: String?,
        storeError: String?,
        canModify: Bool
    ) {
        self.appearanceProfiles = appearanceProfiles
        self.selectedAppearanceProfileID = selectedAppearanceProfileID
        self.snippets = snippets
        self.validationErrors = validationErrors
        self.readCSS = readCSS
        self.livePreviewCSS = livePreviewCSS
        self.safeModeReason = safeModeReason
        self.storeError = storeError
        self.canModify = canModify
    }
}

public struct CSSSnippetRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let managedFileName: String
    public var isEnabled: Bool
    public var sourceFingerprint: String?
    public var lastFailure: String?

    public init(
        id: UUID,
        name: String,
        managedFileName: String,
        isEnabled: Bool,
        sourceFingerprint: String? = nil,
        lastFailure: String? = nil
    ) {
        self.id = id
        self.name = name
        self.managedFileName = managedFileName
        self.isEnabled = isEnabled
        self.sourceFingerprint = sourceFingerprint
        self.lastFailure = lastFailure
    }
}

public enum StyleUseCaseError: LocalizedError, Sendable {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "Appearance settings are unavailable: \(reason) Reveal the managed Styles folder in Finder and repair or remove the invalid settings file before making changes."
        }
    }
}
