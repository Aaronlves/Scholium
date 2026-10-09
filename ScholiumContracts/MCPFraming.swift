import Foundation

public struct MCPFrame: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case line
        case contentLength
    }

    public let body: Data
    public let mode: Mode

    public init(body: Data, mode: Mode) {
        self.body = body
        self.mode = mode
    }
}

/// Incremental parser for the two stdio frame forms used by MCP clients.
/// Each append processes only the new byte; previously received input is never rescanned.
public struct MCPFrameParser: Sendable {
    private static let maximumHeaderSize = 8_192
    private enum Phase: Sendable {
        case line
        case headers(length: Int, byteCount: Int)
        case body(length: Int)
    }

    private var phase: Phase = .line
    private var buffer = Data()
    private var lineIsLengthHeader = false

    public init() {}

    public mutating func append(_ byte: UInt8) throws -> [MCPFrame] {
        switch phase {
        case .line:
            // Delimiters between frames are not part of the next message.
            if buffer.isEmpty, byte == 0x0A || byte == 0x0D { return [] }
            if byte == 0x0A {
                let lineByteCount = buffer.count + 1
                if buffer.last == 0x0D { buffer.removeLast() }
                guard let line = String(data: buffer, encoding: .utf8) else {
                    throw MCPFrameError.invalidHeader
                }
                if lineIsLengthHeader {
                    guard lineByteCount <= Self.maximumHeaderSize,
                        let separator = line.firstIndex(of: ":"),
                        let length = Int(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)),
                        (0...ScholiumMCPContract.maximumEncodedMessageByteCount).contains(length)
                    else {
                        throw MCPFrameError.invalidHeader
                    }
                    buffer.removeAll(keepingCapacity: true)
                    phase = .headers(length: length, byteCount: lineByteCount)
                    return []
                }
                return [takeFrame(mode: .line)]
            }
            buffer.append(byte)
            if buffer.count == 15 {
                lineIsLengthHeader =
                    String(decoding: buffer, as: UTF8.self)
                    .lowercased() == "content-length:"
            }
            let limit =
                lineIsLengthHeader
                ? Self.maximumHeaderSize : ScholiumMCPContract.maximumEncodedMessageByteCount
            // One trailing CR may precede the newline of a full-size line frame.
            guard buffer.count <= limit || (!lineIsLengthHeader && buffer.count == limit + 1 && byte == 0x0D) else {
                throw MCPFrameError.frameTooLarge
            }
            return []

        case .headers(let length, let byteCount):
            let nextByteCount = byteCount + 1
            guard nextByteCount <= Self.maximumHeaderSize else { throw MCPFrameError.frameTooLarge }
            phase = .headers(length: length, byteCount: nextByteCount)
            if byte != 0x0A {
                buffer.append(byte)
                return []
            }
            if buffer.last == 0x0D { buffer.removeLast() }
            guard let line = String(data: buffer, encoding: .utf8),
                !line.lowercased().hasPrefix("content-length:")
            else {
                throw MCPFrameError.invalidHeader
            }
            buffer.removeAll(keepingCapacity: true)
            if line.isEmpty {
                if length == 0 { return [takeFrame(mode: .contentLength)] }
                phase = .body(length: length)
            }
            return []

        case .body(let length):
            buffer.append(byte)
            guard buffer.count == length else { return [] }
            return [takeFrame(mode: .contentLength)]
        }
    }

    public mutating func finish() throws -> [MCPFrame] {
        guard case .line = phase else { throw MCPFrameError.invalidHeader }
        let remaining = buffer.trimmingASCIIWhitespace
        if !remaining.isEmpty {
            if String(decoding: remaining.prefix(15), as: UTF8.self)
                .lowercased().hasPrefix("content-length:")
            {
                throw MCPFrameError.invalidHeader
            }
            guard remaining.count <= ScholiumMCPContract.maximumEncodedMessageByteCount else {
                throw MCPFrameError.frameTooLarge
            }
            buffer = remaining
            return [takeFrame(mode: .line)]
        }
        reset()
        return []
    }

    private mutating func takeFrame(mode: MCPFrame.Mode) -> MCPFrame {
        let frame = MCPFrame(body: buffer, mode: mode)
        reset()
        return frame
    }

    private mutating func reset() {
        buffer = Data()
        phase = .line
        lineIsLengthHeader = false
    }
}

public enum MCPFrameError: LocalizedError, Sendable, Equatable {
    case frameTooLarge
    case invalidHeader

    public var errorDescription: String? {
        switch self {
        case .frameTooLarge: "The MCP message exceeded the supported size."
        case .invalidHeader: "The MCP stdio frame header was invalid."
        }
    }
}

private extension Data {
    var trimmingASCIIWhitespace: Data {
        var start = startIndex
        var end = endIndex
        while start < end, [0x09, 0x0A, 0x0D, 0x20].contains(self[start]) {
            start += 1
        }
        while end > start, [0x09, 0x0A, 0x0D, 0x20].contains(self[end - 1]) {
            end -= 1
        }
        return subdata(in: start..<end)
    }
}
