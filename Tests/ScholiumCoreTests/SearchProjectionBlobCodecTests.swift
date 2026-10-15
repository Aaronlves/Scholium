import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Bounded Search projection blobs")
struct SearchProjectionBlobCodecTests {
    @Test("Raw and compressed frames retain every byte, including sliced Data")
    func exactRoundTrip() throws {
        let inputs = [Data(), Data([0, 0xff, 0x53]), Data((0..<256).map(UInt8.init)), Data(String(repeating: "中文 e\u{301} 😀\r\n", count: 5_000).utf8)]
        for bytes in inputs {
            let frame = try SearchProjectionBlobCodec.encode(bytes)
            #expect(try SearchProjectionBlobCodec.decode(frame) == bytes)
            #expect(try SearchProjectionBlobCodec.decode(frame, maximumDecodedByteCount: bytes.count) == bytes)
            let slice = (Data([0xff]) + frame).dropFirst()
            #expect(try SearchProjectionBlobCodec.decode(slice) == bytes)
            if !bytes.isEmpty {
                #expect(throws: SearchIndexError.self) {
                    try SearchProjectionBlobCodec.decode(frame, maximumDecodedByteCount: bytes.count - 1)
                }
            }
        }
        let repetitive = Data(repeating: 0x41, count: 100_000)
        #expect(try SearchProjectionBlobCodec.encode(repetitive).count < repetitive.count / 10)
    }

    @Test("Corrupt headers, lengths, streams and trailing bytes reject before publication")
    func malformedFrames() throws {
        let valid = try SearchProjectionBlobCodec.encode(Data(repeating: 0x41, count: 100_000))
        #expect(valid[4] == 1)
        var wrongMagic = valid
        wrongMagic[0] = 0
        var unknownEncoding = valid
        unknownEncoding[4] = 2
        var wrongLength = valid
        wrongLength[5] ^= 1
        var excessiveLength = valid
        replaceLength(in: &excessiveLength, with: UInt64(SearchProjectionBlobCodec.maximumCompressionByteCount + 1))
        var overflowLength = valid
        replaceLength(in: &overflowLength, with: .max)
        var brokenStream = valid
        brokenStream[21] = 0
        let malformed: [Data?] = [
            nil, Data(), valid.prefix(12), valid.prefix(20), valid.dropLast(), valid + Data([0]),
            wrongMagic, unknownEncoding, wrongLength, excessiveLength, overflowLength, brokenStream,
            try SearchProjectionBlobCodec.encode(Data([0x41])) + Data([0]),
        ]
        for frame in malformed {
            #expect(throws: SearchIndexError.self) { try SearchProjectionBlobCodec.decode(frame) }
        }
    }

    @Test("Large valid material uses the raw frame outside the compression input bound")
    func largeRawFrame() throws {
        let bytes = Data(repeating: 0, count: SearchProjectionBlobCodec.maximumCompressionByteCount + 1)
        let frame = try SearchProjectionBlobCodec.encode(bytes)
        #expect(frame[4] == 0)
        #expect(try SearchProjectionBlobCodec.decode(frame) == bytes)
        #expect(throws: SearchIndexError.self) {
            try SearchProjectionBlobCodec.decode(frame, maximumDecodedByteCount: SearchProjectionBlobCodec.maximumCompressionByteCount)
        }
    }

    private func replaceLength(in frame: inout Data, with count: UInt64) {
        var littleEndian = count.littleEndian
        withUnsafeBytes(of: &littleEndian) { frame.replaceSubrange(5..<13, with: $0) }
    }
}
