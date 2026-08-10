import Foundation
import ScholiumContracts
import Testing

@Suite("Disposable Research Record comparison")
struct ExactSourceComparisonTests {
    @Test("Comparison is exact across BOM and mixed line endings")
    func exactByteComparison() throws {
        let starting = Data([0xEF, 0xBB, 0xBF]) + Data("first\r\nold\r\n".utf8)
        let ending = Data("first\nnew\nlast".utf8)
        let startingRevision = DocumentFingerprint(data: starting)
        let endingRevision = DocumentFingerprint(data: ending)

        let comparison = try ExactSourceComparisonBuilder.build(
            startingData: starting,
            endingData: ending,
            startingRevision: startingRevision,
            endingRevision: endingRevision
        )

        #expect(comparison.startingRevision == startingRevision)
        #expect(comparison.endingRevision == endingRevision)
        #expect(comparison.startingHasUTF8BOM)
        #expect(!comparison.endingHasUTF8BOM)
        #expect(comparison.lines.contains {
            $0.kind == .startingOnly && $0.text == "old" && $0.lineEnding == .crlf
        })
        #expect(comparison.lines.contains {
            $0.kind == .endingOnly && $0.text == "new" && $0.lineEnding == .lf
        })
        #expect(comparison.lines.last?.text == "last")
        #expect(comparison.lines.last?.lineEnding == ExactSourceComparisonLineEnding.none)
    }

    @Test("Large comparison cooperatively cancels")
    func largeComparisonCancellation() async throws {
        let starting = Data((0..<250_000).map { "old-\($0)\n" }.joined().utf8)
        let ending = Data((0..<250_000).map { "new-\($0)\n" }.joined().utf8)
        let task = Task.detached {
            try ExactSourceComparisonBuilder.build(
                startingData: starting,
                endingData: ending,
                startingRevision: DocumentFingerprint(data: starting),
                endingRevision: DocumentFingerprint(data: ending)
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    @Test("Comparison refuses bytes that mismatch a recorded fingerprint")
    func mismatchedFingerprintRefusal() {
        let recorded = DocumentFingerprint(content: "recorded")
        #expect(throws: ExactSourceComparisonError.self) {
            _ = try ExactSourceComparisonBuilder.build(
                startingData: Data("different".utf8),
                endingData: Data("recorded".utf8),
                startingRevision: recorded,
                endingRevision: recorded
            )
        }
    }
}
