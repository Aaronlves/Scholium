import Foundation
import ScholiumContracts
import Testing

@Suite("Exact Agent source edits")
struct AgentSourceEditTests {
    @Test("Original-revision insert, replace and delete preserve all other bytes")
    func mixedEdits() throws {
        let prefix = "\u{feff}---\r\nunknown: 'keep' # exact\r\nkeywords: [甲]\r\n---\r\n"
        let source = prefix + "重复 👩🏽‍🔬 e\u{301}\r\n重复\r\nEnd"
        let start = prefix.utf8.count
        let second = start + "重复 👩🏽‍🔬 e\u{301}\r\n".utf8.count
        let edits: [AgentSourceEdit] = [
            .init(startUTF8: source.utf8.count, endUTF8: source.utf8.count, expectedText: "", replacement: "!"),
            .init(startUTF8: second, endUTF8: second + "重复\r\n".utf8.count, expectedText: "重复\r\n", replacement: ""),
            .init(startUTF8: start, endUTF8: start + "重复".utf8.count, expectedText: "重复", replacement: "改写"),
        ]
        let result = try AgentSourceEdit.applying(edits, to: Data(source.utf8))
        #expect(Data(result.utf8) == Data((prefix + "改写 👩🏽‍🔬 e\u{301}\r\nEnd!").utf8))
        #expect(Data(result.utf8).prefix(prefix.utf8.count) == Data(prefix.utf8))
    }

    @Test("Wrong, overlapping, coincident, out-of-bounds and split-scalar ranges fail closed")
    func invalidRanges() {
        let source = Data("甲abcabc".utf8)
        let invalid: [[AgentSourceEdit]] = [
            [],
            [.init(startUTF8: 1, endUTF8: 3, expectedText: "甲", replacement: "")],
            [.init(startUTF8: 3, endUTF8: 6, expectedText: "ABC", replacement: "")],
            [.init(startUTF8: -1, endUTF8: 0, expectedText: "", replacement: "")],
            [.init(startUTF8: 0, endUTF8: Int.max, expectedText: "", replacement: "")],
            [.init(startUTF8: 6, endUTF8: 3, expectedText: "", replacement: "")],
            [
                .init(startUTF8: 3, endUTF8: 6, expectedText: "abc", replacement: ""),
                .init(startUTF8: 4, endUTF8: 5, expectedText: "b", replacement: ""),
            ],
            [
                .init(startUTF8: 3, endUTF8: 3, expectedText: "", replacement: "a"),
                .init(startUTF8: 3, endUTF8: 3, expectedText: "", replacement: "b"),
            ],
            [.init(startUTF8: 0, endUTF8: 0, expectedText: "", replacement: "\0")],
        ]
        for edits in invalid {
            #expect(throws: AgentCollaborationError.self) { try AgentSourceEdit.applying(edits, to: source) }
        }
    }

    @Test("Byte comparison rejects canonically equivalent but different source and enforces bounds")
    func exactBytesAndLimits() throws {
        let source = Data("e\u{301}".utf8)
        #expect(throws: AgentCollaborationError.self) {
            try AgentSourceEdit.applying([.init(startUTF8: 0, endUTF8: source.count, expectedText: "é", replacement: "x")], to: source)
        }
        let insertion = AgentSourceEdit(startUTF8: 0, endUTF8: 0, expectedText: "", replacement: "x")
        #expect(throws: AgentCollaborationError.self) { try AgentSourceEdit.applying(Array(repeating: insertion, count: 101), to: Data()) }
        let full = Data(repeating: 65, count: ScholiumMCPContract.maximumDocumentUTF8ByteCount)
        #expect(throws: AgentCollaborationError.self) { try AgentSourceEdit.applying([insertion], to: full) }
        #expect(try AgentSourceEdit.applying([insertion], to: Data()) == "x")
    }
}
