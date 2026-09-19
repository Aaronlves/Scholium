import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func researchSnapshot() throws -> WorkspaceResearchSnapshot {
        try requireActive()
        return currentSnapshot.research
    }

    public func agentChatWorkspaceURL() async throws -> URL {
        try requireActive()
        return await services.controlStore.controlURL
    }

}
