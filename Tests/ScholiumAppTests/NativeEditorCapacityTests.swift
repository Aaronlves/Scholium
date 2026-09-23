import Foundation
import ScholiumEditor
import Testing

@Suite("Native exact-source capacity", .serialized)
struct NativeEditorCapacityTests {
    @Test("Load rejects oversized exact bytes, counting the BOM")
    func loadCapacity() throws {
        let limit = ExactSourceProjection.maximumUTF8Bytes
        let exact = Data(repeating: 0x61, count: limit)
        #expect(try ExactSourceProjection(utf8: exact).utf8.count == limit)
        #expect(throws: ExactSourceProjection.Failure.sourceTooLarge) {
            try ExactSourceProjection(utf8: exact + Data([0x61]))
        }
        #expect(throws: ExactSourceProjection.Failure.sourceTooLarge) {
            try ExactSourceProjection(utf8: Data([0xEF, 0xBB, 0xBF]) + exact)
        }
    }

    @Test("A rejected edit retains its source and counts inserted CRLF bytes")
    func replacementCapacity() throws {
        let limit = ExactSourceProjection.maximumUTF8Bytes
        let source = Data(("x\r\n" + String(repeating: "a", count: limit - 3)).utf8)
        var value = try ExactSourceProjection(utf8: source)
        #expect(throws: ExactSourceProjection.Failure.sourceTooLarge) {
            try value.replace(in: NSRange(location: 2, length: 1), with: "\n")
        }
        #expect(value.utf8 == source)
        try value.replace(in: NSRange(location: 2, length: 2), with: "\n")
        #expect(value.utf8.count == limit)
        #expect(value.utf8.starts(with: Data("x\r\n\r\n".utf8)))
    }

    @Test("Balanced batches are admitted by final size and oversized batches remain atomic")
    func batchCapacity() throws {
        let limit = ExactSourceProjection.maximumUTF8Bytes
        let source = Data(("x" + String(repeating: "a", count: limit - 2) + "z").utf8)
        var value = try ExactSourceProjection(utf8: source)
        // Descending application inserts first. Final capacity, not that
        // temporary state, owns admission of the complete transaction.
        try value.replace([(NSRange(location: 0, length: 1), ""), (NSRange(location: limit, length: 0), "x")])
        #expect(value.utf8.count == limit)
        #expect(value.utf8.first == 0x61)
        #expect(value.utf8.suffix(2) == Data("zx".utf8))
        let previous = value.utf8
        #expect(throws: ExactSourceProjection.Failure.sourceTooLarge) {
            try value.replace([(NSRange(location: 0, length: 0), "extra"), (NSRange(location: 1, length: 1), "")])
        }
        #expect(value.utf8 == previous)
    }
}
