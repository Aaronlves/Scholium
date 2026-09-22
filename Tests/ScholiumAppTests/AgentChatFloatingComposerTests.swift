import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat floating composer reading geometry", .serialized)
@MainActor
struct AgentChatFloatingComposerTests {
    @Test("The floating composer clears latest actions and preserves an earlier passage while its draft grows", arguments: [false, true])
    func floatingComposerPreservesReading(adapted: Bool) async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/floating-input-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic floating composer"
        conversation.draft = ""
        conversation.messages = (0..<2).flatMap { index in
            var question = AgentChatMessage(id: "question-\(index)", role: .user, text: "请核对第 \(index) 组材料。")
            question.turnID = "turn-\(index)"
            var reply = AgentChatMessage(
                id: "reply-\(index)", role: .assistant,
                text: "**Retained passage \(index)**\n\n"
                    + String(repeating: "Synthetic source discussion with 中文, English, and exact reading continuity.\n\n", count: 12),
                phase: .finalAnswer)
            reply.turnID = question.turnID
            return [question, reply]
        }
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let presentation = AgentChatDetailPresentation()
        let session = AgentChatReadingSession()
        let ids = AgentChatTimelineProjection(conversation.messages).ids
        let latestID = try #require(ids.last)
        let detail = AgentChatConversationDetailView(
            controller: controller, isVisible: true, addSelection: { _ in false },
            noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
            openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
            showConversationChanges: { _ in }, presentation: presentation, readingSession: session,
            focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in }, showList: {},
            newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
            showAccountUsage: {}, showDiagnostics: { _, _ in })
        let host = NSHostingView(
            rootView:
                detail
                .environment(\.colorScheme, adapted ? .dark : .light)
                .environment(\.locale, Locale(identifier: adapted ? "zh-Hans" : "en")))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: adapted ? 300 : 360, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: adapted ? .accessibilityHighContrastDarkAqua : .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        func composer() -> AgentChatComposerHost? { descendants(host).compactMap { $0 as? AgentChatComposerHost }.first }
        func latestIsPositioned() -> Bool {
            guard session.isInitialTranscriptReady, session.viewportRequest == nil,
                let marker = session.markers[latestID]?.view,
                let scroll = marker.enclosingScrollView, let document = scroll.documentView
            else { return false }
            return abs(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) < 2
        }
        try await settle(host) { latestIsPositioned() && composer() != nil }
        let editor = try #require(composer())
        let marker = try #require(session.markers[latestID]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        let document = try #require(scroll.documentView)
        // The native top bar reserves readable space inside the same scroll
        // viewport, rather than clipping the transcript below a sibling header.
        #expect(scroll.contentInsets.top >= ScholiumSidebarLayout.headerHeight)
        // Actual transcript geometry must extend behind the input. A sibling
        // below the scroll view cannot satisfy this even if its rows fit.
        let scrollFrame = scroll.convert(scroll.bounds, to: nil)
        let composerFrame = editor.convert(editor.bounds, to: nil)
        #expect(scrollFrame.intersection(composerFrame).height > 1)
        func expectLatestClear() {
            let row = marker.convert(marker.bounds, to: document)
            let readableBottom = scroll.contentView.bounds.maxY - scroll.contentInsets.bottom
            #expect(row.maxY <= readableBottom + 2)
            // The reading marker spans the complete message and its action row.
            let rowInWindow = marker.convert(marker.bounds, to: nil)
            let inputInWindow = editor.convert(editor.bounds, to: nil)
            #expect(rowInWindow.minY >= inputInWindow.maxY - 2)
        }
        expectLatestClear()
        // A changed bottom inset must preserve automatic follow, without an
        // explicit Latest request disguising a stale viewport calculation.
        let compactHeight = editor.frame.height
        window.makeFirstResponder(editor.editor)
        editor.editor.setSelectedRange(NSRange(location: 0, length: editor.editor.string.utf16.count))
        editor.editor.insertText(
            String(repeating: "Latest-follow draft grows with 中文.\n", count: 9),
            replacementRange: editor.editor.selectedRange())
        try await settle(host) {
            editor.frame.height > compactHeight + 10 && latestIsPositioned()
                && !session.isRetainingPosition
        }
        expectLatestClear()
        #expect(!session.isAwayFromLatest)
        #expect(composer() === editor)
        editor.editor.setSelectedRange(NSRange(location: 0, length: editor.editor.string.utf16.count))
        editor.editor.insertText("", replacementRange: editor.editor.selectedRange())
        try await settle(
            host,
            diagnostic: {
                "height=\(editor.frame.height) compact=\(compactHeight) position=\(session.position) bottom=\(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) inset=\(scroll.contentInsets.bottom)"
            }
        ) {
            abs(editor.frame.height - compactHeight) < 2 && latestIsPositioned()
                && !session.isRetainingPosition
        }
        expectLatestClear()
        #expect(!session.isAwayFromLatest)
        #expect(composer() === editor)
        session.navigate(to: "reply-0", in: ids)
        try await settle(host) { session.viewportRequest == nil && session.isRetainingPosition }
        let earlier = try #require(session.markers["reply-0"]?.view)
        func offset() -> CGFloat {
            earlier.convert(earlier.bounds, to: document).minY - scroll.contentView.bounds.minY - scroll.contentInsets.top
        }
        let retainedOffset = offset()
        let compactTopInset = scroll.contentInsets.top
        presentation.showsFind = true
        try await settle(host) {
            scroll.contentInsets.top > compactTopInset + 1
                && abs(offset() - retainedOffset) < 2
        }
        #expect(earlier.enclosingScrollView === scroll)
        #expect(composer() === editor)
        #expect(session.isRetainingPosition)
        presentation.showsFind = false
        try await settle(host) {
            abs(scroll.contentInsets.top - compactTopInset) < 2
                && abs(offset() - retainedOffset) < 2
        }
        var selectedReader: WKWebView?
        for web in descendants(host).compactMap({ $0 as? WKWebView }) {
            if try await web.evaluateJavaScript("document.querySelector('#scholium-document strong')?.textContent") as? String == "Retained passage 0" {
                selectedReader = web
                break
            }
        }
        let web = try #require(selectedReader)
        let selected =
            try await web.evaluateJavaScript(
                """
                const selection = window.getSelection();
                const range = document.createRange();
                range.selectNodeContents(document.querySelector('#scholium-document strong'));
                selection.removeAllRanges(); selection.addRange(range); selection.toString();
                """) as? String
        #expect(selected == "Retained passage 0")
        let shortHeight = editor.frame.height
        controller.editDraft(String(repeating: "Growing draft with 中文 and retained material.\n", count: 9))
        var offsets: [CGFloat] = []
        let growthDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < growthDeadline {
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            offsets.append(offset())
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(editor.frame.height > shortHeight + 10)
        #expect(composer() === editor)
        #expect(offsets.allSatisfy { abs($0 - retainedOffset) < 2 })
        #expect(session.isRetainingPosition)
        #expect(try await web.evaluateJavaScript("window.getSelection().toString()") as? String == selected)
        session.latest(in: ids)
        try await settle(host) { latestIsPositioned() }
        expectLatestClear()
        #expect(!session.isRetainingPosition)
        session.navigate(to: "reply-0", in: ids)
        try await settle(host) { session.viewportRequest == nil && abs(offset() - retainedOffset) < 2 }
        #expect(session.isRetainingPosition)
        #expect(try await web.evaluateJavaScript("window.getSelection().toString()") as? String == selected)
        print("CHAT_FLOATING_COMPOSER adapted=\(adapted) samples=\(offsets.count) max_anchor_drift=\(offsets.map { abs($0 - retainedOffset) }.max() ?? 0)")
        try await controller.flushPersistence()
    }

    @Test("Native inset and clip-size changes preserve follow and a deliberate earlier reading position")
    func nativeViewportGeometryChanges() async throws {
        let session = AgentChatReadingSession()
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 500))
        scroll.automaticallyAdjustsContentInsets = false
        final class Document: NSView { override var isFlipped: Bool { true } }
        let document = Document(frame: NSRect(x: 0, y: 0, width: 360, height: 1800))
        scroll.documentView = document
        let viewport = AgentChatTranscriptViewport.View(session: session)
        document.addSubview(viewport)
        let earlier = AgentChatReadingMarker.View(id: "earlier", session: session)
        earlier.frame = NSRect(x: 0, y: 500, width: 360, height: 600)
        document.addSubview(earlier)
        let last = AgentChatReadingMarker.View(id: "latest", session: session)
        last.frame = NSRect(x: 0, y: 1100, width: 360, height: 700)
        document.addSubview(last)
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer {
            window.contentView = nil
            window.close()
        }
        func atBottom() -> Bool {
            abs(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) < 1
        }
        session.mount(in: ["earlier", "latest"])
        try await settle(scroll) { session.viewportRequest == nil && atBottom() }
        // No document reflow, explicit navigation, or forced reconciliation:
        // only the inset changes, as a floating composer can do after layout.
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 160, right: 0)
        try await settle(scroll) { atBottom() && !session.isRetainingPosition }
        scroll.contentInsets = .init()
        try await settle(scroll) { atBottom() && !session.isRetainingPosition }
        window.setContentSize(NSSize(width: 360, height: 420))
        try await settle(scroll) { atBottom() && !session.isRetainingPosition }
        // An actual user scroll must still pause follow after geometry settles.
        session.beginUserScroll()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 620))
        scroll.reflectScrolledClipView(scroll.contentView)
        session.endUserScroll()
        try await settle(scroll) { session.isRetainingPosition }
        let anchor = try #require(session.anchor)
        try #require(anchor.id == "earlier")
        func anchorOffset() -> CGFloat {
            earlier.convert(earlier.bounds, to: document).minY - scroll.contentView.bounds.minY - scroll.contentInsets.top
        }
        scroll.contentInsets = NSEdgeInsets(top: 18, left: 0, bottom: 140, right: 0)
        try await settle(scroll) { abs(anchorOffset() - anchor.offset) < 1 }
        #expect(session.isRetainingPosition && session.anchor == anchor)
        scroll.contentInsets = .init()
        try await settle(scroll) { abs(anchorOffset() - anchor.offset) < 1 }
        session.latest(in: ["earlier", "latest"])
        try await settle(scroll) { session.viewportRequest == nil && atBottom() }
        #expect(!session.isRetainingPosition)
        // Accessibility scrollbars can change the clip without a gesture phase.
        // Stable geometry must continue to recognize that as a reading choice.
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 700))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await settle(scroll) { session.isRetainingPosition && session.anchor?.id == "earlier" }
        #expect(abs(scroll.contentView.bounds.minY - 700) < 1)
        #expect(abs((session.anchor?.offset ?? 0) + 200) < 1)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    private func settle(_ host: NSView? = nil, diagnostic: () -> String = { "" }, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while true {
            host?.window?.layoutIfNeeded()
            host?.layoutSubtreeIfNeeded()
            if condition() { return }
            if ContinuousClock.now >= deadline { print("CHAT_TIMEOUT \(diagnostic())") }
            try #require(ContinuousClock.now < deadline, "Floating composer fixture did not reach its native reading state")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
