import AppKit
import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// One fresh mounted ChildView per size, with no runtime process or network.
/// Native construction is timed separately from endpoint browsing and teardown.
@Suite(
    "Child browsing native mount diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
@MainActor
struct AgentChatChildBrowsingPerformanceDiagnosticTests {
    @Test("Loaded public child history native mounting", arguments: [25, 100])
    func loadedChildNativeMount(turnCount: Int) async throws {
        _ = NSApplication.shared
        let fixture = SyntheticChildReader(turnCount: turnCount)
        let connection = CurrentValueSubject<Bool, Never>(true)
        let child = AgentChatChildController(
            childID: "synthetic-child", parentID: "synthetic-parent", parentTitle: "Synthetic parent",
            connection: connection.eraseToAnyPublisher(), request: { try await fixture.request($0, $1) })
        defer { child.cancel() }
        child.refresh()
        try await Self.wait { !child.isWorking && child.snapshot != nil }
        while child.canLoadEarlier {
            child.loadEarlier()
            try await Self.wait { !child.isWorking }
        }
        try Self.verifySource(child, turnCount: turnCount)
        let snapshot = child.snapshot
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var host: NSHostingView<AgentChatChildView>?
        defer {
            window.orderOut(nil)
            window.contentView = nil
            host = nil
            window.close()
        }
        let start = ContinuousClock.now
        host = NSHostingView(rootView: AgentChatChildView(child: child, openReference: { _ in false }, close: {}))
        host?.sizingOptions = []
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        host?.layoutSubtreeIfNeeded()
        let constructionMilliseconds = Self.milliseconds(start.duration(to: .now))
        weak var weakHost = host
        let capacity = turnCount * 2
        var firstReaderMilliseconds: Double?
        var mountedCount = 0
        var changedAt = ContinuousClock.now
        var completion = "deadline"
        let mountDeadline = start.advanced(by: .seconds(10))
        while ContinuousClock.now < mountDeadline {
            host?.layoutSubtreeIfNeeded()
            let count = host.map { Self.readers(in: $0).count } ?? 0
            if count != mountedCount {
                mountedCount = count
                changedAt = .now
                if count > 0 && firstReaderMilliseconds == nil { firstReaderMilliseconds = Self.milliseconds(start.duration(to: .now)) }
            }
            if mountedCount == capacity {
                completion = "loaded_capacity"
                break
            }
            if mountedCount > 0, changedAt.duration(to: .now) >= .milliseconds(500) {
                completion = "observed_quiet"
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let mountMilliseconds = Self.milliseconds(start.duration(to: .now))
        // All-history mounting is a hypothesis, not a product requirement.
        // A bounded native subset is also a valid measurement outcome.
        try #require(mountedCount > 0 && mountedCount <= capacity)
        var observedReaders = host.map { Self.readers(in: $0).map(WeakReader.init) } ?? []
        let browsingMilliseconds: Double
        do {
            let mountedHost = try #require(host)
            let scroll = try #require(Self.outerScrollViews(in: mountedHost).first)
            let browsingStart = ContinuousClock.now
            _ = try await Self.scrollToEndpoint(
                .first, expected: SyntheticChildReader.question(0), host: mountedHost, scroll: scroll)
            observedReaders.append(contentsOf: Self.readers(in: mountedHost).map(WeakReader.init))
            _ = try await Self.scrollToEndpoint(
                .last, expected: SyntheticChildReader.answer(turnCount - 1), host: mountedHost, scroll: scroll)
            observedReaders.append(contentsOf: Self.readers(in: mountedHost).map(WeakReader.init))
            let firstReader = try await Self.scrollToEndpoint(
                .first, expected: SyntheticChildReader.question(0), host: mountedHost, scroll: scroll)
            observedReaders.append(contentsOf: Self.readers(in: mountedHost).map(WeakReader.init))
            browsingMilliseconds = Self.milliseconds(browsingStart.duration(to: .now))
            try Self.verifySource(child, turnCount: turnCount)
            #expect(child.snapshot == snapshot)
            #expect(await fixture.methods == ["thread/read"] + Array(repeating: "thread/turns/list", count: turnCount / 25))

            // Refresh replaces the latest page. Only this single-page fixture has
            // unchanged source and IDs; the 100-turn fixture must not claim that.
            if turnCount == 25 {
                let reader = firstReader
                let selected = try #require(
                    try await reader.evaluateJavaScript(
                        """
                        window.__scholiumChildLifetime = 'retained-child-reader';
                        const paragraph = document.querySelector('#scholium-document p');
                        const range = document.createRange(); range.selectNodeContents(paragraph);
                        const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
                        selection.toString();
                        """) as? String)
                #expect(Self.sameRenderedText(selected, SyntheticChildReader.question(0)))
                child.refresh()
                try await Self.wait { !child.isWorking }
                try Self.verifySource(child, turnCount: turnCount)
                let refreshedReader = try await Self.visibleReader(
                    expected: SyntheticChildReader.question(0), host: mountedHost, scroll: scroll)
                #expect(refreshedReader === reader)
                let lifetime = try #require(try await reader.evaluateJavaScript("window.__scholiumChildLifetime") as? String)
                #expect(lifetime == "retained-child-reader")
                let retainedSelection = try #require(try await reader.evaluateJavaScript("window.getSelection().toString()") as? String)
                #expect(retainedSelection.utf8.elementsEqual(selected.utf8))
            }
        }
        let methods = await fixture.methods
        let expectedMethods =
            ["thread/read"] + Array(repeating: "thread/turns/list", count: turnCount / 25)
            + (turnCount == 25 ? ["thread/read", "thread/turns/list"] : [])
        #expect(methods == expectedMethods)

        connection.send(false)
        #expect(child.isDisconnected && !child.canRefresh && !child.canLoadEarlier && !child.canStop)
        child.cancel()
        child.refresh()
        #expect(!child.isWorking && !child.canRefresh)
        #expect(await fixture.methods == methods)
        try Self.verifySource(child, turnCount: turnCount)

        observedReaders.append(contentsOf: host.map { Self.readers(in: $0).map(WeakReader.init) } ?? [])
        let cleanupStart = ContinuousClock.now
        window.orderOut(nil)
        window.contentView = nil
        host = nil
        window.close()
        try await Self.wait { weakHost == nil && observedReaders.allSatisfy { $0.value == nil } }
        let cleanupMilliseconds = Self.milliseconds(cleanupStart.duration(to: .now))
        print(
            "CHAT_CHILD_NATIVE_DIAGNOSTIC turns=\(turnCount) public_messages=\(turnCount * 3) reader_capacity=\(capacity) "
                + "mounted_readers=\(mountedCount) mount_completion=\(completion) construct_ms=\(constructionMilliseconds) "
                + "first_reader_ms=\(firstReaderMilliseconds.map { String($0) } ?? "unavailable") mount_ms=\(mountMilliseconds) "
                + "endpoint_browsing_ms=\(browsingMilliseconds) endpoint_dom_checks=3 unchanged_refresh=\(turnCount == 25) "
                + "cleanup_ms=\(cleanupMilliseconds) "
                + "samples=1 warmups=0 fresh_view=true process_cache=uncontrolled "
                + "boundary=native_mount native_visible_latency=unmeasured diagnostic_only=true")
    }

    private final class WeakReader {
        weak var value: AgentChatReadWebView?
        init(_ value: AgentChatReadWebView) { self.value = value }
    }

    private static func readers(in view: NSView) -> [AgentChatReadWebView] {
        if let reader = view as? AgentChatReadWebView { return [reader] }
        return view.subviews.flatMap { readers(in: $0) }
    }

    private enum Endpoint: Equatable { case first, last }

    /// Exclude WebKit's own scroll views: this probe operates the ChildView's
    /// native outer ScrollView, without a production scrolling test seam.
    private static func outerScrollViews(in view: NSView) -> [NSScrollView] {
        if view is AgentChatReadWebView { return [] }
        if let scroll = view as? NSScrollView { return [scroll] }
        return view.subviews.flatMap { outerScrollViews(in: $0) }
    }

    private static func scrollToEndpoint(
        _ endpoint: Endpoint, expected: String, host: NSView, scroll: NSScrollView
    ) async throws -> AgentChatReadWebView {
        try await visibleReader(expected: expected, host: host, scroll: scroll) {
            // LazyVStack's estimated height can change as endpoint rows mount.
            // Re-read native geometry while driving the same endpoint.
            guard let document = scroll.documentView else { return }
            let maximum = max(document.bounds.height - scroll.contentView.bounds.height, 0)
            let firstY: CGFloat = document.isFlipped ? 0 : maximum
            let lastY: CGFloat = document.isFlipped ? maximum : 0
            var bounds = scroll.contentView.bounds
            bounds.origin.y = endpoint == .first ? firstY : lastY
            scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private static func visibleReader(
        expected: String, host: NSView, scroll: NSScrollView, position: () -> Void = {}
    ) async throws -> AgentChatReadWebView {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            position()
            for reader in readers(in: host) where !reader.isHiddenOrHasHiddenAncestor {
                guard reader.convert(reader.bounds, to: scroll.contentView).intersects(scroll.contentView.bounds) else { continue }
                if let text = try? await reader.evaluateJavaScript("document.querySelector('#scholium-document')?.textContent") as? String,
                    sameRenderedText(text, expected)
                {
                    return reader
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The expected public endpoint did not render in the ChildView's outer viewport")
        throw CancellationError()
    }

    private static func sameRenderedText(_ rendered: String, _ source: String) -> Bool {
        rendered.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(
            source.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }

    private static func verifySource(_ child: AgentChatChildController, turnCount: Int) throws {
        try #require(child.error == nil && child.snapshot?.page.turns.map(\.id) == (0..<turnCount).map { "turn-\($0)" })
        let messages = child.messages
        try #require(messages.count == turnCount * 3)
        for index in 0..<turnCount {
            let request = messages[index * 3]
            let answer = messages[index * 3 + 1]
            let tool = messages[index * 3 + 2]
            #expect(request.value.role == .user && answer.value.role == .assistant && tool.value.role == .operation)
            #expect([request.id, answer.id, tool.id] == ["turn-\(index)/request-\(index)", "turn-\(index)/answer-\(index)", "turn-\(index)/tool-\(index)"])
            #expect(request.value.text.utf8.elementsEqual(SyntheticChildReader.question(index).utf8))
            #expect(answer.value.text.utf8.elementsEqual(SyntheticChildReader.answer(index).utf8))
            #expect(tool.value.activity?.detail.utf8.elementsEqual(SyntheticChildReader.output(index).utf8) == true)
            #expect([request, answer, tool].allSatisfy { $0.value.turnID == "turn-\(index)" })
        }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Synthetic child state or native teardown did not settle")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
}

private actor SyntheticChildReader {
    let turnCount: Int
    private(set) var methods: [String] = []
    init(turnCount: Int) { self.turnCount = turnCount }
    // Identical public bytes to the existing child helper diagnostic.
    nonisolated static func question(_ index: Int) -> String { "Synthetic request \(index). 中文 e\u{301} 😀.\r\n" }
    nonisolated static func answer(_ index: Int) -> String { "Synthetic answer \(index). 精确公开材料 cafe\u{301}.\r\n" }
    nonisolated static func output(_ index: Int) -> String { "Synthetic output \(index).\r\n" }

    func request(_ method: String, _ params: [String: MCPJSONValue]) throws -> MCPJSONValue {
        methods.append(method)
        guard params["threadId"] == .string("synthetic-child") else { throw CodexConnectionError.invalidMessage }
        if method == "thread/read" {
            guard params["includeTurns"] == nil else { throw CodexConnectionError.invalidMessage }
            return .object([
                "thread": .object([
                    "id": .string("synthetic-child"), "parentThreadId": .string("synthetic-parent"),
                    "status": .object(["type": .string("idle")]), "historyMode": .string("paginated"),
                ])
            ])
        }
        guard method == "thread/turns/list", params["limit"] == .integer(25), params["sortDirection"] == .string("desc"),
            params["itemsView"] == .string("full")
        else { throw CodexConnectionError.invalidMessage }
        let page: Int
        if let cursor = params["cursor"] {
            guard let value = cursor.stringValue, value.hasPrefix("page-"), let number = Int(value.dropFirst(5)) else {
                throw CodexConnectionError.invalidMessage
            }
            page = number
        } else {
            page = 0
        }
        guard page >= 0 && page < turnCount / 25 else { throw CodexConnectionError.invalidMessage }
        let upper = turnCount - page * 25
        let lower = upper - 25
        let turns: [MCPJSONValue] = (lower..<upper).reversed().map { index in
            .object([
                "id": .string("turn-\(index)"), "status": .string("completed"), "itemsView": .string("full"),
                "items": .array([
                    .object([
                        "id": .string("request-\(index)"), "type": .string("userMessage"),
                        "content": .array([.object(["type": .string("text"), "text": .string(Self.question(index))])]),
                    ]),
                    .object([
                        "id": .string("answer-\(index)"), "type": .string("agentMessage"),
                        "text": .string(Self.answer(index)), "phase": .string("final_answer"),
                    ]),
                    .object([
                        "id": .string("tool-\(index)"), "type": .string("commandExecution"), "command": .string("synthetic"),
                        "status": .string("completed"), "aggregatedOutput": .string(Self.output(index)), "exitCode": .integer(0),
                    ]),
                    .object([
                        "id": .string("private-\(index)"), "type": .string("reasoning"),
                        "text": .string("Synthetic private state must be excluded"),
                    ]),
                ]),
            ])
        }
        return .object(["data": .array(turns), "nextCursor": lower == 0 ? .null : .string("page-\(page + 1)")])
    }
}
