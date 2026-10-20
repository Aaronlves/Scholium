import Foundation

/// Researcher-facing modes share one exact document session. Review remains a
/// committed read-only projection; Edit and Source grant editing authority.
enum NotePresentationMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case read
    case livePreview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: ScholiumL10n.string("Review")
        case .livePreview: ScholiumL10n.string("Edit")
        case .source: ScholiumL10n.string("Source")
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .livePreview: "square.and.pencil"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }

    var editorMode: MarkdownEditorMode? {
        switch self {
        case .read: nil
        case .livePreview: .livePreview
        case .source: .source
        }
    }
}

/// The shared CodeMirror host presents committed Review or either writable
/// configuration without replacing its exact-source state or history.
enum MarkdownEditorMode: String, Codable, Hashable, Sendable {
    case review
    case livePreview
    case source

    var presentationMode: NotePresentationMode {
        switch self {
        case .review: .read
        case .livePreview: .livePreview
        case .source: .source
        }
    }
}

/// One atomic value owns Document presentation intent, active editing state,
/// retained editor configuration, and editor-surface allocation. A pending
/// editor intent is deliberately distinct from an active mode: the live
/// Document presentation may prepare a selected session for Source without
/// claiming that Source is already visible or writable.
struct DocumentPresentationState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case review(editorIntent: MarkdownEditorMode?)
        case editing(MarkdownEditorMode)
    }

    private(set) var phase: Phase = .review(editorIntent: nil)
    private(set) var retainedEditorMode: MarkdownEditorMode = .livePreview
    private(set) var retainsEditorSurface = false

    var activeMode: NotePresentationMode {
        switch phase {
        case .review: .read
        case .editing(let mode): mode.presentationMode
        }
    }

    var activeEditorMode: MarkdownEditorMode? {
        guard case .editing(let mode) = phase else { return nil }
        return mode
    }

    var pendingEditorMode: MarkdownEditorMode? {
        guard case .review(let editorIntent) = phase else { return nil }
        return editorIntent
    }

    func pendingPresentationMode(
        editorIsLoaded: Bool,
        acknowledgedEditorMode: MarkdownEditorMode?,
        hasEditorError: Bool
    ) -> NotePresentationMode? {
        guard !hasEditorError else { return nil }
        switch phase {
        case .review(let editorIntent):
            return editorIntent?.presentationMode
        case .editing(let mode):
            guard editorIsLoaded, acknowledgedEditorMode == mode else {
                return mode.presentationMode
            }
            return nil
        }
    }

    var isEditing: Bool { activeEditorMode != nil }

    /// Preparing Edit/Source is not a request to render Review. If that
    /// initial editor cannot load, the existing read-recovery surface still
    /// needs the committed projection. An active editor's error surface owns
    /// its own recovery and does not present Review content.
    func requiresReadProjection(editorIsLoaded: Bool, hasEditorError: Bool) -> Bool {
        switch phase {
        case .review(let editorIntent):
            editorIntent == nil || (!editorIsLoaded && hasEditorError)
        case .editing:
            false
        }
    }

    mutating func prepare(_ mode: NotePresentationMode) {
        guard !isEditing else { return }
        let editorMode = mode.editorMode
        if let editorMode { retainedEditorMode = editorMode }
        phase = .review(editorIntent: editorMode)
    }

    mutating func beginEditing(_ mode: MarkdownEditorMode) {
        guard mode != .review else { return }
        retainedEditorMode = mode
        retainsEditorSurface = true
        phase = .editing(mode)
    }

    mutating func switchEditorMode(to mode: MarkdownEditorMode) {
        guard isEditing, mode != .review else { return }
        retainedEditorMode = mode
        phase = .editing(mode)
    }

    mutating func finishEditing() {
        phase = .review(editorIntent: nil)
    }

    mutating func reset() {
        phase = .review(editorIntent: nil)
        retainedEditorMode = .livePreview
    }
}
