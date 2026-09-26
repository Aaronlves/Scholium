import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Opt-in allocator diagnostics for retained derived projections, not process RSS.
@Suite(
    "Related-content projection retained allocation", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_RELATED_PROJECTION_MEMORY"] == "1"))
struct RelatedContentProjectionMemoryTests {
    @Test("Measure retained allocations for five hundred decoded lexical and passage projections")
    func retainedAllocation() throws {
        let paragraphs = (0..<2).map { paragraph in
            (0..<256).map { "conceptualword\(paragraph)_\($0)" }.joined(separator: " ") + "."
        }
        let source = "# Synthetic retained projection\n\n" + paragraphs.joined(separator: "\n\n") + "\n"
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: source)
        let lexical = RelatedContentLexicalProjection(projection: SearchDocumentProjection(document: document))
        let passages = try RelatedContentSourceProjection(document: document)
        let lexicalBytes = try lexical.encoded()
        let passageBytes = try passages.encoded()
        let lexicalChecksum = RelatedContentSourceProjection.checksum(lexicalBytes)
        let passageChecksum = RelatedContentSourceProjection.checksum(passageBytes)
        print("Projection allocator fixture: 500 copies, \(source.utf8.count) source bytes per Note, 2 paragraphs, 512 distinct body words")
        for sample in 0..<4 {
            try measure("lexical", sample: sample) {
                try (0..<500).map { _ in
                    try RelatedContentLexicalProjection.decode(lexicalBytes, checksum: lexicalChecksum)
                }
            }
            try measure("passage", sample: sample) {
                try (0..<500).map { _ in
                    try RelatedContentSourceProjection.decode(
                        passageBytes, checksum: passageChecksum, sourceUTF16Count: source.utf16.count)
                }
            }
        }
    }

    private func measure<Value>(_ kind: String, sample: Int, build: () throws -> [Value]) throws {
        let start = ContinuousClock.now
        let before = allocatedBytes()
        let values = try build()
        withExtendedLifetime(values) {
            let retained = allocatedBytes() - before
            print("Projection allocator \(kind) sample \(sample): \(retained) retained bytes; decode \(start.duration(to: .now))")
            #expect(values.count == 500)
        }
    }

    private func allocatedBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
    }
}
