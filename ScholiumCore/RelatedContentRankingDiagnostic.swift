import ScholiumContracts

/// Request-local diagnostics for an explicitly observed evaluation. No source
/// text or query is retained, persisted, or added to the public result contract.
struct RelatedContentRankingDiagnostic {
    enum Stage: String, Codable {
        case rejectedSource, unavailableProjection, noParagraphs, noLocalMatch
        case localMatch, insufficientFocus, eligible, duplicate, limited, selected
    }

    let note: VaultQualifiedNoteID
    let range: SearchSourceRange?
    let stage: Stage
    var coverage: Double? = nil
}
