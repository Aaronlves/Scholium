import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

enum DocumentNotificationKind {
    case confirmation
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

struct PassageCommentSubmission: Equatable, Sendable {
    let requestID: String
    let documentID: String
    let fingerprint: DocumentFingerprint
    let startLine: Int
    let endLine: Int
    let commentedText: String
    let text: String
}

struct PassageCommentResolution: Equatable, Sendable {
    let requestID: String
    let succeeded: Bool
}

struct ReviewCommentAnchor: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let discussionID: UUID
    let statementID: UUID
    let startLine: Int
    let endLine: Int
    let commentCount: Int
}

enum ReviewCommentAnchorProjection {
    static func anchors(
        for noteID: UUID,
        fingerprint: DocumentFingerprint,
        in discussions: [PortableResearchDiscussion]
    ) -> [ReviewCommentAnchor] {
        var groups: [ReviewCommentAnchorKey: ReviewCommentAnchorGroup] = [:]
        for discussion in discussions where discussion.primaryNoteID == noteID {
            for statement in discussion.statements {
                guard statement.author == .researcher,
                      statement.kind == .discussionTurn,
                      let reference = statement.lineReference,
                      reference.fingerprint == fingerprint else { continue }
                let key = ReviewCommentAnchorKey(
                    discussionID: discussion.id,
                    startLine: reference.line,
                    endLine: reference.endLine
                )
                if var group = groups[key] {
                    group.count += 1
                    if statement.createdAt >= group.latestCreatedAt {
                        group.latestStatementID = statement.id
                        group.latestCreatedAt = statement.createdAt
                    }
                    groups[key] = group
                } else {
                    groups[key] = ReviewCommentAnchorGroup(
                        latestStatementID: statement.id,
                        latestCreatedAt: statement.createdAt,
                        count: 1
                    )
                }
            }
        }
        return groups.map { key, group in
            ReviewCommentAnchor(
                id: "\(key.discussionID.uuidString.lowercased())-\(key.startLine)-\(key.endLine)",
                discussionID: key.discussionID,
                statementID: group.latestStatementID,
                startLine: key.startLine,
                endLine: key.endLine,
                commentCount: group.count
            )
        }.sorted {
            if $0.startLine != $1.startLine { return $0.startLine < $1.startLine }
            if $0.endLine != $1.endLine { return $0.endLine < $1.endLine }
            return $0.id < $1.id
        }
    }
}

struct DocumentFeatureState {
    let notes: [WindowDocumentLocation]
    let selectedDocumentPath: String?
    let ordinarySearchScope: SearchPresentationScope
    let currentVaultID: UUID?
    let vaultRole: VaultRole
    let noteIdentityByPath: [String: UUID]
    let documentRevisions: [String: DocumentFingerprint]
    let workspaceCatalog: WorkspaceCatalogSnapshot?
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
    let noteReviewState: WorkspaceNoteReviewState?
    let researchRecordSourceManifestHash: String
    let researchRecordProjectionIsComplete: Bool
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
    let viewAgentChanges: @MainActor () -> Void
    let reloadNoteReviewState: @MainActor () async throws -> Void
    let markCurrentNoteReviewed: @MainActor (
        UUID,
        DocumentFingerprint,
        String
    ) async throws -> Void
    let openingDocumentPresentationDidComplete: @MainActor () -> Void
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
}

enum ResearchActionSelectionCapture {
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
    let openResearchAction: (ResearchActionItemPresentation) -> Void
    let endResearchActivity: (UUID) -> Void
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
        openResearchAction: @escaping (ResearchActionItemPresentation) -> Void,
        endResearchActivity: @escaping (UUID) -> Void,
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
        self.endResearchActivity = endResearchActivity
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
                        endActivity: endResearchActivity,
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
/// place; a current-revision Review anchor can reopen this route at its turn.
private struct DiscussionRoute: Identifiable {
    let id: UUID
    let discussion: PortableResearchDiscussion
    let focusedStatementID: UUID?

    init(
        discussion: PortableResearchDiscussion,
        focusedStatementID: UUID? = nil
    ) {
        id = discussion.id
        self.discussion = discussion
        self.focusedStatementID = focusedStatementID
    }
}

private struct ReviewCommentAnchorKey: Hashable {
    let discussionID: UUID
    let startLine: Int
    let endLine: Int
}

private struct ReviewCommentAnchorGroup {
    var latestStatementID: UUID
    var latestCreatedAt: Date
    var count: Int
}

private struct DiscussionPanel: View {
    @Environment(\.dismiss) private var dismiss

    let noteTitle: String
    let reload: (UUID) async throws -> PortableResearchDiscussion?
    let loadAgentInstructions: (UUID) async throws -> String
    let end: (UUID) async throws -> Void
    let copyHandoff: (String) throws -> Void
    let currentNoteFingerprint: DocumentFingerprint
    let revealCommentLine: (Int) -> Void
    let onClosed: () -> Void
    let onFinished: () -> Void

    @State private var discussion: PortableResearchDiscussion?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmsEndDiscussion = false
    private let focusedStatementID: UUID?

    init(
        noteTitle: String,
        route: DiscussionRoute,
        reload: @escaping (UUID) async throws -> PortableResearchDiscussion?,
        loadAgentInstructions: @escaping (UUID) async throws -> String,
        end: @escaping (UUID) async throws -> Void,
        copyHandoff: @escaping (String) throws -> Void,
        currentNoteFingerprint: DocumentFingerprint,
        revealCommentLine: @escaping (Int) -> Void,
        onClosed: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        self.noteTitle = noteTitle
        self.reload = reload
        self.loadAgentInstructions = loadAgentInstructions
        self.end = end
        self.copyHandoff = copyHandoff
        self.currentNoteFingerprint = currentNoteFingerprint
        self.revealCommentLine = revealCommentLine
        self.onClosed = onClosed
        self.onFinished = onFinished
        focusedStatementID = route.focusedStatementID
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.regionContentInset) {
                        if let discussion {
                            transcript(discussion)
                        }

                        agentHandoffControls

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
                .task(id: focusedStatementID) {
                    guard let focusedStatementID else { return }
                    await Task.yield()
                    proxy.scrollTo(focusedStatementID, anchor: .center)
                }
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

    private func transcript(_ discussion: PortableResearchDiscussion) -> some View {
        return VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
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
                        commentLocator(reference)
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
                .padding(.leading, focusedStatementID == statement.id ? 8 : 0)
                .overlay(alignment: .leading) {
                    if focusedStatementID == statement.id {
                        Rectangle()
                            .fill(ScholiumColorRole.accent.color)
                            .frame(width: 2)
                            .accessibilityHidden(true)
                    }
                }
                .id(statement.id)
                if statement.id != discussion.statements.last?.id {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func commentLocator(_ reference: ResearchLineReference) -> some View {
        let lines = reference.line == reference.endLine
            ? String(localized: "Comment at line \(reference.line)")
            : String(localized: "Comment at lines \(reference.line)–\(reference.endLine)")
        if reference.fingerprint == currentNoteFingerprint {
            Button {
                revealCommentLine(reference.line)
                onClosed()
                dismiss()
            } label: {
                Label(lines, systemImage: "text.bubble")
            }
            .buttonStyle(.borderless)
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .accessibilityHint("Returns to the comment's current Note location")
            .accessibilityIdentifier("scholium.discussion.commentLocator.current")
            .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        } else {
            Label {
                Text("Earlier revision · \(lines)")
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .scholiumForeground(.secondaryText)
            .help("The Note changed after this Comment. Scholium does not guess a new location.")
            .accessibilityHint("The current Note changed, so this location cannot be opened")
            .accessibilityIdentifier("scholium.discussion.commentLocator.stale")
            .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
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
            Text("The Discussion is waiting for one Agent reply. A successful reply forms its Research Record automatically and clears these Comments from Review. Closing this sheet leaves it active.")
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

}

struct NoteContentView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
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
    @State private var isMarkingNoteReviewed = false
    @State private var noteReviewError: String?
    @State private var noteReviewRequiresReload = false
    @StateObject private var documentFind = DocumentFindPresentationModel()
    @StateObject private var reviewDocumentStatistics = ReviewDocumentStatisticsModel()
    @State private var isInsertingImage = false
    @State private var announcedUnavailableIndexedImages: Set<String> = []
    @State private var indexedImageAvailabilityGeneration = 0

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

            if documentFind.isPresented {
                DocumentFindBar(
                    model: documentFind,
                    allowsReplacement: isEditing
                )
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
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }

            documentBodySurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            DocumentStatisticsStatus(statistics: currentDocumentStatistics)
        }
        .scholiumSurface(.document)
        .overlay(alignment: .top) {
            if documentSession.noteReviewTaskPresentation.isPresented(
                for: state.noteReviewState?.noteID
            ),
               state.noteReviewState?.status == .needsReview {
                noteReviewTaskBanner
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                    .zIndex(10)
            }
        }
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
                allowsReplace: isEditing,
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
                startComment: requestCommentFromDocument,
                presentFind: documentFind.present,
                findNext: documentFind.next,
                findPrevious: documentFind.previous,
                useSelectionForFind: useSelectionForDocumentFind,
                announceDocumentStatistics: announceDocumentStatistics,
                importImage: requestImageImport,
                indexImage: requestImageIndex
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
                end: actions.endDiscussion,
                copyHandoff: actions.copyDiscussionRequest,
                currentNoteFingerprint: noteFingerprint,
                revealCommentLine: revealDiscussionComment,
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
            documentSession.reconcileNoteReviewTask(
                with: state.noteReviewState
            )
            applyPreparedPresentationModeIfAvailable()
            consumePendingPresentationRequest()
            openRequestedDiscussion(state.requestedDiscussionID)
            updateReviewDocumentStatistics(selection: nil)
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
            updateReviewDocumentStatistics(selection: nil)
            documentFind.refresh()
            focusEditorIfPresented()
            if !isEditing,
               documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256 {
                markReadPresentationReady(documentID: note.relativePath)
            }
        }
        .onChange(of: editorSession.presentedMode) { _, presentedMode in
            focusEditorIfPresented()
            if let presentedMode {
                PerformanceProbe.shared.markEditorModeAcknowledged(
                    documentID: note.relativePath,
                    mode: presentedMode
                )
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: note.relativePath,
                    mode: presentedMode
                )
            }
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded else { return }
            consumePendingSourceLocation()
            focusEditorIfPresented()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            indexedImageAvailabilityGeneration &+= 1
        }
        .onChange(of: state.noteReviewState) { _, reviewState in
            documentSession.reconcileNoteReviewTask(with: reviewState)
        }
        .task(id: noteReviewTaskAnnouncementIdentity) {
            guard noteReviewTaskAnnouncementIdentity != nil else { return }
            AccessibilityNotification.Announcement(
                String(localized: "Review Current Note")
            ).post()
        }
        .task(id: readProjectionTaskIdentity) {
            PerformanceProbe.shared.markReadTaskStarted(
                documentID: note.relativePath
            )
            documentSession.prepareReadProjection(
                for: noteFingerprint.sha256
            )
            updateReviewDocumentStatistics(selection: nil)
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
            let html = await controller.readProjectionHTML(
                target: target,
                relativePath: relativePath,
                source: source,
                fingerprint: fingerprint,
                workspaceID: state.currentVaultID,
                semantic: note.workspaceSnapshot?.cachedSemanticDocument
            )
            guard !Task.isCancelled, fingerprint == noteFingerprint else { return }
            PerformanceProbe.shared.markReadHTMLReady(documentID: relativePath)
            renderedReadHTML = html
            renderedReadFingerprint = fingerprint.sha256
        }
        .task(id: indexedImageAvailabilityTaskIdentity) {
            await checkIndexedImageAvailability()
        }
        .task(id: discussionProjectionPollIdentity) {
            await pollPortableDiscussionProjection()
        }
        .task(id: previewTaskIdentity) {
            await rebuildPreviewCatalog()
        }
        .task(id: documentFind.request) {
            guard let request = documentFind.request else { return }
            if case .clear = request.operation {
                editorSession.clearDocumentFind()
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
    }

    private var noteReviewTaskBanner: some View {
        let shape = RoundedRectangle(
            cornerRadius: ScholiumShape.inlineStatusCornerRadius,
            style: .continuous
        )
        return VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                Label("Review Current Note", systemImage: "checkmark.circle")
                    .font(ScholiumTypography.interface(.sectionTitle))
                Spacer(minLength: 0)
                Button {
                    documentSession.dismissNoteReviewTask(
                        for: state.noteReviewState
                    )
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .disabled(isMarkingNoteReviewed)
                .accessibilityLabel("Close Note Review")
            }
            Text("Inspect all currently pending Agent activities for this Note, then explicitly mark the current saved source reviewed.")
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = noteReviewBlockingReason {
                Text(reason)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let noteReviewError {
                Text(noteReviewError)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .textSelection(.enabled)
            }
            if noteReviewRequiresReload {
                Button("Reload Review State") {
                    reloadNoteReviewState()
                }
                .disabled(isMarkingNoteReviewed)
                .accessibilityIdentifier("scholium.noteReview.reload")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    noteReviewControls
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    noteReviewControls
                }
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        .scholiumContentFittingWidth(
            maximumWidth: ScholiumMetrics.ActivityNotificationStack.maximumWidth
        )
        .scholiumEditorialSurface(.floatingControl, in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.noteReview.task")
    }

    private var noteReviewTaskAnnouncementIdentity: String? {
        guard documentSession.noteReviewTaskPresentation.isPresented(
            for: state.noteReviewState?.noteID
        ) else { return nil }
        return documentSession.noteReviewTaskPresentation.presentedIdentity?
            .activityIDs.joined(separator: ":")
    }

    @ViewBuilder
    private var noteReviewControls: some View {
        Button("View Changes…") {
            actions.viewAgentChanges()
        }
        .accessibilityHint("Opens this Note's Research Records without changing Review state")
        .disabled(isMarkingNoteReviewed)
        .accessibilityIdentifier("scholium.noteReview.viewChanges")
        Button("Mark Current Note Reviewed") {
            markCurrentNoteReviewed()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            noteReviewBlockingReason != nil
                || noteReviewRequiresReload
                || isMarkingNoteReviewed
        )
        .accessibilityHint(
            "Covers every currently observed pending Agent activity for this exact saved Note revision"
        )
        .accessibilityIdentifier("scholium.noteReview.mark")
        if isMarkingNoteReviewed {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Marking current Note reviewed")
        }
    }

    private var noteReviewBlockingReason: String? {
        guard state.researchRecordProjectionIsComplete,
              !state.researchRecordSourceManifestHash.isEmpty else {
            return String(localized: "Research Records are not currently complete. Reload before reviewing this Note.")
        }
        guard state.identityAmbiguity == nil,
              state.pendingIdentityRebinding == nil,
              let reviewState = state.noteReviewState,
              let currentRevision = reviewState.currentRevision,
              note.workspaceSnapshot?.stableIdentity.resolvedID == reviewState.noteID else {
            return String(localized: "This Note's stable identity is not currently available for Review.")
        }
        if documentSession.hasUnsavedChanges || isSavingEdit {
            return String(localized: "Save the current editor changes before marking this Note reviewed.")
        }
        if conflict != nil {
            return String(localized: "Resolve the external source conflict before marking this Note reviewed.")
        }
        if editError != nil {
            return String(localized: "Resolve the current save status before marking this Note reviewed.")
        }
        if note.document.fingerprint != currentRevision {
            return String(localized: "The saved Note changed. Reload the current Review state before continuing.")
        }
        return nil
    }

    private func markCurrentNoteReviewed() {
        guard noteReviewBlockingReason == nil,
              !isMarkingNoteReviewed,
              let reviewState = state.noteReviewState,
              let revision = reviewState.currentRevision else { return }
        isMarkingNoteReviewed = true
        noteReviewError = nil
        noteReviewRequiresReload = false
        Task { @MainActor in
            defer { isMarkingNoteReviewed = false }
            do {
                try await actions.markCurrentNoteReviewed(
                    reviewState.noteID,
                    revision,
                    state.researchRecordSourceManifestHash
                )
                documentSession.completeNoteReviewTask()
                AccessibilityNotification.Announcement(
                    String(localized: "Current Note marked reviewed")
                ).post()
                actions.notify(
                    String(localized: "Current Note marked reviewed"),
                    .confirmation
                )
            } catch {
                noteReviewError = error.localizedDescription
                if let applicationError = error as? ScholiumApplicationError,
                   applicationError.mutationRequiresReconciliation {
                    noteReviewRequiresReload = true
                } else if let mutationError = error as?
                    PortableResearchNoteReviewMutationError {
                    switch mutationError {
                    case .sourceChanged, .recordProjectionChanged:
                        noteReviewRequiresReload = true
                    case .sourceUnavailable, .noPendingAgentChanges:
                        break
                    }
                }
            }
        }
    }

    private func reloadNoteReviewState() {
        guard !isMarkingNoteReviewed else { return }
        isMarkingNoteReviewed = true
        noteReviewError = nil
        Task { @MainActor in
            defer { isMarkingNoteReviewed = false }
            do {
                try await actions.reloadNoteReviewState()
                noteReviewRequiresReload = false
            } catch {
                noteReviewError = error.localizedDescription
            }
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

    private var reviewCommentAnchors: [ReviewCommentAnchor] {
        guard let noteID = state.noteIdentityByPath[note.relativePath] else { return [] }
        return ReviewCommentAnchorProjection.anchors(
            for: noteID,
            fingerprint: noteFingerprint,
            in: state.activeDiscussions
        )
    }

    private var reviewCommentAnchorRevision: String {
        reviewCommentAnchors.map {
            "\($0.id):\($0.statementID.uuidString.lowercased()):\($0.commentCount)"
        }.joined(separator: "|")
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
            performanceDocumentID: note.relativePath,
            source: editingSource,
            mode: documentSession.retainedEditorMode,
            presentationCSS: documentPresentationCSS,
            userCSS: state.livePreviewCSS,
            requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(
                source: editingSource,
                linkPreviews: documentSession.previewCatalog?.links ?? []
            ),
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
            onRequestFind: handleDocumentFindShortcut,
            onRequestImportImage: requestImageImport,
            onRequestIndexImage: requestImageIndex,
            onPasteImage: handlePastedImage,
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
        .id(editorSession.viewReconstructionID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1))
    }

    @ViewBuilder
    private var documentBodySurface: some View {
        DocumentEditorHost(
            presentsEditor: isEditing,
            retainsEditor: documentSession.retainsEditorSurface,
            editorIsReady: editorSession.isLoaded
                && editorSession.presentedMode == documentSession.activeEditorMode,
            allowsPendingReadRecovery: documentSession.isEnteringManagedCreation
                && editorSession.errorMessage != nil
        ) {
            readSurface
        } editor: {
            bodyEditor
        }
        .scholiumSurface(.document)
        .overlay(alignment: .topLeading) {
            if isEditing,
               editorSession.isLoaded,
               let presentedMode = editorSession.presentedMode,
               presentedMode == documentSession.activeEditorMode {
                PerformanceReadyBoundary(
                    generation: "\(noteFingerprint.sha256):\(presentedMode.rawValue)"
                ) {
                    PerformanceProbe.shared.markEditorModeVisible(
                        documentID: note.relativePath,
                        mode: presentedMode
                    )
                    PerformanceProbe.shared.markEditorVisible(
                        documentID: note.relativePath
                    )
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            if !isEditing,
               (note.document.hasExactEmptyBody
                || documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256) {
                PerformanceReadyBoundary(
                    generation: "read:\(noteFingerprint.sha256)"
                ) {
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var readSurface: some View {
        if documentSession.isEnteringManagedCreation {
            if let error = editorSession.errorMessage {
                managedCreationEditorFailure(error)
            } else {
                // Managed creation never flashes Review or Empty Note while
                // the exact editor waits for its typed mode acknowledgement.
                Color.clear
                    .accessibilityHidden(true)
            }
        } else if note.document.hasExactEmptyBody {
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
            detail: Text("This note has no body content."),
            indicator: .symbol("doc")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.emptyNoteReview")
    }

    private func managedCreationEditorFailure(_ error: String) -> some View {
        ScholiumContentStateView(
            "Edit Unavailable",
            detail: Text("The note was created and its exact source is saved. \(error)"),
            indicator: .symbol("exclamationmark.triangle", role: .attention)
        ) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button("Retry Edit") {
                    retryManagedCreationEditor(in: .livePreview)
                }
                .keyboardShortcut(.defaultAction)
                Button("Source") {
                    retryManagedCreationEditor(in: .source)
                }
            }
        }
        .accessibilityIdentifier("scholium.managedNewNote.editorFailure")
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
            commentAnchors: reviewCommentAnchors,
            commentAnchorRevision: reviewCommentAnchorRevision,
            onOpenCommentAnchor: openCommentAnchor,
            onSelectionChange: { selection in
                guard !isEditing else { return }
                documentSession.readSelection = selection
                updateReviewDocumentStatistics(selection: selection)
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
                    markReadPresentationReady(documentID: note.relativePath)
                }
            },
            findRequest: documentFind.request,
            onFindResult: { requestID, result in
                switch result {
                case .success(let value):
                    documentFind.accept(value, for: requestID)
                case .failure(let error):
                    documentFind.fail(error, for: requestID)
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

    private func markReadPresentationReady(documentID: String) {
        PerformanceProbe.shared.markReadReady(documentID: documentID)
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
        _ kind: EditorLinkCompletionKind,
        _ query: String
    ) async -> [EditorLinkCompletion] {
        guard let currentVaultID = state.currentVaultID,
              let catalogNotes = state.workspaceCatalog?.notes,
              let generation = state.workspaceCatalog?.graph?.generation else {
            return []
        }
        return await controller.editorLinkCompletions(
            kind: kind,
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

    private var currentDocumentStatistics: DocumentStatistics {
        isEditing
            ? editorSession.documentStatistics
            : reviewDocumentStatistics.value
    }

    private var indexedImageAvailabilityTaskIdentity: String {
        "\(note.relativePath):\(noteFingerprint.sha256):\(indexedImageAvailabilityGeneration)"
    }

    @MainActor
    private func checkIndexedImageAvailability() async {
        let source = isEditing ? editingSource : note.rawContent
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

    private func updateReviewDocumentStatistics(
        selection: MarkdownReviewSelection?
    ) {
        reviewDocumentStatistics.update(
            markdownSource: note.rawContent,
            revision: noteFingerprint.sha256,
            selection: selection
        )
    }

    private func announceDocumentStatistics() {
        AccessibilityNotification.Announcement(
            DocumentStatisticsFormatter.accessibilityValue(currentDocumentStatistics)
        ).post()
    }

    private func handleDocumentFindShortcut(_ shortcut: DocumentFindShortcut) {
        switch shortcut {
        case .present:
            documentFind.present()
        case .next:
            documentFind.next()
        case .previous:
            documentFind.previous()
        case .useSelection:
            useSelectionForDocumentFind()
        }
    }

    private func useSelectionForDocumentFind() {
        if isEditing {
            Task { @MainActor in
                let selection = try? await editorSession.currentSelection(
                    for: editorSession.documentID,
                    in: editingSource
                )
                documentFind.useSelection(selection?.excerpt)
            }
        } else {
            documentFind.useSelection(documentSession.readSelection?.excerpt)
        }
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
              !isInsertingImage else { return }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedImageAttachment?
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
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation = switch mode {
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
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
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
                var message = error.localizedDescription
                if let prepared {
                    do {
                        try await controller.rollbackImageAttachment(prepared)
                    } catch {
                        message += " " + String(
                            localized: "Attachment cleanup needs attention: \(error.localizedDescription)"
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
              !isInsertingImage else { return false }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedImageAttachment?
            do {
                guard isEditing,
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation: PreparedImageAttachment
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
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
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
                var message = error.localizedDescription
                if let prepared {
                    do {
                        try await controller.rollbackImageAttachment(prepared)
                    } catch {
                        message += " " + String(
                            localized: "Attachment cleanup needs attention: \(error.localizedDescription)"
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
                    guard returnToReadAfterSave else { return }
                    await editorSession.resignFocusAndWait()
                    guard returnToReadAfterSave else { return }
                    finishEditing()
                } catch { /* Controller published the recoverable error state. */ }
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
        guard DocumentEditorPresentationGate().allowsEditorFocus(
            isEditing: isEditing,
            isReturningToReview: returnToReadAfterSave,
            editorIsReady: editorSession.isLoaded,
            presentedModeMatchesIntent:
                editorSession.presentedMode == documentSession.activeEditorMode
        ) else { return }
        if documentSession.managedCreationBodyStartUTF16 != nil {
            documentSession.completeManagedCreationEntry()
            AccessibilityNotification.Announcement(
                documentSession.activeEditorMode == .source
                    ? String(localized: "New note created. Source is ready.")
                    : String(localized: "New note created. Edit is ready.")
            ).post()
            return
        }
        editorSession.focus()
    }

    private func retryManagedCreationEditor(in mode: MarkdownEditorMode) {
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
            actions.notify(
                String(
                    localized: "Select a passage before commenting.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
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
                    endLine: submission.endLine,
                    commentedText: submission.commentedText
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
                    String(
                        localized: "The Comment was saved. Research views will refresh when the workspace is available.",
                        table: "Localizable",
                        bundle: .module
                    ),
                    .information
                )
            } catch {
                commentResolution = PassageCommentResolution(
                    requestID: submission.requestID,
                    succeeded: false
                )
                actions.notify(
                    String(
                        localized: "Scholium could not save this Comment. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
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
                        String(
                            localized: "The requested Discussion is no longer active.",
                            table: "Localizable",
                            bundle: .module
                        ),
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
                    String(
                        localized: "Scholium could not open this Discussion. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    .error
                )
                actions.clearRequestedDiscussion()
            }
        }
    }

    private func openCommentAnchor(_ anchor: ReviewCommentAnchor) {
        Task { @MainActor in
            do {
                guard let discussion = try await actions.reloadDiscussion(anchor.discussionID),
                      discussion.statements.contains(where: { $0.id == anchor.statementID }) else {
                    actions.notify(
                        String(
                            localized: "This Comment is no longer in an active Discussion.",
                            table: "Localizable",
                            bundle: .module
                        ),
                        .information
                    )
                    return
                }
                discussionRoute = DiscussionRoute(
                    discussion: discussion,
                    focusedStatementID: anchor.statementID
                )
            } catch {
                actions.notify(
                    String(
                        localized: "Scholium could not open this Comment. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    .error
                )
            }
        }
    }

    private func revealDiscussionComment(_ line: Int) {
        guard line > 0 else { return }
        actions.setPendingSourceLine(line)
        if presentationMode != .read {
            selectPresentationMode(.read)
        }
    }

    private func openResearchAction(_ actionID: ResearchActionID) {
        guard !editorIsComposing else {
            actions.notify(
                String(
                    localized: "Finish text composition to open a Research Action.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        guard isEditing else {
            let selection = documentSession.readSelection
            let anchor = ResearchActionSelectionCapture.anchor(
                for: selection,
                in: note.rawContent,
                relativePath: note.relativePath
            )
            if selection != nil, anchor == nil {
                actions.notify(
                    String(
                        localized: "Scholium could not match the selected passage reliably. The Action will open for the whole note.",
                        table: "Localizable",
                        bundle: .module
                    ),
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
                let anchor = ResearchActionSelectionCapture.anchor(
                    for: selection,
                    in: currentSource,
                    relativePath: note.relativePath
                )
                actions.openResearchAction(actionID, anchor)
            } catch {
                actions.notify(
                    String(
                        localized: "Scholium could not capture the current selection. The Action will open for the whole note. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
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
        noteIdentityByPath: [
            note.relativePath: note.workspaceSnapshot?.stableIdentity.resolvedID,
        ].compactMapValues { $0 },
        documentRevisions: [note.relativePath: note.document.fingerprint],
        workspaceCatalog: nil,
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
        isResolvingIdentity: false,
        noteReviewState: nil,
        researchRecordSourceManifestHash: "",
        researchRecordProjectionIsComplete: false
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
        viewAgentChanges: {},
        reloadNoteReviewState: {},
        markCurrentNoteReviewed: { _, _, _ in },
        openingDocumentPresentationDidComplete: {},
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
