import ScholiumContracts
import SwiftUI

enum DocumentNotificationKind {
    case success
    case information
    case error
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
    let endDiscussion: @MainActor (UUID) async throws -> Void
    let clearRequestedDiscussion: @MainActor () -> Void
    let copyDiscussionRequest: @MainActor (String) throws -> Void
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

    /// Comments persist a fingerprint-bound line reference, not a passage
    /// anchor. Prefer the precise rendered-to-source match, but retain the
    /// safe renderer's source-block range when identical visible passages make
    /// exact quotation matching intentionally ambiguous. Research Actions
    /// continue to use `anchor` and therefore keep their stricter policy.
    static func commentLineRange(
        for selection: MarkdownReviewSelection?,
        in source: String,
        relativePath: String
    ) -> ClosedRange<Int>? {
        guard let selection,
              !selection.excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let anchor = anchor(
            for: selection,
            in: source,
            relativePath: relativePath
        ) {
            return anchor.line ... anchor.endLine
        }

        let lowerBound = min(selection.startLine, selection.endLine)
        let upperBound = max(selection.startLine, selection.endLine)
        let lineCount = source.reduce(into: 1) { count, character in
            if character.isNewline { count += 1 }
        }
        guard lowerBound >= 1,
              upperBound >= lowerBound,
              upperBound <= lineCount else { return nil }
        return lowerBound ... upperBound
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
                    target: .unavailable(
                        vaultID: note.vaultID,
                        relativePath: note.relativePath
                    ),
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
    @ObservedObject private var shellState: WindowShellState

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
    let openReference: (VaultNoteReference, Int?) -> Void
    let settle: (String?) async throws -> Void

    init(
        note: WindowDocumentLocation,
        shellState: WindowShellState,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        researchInspectorContentContext: ResearchInspectorContentContext,
        researchActionsPresentation: ResearchActionsPresentation,
        researchActionFocusRequest: ResearchActionFocusRequest?,
        registerResearchActionFocusOwner: @escaping (ResearchActionID) -> Void,
        openResearchAction: @escaping (ResearchActionID) -> Void,
        retryResearchActionCancellation: @escaping (UUID) -> Void,
        openReference: @escaping (VaultNoteReference, Int?) -> Void,
        settle: @escaping (String?) async throws -> Void
    ) {
        self.note = note
        _shellState = ObservedObject(wrappedValue: shellState)
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.researchInspectorContentContext = researchInspectorContentContext
        self.researchActionsPresentation = researchActionsPresentation
        self.researchActionFocusRequest = researchActionFocusRequest
        self.registerResearchActionFocusOwner = registerResearchActionFocusOwner
        self.openResearchAction = openResearchAction
        self.retryResearchActionCancellation = retryResearchActionCancellation
        self.openReference = openReference
        self.settle = settle
    }

    var body: some View {
        VStack(spacing: 0) {
            ScholiumInspectorModeIndex(
                selectedMode: shellState.inspector.mode,
                select: shellState.selectInspectorMode
            )

            Group {
                switch shellState.inspector.mode {
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
                openReference(reference, line)
            }
        )
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
    let end: (UUID) async throws -> Void
    let copyHandoff: (String) throws -> Void
    let onClosed: () -> Void
    let onFinished: () -> Void

    @State private var discussion: PortableResearchDiscussion?
    @State private var researcherMessage = ""
    @State private var agentName = ""
    @State private var agentReply = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmsEndDiscussion = false

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
        end: @escaping (UUID) async throws -> Void,
        copyHandoff: @escaping (String) throws -> Void,
        onClosed: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.noteTitle = noteTitle
        self.reload = reload
        self.loadAgentInstructions = loadAgentInstructions
        self.append = append
        self.finish = finish
        self.end = end
        self.copyHandoff = copyHandoff
        self.onClosed = onClosed
        self.onFinished = onFinished
        _discussion = State(initialValue: route.discussion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.discussionHeaderDetailSpacing) {
                    Text("Discussion")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    Text(noteTitle)
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                }
                Spacer()
                Button("End Discussion…", role: .destructive) {
                    confirmsEndDiscussion = true
                }
                .disabled(isWorking)
                .accessibilityIdentifier("scholium.discussion.end")
                Button("Close") {
                    onClosed()
                    dismiss()
                }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.discussion.close")
            }
            .padding(ScholiumMetrics.DocumentWorkflow.discussionHeaderInset)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
                    if let discussion {
                        transcript(discussion)
                    }

                    exchangeControls

                    if let errorMessage {
                        Text(errorMessage)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.attention)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("scholium.discussion.error")
                    }
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 640)
        .accessibilityIdentifier("scholium.discussion")
        .task(id: discussion?.updatedAt) {
            await refreshExternalDiscussionState()
        }
        .confirmationDialog(
            "End this Discussion?",
            isPresented: $confirmsEndDiscussion,
            titleVisibility: .visible
        ) {
            Button("Keep Discussion", role: .cancel) {}
            Button("End Discussion", role: .destructive, action: endExchange)
        } message: {
            Text("Scholium will revoke Agent access and preserve the current exchange as a finished Research Record.")
        }
    }

    @ViewBuilder
    private var exchangeControls: some View {
        if discussion?.awaitsAgentReply == true {
            agentHandoffControls
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("AGENT REPLY")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .tracking(0.7)
                    .scholiumForeground(.secondaryText)
                TextField("Agent name", text: $agentName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Agent name")
                    .accessibilityIdentifier("scholium.discussion.agentName")
                TextEditor(text: $agentReply)
                    .font(ScholiumTypography.scholarly(.body))
                    .frame(minHeight: 110)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialTextEditorCornerRadius
                        )
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: ScholiumMetrics.DocumentWorkflow.discussionActionMinimumSpacing)
                Button("Finish", action: finishExchange)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking)
                    .accessibilityIdentifier("scholium.discussion.finish")
            }
        }
    }

    private func transcript(_ discussion: PortableResearchDiscussion) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("EXCHANGE")
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .tracking(0.7)
                .scholiumForeground(.secondaryText)
            ForEach(discussion.statements) { statement in
                VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.discussionTurnDetailSpacing) {
                    Text(statement.attribution)
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                    if let reference = statement.lineReference {
                        Text(
                            reference.line == reference.endLine
                                ? "COMMENT AT LINE \(reference.line)"
                                : "COMMENT AT LINES \(reference.line)–\(reference.endLine)"
                        )
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .tracking(0.6)
                        .scholiumForeground(.secondaryText)
                        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                    } else if let passage = statement.passage {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.discussionTurnDetailSpacing) {
                            Text(
                                passage.line == passage.endLine
                                    ? "PASSAGE AT LINE \(passage.line)"
                                    : "PASSAGE AT LINES \(passage.line)–\(passage.endLine)"
                            )
                            .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            .tracking(0.6)
                            .scholiumForeground(.secondaryText)
                            if passage.state == .needsReattachment {
                                Label(
                                    "This passage no longer has one reliable location.",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.attention)
                                .accessibilityIdentifier(
                                    "scholium.discussion.statementPassage.needsReattachment"
                                )
                            }
                        }
                        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                    }
                    Text(statement.text)
                        .font(ScholiumTypography.scholarly(.body))
                        .lineSpacing(ScholiumMetrics.DocumentWorkflow.discussionTurnLineSpacing)
                        .textSelection(.enabled)
                }
                .padding(.vertical, ScholiumMetrics.DocumentWorkflow.discussionTurnVerticalInset)
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
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(title)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .tracking(0.7)
                .scholiumForeground(.secondaryText)
            TextEditor(text: $researcherMessage)
                .font(ScholiumTypography.scholarly(.body))
                .frame(minHeight: 100)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialTextEditorCornerRadius
                    )
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
        VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.discussionControlSpacing) {
            Button("Copy Handoff") {
                prepareAgentHandoff()
            }
            .buttonStyle(.bordered)
            .disabled(isWorking || discussion == nil)
            .accessibilityIdentifier("scholium.discussion.copyHandoff")
            Text("The Discussion is waiting for an Agent reply. Copying a new handoff replaces its prior pairing; closing this sheet leaves it active.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prepareAgentHandoff() {
        guard let discussion else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            let instructions: String
            do {
                instructions = try await loadAgentInstructions(discussion.id)
            } catch {
                errorMessage = "Scholium could not create a new Agent handoff. \(error.localizedDescription)"
                isWorking = false
                return
            }
            do {
                try copyHandoff(instructions)
            } catch {
                errorMessage = "Scholium could not copy the Agent handoff. \(error.localizedDescription)"
            }
            isWorking = false
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
                do {
                    let instructions = try await loadAgentInstructions(updated.id)
                    do {
                        try copyHandoff(instructions)
                    } catch {
                        errorMessage = "The Discussion was saved, but Scholium could not copy the Agent handoff. \(error.localizedDescription)"
                    }
                } catch {
                    errorMessage = "The Discussion was saved, but Scholium could not create a new Agent handoff. \(error.localizedDescription)"
                }
                isWorking = false
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

    private func endExchange() {
        guard let discussion else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await end(discussion.id)
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
        nonmutating set { documentSession.showConflictComparison = newValue }
    }
    private var editorSession: MarkdownEditorSession { documentSession.editorSession }

    var body: some View {
        AnyView(VStack(spacing: 0) {
            if let ambiguity = state.identityAmbiguity {
                IdentityAmbiguityNotice(ambiguity: ambiguity) {
                    actions.requestIdentityResolution()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            } else if let pending = state.pendingIdentityRebinding {
                IdentityMigrationNotice(
                    rebinding: pending,
                    message: state.identityMigrationFailureMessage,
                    isRetrying: state.isResolvingIdentity
                ) {
                    await actions.retryIdentityRecovery()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
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
        .overlay(alignment: .bottom) {
            if let presentation = documentIntegrityPresentation {
                ScholiumDocumentStatusToast(
                    presentation.title,
                    detail: presentation.detail,
                    kind: presentation.kind
                ) {
                    documentIntegrityActions(presentation)
                }
                .accessibilityIdentifier(presentation.accessibilityIdentifier)
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.bottom, ScholiumGrid.Spacing.sectionSeparation)
            }
        }
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
                end: actions.endDiscussion,
                copyHandoff: actions.copyDiscussionRequest,
                onClosed: actions.clearRequestedDiscussion,
                onFinished: actions.clearRequestedDiscussion
            )
        }
        .task(id: documentIntegrityPresentation) {
            guard let presentation = documentIntegrityPresentation else { return }
            AccessibilityNotification.Announcement(presentation.announcement).post()
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
        .onAppear {
            controller.observe(documentSession)
            applyPreparedPresentationModeIfAvailable()
            consumePendingPresentationRequest()
            openRequestedDiscussion(state.requestedDiscussionID)
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
            focusEditorIfPresented()
            if !isEditing,
               documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256 {
                PerformanceProbe.shared.markReadReady(documentID: note.relativePath)
            }
        }
        .onChange(of: editorSession.presentedMode) { _, _ in
            focusEditorIfPresented()
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded else { return }
            consumePendingSourceLocation()
        }
        .task(id: readProjectionTaskIdentity) {
            failedReadFingerprint = nil
            documentSession.renderedReadReadyFingerprint = ""
            let source = note.rawContent
            let relativePath = note.relativePath
            let fingerprint = noteFingerprint
            if !isEditing {
                documentSession.readSelection = nil
                documentSession.requestScrollRestore(
                    fingerprint: fingerprint.sha256,
                    reason: .documentLoad
                )
            }
            if source.isEmpty {
                // Exact empty Markdown is already a complete Review state. Do
                // not start WebKit merely to render an empty body or imply that
                // source loading is still in progress.
                renderedReadHTML = ""
                renderedReadFingerprint = fingerprint.sha256
                documentSession.renderedReadReadyFingerprint = fingerprint.sha256
                if !isEditing {
                    PerformanceProbe.shared.markReadReady(documentID: relativePath)
                }
                return
            }
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
                .controlSize(.small)
            }
        case .conflict:
            Button("Compare Changes") {
                showConflictComparison = true
            }
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var readProjectionTaskIdentity: String {
        "\(note.relativePath):\(noteFingerprint.sha256)"
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
        return "\(state.currentVaultID?.uuidString ?? "unavailable"):\(noteFingerprint.sha256):\(generation):\(presentationMode.rawValue):\(hasUnsavedChanges)"
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
                && editorSession.presentedMode == documentSession.activeEditorMode
        ) {
            readSurface
        } editor: {
            bodyEditor
        }
        .scholiumSurface(.document)
    }

    @ViewBuilder
    private var readSurface: some View {
        if note.rawContent.isEmpty {
            emptyReviewState
        } else {
            let hasWebProjection = renderedReadFingerprint == noteFingerprint.sha256
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
    }

    private var emptyReviewState: some View {
        ScholiumContentStateView(
            "Empty Note",
            detail: Text("This note has no content."),
            indicator: .symbol("doc")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.emptyNoteReview")
    }

    @ViewBuilder
    private var readProjectionPlaceholder: some View {
        if failedReadFingerprint == noteFingerprint.sha256 {
            ScholiumContentStateView(
                "Review Mode Unavailable",
                detail: Text("Use Source mode while the rendered document is unavailable."),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            )
        } else {
            ScholiumContentStateView(
                "Loading Document…",
                indicator: .progress
            )
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
            linkPreviewRevision: readLinkPreviewRevision,
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
            selectionSurfaceIsActive: !isEditing,
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
                    PerformanceProbe.shared.markReadReady(documentID: note.relativePath)
                }
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
                guard !isEditing else { return }
                documentSession.observeScrollFraction($0)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: {
                guard !isEditing else { return }
                documentSession.observeScrollAnchor($0)
            },
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
        if let retained = editorSession.retainedScrollAnchor {
            return retained
        }
        let fingerprint = DocumentFingerprint(content: editorSession.checkedSource).sha256
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
        [
            noteFingerprint.sha256,
            String(state.documentTextScale.bitPattern),
            String(state.appearanceCSS.hashValue),
            String(state.readCSS.hashValue),
        ].joined(separator: ":")
    }

    private var readLinkPreviewRevision: String {
        let previewRevision = documentSession.previewCatalog.map { catalog in
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
                documentSession.resetPresentation()
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
                    let committedFingerprint = DocumentFingerprint(
                        content: documentSession.originalEditingSource
                    ).sha256
                    if documentSession.renderedReadReadyFingerprint
                        != committedFingerprint {
                        // Never reveal a retained Review projection for the
                        // pre-save revision while SwiftUI publishes the newly
                        // committed Note and its hidden projection catches up.
                        documentSession.renderedReadReadyFingerprint = ""
                    }
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
        guard let editorMode = mode.editorMode else { return }
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
              editingIsAvailable else { return }
        beginEditing(mode: preparedMode)
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

    private func beginEditing(mode: MarkdownEditorMode = .livePreview) {
        controller.beginEditing(
            session: documentSession,
            target: target,
            source: note.rawContent,
            revision: state.documentRevisions[note.relativePath],
            mode: mode
        )
    }

    /// Focus belongs to the mode that the Web editor has acknowledged, not
    /// merely to the mode most recently requested by native UI. This keeps a
    /// retained Source surface from receiving focus during Review -> Edit and
    /// prevents rapid Edit/Source requests from racing the bridge handshake.
    private func focusEditorIfPresented() {
        guard isEditing,
              editorSession.isLoaded,
              editorSession.presentedMode == documentSession.activeEditorMode else { return }
        editorSession.focus()
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
    @State private var isDocumentExpanded = true

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Compare Changes",
            detail: "Compare the current editor with the exact version now on disk.",
            identifier: "scholium.conflictComparison"
        ) {
            Button("Expand All") { isDocumentExpanded = true }
            Button("Collapse All") { isDocumentExpanded = false }
        } content: {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        isDocumentExpanded.toggle()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: isDocumentExpanded
                                ? "chevron.down" : "chevron.right")
                                .accessibilityHidden(true)
                            VStack(
                                alignment: .leading,
                                spacing: ScholiumGrid.Spacing.labelAccessoryGap
                            ) {
                                Text(conflict.relativePath)
                                    .font(ScholiumTypography.interface(.rowTitle))
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
                    .buttonStyle(.plain)
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
                .clipShape(RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                ))
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
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk", role: .destructive, action: onReloadFromDisk)
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
        }
    }

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
        VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.conflictDispositionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.conflictDispositionDetailSpacing) {
                    Text(finding.title)
                        .font(ScholiumTypography.interface(.sectionTitle))
                    Text(finding.judgment.rawValue)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
                Spacer(minLength: ScholiumMetrics.DocumentWorkflow.conflictActionMinimumSpacing)
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let existing {
                    Text("Saved as \(existing.decision.interfaceTitle)")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
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
        .padding(.vertical, ScholiumMetrics.DocumentWorkflow.conflictRowVerticalInset)
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

// MARK: - Preview

#Preview {
    let controller = DocumentController()
    let note = WindowDocumentLocation.syntheticPreview(
        relativePath: "topics/consciousness.md",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note.",
        vaultRole: .topicKnowledge
    )
    let state = DocumentFeatureState(
        notes: [note],
        selectedDocumentPath: note.relativePath,
        ordinarySearchScope: .triptych,
        currentVaultID: note.workspaceSnapshot?.id.vaultID,
        vaultRole: .topicKnowledge,
        locationScope: .workspace,
        noteIdentityByPath: [
            note.relativePath: note.workspaceSnapshot?.stableIdentity.resolvedID,
        ].compactMapValues { $0 },
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
        endDiscussion: { _ in throw CancellationError() },
        clearRequestedDiscussion: {},
        copyDiscussionRequest: { _ in },
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
        target: .unavailable(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        ),
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
