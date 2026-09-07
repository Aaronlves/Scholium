import AppKit
import Testing
@testable import ScholiumApp

@Suite("Native chat input") @MainActor
struct AgentChatComposerInputTests {
    private func event(_ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    }

    @Test("Return submits once, while Shift-Return edits natively without selecting the draft")
    func returnAndLineBreak() throws {
        let host = AgentChatComposerHost()
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        host.editor.string = "中文 😀"
        host.editor.setSelectedRange(NSRange(location: (host.editor.string as NSString).length, length: 0))
        var submits = 0
        host.editor.onSubmit = { submits += 1 }
        host.editor.keyDown(with: try event(.shift))
        #expect(host.editor.string == "中文 😀\n")
        #expect(submits == 0)
        #expect(host.editor.selectedRange().length == 0)
        host.editor.keyDown(with: try event())
        #expect(submits == 1 && host.editor.string == "中文 😀\n")
        #expect(host.editor.selectedRange().length == 0)
        host.editor.onSubmit = nil
        host.editor.keyDown(with: try event())
        #expect(host.editor.selectedRange().length == 0 && host.editor.string == "中文 😀\n")
    }

    @Test("Input whitespace belongs to NSTextView and native wrapping grows the input")
    func inputGeometry() {
        let host = AgentChatComposerHost()
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        host.editor.string = "short"
        host.layoutSubtreeIfNeeded()
        let point = host.editor.convert(NSPoint(x: 250, y: 24), from: host)
        #expect(host.editor.bounds.contains(point))
        let shortHeight = host.fittingHeight(width: 300)
        host.editor.string = String(repeating: "中文 long message ", count: 20)
        let longHeight = host.fittingHeight(width: 300)
        #expect(longHeight > shortHeight)
        #expect(longHeight < 200)
    }

    @Test("Marked text Return is left to the native input method and cannot call Send")
    func markedText() throws {
        let host = AgentChatComposerHost()
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        var submits = 0
        host.editor.onSubmit = { submits += 1 }
        host.editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(host.editor.hasMarkedText())
        host.editor.keyDown(with: try event())
        #expect(submits == 0)
    }
}
