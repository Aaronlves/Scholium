import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Synthetic replies only. Repeated projection models the footer work around
/// two Sources open/close cycles, excluding native popover realization and input.
@Suite(
    "Reply browsing helper diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_MEASURE"] == "1"))
@MainActor
struct AgentChatReplyBrowsingPerformanceTests {
    private static let warmups = 3
    private static let retainedSamples = 20
    private static let repeatedProjections = 4

    @Test("Large reply Sources collection CPU and exact explicit-link contents", arguments: [64, 512])
    func sourcesCollection(kilobytes: Int) throws {
        let fixture = try SyntheticReply(kilobytes: kilobytes)
        let oracle = AgentChatReplySource.collect(fixture.text)
        try fixture.verify(oracle)
        try Self.measure(
            "sources_collect", fixture: fixture, projections: 1,
            operation: { AgentChatReplySource.collect(fixture.text) },
            verify: { result in try fixture.verify(result, oracle: oracle) })
    }

    @Test("Unchanged reply Sources projection across repeated open/close-equivalent work CPU", arguments: [64, 512])
    func repeatedSourcesProjection(kilobytes: Int) throws {
        let fixture = try SyntheticReply(kilobytes: kilobytes)
        let oracle = AgentChatReplySource.collect(fixture.text)
        try fixture.verify(oracle)
        let projection = AgentChatReplySourceProjection()
        try fixture.verify(projection.sources(for: fixture.text), oracle: oracle)
        try Self.measure(
            "sources_projection_repeat", fixture: fixture, projections: Self.repeatedProjections,
            operation: {
                (0..<Self.repeatedProjections).map { _ in projection.sources(for: fixture.text) }
            },
            verify: { results in
                try #require(results.count == Self.repeatedProjections)
                for result in results { try fixture.verify(result, oracle: oracle) }
            })
    }

    @Test("Exact source byte comparison CPU for shared, independent and changed buffers", arguments: [64, 512])
    func exactSourceByteComparison(kilobytes: Int) throws {
        let fixture = try SyntheticReply(kilobytes: kilobytes)
        let separate = String(decoding: Array(fixture.text.utf8), as: UTF8.self)
        var changedBytes = Array(fixture.text.utf8)
        changedBytes[changedBytes.count - 1] = 0x21
        let changed = String(decoding: changedBytes, as: UTF8.self)
        let cases: [(name: String, source: String, candidate: String, equal: Bool)] = [
            ("shared", fixture.text, fixture.text, true),
            ("independent", fixture.text, separate, true),
            ("last_byte_changed", fixture.text, changed, false),
            ("canonical_replacement", "[Café](https://example.org/source)", "[Cafe\u{301}](https://example.org/source)", false),
        ]
        for item in cases {
            try #require(item.source.utf8.elementsEqual(item.candidate.utf8) == item.equal)
            let implementations: [(name: String, compare: (String, String) -> Bool)] = [
                ("utf8_sequence", { $0.utf8.elementsEqual($1.utf8) }),
                ("utf8_buffer", ScholiumExactUTF8.equal),
            ]
            for implementation in implementations {
                try Self.measure(
                    "source_bytes_\(item.name)_\(implementation.name)", fixture: fixture, projections: 1,
                    inputUTF8Bytes: item.source.utf8.count, sourceCount: 0,
                    operation: { implementation.compare(item.source, item.candidate) },
                    verify: { result in try #require(result == item.equal) })
            }
        }
    }

    private static func measure<Value>(
        _ scenario: String, fixture: SyntheticReply, projections: Int, inputUTF8Bytes: Int? = nil, sourceCount: Int? = nil,
        operation: () -> Value, verify: (Value) throws -> Void
    ) throws {
        var samples: [Double] = []
        for sample in 0..<(warmups + retainedSamples) {
            let start = ContinuousClock.now
            let value = operation()
            let duration = start.duration(to: .now).components
            let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
            try verify(value)
            try #require(milliseconds.isFinite && milliseconds >= 0)
            if sample >= warmups { samples.append(milliseconds) }
        }
        let sorted = samples.sorted()
        let middle = retainedSamples / 2
        let median = (sorted[middle - 1] + sorted[middle]) / 2
        let p95 = sorted[Int(ceil(Double(retainedSamples) * 0.95)) - 1]
        print(
            "CHAT_REPLY_BROWSING_DIAGNOSTIC scenario=\(scenario) utf8_bytes=\(inputUTF8Bytes ?? fixture.text.utf8.count) "
                + "source_count=\(sourceCount ?? fixture.expected.count) projections=\(projections) warmups=\(warmups) samples=\(samples.count) "
                + "median_ms=\(median) p95_ms=\(p95) max_ms=\(sorted.last!) raw_ms=\(samples.map { String($0) }.joined(separator: ",")) "
                + "boundary=helper_cpu native_visible_latency=unmeasured diagnostic_only=true")
    }

    private struct SyntheticReply {
        let text: String
        let expected: [AgentChatReplySource]

        init(kilobytes: Int) throws {
            let noteID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
            var explicit: [(title: String, url: URL)] = [
                ("公开 Note 中文😀", AgentChatReference.url(noteID: noteID)),
                ("Zotero synthetic record", try #require(URL(string: "zotero://select/library/items/ABCD1234"))),
                ("Relative PDF", try #require(URL(string: "../synthetic.pdf"))),
                ("Unsupported explicit locator", try #require(URL(string: "javascript:alert"))),
            ]
            explicit += try (0..<28).map { ordinal in
                (
                    "Source \(ordinal) cafe\u{301} 中文😀",
                    try #require(URL(string: "https://example.org/synthetic/\(ordinal)?view=source#passage"))
                )
            }
            expected = explicit.map { .init(url: $0.url, title: $0.title) }
            let paragraph = "Synthetic research paragraph. 中文 e\u{301} 😀 remains ordinary uncited text.\r\n\r\n"
            let padding = String(repeating: paragraph, count: max(1, kilobytes * 1_024 / paragraph.utf8.count))
            let links = explicit.map { "[\($0.title)](\($0.url.absoluteString))" }.joined(separator: "\r\n")
            // A later title for the same URL must not replace the first title,
            // and neither ordinary padding nor a bare mention adds a source.
            text =
                links + "\r\n\r\n" + padding
                + "\r\n[Repeated later title](https://example.org/synthetic/0?view=source#passage)\r\n"
        }

        func verify(_ sources: [AgentChatReplySource], oracle: [AgentChatReplySource]? = nil) throws {
            try #require(sources.count == expected.count)
            for (source, wanted) in zip(sources, expected) {
                try #require(source.url == wanted.url)
                try #require(source.url.absoluteString.utf8.elementsEqual(wanted.url.absoluteString.utf8))
                try #require(source.title.utf8.elementsEqual(wanted.title.utf8))
            }
            if let oracle {
                try #require(sources.count == oracle.count)
                for (source, original) in zip(sources, oracle) {
                    try #require(source.url == original.url && source.title.utf8.elementsEqual(original.title.utf8))
                }
            }
        }
    }
}

@Suite("Reply Sources projection fidelity")
@MainActor
struct AgentChatReplySourcesProjectionTests {
    @Test("Repeated unchanged reply projection parses once and retains exact Sources")
    func unchangedReplyReusesItsSourceProjection() throws {
        var parses = 0
        let projection = AgentChatReplySourceProjection { text in
            parses += 1
            return AgentChatReplySource.collect(text)
        }
        let text = "[公开 café 中文😀](https://example.org/source#passage) ordinary uncited text"
        let original = AgentChatReplySource.collect(text)
        try #require(original.count == 1)
        for _ in 0..<4 {
            let sources = projection.sources(for: text)
            try #require(sources.count == original.count)
            #expect(sources.map(\.url) == original.map(\.url))
            #expect(sources[0].title.utf8.elementsEqual(original[0].title.utf8))
        }
        #expect(parses == 1)
    }

    @Test("Canonically equal replacement updates the title's exact Unicode bytes")
    func sourceReplacementKeepsExactUnicode() throws {
        var parses = 0
        let projection = AgentChatReplySourceProjection { text in
            parses += 1
            return AgentChatReplySource.collect(text)
        }
        let first = "[Café 中文😀](https://example.org/source)"
        let replacement = "[Cafe\u{301} 中文😀](https://example.org/source)"
        try #require(first == replacement && !first.utf8.elementsEqual(replacement.utf8))
        let before = try #require(projection.sources(for: first).first)
        let after = try #require(projection.sources(for: replacement).first)
        #expect(before.title.utf8.elementsEqual("Café 中文😀".utf8))
        #expect(after.title.utf8.elementsEqual("Cafe\u{301} 中文😀".utf8))
        #expect(before.url == after.url && !before.title.utf8.elementsEqual(after.title.utf8))
        _ = projection.sources(for: replacement)
        #expect(parses == 2)
    }

    @Test("Source replacement updates link order, title, duplicate suppression and empty availability")
    func currentSourceReplacementRetainsExplicitLinkSemantics() throws {
        var parses = 0
        let projection = AgentChatReplySourceProjection { text in
            parses += 1
            return AgentChatReplySource.collect(text)
        }
        let first = "[First](https://example.org/first) [Relative PDF](../paper.pdf) [Duplicate](https://example.org/first)"
        let replacement = "[Relative changed](../paper.pdf) [Unsupported](javascript:alert) [First changed](https://example.org/first)"
        let retained = projection.sources(for: first)
        try #require(retained.count == 2)
        let updated = projection.sources(for: replacement)
        try #require(updated.count == 3)
        #expect(updated.map(\.url.absoluteString) == ["../paper.pdf", "javascript:alert", "https://example.org/first"])
        #expect(updated.map(\.title) == ["Relative changed", "Unsupported", "First changed"])
        #expect(retained.map(\.title) == ["First", "Relative PDF"])
        let empty = projection.sources(for: "ordinary uncited text")
        #expect(!AgentChatReplyActionAvailability(sources: empty, hasMaterials: false).hasSources)
        #expect(projection.sources(for: first) == retained)
        #expect(parses == 4)
    }

    @Test("Reply lifetimes retain independent current projections")
    func replyProjectionLifetimesAreIndependent() {
        let first = AgentChatReplySourceProjection()
        let second = AgentChatReplySourceProjection()
        let firstText = "[One](https://example.org/one)"
        let secondText = "[Two](https://example.org/two)"
        #expect(first.sources(for: firstText).map(\.title) == ["One"])
        #expect(second.sources(for: secondText).map(\.title) == ["Two"])
        #expect(first.sources(for: "uncited replacement").isEmpty)
        #expect(second.sources(for: secondText).map(\.title) == ["Two"])
    }
}
