import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// Native geometry proof for a newly created detail, including a retained
/// conversation whose previous detail was destroyed after another selection.
/// The window is never ordered; these samples are not visible-entry timings.
@Suite("Chat detail entry layout", .serialized)
@MainActor
struct AgentChatEntryLayoutTests {
    @Test("Recreated details wait for current readers and geometry while retaining reading and writing", arguments: [false, true])
    func recreatedDetailHasStableFirstLayout(expandedProcess: Bool) async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/entry-layout-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scholium.tests.entry-layout.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let triptychID = UUID()
        let questionText = "核对原文 Cafe\u{301} 中文😀。"
        let progressTitle = "公开进展 Cafe\u{301} 中文"
        let progressParagraph = "这里保留合成来源的原文，并区分公开工作进展与最终分析。Synthetic public progress 👩‍🔬."
        let answerParagraph = "这是用于原生布局验证的合成分析段落。它保留中文、English、Cafe\u{301} 与😀的精确文本。"
        var question = AgentChatMessage(id: "entry-question", role: .user, text: questionText)
        question.turnID = "entry-turn"
        var progress = AgentChatMessage(
            id: "entry-progress", role: .assistant,
            text: "**\(progressTitle)**\n\n" + String(repeating: progressParagraph + "\n\n", count: 14), phase: .commentary)
        progress.turnID = question.turnID
        var tool = AgentChatMessage(
            id: "entry-tool", role: .operation, text: "",
            activity: .init(
                kind: .tool, status: .completed, source: .runtime,
                subject: "Synthetic source read", detail: "Synthetic retained tool output."))
        tool.turnID = question.turnID
        var answer = AgentChatMessage(
            id: "entry-answer", role: .assistant,
            text: "## 合成分析\n\n" + String(repeating: answerParagraph + "\n\n", count: 10)
                + "- 原文保持独立。\n- 解释仍可核对。\n\n| 项目 | 精确值 |\n|---|---|\n| 合成来源 | Cafe\u{301} 😀 |\n",
            phase: .finalAnswer)
        answer.turnID = question.turnID
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic recreated detail"
        conversation.draft = "未发送的草稿 Cafe\u{301}。\n第二行保留原文。"
        conversation.messages = expandedProcess ? [question, progress, tool, answer] : [question, answer]
        let sourceSnapshot = try exactSnapshot(conversation.messages)
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        try await storage.save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        let presentation = AgentChatDetailPresentation()
        let reading = AgentChatReadingSession()
        let native = AgentChatComposerSession(conversationID: conversation.id)
        if expandedProcess {
            reading.processExpansions[progress.id] = true
            reading.toolGroupExpansions["tools:\(tool.id)"] = true
        }
        let processChoices = reading.processExpansions
        let toolChoices = reading.toolGroupExpansions
        let projection = AgentChatTimelineProjection(conversation.messages)
        let readerIDs: Set<String> = expandedProcess ? [question.id, progress.id, answer.id] : [question.id, answer.id]
        func detail() -> AnyView {
            AnyView(
                AgentChatConversationDetailView(
                    controller: controller, isVisible: true, addSelection: { _ in false },
                    noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
                    openAttachment: { _, _ in }, showChanges: { _ in },
                    showConversationChanges: { _ in }, presentation: presentation, readingSession: reading,
                    nativeSession: native, focusRequest: nil, consumeFocusRequest: { _ in },
                    replyNavigation: nil, openReply: { _ in }, showList: {}, newConversation: {},
                    didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {}))
        }
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
            host.rootView = detail()
            _ = try await observeEntry(tag: "initial", host: host, session: reading, native: native, rowIDs: projection.ids, readerIDs: readerIDs)
            reading.navigate(to: question.id, in: projection.ids)
            try await settle(host) { reading.viewportRequest == nil && reading.isRetainingPosition }
            let anchor = try #require(reading.anchor)
            let selection = NSRange(location: 2, length: 3)
            native.host.editor.setSelectedRange(selection)
            let oldReaders = descendants(host).compactMap { ($0 as? WKWebView).map(WeakReader.init) }
            host.rootView = AnyView(Text("Another synthetic conversation is selected"))
            try await settle(host) { reading.viewport == nil && native.host.window == nil && oldReaders.allSatisfy { $0.view == nil } }
            #expect(reading.anchor == anchor)
            host.rootView = detail()
            let result = try await observeEntry(tag: "remount", host: host, session: reading, native: native, rowIDs: projection.ids, readerIDs: readerIDs)
            let first = try #require(result.firstVisible)
            let drift = result.visibleSamples.map { $0.maximumDrift(from: result.settled) }.max() ?? 0
            let layoutDrift = result.visibleSamples.map { $0.maximumLayoutDrift(from: result.settled) }.max() ?? 0
            print(
                "CHAT_ENTRY_LAYOUT expanded_process=\(expandedProcess) first_phase=\(first.phase) "
                    + "first_readers=\(first.readerCount) expected_readers=\(readerIDs.count) "
                    + "visible_before_hydration=\(!first.hydrated) max_visible_geometry_drift=\(drift) "
                    + "max_visible_layout_drift=\(layoutDrift) "
                    + "first=\(first.description) settled=\(result.settled.description) "
                    + "window_never_ordered=true timing_claim=none")
            #expect(first.hydrated, "A rebuilt detail must not reveal fallback geometry before its current readers hydrate")
            #expect(first.readerCount == readerIDs.count)
            #expect(drift < 2, "First visible row, viewport, inset and composer geometry must remain stable")
            #expect(layoutDrift < 2, "Transcript geometry must stay stable independently of missing reader frames")
            #expect(reading.anchor == anchor && reading.isRetainingPosition)
            #expect(reading.processExpansions == processChoices && reading.toolGroupExpansions == toolChoices)
            #expect(native.host.editor.string.utf8.elementsEqual(conversation.draft.utf8))
            #expect(native.host.editor.selectedRange() == selection)
            #expect(try exactSnapshot(try #require(controller.selected).messages) == sourceSnapshot)
            try await verifyReaders(
                descendants(host).compactMap { $0 as? WKWebView }, messages: conversation.messages,
                question: questionText, progressTitle: progressTitle, progressParagraph: progressParagraph,
                answerParagraph: answerParagraph, expandedProcess: expandedProcess)
            try await controller.flushPersistence()
            let stored = try #require(try await storage.load().first { $0.id == conversation.id })
            #expect(try exactSnapshot(stored.messages) == sourceSnapshot)
            #expect(stored.draft.utf8.elementsEqual(conversation.draft.utf8))
            let rebuiltReaders = descendants(host).compactMap { ($0 as? WKWebView).map(WeakReader.init) }
            host.rootView = AnyView(Color.clear)
            try await settle(host) {
                reading.viewport == nil && native.host.window == nil && rebuiltReaders.allSatisfy { $0.view == nil }
            }
            await controller.disconnect()
        } catch {
            host.rootView = AnyView(Color.clear)
            await controller.disconnect()
            throw error
        }
    }

    private final class WeakReader {
        weak var view: WKWebView?
        init(_ view: WKWebView) { self.view = view }
    }

    private struct Geometry {
        let phase: String
        let readerCount: Int
        let hydrated: Bool
        let rows: [String: NSRect]
        let readerFrames: [NSRect]
        let clip: NSRect
        let documentSize: NSSize
        let insets: [CGFloat]
        let composer: NSRect
        let header: NSRect?

        var description: String {
            "rows=\(rows.sorted { $0.key < $1.key }) readers=\(readerFrames) clip=\(clip) document=\(documentSize) "
                + "insets=\(insets) composer=\(composer) header=\(String(describing: header))"
        }

        func maximumDrift(from other: Self) -> CGFloat {
            guard readerFrames.count == other.readerFrames.count else { return .infinity }
            var values = [maximumLayoutDrift(from: other)]
            for (frame, target) in zip(readerFrames, other.readerFrames) { values += rectDifferences(frame, target) }
            return values.max() ?? 0
        }

        /// Missing WebKit instances must not obscure the separately measurable
        /// transcript, viewport and input movement behind an infinite drift.
        func maximumLayoutDrift(from other: Self) -> CGFloat {
            var values =
                rectDifferences(clip, other.clip) + rectDifferences(composer, other.composer)
                + [abs(documentSize.width - other.documentSize.width), abs(documentSize.height - other.documentSize.height)]
                + zip(insets, other.insets).map { abs($0 - $1) }
            for (id, frame) in rows {
                guard let target = other.rows[id] else { return .infinity }
                values += rectDifferences(frame, target)
            }
            if let header, let otherHeader = other.header { values += rectDifferences(header, otherHeader) }
            return values.max() ?? 0
        }

        private func rectDifferences(_ a: NSRect, _ b: NSRect) -> [CGFloat] {
            [abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)]
        }
    }

    private struct EntryObservation {
        let firstVisible: Geometry?
        let visibleSamples: [Geometry]
        let settled: Geometry
    }

    private func observeEntry(
        tag: String, host: NSHostingView<AnyView>, session: AgentChatReadingSession, native: AgentChatComposerSession,
        rowIDs: [String], readerIDs: Set<String>
    ) async throws -> EntryObservation {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var visible: [Geometry] = []
        var previous: Geometry?
        var quietSince: ContinuousClock.Instant?
        var lastTraceState: String?
        var traceCount = 0
        while ContinuousClock.now < deadline {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            let sample = geometry(host: host, session: session, native: native, rowIDs: rowIDs, readerIDs: readerIDs)
            let readerCount = sample?.readerCount ?? descendants(host).compactMap { $0 as? WKWebView }.count
            let state =
                "phase=\(session.initialTranscriptPhase) readers=\(readerCount) hydrated=\(session.areReadersHydrated(readerIDs)) "
                + "geometry_available=\(sample != nil)"
            if state != lastTraceState, traceCount < 12 {
                traceCount += 1
                print(
                    "CHAT_ENTRY_LAYOUT_STATE tag=\(tag) trace=\(traceCount) \(state) "
                        + "viewport_exists=\(session.viewport != nil) viewport_window=\(session.viewport?.window != nil) "
                        + "request=\(String(describing: session.viewportRequest)) scrolling=\(session.isScrolling) "
                        + "composer_window=\(native.host.window != nil)")
            }
            lastTraceState = state
            if let sample {
                if session.isInitialTranscriptReady { visible.append(sample) }
                let currentReady =
                    sample.hydrated && sample.readerCount == readerIDs.count
                    && session.isInitialTranscriptReady && session.viewportRequest == nil
                if currentReady, let previous, sample.maximumDrift(from: previous) < 0.01 {
                    if quietSince == nil { quietSince = ContinuousClock.now }
                    if let quietSince, quietSince.duration(to: ContinuousClock.now) >= .milliseconds(500) {
                        return .init(firstVisible: visible.first, visibleSamples: visible, settled: sample)
                    }
                } else {
                    quietSince = nil
                }
                previous = sample
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let readers = descendants(host).compactMap { $0 as? WKWebView }
        let nativeReaders = readers.prefix(6).enumerated().map { index, view in
            "\(index):frame=\(view.convert(view.bounds, to: host)),window=\(view.window != nil),"
                + "same_window=\(view.window === host.window),hidden=\(view.isHiddenOrHasHiddenAncestor)"
        }.joined(separator: ";")
        let liveMarkers = session.markers.filter { $0.value.view != nil }.keys.sorted()
        print(
            "CHAT_ENTRY_LAYOUT_TIMEOUT tag=\(tag) phase=\(session.initialTranscriptPhase) readers=\(readers.count) "
                + "hydrated=\(session.areReadersHydrated(readerIDs)) viewport_exists=\(session.viewport != nil) "
                + "viewport_window=\(session.viewport?.window != nil) request=\(String(describing: session.viewportRequest)) "
                + "scrolling=\(session.isScrolling) live_marker_count=\(liveMarkers.count) live_markers=\(Array(liveMarkers.prefix(8))) "
                + "latest_sample=\(previous.map { "phase=\($0.phase) readers=\($0.readerCount) hydrated=\($0.hydrated) \($0.description)" } ?? "none") "
                + "native_readers=\(nativeReaders) maximum_native_readers=6 no_dom_text=true")
        throw EntryLayoutTimeout()
    }

    private func geometry(
        host: NSView, session: AgentChatReadingSession, native: AgentChatComposerSession,
        rowIDs: [String], readerIDs: Set<String>
    ) -> Geometry? {
        guard let first = rowIDs.first, let marker = session.markers[first]?.view,
            let scroll = marker.enclosingScrollView, let document = scroll.documentView,
            native.host.window === host.window, scroll.contentView.bounds.height > 0
        else { return nil }
        var rows: [String: NSRect] = [:]
        for id in rowIDs {
            guard let view = session.markers[id]?.view, view.window === host.window else { return nil }
            rows[id] = view.convert(view.bounds, to: host)
        }
        let views = descendants(host)
        let readers = views.compactMap { $0 as? WKWebView }
        let readerFrames = readers.map { $0.convert($0.bounds, to: host) }.sorted { $0.minY < $1.minY }
        let header = views.first { $0.accessibilityIdentifier() == "scholium.chat.back" }
        let insets = scroll.contentInsets
        return Geometry(
            phase: String(describing: session.initialTranscriptPhase),
            readerCount: readers.count, hydrated: session.areReadersHydrated(readerIDs), rows: rows, readerFrames: readerFrames,
            clip: scroll.contentView.bounds,
            documentSize: document.frame.size, insets: [insets.top, insets.bottom, insets.left, insets.right],
            composer: native.host.convert(native.host.bounds, to: host), header: header.map { $0.convert($0.bounds, to: host) })
    }

    private func verifyReaders(
        _ readers: [WKWebView], messages: [AgentChatMessage], question: String,
        progressTitle: String, progressParagraph: String, answerParagraph: String, expandedProcess: Bool
    ) async throws {
        var seen: Set<String> = []
        for reader in readers {
            let result = try await reader.callAsyncJavaScript(
                """
                return {fingerprint: configuration.fingerprint,
                  paragraphs: [...document.querySelectorAll('#scholium-document > p')].map(e => e.textContent),
                  heading: document.querySelector('#scholium-document h2')?.textContent ?? null,
                  listItems: [...document.querySelectorAll('#scholium-document > ul > li')].map(e => e.textContent.trim()),
                  cells: [...document.querySelectorAll('#scholium-document th, #scholium-document td')].map(e => e.textContent)};
                """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            let payload = try #require(result as? [String: Any])
            let fingerprint = try #require(payload["fingerprint"] as? String)
            let message = try #require(messages.first { DocumentFingerprint(content: $0.text).sha256 == fingerprint })
            try #require(seen.insert(message.id).inserted)
            let paragraphs = try #require(payload["paragraphs"] as? [String])
            let expected: [String]
            switch message.id {
            case "entry-question": expected = [question]
            case "entry-progress": expected = [progressTitle] + Array(repeating: progressParagraph, count: 14)
            default:
                expected = Array(repeating: answerParagraph, count: 10)
                #expect(payload["heading"] as? String == "合成分析")
                let cells = try #require(payload["cells"] as? [String])
                #expect(try exactSnapshot(cells) == exactSnapshot(["项目", "精确值", "合成来源", "Cafe\u{301} 😀"]))
                let listItems = try #require(payload["listItems"] as? [String])
                #expect(try exactSnapshot(listItems) == exactSnapshot(["原文保持独立。", "解释仍可核对。"]))
            }
            let exactParagraphs = try exactSnapshot(paragraphs) == exactSnapshot(expected)
            if !exactParagraphs {
                let boundedActual = paragraphs.prefix(18).map { String($0.prefix(160)) }
                let boundedExpected = expected.prefix(18).map { String($0.prefix(160)) }
                print(
                    "CHAT_ENTRY_LAYOUT_DOM message=\(message.id) actual_count=\(paragraphs.count) expected_count=\(expected.count) "
                        + "actual=\(String(decoding: try exactSnapshot(boundedActual), as: UTF8.self)) "
                        + "expected=\(String(decoding: try exactSnapshot(boundedExpected), as: UTF8.self)) "
                        + "synthetic_only=true maximum_paragraphs=18 maximum_characters_each=160")
            }
            #expect(exactParagraphs, "Only top-level prose paragraphs are compared; lists and table cells have separate exact oracles")
        }
        #expect(seen == (expandedProcess ? ["entry-question", "entry-progress", "entry-answer"] : ["entry-question", "entry-answer"]))
    }

    private func exactSnapshot<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func settle(_ host: NSView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try #require(ContinuousClock.now < deadline, "The synthetic entry-layout boundary did not settle")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct EntryLayoutTimeout: Error {}
}
