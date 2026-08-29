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
    let actionID: ResearchActionID
    let method: ResearchMethodSnapshot
    let platformInputs: ResearchActionPlatformInputs
    let academicInputs: ResearchAcademicFieldValues
    let resultContract: ResearchResultContract
    let authority: ResearchAuthorityEnvelope
}

private struct ResolvedResearchActionCandidate: Sendable {
    let availability: ResearchActionAvailability
    let actionID: ResearchActionID
    let method: ResearchMethodSnapshot?
}

extension WorkspaceHandle {
    func researchActionAvailability(
        for target: ResearchActionNoteSnapshot,
        checkingSourceAccess: Bool = true
    ) async throws -> [ResearchActionAvailability] {
        try requireCompleteWorkspace()
        let actionTarget = target
        return try await resolvedResearchActions(
            for: actionTarget,
            checkingSourceAccess: checkingSourceAccess
        )
            .map(\.availability)
    }

    func prepareResearchAction(
        _ request: ResearchActionExecutionRequest,
        allowsResearcherProvidedSource: Bool = false,
        expectedZoteroBinding: AnalysisZoteroBinding? = nil,
        runIDOverride: UUID? = nil
    ) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        let resolved = try await resolvedResearchActionExecution(request)
        let prepared = try await researchActionRunCoordinator.prepareResearchActionRun(
            resolved.request,
            actionContext: resolved.context,
            runIDOverride: runIDOverride,
            requiresAgentChangeEvidence:
                !resolved.context.authority.writableNotes.isEmpty,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource,
            expectedZoteroBinding: expectedZoteroBinding,
            host: self
        )
        let functionPreparation = try researchActionRunCoordinator.attachingAgentActions(
            to: prepared
        )
        let snapshot = functionPreparation.snapshot.actionSnapshot
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: functionPreparation.runID,
            instructions: functionPreparation.instructions,
            state: functionPreparation.state,
            derivedRefreshWarning: functionPreparation.derivedRefreshWarning,
            nextActions: functionPreparation.nextActions ?? []
        )
    }

    func researchFollowUpContext(
        recordID: UUID,
        expectedFinalizedResultFingerprint: DocumentFingerprint
    ) async throws -> ResearchFollowUpContext {
        try requireCompleteWorkspace()
        let record: PortableResearchRecord
        do {
            record = try await researchActionResolverDependencies
                .portableResearchRecordStore.record(id: recordID)
        } catch {
            throw ResearchFollowUpError.parentUnavailable
        }
        guard record.triptychID == id,
              record.kind == .action,
              let targetNoteID = record.primaryNoteID else {
            throw ResearchFollowUpError.parentUnavailable
        }
        guard try record.finalizedResultFingerprint()
                == expectedFinalizedResultFingerprint else {
            throw ResearchFollowUpError.parentResultChanged
        }
        guard let note = currentSnapshot.vaults.lazy.flatMap(\.documents)
            .first(where: { $0.stableIdentity.resolvedID == targetNoteID }),
              let role = ResearchActionTargetRole(vaultRole: note.vaultRole) else {
            throw ResearchFollowUpError.targetUnavailable
        }
        return ResearchFollowUpContext(
            parentRecordID: record.id,
            expectedFinalizedResultFingerprint: expectedFinalizedResultFingerprint,
            target: ResearchActionNoteSnapshot(
                noteID: targetNoteID,
                note: note.id,
                role: role,
                fingerprint: note.fingerprint,
                title: researchActionRunCoordinator.researchActionTitle(for: note)
            ),
            methodFeedbackText: record.methodFeedbackComment?.text,
            methodFeedbackRevision: record.methodFeedbackComment?.revision
        )
    }

    func prepareResearchFollowUp(
        _ request: ResearchFollowUpRequest
    ) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        let parent = try await researchFollowUpContext(
            recordID: request.parentRecordID,
            expectedFinalizedResultFingerprint:
                request.expectedFinalizedResultFingerprint
        )
        guard request.action.target.noteID == parent.target.noteID else {
            throw ResearchFollowUpError.targetUnavailable
        }

        let feedbackDraft = try request.methodFeedbackText.map(
            ResearchMethodFeedbackDraft.init(text:)
        )
        _ = try await saveMethodFeedback(
            recordID: request.parentRecordID,
            draft: feedbackDraft,
            expectedMethodFeedbackRevision:
                request.expectedMethodFeedbackRevision,
            expectedResultFingerprint:
                request.expectedFinalizedResultFingerprint
        )

        // Resolve after the researcher confirms Follow-up. No Method, Profile,
        // note revision, material, permission, or write grant from the parent
        // Run crosses this boundary.
        let resolved = try await resolvedResearchActionExecution(request.action)
        let currentParent = try await researchActionResolverDependencies
            .portableResearchRecordStore.record(id: request.parentRecordID)
        guard try currentParent.finalizedResultFingerprint()
                == request.expectedFinalizedResultFingerprint else {
            throw ResearchFollowUpError.parentResultChanged
        }

        let researchRequest: String
        guard case .freeText(let value)? = request.action.academicInputs.values[
            "research-request"
        ] else {
            throw ResearchContinuationContractError.invalidRequest
        }
        researchRequest = value
        let epistemicStatus: ResearchContinuationEpistemicStatus = switch request.statement.kind {
        case .finding: .researcherFinding
        case .question: .unresolvedQuestion
        case .hypothesis: .hypothesisToVerify
        }
        let handoffItem = try ResearchContinuationHandoffItem(
            content: request.statement.text,
            epistemicStatus: epistemicStatus,
            nextUse: researchRequest
        )
        let handoff = try ResearchContinuationHandoffContext(
            parentRecordID: currentParent.id,
            initiator: .researcher,
            academicPurpose: researchRequest,
            handoff: [handoffItem],
            referenceChecks: [],
            requiresResearcherStateRequery: true
        )
        let runID = UUID()
        let lineage = ResearchContinuationLineage(
            groupID: currentParent.continuationLineage?.groupID
                ?? currentParent.id,
            parentRunID: currentParent.id,
            requestID: runID,
            kind: .followUp
        )
        let prepared = try await researchActionRunCoordinator
            .prepareResearchActionRun(
                resolved.request,
                actionContext: resolved.context,
                runIDOverride: runID,
                continuationLineage: lineage,
                continuationHandoff: handoff,
                requiresAgentChangeEvidence:
                    !resolved.context.authority.writableNotes.isEmpty,
                host: self
            )
        return try await publicActionPreparation(from: prepared)
    }

    func researchActionMaterialCandidates(
        for target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID
    ) async throws -> [ResearchActionNoteSnapshot] {
        try requireCompleteWorkspace()
        let candidates = try await resolvedResearchActions(
            for: target,
            checkingSourceAccess: false
        )
        guard let candidate = candidates.first(where: {
            $0.availability.id == actionID && $0.availability.isEnabled
        }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return try await researchActionRunCoordinator.researchActionMaterialCandidates(
            for: target,
            actionID: candidate.actionID,
            host: self
        ).map { $0.material }
    }

    func researchActionRun(id: UUID) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        return try await publicActionPreparation(
            from: researchActionRunCoordinator.researchActionRun(
                id: id,
                host: self
            )
        )
    }

    func prepareResearchResynthesis(
        _ request: ResearchActionExecutionRequest,
        context: SynthesisMaterialChangedAttentionContext
    ) async throws -> ResearchActionPreparation {
        try requireCompleteWorkspace()
        guard request.actionID == .synthesize,
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
              record.participatingNotes.contains(where: {
                  $0.noteID == context.materialNoteID
                      && $0.role == .analysis
                      && $0.startingRevision == context.recordedRevision
              }) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let recordListing = try await researchActionResolverDependencies
            .portableResearchRecordStore.listing()
        guard WorkspaceSnapshotBuilder.isLatestSynthesisMaterial(
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
        let prepared = try await researchActionRunCoordinator.prepareResearchActionRun(
            resolved.request,
            actionContext: resolved.context,
            runIDOverride: runID,
            continuationLineage: lineage,
            resynthesisContext: context,
            requiresAgentChangeEvidence: true,
            host: self
        )
        let functionPreparation = try researchActionRunCoordinator.attachingAgentActions(
            to: prepared
        )
        let snapshot = functionPreparation.snapshot.actionSnapshot
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: functionPreparation.runID,
            instructions: functionPreparation.instructions,
            state: functionPreparation.state,
            derivedRefreshWarning: functionPreparation.derivedRefreshWarning,
            nextActions: functionPreparation.nextActions ?? []
        )
    }

    private func publicActionPreparation(
        from preparation: ResearchActionRunPreparation
    ) async throws -> ResearchActionPreparation {
        let snapshot = preparation.snapshot.actionSnapshot
        let attached = try researchActionRunCoordinator.attachingAgentActions(
            to: preparation
        )
        return ResearchActionPreparation(
            snapshot: snapshot,
            runID: attached.runID,
            instructions: attached.instructions,
            state: attached.state,
            derivedRefreshWarning: attached.derivedRefreshWarning,
            nextActions: attached.nextActions ?? []
        )
    }

    func resolvedResearchActionExecution(
        _ request: ResearchActionExecutionRequest
    ) async throws -> (
        request: ResearchActionRunRequest,
        context: ResolvedResearchActionContext
    ) {
        try requireActive()
        let target = request.target
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
        guard candidate.availability.profile.profileRevision
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
            target: target
        )
        let prepared = try makeActionRunRequest(
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
            actionID: candidate.actionID,
            method: method,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: resultContract,
            authority: prepared.authority
        )
        return (prepared.request, context)
    }

    func resolvedDefaultActionContext(
        for request: ResearchActionRunRequest
    ) async throws -> ResolvedResearchActionContext {
        try request.validate()
        let definition = request.actionID.definition
        try definition.validate(targetRole: request.target.role)
        guard let profileSnapshot = try await researchActionResolverDependencies
            .researchConfigurationStore
            .profileSnapshot(),
              let profile = profileSnapshot.document.profile(for: definition.id),
              profile.isEnabled,
              profile.applicableRoles.contains(request.target.role),
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
            focalNotes: request.materials,
            passage: request.scope?.selection,
            fidelityChecks: request.checks
        ).validated(
            for: platform,
            target: request.target
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
            target: request.target,
            additionalReads: request.materials,
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
            actionID: request.actionID,
            method: method,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: resultContract,
            authority: authority
        )
    }

    private func resolvedResearchActions(
        for target: ResearchActionNoteSnapshot,
        checkingSourceAccess: Bool
    ) async throws -> [ResolvedResearchActionCandidate] {
        let runAvailability = Dictionary(uniqueKeysWithValues:
            try await researchActionRunCoordinator.researchActionRunAvailability(
                for: target,
                checkingSourceAccess: checkingSourceAccess,
                host: self
            ).map {
                ($0.actionID, $0)
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
            profile.applicableRoles.contains(target.role)
        {
            guard let platform = PlatformActionCatalog.definition(for: profile.actionID) else {
                continue
            }
            let definition = profile.actionID.definition
            try definition.validate(targetRole: target.role)
            let actionID = definition.id
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
            let runState = runAvailability[actionID]
            var reasons = (runState?.repairReasons ?? []).map(
                Self.actionRepairReason
            )
            reasons += await baseActionRepairReasons(
                target: target,
                actionID: actionID,
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
                        && runState?.isEnabled == true
                        && reasons.isEmpty
                        && method != nil,
                    repairReasons: Self.unique(reasons)
                ),
                actionID: actionID,
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
        target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID,
        profile: ResearchAcademicActionProfile
    ) async -> [ResearchActionRepairReason] {
        var reasons: [ResearchActionRepairReason] = []
        if let reason = await researchActionRunCoordinator
            .researchActionTargetRepairReason(target, host: self) {
            reasons.append(Self.actionRepairReason(reason))
        }
        if !actionID.allowedTargetRoles.contains(target.role)
            || !profile.applicableRoles.contains(target.role) {
            reasons.append(ResearchActionRepairReason(code: .invalidTargetRole))
        }
        return Self.unique(reasons)
    }

    private func makeActionRunRequest(
        definition: ResearchActionDefinition,
        target: ResearchActionNoteSnapshot,
        platform: PlatformActionDefinition,
        platformInputs: ResearchActionPlatformInputs,
        academicInputs: ResearchAcademicFieldValues
    ) throws -> (request: ResearchActionRunRequest, authority: ResearchAuthorityEnvelope) {
        try definition.validate(targetRole: target.role)
        let actionID = definition.id
        var seen: Set<UUID> = []
        let additionalReads = platformInputs.focalNotes.filter {
            $0.noteID != target.noteID && seen.insert($0.noteID).inserted
        }
        let materials = additionalReads
        let authority = try Self.authority(
            target: target,
            additionalReads: additionalReads,
            platform: platform
        )
        let instruction: String? = if case .freeText(let text)? =
            academicInputs.values["research-request"] { text } else { nil }
        let request = ResearchActionRunRequest(
            actionID: actionID,
            target: target,
            materials: materials,
            instruction: actionID == .discuss
                ? (instruction ?? "Discuss the current Target using the declared Action parameters.")
                : instruction,
            scope: platformInputs.passage.map(ResearchActionScope.passage),
            checks: actionID == .checkFidelity
                ? (platformInputs.fidelityChecks.isEmpty
                    ? [.content]
                    : Set(platformInputs.fidelityChecks))
                : [],
            dialogueResponseModules: actionID == .discuss ? [] : nil
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
            editableMetadataKeys: []
        )
    }

    private static func actionRepairReason(
        _ reason: ResearchActionRunRepairReason
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
