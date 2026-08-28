import Foundation
import ScholiumContracts
import ScholiumCore

// Availability plus the cross-store preparation and rollback transaction for
// the one per-Workspace Research Action Run coordinator.

struct ResolvedActionRunPhase: Sendable {
    let actionID: ResearchActionID
    let method: ResearchMethodSnapshot
    let citationStyle: String?
}

struct ResearchActionRunAuthorityBinding: Encodable {
    let noteID: String
    let note: VaultQualifiedNoteID
    let role: ResearchActionTargetRole
    let fingerprint: DocumentFingerprint?

    init(_ noteSnapshot: ResearchActionNoteSnapshot, includesFingerprint: Bool) {
        noteID = noteSnapshot.noteID.uuidString.lowercased()
        note = noteSnapshot.note
        role = noteSnapshot.role
        fingerprint = includesFingerprint ? noteSnapshot.fingerprint : nil
    }
}

struct ResearchActionRunTaskDirective: Encodable {
    let action: ResearchActionID
    let academicInputs: ResearchAcademicFieldValues
    let resultContract: ResearchResultContract
    let triptychID: String
    let runID: String
    let confirmationToken: String
    let scope: ResearchActionScopeKind
    let researcherInstruction: String
    let sourceReference: ResearchSourceReference?
    let readSet: [ResearchActionRunAuthorityBinding]
    let writeSet: [ResearchActionRunAuthorityBinding]
    let checks: [FidelityCheck]
    let method: ResearchActionRunMethodAuthorityBinding
}

struct ResearchActionRunMethodAuthorityBinding: Encodable {
    let registrationKey: String
    let action: ResearchActionID
    let primaryMarkdownRevision: DocumentFingerprint
    let skillFolderPath: String?

    init(_ method: ResearchMethodSnapshot) {
        registrationKey = method.registration.key.description
        action = method.registration.actionID
        primaryMarkdownRevision = method.primaryMarkdownRevision
        skillFolderPath = method.skillFolderPath
    }
}

struct ResearchActionRunNamedData: Encodable {
    let noteID: String
    let title: String
}

struct ResearchActionRunSourceLocator: Encodable {
    let machineLocalPath: String
}

struct ResearchActionRunResearchData: Encodable {
    let target: ResearchActionRunNamedData
    let source: ResearchSourceReference?
    let materials: [ResearchActionRunNamedData]
    let fidelityTargets: [ResearchActionRunNamedData]
    let passage: CommentAnchor?
}

extension ResearchActionRunCoordinator {
    // MARK: Availability and Materials

    func researchActionRunAvailability<Host: ResearchActionRunCoordinatorHost>(
        for target: ResearchActionNoteSnapshot,
        checkingSourceAccess: Bool = true,
        host: isolated Host
    ) async throws -> [ResearchActionRunAvailability] {
        try requireMatchingActiveHost(host)
        let targetReason = await researchActionTargetRepairReason(
            target,
            host: host
        )
        var results: [ResearchActionRunAvailability] = []
        for actionID in ResearchActionID.allCases {
            var reasons: [ResearchActionRunRepairReason] = []
            if let targetReason {
                reasons.append(targetReason)
            } else if !actionID.allowedTargetRoles.contains(target.role) {
                reasons.append(ResearchActionRunRepairReason(
                    code: .invalidTargetRole,
                    actionID: actionID,
                    expectedRoles: Array(actionID.allowedTargetRoles)
                ))
            }

            if reasons.isEmpty {
                if checkingSourceAccess,
                   actionID == .analyze,
                   target.role == .analysis {
                    let usesExternalZotero = try await hasExternalZoteroBinding(
                        for: target,
                        host: host
                    )
                    if !usesExternalZotero {
                        let sourceStatus = try await researchSourceAccessStatus(
                            for: target,
                            host: host
                        )
                        if let failure = sourceStatus.failure {
                            reasons.append(ResearchActionRunRepairReason(
                                code: .sourceAccessRequired,
                                actionID: actionID,
                                sourceAccessFailure: failure
                            ))
                        }
                    }
                }
            }

            if reasons.isEmpty {
                let action = actionID.definition
                try action.validate(targetRole: target.role)
                do {
                    let method = try await dependencies.researchConfigurationStore
                        .methodSnapshot(for: action.id)
                    if !method.registration.isEnabled {
                        reasons.append(ResearchActionRunRepairReason(
                            code: .missingWorkflow,
                            actionID: actionID
                        ))
                    }
                } catch {
                    reasons.append(ResearchActionRunRepairReason(
                        code: .missingWorkflow,
                        actionID: actionID
                    ))
                }
            }

            var fidelityChecks: [ResearchActionRunCheckAvailability] = []
            if actionID == .checkFidelity, reasons.isEmpty {
                fidelityChecks.append(ResearchActionRunCheckAvailability(
                    check: .content,
                    isEnabled: true
                ))
                let citation = try await dependencies.researchConfigurationStore
                    .citationMethodSnapshot()
                if citation?.document.activeCitationStyle == nil {
                    fidelityChecks.append(ResearchActionRunCheckAvailability(
                        check: .citations,
                        isEnabled: false,
                        repairReasons: [ResearchActionRunRepairReason(
                            code: .citationStyleUnavailable,
                            actionID: .checkFidelity
                        )]
                    ))
                } else {
                    fidelityChecks.append(ResearchActionRunCheckAvailability(
                        check: .citations,
                        isEnabled: true
                    ))
                }
            }
            results.append(ResearchActionRunAvailability(
                actionID: actionID,
                isEnabled: reasons.isEmpty,
                repairReasons: reasons,
                fidelityChecks: fidelityChecks
            ))
        }
        return results
    }

    func researchActionMaterialCandidates<Host: ResearchActionRunCoordinatorHost>(
        for target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID,
        host: isolated Host
    ) async throws -> [ResearchActionMaterialCandidate] {
        try requireMatchingActiveHost(host)
        _ = try await validateResearchActionTarget(
            target,
            expected: target.fingerprint,
            host: host
        )
        guard actionID.allowedTargetRoles.contains(target.role) else {
            throw ResearchActionRunContractError.invalidTargetRole(
                actionID: actionID,
                role: target.role
            )
        }

        let currentSnapshot = host.researchActionCurrentSnapshot()
        let catalogByLocation = Dictionary(uniqueKeysWithValues:
            currentSnapshot.discovery.catalog.notes.map { note in
                (
                    VaultQualifiedNoteID(
                        vaultID: note.reference.vaultID,
                        relativePath: note.reference.relativePath
                    ),
                    note
                )
            }
        )
        var suggestionsByLocation: [
            VaultQualifiedNoteID: Set<ResearchActionMaterialSuggestionReason>
        ] = [:]
        if let graph = currentSnapshot.discovery.catalog.graph {
            for edge in graph.outgoing[target.note, default: []] {
                guard let destination = edge.destination?.note,
                      destination != target.note else { continue }
                suggestionsByLocation[destination, default: []].insert(
                    ResearchActionMaterialSuggestionReason(
                        kind: .linkedFromTarget,
                        sourceNote: target.note,
                        sourceSpan: edge.occurrence.span
                    )
                )
            }
            for edge in graph.incoming[target.note, default: []] {
                guard edge.source != target.note else { continue }
                suggestionsByLocation[edge.source, default: []].insert(
                    ResearchActionMaterialSuggestionReason(
                        kind: .linksDirectlyToTarget,
                        sourceNote: edge.source,
                        sourceSpan: edge.occurrence.span
                    )
                )
            }
        }

        return currentSnapshot.vaults.flatMap(\.documents).compactMap { note in
            guard note.id != target.note,
                  !note.capabilities.isManagedCritique,
                  case .resolved(let noteID) = note.stableIdentity,
                  let role = ResearchActionTargetRole(vaultRole: note.vaultRole),
                  let vault = currentSnapshot.vault(id: note.id.vaultID)?.vault else {
                return nil
            }
            let title = researchActionTitle(for: note)
            let material = ResearchActionNoteSnapshot(
                noteID: noteID,
                note: note.id,
                role: role,
                fingerprint: note.fingerprint,
                title: title
            )
            _ = vault // Keeps candidate creation explicitly vault-bound.
            return ResearchActionMaterialCandidate(
                material: material,
                aliases: catalogByLocation[note.id]?.aliases ?? [],
                suggestionReasons: Array(suggestionsByLocation[note.id] ?? [])
            )
        }.sorted { lhs, rhs in
            if lhs.material.role != rhs.material.role {
                return lhs.material.role.rawValue < rhs.material.role.rawValue
            }
            let titleOrder = lhs.material.title.localizedStandardCompare(
                rhs.material.title
            )
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.material.note.relativePath.localizedStandardCompare(
                rhs.material.note.relativePath
            ) == .orderedAscending
        }
    }

    // MARK: Preparation

    func prepareResearchActionRun<Host: ResearchActionRunCoordinatorHost>(
        _ request: ResearchActionRunRequest,
        host: isolated Host
    ) async throws -> ResearchActionRunPreparation {
        try await prepareResearchActionRun(
            request,
            allowsResearcherProvidedSource: false,
            host: host
        )
    }

    func researchActionRun<Host: ResearchActionRunCoordinatorHost>(
        id: UUID,
        host: isolated Host
    ) async throws -> ResearchActionRunPreparation {
        try requireMatchingActiveHost(host)
        let record = try await record(runID: id)
        if record.snapshot.request.actionID == .discuss {
            _ = try await validatedDiscussionStatements(snapshot: record.snapshot)
        }
        return ResearchActionRunPreparation(
            snapshot: record.snapshot,
            instructions: try await deliveryInstructions(for: record, host: host),
            state: record.completion?.state ?? .prepared,
            reusedCompletion: record.completion
        )
    }

    func prepareResearchActionRun<Host: ResearchActionRunCoordinatorHost>(
        _ proposedRequest: ResearchActionRunRequest,
        allowsResearcherProvidedSource: Bool = false,
        host: isolated Host
    ) async throws -> ResearchActionRunPreparation {
        let actionContext = try await host.resolveDefaultResearchActionContext(
            for: proposedRequest
        )
        return try await prepareResearchActionRun(
            proposedRequest,
            actionContext: actionContext,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource,
            host: host
        )
    }

    func prepareResearchActionRun<Host: ResearchActionRunCoordinatorHost>(
        _ proposedRequest: ResearchActionRunRequest,
        actionContext: ResolvedResearchActionContext,
        runIDOverride: UUID? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        continuationHandoff: ResearchContinuationHandoffContext? = nil,
        resynthesisContext: SynthesisMaterialChangedAttentionContext? = nil,
        requiresAgentChangeEvidence: Bool = true,
        allowsResearcherProvidedSource: Bool = false,
        expectedZoteroBinding: AnalysisZoteroBinding? = nil,
        suppressRefresh: Bool = false,
        host: isolated Host
    ) async throws -> ResearchActionRunPreparation {
        try requireMatchingActiveHost(host)
        guard (continuationLineage?.kind == .resynthesis)
                == (resynthesisContext != nil) else {
            throw ResearchActionRunContractError.invalidCompletion(
                "A Resynthesize child requires its exact revision-bound context."
            )
        }
        guard (continuationLineage?.kind == .continueResearch)
                == (continuationHandoff != nil),
              continuationHandoff?.parentRecordID
                == continuationLineage?.parentRunID
                || continuationHandoff == nil else {
            throw ResearchContinuationContractError.invalidHandoff
        }
        guard actionContext.actionID == proposedRequest.actionID,
              actionContext.availability.definition.id
                == actionContext.availability.profile.profile.actionID else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let expandedRequest = proposedRequest
        try expandedRequest.validate()
        let target = try await validateResearchActionTarget(
            expandedRequest.target,
            expected: expandedRequest.target.fingerprint,
            host: host
        )
        _ = try await validateResearchActionMaterials(
            expandedRequest.materials,
            host: host
        )
        let request = expandedRequest
        try request.validate()
        guard expectedZoteroBinding == nil
                || (!allowsResearcherProvidedSource
                    && request.actionID == .analyze
                    && request.target.role == .analysis
                    && expectedZoteroBinding?.noteID == request.target.noteID)
        else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
        if let expectedZoteroBinding,
           try await portableTargetZoteroBinding(target) != expectedZoteroBinding {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
        let sourceAccess = try await requiredResearchSourceAccess(
            for: target,
            actionID: request.actionID,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource
        )
        let zoteroContext = allowsResearcherProvidedSource
            ? nil
            : try await zoteroBibliographicContext(
                for: target,
                expectedBinding: expectedZoteroBinding
            )
        _ = try await validateResearchActionWriteTargets(request, host: host)
        _ = try await validateResearchActionFidelityTargets(request, host: host)
        let actionAuthority = try resolvedActionAuthority(
            context: actionContext,
            request: request
        )
        let phases = try await resolveResearchActionRunPhases(
            request,
            actionContext: actionContext,
            includeZoteroIntegration: zoteroContext != nil
                || sourceAccess?.reference.identity.route == .zoteroAttachment
        )
        let actionSnapshot = try resolvedActionSnapshot(
            context: actionContext,
            authority: actionAuthority,
            target: request.target
        )

        let commentOnlyDiscussion: PortableResearchDiscussion?
        if request.actionID == .discuss {
            let active = try await dependencies.portableResearchRecordStore.activeDiscussions(
                noteID: request.target.noteID
            )
            guard active.issues.isEmpty else {
                throw ScholiumApplicationError.researchStoreUnavailable(
                    active.issues.map(\.reason).joined(separator: "\n")
                )
            }
            if let existing = active.discussions.first(where: {
                $0.primaryNoteID == request.target.noteID
            }) {
                guard existing.action == nil, existing.method == nil else {
                    throw ResearchActionRunContractError.activeDiscussionExists(existing.id)
                }
                commentOnlyDiscussion = existing
            } else {
                commentOnlyDiscussion = nil
            }
        } else {
            commentOnlyDiscussion = nil
        }

        let runID = runIDOverride ?? commentOnlyDiscussion?.id ?? UUID()
        let activeRunIDs = try await dependencies.localExecutionStore
            .activeExecutionIDs(containing: [request.target.noteID])
        for activeRunID in activeRunIDs where activeRunID != runID {
            guard let active = try await dependencies.localExecutionStore
                .recordIfPresent(id: activeRunID),
                  active.snapshot.request.target.noteID == request.target.noteID,
                  active.completion == nil else { continue }
            let hasCommittedWrite = active.documentWriteRecords.contains {
                $0.state == .committed
            } || active.zoteroBindingWriteRecords.contains {
                $0.state == .committed
            }
            guard hasCommittedWrite else { continue }
            throw ResearchActionRunContractError.activeResultRequired
        }
        // Every existing Note that a Run may change receives one exact,
        // Run-bound starting revision before Agent access. This is direct
        // change evidence, not a general version history.
        let capturedChangeEvidence: Bool
        if requiresAgentChangeEvidence,
           request.actionID.requiresAgentChangeEvidence {
            _ = try await captureAgentChangeStartingRevision(
                runID: runID,
                target: request.target
            )
            capturedChangeEvidence = true
        } else {
            capturedChangeEvidence = false
        }

        do {
            _ = try await validateResearchActionTarget(
                request.target,
                expected: request.target.fingerprint,
                host: host
            )
            _ = try await validateResearchActionMaterials(
                request.materials,
                host: host
            )
            _ = try await validateResearchActionWriteTargets(request, host: host)
            _ = try await validateResearchActionFidelityTargets(request, host: host)
            let revalidatedSource = try await requiredResearchSourceAccess(
                for: target,
                actionID: request.actionID,
                allowsResearcherProvidedSource: allowsResearcherProvidedSource
            )
            guard revalidatedSource?.reference == sourceAccess?.reference else {
                throw ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .sourceChanged)
                )
            }
            if let expectedZoteroBinding,
               try await portableTargetZoteroBinding(target) != expectedZoteroBinding {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
        } catch {
            if capturedChangeEvidence {
                try? await dependencies.agentChangeEvidenceStore.discard(
                    runID: runID,
                    noteID: request.target.noteID
                )
            }
            throw error
        }

        let confirmationToken = UUID()
        let preparedAt = researchActionRunRecordTimestamp()
        let snapshot = try ResearchActionRunSnapshot(
            runID: runID,
            request: request,
            actionSnapshot: actionSnapshot,
            recordID: runID,
            zoteroBibliographicContext: zoteroContext,
            sourceReference: sourceAccess?.reference,
            analysisSourceRoute: request.actionID == .analyze
                ? (allowsResearcherProvidedSource
                    ? .researcherProvided
                    : (sourceAccess != nil ? .scholiumSource : .externalZotero))
                : nil,
            citationStyle: phases.first?.citationStyle,
            continuationLineage: continuationLineage,
            continuationHandoff: continuationHandoff,
            resynthesisContext: resynthesisContext,
            confirmationToken: confirmationToken,
            preparedAt: preparedAt
        )

        if request.actionID == .checkFidelity {
            let key = ResearchFidelityEvidenceKey(
                snapshot: snapshot,
                finalTargetFingerprint: request.target.fingerprint,
                finalMaterialFingerprints: Dictionary(
                    uniqueKeysWithValues: request.materials.map { ($0.noteID, $0.fingerprint) }
                ),
                checks: request.checks
            )
            if let reused = try await completedFidelityEvidence(
                for: key,
                excluding: nil
            ) {
                return ResearchActionRunPreparation(
                    snapshot: snapshot,
                    instructions: "Existing Fidelity evidence matches this exact revision, scope, evidence, checks, and method resources.",
                    state: .complete,
                    reusedCompletion: reused
                )
            }
        }

        let actionRunInstructions = try renderActionRunInstructions(
            request: request,
            action: actionContext.availability.definition,
            academicInputs: actionContext.academicInputs,
            resultContract: actionContext.resultContract,
            phases: phases,
            runID: runID,
            confirmationToken: confirmationToken,
            zoteroContext: zoteroContext,
            sourceAccess: sourceAccess,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource
        )
        let liveInstructions = try sourceAccessDeliveryInstructions(
            base: actionRunInstructions,
            sourceAccess: sourceAccess
        )
        let deliveryInstructions = liveInstructions
        do {
            // Close the race opened by method loading and evidence capture.
            _ = try await validateResearchActionTarget(
                request.target,
                expected: request.target.fingerprint,
                host: host
            )
            _ = try await validateResearchActionMaterials(
                request.materials,
                host: host
            )
            let finalSource = try await requiredResearchSourceAccess(
                for: target,
                actionID: request.actionID,
                allowsResearcherProvidedSource: allowsResearcherProvidedSource
            )
            guard finalSource?.reference == sourceAccess?.reference else {
                throw ResearchActionRunContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .sourceChanged)
                )
            }
            if let expectedZoteroBinding,
               try await portableTargetZoteroBinding(target) != expectedZoteroBinding {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            let localDiscussion = request.actionID == .discuss
                    ? try localDiscussionExecution(
                        snapshot: snapshot,
                        request: request
                    )
                    : nil
            _ = try await dependencies.localExecutionStore.create(
                    LocalResearchExecutionRecord(
                        triptychID: workspaceID,
                        snapshot: snapshot,
                        preparedInstructions: actionRunInstructions,
                        discussion: localDiscussion
                    )
                )
            if request.actionID == .discuss {
                    let resolved = try ResearchDiscussionFactory.make(
                        snapshot: snapshot,
                        triptychID: workspaceID
                    )
                    if commentOnlyDiscussion != nil {
                        guard let action = resolved.action,
                              let method = resolved.method,
                              let statement = resolved.statements.first else {
                            throw ResearchActionRunContractError.invalidCompletion(
                                "A Comment-only Discussion requires an exact resolved activation."
                            )
                        }
                        _ = try await dependencies.portableResearchRecordStore.activateDiscussion(
                            id: runID,
                            action: action,
                            method: method,
                            participatingNotes: resolved.participatingNotes,
                            statement: statement,
                            at: snapshot.preparedAt
                        )
                    } else {
                        _ = try await dependencies.portableResearchRecordStore
                            .createActiveDiscussion(resolved)
                    }
            }
        } catch {
            if capturedChangeEvidence {
                try? await dependencies.agentChangeEvidenceStore.discard(
                    runID: runID,
                    noteID: request.target.noteID
                )
            }
            try? await dependencies.localExecutionStore.discardUncompleted(
                runID: runID
            )
            throw error
        }
        let refreshWarning: String?
        if suppressRefresh {
            refreshWarning = nil
            host.scheduleResearchActionRefreshRecovery()
        } else {
            refreshWarning = try await host.publishCommittedResearchActionChange(
                "The Research Action preparation"
            )
        }
        var returnedInstructions = deliveryInstructions
        if request.actionID == .discuss {
            guard let responseContract = try await dependencies.localExecutionStore
                .record(id: runID).discussion?.responseContract else {
                throw ResearchActionRunContractError.preparationNotFound(runID)
            }
            let discussionInstructions = actionRunInstructions + "\n\n" + DiscussResponseTransport.locator(
                discussionID: runID,
                triptychID: workspaceID,
                contract: responseContract
            )
            returnedInstructions = discussionInstructions
        }
        return ResearchActionRunPreparation(
            snapshot: snapshot,
            instructions: returnedInstructions,
            derivedRefreshWarning: refreshWarning
        )
    }

    private func localDiscussionExecution(
        snapshot: ResearchActionRunSnapshot,
        request: ResearchActionRunRequest
    ) throws -> ResearchDiscussionExecutionContract {
        let storedProfile = DialogueResponseProfile()
        let effectiveProfile: DialogueResponseProfile
        if let modules = request.dialogueResponseModules {
            effectiveProfile = storedProfile.updated(modules: modules.map(\.rawValue))
        } else {
            effectiveProfile = storedProfile
        }
        guard effectiveProfile.validationIssues.isEmpty else {
            throw ResearchOperationError.invalidDialogueResponseContract(
                effectiveProfile.validationIssues
            )
        }
        let responseContract = DialogueResponseContract(profile: effectiveProfile)
        return try ResearchDiscussionExecutionContract(
            id: snapshot.runID,
            responseContract: responseContract
        )
    }



}
