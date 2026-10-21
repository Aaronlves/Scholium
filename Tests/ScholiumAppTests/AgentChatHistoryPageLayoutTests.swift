import AppKit
import Observation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// Native layout receipts at the history-page publication boundary. The window
/// is never ordered; this proves geometry and ownership, not drawing or motion.
@Suite("Chat prepared history page layout", .serialized)
@MainActor
struct AgentChatHistoryPageLayoutTests {
    enum PageKind: String, CaseIterable, Sendable {
        case mixed
        case processOnly
    }

    @Test(
        "Prepared history publishes final native sizes and every expanded reader",
        arguments: PageKind.allCases)
    func preparedHistoryLayout(kind: PageKind) async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/history-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scholium.tests.history-layout.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let triptychID = UUID()
        let fixture = Fixture(kind: kind, triptychID: triptychID)
        let conversation = fixture.conversation
        let original = try exactSnapshot(conversation.messages)
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        try await storage.save([conversation])
        let controller = fixtureChatController(
            triptychID: triptychID, root: root, methodDefaults: defaults
        ) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        let presentation = AgentChatDetailPresentation()
        let reading = AgentChatReadingSession()
        reading.processExpansions["history-commentary-a"] = true
        reading.toolGroupExpansions["tools:history-tool"] = true
        let native = AgentChatComposerSession(conversationID: conversation.id)
        let projection = AgentChatTimelineProjection(conversation.messages)
        let initialIDs = Set(projection.ids.suffix(AgentChatHistoryWindow.initialPageSize))
        let host = NSHostingView(rootView: AnyView(Color.clear))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        do {
            try await settle(host) { controller.isLoaded }
            try #require(controller.selectedID == conversation.id)
            host.rootView = AnyView(
                AgentChatConversationDetailView(
                    controller: controller, isVisible: true, addSelection: { _ in false },
                    noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
                    openAttachment: { _, _ in }, showChanges: { _ in },
                    showConversationChanges: { _ in }, presentation: presentation, readingSession: reading,
                    nativeSession: native, focusRequest: nil, consumeFocusRequest: { _ in },
                    replyNavigation: .constant(nil), openReply: { _ in }, showList: {}, newConversation: {},
                    didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {}))
            try await settle(host) {
                reading.isInitialTranscriptReady && reading.areReadersHydrated(initialIDs)
                    && reading.viewportRequest == nil && !reading.isScrolling
                    && readers(in: host).count == initialIDs.count
            }
            let initialReaders = try await sampleReaders(in: host, fixture: fixture)
            #expect(Set(initialReaders.keys) == initialIDs)
            let retained = try #require(initialReaders["retained-answer-0"]?.view as? WKWebView)
            let selected = try #require(
                try await retained.evaluateJavaScript(
                    """
                    window.__scholiumHistoryLifetime = 'retained-native-reader';
                    const range = document.createRange();
                    range.selectNodeContents(document.querySelector('#scholium-document h2'));
                    const selection = window.getSelection();
                    selection.removeAllRanges(); selection.addRange(range); selection.toString();
                    """) as? String)
            #expect(selected == "保留的分析 0")
            let draftSelection = NSRange(location: 2, length: 3)
            native.host.editor.setSelectedRange(draftSelection)
            reading.navigate(to: "retained-answer-0", in: projection.ids)
            try await settle(host) { reading.viewportRequest == nil && !reading.isScrolling }
            let anchor = try #require(reading.anchor)
            try verifyAnchor(reading, expected: anchor)
            let viewport = try #require(reading.viewport)
            let scroll = try #require(viewport.enclosingScrollView)
            let presentedHeight = try #require(scroll.documentView?.frame.height)
            let previous = reading.history

            reading.page(earlier: true, in: projection.ids, readerIDs: projection.replyReaderIDs)
            let page = try #require(reading.pendingHistoryPage)
            #expect(page.itemIDs == Set(projection.ids).subtracting(initialIDs))
            if kind == .processOnly {
                #expect(
                    page.readerIDs.isEmpty,
                    "This case must exercise nested-reader registration, without a top-level reader barrier")
            }
            let probe = CommitProbe(host: host, session: reading, expectedReaderIDs: fixture.readerIDs)
            withObservationTracking {
                _ = reading.pendingHistoryPage
            } onChange: { [weak probe] in
                MainActor.assumeIsolated { probe?.capture() }
            }

            var beforeResize: [String: ReaderSample] = [:]
            if kind == .mixed {
                // Model Back's session-activity boundary without destroying this
                // detail or blocking the work needed to prepare its pending page.
                reading.setPresentationActive(false, for: viewport.presentationID)
                try await settle(host) {
                    reading.areReadersHydrated(fixture.readerIDs)
                        && readers(in: host).count == fixture.readerIDs.count
                }
                #expect(reading.pendingHistoryPage?.itemIDs == page.itemIDs)
                #expect(reading.pagingRange(in: projection.ids) == previous.range(in: projection.ids))
                #expect(abs((scroll.documentView?.frame.height ?? 0) - presentedHeight) < 2)
                try verifyAnchor(reading, expected: anchor)
                beforeResize = try await sampleReaders(in: host, fixture: fixture)
                #expect(Set(beforeResize.keys) == fixture.readerIDs)
                window.setContentSize(NSSize(width: 460, height: 680))
                layout(host)
                #expect(abs(host.bounds.width - 460) < 1)
                #expect(reading.pendingHistoryPage?.itemIDs == page.itemIDs)
                // Do not await fresh DOM receipts before reactivation: stale
                // 360-point measurements must themselves prevent publication.
                reading.setPresentationActive(true, for: viewport.presentationID)
            }

            try await settle(host) { reading.pendingHistoryPage == nil }
            // Capture the first native layout after observing publication, not
            // a later quiet/stable sample that could conceal a second reflow.
            layout(host)
            let firstCommitted = nativeSizes(in: host)
            #expect(probe.captures == 1)
            #expect(
                probe.hydrated,
                "The page cannot publish before every saved expanded commentary has mounted and hydrated")
            #expect(probe.sizes.count == fixture.readerIDs.count)
            #expect(Set(firstCommitted.keys) == Set(probe.sizes.keys))
            let committed = try await sampleReaders(in: host, fixture: fixture)
            #expect(Set(committed.keys) == fixture.readerIDs)
            for (id, sample) in committed {
                let identity = ObjectIdentifier(sample.view)
                let before = try #require(
                    probe.sizes[identity], "Every committed reader needs a native size at publication")
                let first = try #require(firstCommitted[identity])
                // Nested commentary IDs differ from their enclosing process item ID.
                // Every reader outside the original range belongs to this new page.
                if !initialIDs.contains(id) {
                    #expect(
                        abs(before.width - first.width) < 2 && abs(before.height - first.height) < 2,
                        "Removing the zero-height parent must not change the prepared reader size")
                    #expect(
                        abs(sample.viewportWidth - before.width) <= 1
                            && abs(sample.height - before.height) <= 1,
                        "Publication requires the actual reader width and applied height to agree with its complete text layout"
                    )
                    #expect(
                        abs(sample.view.bounds.width - first.width) < 2
                            && abs(sample.view.bounds.height - first.height) < 2)
                }
                if id == "history-short" {
                    #expect(
                        before.width <= sample.textWidth + 1,
                        "好。 must already use its intrinsic bubble width at publication")
                }
                if kind == .mixed, !initialIDs.contains(id), id != "history-short",
                    let old = beforeResize[id]
                {
                    #expect(
                        abs(before.width - old.nativeSize.width - 100) < 2,
                        "Long requests and full-width commentary must finish the 360-to-460 resize before publication"
                    )
                }
                if let old = initialReaders[id] {
                    #expect(
                        sample.view === old.view, "Prepending and resizing must keep every existing reader instance"
                    )
                }
            }
            // Existing visible readers can complete their own resize reconciliation
            // independently; their terminal geometry is not a page-commit barrier.
            try await settle(host) {
                initialIDs.allSatisfy { id in
                    guard let sample = committed[id] else { return false }
                    return abs(sample.view.bounds.width - sample.viewportWidth) <= 1
                        && abs(sample.view.bounds.height - sample.height) <= 1
                }
            }
            try await settle(host) { reading.viewportRequest == nil && !reading.isScrolling }
            try verifyAnchor(reading, expected: anchor)
            #expect(
                try await retained.evaluateJavaScript("window.__scholiumHistoryLifetime") as? String
                    == "retained-native-reader")
            #expect(
                try await retained.evaluateJavaScript("window.getSelection().toString()") as? String
                    == selected)
            #expect(native.host.editor.string.utf8.elementsEqual(conversation.draft.utf8))
            #expect(native.host.editor.selectedRange() == draftSelection)
            #expect(reading.processExpansions["history-commentary-a"] == true)
            #expect(reading.toolGroupExpansions["tools:history-tool"] == true)
            #expect(try exactSnapshot(try #require(controller.selected).messages) == original)
            #expect(!window.isVisible)
            print(
                "CHAT_HISTORY_LAYOUT kind=\(kind.rawValue) committed_readers=\(committed.count) all_hydrated_at_publication=\(probe.hydrated) width=\(host.bounds.width) evidence=NoPaint window_never_ordered=true"
            )
            host.rootView = AnyView(Color.clear)
            try await settle(host) { reading.viewport == nil && native.host.window == nil }
            await controller.disconnect()
        } catch {
            host.rootView = AnyView(Color.clear)
            await controller.disconnect()
            throw error
        }
    }

    private struct Fixture {
        let conversation: AgentChatConversation
        let sentinels: [String: String]
        var readerIDs: Set<String> { Set(sentinels.keys) }

        init(kind: PageKind, triptychID: UUID) {
            var messages: [AgentChatMessage] = []
            var sentinels: [String: String] = [:]
            if kind == .mixed {
                messages.append(AgentChatMessage(id: "history-short", role: .user, text: "好。"))
                sentinels["history-short"] = "好。"
                messages.append(
                    AgentChatMessage(
                        id: "history-long", role: .user,
                        text: "长请求：" + String(repeating: "保留中文、English、Cafe\u{301} 和😀的源文，核对最终换行。", count: 24)))
                sentinels["history-long"] = "长请求："
            }
            var commentary = AgentChatMessage(
                id: "history-commentary-a", role: .assistant,
                text: "## 预备公开进展 A\n\n"
                    + String(repeating: "公开进展保留独立来源。Synthetic Cafe\u{301} 中文😀。\n\n", count: 6),
                phase: .commentary)
            commentary.turnID = "history-process-turn"
            var tool = AgentChatMessage(
                id: "history-tool", role: .operation, text: "",
                activity: .init(
                    kind: .tool, status: .completed, source: .runtime, subject: "Synthetic read",
                    detail: "Synthetic output"))
            tool.turnID = commentary.turnID
            var second = AgentChatMessage(
                id: "history-commentary-b", role: .assistant,
                text: "## 预备公开进展 B\n\n另一段公开进展保留精确原文与最终布局。", phase: .commentary)
            second.turnID = commentary.turnID
            messages += [commentary, tool, second]
            sentinels[commentary.id] = "预备公开进展 A"
            sentinels[second.id] = "预备公开进展 B"
            for index in 0..<2 {
                var question = AgentChatMessage(
                    id: "retained-question-\(index)", role: .user, text: "保留的问题 \(index)：核对原文。")
                question.turnID = "retained-turn-\(index)"
                var answer = AgentChatMessage(
                    id: "retained-answer-\(index)", role: .assistant,
                    text: "## 保留的分析 \(index)\n\n"
                        + String(
                            repeating: "合成段落区分来源、解释与评价。English, Cafe\u{301}, café, 中文和😀保持精确文本。\n\n", count: 12)
                        + "| 来源 | 值 |\n|---|---|\n| 合成 | Cafe\u{301} 😀 |\n", phase: .finalAnswer)
                answer.turnID = question.turnID
                messages += [question, answer]
                sentinels[question.id] = "保留的问题 \(index)"
                sentinels[answer.id] = "保留的分析 \(index)"
            }
            var conversation = AgentChatConversation(triptychID: triptychID)
            conversation.title = "Synthetic prepared history \(kind.rawValue)"
            conversation.draft = "未发送的草稿 Cafe\u{301} 😀。\n保留第二行。"
            conversation.messages = messages
            self.conversation = conversation
            self.sentinels = sentinels
        }
    }

    private struct ReaderSample {
        let view: NSView
        let nativeSize: CGSize
        let viewportWidth: CGFloat
        let height: CGFloat
        let textWidth: CGFloat
    }

    private func sampleReaders(in host: NSView, fixture: Fixture) async throws -> [String:
        ReaderSample]
    {
        var result: [String: ReaderSample] = [:]
        for view in readers(in: host) {
            let nativeSize = view.bounds.size
            try #require(nativeSize.width.isFinite && nativeSize.height.isFinite && nativeSize.width > 0 && nativeSize.height > 0)
            if let paragraph = view as? AgentChatNativeParagraphView {
                let message = try #require(
                    fixture.conversation.messages.first {
                        $0.role == .user && $0.text.utf8.elementsEqual(paragraph.string.utf8)
                    })
                try #require(fixture.sentinels[message.id] != nil)
                try #require(result[message.id] == nil)
                #expect(paragraph.string.utf8.elementsEqual(message.text.utf8))
                let container = try #require(paragraph.textContainer)
                let layout = try #require(paragraph.layoutManager)
                layout.ensureLayout(for: container)
                let used = layout.usedRect(for: container)
                result[message.id] = ReaderSample(
                    view: paragraph, nativeSize: nativeSize, viewportWidth: container.containerSize.width,
                    height: max(ScholiumChatAppearance.messageLoadingHeight, ceil(used.height)),
                    textWidth: ceil(used.width))
                continue
            }
            let reader = try #require(view as? WKWebView)
            let value = try await reader.callAsyncJavaScript(
                """
                const root = document.querySelector('#scholium-document');
                const first = root.firstElementChild;
                const range = document.createRange();
                range.selectNodeContents(first);
                return {fingerprint: configuration.fingerprint,
                  identity: (first.textContent || '').slice(0, 64), viewportWidth: window.innerWidth,
                  height: Math.ceil(root.getBoundingClientRect().height), textWidth: Math.ceil(range.getBoundingClientRect().width)};
                """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            let payload = try #require(value as? [String: Any])
            let fingerprint = try #require(payload["fingerprint"] as? String)
            let message = try #require(
                fixture.conversation.messages.first {
                    DocumentFingerprint(content: $0.text).sha256 == fingerprint
                })
            let identity = try #require(payload["identity"] as? String)
            #expect(identity.hasPrefix(try #require(fixture.sentinels[message.id])))
            try #require(result[message.id] == nil)
            result[message.id] = ReaderSample(
                view: reader, nativeSize: nativeSize,
                viewportWidth: CGFloat(try #require(payload["viewportWidth"] as? Double)),
                height: CGFloat(try #require(payload["height"] as? Double)),
                textWidth: CGFloat(try #require(payload["textWidth"] as? Double)))
        }
        return result
    }

    @MainActor private final class CommitProbe {
        private weak var host: NSView?
        private let session: AgentChatReadingSession
        private let expectedReaderIDs: Set<String>
        var captures = 0
        var hydrated = false
        var sizes: [ObjectIdentifier: CGSize] = [:]
        init(host: NSView, session: AgentChatReadingSession, expectedReaderIDs: Set<String>) {
            self.host = host
            self.session = session
            self.expectedReaderIDs = expectedReaderIDs
        }
        func capture() {
            captures += 1
            hydrated = session.areReadersHydrated(expectedReaderIDs)
            if let host {
                func collect(_ view: NSView) {
                    if view is WKWebView || view is AgentChatNativeParagraphView {
                        sizes[ObjectIdentifier(view)] = view.bounds.size
                    }
                    view.subviews.forEach(collect)
                }
                collect(host)
            }
        }
    }

    private func nativeSizes(in host: NSView) -> [ObjectIdentifier: CGSize] {
        Dictionary(
            uniqueKeysWithValues: readers(in: host).map { (ObjectIdentifier($0), $0.bounds.size) })
    }
    private func readers(in view: NSView) -> [NSView] {
        if view is WKWebView || view is AgentChatNativeParagraphView { return [view] }
        return view.subviews.flatMap { readers(in: $0) }
    }
    private func verifyAnchor(
        _ session: AgentChatReadingSession, expected: AgentChatReadingSession.Anchor
    ) throws {
        #expect(session.anchor == expected)
        let viewport = try #require(session.viewport)
        let scroll = try #require(viewport.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let marker = try #require(session.markers[expected.id]?.view)
        let frame = marker.convert(marker.bounds, to: document)
        let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
        #expect(
            abs(frame.minY - top - expected.offset) < 2,
            "The retained passage must agree with actual native clip geometry")
    }
    private func exactSnapshot<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func layout(_ host: NSView) {
        host.window?.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
    }
    private func settle(_ host: NSView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            layout(host)
            if condition() { return }
            try #require(ContinuousClock.now < deadline, "The prepared history boundary did not complete")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
