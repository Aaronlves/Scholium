import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat native draft sessions", .serialized)
@MainActor
struct AgentChatComposerSessionTests {
    @Test("Leaving and remounting a draft retains its native selection and typing Undo")
    func remountRetainsNativeEditing() async throws {
        _ = NSApplication.shared
        let conversationID = UUID()
        let session = AgentChatComposerSession(conversationID: conversationID)
        var draft = "Retained 中文 draft."
        var focused = false
        func input() -> some View {
            AgentChatComposerInput(
                text: Binding(get: { draft }, set: { draft = $0 }),
                isFocused: Binding(get: { focused }, set: { focused = $0 }),
                nativeSession: session,
                readCurrentDraft: { draft },
                isEnabled: true, submit: {})
        }
        let host = NSHostingView(rootView: AnyView(input()))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { session.host.window === window && session.host.editor.isEditable }
        let editor = session.host.editor
        let undo = try #require(editor.undoManager)
        let original = draft
        undo.beginUndoGrouping()
        editor.insertText(" Added 😀", replacementRange: NSRange(location: original.utf16.count, length: 0))
        undo.endUndoGrouping()
        editor.breakUndoCoalescing()
        editor.setSelectedRange(NSRange(location: 2, length: 5))
        let selection = editor.selectedRange()
        try #require(undo.canUndo && draft == original + " Added 😀")

        host.rootView = AnyView(Color.clear)
        try await settle(host) { session.host.window == nil }
        #expect(editor.onSubmit == nil && editor.onTransferMaterials == nil)
        host.rootView = AnyView(input())
        try await settle(host) { session.host.window === window && editor.isEditable }
        #expect(session.host.editor === editor)
        #expect(editor.selectedRange() == selection)
        #expect(editor.undoManager === undo && undo.canUndo)
        undo.undo()
        #expect(editor.string == original && draft == original)
    }

    @Test("An externally replaced draft invalidates retained typing Undo while the native session stays stable")
    func externalReplacementResetsRetainedUndo() async throws {
        _ = NSApplication.shared
        let conversationID = UUID()
        let session = AgentChatComposerSession(conversationID: conversationID)
        var draft = "Before sending"
        func input() -> some View {
            AgentChatComposerInput(
                text: Binding(get: { draft }, set: { draft = $0 }), isFocused: .constant(false),
                nativeSession: session, readCurrentDraft: { draft }, isEnabled: true, submit: {})
        }
        let host = NSHostingView(rootView: AnyView(input()))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { session.host.window === window && session.host.editor.isEditable }
        let editor = session.host.editor
        let undo = try #require(editor.undoManager)
        undo.beginUndoGrouping()
        editor.insertText(" extra", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        undo.endUndoGrouping()
        editor.breakUndoCoalescing()
        try #require(undo.canUndo)
        host.rootView = AnyView(Color.clear)
        try await settle(host) { session.host.window == nil }
        // Sending in another window or external draft replacement has one model
        // authority. Cached native ranges must not restore the old input.
        draft = ""
        host.rootView = AnyView(input())
        try await settle(host) { session.host.window === window && editor.isEditable && editor.string.isEmpty }
        #expect(session.host.editor === editor && !undo.canUndo && !undo.canRedo)
        undo.beginUndoGrouping()
        editor.insertText("New draft", replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        editor.breakUndoCoalescing()
        #expect(undo.canUndo)
        undo.undo()
        #expect(editor.string.isEmpty && draft.isEmpty)
    }

    @Test("Late outgoing teardown cannot clear the incoming native draft binding or completion")
    func retiredMountCannotDetachNewInput() throws {
        _ = NSApplication.shared
        let conversationID = UUID()
        let session = AgentChatComposerSession(conversationID: conversationID)
        let firstMount = AgentChatComposerMountView(session: session)
        var oldDraft = ""
        session.host.onEdit = { oldDraft = $0 }
        session.host.editor.string = "尚未发布的拼音 pin"
        session.host.editor.setMarkedText(
            "yin", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: session.host.editor.string.utf16.count, length: 0))
        let retained = session.host.editor.string
        let secondMount = AgentChatComposerMountView(session: session)
        #expect(oldDraft == retained)
        #expect(!session.host.editor.hasMarkedText())
        #expect(firstMount.isRetired && session.host.superview === secondMount)

        let completion = AgentChatComposerCompletion()
        completion.attach(to: session.host.editor, in: conversationID)
        session.host.completion = completion
        var newDraft = ""
        var deliveries = 0
        session.host.onEdit = { newDraft = $0 }
        session.host.editor.onSubmit = { deliveries += 1 }
        session.host.focusValue = true
        firstMount.detach()
        firstMount.install(session)
        session.host.editor.string = "Current input"
        session.host.commitCurrentDraft()
        session.host.editor.onSubmit?()
        #expect(newDraft == "Current input" && oldDraft == retained)
        #expect(deliveries == 1 && session.host.completion === completion && session.host.focusValue)
        #expect(session.host.superview === secondMount)
        secondMount.detach()
    }

    @Test("Unpublished preedit survives an external draft replacement without overwriting the new model")
    func externalReplacementPreservesUnpublishedComposition() async throws {
        _ = NSApplication.shared
        let session = AgentChatComposerSession(conversationID: UUID())
        var draft = "Original draft "
        func input() -> some View {
            AgentChatComposerInput(
                text: Binding(get: { draft }, set: { draft = $0 }), isFocused: .constant(false),
                nativeSession: session, readCurrentDraft: { draft }, isEnabled: true, submit: {})
        }
        let host = NSHostingView(rootView: AnyView(input()))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { session.host.window === window && session.host.editor.isEditable }
        let editor = session.host.editor
        editor.setMarkedText(
            "pin", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        session.host.commitCurrentDraft()
        try #require(editor.hasMarkedText())
        draft = "Replacement from another window"
        host.rootView = AnyView(input())
        host.layoutSubtreeIfNeeded()
        // An input-service edit may precede its textDidChange notification.
        // Detachment must compare the captured model rather than publish this
        // older preedit over an intervening model replacement.
        editor.textStorage?.replaceCharacters(in: editor.markedRange(), with: "拼音")
        let unpublished = editor.string
        host.rootView = AnyView(Color.clear)
        try await settle(host) { session.host.window == nil }
        #expect(draft == "Replacement from another window")
        #expect(session.retainedInputs == [unpublished])
        #expect(!editor.hasMarkedText())
        host.rootView = AnyView(input())
        try await settle(host) { session.host.window === window && editor.string == draft }
        #expect(session.retainedInputs == [unpublished])
        #expect(editor.undoManager?.canUndo == false)
    }

    @Test("Successive external replacements keep every distinct unpublished preedit until its explicit discard")
    func successiveReplacementsPreserveEarlierInput() async throws {
        _ = NSApplication.shared
        let session = AgentChatComposerSession(conversationID: UUID())
        var draft = "Original draft "
        func input() -> some View {
            AgentChatComposerInput(
                text: Binding(get: { draft }, set: { draft = $0 }), isFocused: .constant(false),
                nativeSession: session, readCurrentDraft: { draft }, isEnabled: true, submit: {})
        }
        let host = NSHostingView(rootView: AnyView(input()))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { session.host.window === window && session.host.editor.isEditable }
        let editor = session.host.editor
        var snapshots: [String] = []
        for (index, preedit) in ["第一份未发布输入", "第二份未发布输入"].enumerated() {
            editor.setMarkedText(
                "pin", selectedRange: NSRange(location: 3, length: 0),
                replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            session.host.commitCurrentDraft()
            try #require(editor.hasMarkedText())
            let replacement = "Replacement \(index + 1) from another window"
            draft = replacement
            host.rootView = AnyView(input())
            host.layoutSubtreeIfNeeded()
            editor.textStorage?.replaceCharacters(in: editor.markedRange(), with: preedit)
            snapshots.append(editor.string)
            host.rootView = AnyView(Color.clear)
            try await settle(host) { session.host.window == nil }
            #expect(draft == replacement && session.retainedInputs == snapshots)
            host.rootView = AnyView(input())
            try await settle(host) { session.host.window === window && editor.isEditable && editor.string == replacement }
            #expect(session.retainedInputs == snapshots)
        }
        try #require(snapshots.count == 2 && snapshots[0] != snapshots[1])
        // Repeated commit/unmark notifications retain one copy of the same
        // complete text. Discard addresses one snapshot, never its neighbours.
        session.retainInput(snapshots[0])
        session.retainInput(snapshots[1])
        #expect(session.retainedInputs == snapshots)
        session.discardRetainedInput(snapshots[0])
        #expect(session.retainedInputs == [snapshots[1]])
        #expect(draft == "Replacement 2 from another window")
        session.discardRetainedInput(snapshots[1])
        #expect(session.retainedInputs.isEmpty)
    }

    @Test("Conversation sessions isolate native editing between conversations and windows")
    func storesIsolateConversationAndWindowEditing() throws {
        _ = NSApplication.shared
        let firstWindow = AgentChatComposerSessionStore()
        let secondWindow = AgentChatComposerSessionStore()
        let firstID = UUID()
        let secondID = UUID()
        let first = firstWindow.session(for: firstID)
        let second = firstWindow.session(for: secondID)
        let otherWindow = secondWindow.session(for: firstID)
        #expect(first !== second && first !== otherWindow)
        #expect(firstWindow.session(for: firstID) === first)
        first.host.editor.replaceDraft("First", selection: NSRange(location: 1, length: 2))
        second.host.editor.replaceDraft("第二个", selection: NSRange(location: 0, length: 1))
        let undo = try #require(first.host.editor.undoManager)
        undo.beginUndoGrouping()
        first.host.editor.insertText(" edit", replacementRange: NSRange(location: 5, length: 0))
        undo.endUndoGrouping()
        first.host.editor.breakUndoCoalescing()
        #expect(second.host.editor.string == "第二个" && otherWindow.host.editor.string.isEmpty)
        #expect(second.host.editor.undoManager?.canUndo == false && otherWindow.host.editor.undoManager?.canUndo == false)
        undo.undo()
        #expect(first.host.editor.string == "First")
        firstWindow.retain([secondID])
        #expect(firstWindow.session(for: firstID) !== first)
    }

    @Test("Find returns to its native initiator and ignores hidden, departed or another-window targets")
    func findRestoresOnlyValidOrigin() throws {
        _ = NSApplication.shared
        let first = NSTextField(string: "Original input")
        let second = NSTextField(string: "Find query")
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        first.frame = NSRect(x: 10, y: 60, width: 280, height: 24)
        second.frame = NSRect(x: 10, y: 20, width: 280, height: 24)
        content.addSubview(first)
        content.addSubview(second)
        let window = mount(content)
        let another = mount(NSView())
        defer {
            window.contentView = nil
            window.close()
            another.close()
        }
        try #require(window.makeFirstResponder(first))
        let origin = AgentChatFindReturnFocus(window: window)
        try #require(window.makeFirstResponder(second))
        #expect(!origin.restore(in: another))
        #expect(origin.restore(in: window))
        #expect(window.firstResponder === first.currentEditor())
        first.isHidden = true
        #expect(!origin.restore(in: window))
        first.isHidden = false
        first.removeFromSuperview()
        #expect(!origin.restore(in: window))
    }

    @Test("A constrained native editor keeps one full line and scrolls its retained draft")
    func constrainedEditorRetainsScrollableContent() throws {
        _ = NSApplication.shared
        let host = AgentChatComposerHost()
        host.editor.string = String(repeating: "Long draft with 中文 and English.\n", count: 30)
        let selection = NSRange(location: 3, length: 8)
        host.editor.setSelectedRange(selection)
        let natural = host.fittingHeight(width: 300)
        let constrained = host.fittingHeight(width: 300, maximumHeight: 55)
        #expect(constrained <= 55 && constrained < natural)
        let minimum = host.fittingHeight(width: 300, maximumHeight: 0)
        let font = try #require(host.editor.font)
        let line = try #require(host.editor.layoutManager).defaultLineHeight(for: font)
        #expect(minimum >= line + 2 * host.editor.textContainerInset.height)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: constrained)
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        #expect(host.editor.frame.height > host.contentSize.height)
        #expect(host.editor.selectedRange() == selection)
        #expect(host.editor.string.contains("中文") && host.hasVerticalScroller)
    }

    private func mount(_ host: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func settle(_ host: NSView, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try #require(ContinuousClock.now < deadline, "Native draft session did not reach its expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
