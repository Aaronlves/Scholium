import Foundation
import ScholiumContracts
import ScholiumCore

/// Narrow WorkspaceHandle-owned ports for callers that must not borrow the
/// complete internal service composition.
extension WorkspaceHandle {
    func validatePortableIdentityForReidentification(_ stableID: UUID) async throws {
        try requireActive()
        try await services.researchConfigurationStore
            .validatePortableIdentityForReidentification(stableID)
    }

    func revokeResearchAgentSession(_ sessionID: UUID) async throws {
        try requireActive()
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        await sessions.revokeSession(sessionID)
    }

    func researchSourceMaterialStatus(
        for analysisNoteID: UUID
    ) async -> ResearchSourceAccessStatus {
        await services.researchSourceAccessStore.status(
            analysisNoteID: analysisNoteID
        )
    }
}
