import Foundation
import ScholiumContracts

/// Bounded, source-owned writing context. Retrieval supplies background, not a
/// replacement for the researcher's current readable span or a claim of evidence.
struct WritingContinuationContext: Equatable {
    static let maximumBeforeUTF16Count = 2_400
    static let maximumAfterUTF16Count = 800
    static let maximumBackgroundUTF16Count = 2_400
    static let maximumPassages = 3

    let before: String
    let after: String
    let focus: String

    init?(snapshot: MarkdownSourceSelectionSnapshot, caret: Int) {
        guard
            let readable = Self.currentReadableRange(snapshot: snapshot, caret: caret)
        else { return nil }
        let sentence: (lowerBound: Int, upperBound: Int) =
            readable.isProse
            ? Self.currentSentenceRange(
                in: snapshot.source,
                lowerBound: readable.lowerBound,
                upperBound: readable.upperBound,
                caret: caret
            ) ?? (readable.lowerBound, readable.upperBound)
            : (readable.lowerBound, readable.upperBound)
        guard
            let preceding = Range(
                NSRange(location: sentence.lowerBound, length: caret - sentence.lowerBound),
                in: snapshot.source
            ),
            let following = Range(
                NSRange(location: caret, length: sentence.upperBound - caret),
                in: snapshot.source
            )
        else { return nil }
        before = Self.bounded(String(snapshot.source[preceding]), limit: Self.maximumBeforeUTF16Count, suffix: true)
        after = Self.bounded(String(snapshot.source[following]), limit: Self.maximumAfterUTF16Count)
        guard before.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        // A partly typed Latin word is not useful retrieval context. Keeping
        // completed wording stable avoids a partial token dominating ranking.
        let completed: String
        if let last = before.last, last.isASCII, last.isLetter || last.isNumber,
            let boundary = before.lastIndex(where: { $0.isWhitespace || $0.isPunctuation })
        {
            completed = String(before[...boundary])
        } else {
            completed = before
        }
        let candidate = (completed + "\n" + after).trimmingCharacters(in: .whitespacesAndNewlines)
        focus = candidate.contains(where: { $0.isLetter || $0.isNumber }) ? candidate : before
    }

    private static func currentReadableRange(
        snapshot: MarkdownSourceSelectionSnapshot, caret: Int
    ) -> (lowerBound: Int, upperBound: Int, isProse: Bool)? {
        let source = snapshot.source
        let document = NoteDocument(relativePath: "WritingContext.md", rawContent: source)
        let lower = max(snapshot.sourceRange.utf16LowerBound, document.bodyUTF16Offset)
        let upper = snapshot.sourceRange.utf16UpperBound
        guard document.hasProvableBodyBoundary, lower >= 0, upper > lower,
            upper <= source.utf16.count,
            upper - lower <= MarkdownReadableWritingRange.maximumFragmentUTF16Count,
            caret >= lower, caret <= upper,
            let range = Range(NSRange(location: lower, length: upper - lower), in: source)
        else { return nil }

        var proofLower = lower
        var proofIndex = range.lowerBound
        var count = upper - lower
        // A blank source line can split a fenced block in the shared paragraph
        // capture. Extend local syntax proof backwards, leaving its upper bound
        // and every provider budget unchanged. Character steps preserve CRLF,
        // non-BMP and decomposed source boundaries.
        while proofLower > document.bodyUTF16Offset {
            let previous = source.index(before: proofIndex)
            let size = source[previous..<proofIndex].utf16.count
            guard count + size <= MarkdownReadableWritingRange.maximumFragmentUTF16Count else { break }
            proofIndex = previous
            proofLower -= size
            count += size
        }
        let reachesBodyStart = proofLower == document.bodyUTF16Offset
        var outerComments: [Range<Int>] = []
        if !reachesBodyStart {
            // A distant opener can enclose an otherwise ordinary paragraph.
            // Inspect the omitted prefix only to reject ambiguity, never to
            // parse or reconstruct it. The original capture starts on a full
            // source line, so the cut cannot split an opener in this prefix.
            // Reuse the source-owned comment scanner so closed inline
            // comments do not make all later prose ambiguous.
            outerComments = MarkdownSemanticParser.commentRanges(in: document)
            guard !outerComments.contains(where: { $0.contains(caret) }) else { return nil }
            let possibleOpeners = try? NSRegularExpression(
                pattern: #"(?:`{3,}|~{3,}|\$+|<(?:[A-Za-z/]|!(?!--)))"#)
            let omittedPrefix = NSRange(
                location: document.bodyUTF16Offset, length: lower - document.bodyUTF16Offset)
            let nativeSource = source as NSString
            for opener in possibleOpeners?.matches(in: source, range: omittedPrefix) ?? [] {
                var previous = opener.range.location
                while previous > document.bodyUTF16Offset, nativeSource.character(at: previous - 1) == 0x5C { previous -= 1 }
                if (opener.range.location - previous) % 2 == 0 { return nil }
            }
        }
        let origin = reachesBodyStart ? proofLower : lower
        guard
            let readable = reachesBodyStart
                ? MarkdownReadableWritingRange(bodyFragment: String(source[proofIndex..<range.upperBound]), caretUTF16: caret - proofLower)
                : MarkdownReadableWritingRange(bodyFragment: String(source[range]), caretUTF16: caret - lower)
        else { return nil }
        var readableLower = origin + readable.sourceUTF16Range.lowerBound
        var readableUpper = origin + readable.sourceUTF16Range.upperBound
        // A truncated paragraph may contain a distant comment's closing tail.
        // Clip with the same source-owned spans, not only the caret verdict.
        for comment in outerComments where comment.overlaps(readableLower..<readableUpper) {
            if comment.upperBound <= caret {
                readableLower = max(readableLower, comment.upperBound)
            } else if comment.lowerBound >= caret {
                readableUpper = min(readableUpper, comment.lowerBound)
            } else {
                return nil
            }
        }
        guard readableLower <= caret, caret <= readableUpper, readableLower < readableUpper else { return nil }
        return (readableLower, readableUpper, readable.isProse)
    }

    private static func currentSentenceRange(
        in source: String,
        lowerBound: Int,
        upperBound: Int,
        caret: Int
    ) -> (lowerBound: Int, upperBound: Int)? {
        guard lowerBound >= 0, upperBound >= lowerBound, upperBound <= source.utf16.count,
            caret >= lowerBound, caret <= upperBound,
            let range = Range(NSRange(location: lowerBound, length: upperBound - lowerBound), in: source)
        else { return nil }

        let characters = Array(source[range])
        var offsets = [0]
        offsets.reserveCapacity(characters.count + 1)
        for character in characters {
            offsets.append(offsets[offsets.count - 1] + character.utf16.count)
        }
        guard let caretIndex = offsets.firstIndex(of: caret - lowerBound) else { return nil }

        func boundaryEnd(after index: Int) -> Int? {
            guard index < characters.count, Self.isSentenceTerminator(characters[index]) else { return nil }
            if characters[index] == ".", index > 0, index + 1 < characters.count,
                characters[index - 1].isNumber, characters[index + 1].isNumber
            {
                return nil
            }
            var end = index + 1
            while end < characters.count, Self.isSentenceCloser(characters[end]) { end += 1 }
            guard
                Self.isCJKSentenceTerminator(characters[index])
                    || end == characters.count || characters[end].isWhitespace
            else { return nil }
            return end
        }

        var sentenceStartIndex = 0
        var completedSentence: Range<Int>?
        var index = 0
        while index < caretIndex {
            if let end = boundaryEnd(after: index), end <= caretIndex {
                completedSentence = sentenceStartIndex..<end
                sentenceStartIndex = end
                while sentenceStartIndex < caretIndex, characters[sentenceStartIndex].isWhitespace {
                    sentenceStartIndex += 1
                }
                index = end
            } else {
                index += 1
            }
        }

        var sentenceEndIndex = characters.count
        index = caretIndex
        while index < characters.count {
            if let end = boundaryEnd(after: index) {
                var whitespaceEnd = end
                while whitespaceEnd < characters.count, characters[whitespaceEnd].isWhitespace {
                    whitespaceEnd += 1
                }
                // Keep authored trailing line endings, but do not pass the
                // separator before a following sentence as writing context.
                sentenceEndIndex = whitespaceEnd == characters.count ? whitespaceEnd : end
                break
            }
            index += 1
        }

        if !characters[sentenceStartIndex..<caretIndex].contains(where: { $0.isLetter || $0.isNumber }),
            let completedSentence,
            characters[completedSentence.upperBound..<caretIndex].allSatisfy(\.isWhitespace)
        {
            sentenceStartIndex = completedSentence.lowerBound
        }
        guard sentenceStartIndex < sentenceEndIndex,
            characters[sentenceStartIndex..<sentenceEndIndex].contains(where: { $0.isLetter || $0.isNumber })
        else { return nil }
        return (
            lowerBound + offsets[sentenceStartIndex],
            lowerBound + offsets[sentenceEndIndex]
        )
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x2E, 0x21, 0x3F, 0x3002, 0xFF01, 0xFF1F, 0x2026: return true
        default: return false
        }
    }

    private static func isSentenceCloser(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x22, 0x27, 0x29, 0x5D, 0x7D, 0xBB, 0x3009, 0x300D, 0x300F, 0x3011, 0x3015, 0x2019, 0x201D, 0xFF09, 0x300B:
            return true
        default: return false
        }
    }

    private static func isCJKSentenceTerminator(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3002, 0xFF01, 0xFF1F: return true
        default: return false
        }
    }

    static func bounded(_ text: String, limit: Int, suffix: Bool = false) -> String {
        guard limit > 0 else { return "" }
        var size = 0
        let characters = suffix ? Array(text.reversed()) : Array(text)
        var kept: [Character] = []
        for character in characters {
            let count = character.utf16.count
            guard size + count <= limit else { break }
            kept.append(character)
            size += count
        }
        return suffix ? String(kept.reversed()) : String(kept)
    }

    static func background(_ response: RelatedContentResponse, catalog: [WorkspaceCatalogNote]) -> [String] {
        guard response.state == .current || response.state == .partial else { return [] }
        let current = Dictionary(
            catalog.map {
                (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0.fingerprint)
            }, uniquingKeysWith: { first, _ in first })
        var result: [String] = []
        var seen = Set<VaultQualifiedNoteID>()
        var budget = maximumBackgroundUTF16Count
        for passage in response.passages {
            let candidate = passage.candidate
            guard current[candidate.note] == candidate.fingerprint,
                seen.insert(candidate.note).inserted, result.count < maximumPassages
            else { continue }
            let identity =
                "Role: \(candidate.vaultRole.rawValue)\nNote: \(candidate.title)\nPath: \(candidate.note.relativePath)\nRevision: \(candidate.fingerprint.sha256)\n"
            let heading = identity + "Source excerpt (may be truncated):\n"
            guard heading.utf16.count + 80 < budget else { continue }
            let text = bounded(passage.source, limit: min(800, budget - heading.utf16.count))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let material = heading + text
            guard material.utf16.count <= budget else { continue }
            result.append(material)
            budget -= material.utf16.count
        }
        return result
    }
}

/// One disposable retrieval result per window, never query history or a second
/// index. A complete Search generation and exact seed/focus bind reuse;
/// passages are rechecked against the current catalog on every use.
@MainActor final class WritingContinuationContextCache {
    struct Key: Equatable {
        let runtime: TriptychRuntimeIdentity
        let note: VaultQualifiedNoteID
        let generation: SearchGenerationID
        let seedFingerprint: DocumentFingerprint
        let focus: String
    }
    private var key: Key?
    private var response: RelatedContentResponse?

    func value(for key: Key) -> RelatedContentResponse? { self.key == key ? response : nil }
    func replace(key: Key, response: RelatedContentResponse) {
        self.key = key
        self.response = response
    }
}
