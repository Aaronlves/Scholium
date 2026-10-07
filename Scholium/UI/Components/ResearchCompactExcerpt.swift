import Foundation
import NaturalLanguage
import ScholiumContracts

/// An exact readable-text slice for both research panes, independent of retrieval and source locators.
struct ResearchCompactExcerpt {
    let text: String
    /// UTF-16 ranges in `text`, including the offset of any leading omission marker.
    let matches: [Range<Int>]
    /// Whether this projection omitted input text; the input may already be a retrieval excerpt.
    let isOmitted: Bool

    init(text source: String, matches: [Range<Int>] = [], characterLimit: Int = 180) {
        let characterLimit = max(1, characterLimit)
        let indices = Array(source.indices) + [source.endIndex]
        let positions = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element, $0.offset) })
        let count = indices.count - 1
        let utf16Count = source.utf16.count
        let validMatches = matches.compactMap { match -> Range<Int>? in
            guard match.lowerBound >= 0, !match.isEmpty, match.upperBound <= utf16Count,
                let range = Range(NSRange(location: match.lowerBound, length: match.count), in: source),
                let lower = positions[range.lowerBound], let upper = positions[range.upperBound]
            else { return nil }
            return lower..<upper
        }.sorted {
            $0.lowerBound == $1.lowerBound ? $0.upperBound < $1.upperBound : $0.lowerBound < $1.lowerBound
        }

        // Match ownership stays upstream. Equivalent supplied source wording shares
        // one identity; presentation never tokenizes or reinterprets the query.
        let window = ResearchExcerptWindow(
            text: source,
            matches: validMatches.map { match in
                let range = indices[match.lowerBound]..<indices[match.upperBound]
                let utf16 = NSRange(range, in: source)
                return .init(
                    range: utf16.location..<NSMaxRange(utf16),
                    identity: SearchTextNormalization.lexicalNormalize(String(source[range])))
            }, characterLimit: characterLimit)
        let covered = Set(window.matches)
        let winning = validMatches.filter { match in
            let utf16 = NSRange(indices[match.lowerBound]..<indices[match.upperBound], in: source)
            return covered.contains(utf16.location..<NSMaxRange(utf16))
        }
        let cluster = winning.first.map { $0.lowerBound..<(winning.map(\.upperBound).max() ?? $0.upperBound) }

        let sentences = Self.tokens(in: source, unit: .sentence, positions: positions)
        let selection: Range<Int>
        if count <= characterLimit, sentences.count <= 2 {
            selection = 0..<count
        } else {
            let anchor = cluster ?? validMatches.first ?? (0..<min(1, count))
            let sentenceIndex =
                sentences.firstIndex { $0.contains(anchor.lowerBound) }
                ?? sentences.firstIndex { $0.upperBound > anchor.lowerBound }
            let finalSentenceIndex = sentences.firstIndex { $0.upperBound >= anchor.upperBound }
            var sentence =
                sentenceIndex.flatMap { first in
                    finalSentenceIndex.map { sentences[first].lowerBound..<sentences[$0].upperBound }
                } ?? (0..<count)
            if let sentenceIndex, sentenceIndex == finalSentenceIndex {
                // Prefer the following sentence so a short qualification remains beside its claim.
                if sentenceIndex + 1 < sentences.count,
                    sentences[sentenceIndex + 1].upperBound - sentence.lowerBound <= characterLimit
                {
                    sentence = sentence.lowerBound..<sentences[sentenceIndex + 1].upperBound
                } else if sentenceIndex > 0,
                    sentence.upperBound - sentences[sentenceIndex - 1].lowerBound <= characterLimit
                {
                    sentence = sentences[sentenceIndex - 1].lowerBound..<sentence.upperBound
                }
            }
            if sentence.count <= characterLimit {
                selection = Self.trimmingWhitespace(sentence, source: source, indices: indices)
            } else {
                selection = Self.window(
                    in: sentence, around: anchor, source: source, indices: indices, positions: positions,
                    characterLimit: characterLimit)
            }
        }

        let sourceRange = indices[selection.lowerBound]..<indices[selection.upperBound]
        let prefix = selection.lowerBound > 0 ? "… " : ""
        let suffix = selection.upperBound < count ? " …" : ""
        let sourceOffset = NSRange(sourceRange, in: source).location
        text = prefix + String(source[sourceRange]) + suffix
        isOmitted = selection.lowerBound > 0 || selection.upperBound < count
        self.matches = validMatches.compactMap { match in
            guard match.lowerBound >= selection.lowerBound, match.upperBound <= selection.upperBound else { return nil }
            let range = NSRange(indices[match.lowerBound]..<indices[match.upperBound], in: source)
            let offset = range.location - sourceOffset + prefix.utf16.count
            return offset..<(offset + range.length)
        }
    }

    private static func tokens(
        in text: String, unit: NLTokenUnit, positions: [String.Index: Int]
    ) -> [Range<Int>] {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        var result: [Range<Int>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let lower = positions[range.lowerBound], let upper = positions[range.upperBound], lower < upper {
                result.append(lower..<upper)
            }
            return true
        }
        return result
    }

    private static func window(
        in sentence: Range<Int>, around anchor: Range<Int>, source: String,
        indices: [String.Index], positions: [String.Index: Int], characterLimit: Int
    ) -> Range<Int> {
        let words = tokens(in: source, unit: .word, positions: positions)
            .filter { $0.overlaps(sentence) }
        let anchorStart = max(sentence.lowerBound, min(anchor.lowerBound, sentence.upperBound - 1))
        var focus = anchorStart..<min(sentence.upperBound, max(anchorStart + 1, anchor.upperBound))
        if focus.count > characterLimit {
            focus = focus.lowerBound..<(focus.lowerBound + characterLimit)
        }
        // Preserve whole matched words when possible, even when a supplied match covers only a suffix.
        for word in words where word.overlaps(focus) {
            let expanded = min(word.lowerBound, focus.lowerBound)..<max(word.upperBound, focus.upperBound)
            if expanded.count <= characterLimit { focus = expanded }
        }
        // Retain a little leading context without interpreting the prose. This keeps short
        // qualifiers such as "not" or "not merely" together with the matched word.
        let matchStart = focus.lowerBound
        for word in words.reversed() where word.upperBound <= focus.lowerBound {
            guard matchStart - word.lowerBound <= 24,
                focus.upperBound - word.lowerBound <= characterLimit,
                source[indices[word.upperBound]..<indices[focus.lowerBound]].allSatisfy(\.isWhitespace)
            else { break }
            focus = word.lowerBound..<focus.upperBound
        }

        let leadingContext = (characterLimit - focus.count) / 2
        var lower = max(sentence.lowerBound, focus.lowerBound - leadingContext)
        var upper = min(sentence.upperBound, lower + characterLimit)
        lower = max(sentence.lowerBound, upper - characterLimit)
        // Move cut points inward to complete words. A token larger than the whole budget
        // necessarily falls back to grapheme boundaries, still with explicit omission markers.
        if let word = words.first(where: { $0.lowerBound < lower && lower < $0.upperBound }),
            word.upperBound <= focus.lowerBound
        {
            lower = word.upperBound
        }
        if let word = words.first(where: { $0.lowerBound < upper && upper < $0.upperBound }),
            word.lowerBound >= focus.upperBound
        {
            upper = word.lowerBound
        }
        return trimmingWhitespace(lower..<upper, source: source, indices: indices)
    }

    private static func trimmingWhitespace(
        _ range: Range<Int>, source: String, indices: [String.Index]
    ) -> Range<Int> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, source[indices[lower]].isWhitespace { lower += 1 }
        while lower < upper, source[indices[upper - 1]].isWhitespace { upper -= 1 }
        return lower..<upper
    }
}
