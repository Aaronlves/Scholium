import Foundation
import ScholiumContracts

/// Private storage reuses the checked SOM1 representation already used by
/// search_segments. Public semantic projections retain exact offset arrays.
struct StoredParagraph: Codable {
    let range: SearchSourceRange
    let segments: [StoredParagraphSegment]

    init(_ paragraph: SearchParagraphProjection) throws {
        range = paragraph.range
        segments = try paragraph.segments.map(StoredParagraphSegment.init)
    }

    func projection() throws -> SearchParagraphProjection {
        SearchParagraphProjection(range: range, segments: try segments.map { try $0.projection() })
    }

    func validate(sourceUTF16Count: Int) throws {
        guard SearchProjectionValidation.valid(paragraphRange: range, sourceUTF16Count: sourceUTF16Count) else {
            throw SearchIndexError.corruptDatabase
        }
        for segment in segments {
            try SearchOffsetMapCodec.validate(
                segment.offsetMap, normalizedUTF16Count: segment.normalizedText.utf16.count,
                sourceUTF16Bounds: segment.sourceRange.map { (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound) },
                sourceUTF16Count: sourceUTF16Count)
        }
    }
}

struct StoredParagraphSegment: Codable {
    let field: SearchMatchedField
    let ordinal: Int
    let text: String
    let normalizedText: String
    let sourceRange: SearchSourceRange?
    let offsetMap: Data
    let relatedRankingText: [String: String]

    init(_ segment: SearchTextSegment) throws {
        field = segment.field
        ordinal = segment.ordinal
        text = segment.text
        normalizedText = segment.normalizedText
        sourceRange = segment.sourceRange
        offsetMap = try SearchOffsetMapCodec.encode(segment.offsetMap)
        relatedRankingText = segment.relatedRankingText
    }

    func projection() throws -> SearchTextSegment {
        SearchTextSegment(
            field: field, ordinal: ordinal, text: text,
            normalizedText: normalizedText, sourceRange: sourceRange,
            offsetMap: try SearchOffsetMapCodec.decode(offsetMap),
            relatedRankingText: relatedRankingText)
    }
}

/// A compact, private representation of exact normalized-to-source UTF-16
/// spans. Search schema changes rebuild this disposable state instead of
/// retaining a second decoder for older encodings.
enum SearchOffsetMapCodec {
    private static let magic = Data([0x53, 0x4f, 0x4d, 0x31])  // SOM1
    private static let headerByteCount = 8
    private static let entryByteCount = 32

    static func encode(_ offsets: [SearchSegmentOffset]) throws -> Data {
        guard let count = UInt32(exactly: offsets.count),
            offsets.allSatisfy({ offset in
                offset.normalizedUTF16LowerBound >= 0
                    && offset.normalizedUTF16UpperBound >= 0
                    && offset.sourceUTF16LowerBound >= 0
                    && offset.sourceUTF16UpperBound >= 0
            })
        else {
            throw SearchIndexError.invalidDocuments(
                "Search offset map contains an invalid generated range."
            )
        }
        var data = Data(capacity: headerByteCount + offsets.count * entryByteCount)
        data.append(magic)
        append(count, to: &data)
        for offset in offsets {
            append(UInt64(offset.normalizedUTF16LowerBound), to: &data)
            append(UInt64(offset.normalizedUTF16UpperBound), to: &data)
            append(UInt64(offset.sourceUTF16LowerBound), to: &data)
            append(UInt64(offset.sourceUTF16UpperBound), to: &data)
        }
        return data
    }

    static func decode(_ data: Data?) throws -> [SearchSegmentOffset] {
        try withRecord(data) { bytes, count in
            var offsets: [SearchSegmentOffset] = []
            offsets.reserveCapacity(count)
            for index in 0..<count {
                offsets.append(try offset(in: bytes, index: index))
            }
            return offsets
        }
    }

    /// Checks the same SOM1 fields and semantic bounds as decoding plus
    /// `SearchProjectionValidation`, without retaining discarded offset arrays.
    static func validate(
        _ data: Data?,
        normalizedUTF16Count: Int,
        sourceUTF16Bounds: (lower: Int, upper: Int)?,
        sourceUTF16Count: Int? = nil
    ) throws {
        guard
            SearchProjectionValidation.valid(
                offsets: [], normalizedUTF16Count: normalizedUTF16Count,
                sourceUTF16Bounds: sourceUTF16Bounds, sourceUTF16Count: sourceUTF16Count)
        else { throw SearchIndexError.corruptDatabase }
        try withRecord(data) { bytes, count in
            guard let sourceUTF16Bounds else {
                guard count == 0 else { throw SearchIndexError.corruptDatabase }
                return
            }
            var previous: SearchSegmentOffset?
            for index in 0..<count {
                let current = try offset(in: bytes, index: index)
                guard
                    SearchProjectionValidation.valid(
                        offset: current, normalizedUTF16Count: normalizedUTF16Count,
                        sourceUTF16Bounds: sourceUTF16Bounds),
                    previous.map({ SearchProjectionValidation.ordered($0, current) }) ?? true
                else { throw SearchIndexError.corruptDatabase }
                previous = current
            }
        }
    }

    private static func withRecord<Output>(
        _ data: Data?,
        _ body: (UnsafeRawBufferPointer, Int) throws -> Output
    ) throws -> Output {
        guard let data, data.count >= headerByteCount, data.prefix(magic.count) == magic else {
            throw SearchIndexError.corruptDatabase
        }
        return try data.withUnsafeBytes { bytes in
            let count = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
            guard count <= (data.count - headerByteCount) / entryByteCount,
                data.count == headerByteCount + count * entryByteCount
            else { throw SearchIndexError.corruptDatabase }
            return try body(bytes, count)
        }
    }

    private static func offset(in bytes: UnsafeRawBufferPointer, index: Int) throws -> SearchSegmentOffset {
        let cursor = headerByteCount + index * entryByteCount
        func value(_ component: Int) -> UInt64 {
            UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: cursor + component * 8, as: UInt64.self))
        }
        let normalizedLower = value(0)
        let normalizedUpper = value(1)
        let sourceLower = value(2)
        let sourceUpper = value(3)
        guard max(max(normalizedLower, normalizedUpper), max(sourceLower, sourceUpper)) <= UInt64(Int.max) else {
            throw SearchIndexError.corruptDatabase
        }
        return SearchSegmentOffset(
            normalizedUTF16LowerBound: Int(normalizedLower), normalizedUTF16UpperBound: Int(normalizedUpper),
            sourceUTF16LowerBound: Int(sourceLower), sourceUTF16UpperBound: Int(sourceUpper))
    }

    private static func append<Value: FixedWidthInteger>(
        _ value: Value,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

enum SearchProjectionValidation {
    static func valid(
        offsets: [SearchSegmentOffset],
        normalizedUTF16Count: Int,
        sourceUTF16Bounds: (lower: Int, upper: Int)?,
        sourceUTF16Count: Int? = nil
    ) -> Bool {
        guard normalizedUTF16Count >= 0 else { return false }
        guard let sourceUTF16Bounds else { return offsets.isEmpty }
        guard sourceUTF16Bounds.lower >= 0,
            sourceUTF16Bounds.upper >= sourceUTF16Bounds.lower,
            sourceUTF16Count.map({ sourceUTF16Bounds.upper <= $0 }) ?? true
        else {
            return false
        }
        guard offsets.allSatisfy({ valid(offset: $0, normalizedUTF16Count: normalizedUTF16Count, sourceUTF16Bounds: sourceUTF16Bounds) }) else {
            return false
        }
        return zip(offsets, offsets.dropFirst()).allSatisfy { ordered($0, $1) }
    }

    static func valid(
        offset: SearchSegmentOffset,
        normalizedUTF16Count: Int,
        sourceUTF16Bounds: (lower: Int, upper: Int)
    ) -> Bool {
        offset.normalizedUTF16LowerBound >= 0
            && offset.normalizedUTF16UpperBound >= offset.normalizedUTF16LowerBound
            && offset.normalizedUTF16UpperBound <= normalizedUTF16Count
            && offset.sourceUTF16LowerBound >= 0
            && offset.sourceUTF16UpperBound >= offset.sourceUTF16LowerBound
            && offset.sourceUTF16LowerBound >= sourceUTF16Bounds.lower
            && offset.sourceUTF16UpperBound <= sourceUTF16Bounds.upper
    }

    static func ordered(_ previous: SearchSegmentOffset, _ next: SearchSegmentOffset) -> Bool {
        previous.normalizedUTF16LowerBound <= next.normalizedUTF16LowerBound
            && previous.sourceUTF16LowerBound <= next.sourceUTF16LowerBound
    }

    static func valid(paragraphRange range: SearchSourceRange, sourceUTF16Count: Int) -> Bool {
        range.utf16LowerBound >= 0 && range.utf16UpperBound <= sourceUTF16Count
            && range.utf16LowerBound < range.utf16UpperBound && range.line > 0 && range.endLine >= range.line
            && range.column > 0 && range.endColumn > 0
    }
}
