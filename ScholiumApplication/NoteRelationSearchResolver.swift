import Foundation
import ScholiumContracts

/// Resolves one explicit direct-relation clause against the current Graph
/// without copying edges into the lexical index.
enum NoteRelationSearchResolver {
    struct Resolution: Sendable {
        let matches: [VaultQualifiedNoteID: SearchRelationshipMatch]
        let diagnostic: SearchQueryDiagnostic?

        static let notRequested = Resolution(matches: [:], diagnostic: nil)
    }

    static func resolve(
        ast: SearchQueryAST,
        scope: SearchExecutionScope,
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?
    ) -> Resolution {
        guard let query = ast.relationQuery else { return .notRequested }
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
            "Direct relation clauses are not applicable to This Note occurrence Search.",
            range: query.sourceRange
        ))
    }

    private static func resolveAuthorized(
        query: SearchRelationQuery,
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
                    "No authorized Note has the exact relation identity ‘\(query.noteIdentity)’.",
                    range: query.sourceRange
                ))
            }
            let candidates = anchors.map {
                "\($0.reference.vaultName)/\($0.reference.relativePath)"
            }.sorted().joined(separator: ", ")
            return Resolution(matches: [:], diagnostic: diagnostic(
                .ambiguousIdentity,
                "The relation identity ‘\(query.noteIdentity)’ is ambiguous: \(candidates).",
                range: query.sourceRange
            ))
        }
        guard let graph = catalog.graph,
              let searchGeneration,
              graph.sourceManifestHash == searchGeneration.sourceManifestHash else {
            return Resolution(matches: [:], diagnostic: diagnostic(
                .notApplicable,
                "Direct relation Search is unavailable until Graph and Note Search share one complete source manifest.",
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
        var matches: [VaultQualifiedNoteID: SearchRelationshipMatch] = [:]
        for edge in graph.relationships where edge.vectorKind == vectorKind(query.relation) {
            guard let subject = edge.subjectNote, let object = edge.objectNote else { continue }
            let target: VaultQualifiedNoteID?
            if query.relation.isSymmetric {
                if subject == anchorID { target = object }
                else if object == anchorID { target = subject }
                else { target = nil }
            } else {
                switch query.direction {
                case .fromNote:
                    target = subject == anchorID ? object : nil
                case .toNote:
                    target = object == anchorID ? subject : nil
                }
            }
            guard let target, target != anchorID, authorizedIDs.contains(target) else { continue }
            let occurrences = Array(Set(
                (matches[target]?.occurrences ?? []) + edge.occurrences
            )).sorted {
                if $0.sourceNote != $1.sourceNote { return $0.sourceNote < $1.sourceNote }
                if $0.locator.line != $1.locator.line {
                    return $0.locator.line < $1.locator.line
                }
                return $0.locator.column < $1.locator.column
            }
            matches[target] = SearchRelationshipMatch(
                relation: query.relation,
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

    private static func vectorKind(_ relation: SearchRelation) -> VectorLinkKind {
        switch relation {
        case .supports: .supports
        case .opposes: .opposes
        case .neutral: .neutral
        case .incompatible: .incompatible
        }
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
