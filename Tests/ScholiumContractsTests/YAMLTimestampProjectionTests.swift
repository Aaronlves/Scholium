import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Exact YAML timestamp projections")
struct YAMLTimestampProjectionTests {
    private static let boundaryCases: [(seconds: Double, expected: String)] = [
        (-1.0001, "1969-12-31T23:59:59.000Z"),
        (-0.0005, "1970-01-01T00:00:00.000Z"),
        (0, "1970-01-01T00:00:00.000Z"),
        (0.123456789, "1970-01-01T00:00:00.123Z"),
        (978_307_200.9999, "2001-01-01T00:00:01.000Z"),
        (1_700_000_000.123456, "2023-11-14T22:13:20.123Z"),
    ]

    @Test("Date conversion retains UTC text and millisecond rounding boundaries")
    func exactTimestampText() {
        for value in Self.boundaryCases {
            #expect(YAMLValue.convert(Date(timeIntervalSince1970: value.seconds)) == .string(value.expected))
        }
    }

    @Test("Timestamp projection preserves authored bytes, scalar types and body edits")
    func sourceRemainsAuthoritative() throws {
        let frontmatter =
            "day: 2026-10-27 # unchanged\r\nstamp: 2026-10-27T08:01:02.125+08:00\r\nquoted: '2026-10-27'\r\nnested:\r\n  dates: [2026-10-27, 'literal']\r\n"
        let prefix = "\u{FEFF}---\r\n" + frontmatter + "---\r\n"
        let source = prefix + "Original body."
        let document = NoteDocument(relativePath: "timestamps.md", rawContent: source)
        #expect(document.sourceBytes == Data(source.utf8))
        #expect(document.validationWarnings.isEmpty)
        #expect(document.parsedFrontmatter["day"] == .string("2026-10-27T00:00:00.000Z"))
        #expect(document.parsedFrontmatter["stamp"] == .string("2026-10-27T00:01:02.125Z"))
        #expect(document.parsedFrontmatter["quoted"] == .string("2026-10-27"))
        #expect(
            document.parsedFrontmatter["nested"]
                == .object([
                    "dates": .array([.string("2026-10-27T00:00:00.000Z"), .string("literal")])
                ]))
        let updated = try document.applying(.body("Changed body."), timestampKey: nil)
        #expect(Data(updated.utf8) == Data((prefix + "Changed body.").utf8))
    }

    @Test("Concurrent date projections keep each caller's exact value", .timeLimit(.minutes(1)))
    func concurrentProjection() async {
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<64 {
                        for value in Self.boundaryCases {
                            guard YAMLValue.convert(Date(timeIntervalSince1970: value.seconds)) == .string(value.expected) else { return false }
                        }
                    }
                    return true
                }
            }
            for await valid in group { #expect(valid) }
        }
    }
}
