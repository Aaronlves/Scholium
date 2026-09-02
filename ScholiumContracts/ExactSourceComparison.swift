import CryptoKit
import Foundation

public enum ExactSourceComparisonError: LocalizedError, Sendable {
    case exactRevisionUnavailable(DocumentFingerprint)
    case nonUTF8Revision(DocumentFingerprint)
    case fingerprintMismatch(expected: DocumentFingerprint, observed: DocumentFingerprint)

    public var errorDescription: String? {
        switch self {
        case .exactRevisionUnavailable(let fingerprint):
            "Comparison is unavailable because exact revision \(fingerprint.sha256) is not retained."
        case .nonUTF8Revision(let fingerprint):
            "Comparison is unavailable because revision \(fingerprint.sha256) is not valid UTF-8 Markdown."
        case .fingerprintMismatch(let expected, let observed):
            "Comparison is unavailable because retained bytes \(observed.sha256) do not match recorded revision \(expected.sha256)."
        }
    }
}

public enum ExactSourceComparisonLineKind: Hashable, Sendable {
    case unchanged
    case startingOnly
    case endingOnly
}

public enum ExactSourceComparisonLineEnding: String, Hashable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
    case none = "None"
}

public struct ExactSourceComparisonLine: Hashable, Identifiable, Sendable {
    public let id: Int
    public let kind: ExactSourceComparisonLineKind
    public let startingLineNumber: Int?
    public let endingLineNumber: Int?
    public let text: String
    public let lineEnding: ExactSourceComparisonLineEnding

    public init(
        id: Int,
        kind: ExactSourceComparisonLineKind,
        startingLineNumber: Int?,
        endingLineNumber: Int?,
        text: String,
        lineEnding: ExactSourceComparisonLineEnding
    ) {
        self.id = id
        self.kind = kind
        self.startingLineNumber = startingLineNumber
        self.endingLineNumber = endingLineNumber
        self.text = text
        self.lineEnding = lineEnding
    }
}

/// A disposable, non-Codable projection over two independently verified byte
/// revisions. Conflict and Agent Change clients supply their own inputs and
/// operations; exact byte comparison has this single owner.
public struct ExactSourceComparison: Sendable {
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint
    public let startingHasUTF8BOM: Bool
    public let endingHasUTF8BOM: Bool
    public let lines: [ExactSourceComparisonLine]

    public init(
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint,
        startingHasUTF8BOM: Bool,
        endingHasUTF8BOM: Bool,
        lines: [ExactSourceComparisonLine]
    ) {
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
        self.startingHasUTF8BOM = startingHasUTF8BOM
        self.endingHasUTF8BOM = endingHasUTF8BOM
        self.lines = lines
    }
}

public enum ExactSourceComparisonBuilder {
    private struct RawLine: Hashable, Sendable {
        let bytes: Data
        let ending: ExactSourceComparisonLineEnding
    }

    public static func build(
        startingData: Data,
        endingData: Data,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint
    ) throws -> ExactSourceComparison {
        try Task.checkCancellation()
        guard try matches(startingData, revision: startingRevision) else {
            try Task.checkCancellation()
            throw ExactSourceComparisonError.fingerprintMismatch(
                expected: startingRevision,
                observed: DocumentFingerprint(data: startingData)
            )
        }
        guard try matches(endingData, revision: endingRevision) else {
            try Task.checkCancellation()
            throw ExactSourceComparisonError.fingerprintMismatch(
                expected: endingRevision,
                observed: DocumentFingerprint(data: endingData)
            )
        }
        let startingBOM = startingData.starts(with: [0xEF, 0xBB, 0xBF])
        let endingBOM = endingData.starts(with: [0xEF, 0xBB, 0xBF])
        let starting = try split(
            startingBOM ? startingData.dropFirst(3) : startingData[...],
            revision: startingRevision
        )
        let ending = try split(
            endingBOM ? endingData.dropFirst(3) : endingData[...],
            revision: endingRevision
        )
        try Task.checkCancellation()

        let operations: [(ExactSourceComparisonLineKind, RawLine, Int?, Int?)]
        if starting.count + ending.count <= 4_000,
           startingData.count + endingData.count <= 512 * 1_024 {
            operations = try collectionDifference(starting: starting, ending: ending)
        } else {
            operations = try boundedDifference(starting: starting, ending: ending)
        }
        var lines: [ExactSourceComparisonLine] = []
        lines.reserveCapacity(operations.count)
        for (offset, operation) in operations.enumerated() {
            if offset.isMultiple(of: 1_024) { try Task.checkCancellation() }
            lines.append(ExactSourceComparisonLine(
                id: offset,
                kind: operation.0,
                startingLineNumber: operation.2,
                endingLineNumber: operation.3,
                text: String(decoding: operation.1.bytes, as: UTF8.self),
                lineEnding: operation.1.ending
            ))
        }
        return ExactSourceComparison(
            startingRevision: startingRevision,
            endingRevision: endingRevision,
            startingHasUTF8BOM: startingBOM,
            endingHasUTF8BOM: endingBOM,
            lines: lines
        )
    }

    private static func split(
        _ bytes: Data.SubSequence,
        revision: DocumentFingerprint
    ) throws -> [RawLine] {
        let data = Data(bytes)
        try validateUTF8(data, revision: revision)
        if data.isEmpty { return [] }
        var result: [RawLine] = []
        var start = data.startIndex
        var index = start
        while index < data.endIndex {
            if index.isMultiple(of: 65_536) { try Task.checkCancellation() }
            if data[index] == 0x0A {
                let hasCR = index > start && data[data.index(before: index)] == 0x0D
                let contentEnd = hasCR ? data.index(before: index) : index
                result.append(RawLine(
                    bytes: data[start..<contentEnd],
                    ending: hasCR ? .crlf : .lf
                ))
                start = data.index(after: index)
            }
            index = data.index(after: index)
        }
        if start < data.endIndex {
            result.append(RawLine(bytes: data[start...], ending: .none))
        }
        return result
    }

    private static func matches(
        _ data: Data,
        revision: DocumentFingerprint
    ) throws -> Bool {
        guard data.count == revision.byteCount else { return false }
        var hasher = SHA256()
        let chunkSize = 64 * 1_024
        var offset = data.startIndex
        while offset < data.endIndex {
            try Task.checkCancellation()
            let end = min(data.endIndex, offset + chunkSize)
            hasher.update(data: data[offset..<end])
            offset = end
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest == revision.sha256
    }

    private static func validateUTF8(
        _ data: Data,
        revision: DocumentFingerprint
    ) throws {
        var index = data.startIndex
        var nextCancellationCheck = data.startIndex
        while index < data.endIndex {
            if index >= nextCancellationCheck {
                try Task.checkCancellation()
                nextCancellationCheck = index + 65_536
            }
            let first = data[index]
            if first <= 0x7F {
                index += 1
                continue
            }
            let remaining = data.distance(from: index, to: data.endIndex)
            let length: Int
            switch first {
            case 0xC2...0xDF:
                length = 2
            case 0xE0:
                guard remaining >= 3,
                      (0xA0...0xBF).contains(data[index + 1]),
                      isContinuation(data[index + 2]) else {
                    throw ExactSourceComparisonError.nonUTF8Revision(revision)
                }
                index += 3
                continue
            case 0xE1...0xEC, 0xEE...0xEF:
                length = 3
            case 0xED:
                guard remaining >= 3,
                      (0x80...0x9F).contains(data[index + 1]),
                      isContinuation(data[index + 2]) else {
                    throw ExactSourceComparisonError.nonUTF8Revision(revision)
                }
                index += 3
                continue
            case 0xF0:
                guard remaining >= 4,
                      (0x90...0xBF).contains(data[index + 1]),
                      isContinuation(data[index + 2]),
                      isContinuation(data[index + 3]) else {
                    throw ExactSourceComparisonError.nonUTF8Revision(revision)
                }
                index += 4
                continue
            case 0xF1...0xF3:
                length = 4
            case 0xF4:
                guard remaining >= 4,
                      (0x80...0x8F).contains(data[index + 1]),
                      isContinuation(data[index + 2]),
                      isContinuation(data[index + 3]) else {
                    throw ExactSourceComparisonError.nonUTF8Revision(revision)
                }
                index += 4
                continue
            default:
                throw ExactSourceComparisonError.nonUTF8Revision(revision)
            }
            guard remaining >= length else {
                throw ExactSourceComparisonError.nonUTF8Revision(revision)
            }
            for continuationIndex in 1..<length where
                !isContinuation(data[index + continuationIndex]) {
                throw ExactSourceComparisonError.nonUTF8Revision(revision)
            }
            index += length
        }
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        (0x80...0xBF).contains(byte)
    }

    private static func collectionDifference(
        starting: [RawLine],
        ending: [RawLine]
    ) throws -> [(ExactSourceComparisonLineKind, RawLine, Int?, Int?)] {
        try Task.checkCancellation()
        let difference = ending.difference(from: starting)
        try Task.checkCancellation()
        let removals = Set(difference.compactMap { change -> Int? in
            guard case .remove(let offset, _, _) = change else { return nil }
            return offset
        })
        let insertions = Set(difference.compactMap { change -> Int? in
            guard case .insert(let offset, _, _) = change else { return nil }
            return offset
        })
        var result: [(ExactSourceComparisonLineKind, RawLine, Int?, Int?)] = []
        var startIndex = 0
        var endIndex = 0
        while startIndex < starting.count || endIndex < ending.count {
            if (startIndex + endIndex).isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            if startIndex < starting.count, removals.contains(startIndex) {
                result.append((.startingOnly, starting[startIndex], startIndex + 1, nil))
                startIndex += 1
            } else if endIndex < ending.count, insertions.contains(endIndex) {
                result.append((.endingOnly, ending[endIndex], nil, endIndex + 1))
                endIndex += 1
            } else if startIndex < starting.count, endIndex < ending.count {
                result.append((.unchanged, starting[startIndex], startIndex + 1, endIndex + 1))
                startIndex += 1
                endIndex += 1
            } else if startIndex < starting.count {
                result.append((.startingOnly, starting[startIndex], startIndex + 1, nil))
                startIndex += 1
            } else {
                result.append((.endingOnly, ending[endIndex], nil, endIndex + 1))
                endIndex += 1
            }
        }
        return result
    }

    /// Large inputs keep cancellation and memory bounded by showing an exact
    /// common prefix/suffix and the complete unmatched middle from each side.
    private static func boundedDifference(
        starting: [RawLine],
        ending: [RawLine]
    ) throws -> [(ExactSourceComparisonLineKind, RawLine, Int?, Int?)] {
        var prefix = 0
        while prefix < starting.count, prefix < ending.count,
              starting[prefix] == ending[prefix] {
            if prefix.isMultiple(of: 1_024) { try Task.checkCancellation() }
            prefix += 1
        }
        var suffix = 0
        while suffix < starting.count - prefix, suffix < ending.count - prefix,
              starting[starting.count - suffix - 1] == ending[ending.count - suffix - 1] {
            if suffix.isMultiple(of: 1_024) { try Task.checkCancellation() }
            suffix += 1
        }
        var result: [(ExactSourceComparisonLineKind, RawLine, Int?, Int?)] = []
        for index in 0..<prefix {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            result.append((.unchanged, starting[index], index + 1, index + 1))
        }
        for index in prefix..<(starting.count - suffix) {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            result.append((.startingOnly, starting[index], index + 1, nil))
        }
        for index in prefix..<(ending.count - suffix) {
            if index.isMultiple(of: 1_024) { try Task.checkCancellation() }
            result.append((.endingOnly, ending[index], nil, index + 1))
        }
        if suffix > 0 {
            for offset in (0..<suffix).reversed() {
                if offset.isMultiple(of: 1_024) { try Task.checkCancellation() }
                let startIndex = starting.count - offset - 1
                let endIndex = ending.count - offset - 1
                result.append((
                    .unchanged,
                    starting[startIndex],
                    startIndex + 1,
                    endIndex + 1
                ))
            }
        }
        return result
    }
}
