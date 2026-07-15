import Foundation

public struct ZoteroMCPFrame: Sendable, Equatable {
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
public struct ZoteroMCPFrameParser: Sendable {
    private static let maximumFrameSize = 2 * 1_024 * 1_024
    private var buffer = Data()

    public init() {}

    public mutating func append(_ byte: UInt8) throws -> [ZoteroMCPFrame] {
        buffer.append(byte)
        var frames: [ZoteroMCPFrame] = []
        while let frame = try nextFrame() { frames.append(frame) }
        return frames
    }

    public mutating func finish() throws -> [ZoteroMCPFrame] {
        var frames: [ZoteroMCPFrame] = []
        while let frame = try nextFrame() { frames.append(frame) }
        let remaining = buffer.trimmingASCIIWhitespace
        if !remaining.isEmpty {
            if String(decoding: remaining.prefix(15), as: UTF8.self)
                .lowercased().hasPrefix("content-length:") {
                throw ZoteroMCPFrameError.invalidHeader
            }
            guard remaining.count <= Self.maximumFrameSize else {
                throw ZoteroMCPFrameError.frameTooLarge
            }
            frames.append(ZoteroMCPFrame(body: remaining, mode: .line))
        }
        buffer.removeAll()
        return frames
    }

    private mutating func nextFrame() throws -> ZoteroMCPFrame? {
        while buffer.first == 0x0A || buffer.first == 0x0D { buffer.removeFirst() }
        guard !buffer.isEmpty else { return nil }
        guard buffer.count <= Self.maximumFrameSize + 8_192 else {
            throw ZoteroMCPFrameError.frameTooLarge
        }
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let firstLineData = buffer[..<newline].dropLastIfCarriageReturn
        guard let firstLine = String(data: firstLineData, encoding: .utf8) else {
            throw ZoteroMCPFrameError.invalidHeader
        }

        if firstLine.lowercased().hasPrefix("content-length:") {
            guard let headerBoundary = buffer.headerBoundary else { return nil }
            let headerData = buffer[..<headerBoundary.start]
            guard let headers = String(data: headerData, encoding: .utf8) else {
                throw ZoteroMCPFrameError.invalidHeader
            }
            let lengthLine = headers.split(whereSeparator: \Character.isNewline).first {
                $0.lowercased().hasPrefix("content-length:")
            }
            guard let lengthLine,
                  let separator = lengthLine.firstIndex(of: ":"),
                  let length = Int(lengthLine[lengthLine.index(after: separator)...].trimmingCharacters(in: .whitespaces)),
                  (0...Self.maximumFrameSize).contains(length) else {
                throw ZoteroMCPFrameError.invalidHeader
            }
            let bodyStart = headerBoundary.end
            guard buffer.count >= bodyStart + length else { return nil }
            let body = buffer.subdata(in: bodyStart..<(bodyStart + length))
            buffer.removeSubrange(0..<(bodyStart + length))
            return ZoteroMCPFrame(body: body, mode: .contentLength)
        }

        guard newline <= Self.maximumFrameSize else { throw ZoteroMCPFrameError.frameTooLarge }
        let body = Data(firstLineData)
        buffer.removeSubrange(0...newline)
        if body.isEmpty { return try nextFrame() }
        return ZoteroMCPFrame(body: body, mode: .line)
    }
}

public enum ZoteroMCPFrameError: LocalizedError, Sendable {
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
        var result = self
        while let first = result.first, [0x09, 0x0A, 0x0D, 0x20].contains(first) {
            result.removeFirst()
        }
        while let last = result.last, [0x09, 0x0A, 0x0D, 0x20].contains(last) {
            result.removeLast()
        }
        return result
    }

    var headerBoundary: (start: Int, end: Int)? {
        if let range = range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
            return (range.lowerBound, range.upperBound)
        }
        if let range = range(of: Data([0x0A, 0x0A])) {
            return (range.lowerBound, range.upperBound)
        }
        return nil
    }
}

private extension Data.SubSequence {
    var dropLastIfCarriageReturn: Data {
        guard last == 0x0D else { return Data(self) }
        return Data(dropLast())
    }
}
