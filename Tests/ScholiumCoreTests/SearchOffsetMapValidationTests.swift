import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Streaming Search offset validation")
struct SearchOffsetMapValidationTests {
    @Test("Streaming and decoded validation agree on framing, exact bounds and ordering")
    func validationEquivalence() throws {
        let entries: [[[UInt64]]] = [
            [], [[0, 1, 0, 1]], [[0, 2, 0, 3], [2, 4, 3, 5]],
            [[2, 1, 0, 1]], [[0, 1, 2, 1]], [[0, 11, 0, 1]], [[0, 1, 0, 11]],
            [[2, 3, 0, 1], [0, 1, 1, 2]], [[0, 1, 2, 3], [1, 2, 0, 1]],
            [[0, 0, 0, 0]], [[UInt64.max, 1, 0, 1]], [[0, 1, 0, UInt64.max]],
        ]
        let malformed: [Data?] = [
            nil, Data(), Data([0x53, 0x4f, 0x4d, 0x32]),
            record([[0, 1, 0, 1]]).dropLast(), record([]) + Data([0]), Data(repeating: 0, count: 8),
            record([[0, 1, 0, 1]], count: UInt32.max),
            record([[0, 1, 0, 1]], rawKind: 0xff),
        ]
        let records = entries.map { Optional(record($0)) } + malformed
        let bounds: [(Int, (lower: Int, upper: Int)?, Int?)] = [
            (10, (0, 10), 10), (4, (0, 5), 5), (10, nil, 10), (-1, (0, 10), 10),
            (0, (0, 0), 0), (10, (-1, 10), 10), (10, (2, 1), 10), (10, (0, 10), 9),
            (10, (0, 10), nil), (Int.max, (0, Int.max), Int.max),
        ]
        for (index, bytes) in records.enumerated() {
            for (normalCount, sourceBounds, sourceCount) in bounds {
                let decoded = try? SearchOffsetMapCodec.decode(bytes)
                let expected =
                    decoded.map {
                        SearchProjectionValidation.valid(
                            offsets: $0, normalizedUTF16Count: normalCount,
                            sourceUTF16Bounds: sourceBounds, sourceUTF16Count: sourceCount)
                    } ?? false
                let actual: Bool
                do {
                    try SearchOffsetMapCodec.validate(
                        bytes, normalizedUTF16Count: normalCount,
                        sourceUTF16Bounds: sourceBounds, sourceUTF16Count: sourceCount)
                    actual = true
                } catch SearchIndexError.corruptDatabase {
                    actual = false
                }
                #expect(actual == expected, "Offset framing/bounds case \(index)")
            }
        }
        try SearchOffsetMapCodec.validate(
            record([[0, 2, 0, 3], [2, 4, 3, 5]]),
            normalizedUTF16Count: 4, sourceUTF16Bounds: (0, 5), sourceUTF16Count: 5)
        let linear = record([[0, 2, 4, 6]], kind: .linear)
        try SearchOffsetMapCodec.validate(
            linear, normalizedUTF16Count: 2, sourceUTF16Bounds: (4, 6), sourceUTF16Count: 6)
        #expect(try SearchOffsetMapCodec.decode(linear).first?.mappingKind == .linear)
        let malformedLinear = record([[0, 2, 4, 7]], kind: .linear)
        #expect(throws: SearchIndexError.self) {
            try SearchOffsetMapCodec.validate(
                malformedLinear, normalizedUTF16Count: 2, sourceUTF16Bounds: (4, 7), sourceUTF16Count: 7)
        }
        for index in [3, 4, 5, 6, 7, 8, 10, 11] {
            #expect(throws: SearchIndexError.self) {
                try SearchOffsetMapCodec.validate(
                    record(entries[index]), normalizedUTF16Count: 10,
                    sourceUTF16Bounds: (0, 10), sourceUTF16Count: 10)
            }
        }
    }

    private func record(
        _ offsets: [[UInt64]],
        kind: SearchSegmentOffset.MappingKind = .sourceSpan,
        count: UInt32? = nil,
        rawKind: UInt8? = nil
    ) -> Data {
        var bytes = Data([0x53, 0x4f, 0x4d, 0x32])
        var length = (count ?? UInt32(offsets.count)).littleEndian
        withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
        for offset in offsets {
            bytes.append(rawKind ?? kind.rawValue)
            for component in offset {
                var value = component.littleEndian
                withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
            }
        }
        return bytes
    }
}
