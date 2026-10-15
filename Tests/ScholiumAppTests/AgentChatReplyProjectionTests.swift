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
        func releaseAll() {
            let continuations = waiting
            waiting.removeAll()
            for continuation in continuations { continuation.resume() }
        }
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

    @Test("Byte-changed Unicode replacement cannot publish the in-flight old page", arguments: [false, true])
    func inFlightCanonicalReplacement(appendsSuffix: Bool) async throws {
        let gate = Gate()
        let projection = AgentChatReplyProjection { await gate.render($0) }
        defer {
            projection.cancel()
            Task { await gate.releaseAll() }
        }
        let first = "\u{FEFF}# Café 中文😀\r\n\r\nRetained **source**.\r\n"
        let decomposed = "\u{FEFF}# Cafe\u{301} 中文😀\r\n\r\nRetained **source**.\r\n"
        let replacement = decomposed + (appendsSuffix ? "追加 👩‍🔬.\r\n" : "")
        try #require(first == decomposed && !first.utf8.elementsEqual(decomposed.utf8))
        projection.submit(first)
        try await until { await gate.sources.count == 1 }
        projection.submit(replacement)
        await gate.release()
        try await until { await gate.sources.count == 2 }
        #expect(projection.snapshot == nil, "The original page is neither exact current source nor an exact byte prefix")
        await gate.release()
        try await until { projection.snapshot.map { $0.document.rawContent.utf8.elementsEqual(replacement.utf8) } == true }
        let sources = await gate.sources
        #expect(sources.count == 2)
        #expect(sources[0].utf8.elementsEqual(first.utf8) && sources[1].utf8.elementsEqual(replacement.utf8))
    }

    @Test("Exact byte append across a CRLF boundary keeps its completed Unicode prefix eligible")
    func exactAppendPreservesCompletedPrefix() async throws {
        let gate = Gate()
        let projection = AgentChatReplyProjection { await gate.render($0) }
        defer {
            projection.cancel()
            Task { await gate.releaseAll() }
        }
        let prefix = "\u{FEFF}**Cafe\u{301} 中文😀**\r"
        let final = prefix + "\n\r\n追加 👩‍🔬.\r\n"
        projection.submit(prefix)
        try await until { await gate.sources.count == 1 }
        projection.submit(final)
        await gate.release()
        try await until { await gate.sources.count == 2 }
        #expect(projection.snapshot?.document.rawContent.utf8.elementsEqual(prefix.utf8) == true)
        await gate.release()
        try await until { projection.snapshot.map { $0.document.rawContent.utf8.elementsEqual(final.utf8) } == true }
    }

    @Test("Reader task identity and append admission distinguish exact Unicode and line ending bytes")
    func exactIdentityAndPrefix() {
        let pairs: [(source: String, prefix: String)] = [
            ("", ""), ("nonempty", ""), ("", "nonempty"),
            ("Café 中文😀", "Cafe\u{301} 中文😀"), ("Cafe\u{301} 中文😀", "Café 中文😀"),
            ("\u{FEFF}Cafe\u{301} 中文😀\r\nNext", "\u{FEFF}Cafe\u{301} 中文😀\r"),
            ("中文😀👩‍🔬", "中文😀👩"), ("A\u{0}B", "A\u{0}"),
            ("line\nnext", "line\r\n"), ("same", "same"),
        ]
        for pair in pairs {
            let identityMatches = ScholiumExactUTF8.SourceIdentity(pair.source) == ScholiumExactUTF8.SourceIdentity(pair.prefix)
            #expect(identityMatches == pair.source.utf8.elementsEqual(pair.prefix.utf8))
            #expect(ScholiumExactUTF8.hasPrefix(pair.source, pair.prefix) == pair.source.utf8.starts(with: pair.prefix.utf8))
        }
    }

    @Test("Synthetic burst projection", .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
    func burstMeasurement() async throws {
        let body = String(repeating: "A source-faithful paragraph with **emphasis**, 中文 and `code`.\n\n", count: 70)
        let projection = AgentChatReplyProjection()
        let clock = ContinuousClock()
        let start = ContinuousClock.now
        for i in 0..<80 { projection.submit(body + String(repeating: "尾", count: i)) }
        try await until { projection.snapshot?.document.rawContent == body + String(repeating: "尾", count: 79) }
        print("CHAT_PROJECTION_BURST snapshots=80 elapsed=\(start.duration(to: clock.now)) finalSourceExact=true")
        projection.cancel()
    }
}
