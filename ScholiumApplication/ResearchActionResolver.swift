import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchActionResolverDependencies: Sendable {
    let portableResearchRecordStore: PortableResearchRecordStore
    let researchConfigurationStore: ResearchConfigurationStore
}

extension WorkspaceServices {
    var researchActionResolverDependencies:
        WorkspaceResearchActionResolverDependencies {
        WorkspaceResearchActionResolverDependencies(
            portableResearchRecordStore: portableResearchRecordStore,
            researchConfigurationStore: researchConfigurationStore
        )
    }
}

struct ResolvedResearchActionContext: Sendable {
    let availability: ResearchActionAvailability
    let function: ResearchFunctionID
    let method: ResearchMethodSnapshot
    let platformInputs: ResearchActionPlatformInputs
    let academicInputs: ResearchAcademicFieldValues
    let resultContract: ResearchResultContract
    let authority: ResearchAuthorityEnvelope
}

private struct ResolvedResearchActionCandidate: Sendable {
    let availability: ResearchActionAvailability
    let function: ResearchFunctionID
    let method: ResearchMethodSnapshot?
}

extension WorkspaceHandle {
    func researchActionAvailability(
        for target: ResearchActionNoteSnapshot,
        checkingSourceAccess: Bool = true
    ) async throws -> [ResearchActionAvailability] {
        try requireCompleteWorkspace()
        let functionTarget = target.functionTarget
        return try await resolvedResearchActions(
            for: functionTarget,
            checkingSourceAccess: checkingSourceAccess
        )
            .map(\.availability)
    }

    func prepareResearchAction(
        _ request: ResearchActionExecutionRequest,
        allowsResearcherProvidedSource: Bool = false,
        runIDOverride: UUID? = nil
    ) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        let resolved = try await resolvedResearchActionExecution(request)
        let prepared = try await researchFunctionCoordinator.prepareResearchFunction(
            resolved.request,
            actionContext: resolved.context,
            runIDOverride: runIDOverride,
            requiresAgentChangeEvidence:
                !resolved.context.authority.writableNotes.isEmpty,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource,
            host: self
        )
        let functionPreparation = try researchFunctionCoordinator.attachingAgentActions(
            to: prepared
        )
        guard let snapshot = functionPreparation.snapshot.actionSnapshot else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: functionPreparation.runID,
            instructions: functionPreparation.instructions,
            state: ResearchActionRunState(functionPreparation.state),
            derivedRefreshWarning: functionPreparation.derivedRefreshWarning,
            nextActions: functionPreparation.nextActions ?? []
        )
    }

    func researchActionMaterialCandidates(
        for target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID
    ) async throws -> [ResearchActionNoteSnapshot] {
        try requireCompleteWorkspace()
        let candidates = try await resolvedResearchActions(
            for: target.functionTarget,
            checkingSourceAccess: false
        )
        guard let candidate = candidates.first(where: {
            $0.availability.id == actionID && $0.availability.isEnabled
        }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return try await researchFunctionCoordinator.researchFunctionMaterialCandidates(
            for: target.functionTarget,
            function: candidate.function,
            host: self
        ).map { $0.material.actionNote }
    }

    func researchActionRun(id: UUID) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        return try await publicActionPreparation(
            from: researchFunctionCoordinator.researchFunctionRun(
                id: id,
                host: self
            )
        )
    }

    func prepareResearchActionFidelity(
        parentRunID: UUID
    ) async throws -> ResearchActionFidelityPreparation {
        try requireCompleteWorkspace()
        let prepared = try await researchFunctionCoordinator.prepareAutomaticFidelity(
            parentRunID: parentRunID,
            host: self
        )
        let automatic = try researchFunctionCoordinator.attachingAgentActions(
            to: prepared
        )
        let preparation = try await publicActionPreparation(from: automatic.preparation)
        return ResearchActionFidelityPreparation(
            parentRunID: automatic.parentRunID,
            preparation: preparation,
            effectiveRunID: automatic.effectiveFidelityRunID,
            reusedExistingEvidence: automatic.reusedExistingEvidence,
            nextActions: automatic.nextActions ?? []
        )
    }

    func prepareResearchResynthesis(
        _ request: ResearchActionExecutionRequest,
        context: MaterialChangedSinceUseAttentionContext
    ) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        guard request.actionID == .synthesize,
              request.expectedExecutionKind == .synthesis,
              context.triptychID == self.id,
              context.recordedRevision != context.currentRevision,
              context.material.stableNoteID.flatMap(UUID.init(uuidString:))
                == context.materialNoteID else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let record = try await researchActionResolverDependencies
            .portableResearchRecordStore.record(
            id: context.recordID
        )
        guard record.triptychID == self.id,
              record.kind == .action,
              record.action?.actionID == .synthesize,
              record.primaryNoteID == context.topicNoteID,
              record.participatingNotes.contains(where: {
                  $0.noteID == context.topicNoteID && $0.role == .topic
              }),
              record.actuallyUsedMaterials.contains(where: {
                  $0.noteID == context.materialNoteID
                      && $0.role == .analysis
                      && $0.revision == context.recordedRevision
              }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let recordListing = try await researchActionResolverDependencies
            .portableResearchRecordStore.listing()
        guard WorkspaceSnapshotBuilder.isLatestSynthesisMaterialUse(
            recordID: context.recordID,
            topicNoteID: context.topicNoteID,
            materialNoteID: context.materialNoteID,
            records: recordListing.records
        ) else {
            throw ResearchActionExecutionContractError.staleResolution
        }

        let resolved = try await resolvedResearchActionExecution(request)
        guard resolved.request.target.noteID == context.topicNoteID,
              resolved.request.target.role == .topic,
              resolved.request.materials.contains(where: {
                  $0.noteID == context.materialNoteID
                      && $0.role == .analysis
                      && $0.note.vaultID == context.material.vaultID
                      && $0.note.relativePath == context.material.relativePath
                      && $0.fingerprint == context.currentRevision
              }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }

        let runID = UUID()
        let lineage = ResearchContinuationLineage(
            groupID: record.continuationLineage?.groupID ?? record.id,
            parentRunID: record.id,
            requestID: runID,
            kind: .resynthesis
        )
        let prepared = try await researchFunctionCoordinator.prepareResearchFunction(
            resolved.request,
            actionContext: resolved.context,
            runIDOverride: runID,
            continuationLineage: lineage,
            resynthesisContext: context,
            requiresAgentChangeEvidence: true,
            host: self
        )
        let functionPreparation = try researchFunctionCoordinator.attachingAgentActions(
            to: prepared
        )
        guard let snapshot = functionPreparation.snapshot.actionSnapshot else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: functionPreparation.runID,
            instructions: functionPreparation.instructions,
            state: ResearchActionRunState(functionPreparation.state),
            derivedRefreshWarning: functionPreparation.derivedRefreshWarning,
            nextActions: functionPreparation.nextActions ?? []
        )
    }

    private func publicActionPreparation(
        from preparation: ResearchFunctionPreparation
    ) async throws -> ResearchActionPreparation {
        guard let snapshot = preparation.snapshot.actionSnapshot else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let attached = try researchFunctionCoordinator.attachingAgentActions(
            to: preparation
        )
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: attached.runID,
            instructions: attached.instructions,
            state: ResearchActionRunState(attached.state),
            derivedRefreshWarning: attached.derivedRefreshWarning,
            nextActions: attached.nextActions ?? []
        )
    }

    func resolvedResearchActionExecution(
        _ request: ResearchActionExecutionRequest
    ) async throws -> (
        request: ResearchFunctionRequest,
        context: ResolvedResearchActionContext
    ) {
        try requireActive()
        let target = request.target.functionTarget
        let candidates = try await resolvedResearchActions(
            for: target,
            checkingSourceAccess: false
        )
        guard let candidate = candidates.first(where: {
            $0.availability.id == request.actionID
        }), candidate.availability.isEnabled,
        let method = candidate.method else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                request.actionID
            )
        }
        guard candidate.availability.definition.executionKind
                == request.expectedExecutionKind,
              candidate.availability.profile.profileRevision
                == request.expectedProfileRevision,
              candidate.availability.profile.profileDocumentRevision
                == request.expectedProfileDocumentRevision else {
            throw ResearchActionExecutionContractError.staleResolution
        }

        let profile = candidate.availability.profile.profile
        let academicInputs = try ResearchAcademicFieldValues(
            rawValues: request.academicInputs.values,
            definitions: profile.academicInputFields
        )
        guard let platform = PlatformActionCatalog.definition(for: request.actionID) else {
            throw ResearchActionExecutionContractError.actionUnavailable(request.actionID)
        }
        let platformInputs = try request.platformInputs.validated(
            for: platform,
            target: target.actionNote
        )
        let prepared = try makeFunctionRequest(
            definition: candidate.availability.definition,
            target: target,
            platform: platform,
            platformInputs: platformInputs,
            academicInputs: academicInputs
        )
        let resultContract = try ResearchResultContract(
            profile: profile,
            registrationKey: method.registration.key,
            profileRevision: candidate.availability.profile.profileRevision
        )
        let context = ResolvedResearchActionContext(
            availability: candidate.availability,
            function: candidate.function,
            method: method,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: resultContract,
            authority: prepared.authority
        )
        return (prepared.request, context)
    }

    func resolvedDefaultActionContext(
        for request: ResearchFunctionRequest
    ) async throws -> ResolvedResearchActionContext {
        try request.validate()
        let definition = try ResearchActionFunctionMapping.definition(
            for: request.function,
            targetRole: request.target.role
        )
        guard let profileSnapshot = try await researchActionResolverDependencies
            .researchConfigurationStore
            .profileSnapshot(),
              let profile = profileSnapshot.document.profile(for: definition.id),
              profile.isEnabled,
              profile.applicableRoles.contains(request.target.role.actionRole),
              let platform = PlatformActionCatalog.definition(for: definition.id) else {
            throw ResearchActionExecutionContractError.actionUnavailable(definition.id)
        }
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: profileSnapshot.revision
        )
        let method = try await researchActionResolverDependencies
            .researchConfigurationStore.methodSnapshot(
            for: definition.id
        )
        guard method.registration.isEnabled else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                definition.id
            )
        }
        let platformInputs = try ResearchActionPlatformInputs(
            focalNotes: request.materials.map(\.actionNote),
            passage: request.scope?.selection,
            fidelityChecks: request.checks
        ).validated(
            for: platform,
            target: request.target.actionNote
        )
        var rawAcademicInputs: [String: ResearchAcademicFieldValue] = [:]
        if let instruction = request.instruction,
           profile.academicInputFields.contains(where: {
               $0.fieldID.rawValue == "research-request"
                   && $0.requirement != .excluded
           }) {
            rawAcademicInputs["research-request"] = .freeText(instruction)
        }
        let academicInputs = try ResearchAcademicFieldValues(
            rawValues: rawAcademicInputs,
            definitions: profile.academicInputFields
        )
        let authority = try Self.authority(
            target: request.target.actionNote,
            additionalReads: request.materials.map(\.actionNote),
            platform: platform
        )
        let resultContract = try ResearchResultContract(
            profile: profile,
            registrationKey: method.registration.key,
            profileRevision: resolvedProfile.profileRevision
        )
        return ResolvedResearchActionContext(
            availability: ResearchActionAvailability(
                definition: definition,
                buttonName: profile.displayName,
                order: profile.order,
                profile: resolvedProfile,
                isEnabled: true
            ),
            function: request.function,
            method: method,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: resultContract,
            authority: authority
        )
    }

    private func resolvedResearchActions(
        for target: ResearchFunctionTarget,
        checkingSourceAccess: Bool
    ) async throws -> [ResolvedResearchActionCandidate] {
        let functionAvailability = Dictionary(uniqueKeysWithValues:
            try await researchFunctionCoordinator.researchFunctionAvailability(
                for: target,
                checkingSourceAccess: checkingSourceAccess,
                host: self
            ).map {
                ($0.function, $0)
            }
        )
        guard let profileSnapshot = try await researchActionResolverDependencies
            .researchConfigurationStore
            .profileSnapshot(),
              let registrationSnapshot = try await researchActionResolverDependencies
                .researchConfigurationStore
                .registrationSnapshot() else {
            throw ResearchConfigurationStoreError.missingProfiles
        }
        var resolved: [ResolvedResearchActionCandidate] = []
        for profile in profileSnapshot.document.profiles where
            profile.applicableRoles.contains(target.role.actionRole)
        {
            guard let definition = Self.actionDefinition(for: profile.actionID),
                  let platform = PlatformActionCatalog.definition(for: profile.actionID) else {
                continue
            }
            let function = try ResearchActionFunctionMapping.function(
                for: definition,
                targetRole: target.role.actionRole
            )
            let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: profileSnapshot.revision
            )
            let registration = registrationSnapshot.document.registration(
                for: definition.id
            )
            let method = try? await researchActionResolverDependencies
                .researchConfigurationStore.methodSnapshot(
                for: definition.id
            )
            let functionState = functionAvailability[function]
            var reasons = (functionState?.repairReasons ?? []).map(
                Self.actionRepairReason
            )
            reasons += await baseActionRepairReasons(
                target: target,
                function: function,
                profile: profile
            )
            if registration == nil {
                reasons.append(ResearchActionRepairReason(code: .methodMissing))
            } else if registration?.isEnabled == false {
                reasons.append(ResearchActionRepairReason(code: .methodDisabled))
            } else if method == nil {
                reasons.append(ResearchActionRepairReason(code: .methodInvalid))
            }
            do {
                try platform.validate(profile: profile)
            } catch {
                reasons.append(ResearchActionRepairReason(code: .profileInvalid))
            }
            resolved.append(ResolvedResearchActionCandidate(
                availability: ResearchActionAvailability(
                    definition: definition,
                    buttonName: profile.displayName,
                    order: profile.order,
                    profile: resolvedProfile,
                    isEnabled: profile.isEnabled
                        && functionState?.isEnabled == true
                        && reasons.isEmpty
                        && method != nil,
                    repairReasons: Self.unique(reasons)
                ),
                function: function,
                method: method
            ))
        }
        return resolved.sorted { lhs, rhs in
            if lhs.availability.order != rhs.availability.order {
                return lhs.availability.order < rhs.availability.order
            }
            return lhs.availability.id.rawValue < rhs.availability.id.rawValue
        }
    }

    private func baseActionRepairReasons(
        target: ResearchFunctionTarget,
        function: ResearchFunctionID,
        profile: ResearchAcademicActionProfile
    ) async -> [ResearchActionRepairReason] {
        var reasons: [ResearchActionRepairReason] = []
        if let reason = await researchFunctionCoordinator
            .researchFunctionTargetRepairReason(target, host: self) {
            reasons.append(Self.actionRepairReason(reason))
        }
        if !function.allowedTargetRoles.contains(target.role)
            || !profile.applicableRoles.contains(target.role.actionRole) {
            reasons.append(ResearchActionRepairReason(code: .invalidTargetRole))
        }
        return Self.unique(reasons)
    }

    private func makeFunctionRequest(
        definition: ResearchActionDefinition,
        target: ResearchFunctionTarget,
        platform: PlatformActionDefinition,
        platformInputs: ResearchActionPlatformInputs,
        academicInputs: ResearchAcademicFieldValues
    ) throws -> (request: ResearchFunctionRequest, authority: ResearchAuthorityEnvelope) {
        let function = try ResearchActionFunctionMapping.function(
            for: definition,
            targetRole: target.role.actionRole
        )
        var seen: Set<UUID> = []
        let additionalReads = platformInputs.focalNotes.filter {
            $0.noteID != target.noteID && seen.insert($0.noteID).inserted
        }
        let materials = additionalReads.map(\.functionMaterial)
        let authority = try Self.authority(
            target: target.actionNote,
            additionalReads: additionalReads,
            platform: platform
        )
        let instruction: String? = if case .freeText(let text)? =
            academicInputs.values["research-request"] { text } else { nil }
        let request = ResearchFunctionRequest(
            function: function,
            target: target,
            materials: materials,
            instruction: function == .discuss
                ? (instruction ?? "Discuss the current Target using the declared Action parameters.")
                : instruction,
            scope: platformInputs.passage.map(ResearchFunctionScope.passage),
            checks: function == .fidelity
                ? (platformInputs.fidelityChecks.isEmpty
                    ? [.content]
                    : Set(platformInputs.fidelityChecks))
                : [],
            dialogueResponseModules: function == .discuss ? [] : nil
        )
        try request.validate()
        return (request, authority)
    }

    private static func authority(
        target: ResearchActionNoteSnapshot,
        additionalReads: [ResearchActionNoteSnapshot],
        platform: PlatformActionDefinition
    ) throws -> ResearchAuthorityEnvelope {
        let writes = platform.operations.contains(.modifyInitialNote)
        return try ResearchAuthorityEnvelope(
            readableNotes: [target] + additionalReads,
            writableNotes: writes ? [target] : [],
            writeOperations: writes ? [.modifyMarkdown, .modifySource] : [],
            editablePropertyKeys: []
        )
    }

    private static func actionDefinition(
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

    private static func actionRepairReason(
        _ reason: ResearchFunctionRepairReason
    ) -> ResearchActionRepairReason {
        let code: ResearchActionRepairReasonCode = switch reason.code {
        case .targetUnavailable: .targetUnavailable
        case .targetChanged: .targetChanged
        case .targetIdentityChanged: .targetIdentityChanged
        case .invalidTargetRole: .invalidTargetRole
        case .inactiveTarget: .inactiveTarget
        case .sourceAccessRequired: .sourceAccessRequired
        case .missingWorkflow: .methodMissing
        case .invalidWorkflow: .methodInvalid
        case .malformedBinding: .profileInvalid
        case .citationStyleUnavailable: .unsupportedCapability
        }
        return ResearchActionRepairReason(
            code: code,
            sourceAccessFailure: reason.sourceAccessFailure
        )
    }

    private static func unique(
        _ reasons: [ResearchActionRepairReason]
    ) -> [ResearchActionRepairReason] {
        var seen: Set<ResearchActionRepairReason> = []
        return reasons.filter { seen.insert($0).inserted }
    }

}

private extension ResearchActionRunState {
    init(_ state: ResearchFunctionRunState) {
        switch state {
        case .prepared: self = .prepared
        case .awaitingFidelity: self = .awaitingFidelity
        case .complete: self = .complete
        case .unverified: self = .unverified
        case .stale: self = .stale
        case .cancelled: self = .cancelled
        }
    }
}

extension ResearchFunctionTarget {
    var actionNote: ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note,
            role: role.actionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

extension ResearchFunctionMaterial {
    var actionNote: ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note,
            role: role.actionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

private extension ResearchActionNoteSnapshot {
    var functionTarget: ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: noteID,
            note: note,
            role: role.functionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }

    var functionMaterial: ResearchFunctionMaterial {
        ResearchFunctionMaterial(
            noteID: noteID,
            note: note,
            role: role.functionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

private extension ResearchFunctionTargetRole {
    var actionRole: ResearchActionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}

private extension ResearchActionTargetRole {
    var functionRole: ResearchFunctionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}
