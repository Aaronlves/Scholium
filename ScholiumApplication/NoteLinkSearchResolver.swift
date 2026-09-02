import Foundation
import ScholiumContracts

/// Resolves one direct authored-link clause against the current graph
/// without copying edges into the lexical index.
enum NoteLinkSearchResolver {
    struct Resolution: Sendable {
        let matches: [VaultQualifiedNoteID: SearchLinkMatch]
        let diagnostic: SearchQueryDiagnostic?

        static let notRequested = Resolution(matches: [:], diagnostic: nil)
    }

    static func resolve(
        ast: SearchQueryAST,
        scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?
    ) -> Resolution {
        guard let query = ast.linkQuery else { return .notRequested }
        guard case .currentNote = scope else {
            return resolveAuthorized(
                query: query,
                scope: scope,
                catalog: catalog,
                searchGeneration: searchGeneration
            )
        }
        return Resolution(matches: [:], diagnostic: diagnostic(
            .notApplicable,
            "Direct link clauses are not applicable to This Note occurrence Search.",
            range: query.sourceRange
        ))
    }

    private static func resolveAuthorized(
        query: SearchLinkQuery,
        scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?
    ) -> Resolution {
        let authorizedNotes = notes(in: scope, catalog: catalog)
        let normalizedIdentity = SearchTextNormalization.normalize(query.noteIdentity)
        let anchors = authorizedNotes.filter { note in
            identities(of: note).contains {
                SearchTextNormalization.normalize($0) == normalizedIdentity
            }
        }
        guard anchors.count == 1, let anchor = anchors.first else {
            if anchors.isEmpty {
                return Resolution(matches: [:], diagnostic: diagnostic(
                    .notApplicable,
                    "No authorized Note has the exact link identity ‘\(query.noteIdentity)’.",
                    range: query.sourceRange
                ))
            }
            let candidates = anchors.map {
                "\($0.reference.vaultName)/\($0.reference.relativePath)"
            }.sorted().joined(separator: ", ")
            return Resolution(matches: [:], diagnostic: diagnostic(
                .ambiguousIdentity,
                "The link identity ‘\(query.noteIdentity)’ is ambiguous: \(candidates).",
                range: query.sourceRange
            ))
        }
        guard let graph = catalog.graph,
              let searchGeneration,
              graph.sourceManifestHash == searchGeneration.sourceManifestHash else {
            return Resolution(matches: [:], diagnostic: diagnostic(
                .notApplicable,
                "Direct link Search is unavailable until Graph and Note Search share one complete source manifest.",
                range: query.sourceRange
            ))
        }

        let anchorID = VaultQualifiedNoteID(
            vaultID: anchor.reference.vaultID,
            relativePath: anchor.reference.relativePath
        )
        let authorizedIDs = Set(authorizedNotes.map {
            VaultQualifiedNoteID(
                vaultID: $0.reference.vaultID,
                relativePath: $0.reference.relativePath
            )
        })
        var matches: [VaultQualifiedNoteID: SearchLinkMatch] = [:]
        let edges: [LinkGraphEdge] = switch query.direction {
        case .fromNote: graph.outgoing[anchorID] ?? []
        case .toNote: graph.incoming[anchorID] ?? []
        }
        for edge in edges {
            let target: VaultQualifiedNoteID? = switch query.direction {
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
        return Resolution(matches: matches, diagnostic: nil)
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
