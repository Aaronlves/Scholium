import AppKit
import Observation

/// The controller owns draft text. A window-local conversation session retains
/// native selection, TextKit and Undo; a disposable mount gives that host its
/// allocated rectangle. The representable only projects text and explicit focus
/// intents, and detachment publishes through the captured conversation binding.
@MainActor @Observable
final class AgentChatComposerSession {
    let conversationID: UUID?
    let host = AgentChatComposerHost()
    private(set) var retainedInputs: [String] = []
    @ObservationIgnored fileprivate weak var mount: AgentChatComposerMountView?

    init(conversationID: UUID?) { self.conversationID = conversationID }

    func retainInput(_ text: String) {
        guard !retainedInputs.contains(text) else { return }
        retainedInputs.append(text)
    }

    func discardRetainedInput(_ text: String) {
        retainedInputs.removeAll { $0 == text }
    }
}

@MainActor
final class AgentChatComposerSessionStore {
    private var sessions: [UUID: AgentChatComposerSession] = [:]
    private let empty = AgentChatComposerSession(conversationID: nil)

    func session(for id: UUID?) -> AgentChatComposerSession {
        guard let id else { return empty }
        if let session = sessions[id] { return session }
        let session = AgentChatComposerSession(conversationID: id)
        sessions[id] = session
        return session
    }

    func retain(_ ids: Set<UUID>) {
        sessions = sessions.filter { ids.contains($0.key) }
    }
}

/// Only the native editing host survives page removal. Its previous mount is
/// retired before reuse, so outgoing SwiftUI updates or teardown cannot detach
/// the newly mounted input. Cached inputs have no responder or delivery route.
@MainActor
final class AgentChatComposerMountView: NSView {
    private(set) var session: AgentChatComposerSession?
    private(set) var isRetired = false

    init(session: AgentChatComposerSession) {
        super.init(frame: .zero)
        install(session)
    }

    required init?(coder: NSCoder) { nil }

    func install(_ session: AgentChatComposerSession) {
        guard !isRetired, self.session !== session else { return }
        detach(retiring: false)
        session.mount?.detach()
        self.session = session
        session.mount = self
        let host = session.host
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }

    func detach(retiring: Bool = true) {
        if retiring { isRetired = true }
        guard let session else { return }
        self.session = nil
        guard session.mount === self else { return }
        session.host.suspend()
        session.host.removeFromSuperview()
        session.mount = nil
    }
}

/// Find remembers the native initiating control, rather than inventing a new
/// default reading target. Invalid, departed or hidden targets receive no focus.
@MainActor
final class AgentChatFindReturnFocus {
    private weak var window: NSWindow?
    private weak var target: NSResponder?

    init(window: NSWindow) {
        self.window = window
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor {
            target = editor.delegate as? NSResponder
        } else {
            target = window.firstResponder
        }
    }

    func restore(in currentWindow: NSWindow?) -> Bool {
        guard let window, window === currentWindow, let target,
            let view = target as? NSView, view.window === window,
            !view.isHiddenOrHasHiddenAncestor,
            (view as? NSControl)?.isEnabled != false,
            (view as? NSTextView)?.isSelectable != false
        else { return false }
        return window.makeFirstResponder(target)
    }

    func targets(_ responder: NSResponder) -> Bool { target === responder }
}
