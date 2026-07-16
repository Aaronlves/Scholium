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
    func duplicate(_ id: VaultQualifiedNoteID, to destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> NoteDocument
    func save(_ id: VaultQualifiedNoteID, changeSet: NoteChangeSet, expectedRevision: DocumentFingerprint) async throws -> SaveResult
    func versions(for id: VaultQualifiedNoteID) async throws -> [VaultVersion]
    func restore(_ id: VaultQualifiedNoteID, versionID: UUID, expectedRevision: DocumentFingerprint) async throws -> SaveResult
    func move(_ id: VaultQualifiedNoteID, to destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func setAside(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func moveToTrash(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func putBack(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> TriptychMoveCommit
    func deletePermanently(_ id: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> PermanentDeletionCommit
    func recoverInterruptedTransactions() async throws -> [String]
    func classifyUnclassified(_ relativePath: String, into slot: WorkspaceVaultSlot, destinationRelativePath: String, expectedRevision: DocumentFingerprint) async throws -> UnclassifiedClassificationCommit
    func resolveIdentity(_ ambiguity: NoteIdentityAmbiguity, candidateID: UUID?) async throws -> NoteIdentityRecord
}

public protocol DiscoveryUseCases: Sendable {
    func snapshot() async throws -> WorkspaceDiscoverySnapshot
    func refresh() async throws -> WorkspaceSnapshot
    func search(_ query: SearchQuery, scope: SearchScope, limit: Int) async throws -> [SearchHit]
    func quickOpen(query: String, limit: Int) async throws -> [WorkspaceCatalogNote]
    func related(query: String, scope: SearchScope, excluding: Set<VaultQualifiedNoteID>, limit: Int) async throws -> [RelatedSearchItem]
}

public protocol ResearchRecordUseCases: Sendable {
    func snapshot() async throws -> WorkspaceResearchSnapshot
    func humanReview(noteID: UUID) async throws -> HumanReviewRecord?
    func comments(noteID: UUID) async throws -> [ResearcherComment]
    func addComment(to note: VaultQualifiedNoteID, text: String, anchor: ResearcherCommentAnchor?, expectedRevision: DocumentFingerprint) async throws -> HumanReviewRecord
    func updateComment(noteID: UUID, commentID: UUID, text: String) async throws -> HumanReviewRecord
    func setCommentResolved(noteID: UUID, commentID: UUID, resolved: Bool) async throws -> HumanReviewRecord
    func deleteComment(noteID: UUID, commentID: UUID) async throws -> HumanReviewRecord
    func reattachComment(to note: VaultQualifiedNoteID, commentID: UUID, anchor: ResearcherCommentAnchor, expectedRevision: DocumentFingerprint) async throws -> HumanReviewRecord
    func reattachComments(to note: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint) async throws -> HumanReviewRecord
    func saveHumanReviewDraft(for note: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint, qualification: NoteQualification?, reviewNote: String) async throws -> HumanReviewRecord
    func completeHumanReview(for note: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint, qualification: NoteQualification?, reviewNote: String) async throws -> HumanReviewRecord
    func dialogues(noteID: UUID) async throws -> [DialogueEntry]
    func critique(workNoteID: UUID) async throws -> CritiqueAssociation?
    func critique(critiqueRelativePath: String) async throws -> CritiqueAssociation?
    func dialogueResponseProfile() async throws -> DialogueResponseProfile
    func settings() async throws -> TriptychSettings
    func saveSettings(_ settings: TriptychSettings) async throws
    func saveDialogueResponseProfile(_ profile: DialogueResponseProfile) async throws
    func dialogueEntries() async throws -> [DialogueEntry]
    func dialogue(id: UUID) async throws -> DialogueEntry
    func appendDialogueReply(_ reply: DialogueReply, to entryID: UUID) async throws -> DialogueEntry
    func appendDialogueFollowUpComment(_ comment: DialogueFollowUpComment, to entryID: UUID) async throws -> DialogueEntry
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

    func selectFunctionMethods(
        _ submission: ResearchFunctionMethodSelectionSubmission
    ) async throws -> ResearchFunctionPreparation

    func completeFunction(
        _ submission: ResearchFunctionCompletionSubmission
    ) async throws -> ResearchFunctionCompletion

    func cancelFunction(
        runID: UUID
    ) async throws

    /// Compatibility wrappers retained while app and external integrations
    /// migrate to the delivery-neutral function boundary.
    func createDialogue(instruction: String, selectedNotes: [DialogueNoteReference], includedCommentIDs: Set<UUID>, requestedDestination: String?, responseProfile: DialogueResponseProfile?) async throws -> DialoguePreparation
    func requestCritique(for work: VaultQualifiedNoteID, expectedRevision: DocumentFingerprint, scope: CritiqueRequestScope, lens: String, selectedRanges: String, additionalInstructions: String) async throws -> CritiquePreparation
}

/// Compatibility composite used by one per-window workspace activation.
/// Feature leaves should prefer the smallest component protocol they need.
public protocol ResearchUseCases:
    ResearchRecordUseCases,
    ResearchCheckpointUseCases,
    ResearchSkillUseCases,
    ResearchFunctionUseCases
{
    var skillsURL: URL { get }
    var recoveryRecordsURL: URL { get }
}

public protocol SettingsUseCases: Sendable {
    func availableWorkspaces() async throws -> [TriptychAssignment]
    func registeredVaults() async throws -> [RegisteredVault]
    func defaultWorkspace() async throws -> TriptychAssignment
}

public protocol StyleUseCases: Sendable {
    func styleSnapshot() async throws -> StyleSnapshot
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
    func resolve(source: ZoteroSourceIdentity) async throws -> ZoteroMatchResult
    func resolveCitation(zoteroKey: String) async throws -> ZoteroItemMetadata?
    func forgetLibraryCache() async throws
}

public protocol WorkspaceEventStreaming: Sendable {
    func events() async -> AsyncStream<WorkspaceEvent>
}

public struct StyleSnapshot: Codable, Hashable, Sendable {
    public let snippets: [CSSSnippetRecord]
    public let validationErrors: [UUID: String]
    public let readCSS: String
    public let livePreviewCSS: String
    public let safeModeReason: String?
    public let storeError: String?
    public let canModify: Bool

    public init(
        snippets: [CSSSnippetRecord],
        validationErrors: [UUID: String],
        readCSS: String,
        livePreviewCSS: String,
        safeModeReason: String?,
        storeError: String?,
        canModify: Bool
    ) {
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
            "CSS snippet settings are unavailable: \(reason) Reveal the managed folder in Finder and repair or remove snippets.json before making changes."
        }
    }
}
