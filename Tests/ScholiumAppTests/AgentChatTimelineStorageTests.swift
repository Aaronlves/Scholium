import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat timeline snapshot storage", .serialized)
@MainActor
struct AgentChatTimelineStorageTests {
    @Test("Only adjacent process messages with the same observed turn form a group")
    func adjacentGroupingPreservesInterleavedAndUnknownTurns() throws {
        let source = Self.mixedMessages()
        let items = AgentChatTimelineItem.group(source)
        let expectedGroups = [
            ["request-a"], ["read-a", "comment-a"], ["read-b"], ["read-a-again"],
            ["unknown-read", "unknown-comment"], ["unknown-answer"],
            ["unknown-read-again"], ["request-b"], ["answer-b"],
            ["read-b-again", "read-b-last"], ["answer-a"],
        ]
        #expect(items.map { $0.messages.map(\.id) } == expectedGroups)
        #expect(items.map(\.id) == expectedGroups.compactMap(\.first))
        #expect(items.map(\.isProcess) == [false, true, true, true, true, false, true, false, false, true, false])
        try Self.expectExact(Array(items.flatMap(\.messages)), source)
        #expect(AgentChatTimelineItem.group([]).isEmpty)
    }

    @Test("Nonzero group indices retain the original snapshot buffer and correct first message")
    func nonzeroSlicesShareSnapshotStorage() throws {
        let source = Self.mixedMessages()
        let items = AgentChatTimelineItem.group(source)
        try #require(items.count == 11)
        let process = items[1]
        #expect(Array(process.messages.indices) == [1, 2])
        #expect(process.messages.startIndex == 1)
        #expect(process.messages[process.messages.startIndex].id == "read-a")
        #expect(process.id == "read-a" && process.isProcess)
        let answer = items[5]
        #expect(answer.messages.startIndex == 7)
        #expect(answer.id == "unknown-answer" && !answer.isProcess)

        // This checks the intended storage change, separately from grouping's
        // value oracle: every range borrows one immutable source snapshot.
        source.withUnsafeBufferPointer { original in
            var offset = 0
            for item in items {
                let expectedOffset = offset
                item.messages.withUnsafeBufferPointer { range in
                    let sharesSnapshot = range.baseAddress == original.baseAddress?.advanced(by: expectedOffset)
                    #expect(sharesSnapshot)
                }
                offset += item.messages.count
            }
            #expect(offset == source.count)
        }
    }

    @Test("Repeated and interleaved turn lookups preserve exact source order and contents")
    func turnLookupUsesObservedIdentityAndOriginalOrder() throws {
        let source = Self.mixedMessages()
        let projection = AgentChatTimelineProjection(source)
        let expectedA = [source[0], source[1], source[2], source[4], source[13]]
        let expectedB = [source[3], source[9], source[10], source[11], source[12]]
        try Self.expectExact(projection.messages(for: "turn-a"), expectedA)
        try Self.expectExact(projection.messages(for: "turn-b"), expectedB)
        #expect(projection.messages(for: nil).isEmpty)
        #expect(projection.messages(for: "absent").isEmpty)
        #expect(projection.hasMessages(for: "turn-a"))
        #expect(projection.hasMessages(for: "turn-b"))
        #expect(!projection.hasMessages(for: nil))
        #expect(!projection.hasMessages(for: "absent"))
        #expect(projection.items.filter { projection.carriesTurnStatus($0) }.map(\.id) == ["read-a", "read-b"])
        #expect(projection.activeActivityID(for: "turn-a") == "read-a")
        #expect(projection.activeActivityID(for: "turn-b") == "read-b-last")
        #expect(projection.activeActivityID(for: nil) == nil)

        // Mutating an on-demand result cannot mutate the retained snapshot or
        // the next result produced for the same observed turn.
        var result = projection.messages(for: "turn-a")
        result[0].text = "Changed caller-owned result"
        result.removeLast()
        try Self.expectExact(projection.messages(for: "turn-a"), expectedA)
        try Self.expectExact(projection.messages, source)
    }

    @Test("Later source replacement and release preserve the complete older timeline snapshot")
    func sourceMutationCannotRewriteOldSnapshot() throws {
        var source = Self.mixedMessages()
        let encodedBefore = try Self.encode(source)
        let projection = AgentChatTimelineProjection(source)
        let standaloneGroups = AgentChatTimelineItem.group(source)
        let expectedA = try Self.encode([source[0], source[1], source[2], source[4], source[13]])
        source[1].text = "New draft source é instead of e\u{301}"
        source[1].turnID = "replacement-turn"
        source.removeFirst()
        source.append(Self.message("new-message", .assistant, turn: "new-turn"))
        source.removeAll(keepingCapacity: false)

        let retainedMessages = try Self.encode(projection.messages)
        let retainedGroups = try Self.encode(Array(projection.items.flatMap(\.messages)))
        let retainedStandaloneGroups = try Self.encode(Array(standaloneGroups.flatMap(\.messages)))
        let retainedTurn = try Self.encode(projection.messages(for: "turn-a"))
        #expect(retainedMessages == encodedBefore)
        #expect(retainedGroups == encodedBefore)
        #expect(retainedStandaloneGroups == encodedBefore)
        #expect(retainedTurn == expectedA)
        #expect(projection.messages(for: "replacement-turn").isEmpty)
        #expect(projection.messages(for: "new-turn").isEmpty)
    }

    @Test(
        "Compare retained allocator storage with the frozen pre-slice timeline owner",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_CHAT_TIMELINE_MEMORY"] == "1"))
    func retainedAllocatorDiagnostic() throws {
        let source = (0..<4_000).map { index in
            Self.message(
                "message-\(index)", index.isMultiple(of: 2) ? .user : .assistant,
                turn: "turn-\(index / 2)", phase: index.isMultiple(of: 2) ? nil : .finalAnswer)
        }
        let expectedIDs = source.map(\.id)
        let expectedReaders = Set(expectedIDs)
        let expectedStatusOwners = stride(from: 1, to: source.count, by: 2).map { "message-\($0)" }
        let warmups = 1
        let retainedSamples = 3
        var measurements: [(owner: String, sample: AllocationSample)] = []

        for pair in 0..<(warmups + retainedSamples) {
            // Alternate order so the candidate does not always inherit the
            // legacy allocator's warmed pages. The fixture is held outside both.
            let owners = pair.isMultiple(of: 2) ? ["frozen_legacy", "candidate"] : ["candidate", "frozen_legacy"]
            for owner in owners {
                let sample: AllocationSample
                if owner == "frozen_legacy" {
                    sample = try Self.measure({ FrozenProjection(source) }) { value in
                        try Self.verifyDiagnostic(
                            messages: value.messages, ids: value.ids, flattened: value.items.flatMap(\.messages),
                            readers: value.replyReaderIDs,
                            statusOwners: value.items.filter { value.carriesTurnStatus($0) }.map(\.id),
                            expectedSource: source, expectedIDs: expectedIDs, expectedReaders: expectedReaders,
                            expectedStatusOwners: expectedStatusOwners)
                        for turn in [0, 1_000, 1_999] {
                            try Self.expectExact(value.messages(for: "turn-\(turn)"), Array(source[(turn * 2)..<(turn * 2 + 2)]))
                        }
                        #expect(value.activeActivityID(for: "turn-0") == nil)
                    }
                } else {
                    sample = try Self.measure({ AgentChatTimelineProjection(source) }) { value in
                        try Self.verifyDiagnostic(
                            messages: value.messages, ids: value.ids, flattened: value.items.flatMap(\.messages),
                            readers: value.replyReaderIDs,
                            statusOwners: value.items.filter { value.carriesTurnStatus($0) }.map(\.id),
                            expectedSource: source, expectedIDs: expectedIDs, expectedReaders: expectedReaders,
                            expectedStatusOwners: expectedStatusOwners)
                        for turn in [0, 1_000, 1_999] {
                            try Self.expectExact(value.messages(for: "turn-\(turn)"), Array(source[(turn * 2)..<(turn * 2 + 2)]))
                        }
                        #expect(value.activeActivityID(for: "turn-0") == nil)
                    }
                }
                if pair >= warmups { measurements.append((owner, sample)) }
                let fields = [
                    "CHAT_TIMELINE_ALLOCATOR owner=\(owner) pair=\(pair) retained=\(pair >= warmups)",
                    "messages=4000 turns=2000 warmups=\(warmups) samples=\(retainedSamples)",
                    "construction_ms=\(sample.milliseconds)",
                    "malloc_live_bytes=\(sample.before.bytes),\(sample.alive.bytes),\(sample.released.bytes)",
                    "malloc_live_blocks=\(sample.before.blocks),\(sample.alive.blocks),\(sample.released.blocks)",
                    "malloc_reserved_bytes=\(sample.before.reserved),\(sample.alive.reserved),\(sample.released.reserved)",
                    "retained_live_bytes_delta=\(sample.byteDelta) retained_live_blocks_delta=\(sample.blockDelta)",
                    "stages=before,extended_lifetime,after_release source_retained=true oracles_outside_timing=true",
                    "scope=process_allocator cumulative_allocations=unmeasured interval_peak=unmeasured rss=unmeasured diagnostic_only=true",
                ]
                print(fields.joined(separator: " "))
            }
        }
        for owner in ["frozen_legacy", "candidate"] {
            let samples = measurements.filter { $0.owner == owner }.map(\.sample)
            try #require(samples.count == retainedSamples)
            print(
                "CHAT_TIMELINE_ALLOCATOR_SUMMARY owner=\(owner) samples=\(samples.count) "
                    + "median_retained_live_bytes=\(samples.map(\.byteDelta).sorted()[1]) "
                    + "median_retained_live_blocks=\(samples.map(\.blockDelta).sorted()[1]) "
                    + "median_construction_ms=\(samples.map(\.milliseconds).sorted()[1]) diagnostic_only=true")
        }
    }

    private static func message(
        _ id: String, _ role: AgentChatMessage.Role, turn: String?, phase: AgentChatMessage.Phase? = nil,
        activity: AgentChatActivity.Status? = nil
    ) -> AgentChatMessage {
        var value = AgentChatMessage(
            id: id, role: role, text: "\u{FEFF}\(id) 中文 😀 café / cafe\u{301}\r\nExact synthetic source.\r\n",
            activity: activity.map { .init(kind: .read, status: $0, source: .runtime, detail: "原文 e\u{301}") },
            phase: phase)
        value.turnID = turn
        return value
    }

    private static func mixedMessages() -> [AgentChatMessage] {
        [
            message("request-a", .user, turn: "turn-a"),
            message("read-a", .operation, turn: "turn-a", activity: .running),
            message("comment-a", .assistant, turn: "turn-a", phase: .commentary),
            message("read-b", .operation, turn: "turn-b", activity: .completed),
            message("read-a-again", .operation, turn: "turn-a"),
            message("unknown-read", .operation, turn: nil),
            message("unknown-comment", .assistant, turn: nil, phase: .commentary),
            message("unknown-answer", .assistant, turn: nil, phase: .finalAnswer),
            message("unknown-read-again", .operation, turn: nil),
            message("request-b", .user, turn: "turn-b"),
            message("answer-b", .assistant, turn: "turn-b", phase: .finalAnswer),
            message("read-b-again", .operation, turn: "turn-b", activity: .running),
            message("read-b-last", .operation, turn: "turn-b", activity: .waitingForInput),
            message("answer-a", .assistant, turn: "turn-a", phase: .finalAnswer),
        ]
    }

    private static func encode(_ messages: [AgentChatMessage]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(messages)
    }

    private static func expectExact(_ actual: [AgentChatMessage], _ expected: [AgentChatMessage]) throws {
        #expect(actual == expected)
        let actualBytes = try encode(actual)
        let expectedBytes = try encode(expected)
        #expect(actualBytes == expectedBytes)
    }

    private static func verifyDiagnostic(
        messages: [AgentChatMessage], ids: [String], flattened: [AgentChatMessage], readers: Set<String>,
        statusOwners: [String], expectedSource: [AgentChatMessage], expectedIDs: [String],
        expectedReaders: Set<String>, expectedStatusOwners: [String]
    ) throws {
        try #require(ids == expectedIDs)
        #expect(readers == expectedReaders)
        #expect(statusOwners == expectedStatusOwners)
        try expectExact(messages, expectedSource)
        try expectExact(flattened, expectedSource)
    }

    private struct AllocatorReading {
        let bytes: UInt64
        let blocks: UInt64
        let reserved: UInt64

        static func capture() -> Self {
            var statistics = malloc_statistics_t()
            malloc_zone_statistics(nil, &statistics)
            return .init(
                bytes: UInt64(statistics.size_in_use), blocks: UInt64(statistics.blocks_in_use),
                reserved: UInt64(statistics.size_allocated))
        }
    }

    private struct AllocationSample {
        let before: AllocatorReading
        let alive: AllocatorReading
        let released: AllocatorReading
        let milliseconds: Double
        var byteDelta: Int64 { Int64(alive.bytes) - Int64(before.bytes) }
        var blockDelta: Int64 { Int64(alive.blocks) - Int64(before.blocks) }
    }

    private static func measure<Value>(
        _ construct: () -> Value, verify: (Value) throws -> Void
    ) rethrows -> AllocationSample {
        let before = AllocatorReading.capture()
        var milliseconds = 0.0
        let alive = try autoreleasepool {
            let start = ContinuousClock.now
            let value = construct()
            let elapsed = start.duration(to: .now).components
            milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            return try withExtendedLifetime(value) {
                let retained = AllocatorReading.capture()
                try verify(value)
                return retained
            }
        }
        return .init(before: before, alive: alive, released: .capture(), milliseconds: milliseconds)
    }

    /// Frozen before the slice/index change. This is a diagnostic comparator,
    /// never a production fallback or the independent grouping oracle above.
    private struct FrozenItem {
        var messages: [AgentChatMessage]
        var id: String { messages[0].id }
        var isProcess: Bool { Self.isProcess(messages[0]) }
        static func isProcess(_ message: AgentChatMessage) -> Bool {
            message.role == .operation || message.phase == .commentary || message.plan != nil
        }
        static func group(_ messages: [AgentChatMessage]) -> [Self] {
            var items: [Self] = []
            for message in messages {
                if Self.isProcess(message), items.last?.isProcess == true,
                    items.last?.messages.last?.turnID == message.turnID
                {
                    items[items.count - 1].messages.append(message)
                } else {
                    items.append(.init(messages: [message]))
                }
            }
            return items
        }
    }

    private struct FrozenProjection {
        let messages: [AgentChatMessage]
        let items: [FrozenItem]
        let ids: [String]
        let replyReaderIDs: Set<String>
        private let messagesByTurn: [String: [AgentChatMessage]]
        private let statusOwnerIDs: Set<String>
        private let activeActivityIDs: [String: String]

        init(_ messages: [AgentChatMessage]) {
            self.messages = messages
            self.items = FrozenItem.group(messages)
            self.ids = self.items.map(\.id)
            var messagesByTurn: [String: [AgentChatMessage]] = [:]
            var firstNonUserIDs: [String: String] = [:]
            var lastUserIDs: [String: String] = [:]
            var activeActivityIDs: [String: String] = [:]
            for message in messages {
                guard let turnID = message.turnID else { continue }
                messagesByTurn[turnID, default: []].append(message)
                if message.role != .user, firstNonUserIDs[turnID] == nil { firstNonUserIDs[turnID] = message.id }
                if message.role == .user { lastUserIDs[turnID] = message.id }
                if message.activity?.status.isActive == true { activeActivityIDs[turnID] = message.id }
            }
            self.messagesByTurn = messagesByTurn
            self.activeActivityIDs = activeActivityIDs
            var statusOwnerIDs: Set<String> = []
            var replyReaderIDs: Set<String> = []
            for item in items {
                if !item.isProcess {
                    for message in item.messages where message.asyncQuestion == nil && !message.text.isEmpty {
                        replyReaderIDs.insert(message.id)
                    }
                }
                guard let turnID = item.messages.first?.turnID else { continue }
                if (firstNonUserIDs[turnID] ?? lastUserIDs[turnID]) == item.id { statusOwnerIDs.insert(item.id) }
            }
            self.statusOwnerIDs = statusOwnerIDs
            self.replyReaderIDs = replyReaderIDs
        }

        func messages(for turnID: String?) -> [AgentChatMessage] {
            guard let turnID else { return [] }
            return messagesByTurn[turnID] ?? []
        }
        func carriesTurnStatus(_ item: FrozenItem) -> Bool { statusOwnerIDs.contains(item.id) }
        func activeActivityID(for turnID: String?) -> String? { turnID.flatMap { activeActivityIDs[$0] } }
    }
}
