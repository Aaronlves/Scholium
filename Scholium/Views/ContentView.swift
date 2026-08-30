import ScholiumContracts
import SwiftUI

enum DiscussionPresentationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Discussion is unavailable until Scholium can identify the selected Analysis, Topic, or Work reliably."
    }
}

private struct ResearchActionAvailabilityRefreshIdentity: Equatable {
    let target: ResearchActionNoteSnapshot?
    let snapshotPhase: WorkspaceSnapshotPhase?
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var appState: WindowModel
    @ObservedObject private var presentationRouter: WindowPresentationRouter
    @ObservedObject private var discoveryController: DiscoveryController
    @ObservedObject private var searchController: WindowSearchController
    @ObservedObject private var researchController: ResearchController
    @ObservedObject private var researchActionController: ResearchActionController
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var documentController: DocumentController
    @ObservedObject private var documentTabController: DocumentTabController
    @ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController
    @ObservedObject private var researchAgentPermissionWindowController:
        ResearchAgentPermissionWindowController
    @ObservedObject private var cssSnippetStore: CSSSnippetStore
    @ObservedObject private var windowWorkspaceController: WindowWorkspaceController
    @ObservedObject private var libraryMutationController: WindowLibraryMutationController
    let windowCoordinator: WorkspaceWindowCoordinator
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()
    @State private var pendingResearchActionFocusID: ResearchActionID?
    @State private var researchActionFocusRequest: ResearchActionFocusRequest?
    @State private var researchActionDismissalFocusDisposition:
        ResearchActionDismissalFocusDisposition = .preserveInputModality

    init(
        appState: WindowModel,
        windowCoordinator: WorkspaceWindowCoordinator
    ) {
        self.appState = appState
        self.windowCoordinator = windowCoordinator
        _presentationRouter = ObservedObject(wrappedValue: appState.presentationRouter)
        _discoveryController = ObservedObject(wrappedValue: appState.discoveryController)
        _searchController = ObservedObject(wrappedValue: appState.searchController)
        _researchController = ObservedObject(wrappedValue: appState.researchController)
        _researchActionController = ObservedObject(
            wrappedValue: appState.researchController.actions
        )
        _shellState = ObservedObject(wrappedValue: appState.shellState)
        _documentController = ObservedObject(wrappedValue: appState.documentController)
        _documentTabController = ObservedObject(wrappedValue: appState.documentTabController)
        _workspaceProjectionController = ObservedObject(
            wrappedValue: appState.workspaceProjectionController
        )
        _researchAgentPermissionWindowController = ObservedObject(
            wrappedValue: appState.researchAgentPermissionWindowController
        )
        _cssSnippetStore = ObservedObject(wrappedValue: appState.cssSnippetStore)
        _windowWorkspaceController = ObservedObject(
            wrappedValue: appState.windowWorkspaceController
        )
        _libraryMutationController = ObservedObject(
            wrappedValue: appState.libraryMutationController
        )
    }

    var body: some View {
        ScholiumWorkspaceSplitView(
            initialLibraryVisible: shellLibraryVisible,
            initialApparatusVisible: shellApparatusVisible,
            documentTabs: appState.documentTabController.tabs(
                in: shellState.selectedWorkspace
            ),
            selectedDocumentTabID: appState.documentTabController.selectedTabID(
                in: shellState.selectedWorkspace
            ),
            selectDocumentTab: { appState.selectDocumentTab(withID: $0) },
            closeDocumentTab: { appState.closeDocumentTab(withID: $0) },
            libraryVisibilityDidChange: {
                appState.recordLibraryVisibility($0)
            },
            researchInspectorVisibilityDidChange: {
                appState.recordResearchInspectorVisibility($0)
            },
            splitControllerDidAttach: {
                windowCoordinator.attach(splitController: $0)
            },
            splitControllerDidDetach: {
                windowCoordinator.detach(splitController: $0)
            }
        ) {
            LibrarySurface {
                SidebarView(
                    controller: appState.discoveryController,
                    context: sidebarContext
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        } document: {
            Group {
                if !shellState.hasCompletedInitialRestore {
                    ScholiumLaunchPlaceholderView()
                } else {
                    detailRegion
                }
            }
            .scholiumSurface(.document)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) {
                if let toast = appState.toastMessage {
                    ToastView(toast: toast)
                        .transition(
                            ScholiumMotion.transientStatusTransition(
                                reduceMotion: reduceMotion
                            )
                        )
                        .padding(
                            .bottom,
                            ScholiumGrid.Spacing.regionContentInset
                        )
                }
            }
            .animation(
                ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
                value: appState.toastMessage
            )
            .overlay(alignment: .topTrailing) {
                refreshStatusNotice
            }
        } apparatus: {
            apparatusRegion
            .scholiumSurface(.apparatus)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        // The native split and each opaque semantic background fill the complete
        // titlebar frame. Each container keeps its actual content inside the
        // live toolbar safe area.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .overlay {
            if appState.showSearchSurface {
                SpotlightSearchOverlay(
                    controller: appState.discoveryController,
                    context: spotlightSearchContext
                )
                    .transition(
                        ScholiumMotion.searchPresentationTransition(
                            reduceMotion: reduceMotion
                        )
                    )
                    .zIndex(20)
            }
        }
        .animation(
            ScholiumMotion.searchPresentation(reduceMotion: reduceMotion),
            value: appState.showSearchSurface
        )
        .onChange(
            of: shellState.researchActivityNotifications
        ) { previous, current in
            let previousReady = Set(previous.compactMap {
                $0.state == .resultReady ? $0.runID : nil
            })
            guard current.contains(where: {
                $0.state == .resultReady && !previousReady.contains($0.runID)
            }) else { return }
            AccessibilityNotification.Announcement(
                String(
                    localized: "An Agent result is ready to review.",
                    table: "Localizable",
                    bundle: .module
                )
            ).post()
        }
        .onChange(
            of: shellState.researchNotificationPermissionNotice
        ) { previous, current in
            guard let current, current != previous else { return }
            let message = switch current {
            case .enable:
                String(
                    localized: "Get Notified When Results Are Ready",
                    table: "Localizable",
                    bundle: .module
                )
            case .openSettings:
                String(
                    localized: "Notifications Are Off",
                    table: "Localizable",
                    bundle: .module
                )
            }
            AccessibilityNotification.Announcement(message).post()
        }
        .sheet(item: presentedSheet, onDismiss: {
            let permissionController = appState
                .researchAgentPermissionWindowController
            if permissionController.claim != nil {
                windowCoordinator.restoreResearchAgentPermissionFocus()
                permissionController.finishDismissal()
            } else if researchActionController.isPresented {
                let actionID = researchActionController.activeActionID
                let focusDisposition = researchActionDismissalFocusDisposition
                appState.presentationRouter.dismissSheet()
                researchActionController.dismiss()
                completeResearchActionDismissalFocus(
                    ifOwnedBy: actionID,
                    disposition: focusDisposition
                )
                researchActionDismissalFocusDisposition = .preserveInputModality
                permissionController.presentationBecameAvailable()
            } else {
                permissionController.presentationBecameAvailable()
            }
        }) { route in
            sheetContent(for: route)
        }
        .alert(item: presentedAlert) { alert in
            switch alert {
            case .actionFailure(let message):
                Alert(
                    title: Text("Could Not Complete Action"),
                    message: Text(message),
                    dismissButton: .default(Text("Dismiss")) {
                        appState.presentationRouter.alert = nil
                    }
                )
            case .localExecutionRecovery(let preview):
                Alert(
                    title: Text("Archive Unreadable Research Actions?"),
                    message: Text(
                        "Scholium cannot determine which Notes are covered by older or damaged local Research Action storage (file count: \(preview.items.count)). Archive the exact files inside Scholium and continue preparing Move to Trash? This disables those old Runs but does not change research Notes or portable Research Records."
                    ),
                    primaryButton: .cancel(Text("Cancel")) {
                        appState.libraryMutationController.cancelLocalExecutionRecovery(preview)
                    },
                    secondaryButton: .destructive(Text("Archive and Continue")) {
                        Task { @MainActor in
                            await appState.libraryMutationController.archiveLocalExecutionsAndRetrySystemTrash(
                                preview
                            )
                        }
                    }
                )
            }
        }
        .task(id: researchActionAvailabilityRefreshIdentity) {
            await appState.refreshResearchActionAvailability()
        }
    }

    private var researchActionAvailabilityRefreshIdentity:
        ResearchActionAvailabilityRefreshIdentity {
        ResearchActionAvailabilityRefreshIdentity(
            target: appState.currentResearchActionTarget,
            snapshotPhase: workspaceProjectionController.snapshotPhase
        )
    }

    @ViewBuilder
    private var refreshStatusNotice: some View {
        if let status = appState.refreshStatusText {
            HStack(spacing: ScholiumMetrics.Workspace.refreshStatusSpacing) {
                Label(
                    status,
                    systemImage: appState.hasDerivedRefreshFailure
                        ? "exclamationmark.triangle"
                        : "arrow.triangle.2.circlepath"
                )
                if appState.hasDerivedRefreshFailure {
                    Button("Retry Refresh") {
                        Task { await appState.retryDerivedRefresh() }
                    }
                    .buttonStyle(.borderless)
                    .font(
                        ScholiumTypography.interface(
                            .small,
                            emphasis: .strong
                        )
                    )
                }
            }
            .font(ScholiumTypography.interface(.small))
            .padding(
                .horizontal,
                ScholiumMetrics.Workspace.refreshStatusHorizontalInset
            )
            .padding(
                .vertical,
                ScholiumMetrics.Workspace.refreshStatusVerticalInset
            )
            .scholiumEditorialSurface(
                .floatingControl,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                    style: .continuous
                )
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.refreshStatus")
        }
    }

    private var shellLibraryVisible: Bool {
        guard shellState.hasCompletedInitialRestore,
              appState.vaultConfig != nil
        else { return true }
        return shellState.libraryVisible
    }

    private var shellApparatusVisible: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && shellState.hasCompletedInitialRestore
            && appState.vaultConfig != nil
            && shellState.inspector.isVisible
    }

    private var presentedSheet: Binding<WindowSheetRoute?> {
        Binding(
            get: { appState.presentationRouter.sheet },
            set: { appState.presentationRouter.sheet = $0 }
        )
    }

    private var presentedAlert: Binding<WindowAlertRoute?> {
        Binding(
            get: { appState.presentationRouter.alert },
            set: { appState.presentationRouter.alert = $0 }
        )
    }

    private func completeResearchActionDismissalFocus(
        ifOwnedBy actionID: ResearchActionID?,
        disposition: ResearchActionDismissalFocusDisposition
    ) {
        let pendingActionID = pendingResearchActionFocusID
        pendingResearchActionFocusID = nil
        guard disposition == .restoreOriginatingAction,
              let actionID,
              pendingActionID == actionID else {
            return
        }
        researchActionFocusRequest = ResearchActionFocusRequest(actionID: actionID)
    }

    private var spotlightSearchContext: SpotlightSearchContext {
        SpotlightSearchContext(
            completionContext: searchCompletionContext,
            savedSearches: appState.searchController.savedSearches,
            savedSearchLoadFailure: appState.searchController.savedSearchLoadFailure,
            recoverSavedSearches: {
                await appState.searchController.recoverSavedSearches()
            },
            refresh: { await appState.searchController.refresh() },
            dismiss: { appState.searchController.dismiss() },
            save: { appState.searchController.saveCurrent(named: $0) },
            run: { appState.searchController.run($0) },
            rename: { appState.searchController.rename($0, to: $1) },
            move: { appState.searchController.move($0, by: $1) },
            delete: { appState.searchController.delete($0) }
        )
    }

    private var searchCompletionContext: SearchCompletionContext {
        let profiles: [SchemaProfileID]
        switch appState.discoveryController.search.criteria.scope {
        case .currentVault:
            profiles = [NoteMetadataCatalog.profile(for: shellState.selectedWorkspace)]
        case .thisNote:
            profiles = []
        case .triptych:
            profiles = [.analysis, .topicMarkdown, .draftProject]
        }
        let managedContracts = profiles.flatMap {
            workspaceProjectionController.metadataCatalog.contracts(for: $0)
        }
        let authoredContracts = profiles.flatMap {
            PropertyContractCatalog.contracts(for: $0)
        }
        let contracts = managedContracts + authoredContracts
        let keys = Array(Set(contracts.map(\.canonicalKey))).sorted()
        let values = Dictionary(
            contracts.compactMap { contract in
                contract.allowedValues.map { (contract.canonicalKey, $0) }
            },
            uniquingKeysWith: { lhs, rhs in Array(Set(lhs + rhs)).sorted() }
        )
        return SearchCompletionContext(
            propertyKeys: keys,
            propertyValues: values
        )
    }

    private var researchInspectorContentContext: ResearchInspectorContentContext {
        ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                visibleAttentionItems: visibleCurrentDocumentAttentionItems,
                activityNotificationCount:
                    currentDocumentActivityNotificationCount,
                freshness: researchProjectionFreshness,
                aboutConfiguration: appState.currentDocumentAboutConfiguration,
                metadataCatalog: workspaceProjectionController.metadataCatalog,
                zoteroBinding: currentAnalysisZoteroBinding,
                noteReviewState: currentNoteReviewState,
                stableNoteID: currentAnalysisStableNoteID
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openProperties: {
                guard let path = appState.currentNote?.relativePath else { return }
                appState.editingNotePath = path
                appState.showMetadataEditor = true
            },
            openAttention: {
                guard let note = appState.currentNote,
                      let vaultID = appState.currentDocumentVaultID else { return }
                windowCoordinator.actions.showAttention(
                    .inspector,
                    VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: note.relativePath
                    )
                )
            },
            openNoteReview: {
                guard let reviewState = currentNoteReviewState,
                      reviewState.status == .needsReview else { return }
                currentNoteDocumentSession?.presentNoteReviewTask(
                    for: reviewState
                )
            },
            retryRefresh: {
                Task { await appState.retryDerivedRefresh() }
            },
            openZoteroItem: { binding in
                await appState.zoteroCoordinator.bridge.openInZotero(binding: binding)
            },
            refreshZoteroMetadata: { noteID, binding in
                appState.presentationRouter.present(.zoteroBinding(
                    ZoteroBindingPanelRoute(
                        noteID: noteID,
                        currentBinding: binding,
                        mode: .refresh
                    )
                ))
            },
            manageZoteroBinding: { noteID, binding in
                appState.presentationRouter.present(.zoteroBinding(
                    ZoteroBindingPanelRoute(
                        noteID: noteID,
                        currentBinding: binding
                    )
                ))
            }
        )
    }

    private var currentNoteStableID: UUID? {
        appState.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID
    }

    private var currentNoteReviewState: WorkspaceNoteReviewState? {
        guard let noteID = currentNoteStableID else { return nil }
        return researchController.records?.noteReviewStates.first {
            $0.noteID == noteID
        }
    }

    private var currentNoteDocumentSession: DocumentSessionModel? {
        if let descriptor = appState.currentDocumentDescriptor {
            return appState.documentController.session(for: descriptor.sessionKey)
        }
        guard let vaultID = appState.currentDocumentVaultID,
              let noteID = currentNoteStableID else { return nil }
        return appState.documentController.session(
            for: DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        )
    }

    private var currentAnalysisZoteroBinding: AnalysisZoteroBinding? {
        guard appState.currentDocumentVaultRole == .sourceCorpus else { return nil }
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID else { return nil }
        return appState.workspaceCatalog?.notes.first {
            $0.reference.vaultID == vaultID
                && $0.reference.relativePath == note.relativePath
        }?.zoteroBinding
    }

    private var currentAnalysisStableNoteID: UUID? {
        guard appState.currentDocumentVaultRole == .sourceCorpus else { return nil }
        return currentNoteStableID
    }

    private var visibleCurrentDocumentAttentionItems: [AttentionQueueItem] {
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID else { return [] }
        let matching = (appState.workspaceCatalog?.attention ?? []).filter {
            $0.note.vaultID == vaultID && $0.note.relativePath == note.relativePath
        }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(matching)
    }

    private var currentDocumentActivityNotificationCount: Int {
        guard let noteID = currentNoteStableID else { return 0 }
        return shellState.researchActivityNotifications.count { notification in
            notification.targetNoteID == noteID
                || notification.affectedNotes.contains { $0.noteID == noteID }
        }
    }

    private var documentActivityNotifications: [ResearchActivityNotification] {
        shellState.researchActivityNotifications.filter {
            $0.state.requiresResearcherAttention
        }
    }

    private var researchProjectionFreshness: ResearchProjectionFreshness {
        if appState.isRefreshingWorkspaceCatalog { return .refreshing }
        switch appState.derivedRefreshStatus {
        case .opening:
            return .refreshing
        case .current:
            return .current
        case .stale(let issue):
            return .stale(issue.reason)
        case .failed(let issue):
            return .failed(issue.reason)
        case nil:
            if appState.workspaceCatalog != nil { return .current }
            return .unavailable(
                appState.workspaceCatalogError ?? "No complete derived workspace snapshot is available."
            )
        }
    }

    private var critiqueProvenanceContext: CritiqueProvenanceContext {
        CritiqueProvenanceContext(
            availableNotes: appState.currentDocumentNotes,
            documentRevisions: appState.currentDocumentRevisions,
            loadAssociation: { path in
                try await appState.researchController.critique(
                    critiqueRelativePath: path
                )
            },
            openTarget: { appState.requestOpenNote($0) },
            openFinding: { finding, fallbackTargetPath in
                appState.openCritiqueFinding(
                    finding,
                    fallbackTargetPath: fallbackTargetPath
                )
            }
        )
    }

    private var documentFeatureState: DocumentFeatureState {
        let note = appState.currentNote
        let path = note?.relativePath
        return DocumentFeatureState(
            notes: appState.currentDocumentNotes,
            selectedDocumentPath: appState.selectedDocumentPath,
            ordinarySearchScope: appState.searchController.ordinaryScope,
            currentVaultID: appState.currentDocumentVaultID,
            vaultRole: appState.currentDocumentVaultRole,
            noteIdentityByPath: appState.currentDocumentIdentityByPath,
            documentRevisions: appState.currentDocumentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            activeDiscussions: appState.researchController.records?.activeDiscussions ?? [],
            requestedDiscussionID: appState.requestedDiscussionID,
            canComment: appState.canCommentCurrentNote,
            canEdit: appState.canEditCurrentNote,
            isManagedCritique: appState.currentDocumentCapabilities.isManagedCritique,
            documentTextScale: appState.documentTextScale,
            appearanceCSS: appState.cssSnippetStore.appearanceCSS,
            readCSS: appState.cssSnippetStore.readCSS,
            livePreviewCSS: appState.cssSnippetStore.livePreviewCSS,
            initialScrollFraction: path.map { appState.scrollPosition(for: $0) } ?? 0,
            requestedPresentationMode: appState.requestPresentationMode,
            pendingSourceLine: appState.pendingSourceLine,
            pendingSourceRange: appState.pendingSourceRange,
            identityAmbiguity: appState.currentDocumentIdentityAmbiguity,
            pendingIdentityRebinding: appState.currentDocumentPendingIdentityRebinding,
            identityMigrationFailureMessage: appState.currentDocumentIdentityMigrationFailure?.message,
            isResolvingIdentity: appState.isResolvingIdentity,
            noteReviewState: currentNoteReviewState,
            researchRecordSourceManifestHash: researchController.records?
                .finishedResearchRecordSourceManifestHash ?? "",
            researchRecordProjectionIsComplete: researchController.records?
                .finishedResearchRecordProjectionIsComplete ?? false
        )
    }

    private var documentFeatureActions: DocumentFeatureActions {
        let documentPath = appState.currentNote?.relativePath
        return DocumentFeatureActions(
            requestIdentityResolution: {
                guard let path = documentPath else { return }
                appState.requestIdentityResolution(for: path)
            },
            retryIdentityRecovery: { await appState.retryIdentityRecovery() },
            beginSearch: { appState.searchController.begin($0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            clearPendingSourceLine: { appState.pendingSourceLine = nil },
            clearPendingSourceRange: { appState.pendingSourceRange = nil },
            createDiscussion: { anchor, message in
                guard let target = appState.currentResearchActionTarget else {
                    throw DiscussionPresentationError.unavailable
                }
                let discussion = try await appState.researchController.createDiscussion(
                    target: target,
                    passage: anchor,
                    researcherMessage: message
                )
                try await appState.researchController.refreshResearchProjection()
                appState.requestDiscussionPresentation(discussion.id)
                return discussion
            },
            createComment: { expectedNoteID, expectedPath, lineReference, message in
                guard let target = appState.currentResearchActionTarget,
                      target.noteID == expectedNoteID,
                      target.note.relativePath == expectedPath,
                      target.fingerprint == lineReference.fingerprint else {
                    throw DiscussionPresentationError.unavailable
                }
                let discussion = try await appState.researchController.createComment(
                    target: target,
                    lineReference: lineReference,
                    researcherMessage: message
                )
                do {
                    try await appState.researchController.refreshResearchProjection()
                } catch {
                    throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                        operation: "The Comment",
                        reason: error.localizedDescription
                    )
                }
                return discussion
            },
            reloadDiscussion: { discussionID in
                try await appState.researchController.activeDiscussionIfPresent(
                    id: discussionID
                )
            },
            loadDiscussionAgentInstructions: { discussionID in
                try await appState.researchController.discussionAgentInstructions(
                    id: discussionID
                )
            },
            refreshDiscussionProjection: {
                try await appState.researchController.refreshResearchProjection()
            },
            endDiscussion: { discussionID in
                try await appState.researchController.endDiscussion(id: discussionID)
            },
            clearRequestedDiscussion: {
                appState.clearRequestedDiscussionPresentation()
            },
            copyDiscussionRequest: { instructions in
                try appState.copyTextToClipboard(instructions)
            },
            rememberScrollPosition: {
                guard let path = documentPath else { return }
                appState.rememberScrollPosition($0, for: path)
            },
            openInternalLink: {
                guard let path = documentPath else { return }
                appState.openInternalLink($0, from: path)
            },
            openExternalURL: { appState.openExternalURL($0) },
            enterCSSSafeMode: { appState.cssSnippetStore.enterSafeMode(after: $0) },
            rememberPresentationMode: {
                appState.rememberPresentationMode($0)
            },
            setPendingSourceLine: { appState.pendingSourceLine = $0 },
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            editProperties: {
                guard let path = documentPath else { return }
                appState.editingNotePath = path
                appState.showMetadataEditor = true
            },
            openResearchAction: { actionID, selection in
                appState.openResearchAction(actionID, selection: selection)
            },
            setResearchInspectorVisible: {
                windowCoordinator.actions.setResearchInspectorVisible($0)
            },
            viewAgentChanges: {
                windowCoordinator.actions.showNoteResearchRecords()
            },
            reloadNoteReviewState: {
                try await appState.researchController.refreshResearchProjection()
            },
            markCurrentNoteReviewed: { noteID, revision, manifest in
                _ = try await appState.researchController.markCurrentNoteReviewed(
                    noteID: noteID,
                    expectedRevision: revision,
                    expectedRecordSourceManifestHash: manifest
                )
            },
            openingDocumentPresentationDidComplete: {
                appState.openingDocumentPresentationDidComplete()
            },
            notify: { message, kind in
                switch kind {
                case .success: appState.showToast(message)
                case .information: appState.showToast(message, kind: .information)
                case .error: appState.showToast(message, kind: .error)
                }
            }
        )
    }

    private var sidebarContext: SidebarContext {
        let propertyFilterOptions = appState.availablePropertyFilterOptions
        let preorderedNotes = appState.filteredNotes
        let folders = appState.currentLibraryFolders
        let selectedLibraryDocumentPath = appState.currentDocumentVaultID
            == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionTotal: sidebarAttentionTotal,
            workspaceNoteCounts: sidebarWorkspaceNoteCounts,
            attentionError: appState.workspaceCatalog == nil
                ? appState.workspaceCatalogError
                : nil,
            treeProjection: appState.libraryTreeProjection(
                preorderedNotes: preorderedNotes,
                folderRelativePaths: folders
            ),
            allNotes: appState.notes,
            folders: folders,
            pathComparisonPolicy: appState.currentLibraryPathComparisonPolicy,
            disclosureScope: appState.currentRegisteredVault.map {
                LibraryDisclosureScope(
                    vaultID: $0.id,
                    sourceScope: appState.noteSourceScope
                )
            },
            selectedDocumentPath: selectedLibraryDocumentPath,
            libraryFocusRequestGeneration: appState.libraryFocusRequestGeneration,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            canMutateLibrary: appState.currentRegisteredVault != nil
                && !appState.libraryMutationController.isCreatingNote
                && !appState.libraryMutationController.isMutatingFolder,
            sourceMutationGeneration: appState.sourceMutationGeneration,
            filterOptions: SidebarLibraryFilterOptions(
                catalogIsAvailable: appState.workspaceCatalog != nil,
                graphIsAvailable: appState.relationshipGraph != nil,
                tags: appState.allTags,
                authors: appState.availableAuthors,
                propertyKeys: propertyFilterOptions.keys,
                propertyValues: propertyFilterOptions.valuesByKey
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openAttention: {
                windowCoordinator.actions.showAttention(.sidebar, nil)
            },
            retryAttention: {
                Task { await appState.refreshWorkspaceCatalog() }
            },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            selectTriptychWorkspace: { appState.requestTriptychWorkspace($0) },
            createUntitledNote: {
                appState.libraryMutationController.requestUntitledNoteCreation(in: $0)
            },
            createUntitledFolder: {
                appState.libraryMutationController.requestUntitledFolderCreation(in: $0)
            },
            moveNote: { target, destination in
                try await appState.libraryMutationController.moveNote(target, to: destination)
            },
            moveFolder: { target, destination in
                try await appState.libraryMutationController.moveFolder(target, to: destination)
            },
            requestFolderFileOperation: {
                appState.folderFileRequest = $0
            },
            requestFolderSystemTrash: {
                do {
                    try await appState.libraryMutationController.prepareFolderSystemTrash($0)
                } catch TriptychTransactionError.activeResearchActions(let runIDs) {
                    appState.openResearchActionRecovery(runIDs: runIDs)
                }
            },
            copyRelativePath: { path in
                do {
                    try appState.copyTextToClipboard(path)
                    appState.showToast(
                        String(
                            localized: "Relative path copied.",
                            table: "Localizable",
                            bundle: .module
                        )
                    )
                } catch {
                    appState.showToast(error.localizedDescription, kind: .error)
                }
            },
            revealNote: { appState.showInFinder($0) },
            requestSystemTrash: {
                do {
                    try await appState.libraryMutationController.prepareNoteSystemTrash($0)
                } catch TriptychTransactionError.activeResearchActions(let runIDs) {
                    appState.openResearchActionRecovery(runIDs: runIDs)
                }
            },
            revealCurrentVault: { appState.revealVaultInFinder() },
            openSettings: { openSettings() },
            selectSortOrder: { appState.discoveryController.selectSortOrder($0) },
            showError: { appState.showToast($0, kind: .error) }
        )
    }

    private var sidebarAttentionTotal: Int? {
        let activityCount = shellState.researchActivityNotifications.count
        let issueCount = AttentionPreferences.visibleTotalCount(
            catalog: appState.workspaceCatalog,
            assignment: appState.workspaceAssignment,
            dismissalLedgerData: attentionDismissalLedgerData
        )
        if let issueCount { return issueCount + activityCount }
        return activityCount > 0 ? activityCount : nil
    }

    private var sidebarWorkspaceNoteCounts: SidebarWorkspaceNoteCounts {
        guard let assignment = appState.workspaceAssignment else {
            return SidebarWorkspaceNoteCounts(values: [:])
        }
        let snapshots = workspaceProjectionController.vaultSnapshotsByID
        var values: [WorkspaceVaultSlot: Int] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vaultID = assignment.vault(for: slot)?.id,
                  let snapshot = snapshots[vaultID] else {
                continue
            }
            values[slot] = snapshot.documents.count {
                !$0.capabilities.isManagedCritique
            }
        }
        return SidebarWorkspaceNoteCounts(values: values)
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        appState.currentWorkspaceSlot
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
        case .metadata(let route):
            if let note = note(at: route.path) {
                MetadataEditorView(
                    note: note,
                    metadataCatalog: workspaceProjectionController.metadataCatalog,
                    expectedRevision: note.workspaceSnapshot?.metadata?.revision,
                    onClose: {
                        finishMetadata(route)
                    },
                    reload: {
                        try await appState.reloadMetadata(for: note.relativePath)
                    }
                ) { fields, revision in
                    _ = try await appState.saveMetadata(
                        for: note,
                        proposedFields: fields,
                        expectedRevision: revision
                    )
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .researchAction(let route):
            if note(at: route.target.relativePath) != nil {
                ResearchActionPanelView(
                    controller: researchActionController,
                    context: ResearchActionPanelContext(
                        chooseLocalSource: {
                            try await fileSelectionPresenter
                                .requiredForFileSelection()
                                .selectURL(ScholiumFileSelectionRequest(
                                    title: String(
                                        localized: "Choose Source",
                                        table: "Localizable",
                                        bundle: .module
                                    ),
                                    prompt: String(
                                        localized: "Choose",
                                        table: "Localizable",
                                        bundle: .module
                                    ),
                                    kind: .files(
                                        allowedContentTypes: [.item],
                                        resolvesAliases: false
                                    )
                                ))
                        },
                        copyInstructions: { instructions in
                            try appState.copyTextToClipboard(instructions)
                        },
                        didCopyHandoff: { runID in
                            windowCoordinator.recordSuccessfulResearchHandoff(
                                runID: runID
                            )
                        },
                        retryRefresh: {
                            Task { await appState.retryDerivedRefresh() }
                        },
                        openRecovery: {
                            appState.presentationRouter.dismissSheet()
                            Task { @MainActor in
                                await Task.yield()
                                appState.showTransactionRecovery = true
                            }
                        },
                        dismiss: { focusDisposition in
                            researchActionDismissalFocusDisposition = focusDisposition
                            appState.presentationRouter.dismissSheet()
                        }
                    )
                )
                .onDisappear {
                    if let currentSheet = appState.presentationRouter.sheet {
                        if case .researchAction(let currentRoute) = currentSheet,
                           currentRoute.presentationID == route.presentationID {
                            // Native dismissal is still in flight. The root
                            // `onDismiss` finalizes the draft and restores
                            // focus only after AppKit has closed the sheet.
                            return
                        }
                        researchActionController.dismiss(
                            presentationID: route.presentationID
                        )
                    }
                }
            }
        case .researchAgentPermission(let requestID):
            let controller = appState.researchAgentPermissionWindowController
            if let claim = controller.claim,
               claim.id == requestID {
                ResearchAgentPermissionView(
                    claim: claim,
                    hasLocallyExpired: controller.hasLocallyExpired,
                    isResolving: controller.isResolving,
                    resolveWriteSet: { state, allowedHandles in
                        controller.resolveWriteSet(
                            state: state,
                            allowedHandles: allowedHandles
                        )
                    },
                    resolveContinuation: { allow in
                        controller.resolveContinuation(allow: allow)
                    },
                    dismiss: {
                        controller.requestDismissal(id: requestID)
                    }
                )
            }
        case .noteFileOperation(let request):
            NoteFileOperationView(
                request: request,
                actions: NoteFileActions(
                    duplicate: { source, destination in
                        _ = try await appState.libraryMutationController.duplicateNote(
                            source,
                            to: destination
                        )
                    },
                    move: { source, destination in
                        try await appState.libraryMutationController.moveNote(
                            source,
                            to: destination
                        )
                    }
                )
            )
        case .folderFileOperation(let request):
            FolderFileOperationView(
                request: request,
                folderRelativePaths: appState.currentLibraryFolders,
                actions: FolderFileActions(
                    move: { target, destination in
                        try await appState.libraryMutationController.moveFolder(
                            target,
                            to: destination
                        )
                    }
                )
            )
        case .systemTrash(let preview):
            SystemTrashConfirmationView(
                preview: preview,
                confirm: { preview in
                    try await appState.libraryMutationController.executeSystemTrash(preview)
                    appState.presentationRouter.dismissSheet()
                },
                cancel: { appState.presentationRouter.dismissSheet() }
            )
        case .transactionRecovery:
            TransactionRecoveryView(
                records: appState.transactionRecoveryRecords,
                error: appState.transactionRecoveryError,
                interruptedSaves: appState.interruptedSaveRecoveries,
                interruptedSaveError: appState.interruptedSaveRecoveryError,
                vaultNames: Dictionary(
                    uniqueKeysWithValues: appState.registeredVaults.map { ($0.id, $0.name) }
                ),
                refresh: { await appState.refreshTransactionRecoveryRecords() },
                markResolved: { try await appState.markTransactionRecoveryResolved($0) },
                revealRecords: { appState.revealTransactionRecoveryRecordsInFinder() },
                loadInterruptedSave: {
                    try await appState.interruptedSaveRecoveryContent($0)
                },
                revealInterruptedSave: {
                    try await appState.revealInterruptedSaveRecoveryInFinder($0)
                },
                restoreInterruptedSave: {
                    try await appState.restoreInterruptedSaveRecovery($0)
                }
            )
        case .identityResolution(let ambiguity):
            IdentityResolutionView(
                ambiguity: ambiguity,
                vaultName: appState.currentDocumentVault?.name
                    ?? appState.currentRegisteredVault?.name
                    ?? "Current Vault",
                isResolving: appState.isResolvingIdentity,
                errorMessage: appState.identityResolutionError,
                onConfirm: { candidateID in
                    await appState.resolveSelectedIdentity(candidateID: candidateID)
                },
                onCancel: {
                    appState.presentationRouter.dismissSheet(if: route.id)
                    appState.identityResolutionError = nil
                }
            )
            .onDisappear {
                appState.identityResolutionError = nil
            }
        case .zoteroBinding(let route):
            ZoteroBindingPanelView(
                route: route,
                search: { query in
                    try await appState.zoteroCoordinator.searchLibrary(query: query)
                },
                prepareFill: { hit in
                    try await appState.zoteroCoordinator.prepareLinkAndFill(
                        noteID: route.noteID,
                        library: hit.library,
                        itemKey: hit.item.key
                    )
                },
                prepareRefresh: {
                    try await appState.zoteroCoordinator.prepareMetadataRefresh(
                        noteID: route.noteID
                    )
                },
                commitPlan: { plan in
                    try await appState.zoteroCoordinator.commitMetadataPlan(plan)
                    appState.presentationRouter.dismissSheet()
                },
                clearBinding: {
                    try await appState.zoteroCoordinator.clearBinding(noteID: route.noteID)
                    appState.presentationRouter.dismissSheet()
                },
                dismiss: { appState.presentationRouter.dismissSheet() }
            )
        }
    }

    private func note(at path: String) -> WindowDocumentLocation? {
        if appState.currentNote?.relativePath == path {
            return appState.currentNote
        }
        return appState.notes.first(where: { $0.relativePath == path })
    }

    private func finishMetadata(_ route: MetadataPanelRoute) {
        appState.presentationRouter.finishMetadata(route)
    }

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            researchNotificationBanner
            if !appState.transactionRecoveryRecords.isEmpty
                || !appState.interruptedSaveRecoveries.isEmpty
                || appState.transactionRecoveryError != nil
                || appState.interruptedSaveRecoveryError != nil {
                TransactionRecoveryNotice(
                    count: appState.transactionRecoveryRecords.count
                        + appState.interruptedSaveRecoveries.count,
                    error: appState.transactionRecoveryError
                        ?? appState.interruptedSaveRecoveryError
                ) {
                    appState.showTransactionRecovery = true
                }
            }
            detailContent
        }
    }

    @ViewBuilder
    private var researchNotificationBanner: some View {
        if !documentActivityNotifications.isEmpty {
            ResearchActivityNotificationStack(
                notifications: documentActivityNotifications,
                open: {
                    windowCoordinator.actions.showAttention(
                        .activityStack,
                        nil
                    )
                }
            )
            .scholiumAttentionPopover(
                anchor: .activityStack,
                session: appState.attentionPopoverSession
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
        }
        if let permission = shellState.researchNotificationPermissionNotice {
            ResearchNotificationPermissionView(
                kind: permission == .enable
                    ? .enableNotifications
                    : .openNotificationSettings,
                review: {
                    switch permission {
                    case .enable:
                        windowCoordinator.requestResearchNotificationAuthorization()
                    case .openSettings:
                        windowCoordinator.openResearchNotificationSettings()
                    }
                },
                dismiss: {
                    shellState.dismissResearchNotificationPermissionNotice()
                }
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
        }
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                note: note,
                shellState: appState.shellState,
                graph: appState.relationshipGraph,
                catalog: appState.workspaceCatalog,
                currentVaultID: appState.currentDocumentVaultID,
                researchInspectorContentContext: researchInspectorContentContext,
                researchActionsPresentation: appState.researchActionsPresentation(),
                researchActionFocusRequest: researchActionFocusRequest,
                registerResearchActionFocusOwner: {
                    pendingResearchActionFocusID = $0
                    researchActionDismissalFocusDisposition = .preserveInputModality
                },
                openResearchAction: { item in
                    if let activity = item.activity {
                        appState.openResearchActionStatus(
                            activity.primary
                        )
                    } else {
                        appState.openResearchAction(item.id)
                    }
                },
                endResearchActivity: { runID in
                    researchActionController.endActivity(runID: runID)
                },
                retryResearchActionCancellation: { runID in
                    researchActionController.retryCancellationRecovery(runID: runID)
                },
                openReference: { reference, sourceLine in
                    appState.researchController.requestOpen(
                        reference,
                        sourceLine: sourceLine
                    )
                },
                settle: { rationale in
                    guard let target = appState.currentResearchActionTarget else { return }
                    _ = try await appState.researchController.settle(
                        target.note,
                        expectedRevision: target.fingerprint,
                        rationale: rationale
                    )
                }
            )
        } else {
            VStack(spacing: 0) {
                if researchActionController.hasCancellationBarrier {
                    ResearchActionsInspectorView(
                        presentation: appState.researchActionsPresentation(),
                        freshness: .current,
                        focusRequest: nil,
                        registerFocusOwner: { _ in },
                        select: { _ in },
                        endActivity: { _ in },
                        retryRefresh: {},
                        retryCancellationRecovery: { runID in
                            researchActionController
                                .retryCancellationRecovery(runID: runID)
                        },
                        settle: { _ in }
                    )
                    .accessibilityIdentifier("scholium.researchActions.recoveryOnly")
                } else {
                    ScholiumContentStateView(
                        "No Document Selected",
                        indicator: .symbol("doc.text")
                    )
                    .accessibilityIdentifier("scholium.noDocumentInspectorState")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .scholiumSurface(.apparatus)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.currentNote != nil {
            DocumentFeatureView(
                controller: appState.documentController,
                state: documentFeatureState,
                actions: documentFeatureActions,
                critiqueProvenanceContext: critiqueProvenanceContext
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(
                    ScholiumMotion.documentRevealTransition(
                        showingDocument: true,
                        reduceMotion: reduceMotion
                    )
                )
                .zIndex(0)
        } else {
            ScholiumNoDocumentDetailView()
                .transition(
                    ScholiumMotion.documentRevealTransition(
                        showingDocument: false,
                        reduceMotion: reduceMotion
                    )
                )
        }
    }

}

private struct LibrarySurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scholiumSurface(.navigation)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library")
            .accessibilityIdentifier("scholium.librarySurface")
    }
}

struct ScholiumLaunchPlaceholderView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Opening Scholium")
    }
}

/// The configured workspace's restrained, read-only no-document state. The
/// Library remains the only actionable interface and this view owns no focus
/// or document state.
private struct ScholiumNoDocumentDetailView: View {
    var body: some View {
        ZStack {
            ScholiumColorRole.documentBackground.color
                .accessibilityHidden(true)

            ScholiumContentStateView(
                "No Document Selected",
                detail: Text("Select a note in the Library to read or edit."),
                indicator: .symbol("doc.text")
            )
            .accessibilityIdentifier("scholium.noDocumentState")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SpotlightSearchOverlay: View {
    @ObservedObject private var controller: DiscoveryController
    let context: SpotlightSearchContext

    init(controller: DiscoveryController, context: SpotlightSearchContext) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: context.dismiss)
                    .accessibilityHidden(true)

                SpotlightSearchPanelView(
                    controller: controller,
                    context: context,
                    maxPanelHeight: max(
                        ScholiumMetrics.Search.collapsedHeight,
                        geometry.size.height
                            - (ScholiumMetrics.Search.responsiveMargin * 2)
                    )
                )
                    .frame(width: panelWidth(for: geometry.size.width))
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .padding(.top, ScholiumMetrics.Search.responsiveMargin)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityValue(searchPresentationValue)
        .accessibilityIdentifier("scholium.searchWorkspace")
    }

    private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            ScholiumMetrics.Search.preferredWidth,
            max(
                320,
                availableWidth - (ScholiumMetrics.Search.responsiveMargin * 2)
            )
        )
    }

    private var searchPresentationValue: String {
        controller.search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "Collapsed" : "Expanded"
    }
}

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(ScholiumMetrics.Workspace.loadingOverlayInset)
            .scholiumEditorialSurface(
                .floatingControl,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.loadingSurfaceCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("scholium.loadingOverlay")
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let symbol: String
    let colorRole: ScholiumColorRole

    init(toast: WindowToast) {
        message = toast.message
        symbol = toast.kind.symbol
        colorRole = toast.kind.colorRole
    }

    init(message: String) {
        self.message = message
        symbol = "checkmark.circle"
        colorRole = .confirmed
    }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: symbol)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(colorRole)
            Text(message)
                .font(ScholiumTypography.interface(.rowTitle))
        }
        .padding(.horizontal, ScholiumMetrics.Workspace.toastHorizontalInset)
        .padding(.vertical, ScholiumMetrics.Workspace.toastVerticalInset)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ResearchNotificationPermissionView: View {
    enum Kind {
        case enableNotifications
        case openNotificationSettings
    }

    let kind: Kind
    let review: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            Image(systemName: symbol)
                .font(ScholiumTypography.interface(.body, emphasis: .strong))
                .scholiumForeground(.secondaryText)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.labelAccessoryGap
            ) {
                Text(title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(detail)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionButton
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .accessibilityLabel("Dismiss")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, ScholiumMetrics.Workspace.toastHorizontalInset)
        .padding(.vertical, ScholiumMetrics.Workspace.toastVerticalInset)
        .frame(maxWidth: 520, alignment: .leading)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var symbol: String {
        "bell"
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(actionTitle, action: review)
            .controlSize(.small)
            .buttonStyle(.bordered)
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .enableNotifications: "Get Notified When Results Are Ready"
        case .openNotificationSettings: "Notifications Are Off"
        }
    }

    private var detail: LocalizedStringResource {
        switch kind {
        case .enableNotifications:
            "Scholium can notify you when the app is in the background."
        case .openNotificationSettings:
            "Turn on Scholium notifications in System Settings if you want background alerts."
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch kind {
        case .enableNotifications: "Enable Notifications"
        case .openNotificationSettings: "Open Settings"
        }
    }

    private var identifier: String {
        "scholium.researchNotificationPermission"
    }
}

// MARK: - Preview

#Preview {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let workspaceStore = try! WorkspaceStore(
        applicationSupportURL: repositoryRoot
            .appendingPathComponent(".build/previews", isDirectory: true)
            .appendingPathComponent("ContentView", isDirectory: true)
    )
    let model = WindowModel(workspaceStore: workspaceStore)
    let coordinator = WorkspaceWindowCoordinator(
        windowID: model.nativeWindowID,
        appState: model,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry()
    )
    ContentView(appState: model, windowCoordinator: coordinator)
        .frame(width: 1100, height: 700)
}
