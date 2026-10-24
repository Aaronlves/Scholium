import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// Repeatable cold-page and steady native-layout diagnostics. The window is
/// never ordered: none of these measurements establish paint or scroll FPS.
@Suite("Chat native history scrolling", .serialized)
@MainActor
struct AgentChatScrollPerformanceTests {
    @Test("Earlier pages retain native position, readers, writing and exact history")
    func earlierPagesAndSteadyUpwardScroll() async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/scroll-performance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "com.scholium.tests.scroll-performance.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let triptychID = UUID()
        let fixture = SyntheticHistory(triptychID: triptychID)
        let conversation = fixture.conversation
        let sourceSnapshot = try exactSnapshot(conversation.messages)
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        try await storage.save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root, methodDefaults: defaults) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        let presentation = AgentChatDetailPresentation()
        let reading = AgentChatReadingSession()
        let native = AgentChatComposerSession(conversationID: conversation.id)
        let projection = AgentChatTimelineProjection(conversation.messages)
        #expect(projection.ids.count == 72)
        // Hydration includes native user paragraphs; only the remaining readers mount WebKit.
        let nativeReaderIDs = Set(
            conversation.messages.compactMap { message -> String? in
                guard projection.replyReaderIDs.contains(message.id), message.role == .user,
                    AgentChatReplyProjection.Snapshot(.init(message.text, isStreaming: message.isStreaming)).nativeParagraph != nil
                else { return nil }
                return message.id
            })
        let webReaderIDs = projection.replyReaderIDs.subtracting(nativeReaderIDs)
        #expect(nativeReaderIDs.count == 36 && webReaderIDs.count == 36)
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
        let selection = NSRange(location: 2, length: 3)
        var retainedReader: WKWebView?
        do {
            try await settle(host) { controller.isLoaded }
            try #require(controller.selectedID == conversation.id)
            let initialStart = ContinuousClock.now
            host.rootView = AnyView(
                AgentChatConversationDetailView(
                    controller: controller, isVisible: true, addSelection: { _ in false },
                    noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
                    openAttachment: { _, _ in }, showChanges: { _ in },
                    showConversationChanges: { _ in }, presentation: presentation, readingSession: reading,
                    nativeSession: native, focusRequest: nil, consumeFocusRequest: { _ in },
                    replyNavigation: .constant(nil), openReply: { _ in }, showList: {}, newConversation: {},
                    didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {}))
            let initialCount = AgentChatHistoryWindow.initialPageSize
            #expect(initialCount == 4 && AgentChatHistoryWindow.pageSize == 24)
            var mountedIDs = Set(projection.ids.suffix(initialCount))
            var mountedReaderIDs = projection.replyReaderIDs.intersection(mountedIDs)
            var mountedWebReaderIDs = webReaderIDs.intersection(mountedIDs)
            var boundary = try await observePage(
                tag: "initial", start: initialStart, previousReaders: [], host: host,
                session: reading, native: native, ids: mountedIDs,
                readerIDs: mountedReaderIDs, webReaderIDs: mountedWebReaderIDs)
            #expect(reading.history.range(in: projection.ids).count == initialCount)
            var readerIdentities: [String: ObjectIdentifier] = [:]
            do {
                let initialReaders = try await verifyReaders(
                    in: host, fixture: fixture, expectedIDs: mountedReaderIDs, webReaderIDs: mountedWebReaderIDs)
                retainedReader = initialReaders[fixture.lastAnswerID] as? WKWebView
                try #require(retainedReader != nil)
                readerIdentities = initialReaders.mapValues { ObjectIdentifier($0) }
            }
            let retainedSelection = try #require(
                try await retainedReader?.evaluateJavaScript(
                    """
                    window.__scholiumScrollLifetime = 'same-native-reader';
                    const range = document.createRange();
                    range.selectNodeContents(document.querySelector('#scholium-document h2'));
                    const selection = window.getSelection();
                    selection.removeAllRanges(); selection.addRange(range); selection.toString();
                    """) as? String)
            #expect(retainedSelection.utf8.elementsEqual("合成分析 35".utf8))
            native.host.editor.setSelectedRange(selection)
            reading.pause()
            try await settle(host) { reading.viewportRequest == nil && reading.anchor != nil }

            for page in 0...2 {
                if page > 0 {
                    var retainedAnchor = try #require(reading.anchor)
                    let previousReaders = Set(readers(in: host).map { ObjectIdentifier($0) })
                    let previousWebReaderIDs = mountedWebReaderIDs
                    let start = ContinuousClock.now
                    let queueProbe = MainQueueProbe()
                    reading.page(earlier: true, in: projection.ids, readerIDs: projection.replyReaderIDs)
                    let expectedCount = min(projection.ids.count, initialCount + page * AgentChatHistoryWindow.pageSize)
                    mountedIDs = Set(projection.ids.suffix(expectedCount))
                    mountedReaderIDs = projection.replyReaderIDs.intersection(mountedIDs)
                    mountedWebReaderIDs = webReaderIDs.intersection(mountedIDs)
                    #expect(reading.history.range(in: projection.ids).count == expectedCount)
                    if page == 2 {
                        try await settle(host) { readers(in: host).count > previousReaders.count }
                        let beforeGesture = readers(in: host).count
                        #expect(beforeGesture - previousReaders.count <= AgentChatReaderPreparation.concurrentReaders)
                        #expect(!reading.areReadersHydrated(mountedReaderIDs), "The regression must scroll during preparation, not after it")
                        reading.beginUserScroll()
                        _ = try await scrollUpward(host: host, session: reading, ticks: 30, duringPreparation: true)
                        retainedAnchor = try #require(reading.anchor)
                    }
                    boundary = try await observePage(
                        tag: "earlier-\(page)", start: start, previousReaders: previousReaders, host: host,
                        session: reading, native: native, ids: mountedIDs,
                        readerIDs: mountedReaderIDs, webReaderIDs: mountedWebReaderIDs)
                    queueProbe.stop(tag: "earlier-\(page)")
                    #expect(boundary.heightChanges <= 1, "A prepared history page must enter the transcript in one layout, without per-reader preview swaps")
                    #expect(boundary.newReaderCount == mountedWebReaderIDs.subtracting(previousWebReaderIDs).count)
                    #expect(reading.anchor == retainedAnchor, "Prepending history must retain the native passage and offset")
                    try verifyNativeAnchor(session: reading, expected: retainedAnchor)
                    let readers = try await verifyReaders(
                        in: host, fixture: fixture, expectedIDs: mountedReaderIDs, webReaderIDs: mountedWebReaderIDs)
                    for (id, identity) in readerIdentities {
                        #expect(readers[id].map { ObjectIdentifier($0) } == identity, "Earlier paging must keep every already mounted reader")
                    }
                    readerIdentities = readers.mapValues { ObjectIdentifier($0) }
                    #expect(readers[fixture.lastAnswerID] === retainedReader)
                    #expect(try await retainedReader?.evaluateJavaScript("window.__scholiumScrollLifetime") as? String == "same-native-reader")
                    let selected = try #require(try await retainedReader?.evaluateJavaScript("window.getSelection().toString()") as? String)
                    #expect(selected.utf8.elementsEqual(retainedSelection.utf8))
                }
                let ticks = try await scrollUpward(host: host, session: reading, ticks: 40)
                let tag = page == 0 ? "initial" : "earlier-\(page)"
                let fields: [String] = [
                    "CHAT_HISTORY_SCROLL tag=\(tag) items=72 mounted=\(mountedIDs.count)",
                    "new_readers=\(boundary.newReaderCount) first_new_reader_ms=\(boundary.firstNewReaderMilliseconds)",
                    "all_hydrated_ms=\(boundary.hydratedMilliseconds) stable_geometry_ms=\(boundary.stableMilliseconds)",
                    "page_height_changes=\(boundary.heightChanges)",
                    "document_height=\(boundary.geometry.document.height) mounted_wk=\(boundary.geometry.readerCount)",
                    "native_input_ms=\(ticks.nativeInputMilliseconds) native_input_boundary=clip_write_and_reflect_before_host_layout",
                    "steady_upward_tick_ms=\(ticks.elapsedMilliseconds) native_y=\(ticks.nativeY)",
                    "native_anchor_observed_ms=\(ticks.observedMilliseconds) native_bounds_events=\(ticks.boundsEvents)",
                    "anchor_id=\(reading.anchor?.id ?? "none") anchor_offset=\(reading.anchor?.offset ?? 0)",
                    "tick_boundary=clip_write_reflect_owner_notifications_host_layout_two_actor_yields",
                    "observation_boundary=tick_start_to_clip_bounds_notification_and_matching_native_anchor",
                    "cold_boundary=command_to_current_readers_hydrated_polling_layout quiet_confirmation_ms=500",
                    "evidence=NoPaint window_never_ordered=true timing_gate=none",
                ]
                print(fields.joined(separator: " "))
                #expect(!window.isVisible)
                #expect(reading.areReadersHydrated(mountedReaderIDs) && readers(in: host).count == mountedWebReaderIDs.count)
                #expect(reading.isRetainingPosition && reading.viewportRequest == nil)
                #expect(native.host.editor.string.utf8.elementsEqual(conversation.draft.utf8))
                #expect(native.host.editor.selectedRange() == selection)
                #expect(try exactSnapshot(try #require(controller.selected).messages) == sourceSnapshot)
            }
            try await controller.flushPersistence()
            let saved = try #require(try await storage.load().first { $0.id == conversation.id })
            #expect(try exactSnapshot(saved.messages) == sourceSnapshot)
            #expect(saved.draft.utf8.elementsEqual(conversation.draft.utf8))
            retainedReader = nil
            let departingReaders = readerViews(in: host).map(WeakReader.init)
            host.rootView = AnyView(Color.clear)
            try await settle(host) {
                reading.viewport == nil && native.host.window == nil && departingReaders.allSatisfy { $0.view == nil }
            }
            await controller.disconnect()
        } catch {
            retainedReader = nil
            host.rootView = AnyView(Color.clear)
            await controller.disconnect()
            throw error
        }
    }

    @MainActor private final class MainQueueProbe {
        private let timer = DispatchSource.makeTimerSource(queue: .main)
        private var previous = ContinuousClock.now
        private var gaps: [Double] = []
        init() {
            timer.schedule(deadline: .now(), repeating: .milliseconds(8))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = ContinuousClock.now
                    let delta = self.previous.duration(to: now).components
                    self.gaps.append(Double(delta.seconds) * 1_000 + Double(delta.attoseconds) / 1e15)
                    self.previous = now
                }
            }
            timer.resume()
        }
        func stop(tag: String) {
            timer.cancel()
            let ordered = gaps.sorted()
            print(
                "CHAT_HISTORY_COLD_QUEUE tag=\(tag) heartbeat_ms=8 samples=\(gaps.count) max_gap_ms=\(ordered.last ?? 0) p95_gap_ms=\(ordered.isEmpty ? 0 : ordered[max(0, Int(Double(ordered.count) * 0.95) - 1)]) evidence=NoPaint includes_forced_host_layout=true"
            )
        }
    }

    private struct SyntheticHistory {
        let conversation: AgentChatConversation
        let paragraphs: [String: [String]]
        let cells: [String: [String]]
        let lastAnswerID = "scroll-answer-35"

        init(triptychID: UUID) {
            var conversation = AgentChatConversation(triptychID: triptychID)
            conversation.title = "Synthetic long multilingual conversation"
            conversation.draft = "未发送的草稿 Cafe\u{301} 😀。\nKeep the exact second line."
            var paragraphs: [String: [String]] = [:]
            var cells: [String: [String]] = [:]
            for exchange in 0..<36 {
                let question = "问题 \(exchange)：核对原文 Cafe\u{301}、中文😀与 café。"
                let userID = "scroll-question-\(exchange)"
                let answerID = "scroll-answer-\(exchange)"
                let prose = (0..<6).map { paragraph in
                    "合成分析 \(exchange).\(paragraph)：保留原文、解释与推论的边界。English, Cafe\u{301}, café, العربية, 👩‍🔬 and 中文 keep independent exact source text."
                }
                let tableCells = ["项目", "精确值", "来源 \(exchange)", "Cafe\u{301} 😀"]
                var user = AgentChatMessage(id: userID, role: .user, text: question)
                user.turnID = "scroll-turn-\(exchange)"
                var answer = AgentChatMessage(
                    id: answerID, role: .assistant,
                    text: "## 合成分析 \(exchange)\n\n" + prose.joined(separator: "\n\n")
                        + "\n\n| 项目 | 精确值 |\n|---|---|\n| 来源 \(exchange) | Cafe\u{301} 😀 |\n",
                    phase: .finalAnswer)
                answer.turnID = user.turnID
                conversation.messages += [user, answer]
                paragraphs[userID] = [question]
                paragraphs[answerID] = prose
                cells[userID] = []
                cells[answerID] = tableCells
            }
            self.conversation = conversation
            self.paragraphs = paragraphs
            self.cells = cells
        }
    }

    private struct Geometry {
        let rows: [String: NSRect]
        let clip: NSRect
        let document: NSSize
        let insets: [CGFloat]
        let composer: NSRect
        let readerCount: Int

        func maximumDrift(from other: Self) -> CGFloat {
            guard rows.keys.sorted() == other.rows.keys.sorted(), readerCount == other.readerCount else { return .infinity }
            var differences = rectDifferences(clip, other.clip) + rectDifferences(composer, other.composer)
            differences += [abs(document.width - other.document.width), abs(document.height - other.document.height)]
            differences += zip(insets, other.insets).map { abs($0 - $1) }
            for (id, frame) in rows {
                guard let target = other.rows[id] else { return .infinity }
                differences += rectDifferences(frame, target)
            }
            return differences.max() ?? 0
        }

        private func rectDifferences(_ a: NSRect, _ b: NSRect) -> [CGFloat] {
            [abs(a.minX - b.minX), abs(a.minY - b.minY), abs(a.width - b.width), abs(a.height - b.height)]
        }
    }

    private struct PageObservation {
        let geometry: Geometry
        let newReaderCount: Int
        let firstNewReaderMilliseconds: Double
        let hydratedMilliseconds: Double
        let stableMilliseconds: Double
        let heightChanges: Int
    }

    private func observePage(
        tag: String, start: ContinuousClock.Instant, previousReaders: Set<ObjectIdentifier>, host: NSView,
        session: AgentChatReadingSession, native: AgentChatComposerSession, ids: Set<String>,
        readerIDs: Set<String>, webReaderIDs: Set<String>
    ) async throws -> PageObservation {
        let deadline = start.advanced(by: .seconds(30))
        var firstNewReader: Double?
        var hydrated: Double?
        var previous: Geometry?
        var quietSince: ContinuousClock.Instant?
        var lastState: String?
        var traces = 0
        var heightChanges = 0
        while ContinuousClock.now < deadline {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            let currentReaders = readers(in: host)
            let count = currentReaders.count
            let newReaderCount = Set(currentReaders.map { ObjectIdentifier($0) }).subtracting(previousReaders).count
            let currentHydrated = count == webReaderIDs.count && session.areReadersHydrated(readerIDs)
            if newReaderCount > 0, firstNewReader == nil { firstNewReader = milliseconds(start.duration(to: .now)) }
            if currentHydrated, hydrated == nil { hydrated = milliseconds(start.duration(to: .now)) }
            let state = "wk=\(count) expected=\(webReaderIDs.count) hydrated=\(currentHydrated) phase=\(session.initialTranscriptPhase)"
            if state != lastState, traces < 12 {
                traces += 1
                print("CHAT_HISTORY_PAGE_STATE tag=\(tag) trace=\(traces) \(state) evidence=NoPaint")
            }
            lastState = state
            if let sample = geometry(host: host, session: session, native: native, ids: ids) {
                if let previous, abs(sample.document.height - previous.document.height) > 1 { heightChanges += 1 }
                let ready =
                    currentHydrated && session.isInitialTranscriptReady && session.viewportRequest == nil && !session.isScrolling
                    && session.pendingHistoryPage == nil
                if ready, let previous, sample.maximumDrift(from: previous) < 0.01 {
                    if quietSince == nil { quietSince = .now }
                    if let quietSince, quietSince.duration(to: .now) >= .milliseconds(500) {
                        return PageObservation(
                            geometry: sample, newReaderCount: newReaderCount,
                            firstNewReaderMilliseconds: try #require(firstNewReader),
                            hydratedMilliseconds: try #require(hydrated), stableMilliseconds: milliseconds(start.duration(to: .now)),
                            heightChanges: heightChanges)
                    }
                } else {
                    quietSince = nil
                }
                previous = sample
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        print(
            "CHAT_HISTORY_PAGE_TIMEOUT tag=\(tag) wk=\(readers(in: host).count) expected=\(webReaderIDs.count) "
                + "hydrated=\(session.areReadersHydrated(readerIDs)) phase=\(session.initialTranscriptPhase) "
                + "request=\(String(describing: session.viewportRequest)) viewport=\(session.viewport != nil) "
                + "document_height=\(previous?.document.height ?? 0) evidence=NoPaint no_dom_text=true")
        throw PageTimeout()
    }

    private func geometry(
        host: NSView, session: AgentChatReadingSession, native: AgentChatComposerSession, ids: Set<String>
    ) -> Geometry? {
        guard let first = ids.sorted().first, let marker = session.markers[first]?.view,
            let scroll = marker.enclosingScrollView, let document = scroll.documentView,
            scroll.contentView.bounds.height > 0, native.host.window === host.window
        else { return nil }
        var rows: [String: NSRect] = [:]
        for id in ids {
            guard let row = session.markers[id]?.view, row.window === host.window, row.isDescendant(of: document) else { return nil }
            rows[id] = row.convert(row.bounds, to: document)
        }
        let insets = scroll.contentInsets
        return Geometry(
            rows: rows, clip: scroll.contentView.bounds, document: document.frame.size,
            insets: [insets.top, insets.bottom, insets.left, insets.right],
            composer: native.host.convert(native.host.bounds, to: host), readerCount: readers(in: host).count)
    }

    private struct ScrollSamples {
        let elapsedMilliseconds: [Double]
        let nativeInputMilliseconds: [Double]
        let observedMilliseconds: [Double]
        let boundsEvents: [Int]
        let nativeY: [CGFloat]
    }

    @MainActor private final class NativeBoundsReceipt {
        var count = 0
        var lastY: CGFloat?
    }

    private func scrollUpward(host: NSView, session: AgentChatReadingSession, ticks: Int, duringPreparation: Bool = false) async throws -> ScrollSamples {
        let anchor = try #require(session.anchor)
        let marker = try #require(session.markers[anchor.id]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        try #require(scroll.documentView != nil && session.viewport != nil)
        var elapsed: [Double] = []
        var nativeInput: [Double] = []
        var observed: [Double] = []
        var boundsEvents: [Int] = []
        var positions: [CGFloat] = []
        let receipt = NativeBoundsReceipt()
        let observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak receipt, weak clip = scroll.contentView] _ in
            MainActor.assumeIsolated {
                guard let receipt, let clip else { return }
                receipt.count += 1
                receipt.lastY = clip.bounds.minY
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        // SwiftUI may still have an idle-phase callback after initial layout or
        // DOM selection. Drain the native dispatch queue before starting the
        // synthetic gesture; a cooperative actor yield is not that barrier.
        await nativeMainQueueTurn()
        host.window?.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        await nativeMainQueueTurn()
        if !duringPreparation {
            try await settle(host) { session.viewportRequest == nil && !session.isScrolling }
            session.beginUserScroll()
        }
        let preparingHeight = scroll.documentView?.frame.height
        let preparingReaders = readers(in: host).count
        for tick in 0..<ticks {
            let oldY = scroll.contentView.bounds.minY
            var requested = scroll.contentView.bounds
            requested.origin.y -= 18
            let destination = scroll.contentView.constrainBoundsRect(requested).origin
            try #require(destination.y < oldY, "The fixed synthetic history must have enough room for every upward tick")
            let previousEvents = receipt.count
            let start = ContinuousClock.now
            scroll.contentView.scroll(to: destination)
            scroll.reflectScrolledClipView(scroll.contentView)
            nativeInput.append(milliseconds(start.duration(to: .now)))
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            elapsed.append(milliseconds(start.duration(to: .now)))
            // Native bounds notifications and the viewport's deferred reconcile
            // own capture. Observe their result instead of calling capture or
            // settleUserPosition from the test to manufacture acknowledgement.
            try await waitForNativeAnchor(
                tick: tick, host: host, session: session, scroll: scroll, receipt: receipt,
                previousEvents: previousEvents, destinationY: destination.y)
            observed.append(milliseconds(start.duration(to: .now)))
            boundsEvents.append(receipt.count - previousEvents)
            positions.append(scroll.contentView.bounds.minY)
            #expect(abs(scroll.contentView.bounds.minY - destination.y) < 2, "Native scrolling must not be reversed by retained layout")
            try verifyNativeAnchor(session: session)
            if duringPreparation {
                #expect(
                    readers(in: host).count <= preparingReaders + AgentChatReaderPreparation.concurrentReaders,
                    "Only already admitted work may finish mounting during a native gesture")
                #expect(scroll.documentView?.frame.height == preparingHeight, "An in-flight reader must not reflow the passage during a native gesture")
            }
            // Give unrelated queued work a turn outside the measured tick.
            try await Task.sleep(for: .milliseconds(10))
        }
        if duringPreparation {
            print(
                "CHAT_HISTORY_COLD_SCROLL ticks=\(ticks) frozen_document_height=\(preparingHeight ?? 0) mounted_wk=\(readers(in: host).count) evidence=NoPaint")
        }
        session.endUserScroll()
        await nativeMainQueueTurn()
        try await settle(host) {
            guard session.viewportRequest == nil, !session.isScrolling,
                let retained = session.anchor, let actual = nativeAnchor(in: scroll)
            else { return false }
            return retained.id == actual.id && abs(retained.offset - actual.offset) < 2
        }
        try verifyNativeAnchor(session: session)
        return ScrollSamples(
            elapsedMilliseconds: elapsed, nativeInputMilliseconds: nativeInput, observedMilliseconds: observed, boundsEvents: boundsEvents, nativeY: positions)
    }

    private func nativeMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func waitForNativeAnchor(
        tick: Int, host: NSView, session: AgentChatReadingSession, scroll: NSScrollView,
        receipt: NativeBoundsReceipt, previousEvents: Int, destinationY: CGFloat
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            await nativeMainQueueTurn()
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            if receipt.count > previousEvents, let observedY = receipt.lastY,
                abs(observedY - destinationY) < 2,
                abs(scroll.contentView.bounds.minY - destinationY) < 2,
                session.viewportRequest == nil, let anchor = session.anchor,
                let actual = nativeAnchor(in: scroll), anchor.id == actual.id,
                abs(anchor.offset - actual.offset) < 2
            {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let actual = nativeAnchor(in: scroll)
        print(
            "CHAT_HISTORY_SCROLL_NATIVE_TIMEOUT tick=\(tick) bounds_events=\(receipt.count - previousEvents) "
                + "observed_y=\(String(describing: receipt.lastY)) destination_y=\(destinationY) native_y=\(scroll.contentView.bounds.minY) "
                + "anchor=\(String(describing: session.anchor)) actual=\(String(describing: actual)) "
                + "scrolling=\(session.isScrolling) request=\(String(describing: session.viewportRequest)) "
                + "phase=\(session.initialTranscriptPhase) evidence=NoPaint manual_capture=false")
        throw NativeObservationTimeout()
    }

    private func nativeAnchor(in scroll: NSScrollView) -> AgentChatReadingSession.Anchor? {
        guard let document = scroll.documentView else { return nil }
        let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
        let rows = descendants(document).compactMap { view -> (String, NSRect)? in
            guard let row = view as? AgentChatReadingMarker.View, row.window === scroll.window else { return nil }
            return (row.id, row.convert(row.bounds, to: document))
        }.sorted { $0.1.minY < $1.1.minY }
        guard let actual = rows.first(where: { $0.1.maxY > top + 1 }) ?? rows.last else { return nil }
        return .init(id: actual.0, offset: actual.1.minY - top)
    }

    private func verifyNativeAnchor(session: AgentChatReadingSession, expected: AgentChatReadingSession.Anchor? = nil) throws {
        let anchor = try #require(session.anchor)
        let marker = try #require(session.markers[anchor.id]?.view)
        let scroll = try #require(marker.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let top = scroll.contentView.bounds.minY + scroll.contentInsets.top
        let rows = session.markers.compactMap { id, entry -> (String, NSRect)? in
            guard let row = entry.view, row.window === marker.window, row.isDescendant(of: document) else { return nil }
            return (id, row.convert(row.bounds, to: document))
        }.sorted { $0.1.minY < $1.1.minY }
        let actual = try #require(rows.first(where: { $0.1.maxY > top + 1 }) ?? rows.last)
        #expect(actual.0 == anchor.id, "The semantic anchor must name the actual native row at the viewport's upper edge")
        #expect(abs(anchor.offset - (actual.1.minY - top)) < 2, "The retained offset must agree with native clip geometry")
        if let expected {
            #expect(anchor == expected)
            let frame = marker.convert(marker.bounds, to: document)
            #expect(abs(expected.offset - (frame.minY - top)) < 2)
        }
    }

    private func verifyReaders(
        in host: NSView, fixture: SyntheticHistory, expectedIDs: Set<String>, webReaderIDs: Set<String>
    ) async throws -> [String: NSView] {
        var seen: [String: NSView] = [:]
        for reader in readers(in: host) {
            let result = try await reader.callAsyncJavaScript(
                """
                return {fingerprint: configuration.fingerprint,
                  paragraphs: [...document.querySelectorAll('#scholium-document > p')].map(e => e.textContent),
                  cells: [...document.querySelectorAll('#scholium-document th, #scholium-document td')].map(e => e.textContent)};
                """, arguments: [:], in: nil, contentWorld: SafeMarkdownReadWebView.bridgeContentWorld)
            let payload = try #require(result as? [String: Any])
            let fingerprint = try #require(payload["fingerprint"] as? String)
            let message = try #require(fixture.conversation.messages.first { DocumentFingerprint(content: $0.text).sha256 == fingerprint })
            try #require(seen[message.id] == nil)
            seen[message.id] = reader
            let paragraphs = try #require(payload["paragraphs"] as? [String])
            let cells = try #require(payload["cells"] as? [String])
            #expect(try exactSnapshot(paragraphs) == exactSnapshot(try #require(fixture.paragraphs[message.id])))
            #expect(try exactSnapshot(cells) == exactSnapshot(try #require(fixture.cells[message.id])))
        }
        #expect(Set(seen.keys) == webReaderIDs)
        for reader in descendants(host).compactMap({ $0 as? AgentChatNativeParagraphView }) {
            let message = try #require(
                fixture.conversation.messages.first {
                    $0.role == .user && reader.string.utf8.elementsEqual($0.text.utf8)
                })
            try #require(seen[message.id] == nil)
            seen[message.id] = reader
            #expect(reader.string.utf8.elementsEqual(message.text.utf8))
        }
        #expect(Set(seen.keys) == expectedIDs)
        return seen
    }

    private final class WeakReader {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private func readers(in view: NSView) -> [WKWebView] { descendants(view).compactMap { $0 as? WKWebView } }
    private func readerViews(in view: NSView) -> [NSView] {
        descendants(view).filter { $0 is WKWebView || $0 is AgentChatNativeParagraphView }
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
    private func exactSnapshot<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private func settle(_ host: NSView, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition() {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try #require(ContinuousClock.now < deadline, "The synthetic history boundary did not settle")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private struct PageTimeout: Error {}
    private struct NativeObservationTimeout: Error {}
}
