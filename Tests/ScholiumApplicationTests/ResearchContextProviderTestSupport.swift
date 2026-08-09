import Foundation
import ScholiumContracts
@testable import ScholiumApplication

/// Test-only provider with a mechanism distinct from production Search: one
/// injected nonprivate summary candidate is checked against the authorized
/// Workspace snapshot and adapted directly into the shared response contract.
/// It owns no runtime fallback, index, parser, ranker, or persisted state.
struct FixtureSummaryResearchContextProvider: ResearchContextProviding {
    enum State: Equatable, Sendable {
        case current
        case stale
        case unavailable
    }

    let state: State
    let expectedQuery: String
    let noteID: UUID
    let note: VaultQualifiedNoteID
    let role: ResearchFunctionTargetRole
    let title: String
    let summary: String
    let summaryRange: SearchSourceRange
    let fingerprint: DocumentFingerprint

    func response(
        for query: ResearchContextQuery,
        run: ResearchContextRunEvidence,
        workspace: WorkspaceSnapshot,
        access: ResearchContextOwnerAccess
    ) async throws -> ResearchContextResponse {
        _ = run
        _ = access
        guard query.triptychID == workspace.triptych.id else {
            throw ResearchContextContractError.invalidAuthorizedScope
        }
        let outcomes = try query.clauses.map { clause in
            guard clause.kind == .discoverNote,
                  clause.query == expectedQuery else {
                return try ResearchContextClauseOutcome(
                    clause: clause,
                    availability: .invalidQuery,
                    items: [],
                    limitations: [
                        "The fixed summary fixture accepts only its declared Note-discovery query."
                    ]
                )
            }
            if state == .unavailable {
                return try ResearchContextClauseOutcome(
                    clause: clause,
                    availability: .unavailable,
                    items: [],
                    limitations: [
                        "The fixed summary fixture is deliberately unavailable."
                    ]
                )
            }
            guard let snapshot = workspace.document(id: note),
                  snapshot.stableIdentity.resolvedID == noteID else {
                return try ResearchContextClauseOutcome(
                    clause: clause,
                    availability: .unavailable,
                    items: [],
                    limitations: [
                        "The fixed candidate has no current Application-owned Note identity."
                    ]
                )
            }
            let isCurrent = state == .current
                && snapshot.fingerprint == fingerprint
            let currentness: ResearchContextCurrentness = isCurrent
                ? .current : .stale
            let availability: ResearchContextAvailability = isCurrent
                ? .current : .stale
            let limitations = ResearchContextNoteProjection
                .unknownWriterLimitations + (isCurrent ? [] : [
                "The fixed provider candidate is stale and must not be recorded as current use."
            ])
            let envelope = try SourceReferenceEnvelope(
                sourceKind: .note,
                owner: .note(
                    triptychID: query.triptychID,
                    note: note,
                    stableObjectIdentity: noteID.uuidString.lowercased()
                ),
                actorClass: .unknown,
                objectRole: objectRole,
                vaultRole: vaultRole,
                fingerprint: fingerprint,
                locator: try .sourceRange(summaryRange),
                authorizedScope: .triptych(
                    runID: query.runID,
                    triptychID: query.triptychID
                ),
                currentness: currentness,
                evidentialLayer: evidentialLayer,
                retrievalReason: .canonicalSummary,
                materialLimitations: limitations
            )
            let item = try ResearchContextResponseItem(
                clauseID: clause.id,
                sourceReference: envelope,
                title: title,
                contentKind: .searchSnippet,
                semanticContent: summary,
                contextUseEligibility:
                    clause.useEligibility == .contextUse && isCurrent
                        ? .contextUse : .referenceOnly,
                noteMatchReasons: [.lexical]
            )
            return try ResearchContextClauseOutcome(
                clause: clause,
                availability: availability,
                items: [item],
                limitations: isCurrent ? [] : Array(limitations.suffix(1))
            )
        }
        return try ResearchContextResponse(query: query, outcomes: outcomes)
    }

    private var vaultRole: VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    private var objectRole: ResearchContextObjectRole {
        switch role {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }

    private var evidentialLayer: EvidentialLayer {
        switch role {
        case .analysis: .paperAnalysis
        case .topic: .topicNote
        case .work: .draftProse
        }
    }
}
