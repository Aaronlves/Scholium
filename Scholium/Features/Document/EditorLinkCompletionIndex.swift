import Foundation
import ScholiumContracts

/// Generation-owned, locale-stable wikilink candidate index. Graph/catalog
/// replacement invalidates older queries; callers receive at most 100 rows.
actor EditorLinkCompletionIndex {
    private static let stableLocale = Locale(identifier: "en_US_POSIX")

    private struct IndexedNote: Sendable {
        let note: WorkspaceCatalogNote
        let stem: String
        let folder: String
        let pathWithoutExtension: String
        let normalizedStem: String
        let normalizedPath: String
        let normalizedTitle: String
        let normalizedDisplayPath: String
        let normalizedSearchText: String
        let normalizedCanonicalSearchText: String
        let normalizedAliases: [(value: String, normalized: String)]
        let analysisReferenceText: String?
        let uniqueSortKey: String
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
            let displayPath = "\(note.reference.vaultName)/\(path)"
            let normalizedAliases = note.aliases.map {
                (value: $0, normalized: Self.normalize($0))
            }
            let canonicalSearchText = "\(note.title) \(path)"
            return IndexedNote(
                note: note,
                stem: stem,
                folder: folder,
                pathWithoutExtension: withoutExtension,
                normalizedStem: Self.normalize(stem),
                normalizedPath: Self.normalize(withoutExtension),
                normalizedTitle: Self.normalize(note.title),
                normalizedDisplayPath: Self.normalize(displayPath),
                normalizedSearchText: Self.normalize(
                    [
                        canonicalSearchText,
                        note.aliases.joined(separator: " "),
                        note.authors.joined(separator: " "),
                        note.publicationDate ?? "",
                    ].joined(separator: " ")
                ),
                normalizedCanonicalSearchText: Self.normalize(canonicalSearchText),
                normalizedAliases: normalizedAliases,
                analysisReferenceText: Self.analysisReferenceText(for: note),
                uniqueSortKey: "\(note.reference.vaultID.uuidString.lowercased()):\(path):"
                    + (note.reference.stableNoteID ?? note.fingerprint.sha256)
            )
        }
        notes.sort(by: Self.candidatesAreOrdered)
        stemGroups = Dictionary(grouping: notes.indices) { notes[$0].normalizedStem }
        pathGroups = Dictionary(grouping: notes.indices) { notes[$0].normalizedPath }
    }

    func query(
        kind: EditorLinkCompletionKind,
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
            if kind == .analysisReference,
               candidate.note.reference.vaultRole != .sourceCorpus {
                continue
            }
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
            let alias = kind == .wikilink
                ? candidate.normalizedAliases.first(where: {
                    !normalizedQuery.isEmpty
                        && !candidate.normalizedCanonicalSearchText.contains(normalizedQuery)
                        && $0.normalized.contains(normalizedQuery)
                        && Self.isSafeWikilinkDisplayText($0.value)
                })?.value
                : candidate.analysisReferenceText
            if kind == .analysisReference, alias == nil { continue }
            let referenceDetail = [
                candidate.note.title,
                candidate.note.authors.joined(separator: ", "),
                candidate.note.publicationDate ?? "",
                "\(candidate.note.reference.vaultName)/\(candidate.note.reference.relativePath)",
            ].filter { !$0.isEmpty }.joined(separator: " — ")
            results.append(EditorLinkCompletion(
                label: alias ?? candidate.note.title,
                insertion: insertion,
                detail: kind == .analysisReference
                    ? "\(referenceDetail)\(ambiguity)"
                    : "\(candidate.note.title) — \(candidate.note.reference.vaultName) — \(candidate.note.reference.vaultRole.displayName) — \(candidate.note.reference.relativePath)\(ambiguity)",
                path: "\(candidate.note.reference.vaultName)/\(candidate.note.reference.relativePath)",
                displayText: alias,
                isAmbiguous: isAmbiguous
            ))
            if results.count == boundedLimit { break }
        }
        return results
    }

    private static func candidatesAreOrdered(_ lhs: IndexedNote, _ rhs: IndexedNote) -> Bool {
        let titleOrder = compareSortText(lhs.normalizedTitle, rhs.normalizedTitle)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        let pathOrder = compareSortText(lhs.normalizedDisplayPath, rhs.normalizedDisplayPath)
        if pathOrder != .orderedSame { return pathOrder == .orderedAscending }
        return lhs.uniqueSortKey < rhs.uniqueSortKey
    }

    private static func analysisReferenceText(for note: WorkspaceCatalogNote) -> String? {
        guard note.reference.vaultRole == .sourceCorpus else { return nil }
        let author: String
        switch note.authors.count {
        case 0:
            author = note.title
        case 1:
            author = note.authors[0]
        case 2:
            author = "\(note.authors[0]) & \(note.authors[1])"
        default:
            author = "\(note.authors[0]) et al."
        }
        let year = note.publicationDate.flatMap { date -> String? in
            let prefix = String(date.prefix(4))
            return prefix.count == 4 && prefix.allSatisfy(\.isNumber) ? prefix : nil
        }
        let text = [author, year].compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isSafeWikilinkDisplayText(text) ? text : nil
    }

    private static func isSafeWikilinkDisplayText(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { "|]\n\r".contains($0) })
    }

    private static func compareSortText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(
            rhs,
            options: [.numeric],
            range: nil,
            locale: stableLocale
        )
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: stableLocale
        )
    }
}
