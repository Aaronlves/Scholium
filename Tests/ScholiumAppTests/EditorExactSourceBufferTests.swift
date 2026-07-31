import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Editor exact-source buffer")
struct EditorExactSourceBufferTests {
    @Test("Incremental storage preserves LF, CRLF, Unicode, and batch semantics")
    func preservesExactBytes() throws {
        let sources = [
            "LF\nonly\n",
            "CRLF\r\nonly\r\n",
            "\u{FEFF}emoji 🧑🏽‍💻\r\n中文 e\u{301}\r\n",
        ]

        for source in sources {
            let length = (source as NSString).length
            let deltas = [
                MarkdownEditorDelta(fromUTF16: length, toUTF16: length, insertion: "尾"),
                MarkdownEditorDelta(fromUTF16: 0, toUTF16: 0, insertion: "前"),
            ]
            let expected = try MarkdownEditorDeltaApplier.apply(deltas, to: source)
            let buffer = EditorExactSourceBuffer(source: source)

            try buffer.apply(deltas)

            #expect(buffer.snapshot() == expected)
            #expect(buffer.utf16Length == (expected as NSString).length)
            #expect(buffer.utf8ByteCount == expected.utf8.count)
        }
    }

    @Test("A rejected change leaves the exact buffer untouched")
    func rejectionIsAtomic() throws {
        let source = "exact 🧑🏽‍💻 source"
        let buffer = EditorExactSourceBuffer(source: source)

        #expect(throws: MarkdownEditorDeltaError.self) {
            try buffer.apply(
                [MarkdownEditorDelta(fromUTF16: 0, toUTF16: 0, insertion: "oversized")],
                maximumUTF8Bytes: source.utf8.count
            )
        }
        #expect(buffer.snapshot() == source)
        #expect(buffer.utf8ByteCount == source.utf8.count)
    }

    @Test("Ordinary inserts do not require an immutable full-source snapshot")
    func ordinaryInsertsStayIncremental() throws {
        let source = String(repeating: "Scholium 中文 input line.\n", count: 4_000)
        var legacySource = source
        var legacyOffset = (legacySource as NSString).length
        let legacyStarted = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<200 {
            legacySource = try MarkdownEditorDeltaApplier.apply([
                MarkdownEditorDelta(
                    fromUTF16: legacyOffset,
                    toUTF16: legacyOffset,
                    insertion: "x"
                ),
            ], to: legacySource)
            legacyOffset += 1
        }
        let legacyNanoseconds = DispatchTime.now().uptimeNanoseconds - legacyStarted

        let buffer = EditorExactSourceBuffer(source: source)
        var insertionOffset = buffer.utf16Length
        let incrementalStarted = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<200 {
            try buffer.apply([
                MarkdownEditorDelta(
                    fromUTF16: insertionOffset,
                    toUTF16: insertionOffset,
                    insertion: "x"
                ),
            ])
            insertionOffset += 1
        }
        let incrementalNanoseconds = DispatchTime.now().uptimeNanoseconds - incrementalStarted

        let result = buffer.snapshot()
        #expect(result == legacySource)
        #expect(result.hasSuffix(String(repeating: "x", count: 200)))
        #expect(buffer.utf8ByteCount == result.utf8.count)
        print(
            "NATIVE_EXACT_SOURCE_INPUT_SCENARIO "
                + "legacy_ms=\(Double(legacyNanoseconds) / 1_000_000) "
                + "incremental_ms=\(Double(incrementalNanoseconds) / 1_000_000)"
        )
    }
}
