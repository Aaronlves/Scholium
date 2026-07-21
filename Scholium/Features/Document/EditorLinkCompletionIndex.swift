import Foundation
import ScholiumContracts

/// Generation-owned, locale-stable wikilink candidate index. Graph/catalog
/// replacement invalidates older queries; callers receive at most 100 rows.
actor EditorLinkCompletionIndex {
    private struct IndexedNote: Sendable {
        let note: WorkspaceCatalogNote
        let stem: String
        let folder: String
        let pathWithoutExtension: String
        let normalizedStem: String
        let normalizedPath: String
        let normalizedSearchText: String
    }

    private var generation = -1
    private var notes: [IndexedNote] = []
    private var stemGroups: [String: [Int]] = [:]
    private var pathGroups: [String: [Int]] = [:]

    func removeAll() {
        generation = -1
        notes.removeAll(keepingCapacity: false)
        stemGroups.removeAll(keepingCapacity: false)
        pathGroups.removeAll(keepingCapacity: false)
    }

    func replace(notes catalogNotes: [WorkspaceCatalogNote], generation: Int) {
        guard generation != self.generation else { return }
        self.generation = generation
        notes = catalogNotes.map { note in
            let path = note.reference.relativePath
            let stem = ((path as NSString).lastPathComponent as NSString)
                .deletingPathExtension
            let folder = (path as NSString).deletingLastPathComponent
            let withoutExtension = (path as NSString).deletingPathExtension
            return IndexedNote(
                note: note,
                stem: stem,
                folder: folder,
                pathWithoutExtension: withoutExtension,
                normalizedStem: Self.normalize(stem),
                normalizedPath: Self.normalize(withoutExtension),
                normalizedSearchText: Self.normalize(
                    "\(note.title) \(path) \(note.aliases.joined(separator: " "))"
                )
            )
        }
        stemGroups = Dictionary(grouping: notes.indices) { notes[$0].normalizedStem }
        pathGroups = Dictionary(grouping: notes.indices) { notes[$0].normalizedPath }
    }

    func query(
        _ text: String,
        sourcePath: String,
        currentVaultID: UUID,
        generation expectedGeneration: Int,
        limit: Int = 100
    ) throws -> [EditorLinkCompletion] {
        try Task.checkCancellation()
        guard expectedGeneration == generation else { return [] }
        let normalizedQuery = Self.normalize(text)
        let sourceFolder = (sourcePath as NSString).deletingLastPathComponent
        let boundedLimit = min(100, max(0, limit))
        guard boundedLimit > 0 else { return [] }

        var results: [EditorLinkCompletion] = []
        results.reserveCapacity(boundedLimit)
        for candidate in notes {
            try Task.checkCancellation()
            guard normalizedQuery.isEmpty
                    || candidate.normalizedSearchText.contains(normalizedQuery) else {
                continue
            }
            let sameFolderMatches = stemGroups[candidate.normalizedStem, default: []].filter {
                notes[$0].note.reference.vaultID == currentVaultID
                    && notes[$0].folder == sourceFolder
            }
            let currentVaultMatches = stemGroups[candidate.normalizedStem, default: []].filter {
                notes[$0].note.reference.vaultID == currentVaultID
            }
            let allStemMatches = stemGroups[candidate.normalizedStem, default: []]
            let allPathMatches = pathGroups[candidate.normalizedPath, default: []]

            let insertion: String
            let isAmbiguous: Bool
            if candidate.note.reference.vaultID == currentVaultID,
               candidate.folder == sourceFolder,
               sameFolderMatches.count == 1 {
                insertion = candidate.stem
                isAmbiguous = false
            } else if candidate.note.reference.vaultID == currentVaultID,
                      currentVaultMatches.count == 1 {
                insertion = candidate.stem
                isAmbiguous = false
            } else if allStemMatches.count == 1 {
                insertion = candidate.stem
                isAmbiguous = false
            } else if candidate.note.reference.vaultID == currentVaultID
                        || allPathMatches.count == 1 {
                insertion = candidate.pathWithoutExtension
                isAmbiguous = false
            } else {
                insertion = ""
                isAmbiguous = true
            }

            let ambiguity = isAmbiguous
                ? " — Ambiguous: no unique Obsidian-compatible target"
                : ""
            results.append(EditorLinkCompletion(
                label: candidate.note.title,
                insertion: insertion,
                detail: "\(candidate.note.reference.vaultName) — \(candidate.note.reference.vaultRole.displayName) — \(candidate.note.reference.relativePath)\(ambiguity)",
                path: "\(candidate.note.reference.vaultName)/\(candidate.note.reference.relativePath)",
                isAmbiguous: isAmbiguous
            ))
            if results.count == boundedLimit { break }
        }
        return results.sorted {
            if $0.label != $1.label {
                return $0.label.localizedStandardCompare($1.label) == .orderedAscending
            }
            return $0.path < $1.path
        }
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
