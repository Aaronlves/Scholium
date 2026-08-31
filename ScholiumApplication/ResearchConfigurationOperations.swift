import Foundation
import ScholiumContracts
import ScholiumCore

extension ResearchOperations {
    public func researchSkillRegistrations() async throws
        -> ResearchSkillRegistrationSnapshot
    {
        let handle = try await reference.requireHandle()
        return try await handle.currentResearchSkillRegistrations()
    }

    public func saveResearchSkillRegistrations(
        _ document: ResearchSkillRegistrationDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillRegistrationSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveCurrentResearchSkillRegistrations(
            document,
            expectedRevision: expectedRevision
        )
    }

    public func academicActionProfiles() async throws -> ResearchAcademicProfileSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.currentAcademicActionProfiles()
    }

    public func saveAcademicActionProfiles(
        _ document: ResearchAcademicProfileDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchAcademicProfileSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveCurrentAcademicActionProfiles(
            document,
            expectedRevision: expectedRevision
        )
    }

    public func researchSkillBinding(
        for actionID: ResearchActionID
    ) async throws -> ResearchSkillBindingSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.currentResearchSkillBinding(for: actionID)
    }

    public func registerExternalResearchSkillFolder(
        actionID: ResearchActionID,
        displayName: String,
        skillFolderPath: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchSkillBindingSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.registerExternalResearchSkillFolder(
            actionID: actionID,
            displayName: displayName,
            skillFolderPath: skillFolderPath,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    public func researchSkillFolderAccess(
        for actionID: ResearchActionID
    ) async throws -> any ResearchSkillFolderAccess {
        let handle = try await reference.requireHandle()
        return try await handle.currentResearchSkillFolderAccess(
            for: actionID
        )
    }

    @discardableResult
    public func preserveInvalidMachineLocalSkillFolderLocatorsAndReset() async throws
        -> URL?
    {
        let handle = try await reference.requireHandle()
        return try await handle
            .preserveInvalidMachineLocalSkillFolderLocatorsAndReset()
    }

}

extension WorkspaceHandle {
    func currentResearchSkillRegistrations() async throws
        -> ResearchSkillRegistrationSnapshot
    {
        try requireActive()
        guard let snapshot = try await services.researchConfigurationStore
            .registrationSnapshot() else {
            throw ResearchConfigurationStoreError.missingRegistrations
        }
        return snapshot
    }

    func saveCurrentResearchSkillRegistrations(
        _ document: ResearchSkillRegistrationDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillRegistrationSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.saveRegistrations(
            document,
            expectedRevision: expectedRevision
        )
    }

    func currentAcademicActionProfiles() async throws -> ResearchAcademicProfileSnapshot {
        try requireActive()
        guard let snapshot = try await services.researchConfigurationStore.profileSnapshot()
        else { throw ResearchConfigurationStoreError.missingProfiles }
        return snapshot
    }

    func saveCurrentAcademicActionProfiles(
        _ document: ResearchAcademicProfileDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchAcademicProfileSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.saveProfiles(
            document,
            expectedRevision: expectedRevision
        )
    }

    func currentResearchSkillBinding(
        for actionID: ResearchActionID
    ) async throws -> ResearchSkillBindingSnapshot {
        try requireActive()
        return try await services.researchConfigurationStore.skillBindingSnapshot(
            for: actionID
        )
    }

    func registerExternalResearchSkillFolder(
        actionID: ResearchActionID,
        displayName: String,
        skillFolderPath: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchSkillBindingSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore
            .registerExternalSkillFolder(
            actionID: actionID,
            displayName: displayName,
            skillFolderPath: skillFolderPath,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    func currentResearchSkillFolderAccess(
        for actionID: ResearchActionID
    ) async throws -> any ResearchSkillFolderAccess {
        try requireActive()
        return try await services.researchConfigurationStore.skillFolderAccess(
            for: actionID
        )
    }

    @discardableResult
    func preserveInvalidMachineLocalSkillFolderLocatorsAndReset() async throws
        -> URL?
    {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore
            .preserveInvalidMachineLocalSkillFolderLocatorsAndReset()
    }

}
