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

struct ObservedScrollPosition: Equatable, Sendable {
    var fraction: Double
    var anchor: EditorScrollAnchor?

    init(fraction: Double = 0, anchor: EditorScrollAnchor? = nil) {
        self.fraction = Self.normalized(fraction)
        self.anchor = anchor
    }

    mutating func updateFraction(_ value: Double) {
        guard value.isFinite else { return }
        fraction = Self.normalized(value)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum ScrollRestoreReason: String, Equatable, Sendable {
    case documentLoad
    case modeHandoff
    case webViewRebuild
    case explicitNavigation
}

struct ScrollRestoreRequest: Equatable, Sendable {
    let id: UInt64
    let fingerprint: String
    let position: ObservedScrollPosition
    let reason: ScrollRestoreReason
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
    /// Once created for the selected document, the editor surface remains
    /// attached while Read is presented. This preserves CodeMirror state
    /// across ordinary mode switches without eagerly allocating a WebKit
    /// editor for every document that is only read.
    @Published var retainsEditorSurface = false
    @Published var retainedEditorMode: NotePresentationMode = .livePreview
    @Published var editingSource = ""
    @Published var originalEditingSource = ""
    @Published var editingRevision: DocumentFingerprint?
    @Published var editError: String?
    @Published var isSavingEdit = false
    @Published var presentationMode: NotePresentationMode = .read
    /// Ordinary WebView scroll reports update this non-published observation.
    /// They must not invalidate the document tree or become restoration input.
    private(set) var observedScrollPosition = ObservedScrollPosition()
    /// Only an explicit lifecycle or navigation transition creates a request.
    /// Coordinators consume each monotonically increasing ID at most once.
    @Published private(set) var scrollRestoreRequest: ScrollRestoreRequest?
    @Published var returnToReadAfterSave = false
    @Published var suppressAutosave = false
    @Published var renderedReadHTML = ""
    @Published var renderedReadFingerprint = ""
    @Published var renderedReadReadyFingerprint = ""
    @Published var failedReadFingerprint: String?
    @Published var previewCatalog: DocumentPreviewCatalog?
    var readSelection: MarkdownReviewSelection?
    @Published var conflict: DocumentConflictSnapshot?
    @Published var canRetrySave = false
    @Published var showConflictComparison = false

    var autosaveTask: Task<Void, Never>?
    var activeSaveTask: Task<EditorSaveOutcome, Error>?
    var activeSaveToken: UUID?
    private var editorCancellable: AnyCancellable?
    private var nextScrollRestoreRequestID: UInt64 = 0

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

    var scrollFraction: Double {
        get { observedScrollPosition.fraction }
        set { observedScrollPosition.updateFraction(newValue) }
    }

    var scrollAnchor: EditorScrollAnchor? {
        get { observedScrollPosition.anchor }
        set { observedScrollPosition.anchor = newValue }
    }

    func observeScrollFraction(_ fraction: Double) {
        observedScrollPosition.updateFraction(fraction)
    }

    func observeScrollAnchor(_ anchor: EditorScrollAnchor?) {
        observedScrollPosition.anchor = anchor
    }

    @discardableResult
    func requestScrollRestore(
        fingerprint: String,
        reason: ScrollRestoreReason,
        position: ObservedScrollPosition? = nil
    ) -> ScrollRestoreRequest {
        nextScrollRestoreRequestID &+= 1
        let observed = position ?? observedScrollPosition
        let matchingAnchor = observed.anchor.flatMap { anchor in
            anchor.sourceFingerprint == fingerprint ? anchor : nil
        }
        let request = ScrollRestoreRequest(
            id: nextScrollRestoreRequestID,
            fingerprint: fingerprint,
            position: ObservedScrollPosition(
                fraction: observed.fraction,
                anchor: matchingAnchor
            ),
            reason: reason
        )
        scrollRestoreRequest = request
        return request
    }

    func resetScrollPosition() {
        observedScrollPosition = ObservedScrollPosition()
        scrollRestoreRequest = nil
    }

    func acknowledgeScrollRestoreRequest(id: UInt64, fingerprint: String) {
        guard scrollRestoreRequest?.id == id,
              scrollRestoreRequest?.fingerprint == fingerprint else { return }
        scrollRestoreRequest = nil
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
