import AppKit
import QuickLook
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

enum DocumentNotificationKind {
    case information
    case error
}

private enum ImageAttachmentSelectionMode: Equatable {
    case importFile
    case index
}

enum DocumentIntegrityPresentation: Hashable {
    case autosaveFailed(message: String, canRetry: Bool)
    case conflict

    static func resolve(
        editError: String?,
        conflict: DocumentConflictSnapshot?,
        canRetrySave: Bool
    ) -> Self? {
        if conflict != nil { return .conflict }
        guard let editError, !editError.isEmpty else { return nil }
        return .autosaveFailed(message: editError, canRetry: canRetrySave)
    }

    var title: String {
        switch self {
        case .autosaveFailed:
            String(localized: "Autosave Failed", table: "Localizable", bundle: .module)
        case .conflict:
            String(localized: "Autosave Paused", table: "Localizable", bundle: .module)
        }
    }

    var detail: String {
        switch self {
        case .autosaveFailed(let message, _):
            String(
                localized: "Your edits are still available. \(message)",
                table: "Localizable",
                bundle: .module
            )
        case .conflict:
            String(
                localized: "This file changed outside Scholium. Your edits are still available.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    var kind: ScholiumDocumentStatusKind {
        switch self {
        case .autosaveFailed: .destructive
        case .conflict: .attention
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .autosaveFailed: "scholium.documentStatus.autosaveFailed"
        case .conflict: "scholium.documentStatus.conflict"
        }
    }

    var announcement: String {
        switch self {
        case .autosaveFailed(_, let canRetry):
            if canRetry {
                return String(
                    localized: "\(title). \(detail) Retry Save is available.",
                    table: "Localizable",
                    bundle: .module
                )
            }
            return "\(title). \(detail)"
        case .conflict:
            return String(
                localized: "\(title). \(detail) Compare Changes is available.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

struct DocumentFeatureState {
    let notes: [WindowDocumentLocation]
    let activeNote: WorkspaceNoteSnapshot?
    let selectedDocumentPath: String?
    let ordinarySearchScope: SearchPresentationScope
    let currentVaultID: UUID?
    let vaultRole: VaultRole
    let noteIdentityByPath: [String: UUID]
    let workspaceCatalog: WorkspaceCatalogSnapshot?
    let canEdit: Bool
    let documentTextScale: Double
    let appearanceCSS: String
    let readCSS: String
    let livePreviewCSS: String
    let initialScrollFraction: Double
    let requestedPresentationMode: NotePresentationMode?
    let sourceLocationRequest: DocumentSourceLocationRequest?
    let identityAmbiguity: NoteIdentityAmbiguity?
    let pendingIdentityRebinding: NoteIdentityPendingRebinding?
    let identityMigrationFailureMessage: String?
    let isResolvingIdentity: Bool
}

struct DocumentFeatureActions {
    var passageAction: @MainActor (DocumentPassageAction, MarkdownSourceSelectionSnapshot?) -> Void = { _, _ in }
    var askAgent: AgentSelectionInquiryHandler = { _, _ in nil }
    var writingContinuation: EditorWritingContinuationQuery = { _, _ in .unavailable(nil) }
    let requestIdentityResolution: @MainActor () -> Void
    let retryIdentityRecovery: @MainActor () async -> Void
    let beginSearch: @MainActor (SearchInvocation) -> Void
    let clearRequestedPresentationMode: @MainActor () -> Void
    let consumeSourceLocation: @MainActor (UUID) -> Void
    let navigateToSourceLine: @MainActor (Int, String?) -> Void
    let rememberScrollPosition: @MainActor (Double) -> Void
    let openInternalLink: @MainActor (String) -> Void
    let openExternalURL: @MainActor (URL) -> Void
    let enterCSSSafeMode: @MainActor (String) -> Void
    let rememberPresentationMode: @MainActor (NotePresentationMode) -> Void
    let setSidebarVisible: @MainActor (Bool) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let openingDocumentPresentationDidComplete: @MainActor () -> Void
    let renameNote:
        @MainActor (
            WindowDocumentLocation,
            String,
            String
        ) async throws -> String
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
    var registerEditorActions:
        @MainActor (
            ScholiumEditorCommandPort, DocumentEditingTarget, DocumentSessionModel,
            ScholiumFocusedEditorActions, ScholiumEditorCommandRegistrationChange
        ) -> Void = { _, _, _, _, _ in }
    var unregisterEditorActions: @MainActor (UUID) -> Void = { _ in }
}

// MARK: - Note Content Container

struct DocumentFeatureView<ShellNotices: View>: View {
    @ObservedObject private var controller: DocumentController
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let hasShellNotices: Bool
    let shellNotices: ShellNotices

    init(
        controller: DocumentController,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        hasShellNotices: Bool,
        @ViewBuilder shellNotices: () -> ShellNotices
    ) {
        self.controller = controller
        self.state = state
        self.actions = actions
        self.hasShellNotices = hasShellNotices
        self.shellNotices = shellNotices()
    }

    var body: some View {
        if let selectedDocumentPath = state.selectedDocumentPath,
            let active = state.activeNote,
            active.id.relativePath == selectedDocumentPath
        {
            let note = active
            let selectedWorkspaceKey = controller.activeDocument.flatMap { descriptor in
                descriptor.reference.relativePath == selectedDocumentPath
                    ? descriptor.sessionKey
                    : nil
            }
            let projectedWorkspaceKey = state.currentVaultID.flatMap { vaultID in
                state.noteIdentityByPath[note.id.relativePath].map { noteID in
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
                    hasShellNotices: hasShellNotices,
                    shellNotices: shellNotices
                )
                .id(key)
            } else {
                DocumentSessionFallback(
                    note: note,
                    controller: controller,
                    target: .unavailable(
                        vaultID: note.id.vaultID,
                        relativePath: note.id.relativePath
                    ),
                    state: state,
                    actions: actions,
                    hasShellNotices: hasShellNotices,
                    shellNotices: shellNotices
                )
                .id(selectedDocumentPath)
            }
        }
    }
}

private struct DocumentSessionFallback<ShellNotices: View>: View {
    let note: WorkspaceNoteSnapshot
    let controller: DocumentController
    let target: DocumentEditingTarget
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let hasShellNotices: Bool
    let shellNotices: ShellNotices

    var body: some View {
        NoteContentView(
            controller: controller,
            target: target,
            note: note,
            documentSession: controller.session(for: target),
            state: state,
            actions: actions,
            hasShellNotices: hasShellNotices,
            shellNotices: shellNotices
        )
    }
}

struct NoteContentView<ShellNotices: View>: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @ObservedObject private var controller: DocumentController
    @ObservedObject private var documentSession: DocumentSessionModel
    @ObservedObject private var writingContinuationPreferences = WritingAssistancePreferences.shared
    let target: DocumentEditingTarget
    let note: WorkspaceNoteSnapshot
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let hasShellNotices: Bool
    let shellNotices: ShellNotices
    private let openingPresentationID: UUID
    @StateObject private var editorCommandPort = ScholiumEditorCommandPort()
    @StateObject private var quickLook = DocumentAttachmentQuickLookSession()
    @ObservedObject private var documentFind: DocumentFindPresentationModel
    @State private var isInsertingImage = false
    @State private var announcedUnavailableIndexedImages: Set<String> = []
    @State private var indexedImageAvailabilityGeneration = 0
    @State private var outlineEntries: [DocumentOutlineEntry] = []
    @State private var outlineScrollFraction: Double
    @State private var outlineScrollAnchor: EditorScrollAnchor?
    @State private var outlineSelectionEntryID: DocumentOutlineEntry.ID?
    @State private var outlineSelectionAwaitsScrollAnchor = false

    init(
        controller: DocumentController,
        target: DocumentEditingTarget,
        note: WorkspaceNoteSnapshot,
        documentSession: DocumentSessionModel,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        hasShellNotices: Bool,
        shellNotices: ShellNotices
    ) {
        self.controller = controller
        _documentSession = ObservedObject(wrappedValue: documentSession)
        _documentFind = ObservedObject(wrappedValue: documentSession.findPresentation)
        self.target = target
        self.note = note
        self.state = state
        self.actions = actions
        self.hasShellNotices = hasShellNotices
        self.shellNotices = shellNotices
        openingPresentationID = documentSession.editorSession.openingPresentationID
        _outlineScrollFraction = State(initialValue: documentSession.scrollFraction)
        _outlineScrollAnchor = State(initialValue: documentSession.scrollAnchor)
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
        documentSession.presentationMode
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
    private var documentIntegrityPresentation: DocumentIntegrityPresentation? {
        DocumentIntegrityPresentation.resolve(
            editError: editError,
            conflict: conflict,
            canRetrySave: canRetrySave
        )
    }
    private var showConflictComparison: Bool {
        get { documentSession.showConflictComparison }
        nonmutating set {
            if newValue {
                documentSession.presentConflictComparison()
            } else {
                documentSession.dismissConflictComparison()
            }
        }
    }
    private var conflictForComparison: DocumentConflictSnapshot? {
        documentSession.conflictComparison ?? documentSession.conflict
    }
    private var editorSession: MarkdownEditorSession { documentSession.editorSession }

    private var documentAttachmentTarget: SourceAttachmentTarget? {
        guard case .workspace(let key) = target,
            key.vaultID == note.id.vaultID
        else { return nil }
        return SourceAttachmentTarget(
            noteID: key.noteID,
            vaultID: key.vaultID,
            relativePath: note.id.relativePath
        )
    }

    private struct EditorCommandFacts: Equatable {
        let availability: EditorInteractionAvailability?
        let mode: NotePresentationMode
        let isLoaded: Bool
        let isAttaching: Bool
        let documentID: String
        let notePath: String
        let canEdit: Bool
    }

    private var editorCommandFacts: EditorCommandFacts {
        EditorCommandFacts(
            availability: editorSession.interactionAvailability,
            mode: documentSession.presentationMode,
            isLoaded: editorSession.isLoaded,
            isAttaching: documentSession.isAttachingDocument,
            documentID: editorSession.documentID,
            notePath: note.id.relativePath,
            canEdit: state.canEdit
        )
    }

    private func publishEditorActionsIfSelected(
        change: ScholiumEditorCommandRegistrationChange
    ) {
        guard controller.selectedDocument?.editingTarget == target,
            controller.retainsSession(documentSession, for: target)
        else { return }
        actions.registerEditorActions(
            editorCommandPort, target, documentSession,
            ScholiumFocusedEditorActions(
                documentID: isEditing ? editorSession.documentID : note.id.relativePath,
                isComposing: isEditing && editorSession.context?.composing == true,
                isAvailable: { command in
                    isEditing && editorSession.context?.availableCommands.contains(command) == true
                },
                perform: { command in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command)
                        } catch {
                            actions.notify(ScholiumErrorLocalization.message(error), .error)
                        }
                    }
                },
                performWithArgument: { command, argument in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command, argument: argument)
                        } catch {
                            actions.notify(ScholiumErrorLocalization.message(error), .error)
                        }
                    }
                },
                importImage: requestImageImport,
                indexImage: requestImageIndex,
                canAttachDocument: isEditing && editorSession.isLoaded && documentAttachmentTarget != nil
                    && !documentSession.isAttachingDocument,
                attachDocumentCopy: { requestDocumentAttachment(.copyIntoTriptych) },
                referenceOriginalDocument: { requestDocumentAttachment(.referenceOriginal) },
                canEditFrontmatter: editingIsAvailable,
                goToFrontmatter: goToFrontmatter
            ),
            change
        )
    }

    private func unpublishEditorActions() {
        actions.unregisterEditorActions(editorCommandPort.token)
        editorCommandPort.actions = nil
    }

    var body: some View {
        AnyView(
            documentBodySurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            DocumentFindOverlay(
                                model: documentFind,
                                allowsReplacement: isEditing,
                                availableWidth: geometry.size.width
                            )
                            GeometryReader { remaining in
                                if hasShellNotices || hasLocalNotices {
                                    ScholiumDocumentNoticeStack(availableSize: remaining.size) {
                                        shellNotices
                                        localNotices
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .transition(ScholiumMotion.documentNoticeTransition(reduceMotion: reduceMotion))
                                }
                            }
                        }
                        .animation(
                            ScholiumMotion.documentNotice(reduceMotion: reduceMotion),
                            value: hasShellNotices || hasLocalNotices
                        )
                    }
                }
                .scholiumSurface(.document)
        )
        .onAppear { publishEditorActionsIfSelected(change: .activation) }
        .onChange(of: editorCommandFacts) { _, _ in publishEditorActionsIfSelected(change: .refresh) }
        .onChange(of: controller.selectedDocument?.editingTarget) { _, selected in
            if selected == target { publishEditorActionsIfSelected(change: .activation) } else { unpublishEditorActions() }
        }
        .sheet(
            isPresented: Binding(
                get: { showConflictComparison },
                set: { showConflictComparison = $0 }
            )
        ) {
            if let conflict = conflictForComparison {
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
                .buttonStyle(.automatic)
            }
        }
        .task(id: documentIntegrityPresentation) {
            guard let presentation = documentIntegrityPresentation else { return }
            AccessibilityNotification.Announcement(presentation.announcement).post()
        }
        .onChange(of: state.requestedPresentationMode) { _, requested in
            guard let requested else { return }
            selectPresentationMode(requested)
            actions.clearRequestedPresentationMode()
        }
        .task(id: sourceLocationExecutionID) { await consumePendingSourceLocation() }
        .onAppear {
            controller.observe(documentSession)
            applyPreparedPresentationModeIfAvailable()
            consumePendingPresentationRequest()
        }
        .onChange(of: editingIsAvailable) { _, available in
            // Window restoration publishes the selected note before stable
            // identity recovery necessarily finishes. Keep the edit gate
            // intact, then apply the committed mode as soon as editing becomes
            // available instead of leaving the document in the default Read
            // mode for the rest of the session.
            if available { applyPreparedPresentationModeIfAvailable() }
        }
        .onChange(of: isEditing) { _, _ in
            documentSession.readSelection = nil
            documentFind.refresh()
            outlineScrollFraction = documentSession.scrollFraction
            outlineScrollAnchor = documentSession.scrollAnchor
            focusEditorIfPresented()
            if !isEditing,
                documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256
            {
                markReadPresentationReady(documentID: note.id.relativePath)
            }
        }
        .onChange(of: editorSession.presentedMode) { _, presentedMode in
            focusEditorIfPresented()
            if let presentedMode {
                PerformanceProbe.shared.markEditorModeAcknowledged(
                    documentID: note.id.relativePath,
                    mode: presentedMode
                )
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: note.id.relativePath,
                    mode: presentedMode
                )
            }
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded else { return }
            documentFind.refresh()
            focusEditorIfPresented()
        }
        .onChange(of: noteFingerprint.sha256) { _, _ in
            documentFind.refresh()
        }
        .onChange(of: documentSession.renderedReadReadyFingerprint) { _, ready in
            if !isEditing, ready == noteFingerprint.sha256 {
                documentFind.refresh()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            indexedImageAvailabilityGeneration &+= 1
        }
        .task(id: outlineTaskIdentity) {
            let entries = DocumentOutlineProjection.make(
                relativePath: note.id.relativePath,
                source: outlineSource
            )
            guard !Task.isCancelled else { return }
            outlineSelectionEntryID = nil
            outlineSelectionAwaitsScrollAnchor = false
            outlineEntries = entries
        }
        .task(id: readProjectionTaskIdentity) {
            guard documentSession.requiresReadProjection, !Task.isCancelled else { return }
            PerformanceProbe.shared.markReadTaskStarted(
                documentID: note.id.relativePath
            )
            documentSession.prepareReadProjection(
                for: noteFingerprint.sha256
            )
            let source = note.document.rawContent
            let relativePath = note.id.relativePath
            let fingerprint = noteFingerprint
            if !isEditing {
                documentSession.readSelection = nil
                // Entering Review now starts this task too. Preserve an
                // explicit mode-handoff or navigation request for this exact
                // revision instead of replacing its restoration identity.
                if documentSession.scrollRestoreRequest?.fingerprint != fingerprint.sha256 {
                    documentSession.requestReadScrollRestore(
                        fingerprint: fingerprint.sha256,
                        reason: .documentLoad
                    )
                }
            }
            if note.document.hasExactEmptyBody {
                // A header-only Note is already a complete Review state. Do
                // not start WebKit merely to render an exact empty body or
                // imply that source loading is still in progress.
                renderedReadHTML = ""
                renderedReadFingerprint = fingerprint.sha256
                documentSession.renderedReadReadyFingerprint = fingerprint.sha256
                if !isEditing {
                    markReadPresentationReady(documentID: relativePath)
                }
                return
            }
            let html = await documentSession.loadReadProjectionIfNeeded {
                await controller.readProjectionHTML(
                    target: target,
                    relativePath: relativePath,
                    source: source,
                    fingerprint: fingerprint,
                    workspaceID: state.currentVaultID,
                    semantic: note.cachedSemanticDocument
                )
            }
            guard let html, !Task.isCancelled, fingerprint == noteFingerprint else { return }
            PerformanceProbe.shared.markReadHTMLReady(documentID: relativePath)
            renderedReadHTML = html
            renderedReadFingerprint = fingerprint.sha256
        }
        .task(id: indexedImageAvailabilityTaskIdentity) {
            await checkIndexedImageAvailability()
        }
        .quickLookPreview(Binding(get: { quickLook.url }, set: { if $0 == nil { quickLook.dismiss() } }))
        .onDisappear {
            quickLook.dismiss()
            unpublishEditorActions()
            controller.dismissFindForDisappearingPresentation(
                target: target, session: documentSession,
                openingPresentationID: openingPresentationID
            )
        }
        .task(id: previewTaskIdentity) {
            await rebuildPreviewCatalog()
        }
        .task(id: documentFind.request) {
            guard let request = documentFind.request else { return }
            if case .clear = request.operation {
                if isEditing {
                    await editorSession.clearDocumentFind()
                }
                return
            }
            guard isEditing, let query = request.editorQuery else { return }
            do {
                let result = try await editorSession.performDocumentFind(query)
                documentFind.accept(result, for: request.id)
            } catch {
                documentFind.fail(error, for: request.id)
            }
        }
        .onDisappear {
        }
    }

    private var hasLocalNotices: Bool {
        state.identityAmbiguity != nil
            || state.pendingIdentityRebinding != nil
            || documentIntegrityPresentation != nil
            || citationPresentation.isVisible
    }

    private var citationPresentation: DocumentCitationPresentation {
        documentSession.citationPresentation(committedDocument: note.document, editingIsAvailable: editingIsAvailable)
    }

    @ViewBuilder
    private var localNotices: some View {
        DocumentCitationNotice(
            presentation: citationPresentation,
            dismiss: editorSession.dismissCitationStatus,
            refresh: {
                Task { @MainActor in
                    guard controller.selectedDocument?.editingTarget == target, citationPresentation.canRefresh else { return }
                    do { try await editorSession.perform(.refreshCitations) } catch {
                        await editorSession.announceCitationStatus(ScholiumErrorLocalization.message(error))
                    }
                }
            },
            openSource: {
                guard controller.selectedDocument?.editingTarget == target, citationPresentation.canOpenSource else { return }
                selectPresentationMode(.source)
            }
        )

        if let ambiguity = state.identityAmbiguity {
            IdentityAmbiguityNotice(ambiguity: ambiguity) {
                actions.requestIdentityResolution()
            }
        } else if let pending = state.pendingIdentityRebinding {
            IdentityMigrationNotice(
                rebinding: pending,
                message: state.identityMigrationFailureMessage,
                isRetrying: state.isResolvingIdentity
            ) {
                await actions.retryIdentityRecovery()
            }
        }

        if let presentation = documentIntegrityPresentation {
            ScholiumDocumentStatusNotice(
                presentation.title,
                detail: presentation.detail,
                kind: presentation.kind
            ) {
                documentIntegrityActions(presentation)
            }
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func documentIntegrityActions(
        _ presentation: DocumentIntegrityPresentation
    ) -> some View {
        switch presentation {
        case .autosaveFailed(_, let canRetry):
            if canRetry {
                Button("Retry Save") {
                    controller.retrySave(session: documentSession, target: target)
                }
                .scholiumActivationPointer()
                .controlSize(.small)
            }
        case .conflict:
            Button("Compare Changes") {
                showConflictComparison = true
            }
            .scholiumActivationPointer()
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var readProjectionTaskIdentity: String? {
        documentSession.readProjectionTaskIdentity(relativePath: note.id.relativePath, fingerprint: noteFingerprint)
    }

    private var outlineSource: String {
        isEditing ? editingSource : note.document.rawContent
    }

    private var outlineTaskIdentity: String {
        if isEditing {
            return "editing:\(editorSession.documentID):\(DocumentFingerprint(content: editingSource).sha256)"
        }
        return "read:\(noteFingerprint.sha256)"
    }

    private var previewTaskIdentity: String {
        let generation = state.workspaceCatalog?.graph?.generation ?? -1
        return "\(state.currentVaultID?.uuidString ?? "unavailable"):\(noteFingerprint.sha256):\(generation):\(presentationMode.rawValue):\(hasUnsavedChanges)"
    }

    @MainActor
    private func rebuildPreviewCatalog() async {
        guard let vaultID = state.currentVaultID,
            let graph = state.workspaceCatalog?.graph,
            state.selectedDocumentPath == note.id.relativePath,
            presentationMode != .source,
            !hasUnsavedChanges
        else {
            documentSession.previewCatalog = nil
            return
        }
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.id.relativePath)
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
                !hasUnsavedChanges
            else { return }
            documentSession.previewCatalog = catalog
        } catch {
            guard !Task.isCancelled else { return }
            documentSession.previewCatalog = nil
        }
    }

    private var editingIsAvailable: Bool {
        state.canEdit
    }

    private var noteFingerprint: DocumentFingerprint {
        // Library summaries can advance before retained source hydration.
        // Every projection and editing base must name these exact bytes so
        // the hydration commit starts a new task for its own revision.
        note.fingerprint
    }

    private var bodyEditor: AnyView {
        AnyView(
            MarkdownEditorWebView(
                session: editorSession,
                documentID: editorSession.bridgeDocumentID,
                documentTitle: note.summary.title,
                performanceDocumentID: note.id.relativePath,
                source: editingSource,
                mode: documentSession.retainedEditorMode,
                presentationCSS: documentPresentationCSS,
                userCSS: state.livePreviewCSS,
                requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(
                    linkPreviews: documentSession.previewCatalog?.links ?? []
                ),
                linkCompletionQuery: queryEditorLinkCompletions,
                linkPreviews: documentSession.previewCatalog?.links ?? [],
                initialScrollFraction: documentSession.editorScrollFraction,
                initialScrollAnchor: editorScrollAnchor,
                onDocumentActivity: {
                    controller.editorSourceDidChange(
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
                onRequestFind: handleDocumentFindShortcut,
                onRequestDocumentTitleRename: { expectedTitle, requestedTitle in
                    try await actions.renameNote(.hydrated(note), expectedTitle, requestedTitle)
                },
                onPasteImage: handlePastedImage,
                onLinkActivation: openAuthoredLink,
                onScrollFractionChange: {
                    guard isEditing,
                        editorSession.openingPresentationID == openingPresentationID
                    else { return }
                    rememberOutlineScrollFraction($0)
                    documentSession.observeScrollFraction($0, on: .editor)
                    actions.rememberScrollPosition($0)
                },
                onScrollAnchorChange: {
                    guard isEditing,
                        editorSession.openingPresentationID == openingPresentationID
                    else { return }
                    rememberOutlineScrollAnchor($0)
                    documentSession.observeScrollAnchor($0, on: .editor)
                },
                onAskAgent: actions.askAgent,
                onPassageAction: { actions.passageAction($0, nil) },
                writingContinuationEnabled: writingContinuationPreferences.continuationEnabled,
                writingContinuationContextKey: writingContinuationPreferences.model,
                writingIndexContextKey: state.workspaceCatalog.map {
                    "\(state.currentVaultID?.uuidString ?? ""):\($0.generatedAt.timeIntervalSinceReferenceDate.bitPattern)"
                } ?? "",
                writingContinuationQuery: actions.writingContinuation,
                imageResourceContextKey: "\(note.id.vaultID):\(note.id.relativePath):\(indexedImageAvailabilityGeneration)",
                imageResourcesQuery: queryEditorImageResources
            )
            .id(editorSession.viewReconstructionID)
            .allowsHitTesting(!returnToReadAfterSave)
            .accessibilityHidden(returnToReadAfterSave)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1))
    }

    @ViewBuilder
    private var documentBodySurface: some View {
        DocumentEditorHost(
            documentID: editorSession.openingPresentationID.uuidString,
            presentsEditor: isEditing || documentSession.pendingEditorMode != nil,
            retainsEditor: documentSession.retainsEditorSurface,
            editorIsReady: editorSession.isLoaded
                && editorSession.presentedMode == documentSession.activeEditorMode,
            allowsPendingReadRecovery: !editorSession.isLoaded && editorSession.errorMessage != nil
        ) {
            readSurface
        } editor: {
            bodyEditor
        }
        .environment(\.documentToolbarUnderlap, true)
        .ignoresSafeArea(.container, edges: .top)
        .scholiumSurface(.document)
        .overlay(alignment: .topLeading) {
            if isEditing,
                editorSession.isLoaded,
                let presentedMode = editorSession.presentedMode,
                presentedMode == documentSession.activeEditorMode
            {
                PerformanceReadyBoundary(
                    generation: "\(noteFingerprint.sha256):\(presentedMode.rawValue)"
                ) {
                    PerformanceProbe.shared.markEditorModeVisible(
                        documentID: note.id.relativePath,
                        mode: presentedMode
                    )
                    PerformanceProbe.shared.markEditorVisible(
                        documentID: note.id.relativePath
                    )
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            if !isEditing,
                note.document.hasExactEmptyBody
                    || documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256
            {
                PerformanceReadyBoundary(
                    generation: "read:\(noteFingerprint.sha256)"
                ) {
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .trailing) {
            documentOutlineOverlay
        }
    }

    @ViewBuilder
    private var documentOutlineOverlay: some View {
        GeometryReader { proxy in
            let hasSpace = proxy.size.width >= ScholiumMetrics.Document.outlineRailMinimumWidth
            let contentIsReady =
                isEditing
                ? editorSession.isLoaded
                : documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256
            let canShow = hasSpace && contentIsReady && outlineEntries.count > 1

            Group {
                if canShow {
                    let railContentHeight =
                        CGFloat(outlineEntries.count) * ScholiumMetrics.Document.outlineMarkerTarget
                        + ScholiumMetrics.Document.outlineRailVerticalInset * 2
                    DocumentOutlineRail(
                        entries: outlineEntries,
                        activeEntryID: outlineSelectionEntryID
                            ?? DocumentOutlineProjection.activeEntryID(
                                entries: outlineEntries,
                                sourceUTF16Offset: outlineScrollAnchor?.sourceUTF16Offset,
                                scrollFraction: outlineScrollFraction
                            ),
                        documentViewportHeight: proxy.size.height,
                        select: navigateToOutlineEntry
                    )
                    .frame(
                        height: min(
                            max(0, proxy.size.height - ScholiumGrid.Spacing.regionContentInset * 2),
                            min(
                                railContentHeight,
                                ScholiumMetrics.Document.outlineRailMaximumHeight
                            )
                        ),
                        alignment: .trailing
                    )
                    .padding(.trailing, ScholiumGrid.Spacing.inlineControlGap)
                    .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .trailing)
            .animation(
                ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                value: canShow
            )
            .accessibilityHidden(!canShow)
            .allowsHitTesting(canShow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func navigateToOutlineEntry(_ entry: DocumentOutlineEntry) {
        outlineSelectionEntryID = entry.id
        outlineSelectionAwaitsScrollAnchor = true
        actions.navigateToSourceLine(
            entry.sourceLine,
            isEditing ? nil : noteFingerprint.sha256
        )
    }

    private func rememberOutlineScrollFraction(_ fraction: Double) {
        outlineScrollFraction = fraction
        // The editor and reader report the fraction and source anchor in
        // different orders. Let the matching anchor decide whether a
        // click-selected marker should be cleared.
    }

    private func rememberOutlineScrollAnchor(_ anchor: EditorScrollAnchor) {
        outlineScrollAnchor = anchor

        // Keep a click-selected marker while the programmatic reveal settles.
        // Once the reported source position belongs to another outline
        // section, normal scroll tracking takes over again.
        if outlineSelectionAwaitsScrollAnchor,
            outlineSelectionEntryID != nil
        {
            outlineSelectionAwaitsScrollAnchor = false
            return
        }
        guard let selectionID = outlineSelectionEntryID,
            let resolvedID = DocumentOutlineProjection.activeEntryID(
                entries: outlineEntries,
                sourceUTF16Offset: anchor.sourceUTF16Offset,
                scrollFraction: anchor.fallbackFraction
            ),
            resolvedID != selectionID
        else { return }
        outlineSelectionEntryID = nil
    }

    @ViewBuilder
    private var readSurface: some View {
        if isEditing, !editorSession.isLoaded, let error = editorSession.errorMessage {
            editorFailure(error)
        } else if documentSession.isEnteringManagedCreation {
            // The host covers preparation until the editor acknowledges its mode.
            Color.clear.accessibilityHidden(true)
        } else if note.document.hasExactEmptyBody {
            emptyReviewState
        } else {
            let hasWebProjection =
                renderedReadFingerprint == noteFingerprint.sha256
                && failedReadFingerprint != noteFingerprint.sha256
            let webProjectionIsReady =
                hasWebProjection
                && documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256

            ZStack {
                if !webProjectionIsReady {
                    readProjectionPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                }

                if hasWebProjection {
                    readDocumentSurface
                        .opacity(webProjectionIsReady ? 1 : 0)
                        .allowsHitTesting(webProjectionIsReady && !isEditing)
                        .accessibilityHidden(!webProjectionIsReady)
                }
            }
        }
    }

    private var emptyReviewState: some View {
        ScholiumContentStateView(
            "Empty Note",
            detail: Text("This note has no body content."),
            indicator: .symbol("doc")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.emptyRenderedReview")
    }

    private func editorFailure(_ error: String) -> some View {
        ScholiumContentStateView(
            "Edit Unavailable",
            detail: documentSession.isEnteringManagedCreation
                ? Text("The note was created and its exact source is saved. \(error)")
                : Text(error),
            indicator: .symbol("exclamationmark.triangle", role: .attention)
        ) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button("Retry Edit") {
                    retryEditor(in: .livePreview)
                }
                .scholiumActivationPointer()
                .keyboardShortcut(.defaultAction)
                Button("Source") {
                    retryEditor(in: .source)
                }
                .scholiumActivationPointer()
            }
        }
        .accessibilityIdentifier(
            documentSession.isEnteringManagedCreation
                ? "scholium.managedNewNote.editorFailure" : "scholium.documentEditorFailure"
        )
    }

    @ViewBuilder
    private var readProjectionPlaceholder: some View {
        if failedReadFingerprint == noteFingerprint.sha256 {
            ScholiumContentStateView(
                "Review Mode Unavailable",
                detail: Text("Use Source mode while the rendered document is unavailable."),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            ) {
                Button("Source") { beginEditing(mode: .source) }
                    .disabled(!editingIsAvailable)
            }
        } else {
            ScholiumContentStateView(
                "Loading Document…",
                indicator: .progress
            )
        }
    }

    private var readDocumentSurface: some View {
        SafeMarkdownReadWebView(
            documentID: note.id.relativePath,
            documentTitle: note.summary.title,
            fingerprint: noteFingerprint.sha256,
            source: note.document.rawContent,
            htmlBody: renderedReadHTML,
            presentationCSS: documentPresentationCSS,
            userCSS: state.readCSS,
            configurationRevision: readConfigurationRevision,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            linkPreviewRevision: readLinkPreviewRevision,
            onLinkClick: openAuthoredLink,
            onOpenExternalURL: { openAuthoredLink($0.absoluteString) },
            onAskAgent: actions.askAgent,
            onPassageAction: { actions.passageAction($0, $1) },
            onSelectionChange: { selection in
                guard !isEditing else { return }
                documentSession.readSelection = selection
            },
            selectionSurfaceIsActive: !isEditing,
            renderingReadinessIsAcknowledged:
                documentSession.renderedReadReadyFingerprint
                == noteFingerprint.sha256,
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
                if !isEditing {
                    markReadPresentationReady(documentID: note.id.relativePath)
                }
            },
            findRequest: isEditing ? nil : documentFind.request,
            onFindResult: { requestID, result in
                switch result {
                case .success(let value):
                    documentFind.accept(value, for: requestID)
                case .failure(let error):
                    documentFind.fail(error, for: requestID)
                }
            },
            observedScrollPosition: documentSession.readScrollPosition,
            scrollRestoreRequest: documentSession.scrollRestoreRequest,
            onScrollRestoreConsumed: { id, fingerprint in
                documentSession.acknowledgeScrollRestoreRequest(
                    id: id,
                    fingerprint: fingerprint
                )
            },
            onScrollFractionChange: {
                guard !isEditing,
                    editorSession.openingPresentationID == openingPresentationID
                else { return }
                rememberOutlineScrollFraction($0)
                documentSession.observeScrollFraction($0, on: .read)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: {
                guard !isEditing,
                    editorSession.openingPresentationID == openingPresentationID
                else { return }
                rememberOutlineScrollAnchor($0)
                documentSession.observeScrollAnchor($0, on: .read)
            },
            sourceLocationRequest: isEditing ? nil : currentSourceLocationRequest,
            onSourceRangeUnavailable: { id in
                guard !isEditing, currentSourceLocationRequest?.id == id else { return }
                if editingIsAvailable {
                    selectPresentationMode(.source)
                } else {
                    actions.consumeSourceLocation(id)
                    actions.notify(
                        String(localized: "This passage cannot be selected in Review. Its supplied text remains available in Chat.", bundle: .module),
                        .information)
                }
            },
            onSourceRevisionChanged: { id in
                guard currentSourceLocationRequest?.id == id else { return }
                actions.consumeSourceLocation(id)
                reportChangedSourceLocation()
            },
            onSourceLocationReached: { id in
                guard !isEditing else { return }
                actions.consumeSourceLocation(id)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func markReadPresentationReady(documentID: String) {
        PerformanceProbe.shared.markReadReady(documentID: documentID)
    }

    private var editorScrollAnchor: EditorScrollAnchor? {
        if let retained = editorSession.retainedScrollAnchor {
            return retained
        }
        let fingerprint = DocumentFingerprint(content: editorSession.checkedSource).sha256
        guard documentSession.editorScrollAnchor?.sourceFingerprint == fingerprint else { return nil }
        return documentSession.editorScrollAnchor
    }

    private var documentPresentation: ScholiumDocumentPresentationConfiguration {
        ScholiumDocumentPresentationConfiguration(textScale: state.documentTextScale)
    }

    private var documentPresentationCSS: String {
        documentPresentation.css + "\n" + state.appearanceCSS
    }

    private var readConfigurationRevision: String {
        [
            noteFingerprint.sha256,
            String(note.summary.title.hashValue),
        ].joined(separator: ":")
    }

    private var readLinkPreviewRevision: String {
        let previewRevision =
            documentSession.previewCatalog.map { catalog in
                let targets = catalog.links.map { link in
                    "\(link.sourceSpan.utf16LowerBound)-\(link.sourceSpan.utf16UpperBound):"
                        + link.targetFingerprint.sha256
                }.joined(separator: ",")
                return "\(catalog.graphGeneration):\(catalog.sourceFingerprint.sha256):\(targets)"
            } ?? "no-previews"
        return previewRevision
    }

    private var hasUnsavedChanges: Bool {
        documentSession.hasUnsavedChanges
    }

    @MainActor
    private func queryEditorImageResources(_ source: String) async -> [String: RenderedMarkdownImage] {
        guard controller.selectedDocument?.editingTarget == target,
            controller.retainsSession(documentSession, for: target),
            editorSession.openingPresentationID == openingPresentationID
        else { return [:] }
        let images = await controller.documentImageResources(
            target: target,
            relativePath: note.id.relativePath,
            source: source,
            fingerprint: DocumentFingerprint(content: source)
        )
        guard !Task.isCancelled,
            controller.selectedDocument?.editingTarget == target,
            controller.retainsSession(documentSession, for: target),
            editorSession.openingPresentationID == openingPresentationID
        else { return [:] }
        return images
    }

    @MainActor
    private func queryEditorLinkCompletions(
        _ kind: EditorLinkCompletionKind,
        _ query: String
    ) async -> [EditorLinkCompletion] {
        guard let currentVaultID = state.currentVaultID,
            let catalogNotes = state.workspaceCatalog?.notes
        else {
            return []
        }
        if kind == .term {
            return controller.editorWritingTermCompletions(
                matching: query, catalogNotes: catalogNotes)
        }
        guard let generation = state.workspaceCatalog?.graph?.generation else { return [] }
        return await controller.editorLinkCompletions(
            kind: kind,
            matching: query,
            sourcePath: note.id.relativePath,
            currentVaultID: currentVaultID,
            catalogNotes: catalogNotes,
            graphGeneration: generation
        )
    }

    private var editorIsComposing: Bool {
        isEditing && editorSession.context?.composing == true
    }

    private var indexedImageAvailabilityTaskIdentity: String {
        "\(note.id.relativePath):\(noteFingerprint.sha256):\(indexedImageAvailabilityGeneration)"
    }

    private func openAuthoredLink(_ destination: String) {
        if let url = URL(string: destination),
            ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
        {
            actions.openExternalURL(url)
            return
        }
        if let url = URL(string: destination), let reference = try? ZoteroReference(url: url) {
            actions.openExternalURL(reference.url)
            return
        }
        guard let file = SourceResourceReferences.file(destination: destination, noteRelativePath: note.id.relativePath),
            let attachmentTarget = documentAttachmentTarget
        else {
            actions.openInternalLink(destination)
            return
        }
        Task { @MainActor in
            do {
                if isEditing {
                    await controller.persistEditingSource(session: documentSession, target: target)
                    guard documentSession.editError == nil, documentSession.conflict == nil else { return }
                }
                let snapshots = try await controller.documentAttachments(for: attachmentTarget)
                let matching: DocumentAttachmentSnapshot?
                if let path = file.relativePath {
                    matching = snapshots.first { $0.record.location == .vaultRelative(path) }
                } else {
                    // Resolve exact absolute path through the machine-local bookmark owner.
                    matching = try await controller.sourceAttachment(for: destination, target: attachmentTarget)
                }
                guard let matching else { throw DocumentAttachmentError.unavailable(destination) }
                let lease = try await controller.prepareDocumentAttachmentPreview(attachmentID: matching.record.id, for: attachmentTarget)
                guard documentAttachmentTarget == attachmentTarget else {
                    await controller.releaseDocumentAttachmentPreview(accessToken: lease.accessToken)
                    return
                }
                quickLook.present(lease) { token in await controller.releaseDocumentAttachmentPreview(accessToken: token) }
            } catch { actions.notify(ScholiumErrorLocalization.message(error), .error) }
        }
    }

    private func requestDocumentAttachment(_ mode: DocumentAttachmentSelectionMode) {
        guard let target = documentAttachmentTarget, isEditing, editorSession.isLoaded,
            editorSession.context?.composing != true
        else { return }
        let expectedDocumentID = editorSession.documentID
        Task { @MainActor in
            defer { if isEditing { editorSession.focusPreferred() } }
            var prepared: PreparedSourceAttachment?
            do {
                guard
                    let preparation = try await controller.selectDocumentAttachment(
                        mode, for: target, session: documentSession, presenter: fileSelectionPresenter)
                else { return }
                prepared = preparation
                guard isEditing, editorSession.documentID == expectedDocumentID,
                    documentAttachmentTarget == target
                else { throw MarkdownEditorSession.SessionError.staleRequest }
                try await editorSession.perform(.insertAttachment, argument: preparation.editorArgument)
                prepared = nil
                AccessibilityNotification.Announcement(String(localized: "Attachment link inserted.")).post()
            } catch {
                var message = ScholiumErrorLocalization.message(error)
                if let prepared {
                    do { try await controller.rollbackSourceAttachment(prepared) } catch { message += " " + ScholiumErrorLocalization.message(error) }
                }
                actions.notify(message, .error)
            }
        }
    }

    @MainActor
    private func checkIndexedImageAvailability() async {
        let source = isEditing ? editingSource : note.document.rawContent
        guard source.contains("](/") else {
            announcedUnavailableIndexedImages = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let unavailable = Set(
                try await controller.unavailableIndexedImagePaths(in: source)
            )
            guard !Task.isCancelled else { return }
            let newlyUnavailable = unavailable.subtracting(
                announcedUnavailableIndexedImages
            )
            announcedUnavailableIndexedImages = unavailable
            guard !newlyUnavailable.isEmpty else { return }
            if newlyUnavailable.count == 1, let path = newlyUnavailable.first {
                actions.notify(
                    String(localized: "Indexed attachment unavailable: \(path)"),
                    .information
                )
            } else {
                actions.notify(
                    String(localized: "\(newlyUnavailable.count) indexed attachments are unavailable."),
                    .information
                )
            }
        } catch is CancellationError {
            return
        } catch {
            // Catalog and local-access health are reported by their owning
            // workflows. A reminder check never blocks or mutates the Note.
        }
    }

    private func handleDocumentFindShortcut(_ shortcut: DocumentFindShortcut) {
        controller.performSelectedDocumentFind(
            shortcut, expectedTarget: target, expectedSession: documentSession
        )
    }

    private func requestImageImport() {
        requestImageSelection(.importFile)
    }

    private func requestImageIndex() {
        requestImageSelection(.index)
    }

    private func requestImageSelection(_ mode: ImageAttachmentSelectionMode) {
        guard isEditing,
            editorSession.isLoaded,
            editorSession.context?.composing != true,
            !isInsertingImage
        else { return }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.id.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.id.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedSourceAttachment?
            do {
                guard let fileSelectionPresenter else {
                    throw ScholiumFileSelectionError.presenterUnavailable
                }
                let request = ScholiumFileSelectionRequest(
                    title: mode == .importFile
                        ? String(localized: "Import Image")
                        : String(localized: "Index Image"),
                    message: mode == .importFile
                        ? String(localized: "Choose an image to copy into this Vault's Attachments folder.")
                        : String(localized: "Choose an image to reference at its absolute path without copying it."),
                    prompt: mode == .importFile
                        ? String(localized: "Import")
                        : String(localized: "Index"),
                    kind: .files(allowedContentTypes: [.image])
                )
                guard let sourceURL = try await fileSelectionPresenter.selectURL(request) else {
                    return
                }
                guard isEditing,
                    note.id.relativePath == expectedPath,
                    editorSession.documentID == expectedDocumentID
                else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation =
                    switch mode {
                    case .importFile:
                        try await controller.importImageAttachment(
                            at: sourceURL,
                            for: noteID
                        )
                    case .index:
                        try await controller.indexImageAttachment(
                            at: sourceURL,
                            for: noteID
                        )
                    }
                prepared = preparation
                guard isEditing,
                    note.id.relativePath == expectedPath,
                    editorSession.documentID == expectedDocumentID
                else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                try await editorSession.perform(
                    .insertImage,
                    argument: preparation.editorArgument
                )
                prepared = nil
                AccessibilityNotification.Announcement(
                    String(localized: "Image inserted.")
                ).post()
            } catch {
                var message = ScholiumErrorLocalization.message(error)
                if let prepared {
                    do {
                        try await controller.rollbackSourceAttachment(prepared)
                    } catch {
                        message +=
                            " "
                            + String(
                                localized: "Attachment cleanup needs attention: \(ScholiumErrorLocalization.message(error))"
                            )
                    }
                }
                actions.notify(message, .error)
            }
        }
    }

    private func handlePastedImage(_ source: EditorPastedImageSource) -> Bool {
        guard isEditing,
            editorSession.isLoaded,
            editorSession.context?.composing != true,
            !isInsertingImage
        else { return false }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.id.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.id.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedSourceAttachment?
            do {
                guard isEditing,
                    note.id.relativePath == expectedPath,
                    editorSession.documentID == expectedDocumentID
                else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation: PreparedSourceAttachment
                switch source {
                case .file(let url):
                    preparation = try await controller.importPastedImageAttachment(
                        at: url,
                        for: noteID
                    )
                case .data(let data, let preferredFilename):
                    preparation = try await controller.importPastedImageAttachment(
                        data: data,
                        preferredFilename: preferredFilename,
                        for: noteID
                    )
                }
                prepared = preparation
                guard isEditing,
                    note.id.relativePath == expectedPath,
                    editorSession.documentID == expectedDocumentID
                else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                try await editorSession.perform(
                    .insertImage,
                    argument: preparation.editorArgument
                )
                prepared = nil
                AccessibilityNotification.Announcement(
                    String(localized: "Image inserted.")
                ).post()
            } catch {
                var message = ScholiumErrorLocalization.message(error)
                if let prepared {
                    do {
                        try await controller.rollbackSourceAttachment(prepared)
                    } catch {
                        message +=
                            " "
                            + String(
                                localized: "Attachment cleanup needs attention: \(ScholiumErrorLocalization.message(error))"
                            )
                    }
                }
                actions.notify(message, .error)
            }
        }
        return true
    }

    private func selectPresentationMode(_ mode: NotePresentationMode) {
        guard !editorIsComposing else {
            actions.notify(
                String(
                    localized: "Finish text composition to change document mode.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        if mode == .read {
            guard isEditing else {
                documentSession.resetPresentation()
                actions.rememberPresentationMode(.read)
                return
            }
            guard !returnToReadAfterSave else { return }
            if !editorSession.isLoaded {
                do {
                    try finishEditing()
                } catch {
                    reportReviewHandoffError(error)
                }
                return
            }
            let handoffID = UUID()
            documentSession.reviewHandoffID = handoffID
            returnToReadAfterSave = true
            Task {
                defer {
                    if documentSession.reviewHandoffID == handoffID {
                        documentSession.reviewHandoffID = nil
                        returnToReadAfterSave = false
                        if controller.selectedDocument?.editingTarget == target {
                            focusEditorIfPresented()
                        }
                    }
                }
                do {
                    let handoffAnchor = try? await editorSession.currentScrollAnchor()
                    guard documentSession.reviewHandoffID == handoffID,
                        controller.selectedDocument?.editingTarget == target, !Task.isCancelled
                    else { return }
                    documentSession.adoptEditorScrollPositionForReview(anchor: handoffAnchor)
                    actions.rememberScrollPosition(
                        handoffAnchor?.fallbackFraction ?? documentSession.readScrollFraction
                    )
                    documentSession.requestReadScrollRestore(
                        fingerprint: handoffAnchor?.sourceFingerprint
                            ?? DocumentFingerprint(content: editingSource).sha256,
                        reason: .modeHandoff
                    )
                    await editorSession.resignFocusAndWait()
                    guard documentSession.reviewHandoffID == handoffID,
                        controller.selectedDocument?.editingTarget == target, !Task.isCancelled
                    else { return }
                    // Capture and save after the editor has relinquished focus:
                    // input accepted during scroll/focus work belongs in this final save.
                    try await controller.flushForExternalOperation(
                        session: documentSession,
                        target: target
                    )
                    guard documentSession.reviewHandoffID == handoffID,
                        controller.selectedDocument?.editingTarget == target, !Task.isCancelled
                    else { return }
                    let committedFingerprint = DocumentFingerprint(
                        content: documentSession.originalEditingSource
                    ).sha256
                    if documentSession.renderedReadReadyFingerprint
                        != committedFingerprint
                    {
                        // Never reveal a retained Review projection for the
                        // pre-save revision while SwiftUI publishes the newly
                        // committed Note and its hidden projection catches up.
                        documentSession.renderedReadReadyFingerprint = ""
                    }
                    try finishEditing()
                } catch is CancellationError {
                    return
                } catch {
                    guard documentSession.reviewHandoffID == handoffID else { return }
                    reportReviewHandoffError(error)
                }
            }
            return
        }

        guard editingIsAvailable else {
            actions.notify(
                String(
                    localized: "This note is read-only in Scholium.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        guard let editorMode = mode.editorMode else { return }
        documentSession.reviewHandoffID = nil
        returnToReadAfterSave = false
        editorSession.authorizeAutomaticFocus()
        if isEditing {
            documentSession.switchEditorMode(to: editorMode)
        } else {
            beginEditing(mode: editorMode)
        }
        actions.rememberPresentationMode(mode)
    }

    private func applyPreparedPresentationModeIfAvailable() {
        guard !isEditing,
            let preparedMode = documentSession.pendingEditorMode,
            editingIsAvailable
        else { return }
        beginEditing(mode: preparedMode)
    }

    private func consumePendingPresentationRequest() {
        guard let requested = state.requestedPresentationMode else { return }
        selectPresentationMode(requested)
        actions.clearRequestedPresentationMode()
    }

    private var currentSourceLocationRequest: DocumentSourceLocationRequest? {
        guard state.sourceLocationRequest?.target == target else { return nil }
        return state.sourceLocationRequest
    }

    private var sourceLocationExecutionID: UUID? {
        guard isEditing, editorSession.isLoaded, !editorSession.isComposing,
            let intendedMode = state.requestedPresentationMode?.editorMode
                ?? documentSession.activeEditorMode,
            editorSession.presentedMode == intendedMode
        else { return nil }
        return currentSourceLocationRequest?.id
    }

    private func reportChangedSourceLocation() {
        actions.notify(
            String(localized: "This reference is from a different version. The Note was opened without selecting a passage.", bundle: .module), .information)
    }

    private func consumePendingSourceLocation() async {
        guard let id = sourceLocationExecutionID, let request = currentSourceLocationRequest,
            request.id == id
        else { return }
        do {
            try await editorSession.revealSourceLocation(request)
            guard !Task.isCancelled else { return }
            actions.consumeSourceLocation(id)
        } catch {
            guard !Task.isCancelled, currentSourceLocationRequest?.id == id else { return }
            actions.consumeSourceLocation(id)
            if error is DocumentSourceLocationFailure {
                reportChangedSourceLocation()
            } else {
                actions.notify(
                    String(localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module),
                    .information)
            }
        }
    }

    private func goToFrontmatter() {
        guard editingIsAvailable, editorSession.context?.composing != true else { return }
        selectPresentationMode(.livePreview)
        editorSession.goToLine(1)
    }

    private func beginEditing(mode: MarkdownEditorMode = .livePreview) {
        controller.beginEditing(
            session: documentSession,
            target: target,
            source: note.document.rawContent,
            revision: noteFingerprint,
            mode: mode
        )
    }

    /// Focus belongs to the mode that the Web editor has acknowledged, not
    /// merely to the mode most recently requested by native UI. This keeps a
    /// retained Source surface from receiving focus during Review -> Edit and
    /// prevents rapid Edit/Source requests from racing the bridge handshake.
    private func focusEditorIfPresented() {
        guard
            DocumentEditorPresentationGate().allowsEditorFocus(
                isEditing: isEditing,
                isReturningToReview: returnToReadAfterSave,
                editorIsReady: editorSession.isLoaded,
                presentedModeMatchesIntent:
                    editorSession.presentedMode == documentSession.activeEditorMode
            )
        else { return }
        if documentSession.managedCreationBodyStartUTF16 != nil {
            documentSession.completeManagedCreationEntry()
            AccessibilityNotification.Announcement(
                documentSession.activeEditorMode == .source
                    ? String(localized: "New note created. Source is ready.")
                    : String(localized: "New note created. Edit is ready.")
            ).post()
            return
        }
        editorSession.focusPreferred()
    }

    private func retryEditor(in mode: MarkdownEditorMode) {
        guard editingIsAvailable else {
            actions.notify(
                String(
                    localized: "This note is read-only in Scholium.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        if let bodyStart = documentSession.managedCreationBodyStartUTF16 {
            editorSession.revealSourceRange(
                fromUTF16: bodyStart,
                toUTF16: bodyStart
            )
        }
        documentSession.switchEditorMode(to: mode)
        actions.rememberPresentationMode(mode.presentationMode)
        editorSession.retryUnavailablePresentation()
    }

    private func finishEditing() throws {
        try controller.finishEditing(session: documentSession, target: target)
        actions.rememberPresentationMode(.read)
    }

    private func reportReviewHandoffError(_ error: Error) {
        documentSession.editError = ScholiumErrorLocalization.message(error)
        documentSession.canRetrySave = DocumentController.saveFailureAllowsRetry(error)
        if controller.selectedDocument?.editingTarget == target {
            controller.setSaveError(ScholiumErrorLocalization.message(error))
        }
    }

    private func reloadFromDisk() {
        Task {
            do {
                try await controller.reloadFromDisk(
                    session: documentSession,
                    target: target
                )
                actions.rememberPresentationMode(.read)
            } catch { /* Controller published the recoverable error state. */  }
        }
    }

}
// MARK: - Source comparison

private struct ConflictComparisonSheet: View {
    let conflict: DocumentConflictSnapshot
    let onReturnToEditing: () -> Void
    let onReloadFromDisk: () -> Void
    @State private var isDocumentExpanded = true

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Compare Changes",
            detail: "Compare the current editor with the exact version now on disk.",
            identifier: "scholium.conflictComparison"
        ) {
            Button("Expand All") { isDocumentExpanded = true }
                .scholiumActivationPointer()
            Button("Collapse All") { isDocumentExpanded = false }
                .scholiumActivationPointer()
        } content: {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        isDocumentExpanded.toggle()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(
                                systemName: isDocumentExpanded
                                    ? "chevron.down" : "chevron.right"
                            )
                            .accessibilityHidden(true)
                            VStack(
                                alignment: .leading,
                                spacing: ScholiumGrid.Spacing.labelAccessoryGap
                            ) {
                                Text(conflict.relativePath)
                                    .font(ScholiumTypography.interface(.rowTitle))
                                    .scholiumContentControlInk(
                                        resting: .primaryText,
                                        emphasized: .accent
                                    )
                                Text("Editor and disk revisions differ")
                                    .font(ScholiumTypography.interface(.small))
                                    .scholiumForeground(.attention)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ScholiumGrid.Spacing.nestedContentInset)
                        .contentShape(Rectangle())
                    }
                    .scholiumActivationPointer()
                    .buttonStyle(.plain)
                    .scholiumContentControlPointerFeedback(
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .accessibilityLabel(conflict.relativePath)
                    .accessibilityValue(
                        isDocumentExpanded ? "Expanded" : "Collapsed"
                    )
                    .accessibilityHint(
                        isDocumentExpanded
                            ? "Collapses this document" : "Expands this document"
                    )

                    if isDocumentExpanded {
                        ScholiumStructuralRule()
                        if let comparison = try? conflict.exactComparison() {
                            ExactSourceComparisonView(
                                comparison: comparison,
                                startingLabel: "Current Editor",
                                endingLabel: "Disk Version",
                                startingOnlyLabel: "Current editor only",
                                endingOnlyLabel: "Disk version only",
                                identifierPrefix: "scholium.conflict"
                            )
                            .padding(ScholiumGrid.Spacing.nestedContentInset)
                        } else {
                            ScholiumContentStateView(
                                "Comparison Unavailable",
                                detail: Text("The exact source revisions could not be compared."),
                                indicator: .symbol("exclamationmark.triangle", role: .attention)
                            )
                            .frame(
                                minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                            )
                        }
                    }
                }
                .background(ScholiumColorRole.documentBackground.color)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                    .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
            }
        } footer: {
            HStack {
                Button("Return to Editing", action: onReturnToEditing)
                    .scholiumActivationPointer()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk", role: .destructive, action: onReloadFromDisk)
                    .scholiumActivationPointer()
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
        }
    }

}

#Preview {
    let controller = DocumentController()
    let note = WindowDocumentLocation.syntheticPreview(
        relativePath: "topics/consciousness.md",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note.",
        vaultRole: .topicKnowledge
    )
    let active = note.hydratedSnapshot!
    let state = DocumentFeatureState(
        notes: [note],
        activeNote: active,
        selectedDocumentPath: active.id.relativePath,
        ordinarySearchScope: .triptych,
        currentVaultID: active.id.vaultID,
        vaultRole: .topicKnowledge,
        noteIdentityByPath: [
            active.id.relativePath: active.stableIdentity.resolvedID
        ].compactMapValues { $0 },
        workspaceCatalog: nil,
        canEdit: false,
        documentTextScale: 1,
        appearanceCSS: "",
        readCSS: "",
        livePreviewCSS: "",
        initialScrollFraction: 0,
        requestedPresentationMode: nil,
        sourceLocationRequest: nil,
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
        consumeSourceLocation: { _ in },
        navigateToSourceLine: { _, _ in },
        rememberScrollPosition: { _ in },
        openInternalLink: { _ in },
        openExternalURL: { _ in },
        enterCSSSafeMode: { _ in },
        rememberPresentationMode: { _ in },
        setSidebarVisible: { _ in },
        setResearchInspectorVisible: { _ in },
        openingDocumentPresentationDidComplete: {},
        renameNote: { _, _, requestedTitle in requestedTitle },
        notify: { _, _ in }
    )
    NoteContentView(
        controller: controller,
        target: .unavailable(
            vaultID: active.id.vaultID,
            relativePath: active.id.relativePath
        ),
        note: active,
        documentSession: DocumentSessionModel(key: nil),
        state: state,
        actions: actions,
        hasShellNotices: false,
        shellNotices: EmptyView()
    )
}
