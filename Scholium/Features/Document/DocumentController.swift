import ScholiumContracts
import Combine
import Foundation

/// Stable session identity plus the current path/title projection used by a
/// single window. Renames replace `reference` while retaining `sessionKey`.
struct WindowDocumentDescriptor: Hashable, Sendable {
    let sessionKey: DocumentSessionKey
    let reference: VaultNoteReference
}

/// The one selected document projection owned by a window. Workspace notes
/// carry stable session identity; identity-recovery notes remain explicitly
/// path-addressed until their stable identity is available again.
enum WindowSelectedDocument: Hashable, Sendable {
    case workspace(WindowDocumentDescriptor)
    case unavailable(vaultID: UUID, relativePath: String)

    var relativePath: String {
        switch self {
        case .workspace(let descriptor): descriptor.reference.relativePath
        case .unavailable(_, let relativePath): relativePath
        }
    }

    var vaultID: UUID? {
        switch self {
        case .workspace(let descriptor): descriptor.reference.vaultID
        case .unavailable(let vaultID, _): vaultID
        }
    }

    var workspaceDescriptor: WindowDocumentDescriptor? {
        guard case .workspace(let descriptor) = self else { return nil }
        return descriptor
    }

    var sessionKey: DocumentSessionKey? {
        workspaceDescriptor?.sessionKey
    }
}

/// Immutable delivery-layer address for one editor session. Workspace notes
/// follow stable identity through renames; unavailable documents retain only
/// the path required for recovery presentation.
enum DocumentEditingTarget: Hashable, Sendable {
    case workspace(DocumentSessionKey)
    case unavailable(vaultID: UUID, relativePath: String)
}

extension DocumentEditingTarget {
    var isFallback: Bool {
        if case .workspace = self { return false }
        return true
    }

    var vaultID: UUID {
        switch self {
        case .workspace(let key): key.vaultID
        case .unavailable(let vaultID, _): vaultID
        }
    }
}

extension WindowSelectedDocument {
    var editingTarget: DocumentEditingTarget {
        switch self {
        case .workspace(let descriptor): .workspace(descriptor.sessionKey)
        case .unavailable(let vaultID, let relativePath):
            .unavailable(vaultID: vaultID, relativePath: relativePath)
        }
    }
}

struct DocumentPresentationSnapshot: Equatable, Sendable {
    let documents: [String: WindowDocumentPresentationSnapshot]
}

enum DocumentMemoryPressureLevel: Sendable {
    case warning
    case critical
}

enum DocumentChromeDirtyState: Equatable, Sendable {
    case clean
    case dirty
}

enum DocumentChromeFailureState: Equatable, Sendable {
    case none
    case save
    case conflict
}

/// Equatable, low-frequency state consumed outside the document surface.
/// Exact source, cursor, selection, and undo state remain session-owned and
/// never travel through the window composition root.
struct DocumentChromeProjection: Equatable, Sendable {
    let document: WindowSelectedDocument?
    let mode: NotePresentationMode
    let dirtyState: DocumentChromeDirtyState
    let isSaving: Bool
    let failureState: DocumentChromeFailureState

    static let empty = DocumentChromeProjection(
        document: nil,
        mode: .read,
        dirtyState: .clean,
        isSaving: false,
        failureState: .none
    )
}

/// One window's tab/session reconciliation against a complete authoritative
/// Workspace generation. Only clean missing documents are removed; any
/// session with recoverable source state remains explicitly retained.
struct DocumentWorkspaceReconciliation: Equatable, Sendable {
    let removedDocuments: Set<WindowSelectedDocument>
    let retainedDeletedDocuments: Set<WindowSelectedDocument>

    static let unchanged = DocumentWorkspaceReconciliation(
        removedDocuments: [],
        retainedDeletedDocuments: []
    )
}

/// Per-window owner for the selected document and retained editor sessions. Repository writes,
/// source transactions and conflict recovery remain Application calls;
/// this controller owns only window and editor-session state.
@MainActor
final class DocumentController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void
    typealias DocumentCommitHandler = @MainActor (SaveResult) async -> Void

    @Published private(set) var selectedDocument: WindowSelectedDocument?
    @Published private(set) var chromeProjection = DocumentChromeProjection.empty
    @Published private(set) var currentPresentationMode: NotePresentationMode = .livePreview
    @Published private(set) var snapshots: [DocumentSessionKey: WorkspaceNoteSnapshot] = [:]
    @Published private(set) var editingDocumentPath: String?
    @Published private(set) var lastSaveError: String?
    @Published var sourceMutationGeneration: UInt64 = 0
    @Published var pendingSourceLine: Int?
    @Published var pendingSourceRange: SearchSourceRange?
    @Published var requestedPresentationMode: NotePresentationMode?
    @Published var noteIdentityByPath: [String: UUID] = [:]
    @Published var identityAmbiguities: [NoteIdentityAmbiguity] = []
    @Published var pendingIdentityRebindings: [NoteIdentityPendingRebinding] = []
    @Published var identityMigrationFailures: [NoteIdentityMigrationFailure] = []
    @Published var isResolvingIdentity = false
    @Published var identityResolutionError: String?

    private let sessions = DocumentSessionStore()
    private let readProjectionCache = DocumentReadProjectionCache()
    private let linkCompletionIndex = EditorLinkCompletionIndex()
    private var retainedReferences: [DocumentSessionKey: VaultNoteReference] = [:]
    /// Workspace publications are invalidations, not a second source owner.
    /// While one session is saving, retain only its latest complete snapshot
    /// and reconcile it immediately after the save releases ownership.
    private var deferredWorkspaceSnapshotsDuringSave: [
        DocumentSessionKey: WorkspaceNoteSnapshot
    ] = [:]
    private var restoredPresentationsByVault: [
        UUID: [String: WindowDocumentPresentationSnapshot]
    ] = [:]
    private var restoredUnqualifiedPresentations: [
        String: WindowDocumentPresentationSnapshot
    ] = [:]
    private var activeWorkspace: WorkspaceVaultSlot = .paperAnalysis
    private var presentationModesByWorkspace: [WorkspaceVaultSlot: NotePresentationMode]
    private struct ClosedPresentationEntry {
        let relativePath: String
        let scrollPosition: ObservedScrollPosition
        var access: UInt64
    }
    private var closedPresentations: [DocumentEditingTarget: ClosedPresentationEntry] = [:]
    private var nextClosedPresentationAccess: UInt64 = 0
    private let intentHandler: IntentHandler
    private var operations: (any DocumentUseCases)?
    private var sessionCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    private var pendingChromeRefreshes: Set<ObjectIdentifier> = []
    private var documentDidCommit: DocumentCommitHandler = { _ in }

    var retainedSessionCount: Int { sessions.retainedSessions.count }
    var closedPresentationCount: Int { closedPresentations.count }

    init(intentHandler: @escaping IntentHandler = { _ in }) {
        var initialPresentationModes: [WorkspaceVaultSlot: NotePresentationMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            initialPresentationModes[workspace] = .livePreview
        }
        presentationModesByWorkspace = initialPresentationModes
        self.intentHandler = intentHandler
    }

    var activeDocument: WindowDocumentDescriptor? {
        selectedDocument?.workspaceDescriptor
    }

    var selectedDocumentPath: String? {
        selectedDocument?.relativePath
    }

    var activeSnapshot: WorkspaceNoteSnapshot? {
        guard let key = selectedDocument?.sessionKey else { return nil }
        return snapshots[key]
    }

    /// Binds this window-local controller to capabilities selected by the one
    /// app-wide WorkspaceStore subscription. Rebinding never replaces editor
    /// sessions or another window's presentation state.
    func bind(
        to operations: any DocumentUseCases,
        snapshot: WorkspaceSnapshot? = nil,
        documentDidCommit: @escaping DocumentCommitHandler = { _ in }
    ) {
        self.operations = operations
        self.documentDidCommit = documentDidCommit
        if let snapshot { _ = receive(snapshot) }
    }

    func unbind() {
        operations = nil
        documentDidCommit = { _ in }
    }

    func workspaceSnapshots() async throws -> [WorkspaceVaultSnapshot] {
        try await requireOperations().snapshot()
    }

    func workspaceSnapshot(vaultID: UUID) async throws -> WorkspaceVaultSnapshot? {
        try await workspaceSnapshots().first(where: { $0.vault.id == vaultID })
    }

    func noteSnapshot(_ id: VaultQualifiedNoteID) async throws -> WorkspaceNoteSnapshot? {
        try await workspaceSnapshot(vaultID: id.vaultID)?.documents.first(where: {
            $0.id.relativePath == id.relativePath
        })
    }

    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) async throws -> DocumentPreviewCatalog {
        try await requireOperations().documentPreviewCatalog(
            source: source,
            sourceFingerprint: sourceFingerprint,
            graphGeneration: graphGeneration
        )
    }

    func readProjectionHTML(
        target: DocumentEditingTarget,
        relativePath: String,
        source: String,
        fingerprint: DocumentFingerprint,
        workspaceID: UUID?,
        semantic: MarkdownSemanticDocument? = nil
    ) async -> String {
        let stableTarget: String
        switch target {
        case .workspace(let key):
            stableTarget = "\(key.vaultID.uuidString.lowercased()):\(key.noteID.uuidString.lowercased())"
        case .unavailable(let vaultID, let path):
            stableTarget = "unavailable:\(vaultID.uuidString.lowercased()):\(path)"
        }
        return await readProjectionCache.html(
            for: DocumentReadProjectionKey(
                workspaceID: workspaceID,
                stableTarget: stableTarget,
                relativePath: relativePath,
                fingerprint: fingerprint
            ),
            source: source,
            semantic: semantic
        )
    }

    func editorLinkCompletions(
        kind: EditorLinkCompletionKind,
        matching query: String,
        sourcePath: String,
        currentVaultID: UUID,
        catalogNotes: [WorkspaceCatalogNote],
        graphGeneration: Int
    ) async -> [EditorLinkCompletion] {
        await linkCompletionIndex.replace(
            notes: catalogNotes,
            generation: graphGeneration
        )
        return (try? await linkCompletionIndex.query(
            kind: kind,
            query,
            sourcePath: sourcePath,
            currentVaultID: currentVaultID,
            generation: graphGeneration
        )) ?? []
    }

    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try await requireOperations().load(id)
    }

    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try await requireOperations().importImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    func rollbackImageAttachment(
        _ preparation: PreparedImageAttachment
    ) async throws {
        try await requireOperations().rollbackImageAttachment(preparation)
    }

    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try await requireOperations().indexImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try await requireOperations().importPastedImageAttachment(
            at: sourceURL,
            for: note
        )
    }

    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedImageAttachment {
        try await requireOperations().importPastedImageAttachment(
            data: data,
            preferredFilename: preferredFilename,
            for: note
        )
    }

    func unavailableIndexedImagePaths(
        in markdownSource: String
    ) async throws -> [String] {
        try await requireOperations().unavailableIndexedImagePaths(
            in: markdownSource
        )
    }

    func save(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<SaveResult> {
        try await requireOperations().save(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
    }

    func saveMetadata(
        _ id: VaultQualifiedNoteID,
        fields: [String: YAMLValue],
        expectedRevision: DocumentFingerprint?
    ) async throws -> WorkspaceMutationOutcome<NoteMetadataSnapshot> {
        try await requireOperations().saveMetadata(
            id,
            fields: fields,
            expectedRevision: expectedRevision
        )
    }

    func metadata(
        _ id: VaultQualifiedNoteID
    ) async throws -> NoteMetadataSnapshot? {
        try await requireOperations().metadata(id)
    }

    func commit(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try await requireOperations().commit(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> {
        try await requireOperations().resolveIdentity(ambiguity, candidateID: candidateID)
    }

    func session(for descriptor: WindowDocumentDescriptor) -> DocumentSessionModel {
        session(for: descriptor.sessionKey)
    }

    func session(for key: DocumentSessionKey) -> DocumentSessionModel {
        let session = sessions.session(for: .workspace(key))
        observe(session)
        return session
    }

    func session(for target: DocumentEditingTarget) -> DocumentSessionModel {
        let session = sessions.session(for: target)
        observe(session)
        if session.key == nil {
            hydratePresentation(of: session, target: target, path: relativePath(for: target))
        }
        return session
    }

    func retainedSession(for key: DocumentSessionKey) -> DocumentSessionModel? {
        guard let session = sessions.retainedSession(for: .workspace(key)) else { return nil }
        observe(session)
        return session
    }

    /// Observes a session only to publish an equatable chrome projection. The
    /// controller never forwards the session's broad objectWillChange stream.
    func observe(_ session: DocumentSessionModel) {
        let identifier = ObjectIdentifier(session)
        guard sessionCancellables[identifier] == nil else { return }
        sessionCancellables[identifier] = session.objectWillChange.sink { [weak self, weak session] in
            guard let self, let session,
                  pendingChromeRefreshes.insert(identifier).inserted else { return }
            Task { @MainActor [weak self, weak session] in
                await Task.yield()
                guard let self else { return }
                self.pendingChromeRefreshes.remove(identifier)
                guard let session else { return }
                self.refreshChromeProjection(ifOwnedBy: session)
            }
        }
    }

    /// Installs a document after the owning WindowModel has resolved an
    /// `openDocument` intent through Application and obtained its stable ID.
    func installOpenedDocument(
        _ descriptor: WindowDocumentDescriptor
    ) {
        selectDocument(.workspace(descriptor))
    }

    func selectDocument(_ document: WindowSelectedDocument) {
        let selectionChanged = selectedDocument != document
        if selectionChanged {
            selectedDocument = document
        }
        switch document {
        case .workspace(let descriptor):
            retainedReferences[descriptor.sessionKey] = descriptor.reference
            let selectedSession = session(for: descriptor.sessionKey)
            hydratePresentation(
                of: selectedSession,
                target: .workspace(descriptor.sessionKey),
                path: descriptor.reference.relativePath
            )
            if selectionChanged {
                selectedSession.prepareForDocumentActivation()
            }
            applyCurrentPresentationMode(
                to: selectedSession,
                target: .workspace(descriptor.sessionKey)
            )
        case .unavailable:
            let selectedSession = session(for: document.editingTarget)
            // Identity-unavailable Notes remain readable but cannot inherit a
            // writable Edit/Source intent until their stable identity resolves.
            selectedSession.preparePresentationMode(.read)
        }
        refreshChromeProjection()
    }

    func selectUnavailableDocument(vaultID: UUID, relativePath: String) {
        selectDocument(.unavailable(vaultID: vaultID, relativePath: relativePath))
    }

    /// Clears a selection only when its authoritative document was removed.
    /// Ordinary navigation never uses this as a presentation command.
    func clearSelection(forRemovedPaths removedPaths: Set<String>) {
        guard let selectedDocumentPath, removedPaths.contains(selectedDocumentPath) else {
            return
        }
        selectedDocument = nil
        refreshChromeProjection()
    }

    /// Leaves the Document region in its no-note state after the researcher
    /// closes the last content tab. Retained sessions remain window-local so a
    /// later reopen can preserve the existing exact-source safety boundary.
    func clearSelectionAfterClosingLastTab() {
        selectedDocument = nil
        refreshChromeProjection()
    }

    /// Reconciles the full editor-session leases from the authoritative tab
    /// membership in one step. Acquisition precedes release inside the store,
    /// so switching tabs can never transiently reap the destination session.
    func reconcileSessionLeases(
        leasedDocuments: [WindowSelectedDocument],
        selectedDocument: WindowSelectedDocument?
    ) {
        let reaped = sessions.reconcileLeases(
            openTargets: leasedDocuments.map(\.editingTarget),
            foregroundTarget: selectedDocument?.editingTarget
        )
        cacheReapedPresentations(reaped)
        pruneReapedSessionBookkeeping()
    }

    /// Flushes every session that is still reachable from a tab or protected
    /// by a safety pin. Ordering is stable to make close/quit diagnostics and
    /// tests deterministic.
    func flushLeasedOrPinnedSessions(
        capturingEditorState: Bool = true
    ) async throws {
        var candidatesByTarget = Dictionary(
            uniqueKeysWithValues: sessions.leasedOrPinnedSessions.map {
                ($0.0, $0.1)
            }
        )
        // Selection is an independent ownership fact. During tab projection
        // reconstruction it can briefly precede lease reconciliation, but it
        // must still participate in every navigation, command, and window
        // flush. Otherwise newly accepted WebKit input can be skipped merely
        // because the tab lease publication is one main-actor turn behind.
        if let selectedDocument,
           let selectedSession = sessions.retainedSession(
            for: selectedDocument.editingTarget
           ) {
            candidatesByTarget[selectedDocument.editingTarget] = selectedSession
        }
        let candidates = candidatesByTarget.sorted {
            relativePath(for: $0.0) < relativePath(for: $1.0)
        }
        for (target, session) in candidates {
            if capturingEditorState,
               session.editorSession.hasAttachedWebView {
                try await session.editorSession.captureStateForViewReconstruction()
            }
            // An attached CodeMirror surface can contain input whose bridge
            // delta is still queued on the main actor. Never use the Swift
            // mirror's clean bit to skip that authoritative buffer. The save
            // path retrieves the complete text and returns cheaply when it is
            // genuinely unchanged. Detached sessions can use their retained
            // mirror because no newer WebKit state exists.
            guard session.isEditing && session.editorSession.hasAttachedWebView
                    || session.hasUnsavedChanges
                    || session.isSavingEdit
                    || session.canRetrySave else {
                continue
            }
            try await flushForExternalOperation(session: session, target: target)
        }
    }

    /// A tab close is a document-specific safety transaction. Inactive tabs
    /// cannot rely on the currently selected view's registration.
    func flushBeforeClosing(_ document: WindowSelectedDocument) async throws {
        guard let session = sessions.retainedSession(for: document.editingTarget) else { return }
        if session.editorSession.hasAttachedWebView {
            try await session.editorSession.captureStateForViewReconstruction()
        }
        guard session.isEditing && session.editorSession.hasAttachedWebView
                || session.hasUnsavedChanges
                || session.isSavingEdit
                || session.canRetrySave else { return }
        try await flushForExternalOperation(session: session, target: document.editingTarget)
    }

    func reapDetachedSessions() {
        cacheReapedPresentations(sessions.reapEligibleSessions())
        pruneReapedSessionBookkeeping()
    }

    /// Installs the immutable Application read model and initializes this
    /// window's editor session from its exact source bytes.
    func installOpenedDocument(
        _ snapshot: WorkspaceNoteSnapshot,
        vaultName: String,
        vaultRole: VaultRole,
        managedCreationBodyStartUTF16: Int? = nil
    ) {
        guard let stableID = snapshot.stableIdentity.resolvedID else { return }
        let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: stableID)
        let descriptor = WindowDocumentDescriptor(
            sessionKey: key,
            reference: VaultNoteReference(
                vaultID: snapshot.id.vaultID,
                vaultName: vaultName,
                vaultRole: vaultRole,
                relativePath: snapshot.id.relativePath,
                stableNoteID: stableID.uuidString
            )
        )
        if let bodyStart = managedCreationBodyStartUTF16 {
            // Publish the new identity, exact source, Edit selection, and
            // writable session as one MainActor transaction. SwiftUI therefore
            // never mounts an intermediate Review state for managed creation.
            requestedPresentationMode = nil
            pendingSourceRange = nil
            pendingSourceLine = nil
            snapshots[key] = snapshot
            retainedReferences[key] = descriptor.reference
            let selectedSession = session(for: key)
            reconcile(session: selectedSession, with: snapshot)
            presentationModesByWorkspace[activeWorkspace] = .livePreview
            currentPresentationMode = .livePreview
            selectedSession.beginManagedCreationEntry(
                bodyStartUTF16: bodyStart
            )
            selectedSession.editorSession.revealSourceRange(
                fromUTF16: bodyStart,
                toUTF16: bodyStart
            )
            beginEditing(
                session: selectedSession,
                target: .workspace(key),
                source: snapshot.document.rawContent,
                revision: snapshot.fingerprint,
                mode: .livePreview
            )
            installOpenedDocument(descriptor)
        } else {
            snapshots[key] = snapshot
            let selectedSession = session(for: key)
            reconcile(session: selectedSession, with: snapshot)
            installOpenedDocument(descriptor)
        }
    }

    /// Publishes an authoritative commit into an already retained document
    /// session without changing this window's selection. The active save path
    /// remains responsible for synchronizing CodeMirror's exact buffer.
    func recordCommittedSnapshot(
        _ snapshot: WorkspaceNoteSnapshot,
        vaultName: String,
        vaultRole: VaultRole
    ) {
        guard let stableID = snapshot.stableIdentity.resolvedID else { return }
        let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: stableID)
        snapshots[key] = snapshot
        let reference = VaultNoteReference(
            vaultID: snapshot.id.vaultID,
            vaultName: vaultName,
            vaultRole: vaultRole,
            relativePath: snapshot.id.relativePath,
            stableNoteID: stableID.uuidString
        )
        retainedReferences[key] = reference
        guard activeDocument?.sessionKey == key else { return }
        updateDocumentProjection(WindowDocumentDescriptor(
            sessionKey: key,
            reference: reference
        ))
        reconcile(session: session(for: key), with: snapshot)
    }

    /// Updates mutable path and title projections without replacing the
    /// document session, editor buffer, undo bridge, or conflict state.
    func updateDocumentProjection(_ descriptor: WindowDocumentDescriptor) {
        let previousPath = retainedReferences[descriptor.sessionKey]?.relativePath
            ?? snapshots[descriptor.sessionKey]?.id.relativePath
        retainedReferences[descriptor.sessionKey] = descriptor.reference
        guard selectedDocument?.sessionKey == descriptor.sessionKey else { return }
        selectedDocument = .workspace(descriptor)
        guard previousPath != nil,
              previousPath != descriptor.reference.relativePath else { return }

        let session = session(for: descriptor.sessionKey)
        editingDocumentPath = session.isEditing
            ? descriptor.reference.relativePath
            : editingDocumentPath

        // A filesystem rename can race an autosave already addressed to the
        // previous path. Stable identity has now proved the destination, so a
        // dirty retained buffer must retry there instead of leaving a stale
        // file-missing alert over the still-valid editor session.
        guard session.isEditing, session.hasUnsavedChanges else { return }
        session.cancelAutosave()
        session.autosaveTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            if let activeSaveTask = session.activeSaveTask {
                let supersededToken = session.activeSaveToken
                _ = try? await activeSaveTask.value
                // `saveEditingSource` normally clears this slot after its
                // task completes. A rename retry can resume first on the main
                // actor, however, and must not accidentally reuse the
                // completed old-path task as the destination save. The token
                // check prevents clearing any newer save.
                if let supersededToken {
                    _ = self.finishSaveAttempt(
                        token: supersededToken,
                        session: session
                    )
                }
            }
            guard !Task.isCancelled,
                  session.conflict == nil,
                  self.relativePath(for: .workspace(descriptor.sessionKey))
                    == descriptor.reference.relativePath,
                  session.hasUnsavedChanges else { return }
            session.editError = nil
            session.canRetrySave = false
            self.setSaveError(nil)
            await self.persistEditingSource(
                session: session,
                target: .workspace(descriptor.sessionKey)
            )
        }
    }

    func rememberPresentationMode(_ mode: NotePresentationMode) {
        guard currentPresentationMode != mode else { return }
        presentationModesByWorkspace[activeWorkspace] = mode
        currentPresentationMode = mode
        refreshChromeProjection()
    }

    func presentationMode(for workspace: WorkspaceVaultSlot) -> NotePresentationMode {
        presentationModesByWorkspace[workspace] ?? .livePreview
    }

    func selectWorkspace(_ workspace: WorkspaceVaultSlot) {
        activeWorkspace = workspace
        let mode = presentationMode(for: workspace)
        if currentPresentationMode != mode {
            currentPresentationMode = mode
        }
        refreshChromeProjection()
    }

    func restorePresentationModes(
        _ modesByWorkspace: [WorkspaceVaultSlot: NotePresentationMode]
    ) {
        var restoredPresentationModes: [WorkspaceVaultSlot: NotePresentationMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            restoredPresentationModes[workspace] = modesByWorkspace[workspace] ?? .livePreview
        }
        presentationModesByWorkspace = restoredPresentationModes
        currentPresentationMode = presentationMode(for: activeWorkspace)
        refreshChromeProjection()
    }

    func scrollPosition(for path: String, vaultID: UUID?) -> Double {
        let value = presentationSession(for: path, vaultID: vaultID)?.scrollFraction
            ?? vaultID.flatMap {
                restoredPresentationsByVault[$0]?[path]?.scrollFraction
            }
            ?? restoredUnqualifiedPresentations[path]?.scrollFraction
            ?? 0
        return min(1, max(0, value))
    }

    func rememberScrollPosition(_ fraction: Double, for path: String, vaultID: UUID?) {
        guard fraction.isFinite else { return }
        let normalized = min(1, max(0, fraction))
        if let session = presentationSession(for: path, vaultID: vaultID) {
            guard abs(session.scrollFraction - normalized) > 0.002 else { return }
            session.scrollFraction = normalized
        } else {
            if let vaultID {
                var presentation = restoredPresentationsByVault[vaultID]?[path]
                    ?? WindowDocumentPresentationSnapshot()
                guard abs(presentation.scrollFraction - normalized) > 0.002 else { return }
                presentation.scrollFraction = normalized
                restoredPresentationsByVault[vaultID, default: [:]][path] = presentation
            } else {
                var presentation = restoredUnqualifiedPresentations[path]
                    ?? WindowDocumentPresentationSnapshot()
                guard abs(presentation.scrollFraction - normalized) > 0.002 else { return }
                presentation.scrollFraction = normalized
                restoredUnqualifiedPresentations[path] = presentation
            }
        }
    }

    func restorePresentationState(
        documentPresentations: [String: WindowDocumentPresentationSnapshot],
        vaultID: UUID?
    ) {
        if let vaultID {
            restoredPresentationsByVault[vaultID] = documentPresentations
        } else {
            restoredUnqualifiedPresentations = documentPresentations
        }
        if let selectedDocument {
            hydratePresentation(
                of: session(for: selectedDocument.editingTarget),
                target: selectedDocument.editingTarget,
                path: selectedDocument.relativePath
            )
        }
    }

    func presentationSnapshot(vaultID: UUID?) -> DocumentPresentationSnapshot {
        var documents: [String: WindowDocumentPresentationSnapshot]
        if let vaultID {
            documents = restoredPresentationsByVault[vaultID] ?? [:]
        } else {
            documents = restoredUnqualifiedPresentations
        }

        for (key, reference) in retainedReferences where reference.vaultID == vaultID {
            guard let session = sessions.retainedSession(for: .workspace(key)) else { continue }
            documents[reference.relativePath] = session.windowPresentationSnapshot
        }
        for (target, session) in sessions.retainedSessions
            where target.isFallback && (vaultID == nil || target.vaultID == vaultID) {
            let path = relativePath(for: target)
            documents[path] = session.windowPresentationSnapshot
        }
        for (target, entry) in closedPresentations where target.vaultID == vaultID {
            documents[entry.relativePath] = WindowDocumentPresentationSnapshot(
                scrollFraction: entry.scrollPosition.fraction
            )
        }
        return DocumentPresentationSnapshot(documents: documents)
    }

    func migratePresentationPath(
        from sourcePath: String,
        to destinationPath: String,
        vaultID: UUID?
    ) {
        if let vaultID,
           let presentation = restoredPresentationsByVault[vaultID]?.removeValue(
            forKey: sourcePath
           ) {
            restoredPresentationsByVault[vaultID, default: [:]][destinationPath]
                = presentation
        } else if vaultID == nil,
                  let presentation = restoredUnqualifiedPresentations.removeValue(
                    forKey: sourcePath
                  ) {
            restoredUnqualifiedPresentations[destinationPath] = presentation
        }
        let migratedKeys = retainedReferences.compactMap { key, reference in
            reference.vaultID == vaultID && reference.relativePath == sourcePath ? key : nil
        }
        for key in migratedKeys {
            guard let reference = retainedReferences[key] else { continue }
            retainedReferences[key] = VaultNoteReference(
                vaultID: reference.vaultID,
                vaultName: reference.vaultName,
                vaultRole: reference.vaultRole,
                relativePath: destinationPath,
                stableNoteID: reference.stableNoteID
            )
        }
        for (target, var entry) in closedPresentations
        where target.vaultID == vaultID && entry.relativePath == sourcePath {
            entry = ClosedPresentationEntry(
                relativePath: destinationPath,
                scrollPosition: entry.scrollPosition,
                access: entry.access
            )
            closedPresentations[target] = entry
        }
    }

    func resetPresentationState() {
        restoredPresentationsByVault = [:]
        restoredUnqualifiedPresentations = [:]
        activeWorkspace = .paperAnalysis
        var resetPresentationModes: [WorkspaceVaultSlot: NotePresentationMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            resetPresentationModes[workspace] = .livePreview
        }
        presentationModesByWorkspace = resetPresentationModes
        currentPresentationMode = .livePreview
        for session in sessions.retainedSessions.values {
            session.resetPresentation()
            session.resetScrollPosition()
        }
        closedPresentations.removeAll(keepingCapacity: false)
    }

    func requestOpen(_ route: WindowDocumentRoute) {
        intentHandler(.openDocument(route))
    }

    func requestFileOperation(_ request: NoteFileRequest) {
        intentHandler(.presentNoteFileOperation(request))
    }

    func removeAll(retainingSessions: Bool = false) {
        if !retainingSessions {
            sessions.removeAll()
            retainedReferences.removeAll()
            deferredWorkspaceSnapshotsDuringSave.removeAll()
            restoredPresentationsByVault = [:]
            restoredUnqualifiedPresentations = [:]
            closedPresentations.removeAll(keepingCapacity: false)
            sessionCancellables.removeAll()
            pendingChromeRefreshes.removeAll()
        }
        activeWorkspace = .paperAnalysis
        var resetPresentationModes: [WorkspaceVaultSlot: NotePresentationMode] = [:]
        for workspace in WorkspaceVaultSlot.allCases {
            resetPresentationModes[workspace] = .livePreview
        }
        presentationModesByWorkspace = resetPresentationModes
        currentPresentationMode = .livePreview
        selectedDocument = nil
        chromeProjection = .empty
        snapshots = [:]
        editingDocumentPath = nil
        lastSaveError = nil
    }

    private func pruneReapedSessionBookkeeping() {
        let retained = Set(sessions.retainedSessions.values.map(ObjectIdentifier.init))
        sessionCancellables = sessionCancellables.filter { retained.contains($0.key) }
        pendingChromeRefreshes.formIntersection(retained)
        retainedReferences = retainedReferences.filter {
            sessions.retainedSession(for: .workspace($0.key)) != nil
        }
        deferredWorkspaceSnapshotsDuringSave = deferredWorkspaceSnapshotsDuringSave.filter {
            sessions.retainedSession(for: .workspace($0.key)) != nil
        }
        snapshots = snapshots.filter {
            sessions.retainedSession(for: .workspace($0.key)) != nil
                || selectedDocument?.sessionKey == $0.key
        }
    }

    private func presentationSession(
        for path: String,
        vaultID: UUID?
    ) -> DocumentSessionModel? {
        if let selectedDocument, selectedDocument.relativePath == path {
            return session(for: selectedDocument.editingTarget)
        }
        if let key = retainedReferences.first(where: {
            $0.value.vaultID == vaultID && $0.value.relativePath == path
        })?.key {
            return retainedSession(for: key)
        }
        if let target = sessions.retainedSessions.keys.first(where: {
            guard $0.isFallback else { return false }
            return relativePath(for: $0) == path
        }) {
            return sessions.retainedSession(for: target)
        }
        return nil
    }

    private func refreshChromeProjection(ifOwnedBy session: DocumentSessionModel) {
        guard selectedSessionWithoutCreation() === session else { return }
        refreshChromeProjection()
    }

    private func refreshChromeProjection() {
        guard let selectedDocument,
              let session = selectedSessionWithoutCreation() else {
            if chromeProjection != .empty { chromeProjection = .empty }
            return
        }
        let failureState: DocumentChromeFailureState
        if session.conflict != nil {
            failureState = .conflict
        } else if session.editError != nil {
            failureState = .save
        } else {
            failureState = .none
        }
        let next = DocumentChromeProjection(
            document: selectedDocument,
            mode: session.presentationMode,
            dirtyState: session.hasUnsavedChanges ? .dirty : .clean,
            isSaving: session.isSavingEdit,
            failureState: failureState
        )
        if chromeProjection != next { chromeProjection = next }
    }

    private func selectedSessionWithoutCreation() -> DocumentSessionModel? {
        guard let selectedDocument else { return nil }
        switch selectedDocument.editingTarget {
        case .workspace(let key):
            return sessions.retainedSession(for: .workspace(key))
        case .unavailable:
            return sessions.retainedSession(for: selectedDocument.editingTarget)
        }
    }

    private func hydratePresentation(
        of session: DocumentSessionModel,
        target: DocumentEditingTarget,
        path: String
    ) {
        if let retained = closedPresentations.removeValue(forKey: target) {
            session.scrollFraction = retained.scrollPosition.fraction
            session.scrollAnchor = retained.scrollPosition.anchor
        }
        let restoredPresentation = restoredPresentationsByVault[target.vaultID]?
            .removeValue(forKey: path)
            ?? restoredUnqualifiedPresentations.removeValue(forKey: path)
        if let restoredPresentation {
            let source: String?
            switch target {
            case .workspace(let key):
                source = snapshots[key]?.document.rawContent
            case .unavailable:
                source = nil
            }
            if let source {
                session.restoreWindowPresentation(
                    restoredPresentation,
                    source: source
                )
            } else {
                session.scrollFraction = restoredPresentation.scrollFraction
            }
        }
    }

    /// Applies the active workspace's one live Document-mode selection to the
    /// newly active session. Hidden sessions may retain their editor surface
    /// and last acknowledged configuration, but Notes and tabs do not own a
    /// mode history.
    private func applyCurrentPresentationMode(
        to session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        switch currentPresentationMode {
        case .read:
            if session.isEditing {
                // Tab changes already flush the departing editor. Never use a
                // presentation cutover to discard a recovery-bearing session.
                guard !session.hasUnsavedChanges,
                      session.conflict == nil,
                      session.editError == nil,
                      !session.isSavingEdit,
                      session.activeSaveTask == nil else { return }
                finishEditing(session: session, target: target)
            } else {
                session.preparePresentationMode(.read)
            }
        case .livePreview, .source:
            if case .workspace(let key) = target,
               let capabilities = snapshots[key]?.capabilities,
               !capabilities.canEditSource {
                session.preparePresentationMode(.read)
                return
            }
            guard let editorMode = currentPresentationMode.editorMode else { return }
            if session.isEditing {
                session.switchEditorMode(to: editorMode)
            } else {
                session.preparePresentationMode(currentPresentationMode)
            }
        }
    }

    private func cacheReapedPresentations(
        _ presentations: [DocumentSessionStore.ReapedPresentation]
    ) {
        for presentation in presentations {
            let relativePath = relativePath(for: presentation.target)
            // A clean externally deleted document deliberately removes its
            // retained path before the zero-lease session is reaped. Do not
            // persist an empty or stale presentation route for source that no
            // longer exists.
            guard !relativePath.isEmpty else { continue }
            nextClosedPresentationAccess &+= 1
            closedPresentations[presentation.target] = ClosedPresentationEntry(
                relativePath: relativePath,
                scrollPosition: presentation.scrollPosition,
                access: nextClosedPresentationAccess
            )
        }
        trimClosedPresentations(to: 64)
    }

    private func trimClosedPresentations(to limit: Int) {
        while closedPresentations.count > limit,
              let oldest = closedPresentations.min(by: { $0.value.access < $1.value.access }) {
            closedPresentations[oldest.key] = nil
        }
    }

    func handleMemoryPressure(_ level: DocumentMemoryPressureLevel) {
        Task { await readProjectionCache.removeAll() }
        Task { await linkCompletionIndex.removeAll() }
        switch level {
        case .warning:
            trimClosedPresentations(to: 16)
        case .critical:
            closedPresentations.removeAll(keepingCapacity: false)
        }
    }

    func relativePath(for target: DocumentEditingTarget) -> String {
        switch target {
        case .workspace(let key):
            (selectedDocument?.sessionKey == key ? selectedDocument?.relativePath : nil)
                ?? retainedReferences[key]?.relativePath
                ?? snapshots[key]?.id.relativePath
                ?? ""
        case .unavailable(_, let relativePath):
            relativePath
        }
    }

    func beginEditing(
        session: DocumentSessionModel,
        target: DocumentEditingTarget,
        source: String,
        revision: DocumentFingerprint?,
        mode: MarkdownEditorMode
    ) {
        guard !session.isEditing else { return }
        observe(session)
        session.suppressAutosave = true
        session.originalEditingSource = source
        session.editingSource = source
        session.editingRevision = revision
        session.editorSession.authorizeAutomaticFocus()
        session.beginEditing(in: mode)
        editingDocumentPath = relativePath(for: target)
        Task { @MainActor [weak session] in
            await Task.yield()
            session?.suppressAutosave = false
        }
    }

    func finishEditing(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        session.cancelScheduledWork()
        session.finishEditing()
        session.returnToReadAfterSave = false
        session.suppressAutosave = false
        session.conflict = nil
        session.canRetrySave = false
        if editingDocumentPath == relativePath(for: target) {
            editingDocumentPath = nil
        }
    }

    func editorSourceDidChange(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        guard session.isEditing else { return }
        scheduleAutosave(session: session, target: target)
    }

    func scheduleAutosave(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        guard session.isEditing,
              !session.suppressAutosave,
              session.conflict == nil,
              session.hasUnsavedChanges else { return }
        let path = relativePath(for: target)
        guard !path.isEmpty else { return }
        if editingDocumentPath != path {
            editingDocumentPath = path
        }
        let clock = ContinuousClock()
        session.autosaveDeadline = clock.now.advanced(
            by: .milliseconds(Self.autosaveDelayMilliseconds)
        )
        guard session.autosaveTask == nil else { return }
        session.autosaveTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            while let deadline = session.autosaveDeadline {
                do {
                    try await clock.sleep(until: deadline)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                guard session.autosaveDeadline == deadline else { continue }
                session.autosaveDeadline = nil
                session.autosaveTask = nil
                await self.persistEditingSource(session: session, target: target)
                return
            }
            session.autosaveTask = nil
        }
    }

    func persistEditingSource(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async {
        let attemptedPath = relativePath(for: target)
        do {
            let outcome = try await saveEditingSource(session: session, target: target)
            session.conflict = nil
            session.canRetrySave = false
            switch outcome {
            case .clean:
                setSaveError(nil)
                session.editError = nil
            case .changedDuringSave:
                setSaveError(nil)
                session.editError = nil
                scheduleAutosave(session: session, target: target)
            }
        } catch is CancellationError {
            return
        } catch {
            if let repositoryError = error as? VaultRepositoryError,
               case .fileDoesNotExist = repositoryError,
               case .workspace = target {
                // External move detection arrives through the typed workspace
                // stream shortly after the repository observes the old path
                // missing. Give stable identity a brief, cancellable chance
                // to rebind before presenting a modal deletion failure. A
                // confirmed move cancels this old autosave and retries at the
                // destination; a true deletion still reaches the normal
                // recovery UI after the grace interval.
                do {
                    try await Task.sleep(for: .milliseconds(750))
                } catch is CancellationError {
                    return
                } catch {
                    // Duration sleep has no other expected failure.
                }
            }
            // A stable-identity rename can complete while an autosave is
            // still addressed to the previous path. That failure is stale:
            // presenting it would transiently replace or disable the editor
            // just as `updateDocumentProjection` retries the same retained
            // buffer at the identity-confirmed destination. The destination
            // retry remains revision-gated and owns any current-path error.
            guard relativePath(for: target) == attemptedPath else { return }
            await presentSaveFailure(error, session: session, target: target)
        }
    }

    func flushCurrentEditor(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async throws {
        session.cancelAutosave()
        for _ in 0..<4 {
            let outcome = try await saveEditingSource(session: session, target: target)
            if outcome != .changedDuringSave { return }
        }
        throw DocumentControllerError.changedDuringSave
    }

    func flushForExternalOperation(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async throws {
        do {
            try await flushCurrentEditor(session: session, target: target)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await presentSaveFailure(error, session: session, target: target)
            throw error
        }
    }

    func retrySave(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        session.editError = nil
        session.canRetrySave = false
        Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try await self.flushCurrentEditor(session: session, target: target)
                self.setSaveError(nil)
            } catch is CancellationError {
                return
            } catch {
                await self.presentSaveFailure(error, session: session, target: target)
            }
        }
    }

    func reloadFromDisk(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async throws {
        guard let conflict = session.conflict else { return }
        do {
            let document = try await loadDocument(for: target)
            guard document.fingerprint == conflict.diskRevision else {
                throw VaultRepositoryError.conflict(
                    expected: conflict.diskRevision,
                    current: document.fingerprint
                )
            }
            await documentDidCommit(SaveResult(document: document))
            session.suppressAutosave = true
            session.editingSource = document.rawContent
            session.originalEditingSource = document.rawContent
            session.editingRevision = document.fingerprint
            session.editorSession.loadDocument(
                document.rawContent,
                documentID: session.editorSession.bridgeDocumentID,
                mode: session.retainedEditorMode
            )
            session.suppressAutosave = false
            session.showConflictComparison = false
            session.editError = nil
            setSaveError(nil)
            finishEditing(session: session, target: target)
        } catch {
            session.showConflictComparison = false
            await presentSaveFailure(error, session: session, target: target)
            throw error
        }
    }

    private func saveEditingSource(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async throws -> EditorSaveOutcome {
        if let activeSaveTask = session.activeSaveTask {
            return try await activeSaveTask.value
        }

        let token = UUID()
        let task = Task { @MainActor in
            try await self.performEditingSave(session: session, target: target)
        }
        session.activeSaveToken = token
        session.activeSaveTask = task
        session.isSavingEdit = true

        do {
            let outcome = try await task.value
            if let conflict = finishSaveAttempt(token: token, session: session) {
                throw conflict
            }
            return outcome
        } catch {
            if let conflict = finishSaveAttempt(token: token, session: session) {
                throw conflict
            }
            throw error
        }
    }

    @discardableResult
    private func finishSaveAttempt(
        token: UUID,
        session: DocumentSessionModel
    ) -> VaultRepositoryError? {
        guard session.activeSaveToken == token else {
            return repositoryConflict(for: session)
        }
        session.activeSaveTask = nil
        session.activeSaveToken = nil
        session.isSavingEdit = false
        return reconcileLatestDeferredWorkspaceSnapshot(for: session)
    }

    private func repositoryConflict(
        for session: DocumentSessionModel
    ) -> VaultRepositoryError? {
        guard let conflict = session.conflict else { return nil }
        return VaultRepositoryError.conflict(
            expected: conflict.baseRevision,
            current: conflict.diskRevision
        )
    }

    /// Drains one session's latest complete workspace publication after its
    /// save is no longer the exact-source owner. Internal visibility keeps the
    /// save/event race deterministic under model-level tests.
    @discardableResult
    func reconcileLatestDeferredWorkspaceSnapshot(
        for session: DocumentSessionModel
    ) -> VaultRepositoryError? {
        guard let key = session.key,
              let snapshot = deferredWorkspaceSnapshotsDuringSave.removeValue(
                forKey: key
              ) else { return nil }
        reconcile(session: session, with: snapshot)
        return repositoryConflict(for: session)
    }

    private func performEditingSave(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async throws -> EditorSaveOutcome {
        guard session.isEditing else { return .clean }
        let path = relativePath(for: target)
        guard !path.isEmpty else { throw DocumentControllerError.documentUnavailable }
        if !session.editorSession.isReady || !session.editorSession.isLoaded {
            guard session.hasUnsavedChanges else { return .clean }
            guard try await session.editorSession.waitUntilLoadedForSave() else {
                throw DocumentControllerError.editorUnavailable
            }
            // The retained CodeMirror session is authoritative again;
            // continue through the ordinary full-buffer and revision checks.
        }
        guard let revision = session.editingRevision else {
            throw DocumentControllerError.saveFailed(
                "The editing revision is unavailable. Return to Review mode and reopen the editor."
            )
        }

        let editorSnapshot = try await session.editorSession.currentTextSnapshot(
            for: session.editorSession.bridgeDocumentID
        )
        let sourceBeingSaved = editorSnapshot.text
        try Task.checkCancellation()
        guard relativePath(for: target) == path else {
            throw DocumentControllerError.documentUnavailable
        }
        session.suppressAutosave = true
        session.editingSource = sourceBeingSaved
        defer { session.suppressAutosave = false }
        guard sourceBeingSaved != session.originalEditingSource
                || session.editorSession.isDirty else {
            if editingDocumentPath == path { editingDocumentPath = nil }
            return .clean
        }

        let result = try await saveDocument(
            sourceBeingSaved,
            target: target,
            expectedRevision: revision
        )
        let saved = result.document
        session.editingRevision = saved.fingerprint
        session.originalEditingSource = saved.rawContent
        await documentDidCommit(result)

        let acknowledgement = try await session.editorSession.acknowledgeCommittedSnapshot(
            expectedText: sourceBeingSaved,
            committedText: saved.rawContent,
            fingerprint: saved.fingerprint,
            documentID: session.editorSession.bridgeDocumentID
        )
        switch acknowledgement {
        case .clean:
            session.editingSource = saved.rawContent
            if editingDocumentPath == path { editingDocumentPath = nil }
            return .clean
        case .superseded:
            session.editingSource = session.editorSession.checkedSource
            editingDocumentPath = path
            return .changedDuringSave
        }
    }

    private func saveDocument(
        _ source: String,
        target: DocumentEditingTarget,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        switch target {
        case .workspace(let key):
            let path = relativePath(for: target)
            guard !path.isEmpty else { throw DocumentControllerError.documentUnavailable }
            return try await commit(
                VaultQualifiedNoteID(vaultID: key.vaultID, relativePath: path),
                changeSet: .source(source),
                expectedRevision: expectedRevision
            )
        case .unavailable:
            throw DocumentControllerError.documentUnavailable
        }
    }

    private func loadDocument(for target: DocumentEditingTarget) async throws -> NoteDocument {
        switch target {
        case .workspace(let key):
            let path = relativePath(for: target)
            guard !path.isEmpty else { throw DocumentControllerError.documentUnavailable }
            return try await load(
                VaultQualifiedNoteID(vaultID: key.vaultID, relativePath: path)
            )
        case .unavailable:
            throw DocumentControllerError.documentUnavailable
        }
    }

    private func presentSaveFailure(
        _ error: Error,
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) async {
        let message = error.localizedDescription
        setSaveError(message)
        if case VaultRepositoryError.conflict = error,
           let diskDocument = try? await loadDocument(for: target),
           let baseRevision = session.editingRevision {
            let editorSource = session.editorSession.isLoaded
                ? session.editorSession.checkedSource
                : session.editingSource
            session.editingSource = editorSource
            session.conflict = DocumentConflictSnapshot(
                relativePath: relativePath(for: target),
                editorSource: editorSource,
                diskSource: diskDocument.rawContent,
                baseRevision: baseRevision
            )
            session.canRetrySave = false
        } else {
            session.conflict = nil
            session.canRetrySave = Self.saveFailureAllowsRetry(error)
        }
        session.editError = message
    }

    static func saveFailureAllowsRetry(_ error: Error) -> Bool {
        if (error as? DocumentControllerError) == .documentUnavailable {
            return false
        }
        guard let repositoryError = error as? VaultRepositoryError else {
            return true
        }
        if case .writeFailed = repositoryError { return true }
        return false
    }

    func setSaveError(_ message: String?) {
        lastSaveError = message
    }

    private func requireOperations() throws -> any DocumentUseCases {
        guard let operations else { throw DocumentControllerError.documentUnavailable }
        return operations
    }

    private static let autosaveDelayMilliseconds: Int = {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"],
           let value = Int(raw), value >= 0 {
            return value
        }
#endif
        return 850
    }()

    /// Applies one complete generation to every open document in this window.
    /// Clean peers converge or close when their stable document disappears;
    /// dirty, conflicted, retryable, or in-flight sessions keep their exact
    /// recovery state and are never silently replaced.
    @discardableResult
    func receive(
        _ workspace: WorkspaceSnapshot,
        openDocuments: [WindowSelectedDocument] = []
    ) -> DocumentWorkspaceReconciliation {
        var documents = Set(openDocuments)
        if let selectedDocument { documents.insert(selectedDocument) }
        guard !documents.isEmpty else { return .unchanged }

        var removed: Set<WindowSelectedDocument> = []
        var retained: Set<WindowSelectedDocument> = []
        for document in documents {
            switch publishedLocation(of: document, in: workspace) {
            case .located(let vault, let note):
                recordPublishedLocation(
                    document: document,
                    vault: vault,
                    note: note
                )
            case .identityUnavailable:
                // The source path still exists, but the generation cannot
                // prove the tab's stable identity. Identity recovery owns this
                // state; it is not evidence that the document was deleted.
                continue
            case .missing:
                guard let session = sessions.retainedSession(
                    for: document.editingTarget
                ), !sessions.pinReasons(for: session).isEmpty else {
                    removed.insert(document)
                    continue
                }
                retainDeletedDocumentForRecovery(document, session: session)
                retained.insert(document)
            }
        }

        forgetCleanDeletedDocuments(removed)
        return DocumentWorkspaceReconciliation(
            removedDocuments: removed,
            retainedDeletedDocuments: retained
        )
    }

    var retainedDeletedDocumentPath: String? {
        guard let selectedDocument,
              let session = sessions.retainedSession(
                  for: selectedDocument.editingTarget
              ), !sessions.pinReasons(for: session).isEmpty else {
            return nil
        }
        return selectedDocument.relativePath
    }

    private enum PublishedDocumentLocation {
        case located(WorkspaceVaultSnapshot, WorkspaceNoteSnapshot)
        case identityUnavailable
        case missing
    }

    private func publishedLocation(
        of document: WindowSelectedDocument,
        in workspace: WorkspaceSnapshot
    ) -> PublishedDocumentLocation {
        guard let vaultID = document.vaultID,
              let vault = workspace.vault(id: vaultID) else {
            return .missing
        }
        switch document {
        case .workspace(let descriptor):
            if let note = vault.documents.first(where: {
                $0.stableIdentity.resolvedID == descriptor.sessionKey.noteID
            }) {
                return .located(vault, note)
            }
            guard let pathMatch = vault.documents.first(where: {
                $0.id.relativePath == descriptor.reference.relativePath
            }) else {
                return .missing
            }
            return switch pathMatch.stableIdentity {
            case .resolved:
                .missing
            case .ambiguous(let candidateIDs):
                candidateIDs.contains(descriptor.sessionKey.noteID)
                    ? .identityUnavailable
                    : .missing
            case .pending(let pendingID):
                pendingID == descriptor.sessionKey.noteID
                    ? .identityUnavailable
                    : .missing
            case .unresolved:
                .identityUnavailable
            }
        case .unavailable(_, let relativePath):
            guard let note = vault.documents.first(where: {
                $0.id.relativePath == relativePath
            }) else {
                return .missing
            }
            return .located(vault, note)
        }
    }

    private func recordPublishedLocation(
        document: WindowSelectedDocument,
        vault: WorkspaceVaultSnapshot,
        note: WorkspaceNoteSnapshot
    ) {
        guard case .workspace(let descriptor) = document else { return }
        let key = descriptor.sessionKey
        snapshots[key] = note
        let updated = WindowDocumentDescriptor(
            sessionKey: key,
            reference: VaultNoteReference(
                vaultID: vault.vault.id,
                vaultName: vault.vault.name,
                vaultRole: vault.vault.role,
                relativePath: note.id.relativePath,
                stableNoteID: key.noteID.uuidString
            )
        )
        retainedReferences[key] = updated.reference
        guard selectedDocument?.editingTarget == document.editingTarget else {
            return
        }
        updateDocumentProjection(updated)
        let selectedSession = session(for: key)
        reconcile(session: selectedSession, with: note)
        if selectedSession.editError == nil { setSaveError(nil) }
    }

    private func retainDeletedDocumentForRecovery(
        _ document: WindowSelectedDocument,
        session: DocumentSessionModel
    ) {
        session.cancelAutosave()
        session.conflict = nil
        session.canRetrySave = false
        let message = String(
            localized: "The note was deleted outside Scholium. Its exact editor buffer remains open for recovery.",
            table: "Localizable",
            bundle: .module
        )
        session.editError = message
        if selectedDocument?.editingTarget == document.editingTarget {
            setSaveError(message)
        }
    }

    private func forgetCleanDeletedDocuments(
        _ documents: Set<WindowSelectedDocument>
    ) {
        guard !documents.isEmpty else { return }
        let targets = Set(documents.map(\.editingTarget))
        for document in documents {
            if let key = document.sessionKey {
                snapshots[key] = nil
                retainedReferences[key] = nil
                deferredWorkspaceSnapshotsDuringSave[key] = nil
            }
            guard let session = sessions.retainedSession(
                for: document.editingTarget
            ) else { continue }
            session.cancelScheduledWork()
            session.finishEditing()
            session.conflict = nil
            session.editError = nil
            session.canRetrySave = false
        }
        if let selectedDocument,
           targets.contains(selectedDocument.editingTarget) {
            if editingDocumentPath == selectedDocument.relativePath {
                editingDocumentPath = nil
            }
            self.selectedDocument = nil
            setSaveError(nil)
            refreshChromeProjection()
        }
    }

    private func reconcile(
        session: DocumentSessionModel,
        with snapshot: WorkspaceNoteSnapshot
    ) {
        let diskSource = snapshot.document.rawContent
        guard let baseRevision = session.editingRevision else {
            session.editingSource = diskSource
            session.originalEditingSource = diskSource
            session.editingRevision = snapshot.fingerprint
            return
        }
        guard baseRevision != snapshot.fingerprint else { return }

        // The handle publishes the committed generation before its save call
        // resumes on the main actor. Let the in-flight save install the exact
        // returned bytes; if it fails, conflict recovery reloads the then
        // current disk revision through the same Application capability.
        if session.isSavingEdit, let key = session.key {
            deferredWorkspaceSnapshotsDuringSave[key] = snapshot
            return
        }

        if session.hasUnsavedChanges || session.editorSession.isComposing {
            session.cancelAutosave()
            let editorSource = session.editorSession.isLoaded
                ? session.editorSession.checkedSource
                : session.editingSource
            session.editingSource = editorSource
            session.conflict = DocumentConflictSnapshot(
                relativePath: snapshot.id.relativePath,
                editorSource: editorSource,
                diskSource: diskSource,
                baseRevision: baseRevision
            )
            session.canRetrySave = false
            session.editError = VaultRepositoryError.conflict(
                expected: baseRevision,
                current: snapshot.fingerprint
            ).localizedDescription
            setSaveError(session.editError)
            return
        }

        session.suppressAutosave = true
        session.editingSource = diskSource
        session.originalEditingSource = diskSource
        session.editingRevision = snapshot.fingerprint
        session.conflict = nil
        session.editError = nil
        session.canRetrySave = false
        let managedBodyStart = session.isEnteringManagedCreation
            ? snapshot.document.bodyUTF16Offset
            : nil
        if let managedBodyStart {
            session.beginManagedCreationEntry(bodyStartUTF16: managedBodyStart)
        }
        if editingDocumentPath == snapshot.id.relativePath {
            editingDocumentPath = nil
        }
        session.suppressAutosave = false
        if session.isEditing || session.editorSession.hasAttachedWebView {
            session.editorSession.loadDocument(
                diskSource,
                documentID: session.editorSession.bridgeDocumentID,
                mode: session.retainedEditorMode,
                initialSourceRange: managedBodyStart.map { $0..<$0 }
            )
        }
    }

}

enum DocumentControllerError: LocalizedError, Equatable {
    case saveFailed(String)
    case editorUnavailable
    case changedDuringSave
    case documentUnavailable

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            String(localized: "Scholium kept the current editor open because it could not safely save this note. \(message)", table: "Localizable", bundle: .module)
        case .editorUnavailable:
            String(localized: "Scholium kept the current editor open because it could not retrieve the complete Markdown buffer.", table: "Localizable", bundle: .module)
        case .changedDuringSave:
            String(localized: "Scholium kept the current editor open because the note continued changing while it was being saved.", table: "Localizable", bundle: .module)
        case .documentUnavailable:
            String(localized: "Scholium kept the exact editor buffer open because this document is no longer available through the active Triptych.", table: "Localizable", bundle: .module)
        }
    }

}
