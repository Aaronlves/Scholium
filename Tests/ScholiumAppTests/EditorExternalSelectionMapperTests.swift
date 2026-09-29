import Foundation
import Testing

@testable import ScholiumApp

@Suite("External editor selection mapping")
struct EditorExternalSelectionMapperTests {
    @Test("Unchanged prefix and shifted suffix retain multiple directed selections")
    func mapsOnlyExactUnchangedRegions() throws {
        let old = "head\nbeta gamma\n"
        let new = "head\nchanged beta gamma\n"
        let prefix = try selection("head", in: old)
        let suffix = try selection("gamma", in: old, reversed: true)

        let mapped = try #require(EditorExternalSelectionMapper.map(
            [prefix, suffix], from: old, to: new
        ))
        let expected = [
            try selection("head", in: new),
            try selection("gamma", in: new, reversed: true),
        ]
        #expect(mapped == expected)
    }

    @Test("Changed, crossing, and insertion-seam selections have no inferred mapping")
    func rejectsUnprovablePositions() throws {
        let old = "left middle right"
        let new = "left changed right"
        let prefix = try selection("left", in: old)
        let changed = try selection("middle", in: old)
        let crossing = try selection("left middle", in: old)
        #expect(EditorExternalSelectionMapper.map([changed], from: old, to: new) == nil)
        #expect(EditorExternalSelectionMapper.map([crossing], from: old, to: new) == nil)
        #expect(EditorExternalSelectionMapper.map([prefix, changed], from: old, to: new) == nil)

        let seam = MarkdownEditorSelectionRange(anchor: 1, head: 1)
        #expect(EditorExternalSelectionMapper.map([seam], from: "ab", to: "aXb") == nil)
    }

    @Test("BOM, CRLF, non-BMP, and decomposed Unicode use exact source offsets")
    func mapsAcrossExactUnicodeAndLineEndings() throws {
        let old = "\u{FEFF}起\r\n🦉 cafe\u{301}\r\n尾"
        let new = "\u{FEFF}引言\r\n起\r\n🦉 cafe\u{301}\r\n尾"
        let owl = try selection("🦉", in: old)
        let decomposed = try selection("cafe\u{301}", in: old, reversed: true)

        let mapped = try #require(EditorExternalSelectionMapper.map(
            [owl, decomposed], from: old, to: new
        ))
        let expected = [
            try selection("🦉", in: new),
            try selection("cafe\u{301}", in: new, reversed: true),
        ]
        #expect(mapped == expected)
    }

    @Test("Invalid surrogate and changed normalization boundaries fall back")
    func rejectsInvalidUnicodeBoundaries() {
        let splitSurrogate = MarkdownEditorSelectionRange(anchor: 1, head: 1)
        #expect(EditorExternalSelectionMapper.map(
            [splitSurrogate], from: "🦉 next", to: "new 🦉 next"
        ) == nil)

        let accent = MarkdownEditorSelectionRange(anchor: 3, head: 4)
        #expect(EditorExternalSelectionMapper.map(
            [accent], from: "caf\u{00E9}", to: "cafe\u{301}"
        ) == nil)
    }

    @Test("Identical exact source retains an end caret")
    func exactIdentity() {
        let source = "\u{FEFF}🦉\r\n"
        let end = EditorSourceOffsetMap(source: source).editorUTF16Length
        let caret = MarkdownEditorSelectionRange(anchor: end, head: end)
        #expect(EditorExternalSelectionMapper.map([caret], from: source, to: source) == [caret])
    }

    private func selection(
        _ text: String, in source: String, reversed: Bool = false
    ) throws -> MarkdownEditorSelectionRange {
        let range = (source as NSString).range(of: text)
        let map = EditorSourceOffsetMap(source: source)
        let from = try #require(map.editorUTF16Offset(forSourceUTF16Offset: range.location))
        let to = try #require(map.editorUTF16Offset(forSourceUTF16Offset: range.location + range.length))
        return reversed
            ? .init(anchor: to, head: from)
            : .init(anchor: from, head: to)
    }
}
