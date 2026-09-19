import AppKit
import Combine
import QuartzCore
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers
import notify

// MARK: - App State

@MainActor
final class WindowModel: ObservableObject {
    enum WindowNavigationError: LocalizedError {
        case noteUnavailable(String)
        case vaultUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .noteUnavailable(let path):
                String(
                    localized: "The visited note '\(path)' is no longer available. Scholium kept the current document open.", table: "Localizable",
                    bundle: .module)
            case .vaultUnavailable(let name):
                String(
                    localized: "The \(name) vault is not available in this Triptych. Scholium kept the current document open.", table: "Localizable",
                    bundle: .module)
            }
        }
    }

    enum DocumentTransitionPreparation {
        case saveOpenDocuments
        case preserveSelectedDocument
        case operationOnly
    }

    enum DocumentTabActivation {
        case place(DocumentTabPlacement)
        case preserveTabMembership
    }

    struct StagedWorkspaceLibrarySelection {
        let registeredVault: RegisteredVault
        let workspace: WorkspaceVaultSlot
        let sourceScope: LibrarySourceScope
        let vaultSnapshot: WorkspaceVaultSnapshot
        let vaultConfig: VaultConfig
        let notes: [WindowDocumentLocation]
        let request: DiscoveryLibraryRequest?
    }

    var windowSessionID = UUID()
    let nativeWindowID: UUID

    // MARK: Published State
    @Published var vaultConfig: VaultConfig?
    @Published var currentRegisteredVault: RegisteredVault?
    @Published var currentVaultRole: VaultRole = .other
    @Published private(set) var libraryFocusRequestGeneration: UInt64 = 0
    @Published var triptychSettings = TriptychSettings()
    let presentationRouter = WindowPresentationRouter()
    let shellState = WindowShellState()
    let writingContinuationContextCache = WritingContinuationContextCache()
    lazy var discoveryController = DiscoveryController(
        shellState: shellState
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var searchController = WindowSearchController(
        discoveryController: discoveryController,
        dependencies: .init(
            loadSavedSearches: { [workspaceStore] in
                try await workspaceStore.savedSearches()
            },
            saveSavedSearches: { [workspaceStore] searches in
                try await workspaceStore.saveSavedSearches(searches)
            },
            recoverSavedSearches: { [workspaceStore] in
                try await workspaceStore.preserveUnreadableSavedSearchesAndReset()
            },
            executionContext: { [weak self] state in
                guard let self else {
                    throw DiscoverySearchExecutionError.workspaceUnavailable
                }
                return DiscoverySearchExecutionContext(
                    workspaceIsAvailable: self.workspaceAssignment != nil,
                    currentNoteSnapshot: state.scope == .thisNote
                        ? try await self.currentSearchSourceSnapshot()
                        : nil,
                    currentVaultID: self.currentRegisteredVault?.id
                )
            },
            resultEvidence: { [weak self] result, scope in
                guard let self else {
                    return WindowSearchResultEvidence(
                        freshness: nil,
                        fingerprint: nil
                    )
                }
                return await self.currentSearchResultEvidence(
                    for: result,
                    scope: scope
                )
            },
            open: { [weak self] result, disposition in
                await self?.openSearchSelection(result, disposition: disposition)
            },
            hasCurrentNote: { [weak self] in self?.currentNote != nil },
            reportInformation: { [weak self] message in
                self?.reportOperationIssue(message, kind: .information)
            },
            reportLoadFailure: { [weak self] message in
                self?.vaultError = message
            },
            reportSaveFailure: { [weak self] message in
                self?.reportOperationIssue(message, kind: .error)
            },
            setAvailabilityStatus: { [weak self] status in
                guard let self else { return }
                if let status {
                    self.refreshStatusText = status
                } else if let refreshStatusText = self.refreshStatusText,
                    ["Search unavailable", "Search failed"].contains(
                        refreshStatusText
                    )
                {
                    self.refreshStatusText = nil
                }
            },
            reportCatalogFailure: { [weak self] message in
                self?.workspaceProjectionController.reportCatalogError(message)
            },
            loadTermGroups: { [workspaceStore] in try await workspaceStore.searchTermGroups() },
            saveTermGroup: { [workspaceStore] group, expected in try await workspaceStore.saveSearchTermGroup(group, replacing: expected) },
            deleteTermGroup: { [workspaceStore] group in try await workspaceStore.deleteSearchTermGroup(group) }
        )
    )
    lazy var documentController = DocumentController { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var libraryMutationController = WindowLibraryMutationController(
        dependencies: WindowLibraryMutationDependencies(
            context: { [weak self] in
                guard let self,
                    let assignment = self.workspaceAssignment,
                    let vault = self.currentRegisteredVault
                else { return nil }
                return WindowLibraryMutationContext(
                    assignmentID: assignment.id,
                    vault: vault,
                    sourceScope: self.noteSourceScope
                )
            },
            enqueueDocumentTransition: { [weak self] operation, didFail, didFinish in
                self?.enqueueCurrencyAwareDocumentTransition(
                    preservingCurrentEditorState: false,
                    operation,
                    didFail: didFail,
                    didFinish: didFinish
                )
            },
            flushEditors: { [weak self] triptychID in
                guard let self else { throw CancellationError() }
                try await self.editorFlushCoordinator.flushAllEditors(in: triptychID)
            },
            flushActiveTarget: { [weak self] target in
                guard let self else { throw CancellationError() }
                try await self.flushRegisteredEditorIfMutatingActiveDocument(target)
            },
            expectedRevision: { [weak self] target in
                guard let self else { throw CancellationError() }
                return try self.mutationExpectedRevision(for: target)
            },
            captureBatchTargets: { [weak self] targets in
                guard let self else { throw CancellationError() }
                return try targets.map { target in
                    guard
                        let snapshot = self.workspaceProjectionController.vaultSnapshot(id: target.documentID.vaultID)?
                            .documents.first(where: { $0.id == target.documentID && $0.stableIdentity.resolvedID == target.stableNoteID }),
                        snapshot.capabilities.canEditSource
                    else { throw LibraryNoteBatchError.selectionChanged }
                    return NoteMutationTarget(documentID: snapshot.id, stableNoteID: target.stableNoteID, revision: snapshot.fingerprint)
                }
            },
            committedNoteCreated: { [weak self] outcome, isCurrent in
                await self?.publishCommittedNoteCreation(outcome, isCurrent: isCurrent)
            },
            committedFolderCreated: { [weak self] outcome in
                await self?.publishCommittedFolderCreation(outcome)
            },
            committedFolderMoved: { [weak self] outcome in
                await self?.publishCommittedFolderMove(outcome)
            },
            committedNoteDuplicated: { [weak self] outcome, target, destination in
                await self?.publishCommittedNoteDuplication(
                    outcome,
                    target: target,
                    destination: destination
                )
            },
            committedNoteMoved: { [weak self] outcome, target in
                await self?.publishCommittedNoteMove(outcome, target: target)
            },
            committedSystemTrash: { [weak self] preview, outcome in
                await self?.publishSystemTrashResult(preview, outcome: outcome)
            },
            importedDocumentsCommitted: { [weak self] vault in
                guard let self else { throw CancellationError() }
                try await self.refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                if self.currentRegisteredVault?.id == vault.id {
                    try await self.browseRegisteredVault(vault)
                }
            },
            presentImportOutcome: { [weak self] outcome in
                self?.presentMarkdownImportOutcome(outcome)
            },
            presentSystemTrash: { [weak self] preview in
                self?.presentationRouter.present(.systemTrash(preview))
            },
            clearPresentedAlert: { [weak self] in
                self?.presentationRouter.alert = nil
            },
            reportError: { [weak self] message in
                self?.reportOperationIssue(message, kind: .error)
            },
            reportInformation: { [weak self] message in
                self?.reportOperationIssue(message, kind: .information)
            },
            refreshTransactionRecovery: { [weak self] in
                await self?.refreshTransactionRecoveryRecords()
            }
        )
    )
    let documentTabController = DocumentTabController()
    let documentNavigationHistoryController = DocumentNavigationHistoryController()
    lazy var researchController = ResearchController(
        shellState: shellState,
        selectedDocuments: documentController.$selectedDocument.eraseToAnyPublisher()
    ) { [weak self] intent in
        self?.handleWindowIntent(intent)
    }
    lazy var workspaceProjectionController = WindowWorkspaceProjectionController(
        loadCatalog: { [weak self] in
            guard let self else {
                throw DiscoverySearchExecutionError.workspaceUnavailable
            }
            return try await self.discoveryController.discoverySnapshot().catalog
        }
    )
    private let libraryTreeProjectionCache = LibraryTreeProjectionCache()
    lazy var commandObservation = WindowCommandObservation(
        shellState: shellState,
        workspaceController: windowWorkspaceController,
        libraryMutationController: libraryMutationController,
        discoveryController: discoveryController,
        documentController: documentController,
        documentTabController: documentTabController,
        documentNavigationHistoryController: documentNavigationHistoryController,
        workspaceProjectionController: workspaceProjectionController
    )
    let attentionPresentationState = AttentionPresentationState()
    lazy var attentionPopoverSession = AttentionPopoverSession(
        presentation: attentionPresentationState,
        discoveryController: discoveryController,
        workspaceController: windowWorkspaceController,
        projectionController: workspaceProjectionController,
        dismissalDays: triptychSettings.attentionDismissalDays,
        dependencies: .init(
            dismissalDaysChanges:
                $triptychSettings
                .map(\.attentionDismissalDays)
                .eraseToAnyPublisher(),
            settlementRequirementChanges: researchController.$researchSnapshot
                .map { $0?.settlementRequirements ?? [] }
                .eraseToAnyPublisher(),
            agentChangeChanges: researchController.$agentChanges
                .eraseToAnyPublisher(),
            agentChangeErrorChanges: researchController.$agentChangesError
                .eraseToAnyPublisher(),
            refresh: { [weak self] in
                guard let self else { return }
                await self.refreshWorkspaceCatalog()
                _ = try? await self.researchController.loadAgentChanges()
            },
            showAgentChange: { [weak self] changeID in
                self?.presentationRouter.present(
                    .agentChanges(scope: .exact(changeID))
                )
            }
        )
    )

    var sidebarVisible: Bool {
        get { shellState.libraryVisible }
        set { shellState.recordLibraryVisibility(newValue) }
    }

    var hasCompletedInitialRestore: Bool {
        shellState.hasCompletedInitialRestore
    }

    var colorScheme: WindowColorSchemeChoice {
        get { shellState.colorScheme }
        set { shellState.colorScheme = newValue }
    }

    var documentTextScale: Double {
        get { shellState.documentTextScale }
        set { shellState.setDocumentTextScale(newValue) }
    }

    var refreshStatusText: String? {
        get { shellState.refreshStatusText }
        set { shellState.setRefreshStatus(newValue) }
    }

    var windowSessionPersistenceError: String? {
        shellState.windowSessionPersistenceError
    }

    var workspaceAssignment: TriptychAssignment? {
        windowWorkspaceController.state.assignment
    }

    var registeredVaults: [RegisteredVault] {
        windowWorkspaceController.state.registeredVaults
    }

    var registeredTriptychs: [TriptychAssignment] {
        windowWorkspaceController.state.registeredTriptychs
    }

    var activeTriptychServicesID: UUID? {
        windowWorkspaceController.state.activeServicesID
    }

    var notes: [WindowDocumentLocation] { workspaceProjectionController.notes }

    func libraryTreeProjection(
        preorderedNotes: [WindowDocumentLocation],
        folderRelativePaths: [String]
    ) -> LibraryTreeProjectionVersion {
        libraryTreeProjectionCache.projection(
            preorderedNotes: preorderedNotes,
            // With Note filters active, only matching Notes supply ancestors.
            // Keep the real empty-folder inventory for the unfiltered Library.
            folderRelativePaths: discoveryController.library.filters == DiscoveryFilterState() ? folderRelativePaths : []
        )
    }

    var availablePropertyFilterOptions: WindowPropertyFilterOptions {
        workspaceProjectionController.propertyFilterOptions
    }
    var allTags: [String] { workspaceProjectionController.tags }
    var documentRevisions: [String: DocumentFingerprint] {
        workspaceProjectionController.documentRevisions
    }
    var workspaceCatalog: WorkspaceCatalogSnapshot? {
        workspaceProjectionController.catalog
    }
    var isRefreshingWorkspaceCatalog: Bool {
        workspaceProjectionController.isRefreshingCatalog
    }
    var derivedRefreshStatus: WorkspaceDerivedRefreshStatus? {
        workspaceProjectionController.derivedRefreshStatus
    }
    var workspaceCatalogError: String? {
        workspaceProjectionController.catalogError
    }
    // Window-level projections for Library leaves. DiscoveryController remains
    // the sole mutable owner.
    var noteSourceScope: LibrarySourceScope {
        discoveryController.library.sourceScope
    }

    var isNeedsAttentionFilter: Bool {
        get { discoveryController.library.filters.needsAttention }
        set { updateDiscoveryFilters { $0.needsAttention = newValue } }
    }

    var isLinkAnnotationsFilter: Bool {
        get { discoveryController.library.filters.hasLinkAnnotations }
        set { updateDiscoveryFilters { $0.hasLinkAnnotations = newValue } }
    }

    var isMalformedMetadataFilter: Bool {
        get { discoveryController.library.filters.hasMalformedMetadata }
        set { updateDiscoveryFilters { $0.hasMalformedMetadata = newValue } }
    }

    var selectedTag: String? {
        get { discoveryController.library.filters.tag }
        set { updateDiscoveryFilters { $0.tag = newValue } }
    }

    var selectedAuthor: String? {
        get { discoveryController.library.filters.author }
        set { updateDiscoveryFilters { $0.author = newValue } }
    }

    var selectedPropertyKey: String? {
        get { discoveryController.library.filters.propertyKey }
        set { updateDiscoveryFilters { $0.propertyKey = newValue } }
    }

    var selectedPropertyValue: String? {
        get { discoveryController.library.filters.propertyValue }
        set { updateDiscoveryFilters { $0.propertyValue = newValue } }
    }

    private func updateDiscoveryFilters(
        _ update: (inout DiscoveryFilterState) -> Void
    ) {
        var filters = discoveryController.library.filters
        update(&filters)
        discoveryController.replaceFilters(filters)
    }

    // Triptych-wide immutable semantic graph forwarded from the exact-window
    // Workspace projection owner.
    var linkGraph: GraphSnapshot? {
        workspaceProjectionController.linkGraph
    }

    // MARK: Window Presentation

    func registerNoteDisplayWindow(_ window: AgentNoteDisplayWindow) {
        workspaceStore.registerNoteDisplayWindow(id: nativeWindowID, window: window)
    }

    func unregisterNoteDisplayWindow() {
        workspaceStore.unregisterNoteDisplayWindow(id: nativeWindowID)
    }

    var chatController: AgentChatController? {
        workspaceAssignment.map { workspaceStore.chatRegistry.controller(for: $0.id) }
    }

    var canToggleResearchInspector: Bool {
        !isDetachedDocumentWindow && (currentNote != nil || shellState.inspector.isVisible)
    }

    var researchInspectorVisible: Bool {
        get { researchController.inspector.isVisible }
        set { researchController.showResearchInspector(newValue) }
    }

    var noteFileRequest: NoteFileRequest? {
        get {
            guard case .noteFileOperation(let request) = presentationRouter.sheet else { return nil }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.noteFileOperation(newValue))
            } else if case .noteFileOperation = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var folderFileRequest: FolderFileRequest? {
        get {
            guard case .folderFileOperation(let request) = presentationRouter.sheet else {
                return nil
            }
            return request
        }
        set {
            if let newValue {
                presentationRouter.present(.folderFileOperation(newValue))
            } else if case .folderFileOperation = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var isLoading: Bool {
        get { presentationRouter.presentsOverlay(.loading) }
        set { presentationRouter.setOverlay(.loading, isPresented: newValue) }
    }

    var showMarkdownImporter: Bool {
        get { presentationRouter.fileImport == .markdown }
        set { presentationRouter.fileImport = newValue ? .markdown : nil }
    }

    var vaultError: String? {
        get { presentationRouter.alert?.message }
        set { presentationRouter.alert = newValue.map(WindowAlertRoute.actionFailure) }
    }

    var selectedIdentityAmbiguity: NoteIdentityAmbiguity? {
        get {
            guard case .identityResolution(let ambiguity) = presentationRouter.sheet else { return nil }
            return ambiguity
        }
        set {
            if let newValue {
                presentationRouter.present(.identityResolution(newValue))
            } else if case .identityResolution = presentationRouter.sheet {
                presentationRouter.dismissSheet()
            }
        }
    }

    var showTransactionRecovery: Bool {
        get {
            guard case .transactionRecovery = presentationRouter.sheet else { return false }
            return true
        }
        set {
            if newValue {
                presentationRouter.present(.transactionRecovery)
            } else {
                presentationRouter.dismissSheet(if: "transaction-recovery")
            }
        }
    }

    // MARK: Services
    let cssSnippetStore: CSSSnippetStore
    var requestedTriptychID: UUID? {
        windowWorkspaceController.requestedTriptychID
    }
    let requestedInitialDocument: VaultNoteReference?
    private var didOpenRequestedInitialDocument = false
    var presentedOpeningRuntimeIdentity: TriptychRuntimeIdentity?
    var projectionRefreshToken: UInt64 = 0
    let workspaceStore: WorkspaceStore
    var isDetachedDocumentWindow = false
    weak var nativeWindowCoordinator: WorkspaceWindowCoordinator?
    @Published var transferInProgress = false {
        didSet { nativeWindowCoordinator?.setTransferInProgress(transferInProgress) }
    }
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    let documentTransitionCoordinator = DocumentTransitionCoordinator()
    var documentTransitionIssueID: UUID?
    let editorFlushCoordinator: WindowEditorFlushCoordinator
    let windowSessionPersistenceCoordinator: WindowSessionPersistenceCoordinator
    lazy var windowCloseCoordinator = WindowCloseCoordinator(
        lifecyclePolicy: lifecyclePolicy,
        persistenceCoordinator: windowSessionPersistenceCoordinator,
        flushContent: { [weak self] in
            guard let self else {
                throw ScholiumWindowLifecycleError.unregisteredBeforeReady
            }
            guard !self.transferInProgress else { throw CancellationError() }
            try await self.flushRegisteredEditorIfNeeded(capturingEditorState: true)
            try await self.chatController?.flushPersistence()
        },
        presentationSnapshot: { [weak self] in
            guard let self,
                self.didRestoreWindowSession,
                !self.isRestoringWindowSession
            else { return nil }
            return self.currentWindowSessionSnapshot()
        },
        recordPersistenceFailure: { [weak self] message in
            guard let self else { return }
            if let message {
                self.shellState.recordWindowSessionPersistenceFailure(message)
            } else {
                self.shellState.clearWindowSessionPersistenceFailure()
            }
        },
        finalizeDependencies: { [weak self] in
            guard let self else { return }
            self.libraryMutationController.unbind()
            self.researchController.unbind()
            self.windowWorkspaceController.cancelAll()
            self.documentTransitionCoordinator.cancelAll()
            self.libraryRevealTask?.cancel()
            self.libraryRevealTask = nil
            self.editorFlushCoordinator.shutdown()
        }
    )
    let windowWorkspaceController: WindowWorkspaceController
    var workspaceCancellables: Set<AnyCancellable> = []
    var libraryRevealTask: Task<Void, Never>?
    @Published var requestedWorkspaceSelection: WorkspaceVaultSlot?
    var isRestoringWindowSession = false
    var didRestoreWindowSession = false
    /// Read by the identity refresh commands in `WindowNoteIdentityActions`;
    /// the stored generation itself has to live with the class.
    var identityRefreshGeneration: UInt64 = 0
    let documentPresentationDidChange = PassthroughSubject<Void, Never>()
    private var performanceModeNotificationTokens: [Int32] = []

    init(
        workspaceStore: WorkspaceStore,
        nativeWindowID: UUID? = nil,
        requestedTriptychID: UUID? = nil,
        requestedInitialDocument: VaultNoteReference? = nil,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
        finalWindowSessionSaver: WindowSessionPersistenceCoordinator.Saver? = nil
    ) {
        PerformanceProbe.shared.markWarmLibraryWindowModelInitializationStarted()
        let resolvedWindowID = nativeWindowID ?? UUID()
        self.nativeWindowID = resolvedWindowID
        windowSessionID = resolvedWindowID
        self.workspaceStore = workspaceStore
        self.lifecyclePolicy = lifecyclePolicy
        self.editorFlushCoordinator = WindowEditorFlushCoordinator(
            windowID: resolvedWindowID,
            registry: workspaceStore
        )
        self.windowSessionPersistenceCoordinator = WindowSessionPersistenceCoordinator(
            store: workspaceStore,
            lifecyclePolicy: lifecyclePolicy,
            finalSaver: finalWindowSessionSaver
        )
        self.windowWorkspaceController = WindowWorkspaceController(
            workspaceStore: workspaceStore,
            requestedTriptychID: requestedTriptychID
        )
        self.requestedInitialDocument = requestedInitialDocument
        if (requestedInitialDocument != nil
            || ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"] != nil)
            && !PerformanceProbe.shared.measuresEditorRetainedMemory
        {
            ScholiumWebKitProcessPrewarmer.shared.start()
        }
        cssSnippetStore = workspaceStore.cssSnippetStore
        windowWorkspaceController.bindDependencies(
            WindowWorkspaceDependencies(
                installSession: { [weak self] capabilities, snapshot in
                    guard let self else { throw CancellationError() }
                    return try await self.installWindowWorkspaceSession(
                        capabilities: capabilities,
                        snapshot: snapshot
                    )
                },
                didRemoveRegistration: { [weak self] assignment in
                    guard let self else { return }
                    let removedVaultIDs = Set(assignment.vaults.values.map(\.id))
                    if self.currentRegisteredVault.map({ removedVaultIDs.contains($0.id) }) == true {
                        self.currentRegisteredVault = nil
                        self.vaultConfig = nil
                    }
                },
                reportInformation: { [weak self] message in
                    self?.reportOperationIssue(message, kind: .information)
                }
            )
        )
        if PerformanceProbe.shared.isEnabled,
            ProcessInfo.processInfo.arguments.contains(
                "--scholium-performance-editor-mode-notifications"
            )
        {
            let requests = [
                "com.scholium.qa.performance-editor-mode.live-preview",
                "com.scholium.qa.performance-editor-mode.source",
                "com.scholium.qa.performance-editor-activation",
                "com.scholium.qa.performance-editor-review",
                "com.scholium.qa.performance-editor-cached-preview",
                "com.scholium.qa.performance-editor-visible-projection",
                "com.scholium.qa.performance-editor-cjk-correctness",
            ]
            for name in requests {
                var token: Int32 = 0
                let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handlePerformanceEditorRequest(name)
                    }
                }
                if status == NOTIFY_STATUS_OK {
                    performanceModeNotificationTokens.append(token)
                }
            }
        }
        searchController.loadSavedSearches()
        startWorkspaceObservers()
    }

    deinit {
        libraryRevealTask?.cancel()
        for token in performanceModeNotificationTokens {
            notify_cancel(token)
        }
    }

    // MARK: Computed Properties
    var sourceMutationGeneration: UInt64 {
        get { documentController.sourceMutationGeneration }
        set { documentController.sourceMutationGeneration = newValue }
    }

    var lastSaveError: String? {
        get { documentController.lastSaveError }
        set { documentController.setSaveError(newValue) }
    }

    var requestPresentationMode: NotePresentationMode? {
        get { documentController.requestedPresentationMode }
        set { documentController.requestedPresentationMode = newValue }
    }

    var transactionRecoveryRecords: [TriptychMutationRecoveryRecord] {
        get { researchController.transactionRecoveryRecords }
        set { researchController.transactionRecoveryRecords = newValue }
    }

    var transactionRecoveryError: String? {
        get { researchController.transactionRecoveryError }
        set { researchController.transactionRecoveryError = newValue }
    }

    var interruptedSaveRecoveries: [InterruptedSaveRecovery] {
        get { researchController.interruptedSaveRecoveries }
        set { researchController.interruptedSaveRecoveries = newValue }
    }

    var interruptedSaveRecoveryError: String? {
        get { researchController.interruptedSaveRecoveryError }
        set { researchController.interruptedSaveRecoveryError = newValue }
    }

    var selectedDocumentPath: String? {
        documentController.selectedDocumentPath
    }

    var currentDocumentDescriptor: WindowDocumentDescriptor? {
        documentController.activeDocument
    }

    var currentDocumentVaultID: UUID? {
        if let vaultID = documentController.selectedDocument?.vaultID {
            return vaultID
        }
        guard noteSourceScope == .library,
            currentNote != nil
        else { return nil }
        // Identity-recovery notes deliberately have no stable document
        // descriptor yet, but they remain vault-qualified by the Library
        // projection that selected them. Preserve that vault ownership so the
        // Document surface can present the authoritative recovery state
        // without inventing a stable note identity or enabling writes.
        return currentRegisteredVault?.id
    }

    var currentDocumentVaultRole: VaultRole {
        if let role = currentDocumentDescriptor?.reference.vaultRole {
            return role
        }
        guard let vaultID = documentController.selectedDocument?.vaultID else { return .other }
        return workspaceAssignment?.vaults.values.first { $0.id == vaultID }?.role ?? .other
    }

    var currentDocumentVault: RegisteredVault? {
        guard let vaultID = currentDocumentVaultID else { return nil }
        return workspaceAssignment?.vaults.values.first { $0.id == vaultID }
    }

    var currentDocumentVaultSnapshot: WorkspaceVaultSnapshot? {
        guard let vaultID = currentDocumentVaultID else { return nil }
        return workspaceProjectionController.vaultSnapshot(id: vaultID)
    }

    var currentDocumentNotes: [WindowDocumentLocation] {
        guard let snapshot = currentDocumentVaultSnapshot else {
            return currentNote.map { [$0] } ?? []
        }
        return snapshot.documents
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)
    }

    var currentLibraryFolders: [String] {
        guard let vaultID = currentRegisteredVault?.id,
            let snapshot = workspaceProjectionController.vaultSnapshot(
                id: vaultID
            )
        else { return [] }
        return snapshot.folders
            .map(\.rawValue)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var currentLibraryPathComparisonPolicy: VaultPathComparisonPolicy? {
        guard let vaultID = currentRegisteredVault?.id else { return nil }
        return
            workspaceProjectionController
            .vaultSnapshot(id: vaultID)?
            .pathComparisonPolicy
    }

    var currentDocumentIdentityByPath: [String: UUID] {
        guard let snapshot = currentDocumentVaultSnapshot else {
            guard let descriptor = currentDocumentDescriptor else { return [:] }
            return [descriptor.reference.relativePath: descriptor.sessionKey.noteID]
        }
        return Dictionary(
            uniqueKeysWithValues: snapshot.documents.compactMap { note in
                note.stableIdentity.resolvedID.map { (note.id.relativePath, $0) }
            })
    }

    var currentDocumentRevisions: [String: DocumentFingerprint] {
        Dictionary(
            uniqueKeysWithValues: currentDocumentNotes.map {
                ($0.relativePath, $0.document.fingerprint)
            })
    }

    var currentNote: WindowDocumentLocation? {
        if let active = documentController.activeSnapshot {
            return .workspace(active)
        }
        if let descriptor = currentDocumentDescriptor,
            let snapshot = workspaceProjectionController.cachedNote(
                vaultID: descriptor.reference.vaultID,
                stableNoteID: descriptor.sessionKey.noteID,
                relativePath: descriptor.reference.relativePath
            )
        {
            return .workspace(snapshot)
        }
        guard let selected = documentController.selectedDocument else { return nil }
        if let vaultID = selected.vaultID {
            return workspaceProjectionController.cachedNote(
                vaultID: vaultID, stableNoteID: selected.sessionKey?.noteID,
                relativePath: selected.relativePath
            ).map(WindowDocumentLocation.workspace)
        }
        return nil
    }

    var selectedDocument: VaultQualifiedNoteID? {
        guard let descriptor = currentDocumentDescriptor else { return nil }
        return VaultQualifiedNoteID(
            vaultID: descriptor.reference.vaultID,
            relativePath: descriptor.reference.relativePath
        )
    }

    var canEditCurrentNote: Bool {
        currentDocumentCapabilities.canEditSource
    }

    var currentDocumentCapabilities: DocumentCapabilities {
        if let capabilities = currentNote?.workspaceSnapshot?.capabilities {
            return capabilities
        }
        guard currentNote != nil else {
            return DocumentCapabilities(
                role: currentDocumentVaultRole,
                identity: .unresolved
            )
        }
        return DocumentCapabilities(
            role: currentDocumentVaultRole,
            identity: .unresolved
        )
    }

    #if DEBUG
        func waitForPendingDocumentTransitionsForTesting() async {
            await documentTransitionCoordinator.waitForIdle()
        }
    #endif

    // MARK: Actions

    /// Mirrors the native Sidebar state for focused labels and next-session
    /// restoration. Researcher intents enter through WorkspaceWindowActions.
    func recordLibraryVisibility(_ visible: Bool) {
        guard sidebarVisible != visible else { return }
        sidebarVisible = visible
    }

    func openRequestedInitialDocumentIfNeeded() {
        guard !didOpenRequestedInitialDocument,
            workspaceAssignment != nil,
            let requestedInitialDocument
        else { return }
        didOpenRequestedInitialDocument = true
        requestOpenNote(requestedInitialDocument, disposition: .replaceCurrent)
    }

    /// Mirrors the native Inspector state without driving its geometry.
    func recordResearchInspectorVisibility(_ visible: Bool) {
        guard visible != researchInspectorVisible else { return }
        researchInspectorVisible = visible
    }

    func migrateInMemoryPath(
        from sourcePath: String,
        to destinationPath: String,
        noteID: UUID,
        identityResolved: Bool,
        vaultID: UUID
    ) {
        if currentRegisteredVault?.id == vaultID {
            noteIdentityByPath[sourcePath] = nil
            if identityResolved {
                noteIdentityByPath[destinationPath] = noteID
            }
        }
        if let descriptor = currentDocumentDescriptor,
            descriptor.reference.vaultID == vaultID,
            descriptor.reference.relativePath == sourcePath,
            descriptor.sessionKey.noteID == noteID
        {
            documentController.updateDocumentProjection(
                WindowDocumentDescriptor(
                    sessionKey: descriptor.sessionKey,
                    reference: VaultNoteReference(
                        vaultID: descriptor.reference.vaultID,
                        vaultName: descriptor.reference.vaultName,
                        vaultRole: descriptor.reference.vaultRole,
                        relativePath: destinationPath,
                        stableNoteID: descriptor.reference.stableNoteID
                    )
                ))
        }
        if let tab = documentTabController.tabs.first(where: {
            $0.document.sessionKey == DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        }), let descriptor = tab.document.workspaceDescriptor {
            let updatedReference = VaultNoteReference(
                vaultID: descriptor.reference.vaultID,
                vaultName: descriptor.reference.vaultName,
                vaultRole: descriptor.reference.vaultRole,
                relativePath: destinationPath,
                stableNoteID: descriptor.reference.stableNoteID
            )
            let updatedDocument = WindowSelectedDocument.workspace(
                WindowDocumentDescriptor(
                    sessionKey: descriptor.sessionKey,
                    reference: updatedReference
                )
            )
            let fallbackTitle = URL(fileURLWithPath: destinationPath)
                .deletingPathExtension()
                .lastPathComponent
            documentTabController.updateDocumentProjection(
                updatedDocument,
                title: fallbackTitle,
                toolTip: [fallbackTitle, descriptor.reference.vaultName, destinationPath]
                    .filter { !$0.isEmpty }
                    .joined(separator: " — ")
            )
        }
        documentController.migratePresentationPath(
            from: sourcePath,
            to: destinationPath,
            vaultID: vaultID
        )
    }

}
