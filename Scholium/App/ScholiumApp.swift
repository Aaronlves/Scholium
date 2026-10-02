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
        case saveSelectedDocument
        case preserveSelectedDocument
        case operationOnly
        case openingDocument(placement: DocumentTabPlacement, retainedTab: @MainActor () -> DocumentTabItem?)
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
    var noteExportWindowController: ScholiumNoteExportWindowController?
    var noteInfoWindowController: NoteInfoWindowController?
    lazy var sidePaneCoordinator = WindowSidePaneCoordinator(model: self)
    lazy var pdfReaderController = PDFReaderController(
        windowID: nativeWindowID,
        zotero: workspaceStore.zoteroBridge,
        setBinding: { [weak self] path, target, expectedBinding in
            guard let self else { throw CancellationError() }
            try await self.setNotePDFBinding(path, for: target, expectedBinding: expectedBinding)
        },
        reportIssue: { [weak self] message in
            self?.reportOperationIssue(message, kind: .error)
        },
        allowsInteraction: { [weak self] in
            self?.acceptsPDFInteraction() == true
        },
        resolveIssue: { [weak self] id in
            self?.shellState.dismissOperationIssue(id: id)
        }
    )

    private func acceptsPDFInteraction() -> Bool {
        !windowCloseCoordinator.isPreparingOrFinalized
            && !(nativeWindowCoordinator?.isNativeCloseInProgress ?? false)
            && !(nativeWindowCoordinator?.registry.isTerminationAttemptInProgress ?? false)
    }

    // MARK: Published State
    @Published var noteExportPreparationInProgress = false
    @Published var vaultConfig: VaultConfig?
    @Published var currentRegisteredVault: RegisteredVault?
    @Published var currentVaultRole: VaultRole = .other
    @Published private(set) var libraryFocusRequestGeneration: UInt64 = 0
    let presentationRouter = WindowPresentationRouter()
    let shellState = WindowShellState()
    let writingContinuationContextCache = WritingContinuationContextCache()
    var selectionResult: (inquiry: AgentChatSelectionInquiry, attachment: AgentChatAttachment, model: String, result: AgentSelectionResult)?
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
            searchCompletions: { [weak self] request in
                guard let self else {
                    throw DiscoverySearchExecutionError.workspaceUnavailable
                }
                return try await self.discoveryController.searchCompletions(request)
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
        workspaceProjectionController: workspaceProjectionController,
        pdfReaderController: pdfReaderController,
        sidePaneCoordinator: sidePaneCoordinator
    )
    private weak var editorCommandPort: ScholiumEditorCommandPort?

    var currentEditorActions: ScholiumFocusedEditorActions? {
        guard let port = editorCommandPort,
            let actions = resolvedEditorActions(for: port.token)
        else { return nil }
        let token = port.token
        return ScholiumFocusedEditorActions(
            documentID: actions.documentID,
            isComposing: actions.isComposing,
            isAvailable: { [weak self] command in
                self?.resolvedEditorActions(for: token)?.isAvailable(command) == true
            },
            perform: { [weak self] command in
                self?.resolvedEditorActions(for: token)?.perform(command)
            },
            performWithArgument: { [weak self] command, argument in
                self?.resolvedEditorActions(for: token)?.performWithArgument(command, argument)
            },
            importImage: { [weak self] in self?.resolvedEditorActions(for: token)?.importImage() },
            indexImage: { [weak self] in self?.resolvedEditorActions(for: token)?.indexImage() },
            canAttachDocument: actions.canAttachDocument,
            attachDocumentCopy: { [weak self] in
                self?.resolvedEditorActions(for: token)?.attachDocumentCopy()
            },
            referenceOriginalDocument: { [weak self] in
                self?.resolvedEditorActions(for: token)?.referenceOriginalDocument()
            },
            canEditFrontmatter: actions.canEditFrontmatter,
            goToFrontmatter: { [weak self] in
                self?.resolvedEditorActions(for: token)?.goToFrontmatter()
            }
        )
    }

    func registerEditorActions(
        port: ScholiumEditorCommandPort,
        target: DocumentEditingTarget,
        session: DocumentSessionModel,
        actions: ScholiumFocusedEditorActions,
        change: ScholiumEditorCommandRegistrationChange
    ) {
        if change == .refresh, editorCommandPort?.token != port.token { return }
        guard documentController.selectedDocument?.editingTarget == target,
            documentController.retainsSession(session, for: target)
        else { return }
        port.target = target
        port.session = session
        port.actions = actions
        editorCommandPort = port
        commandObservation.editorActionsDidChange()
    }

    func unregisterEditorActions(token: UUID) {
        guard editorCommandPort?.token == token else { return }
        clearEditorActions()
    }

    func releaseEditorActionsIfInvalid() {
        guard let port = editorCommandPort else { return }
        if resolvedEditorActions(for: port.token) == nil { clearEditorActions() }
    }

    func clearEditorActions() {
        guard let port = editorCommandPort else { return }
        port.actions = nil
        editorCommandPort = nil
        commandObservation.editorActionsDidChange()
    }

    private func resolvedEditorActions(for token: UUID) -> ScholiumFocusedEditorActions? {
        guard let port = editorCommandPort,
            port.token == token,
            let target = port.target,
            let session = port.session,
            documentController.selectedDocument?.editingTarget == target,
            documentController.retainsSession(session, for: target)
        else { return nil }
        return port.actions
    }
    let attentionPresentationState = AttentionPresentationState()
    lazy var attentionPopoverSession = AttentionPopoverSession(
        presentation: attentionPresentationState,
        workspaceController: windowWorkspaceController,
        projectionController: workspaceProjectionController,
        dependencies: .init(
            documentChangeChanges: researchController.$pendingChanges
                .eraseToAnyPublisher(),
            documentChangeErrorChanges: researchController.$pendingChangesError
                .eraseToAnyPublisher(),
            refresh: { [weak self] in
                guard let self else { return }
                await self.refreshWorkspaceCatalog()
                _ = try? await self.researchController.loadAgentChanges()
                _ = try? await self.researchController.loadDocumentChanges()
            },
            showDocumentChange: { [weak self] noteID in
                self?.presentationRouter.present(
                    .documentChanges(scope: .note(noteID))
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
        set { sidePaneCoordinator.setInspectorVisible(newValue) }
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
    var activeDocumentTransitionCurrency: DocumentTransitionCoordinator.Currency?
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
            self.sidePaneCoordinator.cancelPending()
            let pdfDeparture = self.pdfReaderController.beginDeparture()
            defer { self.pdfReaderController.endDeparture(pdfDeparture) }
            if let info = self.noteInfoWindowController {
                guard await info.prepareForWindowClose() else { throw CancellationError() }
                info.close()
            }
            try await self.flushRegisteredEditorIfNeeded(capturingEditorState: true)
            try await self.pdfReaderController.flushPersistence()
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
            self.selectionResult?.result.stop()
            self.selectionResult = nil
            self.libraryMutationController.unbind()
            self.researchController.unbind()
            self.windowWorkspaceController.cancelAll()
            self.documentTransitionCoordinator.cancelAll()
            self.libraryRevealTask?.cancel()
            self.libraryRevealTask = nil
            self.editorFlushCoordinator.shutdown()
            self.sidePaneCoordinator.shutdown()
            self.pdfReaderController.shutdown()
            self.noteInfoWindowController?.close()
            self.noteInfoWindowController = nil
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
    private var performanceNotificationTokens: [Int32] = []

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
                    performanceNotificationTokens.append(token)
                }
            }
        }
        if PerformanceProbe.shared.isEnabled,
            ProcessInfo.processInfo.arguments.contains(
                "--scholium-performance-library-reveal-notifications"
            )
        {
            for name in [
                "com.scholium.qa.performance-library-reveal-cluster-00",
                "com.scholium.qa.performance-library-reveal-cluster-01",
                "com.scholium.qa.performance-library-reveal-long",
            ] {
                var token: Int32 = 0
                let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handlePerformanceLibraryReveal(name)
                    }
                }
                if status == NOTIFY_STATUS_OK {
                    performanceNotificationTokens.append(token)
                }
            }
        }
        #if DEBUG
            if PerformanceProbe.shared.measuresQAMemoryOwners {
                var token: Int32 = 0
                let status = notify_register_dispatch(
                    PerformanceProbe.qaMemoryOwnerNotification,
                    &token,
                    .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.handleQAMemoryOwnerSnapshot()
                    }
                }
                if status == NOTIFY_STATUS_OK {
                    performanceNotificationTokens.append(token)
                }
            }
        #endif
        searchController.loadSavedSearches()
        startWorkspaceObservers()
    }

    deinit {
        libraryRevealTask?.cancel()
        for token in performanceNotificationTokens {
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

    var currentNote: WindowDocumentLocation? {
        if let active = documentController.activeSnapshot {
            return .hydrated(active)
        }
        if let unavailable = documentController.unavailableSnapshot,
            documentController.selectedDocument?.vaultID == unavailable.id.vaultID,
            documentController.selectedDocument?.relativePath == unavailable.id.relativePath
        {
            return .hydrated(unavailable)
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
        researchController.showResearchInspector(visible)
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

// Application-defined failures are projected at this existing delivery composition
// root. The localization owner reaches backend contracts without a new import edge.
extension ScholiumErrorLocalization {
    static func applicationMessage(_ error: any Error, locale: Locale) -> String? {
        switch error {
        case let error as BootstrapStructurePreparationError:
            return switch error {
            case .invalidName: ScholiumL10n.string("Enter a Triptych name that can be used as a folder name.", locale: locale)
            case .destinationExists(let path):
                ScholiumL10n.string("A folder already exists at \(path). Choose Connect Existing Folders or use another name.", locale: locale)
            }
        case let error as CodexChatToolConfigurationError:
            return switch error {
            case .accessConfirmationRequired:
                ScholiumL10n.string("Confirm whether existing access settings may be used with the new destination.", locale: locale)
            case .invalidName: ScholiumL10n.string("Enter a connection name without line breaks or control characters.", locale: locale)
            case .duplicateName: ScholiumL10n.string("A tool connection already uses this name.", locale: locale)
            case .managedConnection: ScholiumL10n.string("This connection is managed by another configuration or by Scholium.", locale: locale)
            case .invalidAddress:
                ScholiumL10n.string("Enter a program or a valid HTTPS server address. Local servers may use HTTP on the loopback address.", locale: locale)
            case .invalidVariable: ScholiumL10n.string("Enter environment variable names only, without values, spaces or equals signs.", locale: locale)
            }
        case let error as ScholiumAppBridgeError:
            return switch error {
            case .unavailable: ScholiumL10n.string("The running Scholium App bridge is unavailable.", locale: locale)
            case .invalidFrame: ScholiumL10n.string("The Scholium App bridge frame is invalid.", locale: locale)
            case .invalidRequest: ScholiumL10n.string("The Scholium App bridge request is invalid.", locale: locale)
            case .invalidResponse: ScholiumL10n.string("The Scholium App bridge response is invalid.", locale: locale)
            case .unsupportedVersion(let version):
                ScholiumL10n.string("The Scholium App bridge schema version \(String(version)) is unsupported.", locale: locale)
            case .permissionDenied: ScholiumL10n.string("The Scholium App bridge rejected current-user authentication.", locale: locale)
            case .timeout: ScholiumL10n.string("The Scholium App bridge timed out before sending a request.", locale: locale)
            case .outcomeUnknown: ScholiumL10n.string("The Scholium App bridge cannot determine whether the request completed.", locale: locale)
            case .alreadyRunning: ScholiumL10n.string("Another Scholium App bridge already owns this endpoint.", locale: locale)
            case .remote(_, let message): message
            case .systemCall: error.localizedDescription
            }
        case let error as CodexWritingAssistanceError:
            return switch error {
            case .unavailable: ScholiumL10n.string("Writing assistance is unavailable for the selected model or connection.", locale: locale)
            case .busy: ScholiumL10n.string("Another writing request is still running or stopping.", locale: locale)
            case .invalidContext: ScholiumL10n.string("Select a shorter passage or a valid writing context.", locale: locale)
            case .invalidOutput: ScholiumL10n.string("AI returned no usable writing suggestion.", locale: locale)
            case .unsafeRuntime: ScholiumL10n.string("The runtime could not provide isolated, tool-free writing assistance.", locale: locale)
            case .timedOut: ScholiumL10n.string("Writing assistance took too long.", locale: locale)
            }
        case let error as ExternalMarkdownFileError:
            return switch error {
            case .unsupportedType: ScholiumL10n.string("Choose a Markdown file (.md or .markdown).", locale: locale)
            case .missing: ScholiumL10n.string("The original Markdown file is missing.", locale: locale)
            case .notRegularFile: ScholiumL10n.string("The original is not a regular, unlinked file.", locale: locale)
            case .invalidUTF8: ScholiumL10n.string("The Markdown file is not valid UTF-8.", locale: locale)
            case .tooLarge: ScholiumL10n.string("This Markdown file exceeds the 1 MB editor limit.", locale: locale)
            case .permissionDenied: ScholiumL10n.string("Scholium no longer has permission to access this file.", locale: locale)
            case .changed: ScholiumL10n.string("The original Markdown file changed. Your edits remain available in the editor.", locale: locale)
            case .closed: ScholiumL10n.string("This external Markdown session is closed.", locale: locale)
            case .commitUncertain:
                ScholiumL10n.string(
                    "The save could not be verified. Keep the editor open. Check the original; a prior copy may remain in a hidden Scholium file beside it.",
                    locale: locale)
            case .io(let description): ScholiumL10n.string("The Markdown file could not be accessed: \(description)", locale: locale)
            }
        case let error as CodexConnectionError:
            return switch error {
            case .disconnected: ScholiumL10n.string("Codex disconnected. Check the conversation before sending again.", locale: locale)
            case .timedOut: ScholiumL10n.string("Codex did not confirm the request. Check its outcome before sending again.", locale: locale)
            case .invalidMessage: ScholiumL10n.string("Codex returned an invalid protocol message.", locale: locale)
            case .installationChanged: ScholiumL10n.string("The Codex installation changed. Reconnect after checking the installation.", locale: locale)
            case .server(let message): message
            }
        default:
            return nil
        }
    }
}
