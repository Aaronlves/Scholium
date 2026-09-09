import Foundation
import ScholiumContracts
import Testing

@Suite("Exact Note display targets")
struct AgentNoteDisplayTests {
    @Test("Display ranges preserve BOM, CRLF and Unicode coordinates without fuzzy matching")
    func exactRange() throws {
        let bytes = Data("\u{feff}# 原文\r\n\r\nExact **text** 😀.\r\n".utf8)
        let range = try #require(bytes.range(of: Data("text".utf8)))
        func target(_ start: Int?, _ end: Int?, _ text: String?) throws -> AgentNoteDisplayTarget {
            try .init(triptychID: UUID(), noteID: UUID(), note: .init(vaultID: UUID(), relativePath: "Source.md"),
                fingerprint: .init(data: bytes), source: bytes, startUTF8: start, endUTF8: end, expectedText: text)
        }
        let exact = try target(range.lowerBound, range.upperBound, "text")
        #expect(exact.range?.line == 3 && exact.range?.column == 9 && exact.range?.endColumn == 13)
        #expect(exact.excerpt == "text")
        #expect(try target(nil, nil, nil).range == nil)
        #expect(throws: ScholiumMCPFailure.self) { try target(range.lowerBound, range.upperBound, "other") }
        #expect(throws: ScholiumMCPFailure.self) { try target(range.lowerBound, nil, "text") }
        #expect(throws: ScholiumMCPFailure.self) { try target(1, 2, "x") }
        #expect(throws: ScholiumMCPFailure.self) { try target(0, Int.max, "x") }
    }
}
