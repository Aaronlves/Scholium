import Compression
import Foundation
import ScholiumContracts

/// One private framing contract for disposable Search projections. Compression
/// accepts bounded input; larger or incompressible payloads retain their
/// exact bytes in the same frame, without imposing a new source-size limit.
enum SearchProjectionBlobCodec {
    static let maximumCompressionByteCount = 32 * 1_024 * 1_024
    private static let magic = Data([0x53, 0x50, 0x42, 0x31])  // SPB1
    private static let headerByteCount = 21
    private enum Encoding: UInt8 { case raw, lzfse }

    static func encode(_ data: Data) throws -> Data {
        let payload: Data
        let encoding: Encoding
        if !data.isEmpty && data.count <= maximumCompressionByteCount {
            let compressed = try (data as NSData).compressed(using: .lzfse) as Data
            if compressed.count < data.count {
                payload = compressed
                encoding = .lzfse
            } else {
                payload = data
                encoding = .raw
            }
        } else {
            payload = data
            encoding = .raw
        }
        var frame = Data(capacity: headerByteCount + payload.count)
        frame.append(magic)
        frame.append(encoding.rawValue)
        var byteCount = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &byteCount) { frame.append(contentsOf: $0) }
        var payloadByteCount = UInt64(payload.count).littleEndian
        withUnsafeBytes(of: &payloadByteCount) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }

    static func decode(_ frame: Data?, maximumDecodedByteCount: Int = .max) throws -> Data {
        guard let frame, frame.count >= headerByteCount, frame.prefix(4) == magic,
            let encoding = frame.withUnsafeBytes({ Encoding(rawValue: $0[4]) }), maximumDecodedByteCount >= 0
        else { throw SearchIndexError.corruptDatabase }
        let count = frame.withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 5, as: UInt64.self))
        }
        let payloadCount = frame.withUnsafeBytes {
            UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: 13, as: UInt64.self))
        }
        // The system decoder may consume padding after its end marker. Bind
        // the exact encoded extent independently of its streaming status.
        guard count <= UInt64(maximumDecodedByteCount), payloadCount == UInt64(frame.count - headerByteCount)
        else { throw SearchIndexError.corruptDatabase }
        let decodedCount = Int(count)
        switch encoding {
        case .raw:
            guard frame.count - headerByteCount == decodedCount else { throw SearchIndexError.corruptDatabase }
            return Data(frame.dropFirst(headerByteCount))
        case .lzfse:
            // Check the untrusted decoded length before allocating. One spare
            // byte distinguishes an exact result from a full/truncated buffer.
            guard decodedCount > 0, decodedCount <= maximumCompressionByteCount,
                frame.count > headerByteCount
            else { throw SearchIndexError.corruptDatabase }
            var decoded = Data(count: decodedCount + 1)
            try frame.withUnsafeBytes { source in
                try decoded.withUnsafeMutableBytes { destination in
                    var stream = compression_stream(
                        dst_ptr: destination.baseAddress!.assumingMemoryBound(to: UInt8.self), dst_size: decodedCount + 1,
                        src_ptr: source.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: headerByteCount),
                        src_size: frame.count - headerByteCount, state: nil)
                    guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZFSE) == COMPRESSION_STATUS_OK
                    else { throw SearchIndexError.corruptDatabase }
                    defer { compression_stream_destroy(&stream) }
                    stream.src_ptr = source.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: headerByteCount)
                    stream.src_size = frame.count - headerByteCount
                    stream.dst_ptr = destination.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    stream.dst_size = decodedCount + 1
                    let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    guard status == COMPRESSION_STATUS_END, stream.src_size == 0,
                        stream.dst_size == 1
                    else { throw SearchIndexError.corruptDatabase }
                }
            }
            decoded.removeLast()
            return decoded
        }
    }
}
