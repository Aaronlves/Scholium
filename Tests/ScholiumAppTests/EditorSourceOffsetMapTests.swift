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
            [MarkdownEditorDelta(
                fromUTF16: 0,
                toUTF16: (source as NSString).length,
                insertion: "LF\n重建\r\nfinal"
            )],
        ]

        for deltas in batches {
            let next = try MarkdownEditorDeltaApplier.apply(deltas, to: source)
            let nextNSString = next as NSString
            map.apply(
                deltas,
                resultingSourceUTF16Length: nextNSString.length,
                resultingCharacterAt: nextNSString.character(at:)
            )
            source = next
            #expect(map == EditorSourceOffsetMap(source: source))
            assertEquivalent(map, source: source)
        }
    }

    private func assertEquivalent(
        _ map: EditorSourceOffsetMap,
        source: String
    ) {
        let sourceLength = (source as NSString).length
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
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
               units[sourceOffset + 1] == 10 {
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
               units[sourceOffset + 1] == 10 {
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
