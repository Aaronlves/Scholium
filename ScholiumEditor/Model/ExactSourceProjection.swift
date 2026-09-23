import Foundation

/// A value snapshot of exact UTF-8 source and its LF-only editing projection.
///
/// Edits use sequential UTF-16 ranges in `projectedText`. Original newline
/// tokens outside the replaced range remain unchanged; newly inserted LF uses
/// the first newline convention present when this value was initialized.
/// Only an initial UTF-8 BOM is metadata rather than editable text.
///
/// This deliberately builds a complete boundary map per replacement. It does
/// not infer edit locations from string differences or canonical equality.
public struct ExactSourceProjection: Sendable {
    /// Exact persisted UTF-8 bytes, including BOM and authored newline widths.
    public static let maximumUTF8Bytes = 8_000_000

    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        case invalidUTF8
        case invalidRange
        case splitSurrogate
        case nonNormalizedReplacement
        case includesByteOrderMark
        case splitNewline
        case sourceTooLarge

        public var errorDescription: String? {
            switch self {
            case .invalidUTF8: "The source is not valid UTF-8."
            case .invalidRange: "The edit range is outside the current source projection."
            case .splitSurrogate: "The edit range splits a Unicode scalar."
            case .nonNormalizedReplacement: "The replacement contains an unnormalized carriage return."
            case .includesByteOrderMark: "The source range includes the initial byte order mark."
            case .splitNewline: "The source range splits an authored CRLF newline."
            case .sourceTooLarge: "The document exceeds the 8 MB editing limit."
            }
        }
    }

    private let hasBOM: Bool
    private let insertedNewline: [UInt16]
    private var source: String

    public init(utf8: Data) throws {
        guard utf8.count <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
        guard String(data: utf8, encoding: .utf8) != nil else {
            throw Failure.invalidUTF8
        }
        hasBOM = utf8.starts(with: [0xEF, 0xBB, 0xBF])
        let content = hasBOM ? Data(utf8.dropFirst(3)) : utf8
        // String(data:encoding:) consumes a BOM. Decoding retains any second
        // or interior U+FEFF, which is part of the researcher's source.
        source = String(decoding: content, as: UTF8.self)
        let units = Array(source.utf16)
        if let first = units.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            insertedNewline =
                units[first] == 0x0D
                ? (first + 1 < units.count && units[first + 1] == 0x0A ? [0x0D, 0x0A] : [0x0D])
                : [0x0A]
        } else {
            insertedNewline = [0x0A]
        }
    }

    public var projectedText: String {
        String(decoding: projection().units, as: UTF16.self)
    }

    public var utf8: Data {
        var result = hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
        result.append(contentsOf: source.utf8)
        return result
    }

    /// Maps a range in the LF-only editor projection to exact source UTF-16
    /// coordinates. Source coordinates include an initial BOM as one code unit;
    /// projected coordinates exclude it. An empty projected range at zero maps
    /// immediately after that BOM. A full projected range covers all authored
    /// content, retaining CRLF widths, but does not include the metadata BOM.
    ///
    /// Ranges must refer to this value's current revision. Invalid bounds and
    /// Unicode scalar interior boundaries throw rather than being rounded.
    public func sourceUTF16Range(forProjectedUTF16Range range: NSRange) throws -> NSRange {
        let projection = projection()
        let end = try Self.validatedEnd(of: range, count: projection.units.count)
        try Self.validateScalarBoundaries(range, in: projection.units)
        let start = projection.boundaries[range.location]
        return NSRange(
            location: start + (hasBOM ? 1 : 0),
            length: projection.boundaries[end] - start)
    }

    /// Maps exact source UTF-16 coordinates into the LF-only editor projection.
    /// An initial BOM occupies source offset zero and has no editable projection:
    /// ranges including it, including an empty caret before it, are rejected.
    /// A subsequent/interior U+FEFF remains ordinary authored content.
    ///
    /// CRLF is one projected newline. Neither endpoint may lie between its two
    /// code units; scalar interior endpoints are likewise rejected. Mapping never
    /// expands, clips or guesses a nearby position. The result refers to this
    /// value's current revision, so callers must not reuse it after an edit.
    public func projectedUTF16Range(forSourceUTF16Range range: NSRange) throws -> NSRange {
        let projection = projection()
        let bomWidth = hasBOM ? 1 : 0
        let sourceCount = (projection.boundaries.last ?? 0) + bomWidth
        let end = try Self.validatedEnd(of: range, count: sourceCount)
        guard range.location >= bomWidth else { throw Failure.includesByteOrderMark }
        guard
            let startInProjection = Self.projectedBoundary(
                forSourceOffset: range.location - bomWidth,
                in: projection.boundaries),
            let endInProjection = Self.projectedBoundary(
                forSourceOffset: end - bomWidth,
                in: projection.boundaries)
        else {
            throw Failure.splitNewline
        }
        let result = NSRange(location: startInProjection, length: endInProjection - startInProjection)
        try Self.validateScalarBoundaries(result, in: projection.units)
        return result
    }

    /// An atomic batch uses ranges in the same pre-edit projection. Capacity is
    /// checked on the final result, so moving text cannot fail solely because
    /// an insertion is applied before the corresponding deletion.
    public mutating func replace(_ edits: [(range: NSRange, replacement: String)]) throws {
        guard !edits.isEmpty else { return }
        let projection = projection()
        let original = Array(source.utf16)
        var plans: [(range: Range<Int>, replacement: [UInt16])] = []
        var previousStart = projection.units.count + 1
        var removedBytes = 0
        var insertedBytes = 0
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let end = try Self.validatedEnd(of: edit.range, count: projection.units.count)
            guard edit.range.location < previousStart, end <= previousStart else { throw Failure.invalidRange }
            previousStart = edit.range.location
            try Self.validateScalarBoundaries(edit.range, in: projection.units)
            guard edit.replacement.utf8.count <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
            let replacement = Array(edit.replacement.utf16)
            guard !replacement.contains(0x0D) else { throw Failure.nonNormalizedReplacement }
            if projection.units[edit.range.location..<end].elementsEqual(replacement) { continue }
            let sourceRange = projection.boundaries[edit.range.location]..<projection.boundaries[end]
            removedBytes += String(decoding: original[sourceRange], as: UTF16.self).utf8.count
            let newlineGrowth = insertedNewline.count == 2 ? replacement.filter { $0 == 0x0A }.count : 0
            let insertion = edit.replacement.utf8.count.addingReportingOverflow(newlineGrowth)
            let total = insertedBytes.addingReportingOverflow(insertion.partialValue)
            guard !insertion.overflow, !total.overflow, total.partialValue <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
            insertedBytes = total.partialValue
            plans.append((sourceRange, replacement))
        }
        let finalCount = (exactUTF8Count - removedBytes).addingReportingOverflow(insertedBytes)
        guard !finalCount.overflow, finalCount.partialValue <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
        guard !plans.isEmpty else { return }
        // Assemble once from known ranges; a Replace All does not repeatedly
        // map or copy the complete document for each individual occurrence.
        var result: [UInt16] = []
        result.reserveCapacity(finalCount.partialValue)
        var cursor = 0
        for plan in plans.reversed() {
            result.append(contentsOf: original[cursor..<plan.range.lowerBound])
            for unit in plan.replacement {
                if unit == 0x0A { result.append(contentsOf: insertedNewline) } else { result.append(unit) }
            }
            cursor = plan.range.upperBound
        }
        result.append(contentsOf: original[cursor...])
        source = String(decoding: result, as: UTF16.self)
    }

    private var exactUTF8Count: Int { source.utf8.count + (hasBOM ? 3 : 0) }

    /// Applies one known edit. Failure leaves this value unchanged.
    public mutating func replace(in range: NSRange, with normalizedReplacement: String) throws {
        guard normalizedReplacement.utf8.count <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
        let replacement = Array(normalizedReplacement.utf16)
        guard !replacement.contains(0x0D) else { throw Failure.nonNormalizedReplacement }

        let projection = projection()
        let end = try Self.validatedEnd(of: range, count: projection.units.count)
        try Self.validateScalarBoundaries(range, in: projection.units)
        // A no-op replacement must not rewrite mixed original line endings.
        guard !projection.units[range.location..<end].elementsEqual(replacement) else { return }

        var sourceUnits = Array(source.utf16)
        let sourceRange = projection.boundaries[range.location]..<projection.boundaries[end]
        var exactReplacement: [UInt16] = []
        exactReplacement.reserveCapacity(replacement.count)
        for unit in replacement {
            if unit == 0x0A {
                exactReplacement.append(contentsOf: insertedNewline)
            } else {
                exactReplacement.append(unit)
            }
        }
        do {
            let removedByteCount = String(decoding: sourceUnits[sourceRange], as: UTF16.self).utf8.count
            let replacementByteCount = String(decoding: exactReplacement, as: UTF16.self).utf8.count
            let result = (exactUTF8Count - removedByteCount).addingReportingOverflow(replacementByteCount)
            guard !result.overflow, result.partialValue <= Self.maximumUTF8Bytes else { throw Failure.sourceTooLarge }
        }
        sourceUnits.replaceSubrange(sourceRange, with: exactReplacement)
        source = String(decoding: sourceUnits, as: UTF16.self)
    }

    private static func validatedEnd(of range: NSRange, count: Int) throws -> Int {
        guard range.location >= 0, range.length >= 0,
            range.location <= count, range.length <= count - range.location
        else {
            throw Failure.invalidRange
        }
        return range.location + range.length
    }

    /// Bounds are already checked by `validatedEnd` before this helper runs.
    private static func validateScalarBoundaries(_ range: NSRange, in units: [UInt16]) throws {
        for boundary in [range.location, range.location + range.length] {
            if boundary > 0, boundary < units.count,
                UTF16.isLeadSurrogate(units[boundary - 1]),
                UTF16.isTrailSurrogate(units[boundary])
            {
                throw Failure.splitSurrogate
            }
        }
    }

    /// The map is strictly increasing. A missing interior source boundary can
    /// only be the position between CR and LF, which is never guessed away.
    private static func projectedBoundary(forSourceOffset offset: Int, in boundaries: [Int]) -> Int? {
        var lower = 0
        var upper = boundaries.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if boundaries[middle] < offset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower < boundaries.count && boundaries[lower] == offset ? lower : nil
    }

    /// Boundary n is the source UTF-16 offset preceding projected unit n.
    /// CRLF maps one projected unit to two source units. Surrogate-interior
    /// boundaries exist in the table but are rejected by `replace`.
    private func projection() -> (units: [UInt16], boundaries: [Int]) {
        let original = Array(source.utf16)
        var units: [UInt16] = []
        var boundaries = [0]
        units.reserveCapacity(original.count)
        boundaries.reserveCapacity(original.count + 1)
        var offset = 0
        while offset < original.count {
            if original[offset] == 0x0D {
                offset += 1
                if offset < original.count, original[offset] == 0x0A { offset += 1 }
                units.append(0x0A)
            } else {
                units.append(original[offset])
                offset += 1
            }
            boundaries.append(offset)
        }
        return (units, boundaries)
    }
}
