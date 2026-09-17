import Foundation
import ScholiumContracts

/// Bounded, source-owned writing context. Retrieval supplies background, not a
/// replacement for the researcher's current paragraph or a claim of evidence.
struct WritingContinuationContext: Equatable {
    static let maximumBeforeUTF16Count = 2_400
    static let maximumAfterUTF16Count = 800
    static let maximumBackgroundUTF16Count = 2_400
    static let maximumPassages = 3

    let before: String
    let after: String
    let focus: String

    init?(snapshot: MarkdownSourceSelectionSnapshot, caret: Int) {
        let lower = snapshot.sourceRange.utf16LowerBound
        let upper = snapshot.sourceRange.utf16UpperBound
        guard caret >= lower, caret <= upper,
            let preceding = Range(NSRange(location: lower, length: caret - lower), in: snapshot.source),
            let following = Range(NSRange(location: caret, length: upper - caret), in: snapshot.source)
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
