import Foundation
import ScholiumContracts

/// Window-local, derived suggestions. No source is changed until the editor
/// accepts an explicit action.
@MainActor final class EditorWritingSuggestions {
    private struct Vocabulary {
        let fingerprint: DocumentFingerprint
        let terms: [String]
    }
    private var vocabulary: [VaultQualifiedNoteID: Vocabulary] = [:]
    func replace(_ notes: [WorkspaceNoteSummary]) {
        var updated: [VaultQualifiedNoteID: Vocabulary] = [:]
        for note in notes {
            if let cached = vocabulary[note.id], cached.fingerprint == note.fingerprint {
                updated[note.id] = cached
            } else {
                let terms =
                    (note.propertyTextValues["keywords"] ?? [])
                    + (note.propertyTextValues["aliases"] ?? [])
                updated[note.id] = .init(fingerprint: note.fingerprint, terms: terms)
            }
        }
        vocabulary = updated
    }

    private static func plainMarkdown(_ text: String) -> String {
        text.reduce(into: "") { result, character in
            if "\\`*_{}[]<>!|#-+.".contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    func clear() {
        vocabulary = [:]
    }

    func terms(_ query: String, notes: [WorkspaceCatalogNote], bodyTerms: [String] = []) -> [EditorLinkCompletion] {
        let suffixes = WritingCompletionPrefix.suffixes(in: query)
        guard !suffixes.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [(EditorLinkCompletion, Int)] = []
        for note in notes {
            let id = VaultQualifiedNoteID(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)
            let cached = vocabulary[id].flatMap { $0.fingerprint == note.fingerprint ? $0.terms : nil } ?? []
            let words = cached + note.aliases
            for word in words where word.count <= 96 && !word.contains("\n") {
                let normalized = SearchTextNormalization.normalize(word)
                guard
                    let prefix = suffixes.first(where: {
                        WritingCompletionPrefix.canAppend(word, after: $0)
                    }), seen.insert(normalized).inserted
                else { continue }
                var candidate = EditorLinkCompletion(
                    label: word, insertion: Self.plainMarkdown(word),
                    detail: note.title, displayText: nil,
                    availability: .available, unavailableReason: nil)
                candidate.writingAction = "term"
                candidate.replacementUTF16Count = prefix.utf16.count
                result.append((candidate, prefix.utf16.count))
            }
        }
        for word in bodyTerms {
            let normalized = SearchTextNormalization.normalize(word)
            guard let prefix = suffixes.first(where: { WritingCompletionPrefix.canAppend(word, after: $0) }),
                seen.insert(normalized).inserted
            else { continue }
            var candidate = EditorLinkCompletion(
                label: word, insertion: Self.plainMarkdown(word), detail: "", displayText: nil,
                availability: .available, unavailableReason: nil)
            candidate.writingAction = "term"
            candidate.replacementUTF16Count = prefix.utf16.count
            result.append((candidate, prefix.utf16.count))
        }
        return result.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.label.utf16.count != $1.0.label.utf16.count { return $0.0.label.utf16.count < $1.0.label.utf16.count }
            return $0.0.label < $1.0.label
        }.prefix(5).map(\.0)
    }

}
