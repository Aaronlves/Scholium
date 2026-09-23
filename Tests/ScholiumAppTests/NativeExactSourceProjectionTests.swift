import Foundation
import ScholiumEditor
import Testing

@Suite("Exact UTF-8 source projection")
struct NativeExactSourceProjectionTests {
    @Test("Explicit ranges distinguish identical blank lines with different terminators")
    func repeatedBlankLines() throws {
        let bytes = Data("a\r\n\r\n\nb\rc".utf8)
        let initial = try ExactSourceProjection(utf8: bytes)
        #expect(Array(initial.projectedText.utf16) == Array("a\n\n\nb\nc".utf16))
        var deleteCRLF = initial
        try deleteCRLF.replace(in: NSRange(location: 2, length: 1), with: "")
        #expect(deleteCRLF.utf8 == Data("a\r\n\nb\rc".utf8))
        var deleteLF = initial
        try deleteLF.replace(in: NSRange(location: 3, length: 1), with: "")
        #expect(deleteLF.utf8 == Data("a\r\n\r\nb\rc".utf8))
        #expect(initial.utf8 == bytes)
    }

    @Test("Sequential edits retain untouched mixed terminators and use the initial first style")
    func mixedNewlines() throws {
        var value = try ExactSourceProjection(utf8: Data("a\r\nb\nc\rd".utf8))
        try value.replace(in: NSRange(location: 2, length: 1), with: "B")
        try value.replace(in: NSRange(location: 7, length: 0), with: "\nend")
        #expect(value.utf8 == Data("a\r\nB\nc\rd\r\nend".utf8))
        let snapshot = value
        try value.replace(in: NSRange(location: 0, length: 2), with: "")
        try value.replace(in: NSRange(location: 0, length: 0), with: "new\n")
        #expect(value.utf8 == Data("new\r\nB\nc\rd\r\nend".utf8))
        value = snapshot
        #expect(value.utf8 == snapshot.utf8)
    }

    @Test("BOM, decomposed Unicode, emoji, and missing final newline survive a local edit")
    func unicodeAndBOM() throws {
        let bytes = Data("\u{FEFF}cafe\u{0301}\r\n😀\rZ".utf8)
        var value = try ExactSourceProjection(utf8: bytes)
        #expect(value.utf8 == bytes)
        #expect(Array(value.projectedText.utf16) == Array("cafe\u{0301}\n😀\nZ".utf16))
        try value.replace(in: NSRange(location: 9, length: 1), with: "中")
        #expect(value.utf8 == Data("\u{FEFF}cafe\u{0301}\r\n😀\r中".utf8))
        try value.replace(in: NSRange(location: 6, length: 2), with: "🌿")
        #expect(value.utf8 == Data("\u{FEFF}cafe\u{0301}\r\n🌿\r中".utf8))
    }

    @Test("Only the first BOM is metadata; empty and newline-free documents default to LF")
    func bomAndEmptySources() throws {
        var doubled = try ExactSourceProjection(utf8: Data("\u{FEFF}\u{FEFF}x".utf8))
        #expect(Array(doubled.projectedText.utf16) == Array("\u{FEFF}x".utf16))
        try doubled.replace(in: NSRange(location: 1, length: 1), with: "y")
        #expect(doubled.utf8 == Data("\u{FEFF}\u{FEFF}y".utf8))
        for bytes in [Data(), Data([0xEF, 0xBB, 0xBF]), Data("x".utf8)] {
            var value = try ExactSourceProjection(utf8: bytes)
            let end = value.projectedText.utf16.count
            try value.replace(in: NSRange(location: end, length: 0), with: "\n")
            #expect(value.utf8 == bytes + Data([0x0A]))
        }
        var cr = try ExactSourceProjection(utf8: Data("a\rb\nc".utf8))
        try cr.replace(in: NSRange(location: 5, length: 0), with: "\nx")
        #expect(cr.utf8 == Data("a\rb\nc\rx".utf8))
    }

    @Test("No-op replacements preserve mixed bytes; canonical equivalents are real edits")
    func exactNoOp() throws {
        let bytes = Data("\u{FEFF}cafe\u{0301}\r\nx\ny\rz".utf8)
        var value = try ExactSourceProjection(utf8: bytes)
        try value.replace(
            in: NSRange(location: 0, length: value.projectedText.utf16.count),
            with: value.projectedText)
        #expect(value.utf8 == bytes)
        try value.replace(in: NSRange(location: 3, length: 2), with: "é")
        #expect(value.utf8 == Data("\u{FEFF}café\r\nx\ny\rz".utf8))
    }

    @Test("Malformed input and invalid replacement ranges fail without mutation")
    func rejectedEdits() throws {
        for bytes in [Data([0xFF]), Data([0xC0, 0xAF]), Data([0xED, 0xA0, 0x80])] {
            #expect(throws: ExactSourceProjection.Failure.invalidUTF8) {
                try ExactSourceProjection(utf8: bytes)
            }
        }
        let original = Data("\u{FEFF}😀\r\nx".utf8)
        var value = try ExactSourceProjection(utf8: original)
        for range in [
            NSRange(location: NSNotFound, length: 0),
            NSRange(location: 0, length: Int.max),
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: 5, length: 0),
        ] {
            #expect(throws: ExactSourceProjection.Failure.invalidRange) {
                try value.replace(in: range, with: "x")
            }
        }
        for range in [
            NSRange(location: 1, length: 0),
            NSRange(location: 0, length: 1),
            NSRange(location: 1, length: 1),
        ] {
            #expect(throws: ExactSourceProjection.Failure.splitSurrogate) {
                try value.replace(in: range, with: "x")
            }
        }
        #expect(throws: ExactSourceProjection.Failure.nonNormalizedReplacement) {
            try value.replace(in: NSRange(location: 0, length: 0), with: "\r\n")
        }
        #expect(value.utf8 == original)
    }
}
