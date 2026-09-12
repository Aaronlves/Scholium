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
    func replace(_ notes: [WorkspaceNoteSnapshot]) {
        var updated: [VaultQualifiedNoteID: Vocabulary] = [:]
        for note in notes {
            if let cached = vocabulary[note.id], cached.fingerprint == note.fingerprint {
                updated[note.id] = cached
            } else {
                let properties = SearchPropertyProjection(document: note.document)
                let terms = ["keywords", "aliases"].flatMap { properties.textValues(forExactKey: $0) }
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

    func terms(_ query: String, notes: [WorkspaceCatalogNote]) -> [EditorLinkCompletion] {
        guard query.count >= 2 else { return [] }
        let suffixes = (2...min(48, query.count)).reversed().compactMap { count -> String? in
            let suffix = String(query.suffix(count))
            let previous = query.dropLast(count).last
            guard previous == nil || previous?.isWhitespace == true || SearchTokenization.containsCJK(suffix) else { return nil }
            return suffix
        }
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
                        let value = SearchTextNormalization.normalize($0)
                        return value.count >= 2 && normalized.hasPrefix(value) && normalized != value
                    }), seen.insert(normalized).inserted
                else { continue }
                var candidate = EditorLinkCompletion(
                    label: word, insertion: Self.plainMarkdown(word),
                    detail: note.title, path: note.reference.relativePath, displayText: nil, isAmbiguous: false)
                candidate.writingAction = "term"
                candidate.replacementUTF16Count = prefix.utf16.count
                result.append((candidate, prefix.utf16.count))
            }
        }
        return result.sorted {
            $0.1 == $1.1 ? $0.0.label < $1.0.label : $0.1 > $1.1
        }.prefix(5).map(\.0)
    }

}
