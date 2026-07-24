import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceRuntime: ResearchSkillInstallationUseCases {
    public func stageResearcherSkillInstallation(
        from directoryURL: URL
    ) async throws -> ResearchSkillInstallationPreparation {
        // `availableWorkspaces` supplies the runtime-active check without
        // opening or mutating any Triptych merely to inspect a local package.
        _ = try await availableWorkspaces()
        return try await researchSkillInstallationStore.stage(
            directoryURL: directoryURL
        )
    }

    public func installResearcherSkill(
        _ preparation: ResearchSkillInstallationPreparation,
        to triptychIDs: [UUID]
    ) async throws -> ResearchSkillInstallationOutcome {
        guard !triptychIDs.isEmpty else {
            throw ResearchSkillInstallationError.noTriptychsSelected
        }
        var selected: Set<UUID> = []
        for triptychID in triptychIDs where !selected.insert(triptychID).inserted {
            throw ResearchSkillInstallationError.duplicateTriptych(triptychID)
        }

        var destinations: [ResearchSkillInstallationDestination] = []
        for triptychID in triptychIDs {
            let handle = try await openWorkspace(id: triptychID)
            destinations.append(ResearchSkillInstallationDestination(
                triptychID: triptychID,
                skillStore: handle.services.researchSkillStore
            ))
        }
        return try await researchSkillInstallationStore.install(
            preparation,
            destinations: destinations
        )
    }

    public func discardResearcherSkillInstallation(preparationID: UUID) async {
        await researchSkillInstallationStore.discard(preparationID: preparationID)
    }
}
