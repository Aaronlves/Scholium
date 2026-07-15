import ScholiumContracts
import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: WindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            Group {
                if !appState.hasCompletedInitialRestore {
                    ScholiumLaunchPlaceholderView()
                } else if appState.vaultConfig == nil {
                    WorkspaceSetupView(context: workspaceSetupContext)
                } else if appState.currentNote == nil {
                    TriptychInterfaceSurface(isElevatedOverDocument: false) {
                        SidebarView(
                            controller: appState.discoveryController,
                            context: sidebarContext
                        )
                    }
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )
                        .background(.regularMaterial)
                } else {
                    NavigationSplitView(columnVisibility: sidebarVisibility) {
                        TriptychInterfaceSurface(isElevatedOverDocument: true) {
                            SidebarView(
                                controller: appState.discoveryController,
                                context: sidebarContext
                            )
                        }
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .navigationSplitViewColumnWidth(
                                min: 300,
                                ideal: ScholiumMetrics.Triptych.preferredWidth,
                                max: ScholiumMetrics.Triptych.preferredWidth
                            )
                    } detail: {
                        detailRegion
                    }
                    .navigationSplitViewStyle(.prominentDetail)
                    .toolbar(removing: .sidebarToggle)
                    .navigationTitle(windowTitle)
                }
            }
            .onAppear { updateAdaptiveLayout(for: geometry.size.width, isInitial: true) }
            .onChange(of: geometry.size.width) { _, width in
                updateAdaptiveLayout(for: width)
            }
        }
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let status = appState.refreshStatusText {
                HStack(spacing: 7) {
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
                        .font(.caption.weight(.semibold))
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    reduceTransparency
                        ? Color(nsColor: .controlBackgroundColor)
                        : Color.clear,
                    in: Capsule()
                )
                .glassEffect(
                    appState.hasDerivedRefreshFailure
                        ? .regular.tint(.orange.opacity(0.18))
                        : .regular,
                    in: Capsule()
                )
                .padding(10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.refreshStatus")
            }
        }
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
                    .transition(.opacity.combined(with: .scale(0.98)))
            }
        }
        .overlay {
            if appState.showSearchSurface {
                SpotlightSearchOverlay(
                    controller: appState.discoveryController,
                    context: spotlightSearchContext
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(20)
            }
        }
        .animation(
            ScholiumMotion.searchPresentation(reduceMotion: reduceMotion),
            value: appState.showSearchSurface
        )
        .sheet(item: presentedSheet) { route in
            sheetContent(for: route)
        }
        .alert(item: presentedAlert) { alert in
            Alert(
                title: Text("Could Not Complete Action"),
                message: Text(alert.message),
                dismissButton: .default(Text("Dismiss")) {
                    appState.presentationRouter.alert = nil
                }
            )
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                appState.windowWidth >= 980 || appState.sidebarVisible ? .all : .detailOnly
            },
            set: { visibility in
                // The Triptych Interface is the workflow center whenever a
                // document window has enough room for it. SwiftUI can write
                // `.detailOnly` while the window is growing from its compact
                // interface frame; do not let that transient layout decision
                // hide the Interface after the note finishes sliding out.
                appState.sidebarVisible = appState.windowWidth >= 980
                    ? true
                    : visibility != .detailOnly
            }
        )
    }

    private var showsTrailingContext: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && (appState.backlinksVisible || appState.noteHistoryVisible)
            && appState.usesWideWindowLayout
            && appState.currentNote != nil
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

    private var spotlightSearchContext: SpotlightSearchContext {
        SpotlightSearchContext(
            savedSearches: appState.savedSearches,
            refresh: { await appState.refreshAdvancedSearch() },
            dismiss: { appState.showSearchSurface = false },
            save: { appState.saveCurrentSearch(named: $0) },
            run: { appState.runSavedSearch($0) },
            rename: { appState.renameSavedSearch($0, to: $1) },
            move: { appState.moveSavedSearch($0, by: $1) },
            delete: { appState.deleteSavedSearch($0) }
        )
    }

    private var attentionQueueContext: AttentionQueueContext {
        AttentionQueueContext(
            items: appState.workspaceCatalog?.attention ?? [],
            errorMessage: appState.workspaceCatalogError,
            isRefreshing: appState.isRefreshingWorkspaceCatalog,
            dismissalDays: appState.triptychSettings.attentionDismissalDays,
            refresh: { await appState.refreshWorkspaceCatalog() }
        )
    }

    private var relationshipViewContext: RelationshipViewContext {
        RelationshipViewContext(
            currentVault: appState.currentRegisteredVault,
            analysesVaultID: appState.workspaceAssignment?.workspace.paperAnalysisVaultID,
            catalog: appState.workspaceCatalog,
            attentionDismissalDays: appState.triptychSettings.attentionDismissalDays,
            resolveZoteroSource: { source in
                try await appState.zoteroBridge.resolve(source: source)
            },
            openZoteroItem: { itemKey in
                await appState.zoteroBridge.openInZotero(zoteroKey: itemKey)
            },
            confirmZoteroItem: { itemKey, reference in
                try await appState.confirmZoteroItemKey(itemKey, for: reference)
            },
            didConfirmZoteroSource: { title in
                appState.showToast("Zotero source confirmed for \(title).")
            }
        )
    }

    private var critiqueProvenanceContext: CritiqueProvenanceContext {
        CritiqueProvenanceContext(
            availableNotes: appState.notes,
            documentRevisions: appState.documentRevisions,
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
            notes: appState.notes,
            activeTab: appState.activeTab,
            openTabs: appState.openTabs,
            currentVaultID: appState.currentRegisteredVault?.id,
            vaultRole: appState.currentVaultRole,
            locationScope: appState.noteLocationScope,
            noteIdentityByPath: appState.noteIdentityByPath,
            documentRevisions: appState.documentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            propertiesConfiguration: appState.currentPropertiesConfiguration,
            reviewRecord: path.flatMap { appState.humanReviewRecord(for: $0) },
            reviewDisplayState: path.map { appState.reviewDisplayState(for: $0) } ?? .notReviewed,
            changedSinceReview: path.map(appState.changedSinceReviewPaths.contains) ?? false,
            canComment: appState.canCommentCurrentNote,
            canEdit: appState.canEditCurrentNote,
            documentTextScale: appState.documentTextScale,
            readCSS: appState.cssSnippetStore.readCSS,
            livePreviewCSS: appState.cssSnippetStore.livePreviewCSS,
            initialScrollFraction: path.map { appState.scrollPosition(for: $0) } ?? 0,
            requestedPresentationMode: appState.requestPresentationMode,
            pendingSourceLine: appState.pendingSourceLine,
            storedPresentationMode: path.map { appState.presentationMode(for: $0) } ?? .read,
            isCompactLayout: appState.layoutMode == .compact,
            noteHistoryVisible: appState.noteHistoryVisible,
            researchInspectorVisible: appState.backlinksVisible,
            identityAmbiguity: path.flatMap { appState.identityAmbiguity(for: $0) },
            pendingIdentityRebinding: path.flatMap { appState.pendingIdentityRebinding(for: $0) },
            identityMigrationFailureMessage: path
                .flatMap { appState.identityMigrationFailure(for: $0)?.message },
            isResolvingIdentity: appState.isResolvingIdentity
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
            beginSearch: { appState.beginSearch(mode: $0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            registerEditorFlush: { path, token, flush in
                appState.registerEditorFlush(for: path, token: token, flush: flush)
            },
            unregisterEditorFlush: { appState.unregisterEditorFlush(token: $0) },
            clearPendingSourceLine: { appState.pendingSourceLine = nil },
            requestComments: { selection, commentID in
                guard let path = documentPath else { return }
                appState.requestResearcherComments(
                    at: path,
                    selection: selection,
                    focusedCommentID: commentID
                )
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
                guard let path = documentPath else { return }
                appState.rememberPresentationMode($0, for: path)
            },
            setPendingSourceLine: { appState.pendingSourceLine = $0 },
            editProperties: {
                guard let path = documentPath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            openScholia: { appState.openScholia() },
            setNoteHistoryVisible: {
                appState.setNoteHistoryVisible($0, animated: false)
            },
            setResearchInspectorVisible: {
                appState.setResearchInspectorVisible($0, animated: false)
            },
            selectTab: { appState.requestSelectTab($0) },
            closeTab: { appState.requestCloseTab($0) },
            notify: { message, kind in
                switch kind {
                case .success: appState.showToast(message)
                case .information: appState.showToast(message, kind: .information)
                case .error: appState.showToast(message, kind: .error)
                }
            }
        )
    }

    private var noteHistoryContext: NoteHistoryContext {
        NoteHistoryContext(
            controller: appState.researchController,
            vaultRole: appState.currentVaultRole,
            documentRevisions: appState.documentRevisions,
            currentReview: { appState.humanReviewRecord(for: $0) },
            loadDialogue: { await appState.dialogueHistory(for: $0) },
            loadCritique: { await appState.critiqueAssociationRelated(to: $0) },
            loadCheckpoints: { try await appState.noteCheckpoints(for: $0) },
            checkpointContent: { try await appState.noteCheckpointContent($0, path: $1) },
            createCheckpoint: {
                _ = try await appState.createCheckpoint(name: $0, kind: .manual)
            },
            restoreNote: { try await appState.restoreNote($0, from: $1) },
            revealCheckpoints: { appState.revealCheckpointsInFinder() },
            copyText: { try appState.copyTextToClipboard($0) },
            openNote: { appState.requestOpenNote($0) },
            closeTrailing: {
                appState.setNoteHistoryVisible(false, animated: false)
            },
            notify: { appState.showToast($0) }
        )
    }

    private var sidebarContext: SidebarContext {
        let propertyFilterOptions = appState.availablePropertyFilterOptions
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionItems: appState.workspaceCatalog?.attention,
            filteredNotes: appState.filteredNotes,
            allNotes: appState.notes,
            currentVaultID: appState.currentRegisteredVault?.id,
            activeTab: appState.activeTab,
            hasCurrentNote: appState.currentNote != nil,
            hasVaultConfiguration: appState.vaultConfig != nil,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            noteLifecycleRequest: appState.noteLifecycleRequest,
            lifecycleMutationGeneration: appState.lifecycleMutationGeneration,
            catalogIsAvailable: appState.workspaceCatalog != nil,
            graphIsAvailable: appState.relationshipGraph != nil,
            hasUnqualifiedReview: appState.humanReviewRecords.values.contains {
                $0.latestReview?.qualification == .unqualified
            },
            changedSinceReviewCount: appState.changedSinceReviewPaths.count,
            tags: appState.allTags,
            statuses: appState.availableStatuses,
            authors: appState.availableAuthors,
            years: appState.availableYears,
            propertyKeys: propertyFilterOptions.keys,
            propertyValues: propertyFilterOptions.valuesByKey,
            resolvedIdentityPaths: Set(appState.noteIdentityByPath.keys),
            reviewDisplayState: { appState.reviewDisplayState(for: $0) },
            notesAreOrdered: { appState.notesAreOrdered($0, $1) },
            presentAttention: { appState.showAttentionQueues = true },
            revealCurrentVault: { appState.revealVaultInFinder() },
            collapseNote: { appState.requestCollapseNote() },
            selectLocationScope: { appState.requestNoteLocationScope($0) },
            openNote: { appState.requestOpenNote($0, inNewTab: $1) },
            openLifecycleNote: { appState.requestLifecycleNote($0, in: $1) },
            selectWorkspaceVault: { appState.requestWorkspaceVault($0) },
            presentScholia: { appState.requestOpenScholia(for: $0) },
            lifecycleItems: { try await appState.lifecycleLocationItems(for: $0) },
            prepareLifecycle: { appState.prepareLifecycleOperation($0) },
            clearPreparedLifecycle: { appState.clearPreparedLifecycleOperation(at: $0) },
            revealNote: { appState.showInFinder($0) },
            setAside: { try await appState.setAsideNote($0) },
            moveToTrash: { try await appState.moveNoteToTrash($0) },
            deletePermanently: { try await appState.deleteNotePermanently($0) },
            classify: { path, slot, destination in
                try await appState.classifyUnclassified(
                    path,
                    into: slot,
                    destination: destination
                )
            },
            selectSortOrder: { appState.noteSortOrder = $0 },
            showError: { appState.showToast($0, kind: .error) }
        )
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        guard let assignment = appState.workspaceAssignment,
              let current = appState.currentRegisteredVault else { return nil }
        return WorkspaceVaultSlot.allCases.first { slot in
            guard let assigned = assignment.vault(for: slot) else { return false }
            return current.id == assigned.id || current.canonicalPath == assigned.canonicalPath
        }
    }

    private var workspaceSetupContext: WorkspaceSetupContext {
        WorkspaceSetupContext(
            isCreatingNewTriptych: appState.isCreatingNewTriptych,
            targetTriptychID: appState.workspaceAssignment?.id,
            workspaceAssignment: appState.workspaceAssignment,
            registeredTriptychs: appState.registeredTriptychs,
            recoveryMessage: appState.workspaceRecoveryMessage,
            isInitialConfiguration: appState.vaultConfig == nil,
            refreshAssignment: { await appState.refreshWorkspaceAssignment() },
            portableContainerURL: { await appState.portableContainerURL(for: $0) },
            configure: { selection in
                try await appState.configureThreeVaultWorkspace(
                    paperAnalysisURL: selection.paperAnalysisURL,
                    topicKnowledgeURL: selection.topicKnowledgeURL,
                    outputURL: selection.outputURL,
                    portableContainerURL: selection.portableContainerURL,
                    triptychID: selection.triptychID,
                    triptychName: selection.triptychName
                )
                appState.workspaceRecoveryMessage = nil
            },
            dismiss: { appState.showWorkspaceSetup = false }
        )
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
        case .quickOpen:
            QuickOpenView(
                controller: appState.discoveryController,
                context: quickOpenContext
            )
        case .adaptiveContext:
            if let note = appState.currentNote {
                if appState.noteHistoryVisible {
                    NoteHistorySheet(
                        note: note,
                        presentation: .sheet,
                        context: noteHistoryContext
                    )
                        .onDisappear {
                            appState.setNoteHistoryVisible(false, animated: false)
                        }
                } else {
                    AdaptiveResearchInspectorSheet(
                        note: note,
                        controller: appState.researchController,
                        graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                        catalog: appState.workspaceCatalog,
                        currentVaultID: appState.currentRegisteredVault?.id,
                        relationshipViewContext: relationshipViewContext
                    ) {
                        appState.setResearchInspectorVisible(false, animated: false)
                    }
                    .environmentObject(appState)
                    .onDisappear {
                        appState.setResearchInspectorVisible(false, animated: false)
                    }
                }
            }
        case .workspaceSetup:
            WorkspaceSetupView(context: workspaceSetupContext)
        case .frontmatter(let path):
            if let note = note(at: path) {
                FrontmatterEditorView(
                    note: note,
                    configuredEditableFields: appState.currentPropertiesConfiguration.map {
                        Set($0.editableFields)
                    },
                    expectedRevision: appState.documentRevisions[note.relativePath]
                ) { proposedFrontmatter, researchUnitEdit, revision in
                    _ = try await appState.saveProperties(
                        for: note,
                        proposedFrontmatter: proposedFrontmatter,
                        expectedRevision: revision,
                        researchUnitEdit: researchUnitEdit
                    )
                    appState.showToast("Frontmatter saved")
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .scholia(let path):
            if let note = note(at: path) {
                let presentationID = appState.researchController.scholia.presentationID
                ScholiaPanelView(
                    note: note,
                    controller: appState.researchController,
                    context: scholiaContext(for: note)
                ) { destination in
                    scholiaDestination(destination, note: note)
                }
                    .onDisappear {
                        guard let presentationID else { return }
                        appState.researchController.dismissScholiaPresentation(id: presentationID)
                    }
            }
        case .attention:
            AttentionQueueView(
                controller: appState.discoveryController,
                context: attentionQueueContext
            )
        case .qualityReview(let path):
            if let note = note(at: path) {
                QualityReviewView(
                    note: note,
                    context: qualityReviewContext(for: note)
                )
            }
        case .researcherComments(let path):
            if let note = note(at: path) {
                ResearcherCommentsView(
                    note: note,
                    context: researcherCommentsContext(for: note)
                )
                    .onDisappear {
                        appState.pendingCommentSelection = nil
                        appState.focusedResearcherCommentID = nil
                    }
            }
        case .createCheckpoint:
            CreateCheckpointView { name in
                _ = try await appState.createCheckpoint(name: name, kind: .manual)
                appState.showToast("Checkpoint created.")
            }
        case .restoreCheckpoint:
            RestoreCheckpointView(
                controller: appState.researchController,
                restoreCheckpoint: { checkpointID, selection in
                    _ = try await appState.restoreCheckpoint(
                        checkpointID,
                        selection: selection
                    )
                    appState.showToast("Checkpoint restored. Before Restore checkpoint created.")
                },
                revealCheckpoints: {
                    appState.revealCheckpointsInFinder()
                }
            )
        case .lifecycle(let request):
            NoteLifecycleView(
                request: request,
                vaultRole: appState.currentVaultRole,
                actions: NoteLifecycleActions(
                    putBackDestination: {
                        appState.documentController.putBackDestination(for: $0)
                    },
                    create: { path, title, scope, limitations in
                        _ = try await appState.createNote(
                            relativePath: path,
                            title: title,
                            researchUnitScope: scope,
                            researchUnitLimitations: limitations
                        )
                    },
                    duplicate: { source, destination in
                        _ = try await appState.duplicateNote(source, to: destination)
                    },
                    move: { source, destination in
                        try await appState.moveNote(source, to: destination)
                    },
                    putBack: { try await appState.putBackNote($0) },
                    classify: { source, slot, destination in
                        try await appState.classifyUnclassified(
                            source,
                            into: slot,
                            destination: destination
                        )
                    }
                )
            )
        case .transactionRecovery:
            TransactionRecoveryView(
                records: appState.transactionRecoveryRecords,
                error: appState.transactionRecoveryError,
                vaultNames: Dictionary(
                    uniqueKeysWithValues: appState.registeredVaults.map { ($0.id, $0.name) }
                ),
                refresh: { await appState.refreshTransactionRecoveryRecords() },
                markResolved: { try await appState.markTransactionRecoveryResolved($0) },
                revealRecords: { appState.revealTransactionRecoveryRecordsInFinder() }
            )
        case .critique(let path):
            if let note = note(at: path) {
                CritiqueRequestView(
                    note: note,
                    context: critiqueRequestContext(for: note)
                )
            }
        case .identityResolution(let ambiguity):
            IdentityResolutionView(
                ambiguity: ambiguity,
                vaultName: appState.currentRegisteredVault?.name ?? "Current Vault",
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
        }
    }

    private var quickOpenContext: QuickOpenContext {
        QuickOpenContext(
            catalogIsAvailable: appState.workspaceCatalog != nil,
            catalogGeneration: appState.workspaceCatalog?.generatedAt,
            isRefreshingCatalog: appState.isRefreshingWorkspaceCatalog,
            catalogError: appState.workspaceCatalogError,
            refreshCatalog: { await appState.refreshWorkspaceCatalog() }
        )
    }

    private func note(at path: String) -> WindowDocumentLocation? {
        appState.notes.first(where: { $0.relativePath == path })
    }

    private func scholiaContext(for note: WindowDocumentLocation) -> ScholiaPanelContext {
        let hasResolvedIdentity = appState.noteIdentityByPath[note.relativePath] != nil
        return ScholiaPanelContext(
            vaultRole: appState.currentVaultRole,
            humanReviewRecord: appState.humanReviewRecord(for: note.relativePath),
            canComment: appState.canCommentCurrentNote,
            canHumanReview: appState.canHumanReviewCurrentNote,
            canEdit: appState.canEditCurrentNote,
            hasResolvedIdentity: hasResolvedIdentity,
            availableWindowWidth: appState.windowWidth,
            openComments: {
                appState.researcherCommentsPath = note.relativePath
            },
            prepareDialogue: {
                guard let vaultID = appState.currentRegisteredVault?.id,
                      hasResolvedIdentity else { return }
                appState.dialogueInitialNotes = [VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: note.relativePath
                )]
            }
        )
    }

    private func qualityReviewContext(for note: WindowDocumentLocation) -> QualityReviewContext {
        QualityReviewContext(
            revision: appState.documentRevisions[note.relativePath],
            record: appState.humanReviewRecord(for: note.relativePath),
            saveDraft: { revision, qualification, reviewNote in
                try await appState.saveHumanReviewDraft(
                    for: note.relativePath,
                    fingerprint: revision,
                    qualification: qualification,
                    reviewNote: reviewNote
                )
            },
            completeReview: { revision, qualification, reviewNote in
                try await appState.completeHumanReview(
                    for: note.relativePath,
                    fingerprint: revision,
                    qualification: qualification,
                    reviewNote: reviewNote
                )
            }
        )
    }

    private func critiqueRequestContext(for note: WindowDocumentLocation) -> CritiqueRequestContext {
        CritiqueRequestContext(
            triptychID: appState.workspaceAssignment?.id,
            existingCritiquePath: {
                await appState.critiqueAssociation(
                    for: note.relativePath
                )?.critiqueRelativePath
            },
            copyInstructions: { scope, lens, selectedRanges in
                _ = try await appState.copyCritiqueInstructions(
                    for: note.relativePath,
                    scope: scope,
                    lens: lens,
                    selectedRanges: selectedRanges,
                    additionalInstructions: ""
                )
            },
            didCopyInstructions: {
                appState.showToast(
                    "Critique instructions copied. Before Agent Work checkpoint created."
                )
            }
        )
    }

    private func researcherCommentsContext(for note: WindowDocumentLocation) -> ResearcherCommentsContext {
        ResearcherCommentsContext(
            initialComments: appState.humanReviewRecord(for: note.relativePath)?.comments ?? [],
            pendingSelection: appState.pendingCommentSelection,
            focusedCommentID: appState.focusedResearcherCommentID,
            clearPendingSelection: {
                appState.pendingCommentSelection = nil
            },
            add: { text, anchor in
                let record = try await appState.addResearcherComment(
                    to: note.relativePath,
                    text: text,
                    anchor: anchor
                )
                return record.comments
            },
            update: { commentID, text in
                try await appState.updateResearcherComment(
                    at: note.relativePath,
                    commentID: commentID,
                    text: text
                )
                return appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
            },
            setResolved: { commentID, resolved in
                try await appState.setResearcherCommentResolved(
                    at: note.relativePath,
                    commentID: commentID,
                    resolved: resolved
                )
                return appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
            },
            delete: { commentID in
                try await appState.deleteResearcherComment(
                    at: note.relativePath,
                    commentID: commentID
                )
                return appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
            },
            reattach: { commentID, anchor in
                try await appState.reattachResearcherComment(
                    at: note.relativePath,
                    commentID: commentID,
                    anchor: anchor
                )
                return appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
            },
            tryAutomaticReattachment: {
                let record = try await appState.tryReattachingResearcherComments(
                    at: note.relativePath
                )
                return record.comments
            }
        )
    }

    private func dialogueContext(for note: WindowDocumentLocation) -> DialogueContext {
        let fallbackInitialNote = appState.currentRegisteredVault.map {
            VaultQualifiedNoteID(vaultID: $0.id, relativePath: note.relativePath)
        }
        return DialogueContext(
            triptychID: appState.workspaceAssignment?.id,
            fallbackInitialNote: fallbackInitialNote,
            initialNotes: appState.dialogueInitialNotes,
            responseProfile: {
                try await appState.dialogueResponseProfile()
            },
            candidates: {
                try await appState.dialogueCandidates()
            },
            comments: { noteID in
                await appState.comments(for: noteID)
            },
            createDialogue: {
                instruction,
                selectedNotes,
                includedCommentIDs,
                requestedDestination,
                responseProfile in
                try await appState.createDialogue(
                    instruction: instruction,
                    selectedNotes: selectedNotes,
                    includedCommentIDs: includedCommentIDs,
                    requestedDestination: requestedDestination,
                    responseProfile: responseProfile
                )
            },
            didCreateDialogue: {
                appState.showToast(
                    "Instructions copied. Before Agent Work checkpoint created."
                )
                appState.dialogueInitialNotes = []
            }
        )
    }

    @ViewBuilder
    private func scholiaDestination(
        _ destination: ScholiaDestination,
        note: WindowDocumentLocation
    ) -> some View {
        switch destination {
        case .comments:
            ResearcherCommentsView(
                note: note,
                context: researcherCommentsContext(for: note)
            )
        case .review:
            QualityReviewView(
                note: note,
                context: qualityReviewContext(for: note)
            )
        case .critique:
            CritiqueRequestView(
                note: note,
                context: critiqueRequestContext(for: note)
            )
        case .dialogue:
            DialogueView(context: dialogueContext(for: note))
        }
    }

    private func updateAdaptiveLayout(for width: CGFloat, isInitial: Bool = false) {
        guard abs(appState.windowWidth - width) > 0.5 else { return }
        let previousLayoutMode = appState.layoutMode
        // GeometryReader is evaluated during layout. Defer observable state
        // changes until that pass completes to avoid recursive AppKit
        // constraint invalidation on beta macOS.
        DispatchQueue.main.async {
            guard abs(appState.windowWidth - width) > 0.5 else { return }
            appState.windowWidth = width
            if width < 1200, appState.backlinksVisible {
                appState.setResearchInspectorVisible(false, animated: false)
            }
            if width < 1200, appState.noteHistoryVisible {
                appState.setNoteHistoryVisible(false, animated: false)
            }
            if appState.currentNote == nil {
                appState.sidebarVisible = true
            } else if width < 980, isInitial || previousLayoutMode != .compact {
                appState.sidebarVisible = false
            } else if width >= 980, previousLayoutMode == .compact {
                appState.sidebarVisible = true
            }
        }
    }

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            if !appState.transactionRecoveryRecords.isEmpty || appState.transactionRecoveryError != nil {
                TransactionRecoveryNotice(
                    count: appState.transactionRecoveryRecords.count,
                    error: appState.transactionRecoveryError
                ) {
                    appState.showTransactionRecovery = true
                }
            }
            if showsTrailingContext, let note = appState.currentNote {
                // SwiftUI's `.inspector` host can recursively invalidate
                // NSWindow constraints on beta macOS when the selected note adds a
                // WebKit-backed document. HSplitView preserves the native trailing,
                // resizable inspector model without that unstable window host.
                HSplitView {
                    detailContent
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    if appState.noteHistoryVisible {
                        NoteHistorySheet(
                            note: note,
                            presentation: .trailing,
                            context: noteHistoryContext
                        )
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                    } else {
                        ResearchInspectorView(
                            note: note,
                            controller: appState.researchController,
                            graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                            catalog: appState.workspaceCatalog,
                            currentVaultID: appState.currentRegisteredVault?.id,
                            relationshipViewContext: relationshipViewContext
                        )
                            .frame(minWidth: 280, idealWidth: 322, maxWidth: 380, maxHeight: .infinity)
                    }
                }
            } else {
                detailContent
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        NoteTabView(
            controller: appState.documentController,
            state: documentFeatureState,
            actions: documentFeatureActions,
            critiqueProvenanceContext: critiqueProvenanceContext
        )
            .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .leading).combined(with: .opacity)
            )
            .zIndex(0)
    }

    private var windowTitle: String {
        appState.currentNote?.title ?? appState.currentNote?.displayName ?? "Scholium"
    }
}

private struct TriptychInterfaceSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let isElevatedOverDocument: Bool
    let content: Content

    init(
        isElevatedOverDocument: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isElevatedOverDocument = isElevatedOverDocument
        self.content = content()
    }

    var body: some View {
        content
            .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
            .overlay(alignment: .trailing) {
                if isElevatedOverDocument {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.24))
                        .frame(width: 0.5)
                        .shadow(
                            color: Color(nsColor: .shadowColor).opacity(0.14),
                            radius: 10,
                            x: 5
                        )
                        .allowsHitTesting(false)
                }
            }
            .zIndex(isElevatedOverDocument ? 2 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Triptych Interface")
            .accessibilityIdentifier("scholium.triptychInterface")
    }
}

private struct ScholiumLaunchPlaceholderView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Opening Scholium")
    }
}

private struct SpotlightSearchOverlay: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let context: SpotlightSearchContext

    init(controller: DiscoveryController, context: SpotlightSearchContext) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if reduceTransparency {
                    Rectangle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.08))
                }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: context.dismiss)
                    .accessibilityHidden(true)

                SpotlightSearchPanelView(
                    controller: controller,
                    context: context,
                    maxPanelHeight: max(180, geometry.size.height - 72)
                )
                    .frame(width: panelWidth(for: geometry.size.width))
                    .padding(.horizontal, 24)
                    .padding(.top, 36)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityValue(searchPresentationValue)
        .accessibilityIdentifier("scholium.searchWorkspace")
    }

    private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(1_060, max(320, availableWidth - 48))
    }

    private var searchPresentationValue: String {
        controller.search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "Collapsed" : "Expanded"
    }
}

private struct AdaptiveResearchInspectorSheet: View {
    let note: WindowDocumentLocation
    let controller: ResearchController
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let relationshipViewContext: RelationshipViewContext
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Research Inspector")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            ResearchInspectorView(
                note: note,
                controller: controller,
                graph: graph,
                catalog: catalog,
                currentVaultID: currentVaultID,
                relationshipViewContext: relationshipViewContext
            )
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.adaptiveContextPanel")
    }
}

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Quick Open View

struct QuickOpenContext {
    let catalogIsAvailable: Bool
    let catalogGeneration: Date?
    let isRefreshingCatalog: Bool
    let catalogError: String?
    let refreshCatalog: () async -> Void
}

struct QuickOpenView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var controller: DiscoveryController
    let context: QuickOpenContext
    @FocusState private var searchFocused: Bool
    @State private var refreshTask: Task<Void, Never>?

    init(controller: DiscoveryController, context: QuickOpenContext) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List(controller.quickOpen.results, selection: selection) { note in
                    Button {
                        open(note)
                    } label: {
                        ScholiumNoteRow(
                            title: note.title,
                            role: note.reference.vaultRole.displayName,
                            location: note.reference.relativePath,
                            symbol: note.reference.vaultRole.quickOpenSymbolName
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(note.id)
                    .accessibilityLabel(
                        "\(note.title), \(note.reference.vaultRole.displayName), \(note.reference.relativePath)"
                    )
                    .accessibilityHint("Open note")
                    .accessibilityIdentifier(
                        "scholium.quickOpenResult.\(note.reference.vaultRole.rawValue).\(note.reference.relativePath)"
                    )
                }
                .listStyle(.inset)

                if controller.quickOpen.results.isEmpty {
                    ContentUnavailableView {
                        Label(
                            controller.quickOpen.query.isEmpty ? "No Notes Available" : "No Matching Notes",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    } description: {
                        if context.isRefreshingCatalog {
                            Text("Scholium is preparing the Triptych catalog.")
                        } else if let error = context.catalogError,
                                  !context.catalogIsAvailable {
                            Text("The Triptych catalog is unavailable. \(error)")
                        } else if !context.catalogIsAvailable {
                            Text("The Triptych catalog is unavailable.")
                        } else if controller.quickOpen.query.isEmpty {
                            Text("Add a note to Analyses, Topics, or Works.")
                        } else {
                            Text("No title, path, or alias matches \"\(controller.quickOpen.query)\".")
                        }
                    } actions: {
                        if !context.catalogIsAvailable,
                           !context.isRefreshingCatalog {
                            Button("Retry") {
                                Task { await context.refreshCatalog() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Go to Note")
            .searchable(
                text: query,
                placement: .toolbar,
                prompt: "Title, path, or alias"
            )
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { openSelectedResult() }
            .onExitCommand { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 420)
        .accessibilityIdentifier("scholium.quickOpen")
        .onAppear {
            controller.resetQuickOpen()
            scheduleRefresh(immediate: true)
            searchFocused = true
        }
        .onChange(of: context.catalogGeneration) {
            scheduleRefresh(immediate: true)
        }
        .onMoveCommand { direction in
            switch direction {
            case .down: controller.moveQuickOpenSelection(by: 1)
            case .up: controller.moveQuickOpenSelection(by: -1)
            default:
                break
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            controller.resetQuickOpen()
        }
    }

    private var query: Binding<String> {
        Binding(
            get: { controller.quickOpen.query },
            set: { scheduleRefresh(query: $0) }
        )
    }

    private var selection: Binding<WorkspaceCatalogNote.ID?> {
        Binding(
            get: { controller.quickOpen.selectedResultID },
            set: { controller.selectQuickOpenResult($0) }
        )
    }

    private func openSelectedResult() {
        guard let id = controller.quickOpen.selectedResultID,
              let note = controller.quickOpen.results.first(where: { $0.id == id }) else { return }
        open(note)
    }

    private func open(_ note: WorkspaceCatalogNote) {
        controller.requestOpen(note.reference)
        dismiss()
    }

    private func scheduleRefresh(
        query: String? = nil,
        immediate: Bool = false
    ) {
        refreshTask?.cancel()
        let requestedQuery = query ?? controller.quickOpen.query
        controller.updateQuickOpenQuery(requestedQuery)
        refreshTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard !Task.isCancelled else { return }
            let request = controller.beginQuickOpen(requestedQuery)
            do {
                let results = try await controller.quickOpenResults(query: request.query)
                guard !Task.isCancelled else { return }
                controller.receiveQuickOpenResults(results, for: request)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                controller.receiveQuickOpenResults([], for: request)
            }
        }
    }
}

private extension VaultRole {
    var quickOpenSymbolName: String {
        switch self {
        case .sourceCorpus: "doc.text"
        case .topicKnowledge: "lightbulb"
        case .dissertationControl, .draftProject: "pencil.and.outline"
        case .other: "doc"
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: WindowModel.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind.symbol)
                .font(.callout)
                .foregroundStyle(toast.kind.color)
            Text(toast.message)
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    let workspaceStore = WorkspaceStore()
    ContentView()
        .environmentObject(WindowModel(workspaceStore: workspaceStore))
        .frame(width: 1100, height: 700)
}
