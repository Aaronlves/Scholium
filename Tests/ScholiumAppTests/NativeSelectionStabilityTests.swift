import AppKit
import Testing

@testable import ScholiumApp
@testable import ScholiumEditor

@MainActor
@Suite("Stable native selection", .serialized)
struct NativeSelectionStabilityTests {
    private func settleQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test("Queued caret restyle cannot change geometry during forward or reverse drag", arguments: [NSSelectionAffinity.upstream, .downstream])
    func queuedRestyle(affinity: NSSelectionAffinity) async throws {
        let bytes = Data("# Heading\r\n\r\nfirst **粗体😀** passage\n\n```swift\r\nlet value = 1\n```\r\n\r\nlast paragraph".utf8)
        let session = nativeSelectionTestSession(bytes)
        let view = session.nativeEditor
        await settleQueue()
        let initialActive = view.activeBlockIndex
        let source = view.rawSource as NSString
        let last = source.range(of: "last")
        view.setSelectedRange(NSRange(location: last.location, length: 0))
        #expect(view.pendingRecompose)
        let attributes = try #require(view.textStorage?.copy() as? NSAttributedString)
        let origin = session.scrollView.contentView.bounds.origin
        let undoCount = view.undoStack.count
        view.beginPointerSelection()
        let start = source.range(of: "first").location
        let selected = NSRange(location: start, length: last.upperBound - start)
        view.setSelectedRanges([NSValue(range: selected)], affinity: affinity, stillSelecting: true)
        await settleQueue()
        let unchanged = view.textStorage?.isEqual(to: attributes) == true
        #expect(unchanged)
        #expect(view.activeBlockIndex == initialActive)
        #expect(view.selectedRange() == selected)
        #expect(view.selectionAffinity == affinity)
        #expect(session.scrollView.contentView.bounds.origin == origin)
        view.setSelectedRanges([NSValue(range: selected)], affinity: affinity, stillSelecting: false)
        view.endPointerSelection()
        await settleQueue()
        #expect(view.selectedRange() == selected)
        #expect(view.selectionAffinity == affinity)
        #expect(view.activeBlockIndex == initialActive)
        #expect(view.undoStack.count == undoCount)
        #expect(try view.exactUTF8ForSaving() == bytes)
        #expect(source.substring(with: selected).contains("```swift\nlet value = 1\n```"))
        // Collapsing the selection resumes ordinary editing and token reveal.
        view.setSelectedRange(NSRange(location: last.location, length: 0))
        await settleQueue()
        #expect(view.activeBlockIndex == view.blockIndexForRawOffset(last.location))
    }

    @Test("Reading and keyboard extension leave presentation and source unchanged")
    func readingAndKeyboard() async throws {
        let bytes = Data("first **bold** 中文\r\n\r\nsecond 😀 text".utf8)
        let session = nativeSelectionTestSession(bytes)
        let view = session.nativeEditor
        await settleQueue()
        view.setSelectedRange(NSRange(location: 0, length: 0))
        await settleQueue()
        let attributes = try #require(view.textStorage?.copy() as? NSAttributedString)
        view.moveWordRightAndModifySelection(nil)
        view.moveDownAndModifySelection(nil)
        await settleQueue()
        #expect(view.selectedRange().length > 0)
        let stable = view.textStorage?.isEqual(to: attributes) == true
        #expect(stable)
        session.setMode(.read)
        let reading = try #require(view.textStorage?.copy() as? NSAttributedString)
        view.setSelectedRange(NSRange(location: (view.rawSource as NSString).range(of: "second").location, length: 0))
        await settleQueue()
        let readingStable = view.textStorage?.isEqual(to: reading) == true
        #expect(readingStable)
        #expect(try view.exactUTF8ForSaving() == bytes)
    }

    @Test("Presentation refresh keeps the complete native range and affinity")
    func presentationRefresh() async throws {
        let original = Data("中文 **emphasis**\r\n\r\n```swift\nvalue\n```\r\nend".utf8)
        let view = nativeSelectionTestSession(original).nativeEditor
        await settleQueue()
        let range = NSRange(location: 3, length: 30)
        view.setSelectedRanges([NSValue(range: range)], affinity: .upstream, stillSelecting: false)
        view.rerenderStyles()
        #expect(view.selectedRange() == range)
        #expect(view.selectionAffinity == .upstream)
        view.beginPointerSelection()
        view.rerenderStyles()
        #expect(view.deferredPointerRestyle)
        view.endPointerSelection()
        #expect(!view.deferredPointerRestyle)
        #expect(view.selectedRange() == range)
        #expect(view.selectionAffinity == .upstream)
        #expect(try view.exactUTF8ForSaving() == original)
    }

    @Test("Progressive styling defers until mouse-up without scheduling a busy loop")
    func deferredStyling() async throws {
        let view = nativeSelectionTestSession(Data("# Heading\n\nparagraph\n\n**bold**".utf8)).nativeEditor
        await settleQueue()
        let index = try #require(view.blocks.indices.last)
        view.blocks[index].isStyled = false
        view.beginPointerSelection()
        view.drainStylingSlice()
        view.scheduleFullLayoutSettle()
        view.promoteVisibleUnstyledBlocks()
        #expect(!view.blocks[index].isStyled)
        #expect(view.deferredPointerLayout)
        #expect(!view.progressiveStylingScheduled)
        view.endPointerSelection()
        await settleQueue()
        #expect(!view.deferredPointerLayout)
        #expect(view.blocks[index].isStyled)
    }

    @Test("Callout selection reveals source after drag without moving the native range")
    func calloutSelection() async throws {
        let bytes = Data("开头 😀\r\n\r\n> [!WARNING] 提示\r\n> 中文 Body\r\n> 下一行\r\n\r\n结尾".utf8)
        let session = nativeSelectionTestSession(bytes)
        let view = session.nativeEditor
        await settleQueue()
        let source = view.rawSource as NSString
        let marker = source.range(of: "> [!WARNING]")
        let bodyPrefix = source.range(of: "> 中文")
        let selection = NSRange(location: marker.location, length: marker.length)
        #expect(view.selectionContainsOnlyCalloutMarker(selection))
        #expect(!view.selectionContainsOnlyCalloutMarker(source.range(of: "提示")))
        #expect(!view.selectionContainsOnlyCalloutMarker(source.range(of: "中文 Body")))
        let before = try #require(view.textStorage?.copy() as? NSAttributedString)
        let origin = session.scrollView.contentView.bounds.origin
        let undoCount = view.undoStack.count

        view.beginPointerSelection()
        view.setSelectedRanges(
            [NSValue(range: selection)], affinity: .upstream, stillSelecting: true)
        await settleQueue()
        #expect(view.textStorage?.isEqual(to: before) == true)
        view.setSelectedRanges(
            [NSValue(range: selection)], affinity: .upstream, stillSelecting: false)
        view.endPointerSelection()
        await settleQueue()

        let selected = try #require(view.textStorage)
        #expect(view.selectedRange() == selection)
        #expect(view.selectionAffinity == .upstream)
        #expect(selected.attribute(.editorSyntaxInk, at: marker.location, effectiveRange: nil) != nil)
        #expect(selected.attribute(.editorSyntaxInk, at: marker.location + 2, effectiveRange: nil) != nil)
        #expect(selected.attribute(.fragmentOverlay, at: marker.location + 2, effectiveRange: nil) == nil)
        #expect(selected.attribute(.editorSyntaxInk, at: bodyPrefix.location, effectiveRange: nil) == nil)
        #expect(session.scrollView.contentView.bounds.origin == origin)
        #expect(view.undoStack.count == undoCount)
        #expect(try view.exactUTF8ForSaving() == bytes)

        view.setSelectedRange(NSRange(location: source.range(of: "结尾").location, length: 0))
        await settleQueue()
        #expect(view.textStorage?.attribute(.fragmentOverlay, at: marker.location + 2, effectiveRange: nil) != nil)
        #expect(try view.exactUTF8ForSaving() == bytes)
    }
}

@MainActor
func nativeSelectionTestSession(_ bytes: Data) -> MarkdownEditorSession {
    let session = MarkdownEditorSession()
    session.loadDocument(String(decoding: bytes, as: UTF8.self), documentID: "selection-fixture", mode: .edit)
    return session
}
