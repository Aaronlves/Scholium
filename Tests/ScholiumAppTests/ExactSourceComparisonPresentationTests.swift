import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Exact source comparison presentation")
struct ExactSourceComparisonPresentationTests {
    @Test("Unified diff keeps three context lines and folds only the remainder")
    func foldsLongUnchangedRunsAroundChanges() {
        let lines =
            (0..<12).map { unchanged($0) }
            + [changed(12, kind: .startingOnly), changed(13, kind: .endingOnly)]
            + (14..<24).map { unchanged($0) }
            + [changed(24, kind: .endingOnly)]
            + (25..<33).map { unchanged($0) }

        let rows = ExactSourceComparisonPresentation.rows(lines: lines)
        #expect(
            rows.map(\.id) == [
                "fold-0", "line-9", "line-10", "line-11",
                "line-12", "line-13",
                "line-14", "line-15", "line-16", "fold-17",
                "line-21", "line-22", "line-23", "line-24",
                "line-25", "line-26", "line-27", "fold-28",
            ])
        guard case .folded(_, let leading) = rows[0],
            case .folded(_, let middle) = rows[9],
            case .folded(_, let trailing) = rows[17]
        else {
            Issue.record("Expected leading, middle, and trailing folded ranges.")
            return
        }
        #expect(leading.count == 9)
        #expect(middle.count == 4)
        #expect(trailing.count == 5)
    }

    @Test("A comparison with no changed rows folds as one honest range")
    func foldsEntireUnchangedComparison() {
        let rows = ExactSourceComparisonPresentation.rows(
            lines: (0..<8).map { unchanged($0) }
        )
        #expect(rows.count == 1)
        guard case .folded(let id, let folded) = rows[0] else {
            Issue.record("Expected one folded unchanged range.")
            return
        }
        #expect(id == 0)
        #expect(folded.count == 8)
    }

    @Test("Difference navigation addresses changed spans, not document rows")
    func differenceNavigation() {
        let lines = [
            unchanged(0), changed(1, kind: .startingOnly),
            changed(2, kind: .endingOnly), unchanged(3),
            changed(4, kind: .endingOnly), changed(5, kind: .endingOnly),
        ]
        #expect(ExactSourceComparisonPresentation.differenceStartLineIDs(lines: lines) == [1, 4])
    }

    @Test("A mixed change presents the prior source before the saved source")
    func removedBeforeInserted() {
        let lines = [
            unchanged(0), changed(1, kind: .endingOnly),
            changed(2, kind: .startingOnly), unchanged(3),
        ]
        #expect(
            ExactSourceComparisonPresentation.rows(lines: lines).map(\.id) == [
                "line-0", "line-2", "line-1", "line-3",
            ])
        #expect(ExactSourceComparisonPresentation.differenceStartLineIDs(lines: lines) == [2])
    }

    @Test("A byte-only source-format change receives a visible cue")
    func formatOnlyCue() throws {
        func compare(_ before: [UInt8], _ after: [UInt8]) throws -> ExactSourceComparison {
            let starting = Data(before)
            let ending = Data(after)
            return try ExactSourceComparisonBuilder.build(
                startingData: starting, endingData: ending,
                startingRevision: DocumentFingerprint(data: starting),
                endingRevision: DocumentFingerprint(data: ending)
            )
        }
        let bom = try compare(Array("same\n".utf8), [0xEF, 0xBB, 0xBF] + Array("same\n".utf8))
        let newline = try compare(Array("same\n".utf8), Array("same\r\n".utf8))
        let words = try compare(Array("old\n".utf8), Array("new\n".utf8))
        #expect(ExactSourceComparisonPresentation.hasOnlySourceFormatChange(bom))
        #expect(ExactSourceComparisonPresentation.hasOnlySourceFormatChange(newline))
        #expect(!ExactSourceComparisonPresentation.hasOnlySourceFormatChange(words))
    }

    @Test("Inline markup keeps exact grapheme and CJK text on both sides")
    func inlineMarkupIsExact() {
        let before = "情绪 e\u{301} 👩🏽‍🔬 is apt and strong."
        let after = "情感 e\u{301} 👩🏽‍🔬 is apt but weak."
        let (removed, inserted) = ExactSourceInlinePresentation.pairedSegments(before, after)
        #expect(Array(removed.map(\.text).joined().utf8) == Array(before.utf8))
        #expect(Array(inserted.map(\.text).joined().utf8) == Array(after.utf8))
        #expect(removed.contains { $0.changed && $0.text.contains("绪") })
        #expect(inserted.contains { $0.changed && $0.text.contains("感") })
        #expect(removed.contains { !$0.changed && $0.text.contains("👩🏽‍🔬") })
        #expect(inserted.contains { !$0.changed && $0.text.contains("👩🏽‍🔬") })
        #expect(removed.contains { $0.changed && $0.text.contains("strong") })
        #expect(inserted.contains { $0.changed && $0.text.contains("weak") })
    }

    @Test("Unpaired removed and inserted lines retain full-line markup")
    func onlyPairedLinesReceiveInlineSegments() {
        let lines = [
            changed(0, kind: .startingOnly),
            changed(1, kind: .startingOnly),
            changed(2, kind: .endingOnly),
        ]
        let segments = ExactSourceInlinePresentation.segmentsByLineID(lines)
        #expect(segments[0] != nil)
        #expect(segments[2] != nil)
        #expect(segments[1] == nil)
    }

    @Test("Normalization-only changes remain visible while respecting graphemes")
    func normalizationOnlyChange() {
        let (removed, inserted) = ExactSourceInlinePresentation.pairedSegments(
            "caf\u{00E9}", "cafe\u{301}"
        )
        #expect(Array(removed.map(\.text).joined().utf8) == Array("caf\u{00E9}".utf8))
        #expect(Array(inserted.map(\.text).joined().utf8) == Array("cafe\u{301}".utf8))
        #expect(removed.last?.changed == true)
        #expect(inserted.last?.changed == true)
    }

    @Test("Long ordinary paragraph retains unchanged interior between separate edits")
    func longParagraphChanges() {
        let middle = (0..<170).map { "term\($0)" }.joined(separator: " ")
        let before = "good " + middle + " coherent"
        let after = "apt " + middle + " precise"
        let (removed, inserted) = ExactSourceInlinePresentation.pairedSegments(before, after)
        #expect(Array(removed.map(\.text).joined().utf8) == Array(before.utf8))
        #expect(Array(inserted.map(\.text).joined().utf8) == Array(after.utf8))
        #expect(removed.contains { !$0.changed && $0.text.contains("term85") })
        #expect(inserted.contains { !$0.changed && $0.text.contains("term85") })
        #expect(removed.contains { $0.changed && $0.text.contains("good") })
        #expect(inserted.contains { $0.changed && $0.text.contains("precise") })
    }

    private func unchanged(_ id: Int) -> ExactSourceComparisonLine {
        ExactSourceComparisonLine(
            id: id,
            kind: .unchanged,
            startingLineNumber: id + 1,
            endingLineNumber: id + 1,
            text: "line \(id)",
            lineEnding: .lf
        )
    }

    private func changed(
        _ id: Int,
        kind: ExactSourceComparisonLineKind
    ) -> ExactSourceComparisonLine {
        ExactSourceComparisonLine(
            id: id,
            kind: kind,
            startingLineNumber: kind == .startingOnly ? id + 1 : nil,
            endingLineNumber: kind == .endingOnly ? id + 1 : nil,
            text: "changed \(id)",
            lineEnding: .lf
        )
    }
}
