import Foundation
import ScholiumContracts

/// Maps CodeMirror's LF-normalized UTF-16 offsets to exact-source UTF-16
/// offsets without rescanning the whole Markdown buffer for every change.
/// Only CRLF pairs affect the mapping; LF-only documents are an O(1) identity.
struct EditorSourceOffsetMap: Equatable, Sendable {
    private(set) var sourceUTF16Length: Int
    private(set) var crlfSourceOffsets: [Int]

    init(source: String) {
        let units = Array(source.utf16)
        sourceUTF16Length = units.count
        crlfSourceOffsets = Self.crlfOffsets(in: units, baseOffset: 0)
    }

    var editorUTF16Length: Int {
        sourceUTF16Length - crlfSourceOffsets.count
    }

    var usesCRLF: Bool { !crlfSourceOffsets.isEmpty }

    func sourceUTF16Offset(forEditorUTF16Offset requestedOffset: Int) -> Int? {
        guard requestedOffset >= 0, requestedOffset <= editorUTF16Length else {
            return nil
        }
        guard !crlfSourceOffsets.isEmpty else { return requestedOffset }

        var lower = 0
        var upper = crlfSourceOffsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let editorNewlineOffset = crlfSourceOffsets[middle] - middle
            if editorNewlineOffset < requestedOffset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return requestedOffset + lower
    }

    func editorUTF16Offset(forSourceUTF16Offset requestedOffset: Int) -> Int? {
        guard requestedOffset >= 0, requestedOffset <= sourceUTF16Length else {
            return nil
        }
        guard !crlfSourceOffsets.isEmpty else { return requestedOffset }

        var lower = 0
        var upper = crlfSourceOffsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if crlfSourceOffsets[middle] < requestedOffset {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        if lower > 0, crlfSourceOffsets[lower - 1] + 1 == requestedOffset {
            return nil
        }
        return requestedOffset - lower
    }

    /// Updates the sorted CRLF index by shifting unaffected suffix entries and
    /// rescanning only each changed boundary plus its insertion. Deltas use
    /// coordinates in the old exact source, as required by DeltaApplier.
    mutating func apply(
        _ deltas: [MarkdownEditorDelta],
        resultingSourceUTF16Length: Int,
        resultingCharacterAt: (Int) -> unichar
    ) {
        guard !deltas.isEmpty else { return }
        let ordered = deltas.sorted {
            if $0.fromUTF16 == $1.fromUTF16 {
                return $0.toUTF16 < $1.toUTF16
            }
            return $0.fromUTF16 < $1.fromUTF16
        }
        let resultingLength = resultingSourceUTF16Length
        let expectedLength = ordered.reduce(sourceUTF16Length) { length, delta in
            length + delta.insertion.utf16.count - (delta.toUTF16 - delta.fromUTF16)
        }
        guard expectedLength == resultingLength else {
            assertionFailure("The exact-source offset map received an inconsistent result length.")
            return
        }

        var retained: [Int] = []
        retained.reserveCapacity(crlfSourceOffsets.count + ordered.count)
        var completedDeltaIndex = 0
        var completedShift = 0
        for offset in crlfSourceOffsets {
            while completedDeltaIndex < ordered.count,
                  ordered[completedDeltaIndex].toUTF16 < offset {
                let delta = ordered[completedDeltaIndex]
                completedShift += delta.insertion.utf16.count
                    - (delta.toUTF16 - delta.fromUTF16)
                completedDeltaIndex += 1
            }
            let intersectsChangedBoundary = completedDeltaIndex < ordered.count
                && offset >= max(0, ordered[completedDeltaIndex].fromUTF16 - 1)
                && offset <= ordered[completedDeltaIndex].toUTF16
            guard !intersectsChangedBoundary else { continue }
            retained.append(offset + completedShift)
        }

        var cumulativeShift = 0
        var rescanned: [Int] = []
        for delta in ordered {
            let insertionLength = delta.insertion.utf16.count
            let start = delta.fromUTF16 + cumulativeShift
            let end = start + insertionLength
            let scanLower = max(0, start - 1)
            let scanUpper = min(resultingLength - 1, end)
            if scanLower <= scanUpper {
                for offset in scanLower...scanUpper
                where offset + 1 < resultingLength
                    && resultingCharacterAt(offset) == 13
                    && resultingCharacterAt(offset + 1) == 10 {
                    rescanned.append(offset)
                }
            }
            cumulativeShift += insertionLength - (delta.toUTF16 - delta.fromUTF16)
        }

        sourceUTF16Length = resultingLength
        crlfSourceOffsets = Array(Set(retained + rescanned)).sorted()
    }

    private static func crlfOffsets(
        in units: [UInt16],
        baseOffset: Int
    ) -> [Int] {
        guard units.count >= 2 else { return [] }
        var offsets: [Int] = []
        for index in 0..<(units.count - 1)
        where units[index] == 13 && units[index + 1] == 10 {
            offsets.append(baseOffset + index)
        }
        return offsets
    }
}
