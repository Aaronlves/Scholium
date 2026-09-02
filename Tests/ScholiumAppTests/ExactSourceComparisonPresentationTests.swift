import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Exact source comparison presentation")
struct ExactSourceComparisonPresentationTests {
    @Test("Unified diff keeps three context lines and folds only the remainder")
    func foldsLongUnchangedRunsAroundChanges() {
        let lines = (0..<12).map { unchanged($0) }
            + [changed(12, kind: .startingOnly), changed(13, kind: .endingOnly)]
            + (14..<24).map { unchanged($0) }
            + [changed(24, kind: .endingOnly)]
            + (25..<33).map { unchanged($0) }

        let rows = ExactSourceComparisonPresentation.rows(lines: lines)
        #expect(rows.map(\.id) == [
            "fold-0", "line-9", "line-10", "line-11",
            "line-12", "line-13",
            "line-14", "line-15", "line-16", "fold-17",
            "line-21", "line-22", "line-23", "line-24",
            "line-25", "line-26", "line-27", "fold-28",
        ])
        guard case .folded(_, let leading) = rows[0],
              case .folded(_, let middle) = rows[9],
              case .folded(_, let trailing) = rows[17] else {
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

    @Test("Changed-line whitespace receives a visible exact representation")
    func visibleWhitespace() {
        #expect(ExactSourceWhitespacePresentation.visible("alpha beta  ") ==
            "alpha·beta··")
        #expect(ExactSourceWhitespacePresentation.visible("\talpha") == "⇥alpha")
        #expect(ExactSourceWhitespacePresentation.visible("alpha\u{00A0}beta") ==
            "alpha⟦U+A0⟧beta")
        #expect(ExactSourceWhitespacePresentation.visible("alpha") == nil)
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
