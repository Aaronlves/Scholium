import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Native chat input") @MainActor
struct AgentChatComposerInputTests {
    @Test("Sizing probes preserve the live editor geometry and selection while measuring wrapping")
    func measurementDoesNotResizeEditor() {
        let host = AgentChatComposerHost()
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 60)
        host.editor.string = String(repeating: "中文 selection 😀 ", count: 8)
        host.layoutSubtreeIfNeeded()
        host.editor.setSelectedRange(NSRange(location: 3, length: 9))
        let frame = host.editor.frame
        let container = host.editor.textContainer?.containerSize
        let selection = host.editor.selectedRange()
        let wide = host.fittingHeight(width: 10_000)
        #expect(host.editor.frame == frame && host.editor.textContainer?.containerSize == container)
        let narrow = host.fittingHeight(width: 240)
        #expect(narrow > wide)
        #expect(host.editor.frame == frame && host.editor.textContainer?.containerSize == container)
        #expect(host.editor.selectedRange() == selection)
    }

    @Test("Completion queries distinguish commands from email, paths, currency and marked text")
    func completionQueries() {
        func query(_ text: String) -> AgentChatComposerQuery? {
            .read(text: text, selection: NSRange(location: text.utf16.count, length: 0), isComposing: false)
        }
        #expect(query("email@example.org") == nil)
        #expect(query("/Users/me") == nil)
        #expect(query("value $ 100") == nil)
        let current = query("中文 😀 @论证")
        #expect(current?.trigger == "@" && current?.text == "论证")
        #expect(current?.range == NSRange(location: 6, length: 3))
        #expect(AgentChatComposerQuery.read(text: "$method", selection: NSRange(location: 7, length: 0), isComposing: true) == nil)
        #expect(AgentChatComposerQuery.read(text: "$method", selection: NSRange(location: 2, length: 2), isComposing: false) == nil)
    }

    @Test("Completion replaces only its native range, supports Undo, and rejects another conversation")
    func completionReplacement() throws {
        let host = AgentChatComposerHost()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let id = UUID()
        let completion = AgentChatComposerCompletion()
        host.conversationID = id
        host.editor.completionConversationID = id
        host.completion = completion
        host.editor.string = "中文 😀 @论证 后文"
        host.editor.setSelectedRange(NSRange(location: 9, length: 0))
        completion.refresh(from: host.editor, in: id)
        let candidate = AgentChatComposerCandidate(id: "note", title: "论证", detail: "", symbol: "doc", action: .notePicker)
        var choices = 0
        completion.choose = { _ in choices += 1 }
        completion.candidates = [candidate]
        completion.accept(candidate)
        #expect(choices == 0 && host.editor.string == "中文 😀 @论证 后文")
        completion.candidateQuery = completion.query
        completion.accept(candidate)
        #expect(host.editor.string == "中文 😀  后文" && choices == 1)
        let undo = try #require(host.editor.undoManager)
        undo.undo()
        #expect(host.editor.string == "中文 😀 @论证 后文")
        host.editor.setSelectedRange(NSRange(location: 9, length: 0))
        completion.refresh(from: host.editor, in: id)
        host.editor.completionConversationID = UUID()
        completion.accept(candidate)
        #expect(choices == 1 && host.editor.string == "中文 😀 @论证 后文")
        host.editor.completionConversationID = id
        completion.dismiss()
        completion.refresh(from: host.editor, in: id)
        #expect(completion.query == nil)
        completion.detach(from: AgentChatComposerTextView(frame: .zero))
        #expect(completion.editor === host.editor && completion.choose != nil)
        completion.detach(from: host.editor)
        #expect(completion.editor == nil && completion.choose == nil && completion.candidates.isEmpty)
    }

    private func event(_ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    }

    @Test("Image paste captures material without editing text; file references outrank icon data")
    func materialPaste() throws {
        let pasteboard = NSPasteboard(name: .init("scholium.clipboard-fixture.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let host = AgentChatComposerHost()
        host.editor.string = "Keep 中文 😀"
        host.editor.setSelectedRange(NSRange(location: 5, length: 2))
        let selection = host.editor.selectedRange()
        var received: [AgentChatTransferredMaterial] = []
        host.editor.onTransferMaterials = { values, _ in received = values }
        let item = NSPasteboardItem()
        item.setData(Data([1, 2, 3]), forType: .png)
        #expect(pasteboard.writeObjects([item]))
        #expect(host.editor.captureMaterials(from: pasteboard, origin: .clipboard))
        #expect(host.editor.string == "Keep 中文 😀" && host.editor.selectedRange() == selection)
        pasteboard.clearContents()
        guard case .image(let captured) = received.first else {
            Issue.record("Clipboard image was not captured")
            return
        }
        #expect(captured == Data([1, 2, 3]))
        let file = NSPasteboardItem()
        file.setString("file:///fixture/paper.pdf", forType: .fileURL)
        file.setData(Data([4, 5, 6]), forType: .png)
        #expect(pasteboard.writeObjects([file]))
        #expect(host.editor.captureMaterials(from: pasteboard, origin: .clipboard))
        guard case .file(let url) = received.first else {
            Issue.record("File icon replaced the file reference")
            return
        }
        #expect(url.path == "/fixture/paper.pdf" && received.count == 1)
        pasteboard.clearContents()
        #expect(pasteboard.setString("ordinary paste", forType: .string))
        #expect(!host.editor.captureMaterials(from: pasteboard, origin: .clipboard))
        host.editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        pasteboard.clearContents()
        #expect(pasteboard.setData(Data([1]), forType: .png))
        #expect(!host.editor.captureMaterials(from: pasteboard, origin: .clipboard) && host.editor.hasMarkedText())
    }

    @Test("Image drop waits for acceptance, preserves text Undo, and rejects move-only or composing input")
    func materialDrop() throws {
        let pasteboard = NSPasteboard(name: .init("scholium.drop-fixture.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let provider = DragImageProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png])
        #expect(pasteboard.writeObjects([item]))
        let drag = MaterialDraggingInfo(pasteboard)
        let host = AgentChatComposerHost()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.editor.string = "Keep 中文"
        host.editor.insertText(" 😀", replacementRange: NSRange(location: 7, length: 0))
        host.editor.setSelectedRange(NSRange(location: 5, length: 2))
        let text = host.editor.string
        let selection = host.editor.selectedRange()
        let undo = try #require(host.editor.undoManager)
        let undoName = undo.undoActionName
        #expect(undo.canUndo)
        var received: [AgentChatTransferredMaterial] = []
        var origins: [AgentChatLocalMaterial.CaptureOrigin] = []
        host.editor.onTransferMaterials = { values, origin in
            received = values
            origins.append(origin)
        }
        host.editor.isEditable = false
        host.editor.isEditable = true
        #expect(host.editor.registeredDraggedTypes.contains(.png))
        #expect(host.editor.draggingEntered(drag) == .copy)
        #expect(host.editor.draggingUpdated(drag) == .copy)
        #expect(host.editor.prepareForDragOperation(drag))
        #expect(provider.reads == 0 && received.isEmpty)
        #expect(host.editor.performDragOperation(drag))
        host.editor.concludeDragOperation(drag)
        #expect(provider.reads == 1 && origins == [.drop])
        #expect(host.editor.string == text && host.editor.selectedRange() == selection)
        #expect(undo.undoActionName == undoName && undo.canUndo)
        undo.undo()
        #expect(host.editor.string == "Keep 中文")
        pasteboard.clearContents()
        guard case .image(let bytes) = received.first else {
            Issue.record("Dropped image was not captured")
            return
        }
        #expect(bytes == Data([1, 2, 3]))
        #expect(pasteboard.setData(Data([4]), forType: .png))
        drag.draggingSourceOperationMask = .move
        #expect(host.editor.draggingEntered(drag).isEmpty && !host.editor.performDragOperation(drag))
        drag.draggingSourceOperationMask = .copy
        host.editor.isEditable = false
        #expect(host.editor.draggingUpdated(drag).isEmpty && !host.editor.performDragOperation(drag))
        host.editor.isEditable = true
        host.editor.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!host.editor.prepareForDragOperation(drag) && !host.editor.performDragOperation(drag))
        #expect(host.editor.hasMarkedText() && origins == [.drop])
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

private final class DragImageProvider: NSObject, NSPasteboardItemDataProvider {
    var reads = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        reads += 1
        item.setData(Data([1, 2, 3]), forType: type)
    }
}

@MainActor private final class MaterialDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
