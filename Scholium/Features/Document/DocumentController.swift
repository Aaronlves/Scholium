import ScholiumContracts
import Combine
import Foundation

/// Stable session identity plus the current path/title projection used by a
/// single window. Renames replace `reference` while retaining `sessionKey`.
struct WindowDocumentDescriptor: Hashable, Sendable {
    let sessionKey: DocumentSessionKey
    let reference: VaultNoteReference
}

/// Immutable delivery-layer address for one editor session. Workspace notes
/// follow stable identity through renames; portable Unclassified documents
/// remain path-addressed because they intentionally have no vault identity.
enum DocumentEditingTarget: Hashable, Sendable {
    case workspace(DocumentSessionKey)
    case unclassified(relativePath: String)
    case unavailable(relativePath: String)
}

/// Per-window owner for tabs and document/editor sessions. Repository writes,
/// lifecycle transactions, and conflict recovery remain Application calls;
/// this controller owns only window and editor-session state.
@MainActor
final class DocumentController: ObservableObject {
    typealias IntentHandler = @MainActor (WindowIntent) -> Void
    typealias DocumentCommitHandler = @MainActor (NoteDocument) async -> Void
    typealias SaveErrorHandler = @MainActor (String?) -> Void

    @Published private(set) var openDocuments: [WindowDocumentDescriptor] = []
    @Published private(set) var activeDocumentKey: DocumentSessionKey?
    @Published private(set) var snapshots: [DocumentSessionKey: WorkspaceNoteSnapshot] = [:]
    @Published private(set) var editingDocumentPath: String?
    @Published private(set) var lastSaveError: String?

    private let sessions = DocumentSessionStore()
    private let intentHandler: IntentHandler
    private var operations: (any DocumentUseCases)?
    private var sessionCancellables: [ObjectIdentifier: AnyCancellable] = [:]
    private var documentDidCommit: DocumentCommitHandler = { _ in }
    private var saveErrorDidChange: SaveErrorHandler = { _ in }

    init(intentHandler: @escaping IntentHandler = { _ in }) {
        self.intentHandler = intentHandler
    }

    var activeDocument: WindowDocumentDescriptor? {
        guard let activeDocumentKey else { return nil }
        return openDocuments.first(where: { $0.sessionKey == activeDocumentKey })
    }

    var activeSnapshot: WorkspaceNoteSnapshot? {
        guard let activeDocumentKey else { return nil }
        return snapshots[activeDocumentKey]
    }

    /// Binds this window-local controller to capabilities selected by the one
    /// app-wide WorkspaceStore subscription. Rebinding never replaces editor
    /// sessions or another window's presentation state.
    func bind(
        to operations: any DocumentUseCases,
        snapshot: WorkspaceSnapshot? = nil,
        documentDidCommit: @escaping DocumentCommitHandler = { _ in },
        saveErrorDidChange: @escaping SaveErrorHandler = { _ in }
    ) {
        self.operations = operations
        self.documentDidCommit = documentDidCommit
        self.saveErrorDidChange = saveErrorDidChange
        if let snapshot { receive(snapshot) }
    }

    func unbind() {
        operations = nil
        documentDidCommit = { _ in }
        saveErrorDidChange = { _ in }
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
        let session = sessions.session(for: key)
        observe(session)
        return session
    }

    func retainedSession(for key: DocumentSessionKey) -> DocumentSessionModel? {
        guard let session = sessions.retainedSession(for: key) else { return nil }
        observe(session)
        return session
    }

    /// Makes one controller the observable boundary even when a temporary
    /// path-addressed fallback session is required during identity recovery.
    func observe(_ session: DocumentSessionModel) {
        let identifier = ObjectIdentifier(session)
        guard sessionCancellables[identifier] == nil else { return }
        sessionCancellables[identifier] = session.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Installs a document after the owning WindowModel has resolved an
    /// `openDocument` intent through Application and obtained its stable ID.
    func installOpenedDocument(
        _ descriptor: WindowDocumentDescriptor,
        inNewTab: Bool
    ) {
        if let existingIndex = openDocuments.firstIndex(where: {
            $0.sessionKey == descriptor.sessionKey
        }) {
            openDocuments[existingIndex] = descriptor
            activeDocumentKey = descriptor.sessionKey
            return
        }

        if inNewTab || openDocuments.isEmpty {
            openDocuments.append(descriptor)
        } else if let activeDocumentKey,
                  let activeIndex = openDocuments.firstIndex(where: {
                      $0.sessionKey == activeDocumentKey
                  }) {
            openDocuments[activeIndex] = descriptor
        } else {
            openDocuments = [descriptor]
        }
        activeDocumentKey = descriptor.sessionKey
        _ = session(for: descriptor.sessionKey)
    }

    /// Installs the immutable Application read model and initializes this
    /// window's editor session from its exact source bytes.
    func installOpenedDocument(
        _ snapshot: WorkspaceNoteSnapshot,
        vaultName: String,
        vaultRole: VaultRole,
        inNewTab: Bool
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
        installOpenedDocument(descriptor, inNewTab: inNewTab)
        snapshots[key] = snapshot
        reconcile(session: session(for: key), with: snapshot)
    }

    func activateDocument(_ key: DocumentSessionKey) {
        guard openDocuments.contains(where: { $0.sessionKey == key }) else { return }
        activeDocumentKey = key
    }

    /// Updates mutable path and title projections without replacing the
    /// document session, editor buffer, undo bridge, or conflict state.
    func updateDocumentProjection(_ descriptor: WindowDocumentDescriptor) {
        guard let index = openDocuments.firstIndex(where: {
            $0.sessionKey == descriptor.sessionKey
        }) else { return }
        openDocuments[index] = descriptor
    }

    func closeDocument(_ key: DocumentSessionKey) {
        guard let index = openDocuments.firstIndex(where: { $0.sessionKey == key }) else { return }
        let wasActive = activeDocumentKey == key
        openDocuments.remove(at: index)
        snapshots[key] = nil
        if let session = sessions.retainedSession(for: key) {
            sessionCancellables[ObjectIdentifier(session)] = nil
        }
        sessions.removeSession(for: key)
        if wasActive {
            let replacementIndex = min(index, openDocuments.count - 1)
            activeDocumentKey = replacementIndex >= 0
                ? openDocuments[replacementIndex].sessionKey
                : nil
        }
    }

    func requestOpen(_ route: WindowDocumentRoute) {
        intentHandler(.openDocument(route))
    }

    func requestLifecycle(_ request: NoteLifecycleRequest) {
        intentHandler(.presentLifecycle(request))
    }

    func removeAll() {
        sessions.removeAll()
        sessionCancellables.removeAll()
        openDocuments = []
        activeDocumentKey = nil
        snapshots = [:]
        editingDocumentPath = nil
        lastSaveError = nil
    }

    func relativePath(for target: DocumentEditingTarget) -> String {
        switch target {
        case .workspace(let key):
            openDocuments.first(where: { $0.sessionKey == key })?.reference.relativePath
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
        session.editingSource = ""
        session.originalEditingSource = ""
        session.editingRevision = nil
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
            guard !session.hasUnsavedChanges else {
                throw DocumentControllerError.editorUnavailable
            }
            return .clean
        }
        guard let revision = session.editingRevision else {
            throw DocumentControllerError.saveFailed(
                "The editing revision is unavailable. Return to Read mode and reopen the editor."
            )
        }

        let sourceBeingSaved = try await session.editorSession.currentText(for: path)
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
            documentID: path
        )
        if synchronized {
            session.editingSource = saved.rawContent
            if editingDocumentPath == path { editingDocumentPath = nil }
            return committedRefreshFailure.map(EditorSaveOutcome.committedWithRefreshFailure)
                ?? .clean
        }

        session.editingSource = try await session.editorSession.currentText(for: path)
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

    private func setSaveError(_ message: String?) {
        lastSaveError = message
        saveErrorDidChange(message)
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
        for descriptor in openDocuments {
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
                continue
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
                documentID: snapshot.id.relativePath,
                mode: session.presentationMode
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
            "Scholium kept the current editor open because it could not safely save this note. \(message)"
        case .editorUnavailable:
            "Scholium kept the current editor open because it could not retrieve the complete Markdown buffer."
        case .changedDuringSave:
            "Scholium kept the current editor open because the note continued changing while it was being saved."
        case .deltaMirrorMismatch:
            "Scholium kept the current editor open because an editor update did not reach the autosave mirror. The complete editor buffer was recovered; retry the save."
        case .documentUnavailable:
            "Scholium kept the exact editor buffer open because this document is no longer available through the active Triptych."
        }
    }
}
