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
/// carry stable session identity; Unclassified and identity-recovery notes
/// remain explicitly path-addressed without inventing a vault identity.
enum WindowSelectedDocument: Hashable, Sendable {
    case workspace(WindowDocumentDescriptor)
    case unclassified(relativePath: String)
    case unavailable(vaultID: UUID, relativePath: String)

    var relativePath: String {
        switch self {
        case .workspace(let descriptor): descriptor.reference.relativePath
        case .unclassified(let relativePath), .unavailable(_, let relativePath): relativePath
        }
    }

    var vaultID: UUID? {
        switch self {
        case .workspace(let descriptor): descriptor.reference.vaultID
        case .unavailable(let vaultID, _): vaultID
        case .unclassified: nil
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
/// follow stable identity through renames; portable Unclassified documents
/// remain path-addressed because they intentionally have no vault identity.
enum DocumentEditingTarget: Hashable, Sendable {
    case workspace(DocumentSessionKey)
    case unclassified(relativePath: String)
    case unavailable(relativePath: String)
}

extension DocumentEditingTarget {
    var isFallback: Bool {
        if case .workspace = self { return false }
        return true
    }

    var vaultID: UUID? {
        guard case .workspace(let key) = self else { return nil }
        return key.vaultID
    }
}

extension WindowSelectedDocument {
    var editingTarget: DocumentEditingTarget {
        switch self {
        case .workspace(let descriptor): .workspace(descriptor.sessionKey)
        case .unclassified(let relativePath): .unclassified(relativePath: relativePath)
        case .unavailable(_, let relativePath): .unavailable(relativePath: relativePath)
        }
    }
}

struct DocumentPresentationSnapshot: Equatable, Sendable {
    let modes: [String: String]
    let scrollPositions: [String: Double]
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

/// Per-window owner for the selected document and retained editor sessions. Repository writes,
/// lifecycle transactions, and conflict recovery remain Application calls;
/// this controller owns only window and editor-session state.
@MainActor
final class DocumentController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void
    typealias DocumentCommitHandler = @MainActor (NoteDocument) async -> Void

    @Published private(set) var selectedDocument: WindowSelectedDocument?
    @Published private(set) var chromeProjection = DocumentChromeProjection.empty
    @Published private(set) var snapshots: [DocumentSessionKey: WorkspaceNoteSnapshot] = [:]
    @Published private(set) var editingDocumentPath: String?
    @Published private(set) var lastSaveError: String?
    @Published var lifecycleMutationGeneration: UInt64 = 0
    @Published var pendingSourceLine: Int?
    @Published var changedSinceReviewPaths: Set<String> = []
    @Published var requestedPresentationMode: NotePresentationMode?
    @Published var pendingCommentSelection: MarkdownReviewSelection?
    @Published var focusedResearcherCommentID: UUID?
    @Published var humanReviewRecords: [String: HumanReviewRecord] = [:]
    @Published var humanReviewRecordsByNoteID: [UUID: HumanReviewRecord] = [:]
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
    private var restoredModes: [String: String] = [:]
    private var restoredScrollPositions: [String: Double] = [:]
    private var restoredPresentationVaultID: UUID?
    private struct ClosedPresentationEntry {
        let relativePath: String
        let mode: NotePresentationMode
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
        if let snapshot { receive(snapshot) }
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
        workspaceID: UUID?
    ) async -> String {
        let stableTarget: String
        switch target {
        case .workspace(let key):
            stableTarget = "\(key.vaultID.uuidString.lowercased()):\(key.noteID.uuidString.lowercased())"
        case .unclassified(let path):
            stableTarget = "unclassified:\(path)"
        case .unavailable(let path):
            stableTarget = "unavailable:\(path)"
        }
        return await readProjectionCache.html(
            for: DocumentReadProjectionKey(
                workspaceID: workspaceID,
                stableTarget: stableTarget,
                relativePath: relativePath,
                fingerprint: fingerprint
            ),
            source: source
        )
    }

    func editorLinkCompletions(
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
            query,
            sourcePath: sourcePath,
            currentVaultID: currentVaultID,
            generation: graphGeneration
        )) ?? []
    }

    func load(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try await requireOperations().load(id)
    }

    func loadUnclassified(relativePath: String) async throws -> NoteDocument {
        try await requireOperations().loadUnclassified(relativePath: relativePath)
    }

    func unclassifiedDocuments() async throws -> [NoteDocument] {
        try await requireOperations().unclassifiedDocuments()
    }

    func importUnclassifiedMarkdown(at sourceURL: URL) async throws -> URL {
        try await requireOperations().importUnclassifiedMarkdown(at: sourceURL)
    }

    func saveUnclassified(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        try await requireOperations().saveUnclassified(
            relativePath: relativePath,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func create(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> NoteDocument {
        try await requireOperations().create(id, content: content)
    }

    func create(_ request: DocumentCreationRequest) async throws -> NoteDocument {
        try await requireOperations().create(request)
    }

    func duplicate(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        try await requireOperations().duplicate(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    func save(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try await requireOperations().save(
            id,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        )
    }

    func versions(for id: VaultQualifiedNoteID) async throws -> [VaultVersion] {
        try await requireOperations().versions(for: id)
    }

    func restore(
        _ id: VaultQualifiedNoteID,
        versionID: UUID,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try await requireOperations().restore(
            id,
            versionID: versionID,
            expectedRevision: expectedRevision
        )
    }

    func move(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await requireOperations().move(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    func setAside(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await requireOperations().setAside(id, expectedRevision: expectedRevision)
    }

    func moveToTrash(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await requireOperations().moveToTrash(id, expectedRevision: expectedRevision)
    }

    func putBack(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await requireOperations().putBack(id, expectedRevision: expectedRevision)
    }

    func putBackDestination(for relativePath: String) -> String? {
        for prefix in ["Set Aside/", "Trash/"] where relativePath.hasPrefix(prefix) {
            let destination = String(relativePath.dropFirst(prefix.count))
            return destination.isEmpty ? nil : destination
        }
        return nil
    }

    func deletePermanently(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> PermanentDeletionCommit {
        try await requireOperations().deletePermanently(
            id,
            expectedRevision: expectedRevision
        )
    }

    func recoverInterruptedTransactions() async throws -> [String] {
        try await requireOperations().recoverInterruptedTransactions()
    }

    func classifyUnclassified(
        _ relativePath: String,
        into slot: WorkspaceVaultSlot,
        destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> UnclassifiedClassificationCommit {
        try await requireOperations().classifyUnclassified(
            relativePath,
            into: slot,
            destinationRelativePath: destinationRelativePath,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> NoteIdentityRecord {
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
        if selectedDocument != document {
            selectedDocument = document
        }
        switch document {
        case .workspace(let descriptor):
            retainedReferences[descriptor.sessionKey] = descriptor.reference
            hydratePresentation(
                of: session(for: descriptor.sessionKey),
                target: .workspace(descriptor.sessionKey),
                path: descriptor.reference.relativePath
            )
        case .unclassified, .unavailable:
            _ = session(for: document.editingTarget)
        }
        refreshChromeProjection()
    }

    func selectUnclassifiedDocument(relativePath: String) {
        selectDocument(.unclassified(relativePath: relativePath))
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

    /// Captures the selected CodeMirror state before view reconstruction, but
    /// does not make the view itself the owner of close safety.
    func captureSelectedEditorForReconstruction() async throws {
        guard let selectedDocument,
              let session = sessions.retainedSession(for: selectedDocument.editingTarget),
              session.editorSession.hasAttachedWebView else { return }
        try await session.editorSession.captureStateForViewReconstruction()
    }

    /// Flushes every session that is still reachable from a tab or protected
    /// by a safety pin. Ordering is stable to make close/quit diagnostics and
    /// tests deterministic.
    func flushLeasedOrPinnedSessions() async throws {
        let candidates = sessions.leasedOrPinnedSessions.sorted {
            relativePath(for: $0.0) < relativePath(for: $1.0)
        }
        for (target, session) in candidates {
            guard session.hasUnsavedChanges || session.isSavingEdit || session.canRetrySave else {
                continue
            }
            if session.editorSession.hasAttachedWebView {
                try await session.editorSession.captureStateForViewReconstruction()
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
        guard session.hasUnsavedChanges || session.isSavingEdit || session.canRetrySave else { return }
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
        vaultRole: VaultRole
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
        installOpenedDocument(descriptor)
        snapshots[key] = snapshot
        reconcile(session: session(for: key), with: snapshot)
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
        session.autosaveTask?.cancel()
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
                if session.activeSaveToken == supersededToken {
                    session.activeSaveTask = nil
                    session.activeSaveToken = nil
                    session.isSavingEdit = false
                }
            }
            guard !Task.isCancelled,
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

    func presentationMode(for path: String, vaultID: UUID?) -> NotePresentationMode {
        presentationSession(for: path, vaultID: vaultID)?.presentationMode
            ?? restoredModes[path].flatMap(NotePresentationMode.init(rawValue:))
            ?? .read
    }

    func rememberPresentationMode(
        _ mode: NotePresentationMode,
        for path: String,
        vaultID: UUID?
    ) {
        if let session = presentationSession(for: path, vaultID: vaultID) {
            session.presentationMode = mode
        } else {
            restoredPresentationVaultID = vaultID
            restoredModes[path] = mode.rawValue
        }
    }

    func scrollPosition(for path: String, vaultID: UUID?) -> Double {
        let value = presentationSession(for: path, vaultID: vaultID)?.scrollFraction
            ?? restoredScrollPositions[path]
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
            guard abs((restoredScrollPositions[path] ?? 0) - normalized) > 0.002 else { return }
            restoredPresentationVaultID = vaultID
            restoredScrollPositions[path] = normalized
        }
    }

    func restorePresentationState(
        modes: [String: String],
        scrollPositions: [String: Double],
        vaultID: UUID?
    ) {
        restoredModes = modes
        restoredScrollPositions = scrollPositions.filter { $0.value.isFinite }
        restoredPresentationVaultID = vaultID
        if let selectedDocument {
            hydratePresentation(
                of: session(for: selectedDocument.editingTarget),
                target: selectedDocument.editingTarget,
                path: selectedDocument.relativePath
            )
        }
    }

    func presentationSnapshot(vaultID: UUID?) -> DocumentPresentationSnapshot {
        var modes = restoredPresentationVaultID == vaultID ? restoredModes : [:]
        var scrollPositions = restoredPresentationVaultID == vaultID
            ? restoredScrollPositions
            : [:]

        for (key, reference) in retainedReferences where reference.vaultID == vaultID {
            guard let session = sessions.retainedSession(for: .workspace(key)) else { continue }
            modes[reference.relativePath] = session.presentationMode.rawValue
            scrollPositions[reference.relativePath] = min(1, max(0, session.scrollFraction))
        }
        for (target, session) in sessions.retainedSessions where target.isFallback {
            let path = relativePath(for: target)
            modes[path] = session.presentationMode.rawValue
            scrollPositions[path] = min(1, max(0, session.scrollFraction))
        }
        for (target, entry) in closedPresentations where target.vaultID == vaultID {
            modes[entry.relativePath] = entry.mode.rawValue
            scrollPositions[entry.relativePath] = min(1, max(0, entry.scrollPosition.fraction))
        }
        return DocumentPresentationSnapshot(
            modes: modes,
            scrollPositions: scrollPositions
        )
    }

    func migratePresentationPath(
        from sourcePath: String,
        to destinationPath: String,
        vaultID: UUID?
    ) {
        if restoredPresentationVaultID == vaultID {
            if let mode = restoredModes.removeValue(forKey: sourcePath) {
                restoredModes[destinationPath] = mode
            }
            if let scroll = restoredScrollPositions.removeValue(forKey: sourcePath) {
                restoredScrollPositions[destinationPath] = scroll
            }
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
                mode: entry.mode,
                scrollPosition: entry.scrollPosition,
                access: entry.access
            )
            closedPresentations[target] = entry
        }
    }

    func resetPresentationState() {
        restoredModes = [:]
        restoredScrollPositions = [:]
        restoredPresentationVaultID = nil
        for session in sessions.retainedSessions.values {
            session.presentationMode = .read
            session.resetScrollPosition()
        }
        closedPresentations.removeAll(keepingCapacity: false)
    }

    func requestOpen(_ route: WindowDocumentRoute) {
        intentHandler(.openDocument(route))
    }

    func requestLifecycle(_ request: NoteLifecycleRequest) {
        intentHandler(.presentLifecycle(request))
    }

    func removeAll(retainingSessions: Bool = false) {
        if !retainingSessions {
            sessions.removeAll()
            retainedReferences.removeAll()
            restoredModes = [:]
            restoredScrollPositions = [:]
            restoredPresentationVaultID = nil
            closedPresentations.removeAll(keepingCapacity: false)
            sessionCancellables.removeAll()
            pendingChromeRefreshes.removeAll()
        }
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
        case .unclassified, .unavailable:
            return sessions.retainedSession(for: selectedDocument.editingTarget)
        }
    }

    private func hydratePresentation(
        of session: DocumentSessionModel,
        target: DocumentEditingTarget,
        path: String
    ) {
        if let retained = closedPresentations.removeValue(forKey: target) {
            session.presentationMode = retained.mode
            session.scrollFraction = retained.scrollPosition.fraction
            session.scrollAnchor = retained.scrollPosition.anchor
        }
        if let rawMode = restoredModes.removeValue(forKey: path),
           let mode = NotePresentationMode(rawValue: rawMode) {
            session.presentationMode = mode
        }
        if let restoredScroll = restoredScrollPositions.removeValue(forKey: path),
           restoredScroll.isFinite {
            session.scrollFraction = min(1, max(0, restoredScroll))
        }
    }

    private func cacheReapedPresentations(
        _ presentations: [DocumentSessionStore.ReapedPresentation]
    ) {
        for presentation in presentations {
            nextClosedPresentationAccess &+= 1
            closedPresentations[presentation.target] = ClosedPresentationEntry(
                relativePath: relativePath(for: presentation.target),
                mode: presentation.mode,
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
        case .unclassified(let relativePath), .unavailable(let relativePath):
            relativePath
        }
    }

    func beginEditing(
        session: DocumentSessionModel,
        target: DocumentEditingTarget,
        source: String,
        revision: DocumentFingerprint?,
        mode: NotePresentationMode
    ) {
        guard !session.isEditing, mode != .read else { return }
        observe(session)
        session.suppressAutosave = true
        session.originalEditingSource = source
        session.editingSource = source
        session.editingRevision = revision
        session.presentationMode = mode
        session.retainedEditorMode = mode
        session.retainsEditorSurface = true
        session.isEditing = true
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
        session.isEditing = false
        session.presentationMode = .read
        session.returnToReadAfterSave = false
        session.suppressAutosave = false
        session.conflict = nil
        session.canRetrySave = false
        if editingDocumentPath == relativePath(for: target) {
            editingDocumentPath = nil
        }
    }

    func updateEditingSource(
        _ source: String,
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        guard session.isEditing, session.editingSource != source else { return }
        session.editingSource = source
        scheduleAutosave(session: session, target: target)
    }

    func scheduleAutosave(
        session: DocumentSessionModel,
        target: DocumentEditingTarget
    ) {
        guard session.isEditing,
              !session.suppressAutosave,
              session.hasUnsavedChanges else { return }
        let path = relativePath(for: target)
        guard !path.isEmpty else { return }
        editingDocumentPath = path
        session.autosaveTask?.cancel()
        session.autosaveTask = Task { @MainActor [weak self, weak session] in
            try? await Task.sleep(for: .milliseconds(Self.autosaveDelayMilliseconds))
            guard !Task.isCancelled, let self, let session else { return }
            await self.persistEditingSource(session: session, target: target)
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
            case .committedWithRefreshFailure(let message):
                setSaveError(message)
                session.editError = message
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
        session.autosaveTask?.cancel()
        session.autosaveTask = nil
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
            await documentDidCommit(document)
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
            if session.activeSaveToken == token {
                session.activeSaveTask = nil
                session.activeSaveToken = nil
                session.isSavingEdit = false
            }
            return outcome
        } catch {
            if session.activeSaveToken == token {
                session.activeSaveTask = nil
                session.activeSaveToken = nil
                session.isSavingEdit = false
            }
            throw error
        }
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
                "The editing revision is unavailable. Return to Read mode and reopen the editor."
            )
        }

        let sourceBeingSaved = try await session.editorSession.currentText(
            for: session.editorSession.bridgeDocumentID
        )
        try Task.checkCancellation()
        guard relativePath(for: target) == path else {
            throw DocumentControllerError.documentUnavailable
        }
        guard DocumentFingerprint(content: sourceBeingSaved)
                == DocumentFingerprint(content: session.editingSource) else {
            // CodeMirror is authoritative. Recover its complete exact buffer,
            // keep the revision gate unchanged, and require a fresh save.
            session.suppressAutosave = true
            session.editingSource = sourceBeingSaved
            session.suppressAutosave = false
            editingDocumentPath = path
            throw DocumentControllerError.deltaMirrorMismatch
        }

        session.suppressAutosave = true
        session.editingSource = sourceBeingSaved
        defer { session.suppressAutosave = false }
        guard sourceBeingSaved != session.originalEditingSource
                || session.editorSession.isDirty else {
            if editingDocumentPath == path { editingDocumentPath = nil }
            return .clean
        }

        let saved: NoteDocument
        let committedRefreshFailure: String?
        do {
            saved = try await saveDocument(
                sourceBeingSaved,
                target: target,
                expectedRevision: revision
            )
            committedRefreshFailure = nil
        } catch let error as ScholiumApplicationError {
            guard error.mustNotRetryMutation,
                  let committedRevision = error.committedDocumentRevision else {
                throw error
            }
            let committedDocument = NoteDocument(
                relativePath: path,
                rawContent: sourceBeingSaved
            )
            guard committedDocument.fingerprint == committedRevision else { throw error }
            saved = committedDocument
            committedRefreshFailure = error.refreshFailureReason.map {
                "The note was saved, but derived workspace state could not refresh. \($0)"
            }
        } catch {
            throw error
        }
        session.editingRevision = saved.fingerprint
        session.originalEditingSource = saved.rawContent
        await documentDidCommit(saved)

        let synchronized = try await session.editorSession.synchronizeCommittedText(
            expectedText: sourceBeingSaved,
            committedText: saved.rawContent,
            fingerprint: saved.fingerprint,
            documentID: session.editorSession.bridgeDocumentID
        )
        if synchronized {
            session.editingSource = saved.rawContent
            if editingDocumentPath == path { editingDocumentPath = nil }
            return committedRefreshFailure.map(EditorSaveOutcome.committedWithRefreshFailure)
                ?? .clean
        }

        session.editingSource = try await session.editorSession.currentText(
            for: session.editorSession.bridgeDocumentID
        )
        editingDocumentPath = path
        return .changedDuringSave
    }

    private func saveDocument(
        _ source: String,
        target: DocumentEditingTarget,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        switch target {
        case .workspace(let key):
            let path = relativePath(for: target)
            guard !path.isEmpty else { throw DocumentControllerError.documentUnavailable }
            return try await save(
                VaultQualifiedNoteID(vaultID: key.vaultID, relativePath: path),
                changeSet: .source(source),
                expectedRevision: expectedRevision
            ).document
        case .unclassified(let relativePath):
            return try await saveUnclassified(
                relativePath: relativePath,
                source: source,
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
        case .unclassified(let relativePath):
            return try await loadUnclassified(relativePath: relativePath)
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
            session.conflict = DocumentConflictSnapshot(
                relativePath: relativePath(for: target),
                editorSource: session.editingSource,
                diskSource: diskDocument.rawContent,
                baseRevision: baseRevision
            )
            session.canRetrySave = false
        } else {
            session.conflict = nil
            let documentIsUnavailable = (error as? DocumentControllerError) == .documentUnavailable
            session.canRetrySave = !(error is VaultRepositoryError)
                && !documentIsUnavailable
        }
        session.editError = message
    }

    func setSaveError(_ message: String?) {
        lastSaveError = message
    }

    private func requireOperations() throws -> any DocumentUseCases {
        guard let operations else { throw DocumentControllerError.documentUnavailable }
        return operations
    }

    private static var autosaveDelayMilliseconds: Int {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"],
           let value = Int(raw), value >= 0 {
            return value
        }
#endif
        return 850
    }

    /// Applies one complete generation to this window. A clean peer converges
    /// to the new source; a dirty peer keeps its exact buffer and receives an
    /// immutable comparison against the published disk revision.
    func receive(_ snapshot: WorkspaceSnapshot) {
        apply(snapshot)
    }

    private func apply(_ workspace: WorkspaceSnapshot) {
        guard let descriptor = activeDocument else { return }
        let key = descriptor.sessionKey
        let session = session(for: key)
        guard let located = workspace.vaults.lazy.compactMap({ vault -> (WorkspaceVaultSnapshot, WorkspaceNoteSnapshot)? in
            guard vault.vault.id == key.vaultID,
                  let note = vault.documents.first(where: {
                      $0.stableIdentity.resolvedID == key.noteID
                  }) else { return nil }
            return (vault, note)
        }).first else {
            if session.isEditing || session.hasUnsavedChanges {
                session.autosaveTask?.cancel()
                session.autosaveTask = nil
                session.conflict = nil
                session.canRetrySave = false
                let message = "The note was deleted outside Scholium. Its exact editor buffer remains open for recovery."
                session.editError = message
                setSaveError(message)
            }
            return
        }

        let (vault, note) = located
        snapshots[key] = note
        updateDocumentProjection(WindowDocumentDescriptor(
            sessionKey: key,
            reference: VaultNoteReference(
                vaultID: vault.vault.id,
                vaultName: vault.vault.name,
                vaultRole: vault.vault.role,
                relativePath: note.id.relativePath,
                stableNoteID: key.noteID.uuidString
            )
        ))
        reconcile(session: session, with: note)
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
        guard !session.isSavingEdit else { return }

        if session.hasUnsavedChanges {
            session.autosaveTask?.cancel()
            session.autosaveTask = nil
            session.conflict = DocumentConflictSnapshot(
                relativePath: snapshot.id.relativePath,
                editorSource: session.editingSource,
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
        if editingDocumentPath == snapshot.id.relativePath {
            editingDocumentPath = nil
        }
        session.suppressAutosave = false
        if session.editorSession.isLoaded {
            session.editorSession.loadDocument(
                diskSource,
                documentID: session.editorSession.bridgeDocumentID,
                mode: session.retainedEditorMode
            )
        }
    }

}

enum DocumentControllerError: LocalizedError, Equatable {
    case saveFailed(String)
    case editorUnavailable
    case changedDuringSave
    case deltaMirrorMismatch
    case documentUnavailable

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            String(localized: "Scholium kept the current editor open because it could not safely save this note. \(message)", table: "Localizable", bundle: .module)
        case .editorUnavailable:
            String(localized: "Scholium kept the current editor open because it could not retrieve the complete Markdown buffer.", table: "Localizable", bundle: .module)
        case .changedDuringSave:
            String(localized: "Scholium kept the current editor open because the note continued changing while it was being saved.", table: "Localizable", bundle: .module)
        case .deltaMirrorMismatch:
            String(localized: "Scholium kept the current editor open because an editor update did not reach the autosave mirror. The complete editor buffer was recovered; retry the save.", table: "Localizable", bundle: .module)
        case .documentUnavailable:
            String(localized: "Scholium kept the exact editor buffer open because this document is no longer available through the active Triptych.", table: "Localizable", bundle: .module)
        }
    }

}
