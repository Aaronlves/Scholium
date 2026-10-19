import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Editor source offset map")
struct EditorSourceOffsetMapTests {
    @Test("LF, CRLF, Unicode, BOM, and normalization variants match the slow reference")
    func exactMappingMatrix() {
        let sources = [
            "",
            "LF\nonly\n",
            "CRLF\r\nonly\r\n",
            "mixed\r\nline\nend\r\n",
            "\u{FEFF}emoji 🧑🏽‍💻\r\n中文\n",
            "NFC é\r\nNFD e\u{301}\r\n",
            "\r\n\u{301}",
        ]

        for source in sources {
            assertEquivalent(EditorSourceOffsetMap(source: source), source: source)
        }
    }

    @Test("An offset between CR and LF is not an exact-source boundary")
    func rejectsSplitCRLFBoundary() {
        let map = EditorSourceOffsetMap(source: "A\r\nB")
        #expect(map.editorUTF16Offset(forSourceUTF16Offset: 2) == nil)
        #expect(map.sourceUTF16Offset(forEditorUTF16Offset: 1) == 1)
        #expect(map.sourceUTF16Offset(forEditorUTF16Offset: 2) == 3)
    }

    @Test("Accepted deltas incrementally update changed CRLF boundaries")
    func incrementalDeltasMatchFullRebuild() throws {
        var source = "\u{FEFF}A\r\nB\n🧑🏽‍💻\r\nC e\u{301}\n"
        var map = EditorSourceOffsetMap(source: source)
        let batches: [[MarkdownEditorDelta]] = [
            [MarkdownEditorDelta(fromUTF16: 1, toUTF16: 1, insertion: "前\r\n")],
            [MarkdownEditorDelta(fromUTF16: 4, toUTF16: 6, insertion: "\n")],
            [
                MarkdownEditorDelta(fromUTF16: 0, toUTF16: 1, insertion: ""),
                MarkdownEditorDelta(
                    fromUTF16: (source as NSString).length - 1,
                    toUTF16: (source as NSString).length,
                    insertion: "\r\n尾"
                ),
            ],
            [
                MarkdownEditorDelta(
                    fromUTF16: 0,
                    toUTF16: (source as NSString).length,
                    insertion: "LF\n重建\r\nfinal"
                )
            ],
        ]

        for deltas in batches {
            try applyAndAssert(deltas, source: &source, map: &map)
        }
    }

    @Test("Empty source, complete deletion, CRLF joins, and overlapping rescans match a rebuild")
    func incrementalBoundaryMatrix() throws {
        let deletedSource = "A\r\n🧭e\u{301}\r\n"
        let cases: [(source: String, deltas: [MarkdownEditorDelta])] = [
            ("", []),
            ("", [.init(fromUTF16: 0, toUTF16: 0, insertion: "\r\n")]),
            (deletedSource, [.init(fromUTF16: 0, toUTF16: deletedSource.utf16.count, insertion: "")]),
            ("\r\n", [.init(fromUTF16: 0, toUTF16: 1, insertion: "")]),
            ("\r\n", [.init(fromUTF16: 1, toUTF16: 2, insertion: "")]),
            ("A\rx\nB", [.init(fromUTF16: 2, toUTF16: 3, insertion: "")]),
            ("A\r\nB", [.init(fromUTF16: 2, toUTF16: 2, insertion: "X")]),
            ("A\r\nB", [.init(fromUTF16: 1, toUTF16: 3, insertion: "\r\n\r\n")]),
            ("A\r\n", [.init(fromUTF16: 3, toUTF16: 3, insertion: "尾\r\n")]),
            // Both changed-boundary scans see the same newly formed pair.
            (
                "\rX\n",
                [
                    .init(fromUTF16: 1, toUTF16: 2, insertion: ""),
                    .init(fromUTF16: 2, toUTF16: 2, insertion: "\r"),
                ]
            ),
            (
                "a\r\nb\r\nc",
                [
                    .init(fromUTF16: 3, toUTF16: 6, insertion: ""),
                    .init(fromUTF16: 0, toUTF16: 3, insertion: ""),
                ]
            ),
            // Equal-position insertions are accepted by DeltaApplier; their
            // rescanned windows must still produce one sorted, unique index.
            (
                "A\r\nB",
                [
                    .init(fromUTF16: 1, toUTF16: 1, insertion: "\r"),
                    .init(fromUTF16: 1, toUTF16: 1, insertion: "\n🧭\r\n"),
                ]
            ),
            (
                "\u{FEFF}🧭\r\nx\r\ny",
                [
                    .init(fromUTF16: 9, toUTF16: 9, insertion: "尾\r\n"),
                    .init(fromUTF16: 5, toUTF16: 6, insertion: ""),
                    .init(fromUTF16: 0, toUTF16: 0, insertion: "前\r\n"),
                ]
            ),
        ]
        for fixture in cases {
            var source = fixture.source
            var map = EditorSourceOffsetMap(source: source)
            try applyAndAssert(fixture.deltas, source: &source, map: &map)
        }
    }

    @Test("Repeated deterministic nonoverlapping batches retain exact Unicode and CRLF mappings")
    func repeatedIncrementalUpdatesMatchBothOracles() throws {
        var source = "\u{FEFF}A\r\n中文\n🧭e\u{301}\r\nTail\r\n"
        var map = EditorSourceOffsetMap(source: source)
        var generator = DeterministicGenerator()
        let insertions = ["", "\r", "\n", "\r\n", "\n\r", "\r\n\r\n", "🧭", "中文", "e\u{301}", "尾\r\n"]
        for iteration in 0..<48 {
            // Split CRLF freely, but keep surrogate pairs intact so every
            // fixture is a valid exact-source string after NSString editing.
            var boundaries = [0]
            var offset = 0
            for scalar in source.unicodeScalars {
                offset += scalar.value > 0xFFFF ? 2 : 1
                boundaries.append(offset)
            }
            var deltas: [MarkdownEditorDelta] = []
            var lower = 0
            for _ in 0..<3 {
                let from = lower + generator.next(upperBound: boundaries.count - lower)
                let to = from + generator.next(upperBound: min(4, boundaries.count - 1 - from) + 1)
                deltas.append(
                    .init(
                        fromUTF16: boundaries[from], toUTF16: boundaries[to],
                        insertion: insertions[generator.next(upperBound: insertions.count)]))
                lower = to
            }
            if iteration.isMultiple(of: 2) { deltas.reverse() }
            try applyAndAssert(deltas, source: &source, map: &map)
        }
    }

    private func applyAndAssert(
        _ deltas: [MarkdownEditorDelta], source: inout String, map: inout EditorSourceOffsetMap
    ) throws {
        let next = try MarkdownEditorDeltaApplier.apply(deltas, to: source)
        let nextNSString = next as NSString
        map.apply(
            deltas,
            resultingSourceUTF16Length: nextNSString.length,
            resultingCharacterAt: nextNSString.character(at:))
        source = next
        #expect(map == EditorSourceOffsetMap(source: source))
        assertEquivalent(map, source: source)
    }

    private struct DeterministicGenerator {
        private var state: UInt64 = 0x5C40_11A7

        mutating func next(upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(state % UInt64(upperBound))
        }
    }

    private func assertEquivalent(
        _ map: EditorSourceOffsetMap,
        source: String
    ) {
        let sourceLength = (source as NSString).length
        // Canonical search can skip a CRLF followed by a combining mark.
        // The editor removes literal CR code units from exact CRLF pairs.
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n", options: [.literal])
        let editorLength = (normalized as NSString).length
        #expect(map.sourceUTF16Length == sourceLength)
        #expect(map.editorUTF16Length == editorLength)

        for editorOffset in 0...editorLength {
            #expect(
                map.sourceUTF16Offset(forEditorUTF16Offset: editorOffset)
                    == slowSourceOffset(editorOffset, source: source)
            )
        }
        for sourceOffset in 0...sourceLength {
            #expect(
                map.editorUTF16Offset(forSourceUTF16Offset: sourceOffset)
                    == slowEditorOffset(sourceOffset, source: source)
            )
        }
    }

    private func slowSourceOffset(_ requested: Int, source: String) -> Int? {
        let units = Array(source.utf16)
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < units.count, editorOffset < requested {
            if sourceOffset + 1 < units.count,
                units[sourceOffset] == 13,
                units[sourceOffset + 1] == 10
            {
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        return editorOffset == requested ? sourceOffset : nil
    }

    private func slowEditorOffset(_ requested: Int, source: String) -> Int? {
        let units = Array(source.utf16)
        guard requested >= 0, requested <= units.count else { return nil }
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < requested {
            if sourceOffset + 1 < units.count,
                units[sourceOffset] == 13,
                units[sourceOffset + 1] == 10
            {
                guard sourceOffset + 2 <= requested else { return nil }
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        return editorOffset
    }
}
