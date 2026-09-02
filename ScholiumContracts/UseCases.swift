import Foundation

/// Authoritative Library mutations consumed by the window-local mutation
/// coordinator. Document presentation and editor-session owners do not need
/// this capability merely to load or save one active document.
public protocol LibraryMutationUseCases: Sendable {
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
    func createUntitledNote(
        inVault vaultID: UUID,
        folderRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        try await createManagedNote(try ManagedNoteCreationRequest(
            vaultID: vaultID,
            destination: .untitled(folderRelativePath: folderRelativePath)
        ))
    }
}

public protocol DocumentUseCases: LibraryMutationUseCases {
    func snapshot() async throws -> [WorkspaceVaultSnapshot]
    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument
    func metadata(_ id: VaultQualifiedNoteID) async throws -> NoteMetadataSnapshot?
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
    /// Imports complete authored Markdown at one exact Note path without
    /// applying managed New Note YAML.
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
    /// Compare-and-swap saves researcher-owned portable Note metadata without
    /// changing Markdown or YAML source bytes.
    func saveMetadata(
        _ id: VaultQualifiedNoteID,
        fields: [String: YAMLValue],
        expectedRevision: DocumentFingerprint?
    ) async throws -> WorkspaceMutationOutcome<NoteMetadataSnapshot>
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
    func searchLibrary(query: String, limit: Int) async throws -> [ZoteroSearchHit]
}

/// Researcher-facing Analysis-to-Zotero binding, guarded empty-field fill, and
/// clear operations. Application owns the combined transaction; Agent binding
/// writes use their separately authorized Research path. Neither can write
/// Markdown or Zotero.
public protocol ZoteroBindingUseCases: Sendable {
    func zoteroBindings() async throws -> AnalysisZoteroBindingsSnapshot
    func prepareZoteroLinkAndFill(
        noteID: UUID,
        library: ZoteroLibraryMetadata,
        itemKey: String
    ) async throws -> ZoteroMetadataPlan
    func prepareZoteroMetadataRefresh(
        noteID: UUID
    ) async throws -> ZoteroMetadataPlan
    func commitZoteroMetadataPlan(
        _ plan: ZoteroMetadataPlan
    ) async throws -> ZoteroMetadataCommitResult
    func clearZoteroBinding(
        noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> AnalysisZoteroBindingMutationResult
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
