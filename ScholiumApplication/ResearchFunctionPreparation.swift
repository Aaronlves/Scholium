import Foundation
import ScholiumContracts
import ScholiumCore

// Availability plus the cross-store preparation and rollback transaction for
// the one per-Workspace Research Function coordinator.

struct ResolvedFunctionPhase: Sendable {
    let function: ResearchFunctionID
    let method: ResearchMethodSnapshot
    let citationStyle: String?
}

struct ResearchFunctionAuthorityBinding: Encodable {
    let noteID: String
    let note: VaultQualifiedNoteID
    let role: ResearchFunctionTargetRole
    let lifecycle: WorkspaceDocumentLifecycle
    let fingerprint: DocumentFingerprint?

    init(_ target: ResearchFunctionTarget, includesFingerprint: Bool) {
        noteID = target.noteID.uuidString.lowercased()
        note = target.note
        role = target.role
        lifecycle = target.lifecycle
        fingerprint = includesFingerprint ? target.fingerprint : nil
    }

    init(_ material: ResearchFunctionMaterial, includesFingerprint: Bool) {
        noteID = material.noteID.uuidString.lowercased()
        note = material.note
        role = material.role
        lifecycle = material.lifecycle
        fingerprint = includesFingerprint ? material.fingerprint : nil
    }
}

struct ResearchFunctionTaskDirective: Encodable {
    let action: ResearchActionID
    let academicInputs: ResearchAcademicFieldValues
    let resultContract: ResearchResultContract
    let triptychID: String
    let runID: String
    let confirmationToken: String
    let scope: ResearchFunctionScopeKind
    let researcherInstruction: String
    let sourceReference: ResearchSourceReference?
    let readSet: [ResearchFunctionAuthorityBinding]
    let writeSet: [ResearchFunctionAuthorityBinding]
    let checks: [FidelityCheck]
    let method: ResearchFunctionMethodAuthorityBinding
}

struct ResearchFunctionMethodAuthorityBinding: Encodable {
    let registrationKey: String
    let action: ResearchActionID
    let primaryMarkdownRevision: DocumentFingerprint
    let practices: [ResearchFunctionPracticeAuthorityBinding]
    let skillFolderPath: String?

    init(_ method: ResearchMethodSnapshot) {
        registrationKey = method.registration.key.description
        action = method.registration.actionID
        primaryMarkdownRevision = method.primaryMarkdownRevision
        practices = method.practices.map(ResearchFunctionPracticeAuthorityBinding.init)
        skillFolderPath = method.skillFolderPath
    }
}

struct ResearchFunctionPracticeAuthorityBinding: Encodable {
    let title: String
    let relativePath: String
    let revision: DocumentFingerprint

    init(_ practice: ResearchPracticeSnapshot) {
        title = practice.title
        relativePath = practice.relativePath
        revision = practice.revision
    }
}

struct ResearchFunctionNamedData: Encodable {
    let noteID: String
    let title: String
}

struct ResearchFunctionSourceLocator: Encodable {
    let machineLocalPath: String
}

struct ResearchFunctionResearchData: Encodable {
    let target: ResearchFunctionNamedData
    let source: ResearchSourceReference?
    let materials: [ResearchFunctionNamedData]
    let fidelityTargets: [ResearchFunctionNamedData]
    let passage: CommentAnchor?
}

extension ResearchFunctionCoordinator {
    // MARK: Availability and Materials

    func researchFunctionAvailability<Host: ResearchFunctionCoordinatorHost>(
        for target: ResearchFunctionTarget,
        checkingSourceAccess: Bool = true,
        host: isolated Host
    ) async throws -> [ResearchFunctionAvailability] {
        try requireMatchingActiveHost(host)
        let targetReason = await researchFunctionTargetRepairReason(
            target,
            host: host
        )
        var results: [ResearchFunctionAvailability] = []
        for function in ResearchFunctionID.allCases {
            var reasons: [ResearchFunctionRepairReason] = []
            if let targetReason {
                reasons.append(targetReason)
            } else if !function.allowedTargetRoles.contains(target.role) {
                reasons.append(ResearchFunctionRepairReason(
                    code: .invalidTargetRole,
                    function: function,
                    expectedRoles: Array(function.allowedTargetRoles)
                ))
            }

            if reasons.isEmpty {
                if checkingSourceAccess,
                   function == .develop,
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
                            reasons.append(ResearchFunctionRepairReason(
                                code: .sourceAccessRequired,
                                function: function,
                                sourceAccessFailure: failure
                            ))
                        }
                    }
                }
            }

            if reasons.isEmpty {
                let action = try ResearchActionFunctionMapping.definition(
                    for: function,
                    targetRole: target.role
                )
                do {
                    let method = try await dependencies.researchConfigurationStore
                        .methodSnapshot(for: action.id)
                    if !method.registration.isEnabled {
                        reasons.append(ResearchFunctionRepairReason(
                            code: .missingWorkflow,
                            function: function
                        ))
                    }
                } catch {
                    reasons.append(ResearchFunctionRepairReason(
                        code: .missingWorkflow,
                        function: function
                    ))
                }
            }

            var fidelityChecks: [ResearchFunctionCheckAvailability] = []
            if function == .fidelity, reasons.isEmpty {
                fidelityChecks.append(ResearchFunctionCheckAvailability(
                    check: .content,
                    isEnabled: true
                ))
                let citation = try await dependencies.researchConfigurationStore
                    .citationMethodSnapshot()
                if citation?.document.activeCitationStyle == nil {
                    fidelityChecks.append(ResearchFunctionCheckAvailability(
                        check: .citations,
                        isEnabled: false,
                        repairReasons: [ResearchFunctionRepairReason(
                            code: .citationStyleUnavailable,
                            function: .fidelity
                        )]
                    ))
                } else {
                    fidelityChecks.append(ResearchFunctionCheckAvailability(
                        check: .citations,
                        isEnabled: true
                    ))
                }
            }
            results.append(ResearchFunctionAvailability(
                function: function,
                isEnabled: reasons.isEmpty,
                repairReasons: reasons,
                fidelityChecks: fidelityChecks
            ))
        }
        return results
    }

    func researchFunctionMaterialCandidates<Host: ResearchFunctionCoordinatorHost>(
        for target: ResearchFunctionTarget,
        function: ResearchFunctionID,
        host: isolated Host
    ) async throws -> [ResearchFunctionMaterialCandidate] {
        try requireMatchingActiveHost(host)
        _ = try await validateResearchFunctionTarget(
            target,
            expected: target.fingerprint,
            host: host
        )
        guard function.allowedTargetRoles.contains(target.role) else {
            throw ResearchFunctionContractError.invalidTargetRole(
                function: function,
                role: target.role
            )
        }

        let currentSnapshot = host.researchFunctionCurrentSnapshot()
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
            VaultQualifiedNoteID: Set<ResearchFunctionMaterialSuggestionReason>
        ] = [:]
        if let graph = currentSnapshot.discovery.catalog.graph {
            for edge in graph.outgoing[target.note, default: []] {
                guard let destination = edge.destination?.note,
                      destination != target.note else { continue }
                suggestionsByLocation[destination, default: []].insert(
                    ResearchFunctionMaterialSuggestionReason(
                        kind: .linkedFromTarget,
                        sourceNote: target.note,
                        sourceSpan: edge.occurrence.span
                    )
                )
            }
            for edge in graph.incoming[target.note, default: []] {
                guard edge.source != target.note else { continue }
                suggestionsByLocation[edge.source, default: []].insert(
                    ResearchFunctionMaterialSuggestionReason(
                        kind: .linksDirectlyToTarget,
                        sourceNote: edge.source,
                        sourceSpan: edge.occurrence.span
                    )
                )
            }
        }

        return currentSnapshot.vaults.flatMap(\.documents).compactMap { note in
            guard note.id != target.note,
                  note.lifecycle == .active,
                  !note.capabilities.isManagedCritique,
                  case .resolved(let noteID) = note.stableIdentity,
                  let role = ResearchFunctionTargetRole(vaultRole: note.vaultRole),
                  let vault = currentSnapshot.vault(id: note.id.vaultID)?.vault else {
                return nil
            }
            let title = researchFunctionTitle(for: note)
            let material = ResearchFunctionMaterial(
                noteID: noteID,
                note: note.id,
                role: role,
                lifecycle: note.lifecycle,
                fingerprint: note.fingerprint,
                title: title
            )
            _ = vault // Keeps candidate creation explicitly vault-bound.
            return ResearchFunctionMaterialCandidate(
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

    func prepareResearchFunction<Host: ResearchFunctionCoordinatorHost>(
        _ request: ResearchFunctionRequest,
        host: isolated Host
    ) async throws -> ResearchFunctionPreparation {
        try await prepareResearchFunction(
            request,
            fidelityInvocation: request.function == .fidelity ? .manual : nil,
            host: host
        )
    }

    /// Prepares, but never executes or completes, the revision-bound Fidelity
    /// child required after a Develop or Revise completion that actually
    /// modified its Target. Repeated calls are idempotent for an existing
    /// current automatic child, and exact completed manual evidence remains
    /// reusable through the ordinary evidence key.
    func prepareAutomaticFidelity<Host: ResearchFunctionCoordinatorHost>(
        parentRunID: UUID,
        host: isolated Host
    ) async throws -> AutomaticFidelityPreparation {
        try requireMatchingActiveHost(host)
        guard try await dependencies.localExecutionStore
            .recordIfPresent(id: parentRunID) != nil else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Only a current Action run can authorize Content Fidelity."
            )
        }
        let records = try await authoritativeFunctionRecords()
        guard let parent = records.first(where: { $0.id == parentRunID }),
              [.develop, .revise].contains(parent.snapshot.request.function),
              let handoff = parent.snapshot.fidelityHandoff,
              handoff.required,
              let parentCompletion = parent.completion else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Automatic Content Fidelity requires a completed write-capable Action with a final-revision handoff."
            )
        }
        guard parentCompletion.didModifyTarget,
              parentCompletion.targetFingerprint != handoff.preparedTargetFingerprint else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Automatic Content Fidelity requires a write-capable Action that actually modified its Target."
            )
        }
        guard [.awaitingFidelity, .unverified].contains(parentCompletion.state) else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Automatic Fidelity can be prepared only while the parent run is awaiting valid final-revision evidence."
            )
        }

        let parentRequest = parent.snapshot.request
        if let existing = records.first(where: { record in
            guard case .automatic(let recordedParentID)? =
                    record.snapshot.resolvedFidelityInvocation,
                  recordedParentID == parentRunID,
                  record.snapshot.request.target.noteID == parentRequest.target.noteID,
                  record.snapshot.request.target.note == parentRequest.target.note,
                  record.snapshot.request.target.role == parentRequest.target.role,
                  record.snapshot.request.target.lifecycle == parentRequest.target.lifecycle,
                  record.snapshot.request.target.fingerprint
                    == parentCompletion.targetFingerprint,
                  record.snapshot.request.materials
                    == parentRequest.materials,
                  record.snapshot.request.scope == parentRequest.scope,
                  Set(record.snapshot.request.commentIDs)
                    == Set(parentRequest.commentIDs),
                  record.snapshot.request.checks == handoff.checks else {
                return false
            }
            return record.completion?.state != .stale
                && record.completion?.state != .cancelled
        }) {
            return AutomaticFidelityPreparation(
                parentRunID: parentRunID,
                preparation: ResearchFunctionPreparation(
                    snapshot: existing.snapshot,
                    instructions: existing.preparedInstructions ?? "",
                    state: existing.completion?.state ?? .prepared,
                    reusedCompletion: existing.completion
                )
            )
        }

        let finalTarget = ResearchFunctionTarget(
            noteID: parentRequest.target.noteID,
            note: parentRequest.target.note,
            role: parentRequest.target.role,
            lifecycle: parentRequest.target.lifecycle,
            fingerprint: parentCompletion.targetFingerprint,
            title: parentRequest.target.title
        )
        let request = ResearchFunctionRequest(
            function: .fidelity,
            target: finalTarget,
            materials: parentRequest.materials,
            scope: parentRequest.scope,
            checks: handoff.checks,
            commentIDs: parentRequest.commentIDs
        )
        let actionContext = try await host.resolveDefaultResearchActionContext(
            for: request
        )
        let fidelityLineage = parent.snapshot.continuationLineage.map {
            ResearchContinuationLineage(
                groupID: $0.groupID,
                parentRunID: parentRunID,
                requestID: $0.requestID,
                kind: .fidelity
            )
        }
        let preparation = try await prepareResearchFunction(
            request,
            fidelityInvocation: .automatic(parentRunID: parentRunID),
            actionContext: actionContext,
            continuationLineage: fidelityLineage,
            host: host
        )
        return AutomaticFidelityPreparation(
            parentRunID: parentRunID,
            preparation: preparation
        )
    }

    func researchFunctionRun<Host: ResearchFunctionCoordinatorHost>(
        id: UUID,
        host: isolated Host
    ) async throws -> ResearchFunctionPreparation {
        try requireMatchingActiveHost(host)
        let record = try await record(runID: id)
        if record.snapshot.request.function == .discuss {
            _ = try await validatedDiscussionStatements(snapshot: record.snapshot)
        }
        return ResearchFunctionPreparation(
            snapshot: record.snapshot,
            instructions: try await deliveryInstructions(for: record, host: host),
            state: record.completion?.state ?? .prepared,
            reusedCompletion: record.completion
        )
    }

    func prepareResearchFunction<Host: ResearchFunctionCoordinatorHost>(
        _ proposedRequest: ResearchFunctionRequest,
        fidelityInvocation: FidelityInvocationKind? = nil,
        host: isolated Host
    ) async throws -> ResearchFunctionPreparation {
        let actionContext = try await host.resolveDefaultResearchActionContext(
            for: proposedRequest
        )
        return try await prepareResearchFunction(
            proposedRequest,
            fidelityInvocation: fidelityInvocation,
            actionContext: actionContext,
            host: host
        )
    }

    func prepareResearchFunction<Host: ResearchFunctionCoordinatorHost>(
        _ proposedRequest: ResearchFunctionRequest,
        fidelityInvocation: FidelityInvocationKind? = nil,
        actionContext: ResolvedResearchActionContext,
        runIDOverride: UUID? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        continuationHandoff: ResearchContinuationHandoffContext? = nil,
        resynthesisContext: MaterialChangedSinceUseAttentionContext? = nil,
        requiresAgentChangeEvidence: Bool = true,
        suppressRefresh: Bool = false,
        host: isolated Host
    ) async throws -> ResearchFunctionPreparation {
        try requireMatchingActiveHost(host)
        guard (continuationLineage?.kind == .resynthesis)
                == (resynthesisContext != nil) else {
            throw ResearchFunctionContractError.invalidCompletion(
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
        guard actionContext.function == proposedRequest.function,
              actionContext.availability.definition.id
                == actionContext.availability.profile.profile.actionID else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let expandedRequest = proposedRequest
        try expandedRequest.validate()
        let target = try await validateResearchFunctionTarget(
            expandedRequest.target,
            expected: expandedRequest.target.fingerprint,
            host: host
        )
        _ = try await validateResearchFunctionMaterials(
            expandedRequest.materials,
            host: host
        )
        guard expandedRequest.commentIDs.isEmpty else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Legacy Comment evidence is reveal-only and cannot enter a current Action."
            )
        }
        let request = expandedRequest
        try request.validate()
        let sourceAccess = try await requiredResearchSourceAccess(
            for: target,
            function: request.function
        )
        let zoteroContext = try await zoteroBibliographicContext(for: target)
        _ = try await validateResearchFunctionWriteTargets(request, host: host)
        _ = try await validateResearchFunctionFidelityTargets(request, host: host)
        let actionAuthority = try resolvedActionAuthority(
            context: actionContext,
            request: request
        )
        let automaticFidelityChecks = try await automaticFidelityChecks(
            for: request.function
        )
        let phases = try await resolveResearchFunctionPhases(
            request,
            actionContext: actionContext,
            automaticFidelityChecks: automaticFidelityChecks,
            includeZoteroIntegration: zoteroContext != nil
                || sourceAccess?.reference.identity.route == .zoteroAttachment
        )
        let actionSnapshot = try resolvedActionSnapshot(
            context: actionContext,
            authority: actionAuthority,
            target: request.target.actionNote
        )

        let commentOnlyDiscussion: PortableResearchDiscussion?
        if request.function == .discuss {
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
                    throw ResearchFunctionContractError.activeDiscussionExists(existing.id)
                }
                commentOnlyDiscussion = existing
            } else {
                commentOnlyDiscussion = nil
            }
        } else {
            commentOnlyDiscussion = nil
        }

        let runID = runIDOverride ?? commentOnlyDiscussion?.id ?? UUID()
        // Every existing Note that a Run may change receives one exact,
        // Run-bound starting revision before Agent access. This is direct
        // change evidence, not a general version history.
        let capturedChangeEvidence: Bool
        if requiresAgentChangeEvidence,
           request.function.requiresAgentChangeEvidence {
            _ = try await captureAgentChangeStartingRevision(
                runID: runID,
                target: request.target
            )
            capturedChangeEvidence = true
        } else {
            capturedChangeEvidence = false
        }

        do {
            _ = try await validateResearchFunctionTarget(
                request.target,
                expected: request.target.fingerprint,
                host: host
            )
            _ = try await validateResearchFunctionMaterials(
                request.materials,
                host: host
            )
            _ = try await validateResearchFunctionWriteTargets(request, host: host)
            _ = try await validateResearchFunctionFidelityTargets(request, host: host)
            let revalidatedSource = try await requiredResearchSourceAccess(
                for: target,
                function: request.function
            )
            guard revalidatedSource?.reference == sourceAccess?.reference else {
                throw ResearchFunctionContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .sourceChanged)
                )
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
        let preparedAt = researchFunctionRecordTimestamp()
        let evidenceRevisions: [DocumentFingerprint] = []
        let handoff = request.function.requiresFinalFidelity && request.function != .manuscript
            ? ResearchFunctionFidelityHandoff(
                required: true,
                checks: automaticFidelityChecks,
                preparedTargetFingerprint: request.target.fingerprint
            )
            : nil

        let snapshot = ResearchFunctionSnapshot(
            runID: runID,
            request: request,
            actionSnapshot: actionSnapshot,
            recordKind: request.function == .discuss ? .discuss : .functionEnvelope,
            recordID: runID,
            // Manuscript does not impose one universal philosophical pipeline.
            // Develop and Revise expose only a pending Fidelity child here: its
            // exact workflow is prepared later against the final fingerprint.
            requiredChildFunctions: handoff == nil ? [] : [.fidelity],
            evidenceRevisions: evidenceRevisions,
            zoteroBibliographicContext: zoteroContext,
            sourceReference: sourceAccess?.reference,
            citationStyle: phases.first?.citationStyle,
            continuationLineage: continuationLineage,
            continuationHandoff: continuationHandoff,
            resynthesisContext: resynthesisContext,
            fidelityHandoff: handoff,
            fidelityInvocation: fidelityInvocation,
            confirmationToken: confirmationToken,
            preparedAt: preparedAt
        )

        if request.function == .fidelity {
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
                return ResearchFunctionPreparation(
                    snapshot: snapshot,
                    instructions: "Existing Fidelity evidence matches this exact revision, scope, evidence, checks, and method resources.",
                    state: .complete,
                    reusedCompletion: reused
                )
            }
        }

        let functionInstructions = try renderFunctionInstructions(
            request: request,
            action: actionContext.availability.definition,
            academicInputs: actionContext.academicInputs,
            resultContract: actionContext.resultContract,
            phases: phases,
            runID: runID,
            confirmationToken: confirmationToken,
            fidelityHandoffChecks: automaticFidelityChecks,
            zoteroContext: zoteroContext,
            sourceAccess: sourceAccess
        )
        let liveInstructions = try sourceAccessDeliveryInstructions(
            base: functionInstructions,
            sourceAccess: sourceAccess
        )
        let deliveryInstructions = liveInstructions
        do {
            // Close the race opened by method loading and evidence capture.
            _ = try await validateResearchFunctionTarget(
                request.target,
                expected: request.target.fingerprint,
                host: host
            )
            _ = try await validateResearchFunctionMaterials(
                request.materials,
                host: host
            )
            let finalSource = try await requiredResearchSourceAccess(
                for: target,
                function: request.function
            )
            guard finalSource?.reference == sourceAccess?.reference else {
                throw ResearchFunctionContractError.sourceAccessUnavailable(
                    ResearchSourceAccessFailure(code: .sourceChanged)
                )
            }
            let localDiscussion = request.function == .discuss
                    ? try localDiscussionExecution(
                        snapshot: snapshot,
                        request: request
                    )
                    : nil
            _ = try await dependencies.localExecutionStore.create(
                    LocalResearchExecutionRecord(
                        triptychID: workspaceID,
                        snapshot: snapshot,
                        preparedInstructions: functionInstructions,
                        discussion: localDiscussion
                    )
                )
            if request.function == .discuss {
                    let resolved = try ResearchDiscussionFactory.make(
                        snapshot: snapshot,
                        triptychID: workspaceID
                    )
                    if commentOnlyDiscussion != nil {
                        guard let action = resolved.action,
                              let method = resolved.method,
                              let statement = resolved.statements.first else {
                            throw ResearchFunctionContractError.invalidCompletion(
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
            host.scheduleResearchFunctionRefreshRecovery()
        } else {
            refreshWarning = try await host.publishCommittedResearchFunctionChange(
                "The Research Action preparation"
            )
        }
        var returnedInstructions = deliveryInstructions
        if request.function == .discuss {
            guard let responseContract = try await dependencies.localExecutionStore
                .record(id: runID).discussion?.responseContract else {
                throw ResearchFunctionContractError.preparationNotFound(runID)
            }
            let discussionInstructions = functionInstructions + "\n\n" + DiscussResponseTransport.locator(
                discussionID: runID,
                triptychID: workspaceID,
                contract: responseContract
            )
            returnedInstructions = discussionInstructions
        }
        return ResearchFunctionPreparation(
            snapshot: snapshot,
            instructions: returnedInstructions,
            derivedRefreshWarning: refreshWarning
        )
    }

    private func localDiscussionExecution(
        snapshot: ResearchFunctionSnapshot,
        request: ResearchFunctionRequest
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
