import Foundation

/// Researcher-facing Document modes. Review is a committed renderer; Edit and
/// Source are two configurations of the same retained exact-source editor.
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
        case .livePreview: "text.page.badge.magnifyingglass"
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

/// The Web editor has exactly two configurations. Review cannot cross the
/// CodeMirror bridge and therefore cannot become a runtime-rejected mode.
enum MarkdownEditorMode: String, Codable, Hashable, Sendable {
    case livePreview
    case source

    var presentationMode: NotePresentationMode {
        switch self {
        case .livePreview: .livePreview
        case .source: .source
        }
    }
}

/// One atomic value owns Document presentation intent, active editing state,
/// retained editor configuration, and editor-surface allocation. Restored
/// preference is deliberately distinct from an active mode: a session can be
/// awaiting restoration to Source without claiming that Source is visible or
/// writable.
struct DocumentPresentationState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case review(restoration: MarkdownEditorMode?)
        case editing(MarkdownEditorMode)
    }

    private(set) var phase: Phase = .review(restoration: nil)
    private(set) var retainedEditorMode: MarkdownEditorMode = .livePreview
    private(set) var retainsEditorSurface = false

    var activeMode: NotePresentationMode {
        switch phase {
        case .review: .read
        case .editing(let mode): mode.presentationMode
        }
    }

    var selectedMode: NotePresentationMode {
        switch phase {
        case .review(let restoration):
            restoration?.presentationMode ?? .read
        case .editing(let mode):
            mode.presentationMode
        }
    }

    var activeEditorMode: MarkdownEditorMode? {
        guard case .editing(let mode) = phase else { return nil }
        return mode
    }

    var restorationMode: MarkdownEditorMode? {
        guard case .review(let restoration) = phase else { return nil }
        return restoration
    }

    var isEditing: Bool { activeEditorMode != nil }

    mutating func restore(_ mode: NotePresentationMode) {
        guard !isEditing else { return }
        let editorMode = mode.editorMode
        if let editorMode { retainedEditorMode = editorMode }
        phase = .review(restoration: editorMode)
    }

    mutating func beginEditing(_ mode: MarkdownEditorMode) {
        retainedEditorMode = mode
        retainsEditorSurface = true
        phase = .editing(mode)
    }

    mutating func switchEditorMode(to mode: MarkdownEditorMode) {
        guard isEditing else { return }
        retainedEditorMode = mode
        phase = .editing(mode)
    }

    mutating func finishEditing() {
        phase = .review(restoration: nil)
    }

    mutating func reset() {
        phase = .review(restoration: nil)
        retainedEditorMode = .livePreview
    }
}
