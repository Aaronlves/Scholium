import Foundation
import ScholiumContracts
import ScholiumCore

public enum ResearchPermissionOperationError: LocalizedError, Hashable, Sendable {
    case subjectUnavailable(String)
    case staleSubject(String)

    public var errorDescription: String? {
        switch self {
        case .subjectUnavailable(let packageID):
            "Skill \(packageID) is not active in this Triptych."
        case .staleSubject(let packageID):
            "Skill \(packageID) or one of its Action Profiles changed. Reload Research Guidance before continuing."
        }
    }
}

extension WorkspaceHandle {
    func permissionSettings() async throws -> ResearchPermissionSettingsSnapshot {
        try requireActive()
        let policy = try await services.researchPermissionPolicyStore.snapshot()
        return try await permissionSettings(policy: policy)
    }

    func saveTriptychPermissionPolicy(
        _ policy: ResearchPermissionPolicy,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        let saved = try await services.researchPermissionPolicyStore
            .saveTriptychDefault(policy, expectedRevision: expectedRevision)
        return try await permissionSettings(policy: saved)
    }

    func saveSkillPermissionOverride(
        packageID: String,
        policy: ResearchPermissionPolicy,
        expectedEnvelopeDigest: DocumentFingerprint,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        guard let subject = try await researchPermissionSubjects()
            .first(where: { $0.packageID == packageID }) else {
            throw ResearchPermissionOperationError.subjectUnavailable(packageID)
        }
        guard subject.envelopeDigest == expectedEnvelopeDigest else {
            throw ResearchPermissionOperationError.staleSubject(packageID)
        }
        let saved = try await services.researchPermissionPolicyStore.saveOverride(
            packageID: packageID,
            policy: policy,
            approvedEnvelopeDigest: expectedEnvelopeDigest,
            expectedRevision: expectedRevision
        )
        return try await permissionSettings(policy: saved)
    }

    func removeSkillPermissionOverride(
        packageID: String,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try requireActive()
        let mutationLease = try await beginResearchConfigurationMutation()
        defer { endResearchConfigurationMutation(mutationLease) }
        let saved = try await services.researchPermissionPolicyStore.removeOverride(
            packageID: packageID,
            expectedRevision: expectedRevision
        )
        return try await permissionSettings(policy: saved)
    }

    func evaluateStandingPermission(
        _ request: ResearchStandingPermissionRequest
    ) async throws -> ResearchPermissionEvaluation {
        try requireActive()
        guard let subject = try await researchPermissionSubjects()
            .first(where: { $0.packageID == request.packageID }) else {
            throw ResearchPermissionOperationError.subjectUnavailable(request.packageID)
        }
        guard subject.envelopeDigest == request.currentEnvelopeDigest else {
            throw ResearchPermissionOperationError.staleSubject(request.packageID)
        }
        let snapshot = try await services.researchPermissionPolicyStore.snapshot()
        guard let revalidatedSubject = try await researchPermissionSubjects()
            .first(where: { $0.packageID == request.packageID }),
              revalidatedSubject.envelopeDigest == subject.envelopeDigest else {
            throw ResearchPermissionOperationError.staleSubject(request.packageID)
        }
        return ResearchPermissionPolicyResolver.evaluate(
            document: snapshot.document,
            request: request
        )
    }

    func evaluateStandingPermission(
        for request: AgentNoteChangeRequest
    ) async throws -> ResearchPermissionEvaluation {
        guard let subject = try await researchPermissionSubjects()
            .first(where: { $0.packageID == request.requestedAction.packageID }) else {
            throw ResearchPermissionOperationError.subjectUnavailable(
                request.requestedAction.packageID
            )
        }
        let requestedRoles = Set(request.targets.map(\.role))
        guard subject.packageRevision == request.requestedAction.skillRevision,
              requestedRoles.allSatisfy({ role in
                  subject.profiles.contains {
                      $0.actionID == request.requestedAction.definition.id
                          && $0.targetRole == role
                          && $0.profileRevision
                            == request.requestedAction.profileRevision
                  }
              }) else {
            throw ResearchPermissionOperationError.staleSubject(
                request.requestedAction.packageID
            )
        }
        return try await evaluateStandingPermission(
            ResearchStandingPermissionRequest(
                kind: .additionalNoteChanges,
                packageID: subject.packageID,
                currentEnvelopeDigest: subject.envelopeDigest,
                requestedWritableRoles: requestedRoles
            )
        )
    }

    private func permissionSettings(
        policy: ResearchPermissionPolicySnapshot
    ) async throws -> ResearchPermissionSettingsSnapshot {
        let subjects = try await researchPermissionSubjects()
        let subjectByPackage = Dictionary(uniqueKeysWithValues: subjects.map {
            ($0.packageID, $0)
        })
        var statuses = subjects.map { subject in
            Self.permissionStatus(
                subject: subject,
                override: policy.document.override(for: subject.packageID),
                triptychDefault: policy.document.triptychDefault
            )
        }
        let retainedPackageIDs = Set(statuses.map(\.packageID))
        statuses.append(contentsOf: policy.document.skillOverrides.compactMap { override in
            guard !retainedPackageIDs.contains(override.packageID),
                  subjectByPackage[override.packageID] == nil else {
                return nil
            }
            return ResearchPermissionSkillStatus(
                packageID: override.packageID,
                displayName: override.packageID,
                subject: nil,
                overridePolicy: override.policy,
                effectivePolicy: .askEveryTime,
                status: .missingSkill
            )
        })
        statuses.sort {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame
                ? $0.packageID < $1.packageID
                : order == .orderedAscending
        }
        return ResearchPermissionSettingsSnapshot(policy: policy, skills: statuses)
    }

    private static func permissionStatus(
        subject: ResearchPermissionSubject,
        override: ResearchSkillPermissionOverride?,
        triptychDefault: ResearchPermissionPolicy
    ) -> ResearchPermissionSkillStatus {
        guard let override else {
            return ResearchPermissionSkillStatus(
                packageID: subject.packageID,
                displayName: subject.displayName,
                subject: subject,
                overridePolicy: nil,
                effectivePolicy: triptychDefault,
                status: .inherited
            )
        }
        let isCurrent = override.approvedEnvelopeDigest == subject.envelopeDigest
        return ResearchPermissionSkillStatus(
            packageID: subject.packageID,
            displayName: subject.displayName,
            subject: subject,
            overridePolicy: override.policy,
            effectivePolicy: isCurrent ? override.policy : .askEveryTime,
            status: isCurrent ? .approved : .invalidated
        )
    }

    private func researchPermissionSubjects() async throws
        -> [ResearchPermissionSubject]
    {
        let packages = try await services.researchSkillStore.skills()
        let packagesByID = Dictionary(
            packages.filter { $0.origin == .triptych && $0.isValid }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var profileRevisionsByPackage: [
            String: [String: ResearchPermissionProfileRevision]
        ] = [:]
        var displayNameByPackage: [String: String] = [:]

        if let working = try await services.researchSkillStore
            .workingMethodBindingSnapshot() {
            for rawActionID in working.document.actionBindings.keys.sorted() {
                guard let actionID = ResearchActionID(rawValue: rawActionID),
                      let binding = working.document.binding(for: actionID),
                      binding.state != .disabled,
                      let packageID = binding.packageID,
                      packagesByID[packageID] != nil,
                      let definition = Self.permissionDefinition(for: actionID) else {
                    continue
                }
                guard let representativeRole = definition.allowedTargetRoles.sorted(
                    by: { $0.rawValue < $1.rawValue }
                ).first else { continue }
                let function = try ResearchActionFunctionMapping.function(
                    for: definition,
                    targetRole: representativeRole
                )
                let resolution = try await services.researchSkillStore
                    .functionBindingResolution(
                        for: function,
                        actionID: actionID
                    )
                guard resolution.issue == nil,
                      resolution.package?.id == packageID else { continue }
                for role in definition.allowedTargetRoles {
                    let profile = try Self.defaultProfile(
                        for: definition,
                        targetRole: role
                    )
                    displayNameByPackage[packageID] = profile.buttonName
                    let revision = try ResearchPermissionProfileRevision(
                        actionID: actionID,
                        targetRole: role,
                        profileRevision: profile.contentRevision()
                    )
                    profileRevisionsByPackage[packageID, default: [:]][
                        Self.permissionProfileKey(actionID: actionID, role: role)
                    ] = revision
                }
            }
        }

        if let profiles = try await services.researchSkillStore.actionProfileSnapshot() {
            for binding in profiles.document.orderedBindings {
                guard packagesByID[binding.packageID] != nil,
                      let representativeRole = binding.profile.applicableRoles.first else {
                    continue
                }
                let function = try ResearchActionFunctionMapping.function(
                    for: binding.profile.definition,
                    targetRole: representativeRole
                )
                let resolution = try await services.researchSkillStore
                    .profileActionBindingResolution(
                        for: function,
                        actionID: binding.profile.actionID
                    )
                guard resolution.issue == nil,
                      resolution.package?.id == binding.packageID else { continue }
                if displayNameByPackage[binding.packageID] == nil {
                    displayNameByPackage[binding.packageID] = binding.profile.buttonName
                }
                for role in binding.profile.applicableRoles {
                    let revision = try ResearchPermissionProfileRevision(
                        actionID: binding.profile.actionID,
                        targetRole: role,
                        profileRevision: binding.profile.contentRevision()
                    )
                    // Manuscript has both one Working Method binding and one
                    // researcher-editable Profile. The exact active Profile
                    // replaces the Application default for the same
                    // Action/role rather than creating an ambiguous duplicate.
                    profileRevisionsByPackage[binding.packageID, default: [:]][
                        Self.permissionProfileKey(
                            actionID: binding.profile.actionID,
                            role: role
                        )
                    ] = revision
                }
            }
        }

        return try profileRevisionsByPackage.compactMap { packageID, profiles in
            guard let package = packagesByID[packageID],
                  let revision = package.revision else {
                return nil
            }
            return try ResearchPermissionSubject(
                packageID: packageID,
                displayName: displayNameByPackage[packageID] ?? package.name,
                packageRevision: revision,
                profiles: Array(profiles.values)
            )
        }.sorted {
            if $0.displayName != $1.displayName {
                return $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }
            return $0.packageID < $1.packageID
        }
    }

    private static func permissionDefinition(
        for actionID: ResearchActionID
    ) -> ResearchActionDefinition? {
        switch actionID {
        case .discuss: .discuss
        case .analyze: .analyze
        case .synthesize: .synthesize
        case .write: .write
        case .critique: .critique
        case .checkFidelity: .checkFidelity
        case .manuscript: .manuscript
        default: nil
        }
    }

    private static func permissionProfileKey(
        actionID: ResearchActionID,
        role: ResearchActionTargetRole
    ) -> String {
        "\(actionID.rawValue):\(role.rawValue)"
    }
}

extension ResearchOperations {
    public func permissionSettings() async throws
        -> ResearchPermissionSettingsSnapshot
    {
        try await reference.requireHandle().permissionSettings()
    }

    public func saveTriptychPermissionPolicy(
        _ policy: ResearchPermissionPolicy,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try await reference.requireHandle().saveTriptychPermissionPolicy(
            policy,
            expectedRevision: expectedRevision
        )
    }

    public func saveSkillPermissionOverride(
        packageID: String,
        policy: ResearchPermissionPolicy,
        expectedEnvelopeDigest: DocumentFingerprint,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try await reference.requireHandle().saveSkillPermissionOverride(
            packageID: packageID,
            policy: policy,
            expectedEnvelopeDigest: expectedEnvelopeDigest,
            expectedRevision: expectedRevision
        )
    }

    public func removeSkillPermissionOverride(
        packageID: String,
        expectedRevision: DocumentFingerprint?
    ) async throws -> ResearchPermissionSettingsSnapshot {
        try await reference.requireHandle().removeSkillPermissionOverride(
            packageID: packageID,
            expectedRevision: expectedRevision
        )
    }

    public func evaluateStandingPermission(
        _ request: ResearchStandingPermissionRequest
    ) async throws -> ResearchPermissionEvaluation {
        try await reference.requireHandle().evaluateStandingPermission(request)
    }
}
