import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat prepared input in a short native viewport", .serialized)
@MainActor
struct AgentChatShortViewportTests {
    @Test("Long drafts and prepared context leave a readable reply and reachable native input", arguments: [false, true])
    func preparedInputRetainsReadingSpace(adapted: Bool) async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/short-input-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scholium.tests.short-chat.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "原文、解释与待核对的问题 — Sources and interpretation"
        conversation.permission = .fullAccess
        conversation.draft = String(repeating: "请保留原文措辞，并说明尚待核对的问题。\n", count: 10)
        var question = AgentChatMessage(id: "question", role: .user, text: "请核对这些合成材料。")
        question.turnID = "fixture-turn"
        var reply = AgentChatMessage(
            id: "reply", role: .assistant,
            text: "**合成回复 Synthetic reply**\n\n"
                + String(repeating: "这里区分所提供的材料与仍需核对的解释。This fixture preserves a readable research passage.\n\n", count: 14),
            phase: .finalAnswer)
        reply.turnID = question.turnID
        conversation.messages = [question, reply]
        if adapted { conversation.pendingMessageID = "unconfirmed-fixture-input" }
        conversation.attachments = [
            .init(
                noteID: UUID(), vaultID: UUID(), relativePath: "原文与解释.md",
                text: "这是保留身份的合成材料片段。", fingerprint: .init(content: "Synthetic retained material"),
                extent: .passage, source: .savedSource)
        ]
        conversation.draftReplyQuotes = [
            .init(conversationID: conversation.id, messageID: reply.id, text: "这里保留一段待讨论的合成回复。")
        ]
        conversation.queuedMessages = (0..<2).map {
            AgentChatMessage(role: .user, text: "稍后讨论第 \($0 + 1) 个问题。")
        }
        let originalDraft = conversation.draft
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let presentation = AgentChatDetailPresentation()
        presentation.showsFind = true
        presentation.find.query = "Synthetic"
        let reading = AgentChatReadingSession()
        let native = AgentChatComposerSession(conversationID: conversation.id)
        let detail = AgentChatConversationDetailView(
            controller: controller, isVisible: true, addSelection: { _ in false },
            noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
            openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
            showConversationChanges: { _ in }, presentation: presentation, readingSession: reading,
            nativeSession: native, focusRequest: nil, consumeFocusRequest: { _ in },
            replyNavigation: nil, openReply: { _ in }, showList: {}, newConversation: {},
            didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {},
            diagnosticsPresentation: .constant(nil))
        let host = NSHostingView(
            rootView:
                detail
                .environment(\.locale, Locale(identifier: adapted ? "zh-Hans" : "en"))
                .environment(\.colorScheme, adapted ? .dark : .light))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 560),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: adapted ? .accessibilityHighContrastDarkAqua : .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try await settle(host) {
            guard reading.isInitialTranscriptReady, native.host.window === window,
                let scroll = reading.markers["reply"]?.view?.enclosingScrollView
            else { return false }
            return scroll.contentView.bounds.height > 0
        }
        let marker = try #require(reading.markers["reply"]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        let minimumReadingHeight =
            ScholiumChatAppearance.messageNSFont.pointSize
            * ScholiumChatAppearance.messageLineHeight * 6 - 2
        do {
            try await settle(host) {
                scroll.contentView.bounds.height - scroll.contentInsets.top - scroll.contentInsets.bottom
                    >= minimumReadingHeight
            }
        } catch {
            print("CHAT_SHORT_INPUT adapted=\(adapted) viewport=\(scroll.contentView.bounds.height) insets=\(scroll.contentInsets)")
            throw error
        }
        let readableHeight = scroll.contentView.bounds.height - scroll.contentInsets.top - scroll.contentInsets.bottom
        print(
            "CHAT_SHORT_INPUT adapted=\(adapted) readable_height=\(readableHeight) editor_height=\(native.host.bounds.height) viewport=\(scroll.contentView.bounds.height) insets=\(scroll.contentInsets)"
        )
        #expect(readableHeight >= minimumReadingHeight)
        #expect(native.host.bounds.height >= ScholiumChatAppearance.messageNSFont.pointSize + 12)
        #expect(native.host.bounds.height < native.host.fittingHeight(width: native.host.bounds.width))
        #expect(native.host.editor.string == originalDraft && controller.selected?.draft == originalDraft)
        #expect(host.bounds.contains(native.host.convert(native.host.bounds, to: host)))
        let ids = AgentChatTimelineProjection(conversation.messages).ids
        reading.latest(in: ids)
        try await settle(host) {
            guard let document = scroll.documentView else { return false }
            return reading.viewportRequest == nil
                && abs(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) < 2
        }
        let row = marker.convert(marker.bounds, to: scroll.documentView)
        #expect(row.maxY <= scroll.contentView.bounds.maxY - scroll.contentInsets.bottom + 2)
        try await controller.flushPersistence()
    }

    private func settle(_ host: NSView? = nil, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while ContinuousClock.now < deadline {
            host?.window?.layoutIfNeeded()
            host?.layoutSubtreeIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ViewportTimeout()
    }

    private struct ViewportTimeout: Error {}
}
