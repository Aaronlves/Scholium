import Foundation
import ScholiumContracts

/// Bounded, source-owned writing context. Retrieval supplies background, not a
/// replacement for the researcher's current sentence or a claim of evidence.
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
            let sentence = Self.currentSentenceRange(
                in: snapshot.source,
                lowerBound: snapshot.sourceRange.utf16LowerBound,
                upperBound: snapshot.sourceRange.utf16UpperBound,
                caret: caret
            ),
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
        var index = 0
        while index < caretIndex {
            if let end = boundaryEnd(after: index), end <= caretIndex {
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
        case 0x22, 0x27, 0x29, 0x5D, 0x7D, 0xBB, 0x3009, 0x300D, 0x300F, 0x3011, 0x3015, 0x2019, 0x201D:
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
