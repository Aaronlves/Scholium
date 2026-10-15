import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// Native input/layout evidence; the fixture window is never ordered and does
/// not establish paint latency or trackpad frame rate.
@Suite("Chat latest-reply scrolling", .serialized)
@MainActor
struct AgentChatLatestScrollTests {
    @Test("Arriving at latest and reversing preserves readers and native input", arguments: [false, true])
    func arrivingAtLatest(hasChanges: Bool) async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/latest-scroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic latest boundary"
        conversation.draft = "Retained draft"
        conversation.messages = (0..<36).flatMap { index in
            var question = AgentChatMessage(id: "q-\(index)", role: .user, text: "Synthetic question \(index)")
            question.turnID = "turn-\(index)"
            var reply = AgentChatMessage(
                id: "a-\(index)", role: .assistant,
                text: "**Synthetic answer \(index)**\n\n" + String(repeating: "Stable reading with 中文 and English text.\n\n", count: 16),
                changeID: hasChanges ? UUID() : nil, phase: .finalAnswer)
            reply.turnID = question.turnID
            return [question, reply]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let source = try encoder.encode(conversation.messages)
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        let reading = AgentChatReadingSession()
        let presentation = AgentChatDetailPresentation()
        let native = AgentChatComposerSession(conversationID: conversation.id)
        let host = NSHostingView(rootView: AnyView(Color.clear))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            host.rootView = AnyView(Color.clear)
            window.contentView = nil
            window.close()
        }
        try await settle(host) { controller.isLoaded }
        host.rootView = AnyView(
            AgentChatConversationDetailView(
                controller: controller, isVisible: true, addSelection: { _ in false },
                noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
                openAttachment: { _, _ in }, showChanges: { _ in }, showConversationChanges: { _ in },
                presentation: presentation, readingSession: reading, nativeSession: native,
                focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in },
                showList: {}, newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {}))
        try await settle(host) { reading.isInitialTranscriptReady && reading.viewportRequest == nil && !reading.isScrolling }
        let viewport = try #require(reading.viewport)
        let scroll = try #require(viewport.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let retainedReaders = descendants(host).compactMap { $0 as? WKWebView }
        let identities = Set(retainedReaders.map(ObjectIdentifier.init))
        let mountedIDs = Set(reading.markers.keys)
        let history = reading.history
        let selection = NSRange(location: 2, length: 5)
        native.host.editor.setSelectedRange(selection)
        func distance() -> CGFloat {
            max(0, document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom)
        }
        var tickMS: [Double] = []
        var transitions = 0
        var insetChanges = 0
        for round in 0..<2 {
            reading.beginUserScroll()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom - 440))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await settle(host) { reading.isAwayFromLatest }
            var lastAway = reading.isAwayFromLatest
            var lastInset = scroll.contentInsets.bottom
            var records: [String] = []
            for tick in 0..<38 {
                let start = ContinuousClock.now
                var bounds = scroll.contentView.bounds
                bounds.origin.y += 16
                let destination = scroll.contentView.constrainBoundsRect(bounds).origin
                scroll.contentView.scroll(to: destination)
                scroll.reflectScrolledClipView(scroll.contentView)
                host.layoutSubtreeIfNeeded()
                await mainQueueTurn()
                host.layoutSubtreeIfNeeded()
                let elapsed = start.duration(to: .now).components
                let ms = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
                tickMS.append(ms)
                if lastAway != reading.isAwayFromLatest {
                    transitions += 1
                    lastAway = reading.isAwayFromLatest
                }
                if abs(lastInset - scroll.contentInsets.bottom) > 1 {
                    insetChanges += 1
                    lastInset = scroll.contentInsets.bottom
                }
                records.append("\(tick):\(String(format: "%.2f", ms)):\(Int(distance())):\(Int(scroll.contentInsets.bottom))")
                #expect(abs(scroll.contentView.bounds.minY - destination.y) < 2, "Dock changes cannot write over a native gesture")
                try await Task.sleep(for: .milliseconds(8))
            }
            reading.endUserScroll()
            try await settle(host) { !reading.isScrolling && reading.viewportRequest == nil }
            #expect(distance() < 2 && !reading.isRetainingPosition && !reading.isAwayFromLatest)
            // Reversing directly after arrival must still be native scrolling.
            let latestY = scroll.contentView.bounds.minY
            reading.beginUserScroll()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: latestY - 160))
            scroll.reflectScrolledClipView(scroll.contentView)
            reading.endUserScroll()
            try await settle(host) { reading.isRetainingPosition && reading.isAwayFromLatest }
            #expect(abs(scroll.contentView.bounds.minY - (latestY - 160)) < 2)
            print("CHAT_LATEST_SCROLL changes=\(hasChanges) round=\(round) tick_ms_distance_inset=\(records.joined(separator: ",")) evidence=NoPaint")
        }
        #expect(insetChanges == 0, "Latest visibility cannot change the native transcript inset")
        #expect(reading.history == history && Set(reading.markers.keys) == mountedIDs)
        #expect(Set(descendants(host).compactMap { $0 as? WKWebView }.map(ObjectIdentifier.init)) == identities)
        #expect(try encoder.encode(try #require(controller.selected).messages) == source)
        #expect(native.host.editor.string.utf8.elementsEqual(conversation.draft.utf8) && native.host.editor.selectedRange() == selection)
        print(
            "CHAT_LATEST_SUMMARY changes=\(hasChanges) ticks=\(tickMS.count) max_ms=\(tickMS.max() ?? 0) visibility_transitions=\(transitions) inset_changes=\(insetChanges)"
        )
        host.rootView = AnyView(Color.clear)
        await controller.disconnect()
    }

    @Test("Floating geometry reserves only persistent controls and keeps a tall wrapped row clear", arguments: [0, 1, 2])
    func floatingControlBoundaries(activityCount: Int) async throws {
        _ = NSApplication.shared
        let reading = AgentChatReadingSession()
        let fixture = AccessoryFixture()
        let host = NSHostingView(
            rootView:
                VStack(spacing: 0) {
                    Color.clear.frame(maxHeight: .infinity)
                    AgentChatConversationBottomArea(viewportHeight: 500) {
                        AgentChatConversationAccessories(readingSession: reading, hasActivity: activityCount > 0, latest: {}) {
                            HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                                if activityCount > 0 { Button("Changes: 14") {} }
                                if activityCount > 1 { Button("2 agents") {} }
                            }
                            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                            .frame(width: activityCount == 2 ? 240 : nil, height: activityCount == 2 ? 48 : nil)
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .global)
                            } action: {
                                fixture.activityFrame = $0
                            }
                        }
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global)
                        } action: {
                            fixture.accessoryFrame = $0
                        }
                    } input: { _ in
                        TextField("Synthetic draft", text: .constant("Retained writing"))
                            .frame(height: 100)
                    }
                })
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try await settle(host) { fixture.accessorySize != nil }
        let restingSize = try #require(fixture.accessorySize)
        #expect(activityCount > 0 || restingSize.height == 0, "No empty accessory row can remain")
        let draft = try #require(descendants(host).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        #expect(window.makeFirstResponder(draft))
        let focused = window.firstResponder
        let restingActivity = fixture.activityFrame
        reading.isAwayFromLatest = true
        await mainQueueTurn()
        try await settle(host) {
            activityCount != 2 || (fixture.activityFrame?.minY ?? 0) < (restingActivity?.minY ?? 0) - 1
        }
        #expect(fixture.accessorySize == restingSize)
        reading.isAwayFromLatest = false
        await mainQueueTurn()
        try await settle(host) { fixture.activityFrame == restingActivity }
        #expect(fixture.accessorySize == restingSize && window.firstResponder === focused)
        // An earlier window keeps navigation visible even at its own end.
        reading.history.last = "earlier-window-end"
        await mainQueueTurn()
        try await settle(host) {
            activityCount == 1 || (fixture.accessorySize?.height ?? 0) > restingSize.height
        }
        let persistent = try #require(fixture.accessorySize)
        #expect(persistent.height >= ScholiumMetrics.Accessibility.preferredCustomTarget)
        if activityCount == 2 {
            #expect(persistent.height > restingSize.height)
            let activity = try #require(fixture.activityFrame)
            let reserved = try #require(fixture.accessoryFrame)
            #expect(activity.minY >= reserved.minY && activity.maxY <= reserved.maxY)
        }
        print(
            "CHAT_FLOATING_GEOMETRY activity=\(activityCount) draft_focus_retained=true ephemeral_height=\(restingSize.height) persistent_height=\(persistent.height)"
        )
    }

    private final class AccessoryFixture {
        var accessoryFrame: CGRect?
        var accessorySize: CGSize? { accessoryFrame?.size }
        var activityFrame: CGRect?
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func mainQueueTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    private func settle(_ host: NSView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while true {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            if condition() { return }
            try #require(ContinuousClock.now < deadline, "Latest boundary fixture did not converge")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
