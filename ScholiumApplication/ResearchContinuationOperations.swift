import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchContinuationDependencies: Sendable {
    let localResearchExecutionStore: LocalResearchExecutionStore
    let portableResearchRecordStore: PortableResearchRecordStore
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let researchSourceAccessStore: ResearchSourceAccessStore
}

extension WorkspaceServices {
    var researchContinuationDependencies:
        WorkspaceResearchContinuationDependencies {
        WorkspaceResearchContinuationDependencies(
            localResearchExecutionStore: localResearchExecutionStore,
            portableResearchRecordStore: portableResearchRecordStore,
            researchAgentSessions: researchAgentSessions,
            researchSourceAccessStore: researchSourceAccessStore
        )
    }
}

extension WorkspaceRuntime {
    public func continueResearch(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationResult {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.continueResearch(
            credential: credential,
            run: run,
            request: request
        )
    }

    /// Returns the exact decision record created by the authenticated request.
    /// This is an App-delivery surface only; the local Agent bridge never
    /// serializes the record or its repository identifiers.
    public func researchContinuationRequest(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationRequestRecord {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.researchContinuationRequest(
            authenticated: authenticated,
            request: request
        )
    }
}

extension ResearchOperations {
    public func continueAgentResearch(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationResult {
        let handle = try await reference.requireHandle()
        return try await handle.continueResearch(
            credential: credential,
            run: run,
            request: request
        )
    }

    public func pendingContinuationRequests(
        at now: Date = Date()
    ) async throws -> [ResearchContinuationRequestRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.pendingContinuationRequests(at: now)
    }

    public func resolveContinuationRequest(
        parentRunID: UUID,
        requestID: UUID,
        allow: Bool,
        at date: Date = Date()
    ) async throws -> ResearchContinuationRequestRecord {
        let handle = try await reference.requireHandle()
        return try await handle.resolveContinuationRequest(
            parentRunID: parentRunID,
            requestID: requestID,
            allow: allow,
            at: date
        )
    }

    public func continuationRequest(
        parentRunID: UUID,
        requestID: UUID
    ) async throws -> ResearchContinuationRequestRecord {
        let handle = try await reference.requireHandle()
        return try await handle.continuationRequest(
            parentRunID: parentRunID,
            requestID: requestID
        )
    }
}

extension WorkspaceHandle {
    func researchContinuationRequest(
        authenticated: ResearchAuthenticatedRun,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationRequestRecord {
        try requireActive()
        guard authenticated.triptychID == id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let requestFingerprint = try request.contentFingerprint()
        let execution = try await researchContinuationDependencies.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        guard let record = execution.continuationRequests.first(where: {
            $0.requestFingerprint == requestFingerprint && $0.request == request
        }) else {
            throw ResearchContinuationContractError.invalidRecord
        }
        return record
    }

    func continuationRequest(
        parentRunID: UUID,
        requestID: UUID
    ) async throws -> ResearchContinuationRequestRecord {
        try requireActive()
        return try await researchContinuationDependencies.localResearchExecutionStore
            .continuationRequest(
                parentRunID: parentRunID,
                requestID: requestID
            )
    }

    func continueResearch(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContinuationRequest
    ) async throws -> ResearchContinuationResult {
        try requireActive()
        guard let sessions = researchContinuationDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let parentExecution = try await researchContinuationDependencies.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        guard let parentCompletion = parentExecution.completion,
              [.complete, .unverified].contains(parentCompletion.state),
              parentExecution.resultPayload != nil,
              let parentAction = parentExecution.snapshot.actionSnapshot,
              let parentPlatform = PlatformActionCatalog.definition(
                for: parentAction.actionID
              ),
              parentPlatform.operations.contains(.continueResearch),
              let parentRecord = try? await researchContinuationDependencies.portableResearchRecordStore
                .record(id: authenticated.runID),
              parentRecord.triptychID == id else {
            throw ResearchContinuationContractError.parentNotFinalized
        }

        let continuationReferences = request.handoff.flatMap(\.sourceReferences)
        guard continuationReferences.allSatisfy({ reference in
            reference.authorizedScope.runID == authenticated.runID
                && reference.authorizedScope.triptychID
                    == authenticated.triptychID
                && reference.owner.triptychID == authenticated.triptychID
        }) else {
            throw ResearchContinuationContractError.invalidHandoff
        }
        let researcherStateReferences = continuationReferences.filter {
            $0.sourceKind == .researcherState
        }
        guard researcherStateReferences.allSatisfy(
            Self.isResearcherStateReferenceForRequery
        ) else {
            throw ResearchContinuationContractError.invalidHandoff
        }
        let inheritedReferences = continuationReferences.filter {
            $0.sourceKind != .researcherState
        }
        let expectedInheritedReferences = Self.uniqueReferences(
            inheritedReferences
        )
        let inheritedHandoff = try request.handoff.map { item in
            try ResearchContinuationHandoffItem(
                content: item.content,
                epistemicStatus: item.epistemicStatus,
                nextUse: item.nextUse,
                sourceReferences: item.sourceReferences.filter {
                    $0.sourceKind != .researcherState
                }
            )
        }

        let requestFingerprint = try request.contentFingerprint()
        let requestID = Self.stableContinuationID(
            parentRunID: authenticated.runID,
            fingerprint: requestFingerprint
        )
        var decision: ResearchContinuationRequestRecord
        if let existing = parentExecution.continuationRequests.first(where: {
            $0.id == requestID
        }) {
            guard existing.requestFingerprint == requestFingerprint,
                  existing.request == request else {
                throw ResearchContinuationContractError.invalidRecord
            }
            decision = existing
        } else {
            let target = try continuationTarget(request)
            let platform = try continuationPlatform(
                request.nextActionID,
                targetRole: request.targetRole
            )
            let writableRoles: Set<ResearchActionTargetRole> =
                platform.operations.contains(.modifyInitialNote)
                    ? [target.role]
                    : []
            let policy = try await currentCollaborationPolicy()
            let now = Date()
            let pending = try ResearchContinuationRequestRecord(
                id: requestID,
                parentRunID: authenticated.runID,
                triptychID: authenticated.triptychID,
                request: request,
                requestFingerprint: requestFingerprint,
                policy: policy.document.policy,
                policyRevision: policy.revision,
                state: .pending,
                receivedAt: now,
                expiresAt: now.addingTimeInterval(10 * 60)
            )
            _ = try await researchContinuationDependencies.localResearchExecutionStore
                .installContinuationRequest(pending)
            let collaborationRequest = try ResearchCollaborationRequest(
                kind: .continueResearch,
                requestedWritableRoles: writableRoles
            )
            if ResearchCollaborationPolicyResolver.evaluate(
                policy: policy.document.policy,
                request: collaborationRequest
            ) == .mayProceed {
                _ = try await researchContinuationDependencies.localResearchExecutionStore
                    .transitionContinuationRequest(
                        parentRunID: authenticated.runID,
                        requestID: requestID,
                        state: .allowed,
                        authorizationBasis: .collaborationPolicy,
                        decidedAt: now
                    )
            }
            decision = try await researchContinuationDependencies.localResearchExecutionStore
                .continuationRequest(
                    parentRunID: authenticated.runID,
                    requestID: requestID
                )
        }

        if decision.state == .pending, decision.expiresAt <= Date() {
            _ = try await researchContinuationDependencies.localResearchExecutionStore
                .transitionContinuationRequest(
                    parentRunID: authenticated.runID,
                    requestID: requestID,
                    state: .expired,
                    decidedAt: Date()
                )
            decision = try await researchContinuationDependencies.localResearchExecutionStore
                .continuationRequest(
                    parentRunID: authenticated.runID,
                    requestID: requestID
                )
        }
        switch decision.state {
        case .pending:
            return try ResearchContinuationResult(
                state: .pendingResearcherDecision,
                message: "The next Action is waiting for one researcher decision in Scholium. Retry this same request after the decision."
            )
        case .declined:
            return try ResearchContinuationResult(
                state: .declined,
                message: "The researcher declined this next Action; the parent Record is unchanged."
            )
        case .stale:
            return try ResearchContinuationResult(
                state: .stale,
                message: "The next Action request became stale and did not create a Run."
            )
        case .expired:
            return try ResearchContinuationResult(
                state: .expired,
                message: "The next Action request expired and did not create a Run."
            )
        case .allowed, .created:
            break
        }

        try await revalidateContinuationAuthorization(decision)
        let childRunID = requestID
        let handoffContext: ResearchContinuationHandoffContext
        if let existing = try await researchContinuationDependencies.localResearchExecutionStore
            .recordIfPresent(id: childRunID) {
            guard existing.snapshot.continuationLineage?.kind == .continueResearch,
                  existing.snapshot.continuationLineage?.parentRunID
                    == authenticated.runID,
                  existing.snapshot.continuationHandoff?.parentRecordID
                    == authenticated.runID else {
                throw ResearchContinuationContractError.invalidRecord
            }
            guard let existingHandoff = existing.snapshot.continuationHandoff else {
                throw ResearchContinuationContractError.invalidRecord
            }
            guard existingHandoff.initiator == .agent,
                  existingHandoff.academicPurpose == request.academicPurpose,
                  existingHandoff.handoff == inheritedHandoff,
                  existingHandoff.requiresResearcherStateRequery
                    == !researcherStateReferences.isEmpty,
                  existingHandoff.referenceChecks.map(\.sourceReference)
                    == expectedInheritedReferences else {
                throw ResearchContinuationContractError.invalidRecord
            }
            handoffContext = existingHandoff
        } else {
            let target = try continuationTarget(request)
            _ = try continuationPlatform(
                request.nextActionID,
                targetRole: request.targetRole
            )
            let function = try continuationFunction(
                request.nextActionID,
                targetRole: request.targetRole
            )
            let checks = try await continuationReferenceChecks(
                inheritedReferences,
                parentSnapshot: parentExecution.snapshot
            )
            handoffContext = try ResearchContinuationHandoffContext(
                parentRecordID: authenticated.runID,
                initiator: .agent,
                academicPurpose: request.academicPurpose,
                handoff: inheritedHandoff,
                referenceChecks: checks,
                requiresResearcherStateRequery:
                    !researcherStateReferences.isEmpty
            )
            let functionTarget = ResearchFunctionTarget(
                noteID: target.noteID,
                note: target.note,
                role: Self.functionRole(target.role),
                lifecycle: target.lifecycle,
                fingerprint: target.fingerprint,
                title: target.title
            )
            let functionRequest = ResearchFunctionRequest(
                function: function,
                target: functionTarget,
                materials: [],
                instruction: request.academicPurpose,
                scope: .whole,
                checks: function == .fidelity
                    ? (request.fidelityChecks.isEmpty
                        ? [.content]
                        : Set(request.fidelityChecks))
                    : [],
                dialogueResponseModules: function == .discuss ? [] : nil
            )
            let actionContext = try await resolvedDefaultActionContext(
                for: functionRequest
            )
            guard actionContext.availability.definition.id
                    == request.nextActionID else {
                throw ResearchActionExecutionContractError.actionUnavailable(
                    request.nextActionID
                )
            }
            let lineage = ResearchContinuationLineage(
                groupID: parentRecord.continuationLineage?.groupID
                    ?? parentRecord.id,
                parentRunID: parentRecord.id,
                requestID: childRunID,
                kind: .continueResearch
            )
            _ = try await researchFunctionCoordinator.prepareResearchFunction(
                functionRequest,
                actionContext: actionContext,
                runIDOverride: childRunID,
                continuationLineage: lineage,
                continuationHandoff: handoffContext,
                requiresAgentChangeEvidence:
                    !actionContext.authority.writableNotes.isEmpty,
                host: self
            )
        }

        let child = try await researchContinuationDependencies.localResearchExecutionStore.record(id: childRunID)
        let canWrite = !child.boundedWriteSet.entries.isEmpty
        let locator: ResearchRunLocator
        if let attached = try await sessions.attachedLocator(
            for: childRunID,
            credential: credential
        ) {
            locator = attached
        } else {
            locator = try await sessions.attachRun(
                runID: childRunID,
                triptychID: authenticated.triptychID,
                canWrite: canWrite,
                to: credential
            )
        }
        if decision.state == .allowed {
            _ = try await researchContinuationDependencies.localResearchExecutionStore
                .transitionContinuationRequest(
                    parentRunID: authenticated.runID,
                    requestID: requestID,
                    state: .created,
                    childRunID: childRunID,
                    decidedAt: decision.decidedAt ?? Date()
                )
        }
        return try ResearchContinuationResult(
            state: .created,
            nextRun: locator,
            handoffContext: handoffContext,
            message: handoffContext.requiresResearcherStateRequery
                ? "A new independent Action Run was created without inherited Researcher State; query inspect_researcher_state in that Run to read current researcher-owned facts."
                : "A new independent Action Run was created with current Method, Profile, permissions, and no inherited Context response or write state."
        )
    }

    func pendingContinuationRequests(
        at now: Date
    ) async throws -> [ResearchContinuationRequestRecord] {
        try requireActive()
        let listing = try await researchContinuationDependencies.localResearchExecutionStore.listing()
        guard listing.issues.isEmpty else {
            throw ResearchContinuationContractError.invalidRecord
        }
        var result: [ResearchContinuationRequestRecord] = []
        for execution in listing.records {
            for request in execution.continuationRequests where request.state == .pending {
                if request.expiresAt <= now {
                    _ = try await researchContinuationDependencies.localResearchExecutionStore
                        .transitionContinuationRequest(
                            parentRunID: request.parentRunID,
                            requestID: request.id,
                            state: .expired,
                            decidedAt: now
                        )
                } else {
                    result.append(request)
                }
            }
        }
        return result.sorted { $0.receivedAt < $1.receivedAt }
    }

    func resolveContinuationRequest(
        parentRunID: UUID,
        requestID: UUID,
        allow: Bool,
        at date: Date
    ) async throws -> ResearchContinuationRequestRecord {
        try requireActive()
        let request = try await researchContinuationDependencies.localResearchExecutionStore
            .continuationRequest(parentRunID: parentRunID, requestID: requestID)
        guard request.state == .pending, request.expiresAt > date else {
            throw ResearchContinuationContractError.invalidRecord
        }
        _ = try continuationTarget(request.request)
        _ = try continuationPlatform(
            request.request.nextActionID,
            targetRole: request.request.targetRole
        )
        _ = try await researchContinuationDependencies.localResearchExecutionStore
            .transitionContinuationRequest(
                parentRunID: parentRunID,
                requestID: requestID,
                state: allow ? .allowed : .declined,
                authorizationBasis: allow ? .explicitResearcherDecision : nil,
                decidedAt: date
            )
        return try await researchContinuationDependencies.localResearchExecutionStore
            .continuationRequest(parentRunID: parentRunID, requestID: requestID)
    }

    private func revalidateContinuationAuthorization(
        _ record: ResearchContinuationRequestRecord
    ) async throws {
        _ = try continuationTarget(record.request)
        let platform = try continuationPlatform(
            record.request.nextActionID,
            targetRole: record.request.targetRole
        )
        guard record.authorizationBasis == .collaborationPolicy else { return }
        let current = try await currentCollaborationPolicy()
        if current.revision == record.policyRevision,
           current.document.policy == record.policy { return }
        let writableRoles: Set<ResearchActionTargetRole> =
            platform.operations.contains(.modifyInitialNote)
                ? [record.request.targetRole]
                : []
        let request = try ResearchCollaborationRequest(
            kind: .continueResearch,
            requestedWritableRoles: writableRoles
        )
        guard ResearchCollaborationPolicyResolver.evaluate(
            policy: current.document.policy,
            request: request
        ) == .mayProceed else {
            _ = try await researchContinuationDependencies.localResearchExecutionStore
                .transitionContinuationRequest(
                    parentRunID: record.parentRunID,
                    requestID: record.id,
                    state: .stale,
                    decidedAt: Date()
                )
            throw ResearchContinuationContractError.decisionRequired
        }
    }

    private func continuationTarget(
        _ request: ResearchContinuationRequest
    ) throws -> ResearchActionNoteSnapshot {
        let vaultRole = Self.vaultRole(request.targetRole)
        guard let vault = currentSnapshot.vaults.first(where: {
            $0.vault.role == vaultRole
        }),
        let note = vault.documents.first(where: {
            $0.id.relativePath == request.targetRelativePath
        }),
        note.lifecycle == .active,
        let noteID = note.stableIdentity.resolvedID else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        return ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note.id,
            role: request.targetRole,
            lifecycle: note.lifecycle,
            fingerprint: note.fingerprint,
            title: ResearchNoteTitleResolver.resolve(
                document: note.document,
                profile: note.schemaProfile
            ).title
        )
    }

    private func continuationPlatform(
        _ actionID: ResearchActionID,
        targetRole: ResearchActionTargetRole
    ) throws -> PlatformActionDefinition {
        guard let platform = PlatformActionCatalog.definition(for: actionID),
              platform.allowedTargetRoles.contains(targetRole) else {
            throw ResearchActionExecutionContractError.actionUnavailable(actionID)
        }
        return platform
    }

    private func continuationFunction(
        _ actionID: ResearchActionID,
        targetRole: ResearchActionTargetRole
    ) throws -> ResearchFunctionID {
        let definition: ResearchActionDefinition = switch actionID {
        case .discuss: .discuss
        case .analyze: .analyze
        case .synthesize: .synthesize
        case .write: .write
        case .critique: .critique
        case .checkFidelity: .checkFidelity
        case .manuscript: .manuscript
        default:
            throw ResearchActionExecutionContractError.actionUnavailable(actionID)
        }
        return try ResearchActionFunctionMapping.function(
            for: definition,
            targetRole: targetRole
        )
    }

    private func continuationReferenceChecks(
        _ references: [SourceReferenceEnvelope],
        parentSnapshot: ResearchFunctionSnapshot
    ) async throws -> [ResearchContinuationReferenceCheck] {
        var seen: Set<UUID> = []
        var checks: [ResearchContinuationReferenceCheck] = []
        for reference in references where seen.insert(reference.id).inserted {
            let result = try await continuationReferenceStatus(
                reference,
                parentSnapshot: parentSnapshot
            )
            checks.append(try ResearchContinuationReferenceCheck(
                sourceReference: reference,
                status: result.status,
                explanation: result.explanation
            ))
        }
        return checks
    }

    private func continuationReferenceStatus(
        _ reference: SourceReferenceEnvelope,
        parentSnapshot: ResearchFunctionSnapshot
    ) async throws -> (
        status: ResearchContinuationReferenceStatus,
        explanation: String
    ) {
        guard reference.owner.triptychID == id else {
            return (.missing, "The referenced owner belongs to another Triptych.")
        }
        switch reference.sourceKind {
        case .note:
            guard reference.owner.kind == .note,
                  let vaultID = reference.owner.vaultID,
                  let relativePath = reference.owner.relativePath,
                  reference.actorClass == .unknown,
                  let snapshot = currentSnapshot.document(
                    id: VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: relativePath
                    )
                  ),
                  snapshot.lifecycle == .active,
                  snapshot.stableIdentity.resolvedID?.uuidString.lowercased()
                    == reference.owner.stableObjectIdentity else {
                return (.missing, "The referenced Note owner is missing or has a different stable identity.")
            }
            guard snapshot.fingerprint == reference.fingerprint,
                  reference.currentness == .current else {
                return (
                    .changed,
                    "The authoritative Note owner has a different current revision; query and reread it before use."
                )
            }
            guard reference.vaultRole == snapshot.vaultRole,
                  reference.objectRole == Self.objectRole(snapshot.vaultRole),
                  reference.evidentialLayer == Self.evidentialLayer(snapshot.vaultRole),
                  Self.isNoteRetrievalReason(reference.retrievalReason),
                  let document = try? await loadDocument(snapshot.id),
                  document.fingerprint == snapshot.fingerprint,
                  Self.locator(reference.locator, isValidIn: document.rawContent)
            else {
                throw ResearchContinuationContractError.invalidHandoff
            }
            return (
                .current,
                "The authoritative Note owner, revision, and locator are current."
            )
        case .record:
            guard reference.owner.kind == .record,
                  let recordID = reference.owner.recordID,
                  reference.owner.stableObjectIdentity
                    == recordID.uuidString.lowercased(),
                  reference.objectRole == .researchRecord,
                  reference.vaultRole == nil,
                  reference.evidentialLayer == .researchRecord,
                  reference.retrievalReason == .recordSearch else {
                throw ResearchContinuationContractError.invalidHandoff
            }
            let listing = try await researchContinuationDependencies.portableResearchRecordStore.listing()
            guard listing.issues.isEmpty,
                  let current = listing.revisions.first(where: { $0.id == recordID })
            else { return (.missing, "The Research Record owner is missing.") }
            guard current.fingerprint == reference.fingerprint,
                  reference.currentness == .current else {
                return (
                    .changed,
                    "The Research Record has changed; query its current attributed content before use."
                )
            }
            switch reference.locator.kind {
            case .recordStatement:
                guard let statementID = reference.locator.statementID,
                      let statement = current.record.statements.first(where: {
                          $0.id == statementID
                      }),
                      reference.actorClass == Self.actorClass(statement.author)
                else {
                    throw ResearchContinuationContractError.invalidHandoff
                }
            case .wholeObject:
                guard reference.actorClass == .unknown else {
                    throw ResearchContinuationContractError.invalidHandoff
                }
            case .sourceRange, .materialLocator, .unknown:
                throw ResearchContinuationContractError.invalidHandoff
            }
            return (
                .current,
                "The authoritative Research Record owner, revision, and locator are current."
            )
        case .material:
            guard let frozen = parentSnapshot.sourceReference,
                  ResearchContextMaterialProjection.isCurrentReference(
                    reference,
                    source: frozen,
                    zoteroBibliographicContext:
                        parentSnapshot.zoteroBibliographicContext,
                    runID: parentSnapshot.runID,
                    triptychID: id
                  ) else {
                throw ResearchContinuationContractError.invalidHandoff
            }
            let status = await researchContinuationDependencies.researchSourceAccessStore.status(
                analysisNoteID: parentSnapshot.request.target.noteID
            )
            switch status.state {
            case .available:
                guard let current = status.reference else {
                    return (
                        .unavailable,
                        "The authoritative source owner returned no current Material reference."
                    )
                }
                guard current.identity == frozen.identity else {
                    return (
                        .missing,
                        "The Run's selected source Material is no longer the current source binding."
                    )
                }
                guard current.fingerprint == frozen.fingerprint,
                      reference.currentness == .current else {
                    return (
                        .changed,
                        "The selected source Material has a different current revision; reopen it before use."
                    )
                }
                return (
                    .current,
                    "The authoritative source Material identity, fingerprint, and locator are current."
                )
            case .repairRequired:
                switch status.failure?.code {
                case .sourceChanged:
                    return (
                        .changed,
                        "The selected source Material changed after the parent Run used it."
                    )
                case .missingBinding, .sourceMissing, .zoteroAttachmentMissing:
                    return (
                        .missing,
                        "The selected source Material is missing from its authoritative binding."
                    )
                case .corruptBinding, .bookmarkUnavailable, .bookmarkStale,
                        .sourceUnreadable, .sourceNotRegular,
                        .sourceIsSymbolicLink, .zoteroUnavailable,
                        .zoteroIdentityMismatch, .none:
                    return (
                        .unavailable,
                        "The authoritative source owner cannot currently verify this Material."
                    )
                }
            }
        case .researcherState:
            throw ResearchContinuationContractError.invalidHandoff
        }
    }

    private static func isResearcherStateReferenceForRequery(
        _ reference: SourceReferenceEnvelope
    ) -> Bool {
        reference.owner.kind == .researcherState
            && reference.actorClass == .researcher
            && reference.objectRole == .researcherState
            && reference.vaultRole == nil
            && reference.fingerprint != nil
            && reference.locator.kind == .wholeObject
            && (reference.currentness == .current
                || reference.currentness == .stale)
            && reference.evidentialLayer == .researcherState
            && reference.retrievalReason == .researcherState
    }

    private static func uniqueReferences(
        _ references: [SourceReferenceEnvelope]
    ) -> [SourceReferenceEnvelope] {
        var seen: Set<UUID> = []
        return references.filter { seen.insert($0.id).inserted }
    }

    private static func stableContinuationID(
        parentRunID: UUID,
        fingerprint: DocumentFingerprint
    ) -> UUID {
        let digest = DocumentFingerprint(
            content: "\(parentRunID.uuidString.lowercased()):continue:\(fingerprint.sha256)"
        ).sha256
        return UUID(uuidString: [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func vaultRole(_ role: ResearchActionTargetRole) -> VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    private static func functionRole(
        _ role: ResearchActionTargetRole
    ) -> ResearchFunctionTargetRole {
        switch role {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}
