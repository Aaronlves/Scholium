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
    /// Resolves the source-evidence owner for this Run. Every Run now owns its
    /// own frozen evidence; Check Fidelity is an independent researcher-started
    /// Action rather than an automatic child.
    func effectiveResearchAgentEvidence(
        for record: LocalResearchExecutionRecord
    ) async throws -> ResearchAgentEffectiveEvidence {
        return ResearchAgentEffectiveEvidence(
            sourceReference: record.snapshot.sourceReference,
            zoteroBibliographicContext:
                record.snapshot.zoteroBibliographicContext,
            analysisSourceRoute: record.snapshot.analysisSourceRoute,
            isAnalyzeAction:
                record.snapshot.actionSnapshot?.actionID == .analyze
        )
    }
}
