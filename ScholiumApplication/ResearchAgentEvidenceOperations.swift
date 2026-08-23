import Foundation
import ScholiumContracts
import ScholiumCore

struct ResearchAgentEffectiveEvidence: Sendable {
    let sourceReference: ResearchSourceReference?
    let zoteroBibliographicContext: ZoteroBibliographicContext?
    let analysisSourceRoute: ResearchAnalysisSourceRoute?
    let isAnalyzeAction: Bool
}

extension WorkspaceHandle {
    /// Resolves the independently frozen source-evidence owner for this Run.
    func effectiveResearchAgentEvidence(
        for record: LocalResearchExecutionRecord
    ) async throws -> ResearchAgentEffectiveEvidence {
        ResearchAgentEffectiveEvidence(
            sourceReference: record.snapshot.sourceReference,
            zoteroBibliographicContext:
                record.snapshot.zoteroBibliographicContext,
            analysisSourceRoute: record.snapshot.analysisSourceRoute,
            isAnalyzeAction:
                record.snapshot.actionSnapshot.actionID == .analyze
        )
    }
}
