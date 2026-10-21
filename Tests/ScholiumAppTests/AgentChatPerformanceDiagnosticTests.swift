import AppKit
import Combine
import Darwin
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

/// Opt-in synthetic diagnostics. No runtime connection, ordered window or product gate.
@Suite(
    "Chat owner performance diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
@MainActor
struct AgentChatPerformanceDiagnosticTests {
    private static let warmups = 3
    private static let retainedSamples = 20

    @Test("Separate long-history projection, changed reconciliation and idempotent reconciliation", arguments: [1_000, 4_000])
    func longHistoryProjectionAndReconciliation(messageCount: Int) async throws {
        try await withOwnedController { controller, id in
            let messages = Self.messages(messageCount)
            let expectedIDs = messages.map(\.id)
            let draft = "\u{FEFF}保留研究者草稿 e\u{301} 😀\r\n"
            let turns: [MCPJSONValue] = messages.enumerated().map { index, message in
                .object([
                    "id": .string("turn-\(index)"), "status": .string("completed"),
                    "items": .array([
                        .object([
                            "id": .string(message.id), "type": .string("agentMessage"),
                            "text": .string(message.text + "已刷新\r\n"), "phase": .string("final_answer"),
                        ])
                    ]),
                ])
            }
            let history: MCPJSONValue = .object([
                "thread": .object(["id": .string("synthetic-thread"), "turns": .array(turns)])
            ])
            var publications = 0
            let observation = controller.$conversations.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            var projectionTimes: [Double] = []
            var decodeTimes: [Double] = []
            var changedTimes: [Double] = []
            var unchangedTimes: [Double] = []
            print(
                "CHAT_HISTORY_BOUNDARIES messages=\(messageCount) decode=public_transcript_from_predecoded_mcp_value "
                    + "hydrate=full_hydrate_including_transcript_decode decode_and_hydrate=independent_samples "
                    + "memory_capture_and_oracles=outside_timing diagnostic_only=true")
            for sample in 0..<(Self.warmups + Self.retainedSamples) {
                var memory: [ProcessMemoryReading] = []
                memory.reserveCapacity(8)
                memory.append(try Self.currentProcessMemory())
                // Release sample-local projections, request snapshots and
                // autoreleased diagnostics before sampling the next boundary.
                // The controller's actual public history remains retained.
                try autoreleasepool {
                    let projectionStart = ContinuousClock.now
                    let projection = AgentChatTimelineProjection(messages)
                    let projectionTime = Self.milliseconds(since: projectionStart)
                    let orderedIDsMatch = projection.ids == expectedIDs
                    try #require(orderedIDsMatch)
                    try #require(projection.items.count == messageCount)

                    let (decodeTime, decodedMemory) = try autoreleasepool {
                        let start = ContinuousClock.now
                        let decoded = try CodexChatTranscript.history(history, threadID: "synthetic-thread")
                        let elapsed = Self.milliseconds(since: start)
                        let alive = try withExtendedLifetime(decoded) { try Self.currentProcessMemory() }
                        try #require(decoded.count == messageCount)
                        let exactDecodedSources = decoded.enumerated().allSatisfy { index, turn in
                            guard turn.id == "turn-\(index)", turn.status == .completed, turn.items.count == 1,
                                let item = turn.items.first,
                                case .assistant(let text, let phase) = item.content
                            else { return false }
                            return item.id == messages[index].id && phase == .finalAnswer && !item.isStreaming
                                && text.utf8.elementsEqual((messages[index].text + "已刷新\r\n").utf8)
                        }
                        try #require(exactDecodedSources)
                        return (elapsed, alive)
                    }
                    memory.append(decodedMemory)
                    memory.append(try Self.currentProcessMemory())

                    controller.update(in: id) {
                        $0.threadID = "synthetic-thread"
                        $0.messages = messages
                        $0.turns = [:]
                        $0.draft = draft
                    }
                    publications = 0
                    let changedRead = try controller.beginHistoryRead(in: id)
                    memory.append(try Self.currentProcessMemory())
                    let changedStart = ContinuousClock.now
                    try controller.hydrate(history, in: id, after: changedRead)
                    let changedTime = Self.milliseconds(since: changedStart)
                    memory.append(try Self.currentProcessMemory())
                    try #require(publications == 1)
                    let reconciled = try #require(controller.selected)
                    try #require(reconciled.messages.count == messageCount)
                    let exactMessagesMatch = reconciled.messages.enumerated().allSatisfy { index, message in
                        message.id == messages[index].id
                            && Array(message.text.utf8) == Array((messages[index].text + "已刷新\r\n").utf8)
                            && message.turnID == "turn-\(index)"
                    }
                    try #require(exactMessagesMatch)
                    try #require(Array(reconciled.draft.utf8) == Array(draft.utf8))
                    publications = 0
                    let unchangedRead = try controller.beginHistoryRead(in: id)
                    memory.append(try Self.currentProcessMemory())
                    let unchangedStart = ContinuousClock.now
                    try controller.hydrate(history, in: id, after: unchangedRead)
                    let unchangedTime = Self.milliseconds(since: unchangedStart)
                    memory.append(try Self.currentProcessMemory())
                    try #require(publications == 0)
                    try #require(controller.selected == reconciled)
                    if sample >= Self.warmups {
                        projectionTimes.append(projectionTime)
                        decodeTimes.append(decodeTime)
                        changedTimes.append(changedTime)
                        unchangedTimes.append(unchangedTime)
                    }
                }
                memory.append(try Self.currentProcessMemory())
                try #require(memory.count == 8)
                Self.printHistoryMemory(memory, messageCount: messageCount, sample: sample)
            }
            Self.summary("timeline_projection", count: messageCount, samples: projectionTimes)
            Self.summary("history_decode_only", count: messageCount, samples: decodeTimes)
            Self.summary("history_changed", count: messageCount, samples: changedTimes)
            Self.summary("history_idempotent", count: messageCount, samples: unchangedTimes)
        }
    }

    @Test("Measure exact Unicode streaming with tail and non-tail retained message targets", arguments: [1_000, 4_000])
    func streamingAcrossRetainedHistory(messageCount: Int) async throws {
        try await withOwnedController { controller, id in
            let messages = Self.messages(messageCount)
            let deltas = (0..<200).map { "文😀 e\u{301} \($0)\r\n" }
            for targetIndex in [messageCount - 1, messageCount / 2] {
                let target = messages[targetIndex]
                let events: [[String: MCPJSONValue]] = deltas.map { delta in
                    [
                        "method": .string("item/agentMessage/delta"),
                        "params": .object([
                            "threadId": .string("synthetic-thread"), "turnId": .string(target.turnID!),
                            "itemId": .string(target.id), "delta": .string(delta),
                        ]),
                    ]
                }
                var samples: [Double] = []
                for sample in 0..<(Self.warmups + Self.retainedSamples) {
                    controller.update(in: id) {
                        $0.threadID = "synthetic-thread"
                        $0.messages = messages
                    }
                    let start = ContinuousClock.now
                    for event in events { await controller.receive(event) }
                    let duration = Self.milliseconds(since: start)
                    let actual = try #require(controller.selected)
                    try #require(actual.messages.count == messageCount)
                    let exactMessagesMatch = actual.messages.enumerated().allSatisfy { index, message in
                        let expected = messages[index].text + (index == targetIndex ? deltas.joined() : "")
                        return message.id == messages[index].id && message.turnID == messages[index].turnID
                            && Array(message.text.utf8) == Array(expected.utf8)
                    }
                    try #require(exactMessagesMatch)
                    if sample >= Self.warmups { samples.append(duration) }
                }
                Self.summary(
                    targetIndex == messageCount - 1 ? "stream_200_tail" : "stream_200_non_tail",
                    count: messageCount, samples: samples)
            }
        }
    }

    @Test("Measure never-ordered transcript entry through exact reader hydration and native positioning")
    func readerEntryHydration() async throws {
        for messageCount in [72, 4_000] {
            try await withOwnedController { controller, id in
                controller.update(in: id) { $0.messages = Self.messages(messageCount) }
                for sample in 0..<3 {
                    let start = ContinuousClock.now
                    try await withOwnedTranscript(controller: controller, id: id) { fixture in
                        try await fixture.waitUntilHydrated()
                        let elapsed = Self.milliseconds(since: start)
                        print(
                            "CHAT_DIAGNOSTIC scenario=reader_entry messages=\(messageCount) sample=\(sample) "
                                + "readers=4 elapsed_ms=\(elapsed) source_fingerprints_exact=true viewport_positioned=true "
                                + "series=three_raw_samples_no_percentiles")
                    }
                }
            }
        }
    }

    @Test("Attribute hidden transcript entry with identical readers and alternating warmed history sizes")
    func readerEntryPhaseAttribution() async throws {
        let visibleMessages = Self.messages(4).enumerated().map { index, original in
            var message = AgentChatMessage(
                id: "visible-reply-\(index)", role: original.role, text: original.text,
                attachments: original.attachments, localMaterials: original.localMaterials,
                changeID: original.changeID, activity: original.activity, phase: original.phase)
            message.turnID = "visible-turn-\(index)"
            return message
        }
        let expectedBytes = visibleMessages.map { Array($0.text.utf8) }
        let expectedFingerprints = visibleMessages.map { DocumentFingerprint(content: $0.text).sha256 }
        let histories = [72, 4_000].map { count in (count, Self.messages(count - 4) + visibleMessages) }
        var samples: [Int: [OffscreenTranscript.EntryPhases]] = [:]
        try await withOwnedController { controller, id in
            for pair in 0..<(Self.warmups + Self.retainedSamples) {
                let order = pair.isMultiple(of: 2) ? histories : histories.reversed().map { $0 }
                for (orderIndex, history) in order.enumerated() {
                    let (count, messages) = history
                    let uniqueIDs = Set(messages.map(\.id))
                    try #require(uniqueIDs.count == count)
                    let actualVisible = Array(messages.suffix(4))
                    try #require(actualVisible == visibleMessages)
                    let exactBytes = actualVisible.map { Array($0.text.utf8) } == expectedBytes
                    let exactFingerprints = actualVisible.map { DocumentFingerprint(content: $0.text).sha256 } == expectedFingerprints
                    try #require(exactBytes && exactFingerprints)
                    controller.update(in: id) { $0.messages = messages }
                    try await withOwnedTranscript(controller: controller, id: id) { fixture in
                        let phases = try await fixture.measureEntryPhases()
                        let durations = [
                            phases.construction, phases.initialLayout, phases.forcedLayout,
                            phases.fourMountedElapsed, phases.nativePositionedElapsed,
                            phases.verifiedElapsed, phases.oracleWall,
                        ]
                        try #require(durations.allSatisfy { $0.isFinite && $0 >= 0 })
                        try #require(phases.fourMountedElapsed >= phases.construction)
                        try #require(phases.nativePositionedElapsed >= phases.fourMountedElapsed)
                        try #require(phases.verifiedElapsed >= phases.nativePositionedElapsed)
                        try #require(phases.oracleAttempts >= 1 && phases.layoutIterations >= 1)
                        let retained = pair >= Self.warmups
                        if retained { samples[count, default: []].append(phases) }
                        print(
                            "CHAT_DIAGNOSTIC scenario=reader_entry_phases messages=\(count) pair=\(pair) order=\(orderIndex) "
                                + "retained=\(retained) readers=4 identical_reader_sources=true source_fingerprints_exact=true viewport_positioned=true "
                                + "construction_ms=\(phases.construction) initial_layout_ms=\(phases.initialLayout) "
                                + "forced_layout_total_ms=\(phases.forcedLayout) layout_iterations=\(phases.layoutIterations) "
                                + "four_mounted_elapsed_ms=\(phases.fourMountedElapsed) native_positioned_elapsed_ms=\(phases.nativePositionedElapsed) "
                                + "verified_elapsed_ms=\(phases.verifiedElapsed) oracle_wall_ms=\(phases.oracleWall) oracle_attempts=\(phases.oracleAttempts) "
                                + "elapsed_boundaries=cumulative_from_construction_start wall_durations=construction_initial_layout_forced_layout_oracle "
                                + "diagnostic_only=true")
                    }
                }
            }
        }
        for count in [72, 4_000] {
            let retained = try #require(samples[count])
            try #require(retained.count == Self.retainedSamples)
            Self.summary("reader_phase_construction", count: count, samples: retained.map(\.construction))
            Self.summary("reader_phase_initial_layout", count: count, samples: retained.map(\.initialLayout))
            Self.summary("reader_phase_forced_layout_total", count: count, samples: retained.map(\.forcedLayout))
            Self.summary("reader_phase_four_mounted_elapsed", count: count, samples: retained.map(\.fourMountedElapsed))
            Self.summary("reader_phase_native_positioned_elapsed", count: count, samples: retained.map(\.nativePositionedElapsed))
            Self.summary("reader_phase_verified_elapsed", count: count, samples: retained.map(\.verifiedElapsed))
            Self.summary("reader_phase_oracle_wall", count: count, samples: retained.map(\.oracleWall))
        }
    }

    @Test("Forty fully released transcript lifecycles retain app-only RSS and native-owner samples")
    func retainedReaderLifetimeMemory() async throws {
        try await withOwnedController { controller, id in
            controller.update(in: id) { $0.messages = Self.messages(72) }
            var rss = [try Self.currentProcessRSS()]
            for cycle in 1...40 {
                try await withOwnedTranscript(controller: controller, id: id) { fixture in
                    try await fixture.waitUntilHydrated()
                }
                let bytes = try Self.currentProcessRSS()
                rss.append(bytes)
                print(
                    "CHAT_DIAGNOSTIC scenario=reader_lifetime cycle=\(cycle) app_only_rss_bytes=\(bytes) "
                        + "live_owned_readers=0 live_owned_hosts=0 live_owned_windows=0 webkit_process_memory=unverified")
            }
            let firstValues = rss[21...30].map { Double($0) }
            let secondValues = rss[31...40].map { Double($0) }
            let firstTail = firstValues.reduce(0, +) / Double(firstValues.count)
            let secondTail = secondValues.reduce(0, +) / Double(secondValues.count)
            for (mean, values) in [(firstTail, firstValues), (secondTail, secondValues)] {
                let minimum = try #require(values.min())
                let maximum = try #require(values.max())
                try #require(mean.isFinite && mean >= minimum && mean <= maximum)
            }
            print(
                "CHAT_DIAGNOSTIC scenario=reader_lifetime_tails cycles=40 first_tail_mean_bytes=\(firstTail) "
                    + "second_tail_mean_bytes=\(secondTail) raw_app_only_rss_bytes=\(rss.map(String.init).joined(separator: ",")) "
                    + "convergence=diagnostic_not_acceptance")
        }
    }

    private func withOwnedTranscript(
        controller: AgentChatController, id: UUID,
        operation: (OffscreenTranscript) async throws -> Void
    ) async throws {
        let fixture = OffscreenTranscript(controller: controller, id: id)
        do {
            try await operation(fixture)
            fixture.close()
            try await fixture.waitUntilReleased()
        } catch {
            fixture.close()
            // Complete the same native ownership barrier on failed hydration,
            // before the controller disconnects and its disposable root is removed.
            try await fixture.waitUntilReleased()
            throw error
        }
    }

    private func withOwnedController(_ operation: (AgentChatController, UUID) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/chat-performance-diagnostics/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let preference = ChatSidebarPreferenceFixture()
        defer { preference.cleanup() }
        let controller = fixtureChatControllerWithAdmission(
            triptychID: UUID(), root: root, workspaceDirectory: { root },
            methodDefaults: preference.defaults,
            contextAccessPreferences: AgentContextAccessPreferences(defaults: preference.defaults),
            saveHistory: { _ in },
            toolHandler: { request, _ in try! .init(requestID: request.requestID, result: .object([:])) })
        do {
            try #require(await controller.waitUntilLoaded())
            let id = try #require(controller.selectedID)
            try await operation(controller, id)
            await controller.disconnect()
        } catch {
            await controller.disconnect()
            throw error
        }
    }

    private static func messages(_ count: Int) -> [AgentChatMessage] {
        (0..<count).map { index in
            var message = AgentChatMessage(
                id: "reply-\(index)", role: .assistant,
                text: "## Synthetic reader \(index)\r\n\r\n"
                    + String(repeating: "保留 😀 e\u{301} 原文与 **解释** 的区别。\r\n\r\n", count: 8)
                    + "| Claim | Status |\r\n|---|---|\r\n| 合成 | 待核对 |\r\n",
                phase: .finalAnswer)
            message.turnID = "turn-\(index)"
            return message
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private static func summary(_ scenario: String, count: Int, samples: [Double]) {
        let sorted = samples.sorted()
        let median = (sorted[9] + sorted[10]) / 2
        let p95 = sorted[18]
        print(
            "CHAT_DIAGNOSTIC scenario=\(scenario) messages=\(count) warmups=3 samples=20 "
                + "median_ms=\(median) p95_ms=\(p95) max_ms=\(sorted[19]) "
                + "raw_ms=\(samples.map(String.init(describing:)).joined(separator: ",")) diagnostic_only=true")
    }

    private struct ProcessMemoryReading {
        let rss: UInt64
        let liveMallocBytes: UInt64
        let liveMallocBlocks: UInt64
        let reservedMallocBytes: UInt64
        let zoneHighWaterSum: UInt64
    }

    /// The SDK reports live blocks/bytes and reserved pages, not cumulative
    /// allocations. Zone high-water sums span the process lifetime and do not
    /// establish a hydrate interval's peak. Allocations tracing is still needed
    /// to attribute churn that allocates and frees within one synchronous call.
    private static func currentProcessMemory() throws -> ProcessMemoryReading {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return .init(
            rss: try currentProcessRSS(),
            liveMallocBytes: UInt64(statistics.size_in_use),
            liveMallocBlocks: UInt64(statistics.blocks_in_use),
            reservedMallocBytes: UInt64(statistics.size_allocated),
            zoneHighWaterSum: UInt64(statistics.max_size_in_use))
    }

    private static func printHistoryMemory(_ readings: [ProcessMemoryReading], messageCount: Int, sample: Int) {
        let values: (KeyPath<ProcessMemoryReading, UInt64>) -> String = { key in
            readings.map { String($0[keyPath: key]) }.joined(separator: ",")
        }
        print(
            "CHAT_HISTORY_MEMORY messages=\(messageCount) sample=\(sample) retained=\(sample >= warmups) "
                + "stages=entry,decode_alive,decode_released,changed_before,changed_after,idempotent_before,idempotent_after,after_sample_scope "
                + "app_only_rss_bytes=\(values(\.rss)) malloc_live_bytes=\(values(\.liveMallocBytes)) "
                + "malloc_live_blocks=\(values(\.liveMallocBlocks)) malloc_reserved_bytes=\(values(\.reservedMallocBytes)) "
                + "malloc_lifetime_zone_high_water_sum_bytes=\(values(\.zoneHighWaterSum)) "
                + "controller_history_retained=true capture_outside_timing=true allocation_churn=unmeasured "
                + "hydrate_interval_peak=unmeasured memory_captures=sequential_process_samples diagnostic_only=true")
    }

    private static func currentProcessRSS() throws -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        try #require(status == KERN_SUCCESS)
        return UInt64(info.resident_size)
    }
}

@MainActor
private final class OffscreenTranscript {
    struct EntryPhases {
        let construction: Double
        let initialLayout: Double
        let forcedLayout: Double
        let layoutIterations: Int
        let fourMountedElapsed: Double
        let nativePositionedElapsed: Double
        let verifiedElapsed: Double
        let oracleWall: Double
        let oracleAttempts: Int
    }
    private let constructionStart: ContinuousClock.Instant
    private var constructionEnd: ContinuousClock.Instant
    private let session = AgentChatReadingSession()
    private let expectedIDs: Set<String>
    private let fingerprints: [String: String]
    private let readers = NSHashTable<WKWebView>.weakObjects()
    private var host: NSHostingView<AnyView>?
    private var window: NSWindow?
    private weak var releasedHost: NSHostingView<AnyView>?
    private weak var releasedWindow: NSWindow?

    init(controller: AgentChatController, id: UUID, constructionStart start: ContinuousClock.Instant = .now) {
        constructionStart = start
        constructionEnd = start
        let messages = controller.conversation(id)!.messages
        let expected = Array(messages.suffix(4))
        expectedIDs = Set(expected.map(\.id))
        fingerprints = Dictionary(
            uniqueKeysWithValues: expected.map {
                ($0.text.components(separatedBy: "\r\n")[0].replacingOccurrences(of: "## ", with: ""), DocumentFingerprint(content: $0.text).sha256)
            })
        let detail = AgentChatConversationDetailView(
            controller: controller, isVisible: true, addSelection: { _ in false },
            noteChoices: [], prepareNotes: { _ in { _ in } }, openReference: { _ in false },
            openAttachment: { _, _ in }, showChanges: { _ in },
            showConversationChanges: { _ in }, presentation: AgentChatDetailPresentation(), readingSession: session,
            nativeSession: AgentChatComposerSession(conversationID: id),
            focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: .constant(nil), openReply: { _ in }, showList: {},
            newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
            showAccountUsage: {})
        let host = NSHostingView(rootView: AnyView(detail))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        self.host = host
        self.window = window
        releasedHost = host
        releasedWindow = window
        constructionEnd = .now
    }

    func waitUntilHydrated() async throws {
        _ = try await waitUntilHydrated(measuringPhases: false)
    }

    func measureEntryPhases() async throws -> EntryPhases {
        let phases = try await waitUntilHydrated(measuringPhases: true)
        return try #require(phases)
    }

    private func waitUntilHydrated(measuringPhases: Bool) async throws -> EntryPhases? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var initialLayout: Double?
        var forcedLayout = 0.0
        var layoutIterations = 0
        var fourMounted: Double?
        var nativePositioned: Double?
        var oracleWall = 0.0
        var oracleAttempts = 0
        while ContinuousClock.now < deadline {
            guard let host, let window else { throw CocoaError(.coderReadCorrupt) }
            try #require(!window.isVisible)
            let layoutStart = measuringPhases ? ContinuousClock.now : nil
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            if let layoutStart {
                let duration = Self.milliseconds(from: layoutStart, to: .now)
                if initialLayout == nil { initialLayout = duration }
                forcedLayout += duration
                layoutIterations += 1
            }
            let mounted = Self.webViews(in: host)
            mounted.forEach(readers.add)
            if measuringPhases, fourMounted == nil, mounted.count == expectedIDs.count {
                fourMounted = Self.milliseconds(from: constructionStart, to: .now)
            }
            if mounted.count == expectedIDs.count, session.initialTranscriptPhase == .visible,
                session.viewport?.window === window, session.viewportRequest == nil,
                session.areReadersHydrated(expectedIDs)
            {
                if measuringPhases, nativePositioned == nil {
                    nativePositioned = Self.milliseconds(from: constructionStart, to: .now)
                }
                let oracleStart = measuringPhases ? ContinuousClock.now : nil
                var settledTitles: Set<String> = []
                for web in mounted {
                    try #require(!web.configuration.websiteDataStore.isPersistent)
                    let title =
                        try? await web.callAsyncJavaScript(
                            """
                            const root = document.getElementById('scholium-document');
                            const title = root?.querySelector('h2')?.textContent;
                            const expected = fingerprints[title];
                            if (!expected || !window.scholiumReadPreparation || !window.scholiumUpdateReply) return null;
                            const result = await window.scholiumReadPreparation.settle('chat-reply', expected, 1, Date.now() + 500);
                            return result.settled && root.getBoundingClientRect().height > 0 ? title : null;
                            """, arguments: ["fingerprints": fingerprints], in: nil,
                            contentWorld: SafeMarkdownReadWebView.bridgeContentWorld) as? String
                    if let title { settledTitles.insert(title) }
                }
                if let oracleStart {
                    oracleWall += Self.milliseconds(from: oracleStart, to: .now)
                    oracleAttempts += 1
                }
                if settledTitles == Set(fingerprints.keys) {
                    let liveMarkerIDs = Set(session.markers.compactMap { $0.value.view == nil ? nil : $0.key })
                    try #require(liveMarkerIDs == expectedIDs)
                    guard measuringPhases else { return nil }
                    return EntryPhases(
                        construction: Self.milliseconds(from: constructionStart, to: constructionEnd),
                        initialLayout: try #require(initialLayout), forcedLayout: forcedLayout,
                        layoutIterations: layoutIterations, fourMountedElapsed: try #require(fourMounted),
                        nativePositionedElapsed: try #require(nativePositioned),
                        verifiedElapsed: Self.milliseconds(from: constructionStart, to: .now),
                        oracleWall: oracleWall, oracleAttempts: oracleAttempts)
                }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.coderReadCorrupt)
    }

    func close() {
        if let host {
            Self.webViews(in: host).forEach { $0.stopLoading() }
            host.rootView = AnyView(EmptyView())
            host.layoutSubtreeIfNeeded()
        }
        window?.contentView = nil
        window?.close()
        host = nil
        window = nil
    }

    func waitUntilReleased() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !readers.allObjects.isEmpty || releasedHost != nil || releasedWindow != nil || session.viewport != nil {
            try #require(ContinuousClock.now < deadline, "Owned native reader resources did not settle after teardown.")
            await Task.yield()
        }
        try #require(session.markers.values.allSatisfy { $0.view == nil })
    }

    private static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: end).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }

    private static func webViews(in view: NSView) -> [WKWebView] {
        if let web = view as? WKWebView { return [web] }
        return view.subviews.flatMap(webViews)
    }
}
