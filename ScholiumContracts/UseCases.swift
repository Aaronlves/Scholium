import Foundation

/// Authoritative Library mutations consumed by the window-local mutation
/// coordinator. Document presentation and editor-session owners do not need
/// this capability merely to load or save one active document.
public protocol LibraryMutationUseCases: Sendable {
    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview
    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws -> WorkspaceMutationOutcome<NoteRestructureCommit>
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
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
    func prepareFolderSystemTrash(
        inVault vaultID: UUID,
        relativePath: String
    ) async throws -> SystemTrashDeletionPreview
    func duplicate(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    func move(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit>
    func prepareSystemTrash(
        _ target: NoteMutationTarget
    ) async throws -> SystemTrashDeletionPreview
    func moveToSystemTrash(
        _ preview: SystemTrashDeletionPreview
    ) async throws -> WorkspaceMutationOutcome<SystemTrashDeletionCommit>
    func recoverInterruptedTransactions() async throws -> [String]
}

public extension LibraryMutationUseCases {
    func prepareNoteRestructure(_ request: NoteRestructureRequest) async throws -> NoteRestructurePreview {
        throw NoteRestructureError.unavailable("Note reorganization is unavailable in this workspace.")
    }
    func commitNoteRestructure(_ preview: NoteRestructurePreview) async throws -> WorkspaceMutationOutcome<NoteRestructureCommit> {
        throw NoteRestructureError.unavailable("Note reorganization is unavailable in this workspace.")
    }
    func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        try await createManagedNote(
            try ManagedNoteCreationRequest(
                vaultID: vaultID,
                destination: .untitled(folderRelativePath: folderRelativePath)
            ))
    }
}

public protocol DocumentUseCases: LibraryMutationUseCases {
    func snapshot() async throws -> [WorkspaceVaultSnapshot]
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment
    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment
    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment
    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment
    func unavailableIndexedImagePaths(in markdownSource: String) async throws -> [String]
    func sourceAttachment(for destination: String, target: SourceAttachmentTarget) async throws -> DocumentAttachmentSnapshot?
    func documentAttachments(
        for target: SourceAttachmentTarget
    ) async throws -> [DocumentAttachmentSnapshot]
    func prepareDocumentAttachment(
        at sourceURL: URL,
        to target: SourceAttachmentTarget,
        management: DocumentAttachmentManagement
    ) async throws -> PreparedSourceAttachment
    func prepareDocumentAttachmentPreview(
        attachmentID: UUID,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease
    func releaseDocumentAttachmentPreview(
        accessToken: UUID
    ) async
    func rollbackSourceAttachment(
        _ preparation: PreparedSourceAttachment
    ) async throws
    /// Imports complete authored Markdown at one exact Note path without
    /// generating or rewriting YAML.
    func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument>
    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
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
    func searchCompletions(_ request: SearchCompletionRequest) async throws -> SearchCompletionResponse
    func relatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentResponse
    /// Prepare Note-level discovery without publishing or retaining result cards.
    func prepareRelatedContent(_ request: RelatedContentRequest) async throws
    func links(
        for note: VaultQualifiedNoteID,
        direction: WorkspaceLinkDirection
    ) async throws -> [LinkGraphEdge]
    func linkDiagnostics() async throws -> [LinkGraphDiagnostic]
}

/// App-owned researcher judgments and recovery operations. External Agent
/// conversation, task lifecycle, and philosophical result ownership are not
/// represented by this capability.
public protocol ResearchUseCases: Sendable {
    func snapshot() async throws -> WorkspaceResearchSnapshot
    func settle(
        _ note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        rationale: String?
    ) async throws -> SettlementRecord
    func settings() async throws -> TriptychSettingsSnapshot
    func settingsLoadState() async throws -> TriptychSettingsLoadState
    func settingsRecoverySnapshot() async throws -> TriptychSettingsRecoverySnapshot
    func resetSettingsToDefaults(
        expectedRevision: SettingsRevision?
    ) async throws -> TriptychSettingsRecoveryResult
    func saveSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) async throws -> TriptychSettingsSnapshot
    func recoveryRecords() async throws -> [TriptychMutationRecoveryRecord]
    func resolveRecoveryRecord(_ id: UUID) async throws
}

public protocol StyleUseCases: Sendable {
    func styleSnapshot() async throws -> StyleSnapshot
    func createAppearanceProfile(named name: String) async throws -> StyleSnapshot
    func selectAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func updateAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot
    func renameAppearanceProfile(_ id: UUID, to name: String) async throws -> StyleSnapshot
    func duplicateAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func removeAppearanceProfile(_ id: UUID) async throws -> StyleSnapshot
    func appearanceConfigurationURL() async throws -> URL
    func reloadAppearanceConfiguration() async throws -> StyleSnapshot
    func restoreAppearanceDefaults() async throws -> StyleSnapshot
    func repairAppearanceProfile(_ profile: DocumentAppearanceProfile) async throws -> StyleSnapshot
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
    func libraryInfo() async -> ZoteroLibraryInfo
    func refreshLibraryInfo() async throws -> ZoteroLibraryInfo
    func clearConnectionHistory() async throws
    func searchLibrary(query: String, limit: Int) async throws -> [ZoteroSearchHit]
}

public struct StyleSnapshot: Codable, Hashable, Sendable {
    public let appearanceProfiles: [DocumentAppearanceProfile]
    public let selectedAppearanceProfileID: UUID?
    public let storeError: String?
    public let canModifyAppearance: Bool
    public let appearanceError: String?

    public init(
        appearanceProfiles: [DocumentAppearanceProfile],
        selectedAppearanceProfileID: UUID?,
        storeError: String?,
        canModifyAppearance: Bool,
        appearanceError: String?
    ) {
        self.appearanceProfiles = appearanceProfiles
        self.selectedAppearanceProfileID = selectedAppearanceProfileID
        self.storeError = storeError
        self.canModifyAppearance = canModifyAppearance
        self.appearanceError = appearanceError
    }
}

public enum StyleUseCaseError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidConfiguration(String)
    case configurationChanged

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            "Appearance settings are unavailable: \(reason) Reveal the managed Styles folder in Finder and repair or remove the invalid settings file before making changes."
        case .invalidConfiguration(let reason):
            "Could not load appearance configuration: \(reason) The current appearance has been retained."
        case .configurationChanged:
            "The appearance configuration changed outside Scholium. Reload it before saving. Your draft has been retained."
        }
    }
}
