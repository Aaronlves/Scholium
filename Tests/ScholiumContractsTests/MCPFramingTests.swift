import Foundation
import ScholiumContracts
import Testing

@Suite("Incremental MCP framing", .timeLimit(.minutes(1)))
struct MCPFramingTests {
    @Test("Mixed frames preserve Unicode, body newlines and immediate frame boundaries")
    func mixedFrames() throws {
        let lineBody = Data(#"{"text":"甲 👩🏽‍🔬 é"}"#.utf8)
        let lengthBody = Data("{\r\n\"text\":\"甲\"\n}".utf8)
        let lastBody = Data(#"{"id":3}"#.utf8)
        let input =
            Data([0x0D, 0x0A, 0x0A]) + lineBody + Data([0x0D, 0x0A])
            + Data("cOnTeNt-LeNgTh: \(lengthBody.count)\r\nContent-Type: application/json\r\n\r\n".utf8)
            + lengthBody + Data("Content-Length: 0\n\n".utf8) + lastBody + Data([0x0A])

        #expect(
            try parse(input) == [
                MCPFrame(body: lineBody, mode: .line),
                MCPFrame(body: lengthBody, mode: .contentLength),
                MCPFrame(body: Data(), mode: .contentLength),
                MCPFrame(body: lastBody, mode: .line),
            ])
    }

    @Test("A completed frame is delivered before EOF or the next frame")
    func immediateDelivery() throws {
        let body = Data(#"{"id":1}"#.utf8)
        for header in [Data(), Data("Content-Length: \(body.count)\n\n".utf8)] {
            var parser = MCPFrameParser()
            let bytes = header + body + (header.isEmpty ? Data([0x0A]) : Data())
            for byte in bytes.dropLast() { #expect(try parser.append(byte).isEmpty) }
            let result = try parser.append(try #require(bytes.last))
            #expect(result == [MCPFrame(body: body, mode: header.isEmpty ? .line : .contentLength)])
            #expect(try parser.finish().isEmpty)
        }
    }

    @Test("Both framing forms admit the complete encoded-message budget", arguments: [false, true])
    func completeBudget(contentLength: Bool) throws {
        let body = Data(repeating: 0x41, count: ScholiumMCPContract.maximumEncodedMessageByteCount)
        let input =
            contentLength
            ? Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body
            : body + Data([0x0D, 0x0A])
        #expect(
            try parse(input) == [
                MCPFrame(body: body, mode: contentLength ? .contentLength : .line)
            ])
    }

    @Test("Oversized line and declared body fail before a handler can receive them")
    func oversizedFrames() {
        let line = Data(repeating: 0x41, count: ScholiumMCPContract.maximumEncodedMessageByteCount + 1)
        #expect(throws: MCPFrameError.frameTooLarge) { try parse(line) }
        let header = Data("Content-Length: \(ScholiumMCPContract.maximumEncodedMessageByteCount + 1)\n\n".utf8)
        #expect(throws: MCPFrameError.invalidHeader) { try parse(header) }
    }

    @Test("Headers are independently bounded even when the declared body is small")
    func oversizedHeaders() {
        let input =
            Data("Content-Length: 2\r\nX-Padding: ".utf8)
            + Data(repeating: 0x41, count: 8_192) + Data("\r\n\r\n{}".utf8)
        #expect(throws: MCPFrameError.frameTooLarge) { try parse(input) }
        let firstLine = Data("Content-Length:".utf8) + Data(repeating: 0x20, count: 8_192)
        #expect(throws: MCPFrameError.frameTooLarge) { try parse(firstLine) }
    }

    @Test(
        "Malformed, duplicate and incomplete length headers fail closed",
        arguments: [
            "Content-Length: -1\n\n",
            "Content-Length: 18446744073709551615\n\n",
            "Content-Length: abc\n\n",
            "Content-Length: 2\nContent-Length: 2\n\n{}",
            "Content-Length: 2\nContent-Length: 4\n\n{}{}",
            "Content-Length: 2",
            "Content-Length: 2\n",
            "Content-Length: 2\nX-Test: value\n",
            "Content-Length: 2\r\n\r\n{",
        ])
    func malformedHeader(input: String) {
        #expect(throws: MCPFrameError.invalidHeader) { try parse(Data(input.utf8)) }
    }

    @Test("EOF accepts a final unframed JSON line and resets its state")
    func unterminatedLine() throws {
        let body = Data(#"{"text":"甲"}"#.utf8)
        var parser = MCPFrameParser()
        for byte in Data([0x09, 0x20]) + body + Data([0x20, 0x09]) {
            #expect(try parser.append(byte).isEmpty)
        }
        #expect(try parser.finish() == [MCPFrame(body: body, mode: .line)])
        #expect(try parser.finish().isEmpty)
        #expect(try parser.append(0x0A).isEmpty)
    }

    @Test("A malformed UTF-8 line or supplementary header fails at its boundary")
    func invalidUTF8() {
        #expect(throws: MCPFrameError.invalidHeader) { try parse(Data([0xFF, 0x0A])) }
        let header = Data("Content-Length: 2\nX-Test: ".utf8) + Data([0xFF, 0x0A, 0x0A]) + Data("{}".utf8)
        #expect(throws: MCPFrameError.invalidHeader) { try parse(header) }
    }

    private func parse(_ data: Data) throws -> [MCPFrame] {
        var parser = MCPFrameParser()
        var frames: [MCPFrame] = []
        for byte in data { frames.append(contentsOf: try parser.append(byte)) }
        frames.append(contentsOf: try parser.finish())
        return frames
    }
}
