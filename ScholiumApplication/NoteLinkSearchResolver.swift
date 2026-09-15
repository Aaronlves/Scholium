import Foundation
import ScholiumContracts

/// Resolves each direct authored-link predicate against the current graph
/// without copying edges into the lexical index.
enum NoteLinkSearchResolver {
    struct Resolution: Sendable {
        let matches: [SearchLinkQuery: SearchLinkResolution]
        let diagnostic: SearchQueryDiagnostic?

        static let notRequested = Resolution(matches: [:], diagnostic: nil)
    }

    static func resolve(
        ast: SearchQueryAST,
        scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?,
        includedVaultIDs: [UUID]? = nil
    ) -> Resolution {
        guard !ast.linkQueries.isEmpty else { return .notRequested }
        if case .currentNote = scope {
            return Resolution(
                matches: [:],
                diagnostic: diagnostic(
                    .notApplicable,
                    "Direct link clauses are not applicable to This Note occurrence Search.", range: ast.linkQueries[0].sourceRange))
        }
        var resolutions: [SearchLinkQuery: SearchLinkResolution] = [:]
        for query in ast.linkQueries {
            let result = resolveAuthorized(query: query, scope: scope, catalog: catalog, searchGeneration: searchGeneration, includedVaultIDs: includedVaultIDs)
            if let issue = result.diagnostic { return Resolution(matches: [:], diagnostic: issue) }
            resolutions[query] = SearchLinkResolution(matches: result.matches, indeterminateNotes: result.indeterminateNotes)
        }
        return Resolution(matches: resolutions, diagnostic: nil)
    }

    private struct AnchorResolution {
        let matches: [VaultQualifiedNoteID: SearchLinkMatch]
        let diagnostic: SearchQueryDiagnostic?
        var indeterminateNotes: Set<VaultQualifiedNoteID> = []
    }

    private static func resolveAuthorized(
        query: SearchLinkQuery,
        scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?,
        includedVaultIDs: [UUID]?
    ) -> AnchorResolution {
        let authorizedNotes = notes(in: scope, catalog: catalog).filter { includedVaultIDs?.contains($0.reference.vaultID) ?? true }
        let normalizedIdentity = SearchTextNormalization.normalize(query.noteIdentity)
        let anchors = authorizedNotes.filter { note in
            identities(of: note).contains {
                SearchTextNormalization.normalize($0) == normalizedIdentity
            }
        }
        guard anchors.count == 1, let anchor = anchors.first else {
            if anchors.isEmpty {
                return AnchorResolution(
                    matches: [:],
                    diagnostic: diagnostic(
                        .notApplicable,
                        "No authorized Note has the exact link identity ‘\(query.noteIdentity)’.",
                        range: query.sourceRange
                    ))
            }
            let candidates = anchors.map {
                "\($0.reference.vaultName)/\($0.reference.relativePath)"
            }.sorted().joined(separator: ", ")
            return AnchorResolution(
                matches: [:],
                diagnostic: diagnostic(
                    .ambiguousIdentity,
                    "The link identity ‘\(query.noteIdentity)’ is ambiguous: \(candidates).",
                    range: query.sourceRange
                ))
        }
        guard let graph = catalog.graph,
            let searchGeneration,
            graph.sourceManifestHash == searchGeneration.sourceManifestHash
        else {
            return AnchorResolution(
                matches: [:],
                diagnostic: diagnostic(
                    .notApplicable,
                    "Direct link Search is unavailable until Graph and Note Search share one complete source manifest.",
                    range: query.sourceRange
                ))
        }

        let anchorID = VaultQualifiedNoteID(
            vaultID: anchor.reference.vaultID,
            relativePath: anchor.reference.relativePath
        )
        let authorizedIDs = Set(
            authorizedNotes.map {
                VaultQualifiedNoteID(
                    vaultID: $0.reference.vaultID,
                    relativePath: $0.reference.relativePath
                )
            })
        var matches: [VaultQualifiedNoteID: SearchLinkMatch] = [:]
        let edges: [LinkGraphEdge] =
            switch query.direction {
            case .fromNote: graph.outgoing[anchorID] ?? []
            case .toNote: graph.incoming[anchorID] ?? []
            }
        for edge in edges {
            let target: VaultQualifiedNoteID? =
                switch query.direction {
                case .fromNote: edge.destination?.note
                case .toNote: edge.source
                }
            guard let target, target != anchorID, authorizedIDs.contains(target) else { continue }
            let occurrence = SearchLinkOccurrence(sourceNote: edge.source, occurrence: edge.occurrence)
            let occurrences = Array(Set((matches[target]?.occurrences ?? []) + [occurrence])).sorted {
                if $0.sourceNote != $1.sourceNote { return $0.sourceNote < $1.sourceNote }
                return $0.span.utf16LowerBound < $1.span.utf16LowerBound
            }
            matches[target] = SearchLinkMatch(
                direction: query.direction,
                anchorIdentity: query.noteIdentity,
                targetNote: target,
                occurrences: occurrences
            )
        }
        func hasUnresolvedLinks(_ note: VaultQualifiedNoteID) -> Bool {
            (graph.outgoing[note] ?? []).contains { !$0.occurrence.isExternal && $0.destination == nil }
        }
        let indeterminate: Set<VaultQualifiedNoteID>
        switch query.direction {
        case .fromNote: indeterminate = hasUnresolvedLinks(anchorID) ? authorizedIDs.subtracting([anchorID]) : []
        case .toNote: indeterminate = Set(authorizedIDs.filter { $0 != anchorID && hasUnresolvedLinks($0) })
        }
        return AnchorResolution(matches: matches, diagnostic: nil, indeterminateNotes: indeterminate)
    }

    private static func notes(
        in scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot
    ) -> [WorkspaceCatalogNote] {
        switch scope {
        case .currentNote:
            return []
        case .currentVault(let vaultID):
            return catalog.notes.filter { $0.reference.vaultID == vaultID }
        case .triptych:
            return catalog.notes
        }
    }

    private static func identities(of note: WorkspaceCatalogNote) -> [String] {
        [
            note.reference.stableNoteID,
            note.reference.relativePath,
            ((note.reference.relativePath as NSString).lastPathComponent as NSString)
                .deletingPathExtension,
            note.title,
        ].compactMap { $0 } + note.aliases
    }

    private static func diagnostic(
        _ code: SearchQueryDiagnosticCode,
        _ message: String,
        range: Range<Int>
    ) -> SearchQueryDiagnostic {
        SearchQueryDiagnostic(
            code: code,
            message: message,
            utf16LowerBound: range.lowerBound,
            utf16UpperBound: range.upperBound
        )
    }
}
