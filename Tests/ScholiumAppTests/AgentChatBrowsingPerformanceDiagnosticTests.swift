import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Public, synthetic browsing inputs only. These measure the reachable helper
/// owners, excluding native list realization, scrolling, WebKit and Quick Look.
@Suite(
    "Chat browsing helper diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
@MainActor
struct AgentChatBrowsingPerformanceDiagnosticTests {
    private static let warmups = 3
    private static let retainedSamples = 20

    @Test("List search, filter, stable ordering and readable preview CPU", arguments: [24, 100])
    func conversationListHelpers(conversationCount: Int) throws {
        let conversations = Self.conversations(conversationCount)
        let unchanged = conversations
        var order = AgentChatListOrder()
        order.reset(conversations.reversed().map(\.id))
        let ordinals = Array((0..<conversationCount).reversed())
        let scenarios: [(name: String, query: String, filter: AgentChatListFilter, ordinals: [Int])] = [
            ("list_empty", "", .all, ordinals),
            ("list_title", "TITLE_TARGET", .all, [5]),
            ("list_tool_detail", "TOOL_TARGET", .all, [7]),
            ("list_material", "原文边界😀", .all, [11]),
            ("list_absent", ".*", .all, []),
            ("list_unsent_absent", "DRAFT_ONLY_SENTINEL", .all, []),
            ("list_draft_filter", "", .drafts, ordinals.filter { $0.isMultiple(of: 5) }),
            ("list_unread_filter", "", .unread, ordinals.filter { $0.isMultiple(of: 4) }),
        ]
        for scenario in scenarios {
            let expectedIDs = scenario.ordinals.map { conversations[$0].id }
            try Self.measure(
                scenario.name, count: conversationCount,
                operation: {
                    // The actual list helpers, composed without a mounted SwiftUI
                    // List. Runtime status reads and native row realization are absent.
                    let matches = conversations.filter {
                        scenario.filter.includes($0, needsInput: false, inProgress: false)
                            && AgentChatSearch.contains($0, query: scenario.query)
                    }
                    return order.arrange(matches).map { conversation in
                        (conversation.id, AgentChatListPresentation.preview(conversation, query: scenario.query))
                    }
                },
                verify: { result in
                    try #require(result.map { $0.0 } == expectedIDs)
                    for (row, ordinal) in zip(result, scenario.ordinals) {
                        if scenario.query.isEmpty {
                            let expected =
                                ordinal.isMultiple(of: 5)
                                ? "DRAFT_ONLY_SENTINEL😀"
                                : "Visible reply \(ordinal) Synthetic plain text."
                            try #require(Array(row.1.utf8) == Array(expected.utf8))
                        } else {
                            try #require(row.1.contains(scenario.query))
                        }
                    }
                    try #require(conversations == unchanged)
                })
        }
    }

    @Test("Find refresh and retained match navigation CPU", arguments: [72, 4_000])
    func conversationFindHelpers(messageCount: Int) throws {
        let messages = Self.findMessages(messageCount, toolsOnly: false)
        let expected = [0, messageCount / 2, messageCount - 1].map { "message-\($0)" }
        try Self.measureFind(messages, markerIDs: expected, prefix: "find")
        var retained = AgentChatFindState()
        retained.query = "MATCH_POINT😀"
        retained.refresh(messages: messages)
        retained.move(backwards: false)
        try #require(retained.selectedID == expected[1])
        let appended = messages + [AgentChatMessage(id: "appended", role: .assistant, text: "MATCH_POINT😀")]
        try Self.measure(
            "find_append_retains_match", count: messageCount,
            operation: {
                var result = retained
                result.refresh(messages: appended)
                return result
            },
            verify: { result in
                try #require(result.messageIDs == expected + ["appended"])
                try #require(result.selectedID == expected[1] && result.position == 2)
            })
    }

    @Test("Find over many retained tool details, including a large output, CPU", arguments: [64, 400])
    func retainedToolDetailSearch(messageCount: Int) throws {
        let messages = Self.findMessages(messageCount, toolsOnly: true)
        let expected = [0, messageCount / 2, messageCount - 1].map { "message-\($0)" }
        try Self.measureFind(messages, markerIDs: expected, prefix: "tool_detail_find")
    }

    @Test("Repeated partial Character candidates in decomposed Latin and emoji output CPU", arguments: [256, 1_024, 8_192])
    func repeatedPartialCharacterCandidates(repetitions: Int) throws {
        let padding = String(repeating: "x", count: 4_096)
        let cases = [
            (name: "combining_acute", unit: "cafe\u{301} ", query: "\u{301}"),
            (name: "emoji_component", unit: "👨‍👩‍👧‍👦 ", query: "👩"),
        ]
        for item in cases {
            let source = padding + String(repeating: item.unit, count: repetitions) + padding
            let message = AgentChatMessage(
                id: "synthetic-partial-output", role: .operation, text: "",
                activity: .init(kind: .tool, status: .completed, source: .runtime, subject: "Synthetic tool", detail: source))
            // The original String API is independent of the production matcher.
            // A native scalar candidate must exist, but no complete Character
            // match can admit this message into Find's results.
            let expectedMatches = source.range(of: item.query, options: .caseInsensitive) == nil ? [] : [message.id]
            try #require(expectedMatches.isEmpty)
            try #require((source as NSString).range(of: item.query, options: .caseInsensitive).location != NSNotFound)
            try #require(source.utf8.count <= AgentChatCommandOutput.maximumUTF8Bytes)
            print(
                "CHAT_BROWSING_PARTIAL_INPUT kind=\(item.name) repetitions=\(repetitions) "
                    + "utf8_bytes=\(source.utf8.count) message_count=1 expected_matches=\(expectedMatches.count)")
            // This candidate-dense diagnostic deliberately uses smaller inputs
            // and fewer samples than the ordinary absent-query workload.
            try Self.measure(
                "partial_candidates_\(item.name)", count: repetitions, warmupCount: 0, sampleCount: 3,
                operation: {
                    var find = AgentChatFindState()
                    find.query = item.query
                    find.refresh(messages: [message], reset: true)
                    return find
                },
                verify: { result in
                    try #require(result.messageIDs == expectedMatches && result.selectedID == nil && result.position == nil)
                })
        }
    }

    @Test("Child inspection public-message projection after verified pagination CPU", arguments: [25, 100])
    func childInspectionProjection(turnCount: Int) async throws {
        let fixture = SyntheticChildPages(turnCount: turnCount)
        let child = AgentChatChildController(
            childID: "synthetic-child", parentID: "synthetic-parent", parentTitle: "Synthetic parent",
            connection: Just(true).eraseToAnyPublisher(),
            request: { try await fixture.request($0, $1) })
        defer { child.cancel() }
        child.refresh()
        try await Self.wait { !child.isWorking && child.snapshot != nil }
        try #require(child.error == nil && child.snapshot?.page.turns.count == 25)
        while child.canLoadEarlier {
            child.loadEarlier()
            try await Self.wait { !child.isWorking }
            try #require(child.error == nil)
        }
        try #require(child.snapshot?.page.turns.map(\.id) == (0..<turnCount).map { "turn-\($0)" })
        let expectedIDs = (0..<turnCount).flatMap { index in
            ["turn-\(index)/request-\(index)", "turn-\(index)/answer-\(index)", "turn-\(index)/tool-\(index)"]
        }
        let snapshot = child.snapshot
        try Self.measure(
            "child_public_projection", count: turnCount * 3,
            operation: {
                child.messages
            },
            verify: { result in
                try #require(result.map(\.id) == expectedIDs)
                for index in 0..<turnCount {
                    let request = result[index * 3]
                    let answer = result[index * 3 + 1]
                    let tool = result[index * 3 + 2]
                    try #require(request.value.role == .user && answer.value.role == .assistant && tool.value.role == .operation)
                    try #require(Array(request.value.text.utf8) == Array(SyntheticChildPages.question(index).utf8))
                    try #require(Array(answer.value.text.utf8) == Array(SyntheticChildPages.answer(index).utf8))
                    try #require(tool.value.activity?.detail == SyntheticChildPages.output(index))
                    try #require([request, answer, tool].allSatisfy { $0.value.turnID == "turn-\(index)" })
                }
                try #require(child.snapshot == snapshot)
            })
        let methods = await fixture.methods
        try #require(methods == ["thread/read"] + Array(repeating: "thread/turns/list", count: turnCount / 25))
    }

    private static func conversations(_ count: Int) -> [AgentChatConversation] {
        let triptych = UUID()
        let detail = String(repeating: "Synthetic public output 中文 e\u{301}.\r\n", count: 96)
        return (0..<count).map { ordinal in
            var conversation = AgentChatConversation(triptychID: triptych)
            conversation.title = "Retained Chat \(ordinal)" + (ordinal == 5 ? " TITLE_TARGET" : "")
            conversation.updatedAt = Date(timeIntervalSince1970: Double(ordinal))
            if ordinal.isMultiple(of: 5) { conversation.draft = "DRAFT_ONLY_SENTINEL😀" }
            if ordinal.isMultiple(of: 4) { conversation.unreadAt = conversation.updatedAt }
            conversation.messages = (0..<40).map { index in
                var message = AgentChatMessage(
                    id: "conversation-\(ordinal)-message-\(index)", role: index.isMultiple(of: 2) ? .user : .assistant,
                    text: "Synthetic public message \(ordinal)/\(index). 中文 e\u{301} 😀.")
                message.turnID = "turn-\(ordinal)-\(index / 2)"
                if index == 10 {
                    message = .init(
                        id: message.id, role: .operation, text: "",
                        activity: .init(
                            kind: .tool, status: .completed, source: .runtime,
                            subject: "Synthetic tool", detail: detail + (ordinal == 7 ? "TOOL_TARGET" : "")))
                } else if index == 0 && ordinal == 11 {
                    let source = String(repeating: "Synthetic retained material. ", count: 96) + "原文边界😀"
                    message = .init(
                        id: message.id, role: .user, text: message.text,
                        attachments: [
                            .init(
                                noteID: UUID(), vaultID: UUID(), relativePath: "Synthetic.md", text: source,
                                fingerprint: .init(content: source))
                        ])
                } else if index == 39 {
                    message.text = "**Visible reply \(ordinal)**\n\nSynthetic plain text."
                    message.phase = .finalAnswer
                }
                return message
            }
            return conversation
        }
    }

    private static func findMessages(_ count: Int, toolsOnly: Bool) -> [AgentChatMessage] {
        let markerIndices = Set([0, count / 2, count - 1])
        let detail = String(repeating: "Synthetic retained output 中文 cafe\u{301}.\r\n", count: 256)
        return (0..<count).map { index in
            let marker = markerIndices.contains(index) ? " MATCH_POINT😀" : ""
            var message = AgentChatMessage(
                id: "message-\(index)", role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "Synthetic public passage \(index). 中文 cafe\u{301} e\u{301}.\r\n" + marker)
            if toolsOnly || index == count / 2 {
                let output =
                    toolsOnly && index == count / 2
                    ? String(repeating: "Synthetic retained output 中文 cafe\u{301}.\r\n", count: 6_000)
                    : detail
                message = .init(
                    id: message.id, role: .operation, text: "",
                    activity: .init(
                        kind: .tool, status: .completed, source: .runtime,
                        subject: "Synthetic tool", detail: output + marker))
                // Keep this workload within the production retained-output limit.
                precondition(message.activity!.detail.utf8.count <= AgentChatCommandOutput.maximumUTF8Bytes)
            }
            message.turnID = "turn-\(index / 2)"
            return message
        }
    }

    private static func measureFind(_ messages: [AgentChatMessage], markerIDs: [String], prefix: String) throws {
        let unchanged = messages
        let scenarios = [
            ("marker", "MATCH_POINT😀", markerIDs),
            ("unicode_all", "CAFE\u{301}", messages.map(\.id)),
            ("absent", ".*", [String]()),
            ("empty", "", [String]()),
        ]
        for (name, query, expectedIDs) in scenarios {
            try measure(
                "\(prefix)_\(name)", count: messages.count,
                operation: {
                    var result = AgentChatFindState()
                    result.query = query
                    result.refresh(messages: messages, reset: true)
                    return result
                },
                verify: { result in
                    try #require(result.messageIDs == expectedIDs && result.selectedID == expectedIDs.first)
                    try #require(result.position == (expectedIDs.isEmpty ? nil : 1))
                    try #require(messages == unchanged)
                })
        }
    }

    private static func measure<Value>(
        _ scenario: String, count: Int, warmupCount: Int = warmups, sampleCount: Int = retainedSamples,
        operation: () -> Value, verify: (Value) throws -> Void
    ) throws {
        var samples: [Double] = []
        for sample in 0..<(warmupCount + sampleCount) {
            let start = ContinuousClock.now
            let value = operation()
            let duration = start.duration(to: .now).components
            let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
            try verify(value)
            try #require(milliseconds.isFinite && milliseconds >= 0)
            if sample >= warmupCount { samples.append(milliseconds) }
        }
        let sorted = samples.sorted()
        let median =
            sampleCount.isMultiple(of: 2)
            ? (sorted[sampleCount / 2 - 1] + sorted[sampleCount / 2]) / 2 : sorted[sampleCount / 2]
        let p95 = sorted[Int(ceil(Double(sampleCount) * 0.95)) - 1]
        print(
            "CHAT_BROWSING_DIAGNOSTIC scenario=\(scenario) count=\(count) warmups=\(warmupCount) samples=\(samples.count) "
                + "median_ms=\(median) p95_ms=\(p95) max_ms=\(sorted.last!) raw_ms=\(samples.map { String($0) }.joined(separator: ",")) "
                + "boundary=helper_cpu native_visible_latency=unmeasured diagnostic_only=true")
    }

    private static func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Synthetic child pagination did not settle")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor SyntheticChildPages {
    let turnCount: Int
    private(set) var methods: [String] = []
    init(turnCount: Int) { self.turnCount = turnCount }

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
        guard method == "thread/turns/list", params["limit"] == .integer(25),
            params["sortDirection"] == .string("desc"), params["itemsView"] == .string("full")
        else { throw CodexConnectionError.invalidMessage }
        let page: Int
        if let cursor = params["cursor"] {
            guard let value = cursor.stringValue, value.hasPrefix("page-"), let number = Int(value.dropFirst(5))
            else { throw CodexConnectionError.invalidMessage }
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
                        "id": .string("tool-\(index)"), "type": .string("commandExecution"),
                        "command": .string("synthetic"), "status": .string("completed"),
                        "aggregatedOutput": .string(Self.output(index)), "exitCode": .integer(0),
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
