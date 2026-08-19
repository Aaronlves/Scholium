import Foundation

public protocol DocumentUseCases: Sendable {
    func snapshot() async throws -> [WorkspaceVaultSnapshot]
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment
    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment
    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment
    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment
    func unavailableIndexedImagePaths(in markdownSource: String) async throws -> [String]
    func rollbackImageAttachment(
        _ preparation: PreparedImageAttachment
    ) async throws
    func create(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    /// Creates one note through the sole role-seed and typed-metadata owner.
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit>
    /// Creates the first unoccupied default folder in `parentRelativePath`.
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath>
    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit>
    func moveFolderToTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit>
    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    func duplicate(
        _ target: NoteLifecycleTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    /// Commits authoritative source bytes and returns before disposable
    /// workspace projections necessarily reach the same revision.
    func commit(_ id: VaultQualifiedNoteID, changeSet: NoteChangeSet, expectedRevision: DocumentFingerprint) async throws -> SaveResult
    /// Commits authoritative source bytes and waits for the matching complete
    /// derived workspace generation. Use only when the caller immediately
    /// consumes graph, identity, Search, or other same-generation projection.
    func save(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<SaveResult>
    func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func move(
        _ target: NoteLifecycleTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func setAside(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func setAside(
        _ target: NoteLifecycleTarget
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func moveToTrash(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func moveToTrash(
        _ target: NoteLifecycleTarget
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func putBack(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func putBack(
        _ target: NoteLifecycleTarget
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func deletePermanently(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<PermanentDeletionCommit>
    func deletePermanently(
        _ target: NoteLifecycleTarget
    ) async throws -> WorkspaceMutationOutcome<PermanentDeletionCommit>
    func interruptedSaveRecoveries() async throws -> [InterruptedSaveRecovery]
    func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> InterruptedSaveRecoveryContent
    func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> URL
    func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) async throws -> WorkspaceMutationOutcome<InterruptedSaveRecoveryRestoreCommit>
    func recoverInterruptedTransactions() async throws -> [String]
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord>
    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog
}

public extension DocumentUseCases {
    func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        try await createManagedNote(try ManagedNoteCreationRequest(
            vaultID: vaultID,
            destination: .untitled(folderRelativePath: folderRelativePath)
        ))
    }

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
    func createComment(
        target: ResearchFunctionTarget,
        lineReference: ResearchLineReference,
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
    func saveResearcherResponse(
        recordID: UUID,
        draft: ResearcherResponseDraft,
        expectedEvaluationRevision: UUID?,
        expectedMethodFeedbackRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> PortableResearchRecord
    func researchRecordChangeState(
        recordID: UUID
    ) async throws -> ResearchRecordChangeState
    func markCurrentNoteReviewed(
        noteID: UUID,
        expectedRevision: DocumentFingerprint,
        expectedRecordSourceManifestHash: String
    ) async throws -> PortableResearchNoteReview
    func undoResearchRecordChanges(
        recordID: UUID,
        selectedNoteIDs: Set<UUID>,
        expectedResultFingerprint: DocumentFingerprint
    ) async throws -> ResearchRecordChangesUndoResult
    func issueMethodImprovementHandoff(
        recordID: UUID,
        validity: TimeInterval
    ) async throws -> ResearchAgentHandoff
    func setResearchRecordRecommendationDisposition(
        recordID: UUID,
        recommendationID: UUID,
        status: ResearchLiteratureRecommendationDispositionStatus
    ) async throws -> PortableResearchRecord
    func setResearchRecordRecommendationNote(
        recordID: UUID,
        recommendationID: UUID,
        note: String?
    ) async throws -> PortableResearchRecord
    func deleteResearchRecordPermanently(id: UUID) async throws
    func researchRecordComparison(
        recordID: UUID,
        noteID: UUID
    ) async throws -> ExactSourceComparison
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
    func settings() async throws -> TriptychSettingsSnapshot
    func settingsLoadState() async throws -> TriptychSettingsLoadState
    func saveSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot
    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord]
    func resolveRecoveryRecord(_ id: UUID) async throws
}

public extension ResearchRecordUseCases {
    /// Test and preview adapters that only model valid current settings may
    /// inherit this projection. Production owners implement the typed load
    /// state so damaged or unsupported source is never flattened.
    func settingsLoadState() async throws -> TriptychSettingsLoadState {
        .current(try await settings())
    }
}

public protocol ResearchConfigurationUseCases: Sendable {
    func researchSkillRegistrations() async throws -> ResearchSkillRegistrationSnapshot
    func saveResearchSkillRegistrations(
        _ document: ResearchSkillRegistrationDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillRegistrationSnapshot
    func academicActionProfiles() async throws -> ResearchAcademicProfileSnapshot
    func saveAcademicActionProfiles(
        _ document: ResearchAcademicProfileDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchAcademicProfileSnapshot
    func collaborationPolicy() async throws -> ResearchCollaborationPolicySnapshot
    func saveCollaborationPolicy(
        _ document: ResearchCollaborationPolicyDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchCollaborationPolicySnapshot
    func researchMethod(for actionID: ResearchActionID) async throws -> ResearchMethodSnapshot
    func saveResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    func restoreDefaultResearchMethod(
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot
    func philosophicalPractices() async throws -> [ResearchPracticeSnapshot]
    func createPhilosophicalPractice(
        title: String,
        source: String
    ) async throws -> ResearchPracticeSnapshot
    func savePhilosophicalPractice(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot
}

public protocol ResearchActionUseCases: Sendable {
    func availableActions(
        for target: ResearchActionNoteSnapshot
    ) async throws -> [ResearchActionAvailability]

    func prepareAction(
        _ request: ResearchActionExecutionRequest
    ) async throws -> ResearchActionPreparation

    func materialCandidates(
        for target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID
    ) async throws -> [ResearchActionNoteSnapshot]

    func actionRun(id: UUID) async throws -> ResearchActionPreparation

    func cancelAction(runID: UUID) async throws

    func issueAgentHandoff(
        runID: UUID,
        validity: TimeInterval
    ) async throws -> ResearchAgentHandoff

    func prepareResynthesis(
        _ request: ResearchActionExecutionRequest,
        context: MaterialChangedSinceUseAttentionContext
    ) async throws -> ResearchActionPreparation
}

public protocol ResearchSourceAccessUseCases: Sendable {
    func sourceAccess(
        for target: ResearchFunctionTarget
    ) async throws -> ResearchSourceAccessStatus

    func bindSourceAccess(
        _ request: ResearchSourceBindingRequest
    ) async throws -> ResearchSourceReference

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
    func libraries() async throws -> [ZoteroLibraryMetadata]
    func searchLibrary(query: String, limit: Int) async throws -> [ZoteroSearchHit]
}

/// Revision-checked portable Analysis-to-Zotero relationship mutations. This
/// authority is separate from Zotero's read-only metadata transport and from
/// Markdown document writes.
public protocol ZoteroBindingUseCases: Sendable {
    func zoteroBindings() async throws -> AnalysisZoteroBindingsSnapshot
    func setZoteroBinding(
        _ binding: AnalysisZoteroBinding,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult
    func clearZoteroBinding(
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult
}

/// Delivery-neutral MCP request handling for the local Agent coordination
/// bridge. The CLI owns stdio framing; Application owns bridge discovery,
/// authentication, and request execution.
public protocol AgentBridgeUseCases: Sendable {
    func start(
        triptychID: UUID,
        request: ResearchAgentStartRequest
    ) async throws -> ResearchAgentStartedSession
    func pair(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode
    ) async throws -> ResearchConnectionCredential
    func context(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) async throws -> ResearchAuthenticatedRunContext
    func query(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        request: ResearchContextRequest
    ) async throws -> ResearchContextResponse
    func extendWriteSet(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchWriteSetExtensionIntent
    ) async throws -> ResearchWriteSetExtensionResult
    func writeDocument(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchDocumentWriteIntent
    ) async throws -> ResearchDocumentWriteResult
    func writeZoteroBinding(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchZoteroBindingWriteIntent
    ) async throws -> ResearchZoteroBindingWriteResult
    func resolveWriteConflict(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        intent: ResearchWriteConflictResolutionIntent
    ) async throws -> ResearchWriteConflictResolutionResult
    func submitResult(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        submission: ResearchAgentResultSubmission
    ) async throws -> ResearchAgentResultReceipt
    func continueResearch(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationResult
    func methodImprovementContext(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) async throws -> ResearchMethodImprovementContext
    func submitMethodImprovement(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential,
        submission: ResearchMethodImprovementSubmission
    ) async throws -> ResearchMethodImprovementReceipt
    func end(
        run: ResearchRunLocator,
        credential: ResearchConnectionCredential
    ) async throws -> ResearchRunEndReceipt
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
