import ScholiumContracts
import SwiftUI

enum DocumentNotificationKind {
    case success
    case information
    case error
}

struct PassageCommentSubmission: Equatable, Sendable {
    let requestID: String
    let documentID: String
    let fingerprint: DocumentFingerprint
    let startLine: Int
    let endLine: Int
    let text: String
}

struct PassageCommentResolution: Equatable, Sendable {
    let requestID: String
    let succeeded: Bool
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
    let activeDiscussions: [PortableResearchDiscussion]
    let requestedDiscussionID: UUID?
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
    let pendingSourceRange: SearchSourceRange?
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
    let clearPendingSourceRange: @MainActor () -> Void
    /// A passage Comment starts the same Discussion used by whole-note work.
    let createDiscussion: @MainActor (
        CommentAnchor,
        String
    ) async throws -> PortableResearchDiscussion
    let createComment: @MainActor (
        UUID,
        String,
        ResearchLineReference,
        String
    ) async throws -> PortableResearchDiscussion
    let reloadDiscussion: @MainActor (UUID) async throws -> PortableResearchDiscussion?
    let loadDiscussionAgentInstructions: @MainActor (UUID) async throws -> String
    let refreshDiscussionProjection: @MainActor () async throws -> Void
    let appendDiscussionStatement: @MainActor (
        UUID,
        PortableResearchStatementAuthor,
        String,
        String
    ) async throws -> PortableResearchDiscussion
    let finishDiscussion: @MainActor (UUID) async throws -> PortableResearchRecord
    let clearRequestedDiscussion: @MainActor () -> Void
    let handoffDiscussionRequest: @MainActor (String) -> Bool
    let copyDiscussionRequest: @MainActor (String) -> Bool
    let rememberScrollPosition: @MainActor (Double) -> Void
    let openInternalLink: @MainActor (String) -> Void
    let openExternalURL: @MainActor (URL) -> Void
    let enterCSSSafeMode: @MainActor (String) -> Void
    let rememberPresentationMode: @MainActor (NotePresentationMode) -> Void
    let setPendingSourceLine: @MainActor (Int?) -> Void
    let setSidebarVisible: @MainActor (Bool) -> Void
    let editProperties: @MainActor () -> Void
    let openResearchAction: @MainActor (
        ResearchActionID,
        CommentAnchor?
    ) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
}

enum ResearchFunctionSelectionCapture {
    static func anchor(
        for selection: MarkdownReviewSelection?,
        in source: String,
        relativePath: String
    ) -> CommentAnchor? {
        guard let selection else { return nil }
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        if let exactRange = selection.exactUTF16Range {
            return CommentAnchorBuilder.anchor(
                in: source,
                fingerprint: document.fingerprint,
                utf16Range: exactRange,
                selectedText: selection.excerpt
            )
        }
        return CommentAnchorBuilder.anchor(
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
    let researchActionsPresentation: ResearchActionsPresentation
    let researchActionFocusRequest: ResearchActionFocusRequest?
    let registerResearchActionFocusOwner: (ResearchActionID) -> Void
    let openResearchAction: (ResearchActionID) -> Void
    let retryResearchActionCancellation: (UUID) -> Void
    let settle: (String?) async throws -> Void

    init(
        note: WindowDocumentLocation,
        controller: ResearchController,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        researchActionsPresentation: ResearchActionsPresentation,
        researchActionFocusRequest: ResearchActionFocusRequest?,
        registerResearchActionFocusOwner: @escaping (ResearchActionID) -> Void,
        openResearchAction: @escaping (ResearchActionID) -> Void,
        retryResearchActionCancellation: @escaping (UUID) -> Void,
        settle: @escaping (String?) async throws -> Void
    ) {
        self.note = note
        self.controller = controller
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.researchInspectorContentContext = researchInspectorContentContext
        self.researchActionsPresentation = researchActionsPresentation
        self.researchActionFocusRequest = researchActionFocusRequest
        self.registerResearchActionFocusOwner = registerResearchActionFocusOwner
        self.openResearchAction = openResearchAction
        self.retryResearchActionCancellation = retryResearchActionCancellation
        self.settle = settle
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
                case .connect:
                    ConnectionsInspectorView(context: relationshipContext)
                case .actions:
                    ResearchActionsInspectorView(
                        presentation: researchActionsPresentation,
                        freshness: researchInspectorContentContext.freshness,
                        focusRequest: researchActionFocusRequest,
                        registerFocusOwner: registerResearchActionFocusOwner,
                        select: openResearchAction,
                        retryRefresh: researchInspectorContentContext.retryRefresh,
                        retryCancellationRecovery: retryResearchActionCancellation,
                        settle: settle
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

            HStack(spacing: ScholiumMetrics.Apparatus.modeColumnSpacing) {
                ForEach(ResearchInspectorMode.allCases) { mode in
                    InspectorModeButton(
                        mode: mode,
                        isSelected: controller.inspector.mode == mode,
                        focusedMode: $focusedMode,
                        select: { selectMode(mode) },
                        move: { moveFocus(from: mode, direction: $0) }
                    )
                    .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
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
                .font(
                    isSelected
                        ? ScholiumInterfaceTypography.apparatusModeSelected
                        : ScholiumInterfaceTypography.apparatusMode
                )
                .lineLimit(1)
                .minimumScaleFactor(0.9)
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

/// Opens one already-active Discussion. Lightweight Comments are created in
/// place and never use this route; Discuss collects them here when requested.
private struct DiscussionRoute: Identifiable {
    let id: UUID
    let discussion: PortableResearchDiscussion

    init(discussion: PortableResearchDiscussion) {
        id = discussion.id
        self.discussion = discussion
    }
}

private struct DiscussionPanel: View {
    @Environment(\.dismiss) private var dismiss

    let noteTitle: String
    let reload: (UUID) async throws -> PortableResearchDiscussion?
    let loadAgentInstructions: (UUID) async throws -> String
    let append: (
        UUID,
        PortableResearchStatementAuthor,
        String,
        String
    ) async throws -> PortableResearchDiscussion
    let finish: (UUID) async throws -> PortableResearchRecord
    let handoff: (String) -> Bool
    let copyOnly: (String) -> Bool
    let onClosed: () -> Void
    let onFinished: () -> Void

    @State private var discussion: PortableResearchDiscussion?
    @State private var researcherMessage = ""
    @State private var agentName = ""
    @State private var agentReply = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var agentInstructions: String?

    init(
        noteTitle: String,
        route: DiscussionRoute,
        reload: @escaping (UUID) async throws -> PortableResearchDiscussion?,
        loadAgentInstructions: @escaping (UUID) async throws -> String,
        append: @escaping (
            UUID,
            PortableResearchStatementAuthor,
            String,
            String
        ) async throws -> PortableResearchDiscussion,
        finish: @escaping (UUID) async throws -> PortableResearchRecord,
        handoff: @escaping (String) -> Bool,
        copyOnly: @escaping (String) -> Bool,
        onClosed: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.noteTitle = noteTitle
        self.reload = reload
        self.loadAgentInstructions = loadAgentInstructions
        self.append = append
        self.finish = finish
        self.handoff = handoff
        self.copyOnly = copyOnly
        self.onClosed = onClosed
        self.onFinished = onFinished
        _discussion = State(initialValue: route.discussion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discussion")
                        .font(.title3.weight(.semibold))
                    Text(noteTitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    onClosed()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.discussion.close")
            }
            .padding(18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let discussion {
                        transcript(discussion)
                    }

                    exchangeControls

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.attention.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("scholium.discussion.error")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
        .accessibilityIdentifier("scholium.discussion")
        .task(id: discussion?.updatedAt) {
            await refreshExternalDiscussionState()
        }
        .task(id: discussion?.id) {
            await loadResolvedAgentInstructions()
        }
    }

    @ViewBuilder
    private var exchangeControls: some View {
        if discussion?.awaitsAgentReply == true {
            agentHandoffControls
            VStack(alignment: .leading, spacing: 8) {
                Text("AGENT REPLY")
                    .font(ScholiumInterfaceTypography.apparatusLabel)
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                TextField("Agent name", text: $agentName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Agent name")
                    .accessibilityIdentifier("scholium.discussion.agentName")
                TextEditor(text: $agentReply)
                    .font(.body)
                    .frame(minHeight: 110)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                    }
                    .accessibilityLabel("Agent reply")
                    .accessibilityIdentifier("scholium.discussion.agentReply")
                HStack {
                    Spacer()
                    Button("Record Agent Reply", action: recordAgentReply)
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            isWorking
                                || normalized(agentName).isEmpty
                                || normalized(agentReply).isEmpty
                        )
                        .accessibilityIdentifier("scholium.discussion.recordAgentReply")
                }
            }

        } else {
            researcherComposer(
                title: "FOLLOW UP",
                buttonTitle: "Save and Copy Follow-up",
                action: beginOrFollowUp
            )
            HStack {
                Text("Review the reply. Finish creates one Research Record; Follow Up keeps this Discussion active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Finish", action: finishExchange)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                    .accessibilityIdentifier("scholium.discussion.finish")
            }
        }
    }

    private func transcript(_ discussion: PortableResearchDiscussion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXCHANGE")
                .font(ScholiumInterfaceTypography.apparatusLabel)
                .tracking(0.7)
                .foregroundStyle(.secondary)
            ForEach(discussion.statements) { statement in
                VStack(alignment: .leading, spacing: 3) {
                    Text(statement.attribution)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let reference = statement.lineReference {
                        Text(
                            reference.line == reference.endLine
                                ? "COMMENT AT LINE \(reference.line)"
                                : "COMMENT AT LINES \(reference.line)–\(reference.endLine)"
                        )
                        .font(ScholiumInterfaceTypography.apparatusLabel)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    } else if let passage = statement.passage {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                passage.line == passage.endLine
                                    ? "PASSAGE AT LINE \(passage.line)"
                                    : "PASSAGE AT LINES \(passage.line)–\(passage.endLine)"
                            )
                            .font(ScholiumInterfaceTypography.apparatusLabel)
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                            if passage.state == .needsReattachment {
                                Label(
                                    "This passage no longer has one reliable location.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(ScholiumColorRole.attention.color)
                                .accessibilityIdentifier(
                                    "scholium.discussion.statementPassage.needsReattachment"
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Text(statement.text)
                        .font(.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 3)
                if statement.id != discussion.statements.last?.id {
                    Divider()
                }
            }
        }
    }

    private func researcherComposer(
        title: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(ScholiumInterfaceTypography.apparatusLabel)
                .tracking(0.7)
                .foregroundStyle(.secondary)
            TextEditor(text: $researcherMessage)
                .font(.body)
                .frame(minHeight: 100)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                }
                .accessibilityLabel(title.capitalized)
                .accessibilityIdentifier("scholium.discussion.researcherMessage")
            HStack {
                Spacer()
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .disabled(isWorking || normalized(researcherMessage).isEmpty)
                    .accessibilityIdentifier("scholium.discussion.submitResearcherTurn")
            }
        }
    }

    private var agentHandoffControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button("Copy and Open Agent App…") {
                    guard let agentInstructions else { return }
                    if !handoff(agentInstructions) {
                        errorMessage = "Scholium could not prepare the agent handoff."
                    }
                }
                .buttonStyle(.bordered)
                .disabled(agentInstructions == nil)
                Button("Copy Only") {
                    guard let agentInstructions else { return }
                    if !copyOnly(agentInstructions) {
                        errorMessage = "Scholium could not copy the agent request."
                    }
                }
                .buttonStyle(.link)
                .disabled(agentInstructions == nil)
            }
            Text("The Discussion is waiting for an agent reply. Closing this sheet leaves it active.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func beginOrFollowUp() {
        let message = normalized(researcherMessage)
        guard !message.isEmpty, let discussion else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let updated = try await append(
                    discussion.id,
                    .researcher,
                    "Researcher",
                    message
                )
                self.discussion = updated
                researcherMessage = ""
                isWorking = false
                guard let agentInstructions else {
                    errorMessage = "The Discussion was saved, but its resolved Discuss Method is unavailable."
                    return
                }
                if !copyOnly(agentInstructions) {
                    errorMessage = "The Discussion was saved, but Scholium could not copy the agent handoff."
                }
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func recordAgentReply() {
        guard let discussion else { return }
        let attribution = normalized(agentName)
        let reply = normalized(agentReply)
        guard !attribution.isEmpty, !reply.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                self.discussion = try await append(
                    discussion.id,
                    .agent,
                    attribution,
                    reply
                )
                agentName = ""
                agentReply = ""
                isWorking = false
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    private func finishExchange() {
        guard let discussion else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                _ = try await finish(discussion.id)
                isWorking = false
                onFinished()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

    @MainActor
    private func refreshExternalDiscussionState() async {
        guard var current = discussion else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
                guard let refreshed = try await reload(current.id) else {
                    onFinished()
                    dismiss()
                    return
                }
                guard refreshed != current else { continue }
                discussion = refreshed
                current = refreshed
            } catch is CancellationError {
                return
            } catch {
                // A cooperating external process may be between its atomic
                // replace and coordinated readback. Keep the visible durable
                // state and retry quietly while this sheet remains active.
            }
        }
    }

    private func loadResolvedAgentInstructions() async {
        guard let discussion,
              discussion.action != nil,
              discussion.method != nil else {
            agentInstructions = nil
            return
        }
        do {
            agentInstructions = try await loadAgentInstructions(discussion.id)
        } catch {
            agentInstructions = nil
            errorMessage = "The resolved Discuss Method is unavailable. \(error.localizedDescription)"
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NoteContentView: View {
    @ObservedObject private var controller: DocumentController
    @ObservedObject private var documentSession: DocumentSessionModel
    let target: DocumentEditingTarget
    let note: WindowDocumentLocation
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext
    @State private var discussionRoute: DiscussionRoute?
    @State private var commentComposerRequestID: UUID?
    @State private var commentResolution: PassageCommentResolution?

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
            \.scholiumResearchActionActions,
            ScholiumFocusedResearchActionActions(open: openResearchAction)
        )
        .focusedSceneValue(
            \.scholiumEditorActions,
            ScholiumFocusedEditorActions(
                documentID: isEditing ? editorSession.documentID : note.relativePath,
                isComposing: isEditing && editorSession.context?.composing == true,
                isAvailable: { command in
                    isEditing && editorSession.context?.availableCommands.contains(command) == true
                },
                canCommentOnSelectedPassage: {
                    presentationMode == .read && documentSession.readSelection != nil
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
                startComment: requestCommentFromDocument
            )
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
        .sheet(item: $discussionRoute, onDismiss: {
            actions.clearRequestedDiscussion()
            Task { @MainActor in
                await Task.yield()
                if isEditing { editorSession.focus() }
            }
        }) { route in
            DiscussionPanel(
                noteTitle: note.title ?? note.displayName,
                route: route,
                reload: actions.reloadDiscussion,
                loadAgentInstructions: actions.loadDiscussionAgentInstructions,
                append: actions.appendDiscussionStatement,
                finish: actions.finishDiscussion,
                handoff: actions.handoffDiscussionRequest,
                copyOnly: actions.copyDiscussionRequest,
                onClosed: actions.clearRequestedDiscussion,
                onFinished: actions.clearRequestedDiscussion
            )
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
            consumePendingSourceLocation()
        }
        .onChange(of: state.pendingSourceRange) { _, range in
            if range != nil { consumePendingSourceLocation() }
        }
        .onChange(of: state.requestedDiscussionID) { _, discussionID in
            openRequestedDiscussion(discussionID)
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
            openRequestedDiscussion(state.requestedDiscussionID)
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
            guard loaded else { return }
            consumePendingSourceLocation()
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
        .task(id: discussionProjectionPollIdentity) {
            await pollPortableDiscussionProjection()
        }
        .task(id: previewTaskIdentity) {
            await rebuildPreviewCatalog()
        }
    }

    private var readProjectionTaskIdentity: String {
        "\(noteFingerprint.sha256):\(presentationMode.rawValue)"
    }

    private var discussionProjectionPollIdentity: String {
        state.activeDiscussions.map {
            "\($0.id.uuidString.lowercased()):\($0.updatedAt.timeIntervalSinceReferenceDate)"
        }.sorted().joined(separator: "|")
    }

    @MainActor
    private func pollPortableDiscussionProjection() async {
        guard !state.activeDiscussions.isEmpty else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
                try await actions.refreshDiscussionProjection()
            } catch is CancellationError {
                return
            } catch {
                // Keep the last verified projection. A later workspace event
                // or explicit reopen retries without inventing Discussion state.
                return
            }
        }
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
            linkCompletionQuery: queryEditorLinkCompletions,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
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
            onLinkActivation: { target in
                if let url = URL(string: target),
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    actions.openExternalURL(url)
                } else {
                    actions.openInternalLink(target)
                }
            },
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
                Text("Review mode is unavailable")
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
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            onLinkClick: {
                actions.openInternalLink($0)
            },
            onOpenExternalURL: actions.openExternalURL,
            onCommentSelection: commentingIsAvailable ? { selection in
                saveComment(selection)
            } : nil,
            commentComposerRequestID: commentComposerRequestID,
            commentResolution: commentResolution,
            onSelectionChange: { selection in
                guard !isEditing else { return }
                documentSession.readSelection = selection
            },
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
        consumePendingSourceLocation()
    }

    private func consumePendingSourceLocation() {
        if let range = state.pendingSourceRange {
            editorSession.revealSourceRange(
                fromUTF16: range.utf16LowerBound,
                toUTF16: range.utf16UpperBound
            )
            actions.clearPendingSourceRange()
            actions.clearPendingSourceLine()
        } else if let line = state.pendingSourceLine {
            editorSession.goToLine(line)
            actions.clearPendingSourceLine()
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

    private func requestCommentFromDocument() {
        guard commentingIsAvailable, presentationMode == .read else { return }
        guard documentSession.readSelection != nil else {
            actions.notify("Select a passage before commenting.", .information)
            return
        }
        commentComposerRequestID = UUID()
    }

    private func saveComment(_ submission: PassageCommentSubmission) {
        let text = submission.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              presentationMode == .read,
              submission.documentID == note.relativePath,
              let noteID = state.noteIdentityByPath[note.relativePath] else {
            commentResolution = PassageCommentResolution(
                requestID: submission.requestID,
                succeeded: false
            )
            return
        }
        Task { @MainActor in
            do {
                guard noteFingerprint == submission.fingerprint else {
                    throw ResearchOperationError.staleCommentRevision
                }
                let reference = try ResearchLineReference(
                    fingerprint: submission.fingerprint,
                    line: submission.startLine,
                    endLine: submission.endLine
                )
                _ = try await actions.createComment(
                    noteID,
                    submission.documentID,
                    reference,
                    text
                )
                commentResolution = PassageCommentResolution(
                    requestID: submission.requestID,
                    succeeded: true
                )
            } catch ScholiumApplicationError.operationCommittedButRefreshFailed {
                commentResolution = PassageCommentResolution(
                    requestID: submission.requestID,
                    succeeded: true
                )
                actions.notify(
                    "The Comment was saved. Research views will refresh when the workspace is available.",
                    .information
                )
            } catch {
                commentResolution = PassageCommentResolution(
                    requestID: submission.requestID,
                    succeeded: false
                )
                actions.notify(
                    "Scholium could not save this Comment. \(error.localizedDescription)",
                    .error
                )
            }
        }
    }

    private func openRequestedDiscussion(_ discussionID: UUID?) {
        guard let discussionID else { return }
        Task { @MainActor in
            do {
                guard let discussion = try await actions.reloadDiscussion(discussionID) else {
                    actions.notify(
                        "The requested Discussion is no longer active.",
                        .information
                    )
                    actions.clearRequestedDiscussion()
                    return
                }
                guard state.requestedDiscussionID == discussionID else { return }
                discussionRoute = DiscussionRoute(discussion: discussion)
            } catch {
                guard state.requestedDiscussionID == discussionID else { return }
                actions.notify(
                    "Scholium could not open this Discussion. \(error.localizedDescription)",
                    .error
                )
                actions.clearRequestedDiscussion()
            }
        }
    }

    private func openResearchAction(_ actionID: ResearchActionID) {
        guard !editorIsComposing else {
            actions.notify(
                "Finish text composition to open a Research Action.",
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
                    "Scholium could not match the selected passage reliably. The Action will open for the whole note.",
                    .information
                )
            }
            actions.openResearchAction(actionID, anchor)
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
                actions.openResearchAction(actionID, anchor)
            } catch {
                actions.notify(
                    "Scholium could not capture the current selection. The Action will open for the whole note. \(error.localizedDescription)",
                    .information
                )
                actions.openResearchAction(actionID, nil)
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

private struct CritiqueFindingDispositionRow: View {
    let finding: CritiqueFinding
    let existing: CritiqueFindingDisposition?
    let workRevisionChanged: Bool
    let save: @MainActor (
        CritiqueFindingDispositionDecision,
        String?,
        String?
    ) async throws -> Void

    @State private var decision: CritiqueFindingDispositionDecision
    @State private var rationale: String
    @State private var noTextChangeRationale: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        finding: CritiqueFinding,
        existing: CritiqueFindingDisposition?,
        workRevisionChanged: Bool,
        save: @escaping @MainActor (
            CritiqueFindingDispositionDecision,
            String?,
            String?
        ) async throws -> Void
    ) {
        self.finding = finding
        self.existing = existing
        self.workRevisionChanged = workRevisionChanged
        self.save = save
        _decision = State(initialValue: existing?.decision ?? .accept)
        _rationale = State(initialValue: existing?.rationale ?? "")
        _noTextChangeRationale = State(
            initialValue: existing?.noTextChangeRationale ?? ""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                        .font(.callout.weight(.semibold))
                    Text(finding.judgment.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Picker("Disposition", selection: $decision) {
                    Text("Accept").tag(CritiqueFindingDispositionDecision.accept)
                    Text("Reject").tag(CritiqueFindingDispositionDecision.reject)
                    Text("Rebut").tag(CritiqueFindingDispositionDecision.rebut)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 108)
            }

            TextField("Rationale (optional)", text: $rationale, axis: .vertical)
                .lineLimit(1...3)

            if decision == .accept, !workRevisionChanged {
                TextField(
                    "Why no text change is required",
                    text: $noTextChangeRationale,
                    axis: .vertical
                )
                .lineLimit(1...3)
                Text("The Work still matches the Critique target revision, so Accept requires this explanation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.attention.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let existing {
                    Text("Saved as \(existing.decision.interfaceTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(existing == nil ? "Save Disposition" : "Update Disposition") {
                    persist()
                }
                .buttonStyle(.bordered)
                .disabled(
                    isSaving
                        || (decision == .accept
                            && !workRevisionChanged
                            && noTextChangeRationale.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty)
                )
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private func persist() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await save(
                    decision,
                    normalized(rationale),
                    decision == .accept && !workRevisionChanged
                        ? normalized(noTextChangeRationale)
                        : nil
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func normalized(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

private extension CritiqueFindingDispositionDecision {
    var interfaceTitle: String {
        switch self {
        case .accept: "Accept"
        case .reject: "Reject"
        case .rebut: "Rebut"
        }
    }
}

private extension ResearchWriteScope {
    var researchRecordTitle: String {
        switch self {
        case .currentNote: "Current Note"
        case .selectedNotes: "Selected Notes"
        case .analysesAndTopics: "Analyses and Topics"
        case .entireTriptych: "Entire Triptych"
        }
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
        activeDiscussions: [],
        requestedDiscussionID: nil,
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
        pendingSourceRange: nil,
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
        clearPendingSourceRange: {},
        createDiscussion: { _, _ in throw CancellationError() },
        createComment: { _, _, _, _ in throw CancellationError() },
        reloadDiscussion: { _ in nil },
        loadDiscussionAgentInstructions: { _ in throw CancellationError() },
        refreshDiscussionProjection: {},
        appendDiscussionStatement: { _, _, _, _ in throw CancellationError() },
        finishDiscussion: { _ in throw CancellationError() },
        clearRequestedDiscussion: {},
        handoffDiscussionRequest: { _ in true },
        copyDiscussionRequest: { _ in true },
        rememberScrollPosition: { _ in },
        openInternalLink: { _ in },
        openExternalURL: { _ in },
        enterCSSSafeMode: { _ in },
        rememberPresentationMode: { _ in },
        setPendingSourceLine: { _ in },
        setSidebarVisible: { _ in },
        editProperties: {},
        openResearchAction: { _, _ in },
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
