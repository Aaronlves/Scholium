import Foundation
import ScholiumContracts

/// Generation-owned, locale-stable wikilink candidate index. Graph/catalog
/// replacement invalidates older queries; callers receive at most 100 rows.
actor EditorLinkCompletionIndex {
    private static let stableLocale = Locale(identifier: "en_US_POSIX")

    private struct IndexedNote: Sendable {
        let note: WorkspaceCatalogNote
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
    private var resolution = LinkResolutionCatalog(catalog: [])

    func removeAll() {
        generation = -1
        notes.removeAll(keepingCapacity: false)
        resolution = LinkResolutionCatalog(catalog: [])
    }

    func replace(notes catalogNotes: [WorkspaceCatalogNote], generation: Int) {
        guard generation != self.generation else { return }
        self.generation = generation
        notes = catalogNotes.map { note in
            let path = note.reference.relativePath
            let displayPath = "\(note.reference.vaultName)/\(path)"
            let normalizedAliases = note.aliases.map {
                (value: $0, normalized: Self.normalize($0))
            }
            let canonicalSearchText = "\(note.title) \(path)"
            return IndexedNote(
                note: note,
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
        resolution = LinkResolutionCatalog(
            catalog: catalogNotes.map {
                LinkCatalogNote(
                    id: VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath),
                    title: $0.title,
                    aliases: $0.aliases)
            })
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
        let source = VaultQualifiedNoteID(vaultID: currentVaultID, relativePath: sourcePath)
        let boundedLimit = min(100, max(0, limit))
        guard boundedLimit > 0 else { return [] }

        var results: [EditorLinkCompletion] = []
        results.reserveCapacity(boundedLimit)
        for candidate in notes {
            try Task.checkCancellation()
            if kind == .analysisReference,
                candidate.note.reference.vaultRole != .sourceCorpus
            {
                continue
            }
            guard
                normalizedQuery.isEmpty
                    || candidate.normalizedSearchText.contains(normalizedQuery)
            else {
                continue
            }
            let plan = resolution.wikilinkTarget(
                for: VaultQualifiedNoteID(
                    vaultID: candidate.note.reference.vaultID,
                    relativePath: candidate.note.reference.relativePath),
                from: source)
            var insertion: String
            var availability: EditorLinkCompletionAvailability
            var unavailableReason: String?
            switch plan {
            case .available(let target):
                insertion = target
                availability = .available
                unavailableReason = nil
            case .ambiguous:
                insertion = ""
                availability = .ambiguous
                unavailableReason = ScholiumL10n.string("This Note has no unique Wikilink target from the current Note. Add a unique alias.")
            case .unsupportedSyntax:
                insertion = ""
                availability = .unsupportedSyntax
                unavailableReason = ScholiumL10n.string("This Note's filename cannot be represented by the supported Wikilink syntax. Add a unique alias.")
            case .missingNote:
                insertion = ""
                availability = .unavailable
                unavailableReason = ScholiumL10n.string("This Note is no longer available. Refresh the Library and try again.")
            }
            let alias =
                kind == .wikilink
                ? candidate.normalizedAliases.first(where: {
                    !normalizedQuery.isEmpty
                        && !candidate.normalizedCanonicalSearchText.contains(normalizedQuery)
                        && $0.normalized.contains(normalizedQuery)
                        && Self.isSafeWikilinkDisplayText($0.value)
                })?.value
                : candidate.analysisReferenceText
            if kind == .analysisReference, alias == nil {
                insertion = ""
                availability = .unsupportedSyntax
                unavailableReason = ScholiumL10n.string(
                    "This Note has no label that can be inserted as Wikilink display text. Use a safe Note title or author.")
            }
            let referenceDetail = [
                candidate.note.title,
                candidate.note.authors.joined(separator: ", "),
                candidate.note.publicationDate ?? "",
                "\(candidate.note.reference.vaultName)/\(candidate.note.reference.relativePath)",
            ].filter { !$0.isEmpty }.joined(separator: " — ")
            results.append(
                EditorLinkCompletion(
                    label: alias ?? candidate.note.title,
                    insertion: insertion,
                    detail: kind == .analysisReference
                        ? referenceDetail
                        : "\(candidate.note.title) — \(candidate.note.reference.vaultName) — \(candidate.note.reference.vaultRole.displayName) — \(candidate.note.reference.relativePath)",
                    displayText: alias,
                    availability: availability,
                    unavailableReason: unavailableReason
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
        if isSafeWikilinkDisplayText(text) { return text }
        return isSafeWikilinkDisplayText(note.title) ? note.title : nil
    }

    private static func isSafeWikilinkDisplayText(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(where: { "|[]\n\r".contains($0) })
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
