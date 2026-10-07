import Foundation

/// Selects an exact readable-text window from already verified matches. Matching,
/// term identity, source locators and result ranking remain with the caller.
public struct ResearchExcerptWindow: Sendable {
    public struct Match: Sendable {
        public let range: Range<Int>
        public let identity: String

        public init(range: Range<Int>, identity: String) {
            self.range = range
            self.identity = identity
        }
    }

    /// UTF-16 range in the input text, always on complete Character boundaries.
    public let range: Range<Int>
    /// Complete supplied matches within the window, in source order.
    public let matches: [Range<Int>]

    public init(text: String, matches: [Match], characterLimit: Int, leadingContext: Int = 40) {
        var utf16Offsets = [0]
        for character in text {
            utf16Offsets.append(utf16Offsets.last! + String(character).utf16.count)
        }
        let characterCount = utf16Offsets.count - 1
        let limit = max(1, min(characterLimit, characterCount))
        let context = max(0, min(leadingContext, characterCount))
        func characterOffset(_ offset: Int) -> Int? {
            var lower = 0
            var upper = utf16Offsets.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if utf16Offsets[middle] < offset { lower = middle + 1 } else { upper = middle }
            }
            return lower < utf16Offsets.count && utf16Offsets[lower] == offset ? lower : nil
        }
        struct Occurrence {
            let identity: String
            let lower: Int
            let upper: Int
            let original: Range<Int>
        }
        let occurrences = matches.compactMap { match -> Occurrence? in
            guard !match.range.isEmpty,
                let lower = characterOffset(match.range.lowerBound),
                let upper = characterOffset(match.range.upperBound), upper - lower <= limit
            else { return nil }
            return Occurrence(identity: match.identity, lower: lower, upper: upper, original: match.range)
        }.sorted {
            if $0.lower != $1.lower { return $0.lower < $1.lower }
            if $0.upper != $1.upper { return $0.upper < $1.upper }
            return $0.identity < $1.identity
        }
        let starts = Set([0] + occurrences.flatMap { [max(0, $0.lower - context), max(0, $0.upper - limit)] }).sorted()
        let ends = occurrences.indices.sorted {
            if occurrences[$0].upper != occurrences[$1].upper { return occurrences[$0].upper < occurrences[$1].upper }
            return $0 < $1
        }
        var counts: [String: Int] = [:]
        var active = Array(repeating: false, count: occurrences.count)
        var distinct = 0
        var repeated = 0
        var lowerCursor = 0
        var upperCursor = 0
        var best = (start: 0, distinct: -1, repeated: -1)
        func adjust(_ identity: String, by delta: Int) {
            let previous = counts[identity, default: 0]
            let current = previous + delta
            counts[identity] = current
            distinct += (current > 0 ? 1 : 0) - (previous > 0 ? 1 : 0)
            repeated += min(2, current) - min(2, previous)
        }
        // Each occurrence enters/leaves at most once. Distinct matches lead;
        // repeated language contributes only a saturated secondary tie.
        for start in starts {
            let end = min(start + limit, characterCount)
            while upperCursor < ends.count, occurrences[ends[upperCursor]].upper <= end {
                let index = ends[upperCursor]
                if occurrences[index].lower >= start {
                    active[index] = true
                    adjust(occurrences[index].identity, by: 1)
                }
                upperCursor += 1
            }
            while lowerCursor < occurrences.count, occurrences[lowerCursor].lower < start {
                if active[lowerCursor] {
                    active[lowerCursor] = false
                    adjust(occurrences[lowerCursor].identity, by: -1)
                }
                lowerCursor += 1
            }
            if distinct > best.distinct || distinct == best.distinct && repeated > best.repeated {
                best = (start, distinct, repeated)
            }
        }
        let winningEnd = min(best.start + limit, characterCount)
        let winning = occurrences.filter { $0.lower >= best.start && $0.upper <= winningEnd }
        // Balance context around the winning cluster without dropping a match.
        var start = 0
        if let first = winning.first, let upper = winning.map(\.upper).max() {
            start = min(max(0, (first.lower + upper - limit) / 2), max(0, characterCount - limit))
        }
        let end = min(start + limit, characterCount)
        range = utf16Offsets[start]..<utf16Offsets[end]
        self.matches = occurrences.filter { $0.lower >= start && $0.upper <= end }.map(\.original)
    }
}
