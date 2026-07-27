import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func actionProfiles() async throws -> ResearchActionProfileSnapshot? {
        try requireActive()
        return try await services.researchSkillStore.actionProfileSnapshot()
    }

    func saveActionProfile(
        _ binding: ResearchActionProfileBinding,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.saveActionProfile(
            binding,
            expectedDocumentRevision: expectedDocumentRevision
        )
    }

    func removeActionProfile(
        actionID: ResearchActionID,
        expectedDocumentRevision: DocumentFingerprint
    ) async throws -> ResearchActionProfileSnapshot {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.removeActionProfile(
            actionID: actionID,
            expectedDocumentRevision: expectedDocumentRevision
        )
    }

    func saveActionProfileDocument(
        _ document: ResearchActionProfileDocument,
        expectedDocumentRevision: DocumentFingerprint?
    ) async throws -> ResearchActionProfileSnapshot {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.saveActionProfileDocument(
            document,
            expectedRevision: expectedDocumentRevision
        )
    }

    func installDefaultWorkingMethods()
        async throws -> ResearchWorkingMethodBindingSnapshot
    {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.installDefaultWorkingMethods()
    }

    func workingMethodBindings() async throws -> ResearchWorkingMethodBindingSnapshot? {
        try requireActive()
        return try await services.researchSkillStore.workingMethodBindingSnapshot()
    }

    func saveWorkingMethod(
        for actionID: ResearchActionID,
        source: String,
        expectedPackageRevision: DocumentFingerprint,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.saveWorkingMethod(
            for: actionID,
            source: source,
            expectedPackageRevision: expectedPackageRevision,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    func disableWorkingMethod(
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.disableWorkingMethod(
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    func activateResearcherSkill(
        packageID: String,
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodBindingSnapshot {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.activateResearcherSkill(
            packageID: packageID,
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    func restoreBundledWorkingMethod(
        for actionID: ResearchActionID,
        expectedPackageState: ResearchWorkingMethodExpectedPackageState,
        expectedBindingRevision: DocumentFingerprint
    ) async throws -> ResearchWorkingMethodRestoreOutcome {
        try requireActive()
        let mutationID = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationID) }
        return try await services.researchSkillStore.restoreBundledWorkingMethod(
            for: actionID,
            expectedPackageState: expectedPackageState,
            expectedBindingRevision: expectedBindingRevision
        )
    }

}
