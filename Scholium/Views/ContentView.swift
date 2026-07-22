import AppKit
import ScholiumContracts
import SwiftUI

private enum CommentExchangePresentationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Comment is unavailable until Scholium can identify the selected Analysis, Topic, or Work reliably."
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: WindowModel
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let windowCoordinator: WorkspaceWindowCoordinator
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

    var body: some View {
        ScholiumWorkspaceSplitView(
            initialLibraryVisible: shellLibraryVisible,
            initialApparatusVisible: shellApparatusVisible,
            documentTabs: appState.documentTabController.tabs,
            selectedDocumentTabID: appState.documentTabController.selectedTabID,
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
                if !appState.hasCompletedInitialRestore {
                    ScholiumLaunchPlaceholderView()
                } else {
                    detailRegion
                }
            }
            .scholiumSurface(.document)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 20)
            }
        }
        .animation(
            ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
            value: appState.toastMessage
        )
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
                .scholiumEditorialSurface(
                    .floatingControl,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                        style: .continuous
                    )
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
        .sheet(item: presentedSheet, onDismiss: {
            if appState.presentationRouter.sheet == nil,
               appState.researchController.functions.isPresented {
                appState.researchController.functions.dismiss()
            }
        }) { route in
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
        .task(id: appState.currentResearchFunctionTarget) {
            await appState.refreshResearchFunctionAvailability()
        }
    }

    private var shellLibraryVisible: Bool {
        guard appState.hasCompletedInitialRestore,
              appState.vaultConfig != nil
        else { return true }
        return appState.sidebarVisible
    }

    private var shellApparatusVisible: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && appState.hasCompletedInitialRestore
            && appState.vaultConfig != nil
            && appState.researchInspectorVisible
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
            dismiss: { appState.dismissSearch() },
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
            refresh: { await appState.refreshWorkspaceCatalog() },
            close: { appState.discoveryController.showAttentionQueue(false) }
        )
    }

    private var researchInspectorContentContext: ResearchInspectorContentContext {
        ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                researchUnit: appState.currentNote?.researchUnit
                    ?? ResearchUnitDeclaration(frontmatter: [:]),
                currentVault: appState.currentDocumentVault,
                analysesVaultID: appState.workspaceAssignment?.workspace.paperAnalysisVaultID,
                catalog: appState.workspaceCatalog,
                visibleAttentionItems: visibleCurrentDocumentAttentionItems,
                freshness: researchProjectionFreshness,
                propertiesConfiguration: appState.currentDocumentPropertiesConfiguration
            ),
            openResearchRecord: {
                windowCoordinator.actions.showResearchRecord()
            },
            openProperties: {
                guard let path = appState.currentNote?.relativePath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            customizeProperties: {
                settingsModel.selectPane(.properties)
                openSettings()
            },
            openAttention: {
                appState.discoveryController.showAttentionQueue(true)
            },
            retryRefresh: {
                Task { await appState.retryDerivedRefresh() }
            },
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
                appState.showToast(String(localized: "Zotero source confirmed for \(title).", table: "Localizable", bundle: .module))
            }
        )
    }

    private var currentCritique: CritiqueAssociation? {
        guard appState.currentDocumentVaultRole == .draftProject,
              let noteID = appState.currentDocumentDescriptor?.sessionKey.noteID else {
            return nil
        }
        return appState.researchController.records?.critiques.first {
            $0.workNoteID == noteID
        }
    }

    private var visibleCurrentDocumentAttentionItems: [AttentionQueueItem] {
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID else { return [] }
        let matching = (appState.workspaceCatalog?.attention ?? []).filter {
            $0.note.vaultID == vaultID && $0.note.relativePath == note.relativePath
        }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(matching)
    }

    private var researchProjectionFreshness: ResearchProjectionFreshness {
        if appState.isRefreshingWorkspaceCatalog { return .refreshing }
        switch appState.derivedRefreshStatus {
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
            ordinarySearchScope: appState.ordinarySearchScope,
            currentVaultID: appState.currentDocumentVaultID,
            vaultRole: appState.currentDocumentVaultRole,
            locationScope: appState.currentDocumentDescriptor == nil
                ? appState.noteLocationScope
                : .workspace,
            noteIdentityByPath: appState.currentDocumentIdentityByPath,
            documentRevisions: appState.currentDocumentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            propertiesConfiguration: appState.currentDocumentPropertiesConfiguration,
            annotations: appState.currentDocumentAnnotations,
            commentExchanges: appState.researchController.records?.commentExchanges ?? [],
            requestedCommentExchangeID: appState.requestedCommentExchangeID,
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
            isResolvingIdentity: appState.isResolvingIdentity
        )
    }

    private var documentFeatureActions: DocumentFeatureActions {
        let documentPath = appState.currentNote?.relativePath
        let triptychID = appState.workspaceAssignment?.id
        return DocumentFeatureActions(
            requestIdentityResolution: {
                guard let path = documentPath else { return }
                appState.requestIdentityResolution(for: path)
            },
            retryIdentityRecovery: { await appState.retryIdentityRecovery() },
            beginSearch: { appState.beginSearch($0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            clearPendingSourceLine: { appState.pendingSourceLine = nil },
            clearPendingSourceRange: { appState.pendingSourceRange = nil },
            createAnnotation: { anchor, text in
                guard let path = documentPath else { return }
                _ = try await appState.addAnnotation(
                    to: path,
                    text: text,
                    anchor: anchor
                )
            },
            updateAnnotation: { annotationID, text in
                guard let path = documentPath else { return }
                try await appState.updateAnnotation(
                    at: path,
                    annotationID: annotationID,
                    text: text
                )
            },
            deleteAnnotation: { annotationID in
                guard let path = documentPath else { return }
                try await appState.deleteAnnotation(
                    at: path,
                    annotationID: annotationID
                )
            },
            createCommentExchange: { anchor, message in
                guard let target = appState.currentResearchFunctionTarget else {
                    throw CommentExchangePresentationError.unavailable
                }
                return try await appState.researchController.createCommentExchange(
                    CommentExchange(
                        note: ResearchActivityNoteReference(
                            noteID: target.noteID,
                            note: target.note,
                            role: target.role,
                            title: target.title
                        ),
                        anchor: anchor,
                        turns: [CommentExchangeTurn(author: .researcher, text: message)]
                    )
                )
            },
            appendCommentExchangeTurn: { exchangeID, author, text in
                try await appState.researchController.appendCommentExchangeTurn(
                    exchangeID: exchangeID,
                    turn: CommentExchangeTurn(author: author, text: text)
                )
            },
            finishCommentExchange: { exchangeID in
                try await appState.researchController.finishCommentExchange(
                    exchangeID: exchangeID
                )
            },
            clearRequestedCommentExchange: {
                appState.requestedCommentExchangeID = nil
            },
            handoffCommentRequest: { instructions in
                appState.agentApplicationHandoff.copyAndOpen(
                    instructions: instructions,
                    copy: { try appState.copyTextToClipboard($0) }
                )
            },
            copyCommentRequest: { instructions in
                appState.agentApplicationHandoff.copyOnly(
                    instructions: instructions,
                    copy: { try appState.copyTextToClipboard($0) }
                )
            },
            commentReplyCommand: { exchangeID in
                let selector = triptychID.map { " --triptych \($0.uuidString)" } ?? ""
                return "scholium comment reply \(exchangeID.uuidString) --agent \"AGENT_NAME\" --from -\(selector)"
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
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            editProperties: {
                guard let path = documentPath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            openResearchFunction: { function, selection in
                appState.openResearchFunction(function, selection: selection)
            },
            setResearchInspectorVisible: {
                windowCoordinator.actions.setResearchInspectorVisible($0)
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
        let selectedLibraryDocumentPath = appState.currentDocumentVaultID
            == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionItems: appState.workspaceCatalog?.attention,
            filteredNotes: appState.filteredNotes,
            allNotes: appState.notes,
            currentVaultID: appState.currentRegisteredVault?.id,
            disclosureScope: appState.currentRegisteredVault.map {
                LibraryDisclosureScope(
                    vaultID: $0.id,
                    locationScope: appState.noteLocationScope
                )
            },
            selectedDocumentPath: selectedLibraryDocumentPath,
            libraryFocusRequestGeneration: appState.libraryFocusRequestGeneration,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            noteLifecycleRequest: appState.noteLifecycleRequest,
            lifecycleMutationGeneration: appState.lifecycleMutationGeneration,
            catalogIsAvailable: appState.workspaceCatalog != nil,
            graphIsAvailable: appState.relationshipGraph != nil,
            tags: appState.allTags,
            statuses: appState.availableStatuses,
            authors: appState.availableAuthors,
            years: appState.availableYears,
            propertyKeys: propertyFilterOptions.keys,
            propertyValues: propertyFilterOptions.valuesByKey,
            resolvedIdentityPaths: Set(appState.noteIdentityByPath.keys),
            bibliographyController: appState.researchController.bibliography,
            attentionQueueContext: attentionQueueContext,
            notesAreOrdered: { appState.notesAreOrdered($0, $1) },
            selectLocationScope: { appState.requestNoteLocationScope($0) },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            openLifecycleNote: { appState.requestLifecycleNote($0, in: $1) },
            selectWorkspaceVault: { appState.requestWorkspaceVault($0) },
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
            openRecommendedAnalysis: { reference in
                guard let note = appState.workspaceCatalog?.notes.first(where: {
                    $0.reference.vaultID == reference.vaultID
                        && $0.reference.relativePath == reference.relativePath
                }) else { return }
                appState.requestOpenNote(note.reference)
            },
            openRecommendedZoteroItem: { itemKey in
                await appState.zoteroBridge.openInZotero(zoteroKey: itemKey)
            },
            copyRecommendedBibliographyText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                appState.showToast(String(localized: "Research instructions copied.", table: "Localizable", bundle: .module))
            },
            repairRecommendedBibliographyMethod: {
                UserDefaults.standard.set(
                    WorkspaceSettingsPane.researchGuidance.rawValue,
                    forKey: "scholium.settings.selectedPane"
                )
                UserDefaults.standard.set(
                    "skills",
                    forKey: "scholium.settings.researchGuidanceCollection"
                )
                openSettings()
            },
            revealCurrentVault: { appState.revealVaultInFinder() },
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            openSettings: { openSettings() },
            selectSortOrder: { appState.noteSortOrder = $0 },
            showError: { appState.showToast($0, kind: .error) }
        )
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        appState.currentWorkspaceSlot
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
        case .frontmatter(let route):
            if let note = note(at: route.path) {
                FrontmatterEditorView(
                    note: note,
                    configuredEditableFields: appState.currentDocumentPropertiesConfiguration.map {
                        Set($0.editableFields)
                    },
                    expectedRevision: appState.currentDocumentRevisions[note.relativePath],
                    onClose: {
                        finishFrontmatter(route)
                    }
                ) { proposedFrontmatter, researchUnitEdit, revision in
                    _ = try await appState.saveProperties(
                        for: note,
                        proposedFrontmatter: proposedFrontmatter,
                        expectedRevision: revision,
                        researchUnitEdit: researchUnitEdit
                    )
                    appState.showToast(String(localized: "Frontmatter saved", table: "Localizable", bundle: .module))
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .researchFunction(let route):
            if note(at: route.target.relativePath) != nil {
                ResearchFunctionPanelView(
                    controller: appState.researchController.functions,
                    context: ResearchFunctionPanelContext(
                        repairCitationMethod: {
                            UserDefaults.standard.set(
                                WorkspaceSettingsPane.researchGuidance.rawValue,
                                forKey: "scholium.settings.selectedPane"
                            )
                            UserDefaults.standard.set(
                                "skills",
                                forKey: "scholium.settings.researchGuidanceCollection"
                            )
                            openSettings()
                        },
                        repairDiscussResponseDefaults: {
                            UserDefaults.standard.set(
                                WorkspaceSettingsPane.researchGuidance.rawValue,
                                forKey: "scholium.settings.selectedPane"
                            )
                            UserDefaults.standard.set(
                                "prompt-templates",
                                forKey: "scholium.settings.researchGuidanceCollection"
                            )
                            UserDefaults.standard.set(
                                "dialogue-response",
                                forKey: "scholium.settings.researchGuidancePromptSection"
                            )
                            openSettings()
                        },
                        agentApplicationHandoff: appState.agentApplicationHandoff,
                        copyInstructions: { instructions in
                            try appState.copyTextToClipboard(instructions)
                            appState.showToast(String(localized: "Function instructions copied.", table: "Localizable", bundle: .module))
                        },
                        dismiss: {
                            appState.presentationRouter.dismissSheet()
                        }
                    )
                )
                .onDisappear {
                    // Normal sheet dismissal is finalized by the root
                    // `onDismiss`, after AppKit has yielded keyboard focus.
                    // A direct route replacement still invalidates this draft
                    // immediately so it cannot leak into the next sheet.
                    if appState.presentationRouter.sheet != nil,
                       !appState.presentationRouter.suspendsResearchFunction(
                           presentationID: route.presentationID
                       ) {
                        appState.researchController.functions.dismiss(
                            presentationID: route.presentationID
                        )
                    }
                }
            }
        case .createCheckpoint:
            CreateCheckpointView { name in
                _ = try await appState.createCheckpoint(name: name, kind: .manual)
                appState.showToast(String(localized: "Checkpoint created.", table: "Localizable", bundle: .module))
            }
        case .restoreCheckpoint:
            RestoreCheckpointView(
                controller: appState.researchController,
                restoreCheckpoint: { checkpointID, selection in
                    _ = try await appState.restoreCheckpoint(
                        checkpointID,
                        selection: selection
                    )
                    appState.showToast(String(localized: "Checkpoint restored. Before Restore checkpoint created.", table: "Localizable", bundle: .module))
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
                    create: { path, title, researchStatus in
                        _ = try await appState.createNote(
                            relativePath: path,
                            title: title,
                            analysisResearchStatus: researchStatus
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
        }
    }

    private func note(at path: String) -> WindowDocumentLocation? {
        if appState.currentNote?.relativePath == path {
            return appState.currentNote
        }
        return appState.notes.first(where: { $0.relativePath == path })
    }

    private func finishFrontmatter(_ route: FrontmatterPanelRoute) {
        appState.presentationRouter.finishFrontmatter(route)
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
            detailContent
        }
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                note: note,
                controller: appState.researchController,
                graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                catalog: appState.workspaceCatalog,
                currentVaultID: appState.currentDocumentVaultID,
                researchInspectorContentContext: researchInspectorContentContext,
                researchFunctionsPresentation: appState.researchFunctionsPresentation(
                    critique: currentCritique
                ),
                openResearchFunction: { appState.openResearchFunction($0) },
                openResearchRecord: {
                    windowCoordinator.actions.showResearchRecord()
                },
                openComment: { exchangeID in
                    appState.requestedCommentExchangeID = exchangeID
                },
                settle: { rationale in
                    guard let target = appState.currentResearchFunctionTarget else { return }
                    _ = try await appState.researchController.settle(
                        target.note,
                        expectedRevision: target.fingerprint,
                        rationale: rationale
                    )
                }
            )
        } else {
            Color.clear
                .scholiumSurface(.apparatus)
                .accessibilityHidden(true)
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.995)))
                .zIndex(0)
        } else {
            ScholiumNoDocumentDetailView()
                .transition(.opacity)
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

/// The configured workspace's intentionally silent no-document state. The
/// Library remains the only actionable interface.
private struct ScholiumNoDocumentDetailView: View {
    var body: some View {
        ScholiumColorRole.documentBackground.color
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .accessibilityIdentifier("scholium.noDocumentSurface")
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
            .padding(28)
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
    let color: Color

    init(toast: WindowModel.Toast) {
        message = toast.message
        symbol = toast.kind.symbol
        color = toast.kind.color
    }

    init(message: String) {
        self.message = message
        symbol = "checkmark.circle"
        color = ScholiumColorRole.confirmed.color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(color)
            Text(message)
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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

// MARK: - Preview

#Preview {
    let workspaceStore = WorkspaceStore()
    let model = WindowModel(workspaceStore: workspaceStore)
    let coordinator = WorkspaceWindowCoordinator(
        windowID: model.nativeWindowID,
        appState: model,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry()
    )
    ContentView(windowCoordinator: coordinator)
        .environmentObject(model)
        .frame(width: 1100, height: 700)
}
