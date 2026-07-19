import ScholiumContracts
import Combine
import SwiftUI

/// A document session follows stable vault and note identities. Paths and
/// titles are mutable projections and therefore must never own editor state.
struct DocumentSessionKey: Hashable, Sendable {
    let vaultID: UUID
    let noteID: UUID
}

enum EditorSaveOutcome: Equatable {
    case clean
    case changedDuringSave
    case committedWithRefreshFailure(String)
}

/// The single owner for mutable, reconstruction-sensitive document UI state.
/// The WKWebView remains an implementation detail of `MarkdownEditorSession`;
/// CodeMirror remains authoritative while the session is editing.
@MainActor
final class DocumentSessionModel: ObservableObject {
    let key: DocumentSessionKey?
    let editorSession = MarkdownEditorSession()
    let editorFlushToken = UUID()

    @Published var isEditing = false
    @Published var editingSource = ""
    @Published var originalEditingSource = ""
    @Published var editingRevision: DocumentFingerprint?
    @Published var editError: String?
    @Published var isSavingEdit = false
    @Published var presentationMode: NotePresentationMode = .read
    @Published var scrollFraction: Double = 0
    @Published var returnToReadAfterSave = false
    @Published var suppressAutosave = false
    @Published var renderedReadHTML = ""
    @Published var renderedReadFingerprint = ""
    @Published var failedReadFingerprint: String?
    var readSelection: MarkdownReviewSelection?
    @Published var conflict: DocumentConflictSnapshot?
    @Published var canRetrySave = false
    @Published var showConflictComparison = false

    var autosaveTask: Task<Void, Never>?
    var activeSaveTask: Task<EditorSaveOutcome, Error>?
    var activeSaveToken: UUID?
    private var editorCancellable: AnyCancellable?

    init(key: DocumentSessionKey?) {
        self.key = key
        editorCancellable = editorSession.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    func cancelScheduledWork() {
        autosaveTask?.cancel()
        autosaveTask = nil
        activeSaveTask?.cancel()
        activeSaveTask = nil
        activeSaveToken = nil
    }

    /// A dirty decision must include both the Swift mirror and CodeMirror's
    /// bridge state. Either side can be newer while an editor message is in
    /// flight, so an external publication may replace the buffer only when
    /// both agree that the session is clean.
    var hasUnsavedChanges: Bool {
        editorSession.isDirty || editingSource != originalEditingSource
    }
}

/// Per-window retention for document sessions. `DocumentController` owns one
/// store, so two windows cannot share editor buffers, undo histories, focus,
/// or saves.
@MainActor
final class DocumentSessionStore {
    private var sessions: [DocumentSessionKey: DocumentSessionModel] = [:]

    var retainedSessions: [DocumentSessionKey: DocumentSessionModel] {
        sessions
    }

    func session(for key: DocumentSessionKey) -> DocumentSessionModel {
        if let existing = sessions[key] { return existing }
        let session = DocumentSessionModel(key: key)
        sessions[key] = session
        return session
    }

    func retainedSession(for key: DocumentSessionKey) -> DocumentSessionModel? {
        sessions[key]
    }

    func removeAll() {
        sessions.values.forEach { $0.cancelScheduledWork() }
        sessions.removeAll()
    }
}
