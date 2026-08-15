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

    public func collaborationPolicy() async throws -> ResearchCollaborationPolicySnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.currentCollaborationPolicy()
    }

    public func saveCollaborationPolicy(
        _ document: ResearchCollaborationPolicyDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchCollaborationPolicySnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveCurrentCollaborationPolicy(
            document,
            expectedRevision: expectedRevision
        )
    }

    public func researchMethod(
        for actionID: ResearchActionID
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.currentResearchMethod(for: actionID)
    }

    public func saveResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.saveCurrentResearchMethod(
            registrationKey: registrationKey,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    public func registerExternalResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        primaryMarkdownPath: String,
        skillFolderPath: String?,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.registerExternalResearchMethod(
            actionID: actionID,
            displayName: displayName,
            primaryMarkdownPath: primaryMarkdownPath,
            skillFolderPath: skillFolderPath,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    public func createResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        source: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.createResearchMethod(
            actionID: actionID,
            displayName: displayName,
            source: source,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    public func restorePreviousResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.restorePreviousResearchMethod(
            registrationKey: registrationKey,
            expectedRevision: expectedRevision
        )
    }

    public func restoreDefaultResearchMethod(
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.restoreDefaultResearchMethod(
            actionID: actionID,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    public func preserveInvalidMachineLocalMethodLocatorsAndReset() async throws -> URL? {
        let handle = try await reference.requireHandle()
        return try await handle.preserveInvalidMachineLocalMethodLocatorsAndReset()
    }

    public func philosophicalPractices() async throws -> [ResearchPracticeSnapshot] {
        let handle = try await reference.requireHandle()
        return try await handle.currentPhilosophicalPractices()
    }

    public func createPhilosophicalPractice(
        title: String,
        source: String
    ) async throws -> ResearchPracticeSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.createPhilosophicalPractice(title: title, source: source)
    }

    public func savePhilosophicalPractice(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.savePhilosophicalPractice(
            relativePath: relativePath,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    public func restorePreviousPhilosophicalPractice(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        let handle = try await reference.requireHandle()
        return try await handle.restorePreviousPhilosophicalPractice(
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )
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

    func currentCollaborationPolicy() async throws
        -> ResearchCollaborationPolicySnapshot
    {
        try requireActive()
        guard let snapshot = try await services.researchConfigurationStore
            .collaborationSnapshot() else {
            throw ResearchConfigurationStoreError.missingCollaborationPolicy
        }
        return snapshot
    }

    func saveCurrentCollaborationPolicy(
        _ document: ResearchCollaborationPolicyDocument,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchCollaborationPolicySnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.saveCollaborationPolicy(
            document,
            expectedRevision: expectedRevision
        )
    }

    func currentResearchMethod(
        for actionID: ResearchActionID
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        return try await services.researchConfigurationStore.methodSnapshot(
            for: actionID
        )
    }

    func saveCurrentResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.savePrimaryMethod(
            registrationKey: registrationKey,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func registerExternalResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        primaryMarkdownPath: String,
        skillFolderPath: String?,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.registerExternalMethod(
            actionID: actionID,
            displayName: displayName,
            primaryMarkdownPath: primaryMarkdownPath,
            skillFolderPath: skillFolderPath,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    func createResearchMethod(
        actionID: ResearchActionID,
        displayName: String,
        source: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.createPrimaryMethod(
            actionID: actionID,
            displayName: displayName,
            source: source,
            expectedRegistrationRevision: expectedRegistrationRevision
        )
    }

    func restorePreviousResearchMethod(
        registrationKey: ResearchSkillRegistrationKey,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.restorePrimaryMethod(
            registrationKey: registrationKey,
            expectedRevision: expectedRevision
        )
    }

    func restoreDefaultResearchMethod(
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchMethodSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.restoreDefaultPrimaryMethod(
            actionID: actionID,
            expectedRevision: expectedRevision
        )
    }

    @discardableResult
    func preserveInvalidMachineLocalMethodLocatorsAndReset() async throws -> URL? {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore
            .preserveInvalidMachineLocalMethodLocatorsAndReset()
    }

    func currentPhilosophicalPractices() async throws -> [ResearchPracticeSnapshot] {
        try requireActive()
        return try await services.researchConfigurationStore.practiceCatalog()
    }

    func createPhilosophicalPractice(
        title: String,
        source: String
    ) async throws -> ResearchPracticeSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.createPractice(
            title: title,
            source: source
        )
    }

    func savePhilosophicalPractice(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.savePractice(
            relativePath: relativePath,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func restorePreviousPhilosophicalPractice(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchPracticeSnapshot {
        try requireActive()
        let lease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(lease) }
        return try await services.researchConfigurationStore.restorePreviousPractice(
            relativePath: relativePath,
            expectedRevision: expectedRevision
        )
    }
}
