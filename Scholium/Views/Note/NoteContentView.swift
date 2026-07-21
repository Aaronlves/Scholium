import ScholiumContracts
import SwiftUI

enum DocumentNotificationKind {
    case success
    case information
    case error
}

struct DocumentFeatureState {
    let notes: [WindowDocumentLocation]
    let selectedDocumentPath: String?
    let ordinarySearchScope: SearchPresentationScope
    let currentVaultID: UUID?
    let vaultRole: VaultRole
    let locationScope: NoteLocationScope
    let noteIdentityByPath: [String: UUID]
    let documentRevisions: [String: DocumentFingerprint]
    let workspaceCatalog: WorkspaceCatalogSnapshot?
    let propertiesConfiguration: VaultPropertiesConfiguration?
    let reviewRecord: HumanReviewRecord?
    let reviewDisplayState: HumanReviewDisplayState
    let changedSinceReview: Bool
    let canComment: Bool
    let canEdit: Bool
    let isManagedCritique: Bool
    let documentTextScale: Double
    let appearanceCSS: String
    let readCSS: String
    let livePreviewCSS: String
    let initialScrollFraction: Double
    let requestedPresentationMode: NotePresentationMode?
    let pendingSourceLine: Int?
    let identityAmbiguity: NoteIdentityAmbiguity?
    let pendingIdentityRebinding: NoteIdentityPendingRebinding?
    let identityMigrationFailureMessage: String?
    let isResolvingIdentity: Bool
}

struct DocumentFeatureActions {
    let requestIdentityResolution: @MainActor () -> Void
    let retryIdentityRecovery: @MainActor () async -> Void
    let beginSearch: @MainActor (SearchInvocation) -> Void
    let clearRequestedPresentationMode: @MainActor () -> Void
    let clearPendingSourceLine: @MainActor () -> Void
    let requestComments: @MainActor (MarkdownReviewSelection?, UUID?) -> Void
    let rememberScrollPosition: @MainActor (Double) -> Void
    let openInternalLink: @MainActor (String) -> Void
    let openExternalURL: @MainActor (URL) -> Void
    let enterCSSSafeMode: @MainActor (String) -> Void
    let rememberPresentationMode: @MainActor (NotePresentationMode) -> Void
    let setPendingSourceLine: @MainActor (Int?) -> Void
    let setSidebarVisible: @MainActor (Bool) -> Void
    let editProperties: @MainActor () -> Void
    let openResearchFunction: @MainActor (
        ResearchFunctionID,
        ResearcherCommentAnchor?
    ) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
}

enum ResearchFunctionSelectionCapture {
    static func anchor(
        for selection: MarkdownReviewSelection?,
        in source: String,
        relativePath: String
    ) -> ResearcherCommentAnchor? {
        guard let selection else { return nil }
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        if let exactRange = selection.exactUTF16Range {
            return ResearcherCommentAnchorBuilder.anchor(
                in: source,
                fingerprint: document.fingerprint,
                utf16Range: exactRange,
                selectedText: selection.excerpt
            )
        }
        return ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: selection.excerpt,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter,
            in: document
        )
    }
}

// MARK: - Note Content Container

struct DocumentFeatureView: View {
    @ObservedObject private var controller: DocumentController
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    init(
        controller: DocumentController,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        critiqueProvenanceContext: CritiqueProvenanceContext
    ) {
        self.controller = controller
        self.state = state
        self.actions = actions
        self.critiqueProvenanceContext = critiqueProvenanceContext
    }

    var body: some View {
        if let selectedDocumentPath = state.selectedDocumentPath,
           let note = state.notes.first(where: { $0.relativePath == selectedDocumentPath }) {
            let selectedWorkspaceKey = controller.activeDocument.flatMap { descriptor in
                descriptor.reference.relativePath == selectedDocumentPath
                    ? descriptor.sessionKey
                    : nil
            }
            let projectedWorkspaceKey = state.currentVaultID.flatMap { vaultID in
                state.noteIdentityByPath[note.relativePath].map { noteID in
                    DocumentSessionKey(vaultID: vaultID, noteID: noteID)
                }
            }
            if let key = selectedWorkspaceKey ?? projectedWorkspaceKey {
                NoteContentView(
                    controller: controller,
                    target: .workspace(key),
                    note: note,
                    documentSession: controller.session(for: key),
                    state: state,
                    actions: actions,
                    critiqueProvenanceContext: critiqueProvenanceContext
                )
                .id(key)
            } else {
                DocumentSessionFallback(
                    note: note,
                    controller: controller,
                    target: state.locationScope == .unclassified
                        ? .unclassified(relativePath: note.relativePath)
                        : .unavailable(relativePath: note.relativePath),
                    state: state,
                    actions: actions,
                    critiqueProvenanceContext: critiqueProvenanceContext
                )
                    .id(selectedDocumentPath)
            }
        }
    }
}

private struct DocumentSessionFallback: View {
    let note: WindowDocumentLocation
    let controller: DocumentController
    let target: DocumentEditingTarget
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    var body: some View {
        NoteContentView(
            controller: controller,
            target: target,
            note: note,
            documentSession: controller.session(for: target),
            state: state,
            actions: actions,
            critiqueProvenanceContext: critiqueProvenanceContext
        )
    }
}

struct ResearchInspectorView: View {
    @ObservedObject private var controller: ResearchController
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedMode: ResearchInspectorMode?

    let note: WindowDocumentLocation
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let researchInspectorContentContext: ResearchInspectorContentContext
    let researchFunctionsPresentation: ResearchFunctionsPresentation
    let openResearchFunction: (ResearchFunctionID) -> Void
    let openResearchRecord: () -> Void

    init(
        note: WindowDocumentLocation,
        controller: ResearchController,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        researchFunctionsPresentation: ResearchFunctionsPresentation,
        openResearchFunction: @escaping (ResearchFunctionID) -> Void,
        openResearchRecord: @escaping () -> Void
    ) {
        self.note = note
        self.controller = controller
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.researchInspectorContentContext = researchInspectorContentContext
        self.researchFunctionsPresentation = researchFunctionsPresentation
        self.openResearchFunction = openResearchFunction
        self.openResearchRecord = openResearchRecord
    }

    var body: some View {
        VStack(spacing: 0) {
            inspectorTabs

            Group {
                switch controller.inspector.mode {
                case .overview:
                    ResearchOverviewView(
                        note: note,
                        context: researchInspectorContentContext
                    )
                case .connections:
                    ConnectionsInspectorView(context: relationshipContext)
                case .functions:
                    ResearchFunctionsInspectorView(
                        presentation: researchFunctionsPresentation,
                        freshness: researchInspectorContentContext.freshness,
                        select: openResearchFunction,
                        openResearchRecord: openResearchRecord,
                        retryRefresh: researchInspectorContentContext.retryRefresh
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scholiumSurface(.apparatus)
        .accessibilityIdentifier("scholium.researchInspector")
    }

    private var inspectorTabs: some View {
        ZStack(alignment: .bottom) {
            ScholiumStructuralRule()

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(ResearchInspectorMode.allCases) { mode in
                        InspectorModeButton(
                            mode: mode,
                            isSelected: controller.inspector.mode == mode,
                            focusedMode: $focusedMode,
                            select: { selectMode(mode) },
                            move: { moveFocus(from: mode, direction: $0) }
                        )
                        .frame(minWidth: 92)
                    }
                }
                .frame(minWidth: 276)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
        }
        .frame(minHeight: ScholiumMetrics.Apparatus.headerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research Inspector")
    }

    private func selectMode(_ mode: ResearchInspectorMode) {
        controller.selectInspectorMode(mode)
        focusedMode = mode
    }

    private func moveFocus(
        from mode: ResearchInspectorMode,
        direction: MoveCommandDirection
    ) {
        let modes = ResearchInspectorMode.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        let visualStep: Int
        switch direction {
        case .left:
            visualStep = layoutDirection == .leftToRight ? -1 : 1
        case .right:
            visualStep = layoutDirection == .leftToRight ? 1 : -1
        default:
            return
        }
        let nextIndex = (index + visualStep + modes.count) % modes.count
        selectMode(modes[nextIndex])
    }

    private var relationshipContext: RelationshipInspectorContext {
        RelationshipInspectorContext(
            graph: graph,
            catalog: catalog,
            current: currentVaultID.map {
                VaultQualifiedNoteID(vaultID: $0, relativePath: note.relativePath)
            },
            freshness: researchInspectorContentContext.freshness,
            retryRefresh: researchInspectorContentContext.retryRefresh,
            openReference: { reference, line in
                controller.requestOpen(reference, sourceLine: line)
            }
        )
    }
}

private struct InspectorModeButton: View {
    @State private var isHovering = false
    let mode: ResearchInspectorMode
    let isSelected: Bool
    let focusedMode: FocusState<ResearchInspectorMode?>.Binding
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            Text(mode.interfaceTitleResource)
                .font(.body)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.Apparatus.headerHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(interactions: .activate)
        .focused(focusedMode, equals: mode)
        .foregroundStyle(
            isSelected || isHovering
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    isSelected
                        ? ScholiumColorRole.accent.color
                        : ScholiumColorRole.secondaryText.color.opacity(isHovering ? 0.45 : 0)
                )
                .frame(height: isSelected ? 2 : 1)
                .padding(.horizontal, 14)
        }
        .onHover { isHovering = $0 }
        .onMoveCommand(perform: move)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("scholium.inspectorMode.\(mode.rawValue)")
    }
}
// MARK: - Note Content View

struct NoteContentView: View {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @ObservedObject private var controller: DocumentController
    @ObservedObject private var documentSession: DocumentSessionModel
    let target: DocumentEditingTarget
    let note: WindowDocumentLocation
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    init(
        controller: DocumentController,
        target: DocumentEditingTarget,
        note: WindowDocumentLocation,
        documentSession: DocumentSessionModel,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        critiqueProvenanceContext: CritiqueProvenanceContext
    ) {
        self.controller = controller
        _documentSession = ObservedObject(wrappedValue: documentSession)
        self.target = target
        self.note = note
        self.state = state
        self.actions = actions
        self.critiqueProvenanceContext = critiqueProvenanceContext
    }

    private var isEditing: Bool {
        documentSession.isEditing
    }
    private var editingSource: String {
        documentSession.editingSource
    }
    private var editError: String? {
        get { documentSession.editError }
        nonmutating set { documentSession.editError = newValue }
    }
    private var isSavingEdit: Bool {
        documentSession.isSavingEdit
    }
    private var presentationMode: NotePresentationMode {
        get { documentSession.presentationMode }
        nonmutating set { documentSession.presentationMode = newValue }
    }
    private var returnToReadAfterSave: Bool {
        get { documentSession.returnToReadAfterSave }
        nonmutating set { documentSession.returnToReadAfterSave = newValue }
    }
    private var renderedReadHTML: String {
        get { documentSession.renderedReadHTML }
        nonmutating set { documentSession.renderedReadHTML = newValue }
    }
    private var renderedReadFingerprint: String {
        get { documentSession.renderedReadFingerprint }
        nonmutating set { documentSession.renderedReadFingerprint = newValue }
    }
    private var failedReadFingerprint: String? {
        get { documentSession.failedReadFingerprint }
        nonmutating set { documentSession.failedReadFingerprint = newValue }
    }
    private var conflict: DocumentConflictSnapshot? {
        documentSession.conflict
    }
    private var canRetrySave: Bool {
        documentSession.canRetrySave
    }
    private var showConflictComparison: Bool {
        get { documentSession.showConflictComparison }
        nonmutating set { documentSession.showConflictComparison = newValue }
    }
    private var editorSession: MarkdownEditorSession { documentSession.editorSession }

    var body: some View {
        AnyView(VStack(spacing: 0) {
            if let ambiguity = state.identityAmbiguity {
                IdentityAmbiguityNotice(ambiguity: ambiguity) {
                    actions.requestIdentityResolution()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else if let pending = state.pendingIdentityRebinding {
                IdentityMigrationNotice(
                    rebinding: pending,
                    message: state.identityMigrationFailureMessage,
                    isRetrying: state.isResolvingIdentity
                ) {
                    await actions.retryIdentityRecovery()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if state.isManagedCritique {
                CritiqueProvenanceView(
                    note: note,
                    context: critiqueProvenanceContext
                )
            }

            documentBodySurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .scholiumSurface(.document)
        .focusedSceneValue(\.scholiumSearchActions, ScholiumSearchActions { invocation in
            actions.beginSearch(invocation)
        })
        .focusedSceneValue(
            \.scholiumResearchFunctionActions,
            ScholiumFocusedResearchFunctionActions(open: openResearchFunction)
        )
        .focusedSceneValue(
            \.scholiumEditorActions,
            isEditing ? ScholiumFocusedEditorActions(
                documentID: editorSession.documentID,
                isComposing: editorSession.context?.composing == true,
                isAvailable: { command in
                    editorSession.context?.availableCommands.contains(command) == true
                },
                canAddComment: {
                    editorSession.context?.selections.contains(where: \.isNonempty) == true
                },
                perform: { command in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command)
                        } catch {
                            actions.notify(error.localizedDescription, .error)
                        }
                    }
                },
                performWithArgument: { command, argument in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command, argument: argument)
                        } catch {
                            actions.notify(error.localizedDescription, .error)
                        }
                    }
                },
                addComment: requestResearcherCommentsFromDocument
            ) : nil
        ))
        .sheet(isPresented: Binding(
            get: { showConflictComparison },
            set: { showConflictComparison = $0 }
        )) {
            if let conflict {
                ConflictComparisonSheet(
                    conflict: conflict,
                    onReturnToEditing: {
                        showConflictComparison = false
                        Task { @MainActor in
                            await Task.yield()
                            editorSession.focus()
                        }
                    },
                    onReloadFromDisk: { reloadFromDisk() }
                )
            }
        }
        .alert(conflict == nil ? "Save Failed" : "This Note Changed on Disk", isPresented: Binding(
            get: { editError != nil && (conflict == nil || !editorIsComposing) },
            set: { if !$0, !editorIsComposing { editError = nil } }
        )) {
            if conflict != nil {
                Button("Compare Changes") {
                    editError = nil
                    showConflictComparison = true
                }
                .keyboardShortcut(.defaultAction)
                Button("Reload from Disk", role: .destructive) { reloadFromDisk() }
            } else if canRetrySave {
                Button("Retry Save") {
                    controller.retrySave(session: documentSession, target: target)
                }
            }
            Button("Keep Editing", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .onChange(of: state.requestedPresentationMode) { _, requested in
            guard let requested else { return }
            selectPresentationMode(requested)
            actions.clearRequestedPresentationMode()
        }
        .onChange(of: editError) { _, error in
            guard error != nil, !editorIsComposing else { return }
            // Native save/conflict recovery owns focus while it is visible.
            // Keep the retained CodeMirror state, but dismiss disposable
            // WebKit presentation such as link or footnote previews.
            editorSession.resignFocus()
        }
        .onAppear {
            controller.observe(documentSession)
            restorePresentationModeIfAvailable()
            consumePendingPresentationRequest()
        }
        .onChange(of: editingIsAvailable) { _, available in
            // Window restoration publishes the selected note before stable
            // identity recovery necessarily finishes. Keep the edit gate
            // intact, then apply the committed mode as soon as editing becomes
            // available instead of leaving the document in the default Read
            // mode for the rest of the session.
            if available { restorePresentationModeIfAvailable() }
        }
        .onChange(of: isEditing) { _, _ in
            documentSession.readSelection = nil
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded, let line = state.pendingSourceLine else { return }
            editorSession.goToLine(line)
            actions.clearPendingSourceLine()
        }
        .task(id: readProjectionTaskIdentity) {
            guard presentationMode == .read else { return }
            failedReadFingerprint = nil
            documentSession.renderedReadReadyFingerprint = ""
            documentSession.readSelection = nil
            let source = note.rawContent
            let relativePath = note.relativePath
            let fingerprint = noteFingerprint
            documentSession.requestScrollRestore(
                fingerprint: fingerprint.sha256,
                reason: .documentLoad
            )
            let html = await controller.readProjectionHTML(
                target: target,
                relativePath: relativePath,
                source: source,
                fingerprint: fingerprint,
                workspaceID: state.currentVaultID
            )
            guard !Task.isCancelled, fingerprint == noteFingerprint else { return }
            renderedReadHTML = html
            renderedReadFingerprint = fingerprint.sha256
        }
        .task(id: previewTaskIdentity) {
            await rebuildPreviewCatalog()
        }
    }

    private var readProjectionTaskIdentity: String {
        "\(noteFingerprint.sha256):\(presentationMode.rawValue)"
    }

    private var previewTaskIdentity: String {
        let generation = state.workspaceCatalog?.graph?.generation ?? -1
        return "\(state.currentVaultID?.uuidString ?? "unclassified"):\(noteFingerprint.sha256):\(generation):\(presentationMode.rawValue):\(hasUnsavedChanges)"
    }

    @MainActor
    private func rebuildPreviewCatalog() async {
        guard let vaultID = state.currentVaultID,
              let graph = state.workspaceCatalog?.graph,
              state.selectedDocumentPath == note.relativePath,
              presentationMode != .source,
              !hasUnsavedChanges else {
            documentSession.previewCatalog = nil
            return
        }
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
        let expectedFingerprint = noteFingerprint
        let expectedGeneration = graph.generation
        do {
            let catalog = try await controller.documentPreviewCatalog(
                source: sourceID,
                sourceFingerprint: expectedFingerprint,
                graphGeneration: expectedGeneration
            )
            guard !Task.isCancelled,
                  noteFingerprint == expectedFingerprint,
                  state.workspaceCatalog?.graph?.generation == expectedGeneration,
                  !hasUnsavedChanges else { return }
            documentSession.previewCatalog = catalog
        } catch {
            guard !Task.isCancelled else { return }
            documentSession.previewCatalog = nil
        }
    }

    private var commentingIsAvailable: Bool {
        state.selectedDocumentPath == note.relativePath && state.canComment
    }

    private var editingIsAvailable: Bool {
        state.canEdit
    }

    private var noteFingerprint: DocumentFingerprint {
        state.documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
    }

    private var bodyEditor: AnyView {
        AnyView(MarkdownEditorWebView(
            session: editorSession,
            documentID: editorSession.bridgeDocumentID,
            source: editingSource,
            mode: documentSession.retainedEditorMode,
            presentationCSS: documentPresentationCSS,
            userCSS: state.livePreviewCSS,
            linkCompletions: [],
            linkCompletionQuery: queryEditorLinkCompletions,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            researcherComments: currentResearcherComments,
            initialScrollFraction: state.initialScrollFraction,
            initialScrollAnchor: editorScrollAnchor,
            onDocumentChange: { updatedSource in
                controller.updateEditingSource(
                    updatedSource,
                    session: documentSession,
                    target: target
                )
            },
            onRequestSave: {
                Task {
                    await controller.persistEditingSource(
                        session: documentSession,
                        target: target
                    )
                }
            },
            onRequestSearch: {
                actions.beginSearch(.findInNote(previousScope: state.ordinarySearchScope))
            },
            onRequestComment: requestResearcherCommentsFromDocument,
            onLinkActivation: { target in
                if let url = URL(string: target),
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    actions.openExternalURL(url)
                } else {
                    actions.openInternalLink(target)
                }
            },
            onCommentActivation: commentingIsAvailable ? { commentID in
                actions.requestComments(nil, commentID)
            } : nil,
            onScrollFractionChange: {
                documentSession.observeScrollFraction($0)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: { documentSession.observeScrollAnchor($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1))
    }

    @ViewBuilder
    private var documentBodySurface: some View {
        DocumentEditorHost(
            presentsEditor: isEditing,
            retainsEditor: documentSession.retainsEditorSurface,
            editorIsReady: editorSession.isLoaded
        ) {
            readSurface
        } editor: {
            bodyEditor
        }
        .scholiumSurface(.document)
    }

    @ViewBuilder
    private var readSurface: some View {
        let hasWebProjection = renderedReadFingerprint == noteFingerprint.sha256
            && !renderedReadHTML.isEmpty
            && failedReadFingerprint != noteFingerprint.sha256
        let webProjectionIsReady = hasWebProjection
            && documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256

        ZStack {
            readProjectionPlaceholder
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .opacity(webProjectionIsReady ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(webProjectionIsReady)

            if hasWebProjection {
                readDocumentSurface
                    .opacity(webProjectionIsReady ? 1 : 0)
                    .allowsHitTesting(webProjectionIsReady && !isEditing)
                    .accessibilityHidden(!webProjectionIsReady)
            }
        }
    }

    @ViewBuilder
    private var readProjectionPlaceholder: some View {
        if failedReadFingerprint == noteFingerprint.sha256 {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text("Read mode is unavailable")
                    .font(.headline)
                Text("Use Source mode while the rendered document is unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityElement(children: .combine)
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading document")
        }
    }

    private var readDocumentSurface: some View {
        SafeMarkdownReadWebView(
            documentID: note.relativePath,
            fingerprint: noteFingerprint.sha256,
            source: note.rawContent,
            htmlBody: renderedReadHTML,
            presentationCSS: documentPresentationCSS,
            userCSS: state.readCSS,
            configurationRevision: readConfigurationRevision,
            researcherComments: currentResearcherComments,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            onLinkClick: {
                actions.openInternalLink($0)
            },
            onOpenExternalURL: actions.openExternalURL,
            onCommentSelection: commentingIsAvailable ? { selection in
                actions.requestComments(selection, nil)
            } : nil,
            onSelectionChange: { selection in
                guard !isEditing else { return }
                documentSession.readSelection = selection
            },
            onCommentActivation: commentingIsAvailable ? { commentID in
                actions.requestComments(nil, commentID)
            } : nil,
            onRenderingFailure: { reason in
                actions.enterCSSSafeMode(reason)
                failedReadFingerprint = noteFingerprint.sha256
                documentSession.renderedReadReadyFingerprint = ""
            },
            onRenderingLoading: {
                documentSession.renderedReadReadyFingerprint = ""
            },
            onRenderingReady: {
                documentSession.renderedReadReadyFingerprint = noteFingerprint.sha256
                PerformanceProbe.shared.markReadReady(documentID: note.relativePath)
            },
            observedScrollPosition: documentSession.observedScrollPosition,
            scrollRestoreRequest: documentSession.scrollRestoreRequest,
            onScrollRestoreConsumed: { id, fingerprint in
                documentSession.acknowledgeScrollRestoreRequest(
                    id: id,
                    fingerprint: fingerprint
                )
            },
            onScrollFractionChange: {
                documentSession.observeScrollFraction($0)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: { documentSession.observeScrollAnchor($0) },
            targetSourceLine: isEditing ? nil : state.pendingSourceLine,
            onSourceLineReached: {
                guard !isEditing else { return }
                actions.clearPendingSourceLine()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var currentResearcherComments: [ResearcherComment] {
        state.reviewRecord?.comments ?? []
    }

    private var editorScrollAnchor: EditorScrollAnchor? {
        let fingerprint = DocumentFingerprint(content: editingSource).sha256
        guard documentSession.scrollAnchor?.sourceFingerprint == fingerprint else { return nil }
        return documentSession.scrollAnchor
    }

    private var documentPresentation: ScholiumDocumentPresentationConfiguration {
        ScholiumDocumentPresentationConfiguration(textScale: state.documentTextScale)
    }

    private var documentPresentationCSS: String {
        documentPresentation.css + "\n" + state.appearanceCSS
    }

    private var readConfigurationRevision: String {
        let commentRevision = state.reviewRecord.map {
            "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)"
        } ?? "no-comments"
        let previewRevision = documentSession.previewCatalog.map { catalog in
            let targets = catalog.links.map { link in
                "\(link.sourceSpan.utf16LowerBound)-\(link.sourceSpan.utf16UpperBound):"
                    + link.targetFingerprint.sha256
            }.joined(separator: ",")
            return "\(catalog.graphGeneration):\(catalog.sourceFingerprint.sha256):\(targets)"
        } ?? "no-previews"
        return [
            noteFingerprint.sha256,
            String(state.documentTextScale.bitPattern),
            String(state.appearanceCSS.hashValue),
            String(state.readCSS.hashValue),
            commentRevision,
            previewRevision,
        ].joined(separator: ":")
    }

    private var hasUnsavedChanges: Bool {
        documentSession.hasUnsavedChanges
    }

    @MainActor
    private func queryEditorLinkCompletions(
        _ query: String
    ) async -> [EditorLinkCompletion] {
        guard let currentVaultID = state.currentVaultID,
              let catalogNotes = state.workspaceCatalog?.notes,
              let generation = state.workspaceCatalog?.graph?.generation else {
            return []
        }
        return await controller.editorLinkCompletions(
            matching: query,
            sourcePath: note.relativePath,
            currentVaultID: currentVaultID,
            catalogNotes: catalogNotes,
            graphGeneration: generation
        )
    }

    private var editorIsComposing: Bool {
        isEditing && editorSession.context?.composing == true
    }

    private func selectPresentationMode(_ mode: NotePresentationMode) {
        guard !editorIsComposing else {
            actions.notify("Finish text composition to change document mode.", .information)
            return
        }
        if mode == .read {
            guard isEditing else {
                presentationMode = .read
                actions.rememberPresentationMode(.read)
                return
            }
            returnToReadAfterSave = true
            Task {
                do {
                    try await controller.flushForExternalOperation(
                        session: documentSession,
                        target: target
                    )
                    guard returnToReadAfterSave else { return }
                    let handoffAnchor = try? await editorSession.currentScrollAnchor()
                    documentSession.observeScrollAnchor(handoffAnchor)
                    documentSession.requestScrollRestore(
                        fingerprint: handoffAnchor?.sourceFingerprint
                            ?? DocumentFingerprint(content: editingSource).sha256,
                        reason: .modeHandoff
                    )
                    editorSession.resignFocus()
                    finishEditing()
                } catch { /* Controller published the recoverable error state. */ }
            }
            return
        }

        guard editingIsAvailable else {
            actions.notify("This note is read-only in Scholium.", .information)
            return
        }
        actions.rememberPresentationMode(mode)

        if isEditing {
            presentationMode = mode
            documentSession.retainedEditorMode = mode
        } else {
            beginEditing(mode: mode)
        }
    }

    private func restorePresentationModeIfAvailable() {
        guard !isEditing,
              presentationMode != .read,
              editingIsAvailable else { return }
        beginEditing(mode: presentationMode)
    }

    private func consumePendingPresentationRequest() {
        guard let requested = state.requestedPresentationMode else { return }
        selectPresentationMode(requested)
        actions.clearRequestedPresentationMode()
        if let line = state.pendingSourceLine {
            editorSession.goToLine(line)
        }
    }

    private func beginEditing(mode: NotePresentationMode = .livePreview) {
        controller.beginEditing(
            session: documentSession,
            target: target,
            source: note.rawContent,
            revision: state.documentRevisions[note.relativePath],
            mode: mode
        )
        Task { @MainActor in
            await Task.yield()
            editorSession.focus()
        }
    }

    private func finishEditing() {
        controller.finishEditing(session: documentSession, target: target)
        actions.rememberPresentationMode(.read)
    }

    private func reloadFromDisk() {
        Task {
            do {
                try await controller.reloadFromDisk(
                    session: documentSession,
                    target: target
                )
                actions.rememberPresentationMode(.read)
            } catch { /* Controller published the recoverable error state. */ }
        }
    }

    private func requestResearcherCommentsFromDocument() {
        guard commentingIsAvailable else { return }
        guard isEditing else {
            actions.notify(
                "Select a passage in Read, Live Preview, or Source before adding a Comment.",
                .information
            )
            return
        }
        Task { @MainActor in
            do {
                let currentSource = try await editorSession.currentText(
                    for: editorSession.bridgeDocumentID
                )
                let selection = try await editorSession.currentSelection(
                    for: editorSession.bridgeDocumentID,
                    in: currentSource
                )
                guard let selection,
                      ResearchFunctionSelectionCapture.anchor(
                          for: selection,
                          in: currentSource,
                          relativePath: note.relativePath
                      ) != nil else {
                    actions.notify(
                        "Select a passage before adding a Comment. Review or Critique provides the whole-note judgment.",
                        .information
                    )
                    editorSession.focus()
                    return
                }
                try await controller.flushForExternalOperation(
                    session: documentSession,
                    target: target
                )
                actions.requestComments(selection, nil)
            } catch {
                actions.notify(
                    "Scholium could not capture the current editor selection. Keep editing and try again. \(error.localizedDescription)",
                    .error
                )
            }
        }
    }

    private func openResearchFunction(_ function: ResearchFunctionID) {
        guard !editorIsComposing else {
            actions.notify(
                "Finish text composition to open a research function.",
                .information
            )
            return
        }
        guard isEditing else {
            let selection = documentSession.readSelection
            let anchor = ResearchFunctionSelectionCapture.anchor(
                for: selection,
                in: note.rawContent,
                relativePath: note.relativePath
            )
            if selection != nil, anchor == nil {
                actions.notify(
                    "Scholium could not match the selected passage reliably. The function will open for the whole note.",
                    .information
                )
            }
            actions.openResearchFunction(function, anchor)
            return
        }

        Task { @MainActor in
            do {
                let currentSource = try await editorSession.currentText(
                    for: editorSession.bridgeDocumentID
                )
                let selection = try await editorSession.currentSelection(
                    for: editorSession.bridgeDocumentID,
                    in: currentSource
                )
                let anchor = ResearchFunctionSelectionCapture.anchor(
                    for: selection,
                    in: currentSource,
                    relativePath: note.relativePath
                )
                actions.openResearchFunction(function, anchor)
            } catch {
                actions.notify(
                    "Scholium could not capture the current selection. The function will open for the whole note. \(error.localizedDescription)",
                    .information
                )
                actions.openResearchFunction(function, nil)
            }
        }
    }

}

// MARK: - Research Record

private struct ConflictComparisonSheet: View {
    let conflict: DocumentConflictSnapshot
    let onReturnToEditing: () -> Void
    let onReloadFromDisk: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Changes")
                        .font(.title2.weight(.semibold))
                    Text(conflict.relativePath)
                        .font(ScholiumTypography.swiftUIRevisionIdentity())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            HStack(alignment: .top, spacing: 24) {
                revisionLabel(
                    title: "Current Editor",
                    fingerprint: conflict.editorRevision,
                    detail: "Based on \(short(conflict.baseRevision))"
                )
                revisionLabel(
                    title: "Disk Version",
                    fingerprint: conflict.diskRevision,
                    detail: "The version shown below"
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(marker(for: line.kind))
                                .font(ScholiumTypography.swiftUIDiff(bold: true))
                                .foregroundStyle(color(for: line.kind))
                                .frame(width: 16)
                                .accessibilityLabel(label(for: line.kind))
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(ScholiumTypography.swiftUIDiff())
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color(for: line.kind).opacity(line.kind == .unchanged ? 0 : 0.08))
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("Return to Editing", action: onReturnToEditing)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk", role: .destructive, action: onReloadFromDisk)
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 900, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.conflictComparison")
    }

    @ViewBuilder
    private func revisionLabel(
        title: String,
        fingerprint: DocumentFingerprint,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(short(fingerprint))
                .font(ScholiumTypography.swiftUIRevisionIdentity())
                .textSelection(.enabled)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            title == "Current Editor"
                ? "scholium.conflict.currentRevision"
                : "scholium.conflict.diskRevision"
        )
    }

    private func marker(for kind: DocumentConflictLineKind) -> String {
        switch kind {
        case .unchanged: " "
        case .editorOnly: "−"
        case .diskOnly: "+"
        }
    }

    private func label(for kind: DocumentConflictLineKind) -> String {
        switch kind {
        case .unchanged: "Unchanged"
        case .editorOnly: "Current editor only"
        case .diskOnly: "Disk version only"
        }
    }

    private func color(for kind: DocumentConflictLineKind) -> Color {
        switch kind {
        case .unchanged: .secondary
        case .editorOnly: .red
        case .diskOnly: .green
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "SHA-256 \(fingerprint.sha256.prefix(12))… (\(fingerprint.byteCount) bytes)"
    }

    private var diffLines: [DocumentConflictLine] { conflict.comparisonLines }
}

struct ResearchRecordContext {
    let controller: ResearchController
    let vaultRole: VaultRole
    let documentRevisions: [String: DocumentFingerprint]
    let currentReview: @MainActor (String) -> HumanReviewRecord?
    let loadDialogue: @MainActor (String) async -> [DialogueEntry]
    let loadCritique: @MainActor (String) async -> CritiqueAssociation?
    let copyText: @MainActor (String) throws -> Void
    let openNote: @MainActor (String) -> Void
    let notify: @MainActor (String) -> Void
}

private enum DialogueHistorySheetRoute: Identifiable {
    case followUp(DialogueEntry)
    case response(DialogueEntry)

    var id: String {
        switch self {
        case .followUp(let entry): "follow-up-\(entry.id.uuidString)"
        case .response(let entry): "response-\(entry.id.uuidString)"
        }
    }
}

struct ResearchRecordView: View {
    @ObservedObject private var researchController: ResearchController
    let note: WindowDocumentLocation
    let context: ResearchRecordContext

    @State private var review: HumanReviewRecord?
    @State private var dialogue: [DialogueEntry] = []
    @State private var critique: CritiqueAssociation?
    @State private var pendingDialogueSheet: DialogueHistorySheetRoute?
    @State private var expandedDialogueEntryIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(
        note: WindowDocumentLocation,
        context: ResearchRecordContext
    ) {
        self.note = note
        self.context = context
        _researchController = ObservedObject(wrappedValue: context.controller)
    }

    var body: some View {
        VStack(spacing: 0) {
            researchRecordHeader
            ScholiumStructuralRule()

            if isLoading {
                Spacer()
                ProgressView("Loading Research Record…")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if context.vaultRole.allowsHumanReview { reviewSection }
                        commentSection
                        functionRunSection
                        dialogueSection
                        if context.vaultRole.allowsCritique { critiqueSection }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.researchRecord")
        .task { await reload() }
        .alert("Research Record Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $pendingDialogueSheet) { route in
            switch route {
            case .followUp(let entry):
                ManualDialogueFollowUpView(
                    controller: context.controller,
                    entry: entry
                ) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
            case .response(let entry):
                ManualDialogueReplyView(
                    controller: context.controller,
                    entry: entry
                ) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
            }
        }
    }

    private var researchRecordHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Research Record")
                    .font(.title2.weight(.semibold))
                Text(note.title ?? note.displayName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    private var reviewSection: some View {
        historySection("Human Review", systemImage: "checkmark.seal") {
            if let review {
                if let latest = review.latestReview {
                    HStack {
                        Label(
                            latest.qualification == .qualified ? "Qualified" : "Unqualified",
                            systemImage: latest.qualification == .qualified
                                ? "checkmark.seal.fill"
                                : "xmark.seal.fill"
                        )
                        .foregroundStyle(latest.qualification == .qualified ? .green : .red)
                        Spacer()
                        Text(latest.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Text(latest.reviewNote)
                        .textSelection(.enabled)
                    Text("Bound to SHA-256 \(latest.fingerprint.sha256.prefix(12))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if let draft = review.draft {
                    Label("Review draft saved", systemImage: "square.and.pencil")
                    if !draft.reviewNote.isEmpty { Text(draft.reviewNote).textSelection(.enabled) }
                } else {
                    emptyText("No completed Human Review for this note.")
                }
            } else {
                emptyText("This note has no Human Review.")
            }
        }
    }

    private var commentSection: some View {
        historySection("Researcher Comments", systemImage: "text.bubble") {
            if let comments = review?.comments, !comments.isEmpty {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let anchor = comment.anchor
                            Text(anchor.state == .needsReattachment
                                ? "Needs Reattachment — originally line \(anchor.line)"
                                : (anchor.line == anchor.endLine
                                    ? "Line \(anchor.line)"
                                    : "Lines \(anchor.line)–\(anchor.endLine)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(anchor.state == .needsReattachment ? Color.orange : Color.secondary)
                            if comment.resolvedAt != nil {
                                Text("Resolved")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text(comment.text).textSelection(.enabled)
                        Text(comment.anchor.selectedText ?? comment.anchor.quotation)
                            .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 3)
                    if comment.id != comments.last?.id { Divider() }
                }
            } else {
                emptyText("This note has no researcher comments.")
            }
        }
    }

    private var functionRunSection: some View {
        historySection("Function Runs", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            if currentFunctionRuns.isEmpty {
                emptyText("No Research Function runs are recorded for this note.")
            } else {
                Text("Run state is shown here without merging Dialogue, Critique, Human Review, Comments, or Fidelity findings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(currentFunctionRuns) { run in
                    VStack(alignment: .leading, spacing: 8) {
                        ResearchFunctionRunStatusView(record: run, showsFunction: true)
                        if let instructions = run.preparedInstructions,
                           run.runState != .complete,
                           run.runState != .cancelled {
                            Button("Copy Instructions for Agent") {
                                do {
                                    try context.copyText(instructions)
                                    context.notify("Research Function instructions copied")
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            .accessibilityIdentifier(
                                "scholium.researchRecord.copyResearchFunctionInstructions"
                            )
                        }
                    }
                    if run.id != currentFunctionRuns.last?.id { Divider() }
                }
            }
        }
        .accessibilityIdentifier("scholium.researchRecord.functionRuns")
    }

    private var currentFunctionRuns: [ResearchFunctionRecordProjection] {
        guard let noteID = note.workspaceSnapshot?.stableIdentity.resolvedID else {
            return []
        }
        return (researchController.records?.functionRuns ?? [])
            .filter { $0.snapshot.request.target.noteID == noteID }
            .sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private var dialogueSection: some View {
        historySection("Dialogue", systemImage: "bubble.left.and.bubble.right") {
            if dialogue.isEmpty {
                emptyText("No researcher instructions have included this note.")
            } else {
                ForEach(dialogue) { entry in
                    let isExpanded = expandedDialogueEntryIDs.contains(entry.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if isExpanded {
                                expandedDialogueEntryIDs.remove(entry.id)
                            } else {
                                expandedDialogueEntryIDs.insert(entry.id)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 12)
                                    .accessibilityHidden(true)
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Dialogue from \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                        .accessibilityHint(isExpanded ? "Collapses this Dialogue entry" : "Expands this Dialogue entry")
                        .accessibilityIdentifier("scholium.dialogue.entryDisclosure")

                        if isExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                        DialogueTurnRow(
                            id: entry.id,
                            participant: "Researcher",
                            role: "Initial Comment",
                            scope: "Overall",
                            text: entry.instruction,
                            createdAt: entry.createdAt,
                            systemImage: "person"
                        )
                        if let destination = entry.requestedDestination {
                            LabeledContent("Requested Destination") {
                                Text(destination)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                        DisclosureGroup("Selected Notes (\(entry.selectedNotes.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(entry.selectedNotes) { selectedNote in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedNote.title)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(selectedNote.vaultName) — \(selectedNote.relativePath)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        if let kind = selectedNote.kind {
                                            Text("Kind: \(kind)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        if let linkedNoteSummary = entry.linkedNoteSummary {
                            DisclosureGroup("Linked-Note Context") {
                                Text(linkedNoteSummary)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .padding(.top, 3)
                            }
                        }
                        if !entry.includedComments.isEmpty {
                            Divider()
                            Text("Included Comments")
                                .font(.subheadline.weight(.semibold))
                            ForEach(entry.includedComments) { includedComment in
                                VStack(alignment: .leading, spacing: 3) {
                                    let sourceNote = includedComment.note
                                    Text(sourceNote.title)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(sourceNote.vaultName) — \(sourceNote.relativePath)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text("Note ID: \(sourceNote.noteID.uuidString)")
                                        .font(ScholiumTypography.swiftUIMonospaceFont(
                                            size: 10,
                                            relativeTo: .caption
                                        ))
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                    Text(includedComment.comment.text)
                                        .textSelection(.enabled)
                                    Text(
                                        "Lines \(includedComment.comment.anchor.line)–\(includedComment.comment.anchor.endLine)"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        let chronologicalTurns = entry.chronologicalTurns
                        if !chronologicalTurns.isEmpty {
                            Divider()
                            Text("Follow-up Exchange")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(chronologicalTurns) { turn in
                            switch turn {
                            case .researcher(let comment):
                                DialogueTurnRow(
                                    id: comment.id,
                                    participant: "Researcher",
                                    role: "Follow-up Comment",
                                    scope: dialogueScope(
                                        noteID: comment.noteID,
                                        commentID: comment.commentID,
                                        in: entry
                                    ),
                                    text: comment.text,
                                    createdAt: comment.createdAt,
                                    systemImage: "person"
                                )
                            case .agent(let reply):
                                DialogueTurnRow(
                                    id: reply.id,
                                    participant: reply.agentName.isEmpty ? "Agent" : reply.agentName,
                                    role: "Agent Response",
                                    scope: dialogueScope(
                                        noteID: reply.noteID,
                                        commentID: reply.commentID,
                                        in: entry
                                    ),
                                    text: reply.text,
                                    createdAt: reply.createdAt,
                                    systemImage: "sparkles"
                                )
                            }
                        }
                        if !entry.preparedInstructions.isEmpty {
                            DisclosureGroup("Prepared Instructions") {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.preparedInstructions)
                                    .font(ScholiumTypography.swiftUIMonospaceFont(
                                        size: 11,
                                        relativeTo: .caption
                                    ))
                                    .textSelection(.enabled)
                                Button {
                                    do {
                                        try context.copyText(entry.preparedInstructions)
                                        context.notify("Instructions copied")
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                } label: {
                                    Label("Copy Instructions", systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                            }
                        }
                        HStack {
                            Button {
                                pendingDialogueSheet = .followUp(entry)
                            } label: {
                                Label("Add Follow-up Comment…", systemImage: "plus.bubble")
                            }
                            .accessibilityIdentifier("scholium.dialogue.addFollowUp")

                            Button {
                                pendingDialogueSheet = .response(entry)
                            } label: {
                                Label("Record Agent Response…", systemImage: "bubble.left.and.bubble.right")
                            }
                            .accessibilityIdentifier("scholium.dialogue.recordResponse")
                        }
                        .controlSize(.small)
                            }
                            .padding(.leading, 19)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("scholium.researchRecord.dialogueSection")
    }

    private func dialogueScope(
        noteID: UUID?,
        commentID: UUID?,
        in entry: DialogueEntry
    ) -> String {
        if let commentID,
           let included = entry.includedComments.first(where: { $0.comment.id == commentID }) {
            return "Comment in \(included.note.title)"
        }
        if let noteID,
           let selected = entry.selectedNotes.first(where: { $0.noteID == noteID }) {
            return selected.title
        }
        return "Overall"
    }

    private var critiqueSection: some View {
        historySection("Critique", systemImage: "sparkles") {
            if let critique {
                if note.relativePath != critique.critiqueRelativePath {
                    Button {
                        context.openNote(critique.critiqueRelativePath)
                    } label: {
                        Label("Open Critique", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.link)
                }

                Button {
                    context.openNote(critique.workRelativePath)
                } label: {
                    Label("Open Target Work", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.link)

                let currentTargetSHA = context.documentRevisions[critique.workRelativePath]?.sha256
                let isStale = currentTargetSHA.map { $0 != critique.targetFingerprint.sha256 } ?? true
                Label(
                    isStale ? "Targets an earlier Work version" : "Targets the current Work version",
                    systemImage: isStale ? "clock.badge.exclamationmark" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)

                Text("Target SHA-256 \(critique.targetFingerprint.sha256.prefix(12))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !critique.rounds.isEmpty {
                    DisclosureGroup("Request Rounds (\(critique.rounds.count))") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(critique.rounds.reversed()) { round in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(round.scope.rawValue) — \(round.requestedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                    HStack(spacing: 5) {
                                        Text("SHA-256 \(round.targetFingerprint.sha256.prefix(12))…")
                                    }
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }
            } else {
                emptyText("No Critique is associated with this Work.")
            }
        }
    }

    private func historySection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func emptyText(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func reload() async {
        isLoading = true
        review = context.currentReview(note.relativePath)
        async let loadedDialogue = context.loadDialogue(note.relativePath)
        async let loadedCritique = context.loadCritique(note.relativePath)
        dialogue = await loadedDialogue
        critique = await loadedCritique
        isLoading = false
    }
}

private struct DialogueTurnRow: View {
    let id: UUID
    let participant: String
    let role: String
    let scope: String
    let text: String
    let createdAt: Date
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(participant, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .textSelection(.enabled)
            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.dialogue.turn.\(id.uuidString)")
    }
}

private enum ManualDialogueTarget: Hashable, Identifiable {
    case overall
    case note(UUID)
    case comment(UUID)

    var id: String {
        switch self {
        case .overall: "overall"
        case .note(let id): "note:\(id.uuidString)"
        case .comment(let id): "comment:\(id.uuidString)"
        }
    }
}

private struct ManualDialogueFollowUpView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ResearchController
    let entry: DialogueEntry
    let onSaved: (DialogueEntry) -> Void

    @State private var text = ""
    @State private var target: ManualDialogueTarget = .overall
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var targetOptions: [ManualDialogueTarget] {
        [.overall]
            + entry.selectedNotes.map { .note($0.noteID) }
            + entry.includedComments.map { .comment($0.comment.id) }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus.bubble")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Follow-up Comment")
                        .font(.title2.weight(.semibold))
                    Text("Continue the scholarly exchange without changing the selected notes or creating agent instructions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                Picker("Comment Applies To", selection: $target) {
                    ForEach(targetOptions) { option in
                        Text(dialogueTargetLabel(option, in: entry)).tag(option)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Comment") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(5)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityLabel("Follow-up Comment")
                        .accessibilityIdentifier("scholium.dialogue.followUpText")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Comment") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("scholium.dialogue.saveFollowUp")
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 640, minHeight: 430, idealHeight: 500)
        .alert("Could Not Add Follow-up Comment", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard canSave else { return }
        let targetIDs = dialogueTargetIDs(target, in: entry)
        isSaving = true
        Task {
            do {
                let updated = try await controller.appendDialogueFollowUpComment(
                    DialogueFollowUpComment(
                        text: text,
                        noteID: targetIDs.noteID,
                        commentID: targetIDs.commentID
                    ),
                    to: entry.id
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct ManualDialogueReplyView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ResearchController
    let entry: DialogueEntry
    let onSaved: (DialogueEntry) -> Void

    @State private var agentName = "Agent"
    @State private var text = ""
    @State private var target: ManualDialogueTarget = .overall
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var targetOptions: [ManualDialogueTarget] {
        [.overall]
            + entry.selectedNotes.map { .note($0.noteID) }
            + entry.includedComments.map { .comment($0.comment.id) }
    }

    private var canSave: Bool {
        !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record Agent Response")
                        .font(.title2.weight(.semibold))
                    Text("Store a response returned outside the local Scholium CLI in this Dialogue entry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                TextField("Agent Name", text: $agentName)
                    .accessibilityIdentifier("scholium.dialogue.agentName")
                Picker("Reply Addresses", selection: $target) {
                    ForEach(targetOptions) { option in
                        Text(dialogueTargetLabel(option, in: entry)).tag(option)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Response") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(5)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityLabel("Agent response")
                        .accessibilityIdentifier("scholium.dialogue.responseText")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Record Response") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("scholium.dialogue.saveResponse")
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 640, minHeight: 430, idealHeight: 500)
        .alert("Could Not Record Agent Response", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard canSave else { return }
        let targetIDs = dialogueTargetIDs(target, in: entry)

        isSaving = true
        Task {
            do {
                let updated = try await controller.appendDialogueReply(
                    DialogueReply(
                        agentName: agentName,
                        text: text,
                        noteID: targetIDs.noteID,
                        commentID: targetIDs.commentID
                    ),
                    to: entry.id
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private func dialogueTargetLabel(
    _ target: ManualDialogueTarget,
    in entry: DialogueEntry
) -> String {
    switch target {
    case .overall:
        return "Overall instruction"
    case .note(let noteID):
        return entry.selectedNotes.first(where: { $0.noteID == noteID })
            .map { "Note: \($0.title)" }
            ?? "Selected note"
    case .comment(let commentID):
        guard let included = entry.includedComments.first(where: {
            $0.comment.id == commentID
        }) else { return "Researcher Comment" }
        return "Comment in \(included.note.title): \(included.comment.text)"
    }
}

private func dialogueTargetIDs(
    _ target: ManualDialogueTarget,
    in entry: DialogueEntry
) -> (noteID: UUID?, commentID: UUID?) {
    switch target {
    case .overall:
        return (nil, nil)
    case .note(let id):
        return (id, nil)
    case .comment(let id):
        let noteID = entry.includedComments.first(where: {
            $0.comment.id == id
        })?.note.noteID
        return (noteID, id)
    }
}

// MARK: - Preview

#Preview {
    let controller = DocumentController()
    let note = WindowDocumentLocation.unclassified(NoteDocument(
        relativePath: "topics/consciousness.md",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note."
    ))
    let state = DocumentFeatureState(
        notes: [note],
        selectedDocumentPath: note.relativePath,
        ordinarySearchScope: .triptych,
        currentVaultID: nil,
        vaultRole: .other,
        locationScope: .unclassified,
        noteIdentityByPath: [:],
        documentRevisions: [note.relativePath: note.document.fingerprint],
        workspaceCatalog: nil,
        propertiesConfiguration: nil,
        reviewRecord: nil,
        reviewDisplayState: .notReviewed,
        changedSinceReview: false,
        canComment: false,
        canEdit: false,
        isManagedCritique: false,
        documentTextScale: 1,
        appearanceCSS: "",
        readCSS: "",
        livePreviewCSS: "",
        initialScrollFraction: 0,
        requestedPresentationMode: nil,
        pendingSourceLine: nil,
        identityAmbiguity: nil,
        pendingIdentityRebinding: nil,
        identityMigrationFailureMessage: nil,
        isResolvingIdentity: false
    )
    let actions = DocumentFeatureActions(
        requestIdentityResolution: {},
        retryIdentityRecovery: {},
        beginSearch: { _ in },
        clearRequestedPresentationMode: {},
        clearPendingSourceLine: {},
        requestComments: { _, _ in },
        rememberScrollPosition: { _ in },
        openInternalLink: { _ in },
        openExternalURL: { _ in },
        enterCSSSafeMode: { _ in },
        rememberPresentationMode: { _ in },
        setPendingSourceLine: { _ in },
        setSidebarVisible: { _ in },
        editProperties: {},
        openResearchFunction: { _, _ in },
        setResearchInspectorVisible: { _ in },
        notify: { _, _ in }
    )
    let critiqueProvenanceContext = CritiqueProvenanceContext(
        availableNotes: [note],
        documentRevisions: [note.relativePath: note.document.fingerprint],
        loadAssociation: { _ in nil },
        openTarget: { _ in },
        openFinding: { _, _ in }
    )
    NoteContentView(
        controller: controller,
        target: .unavailable(relativePath: note.relativePath),
        note: note,
        documentSession: DocumentSessionModel(key: nil),
        state: state,
        actions: actions,
        critiqueProvenanceContext: critiqueProvenanceContext
    )
}

// MARK: - RoundedCorner Shape (for NSTabView-style folder tabs)

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: RectCorner

    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft = RectCorner(rawValue: 1 << 0)
        static let topRight = RectCorner(rawValue: 1 << 1)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)

        // Top-left corner
        if corners.contains(.topLeft) {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                       radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - (corners.contains(.topRight) ? r : 0), y: rect.minY))

        // Top-right corner
        if corners.contains(.topRight) {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                       radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
