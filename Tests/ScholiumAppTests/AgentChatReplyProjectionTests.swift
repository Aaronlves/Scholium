import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Chat projection scheduling", .serialized) @MainActor
struct AgentChatReplyProjectionTests {
    actor Gate {
        var sources: [String] = []
        var waiting: [CheckedContinuation<Void, Never>] = []
        func render(_ source: String) async -> AgentChatReplyProjection.Snapshot {
            sources.append(source)
            await withCheckedContinuation { waiting.append($0) }
            return .init(source)
        }
        func release() { waiting.removeFirst().resume() }
    }
    private func until(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition())
    }
    @Test("A busy parser coalesces deltas, displays progress, and flushes exact final source")
    func coalesces() async throws {
        let gate = Gate()
        let projection = AgentChatReplyProjection { await gate.render($0) }
        projection.submit("First")
        try await until { await gate.sources.count == 1 }
        for i in 1...80 { projection.submit("First" + String(repeating: "文😀", count: i)) }
        await gate.release()
        try await until { await gate.sources.count == 2 }
        #expect(projection.snapshot?.document.rawContent == "First")
        await gate.release()
        let final = "First" + String(repeating: "文😀", count: 80)
        try await until { projection.snapshot?.document.rawContent == final }
        #expect(await gate.sources == ["First", final])
        projection.cancel()
    }
    @Test("Cancelled and replaced source cannot publish an obsolete page")
    func cancellation() async throws {
        let gate = Gate()
        let projection = AgentChatReplyProjection { await gate.render($0) }
        projection.submit("Obsolete")
        try await until { await gate.sources.count == 1 }
        projection.cancel()
        projection.submit("Replacement")
        try await until { await gate.sources.count == 2 }
        await gate.release()
        #expect(projection.snapshot == nil)
        await gate.release()
        try await until { projection.snapshot?.document.rawContent == "Replacement" }
        projection.cancel()
    }
    @Test("Synthetic burst projection", .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
    func burstMeasurement() async throws {
        let body = String(repeating: "A source-faithful paragraph with **emphasis**, 中文 and `code`.\n\n", count: 70)
        let projection = AgentChatReplyProjection()
        let clock = ContinuousClock(), start = ContinuousClock.now
        for i in 0..<80 { projection.submit(body + String(repeating: "尾", count: i)) }
        try await until { projection.snapshot?.document.rawContent == body + String(repeating: "尾", count: 79) }
        print("CHAT_PROJECTION_BURST snapshots=80 elapsed=\(start.duration(to: clock.now)) finalSourceExact=true")
        projection.cancel()
    }
}
