import Foundation
import ScholiumContracts
import ScholiumCore

public enum AgentNoteChangeOperationError: LocalizedError, Hashable, Sendable {
    case crossTriptych
    case parentRunNotFound(UUID)
    case parentRunMismatch(UUID)
    case redundantRequest(UUID)
    case invalidCoordinationKey
    case expiredCoordinationKey
    case coordinationRequestAlreadyBound(UUID)
    case continuationUnavailable(UUID)

    public var errorDescription: String? {
        switch self {
        case .crossTriptych:
            "The Agent Note Change request belongs to another Triptych."
        case .parentRunNotFound(let id):
            "Parent run \(id.uuidString.lowercased()) is not a current local Action run."
        case .parentRunMismatch(let id):
            "Parent run \(id.uuidString.lowercased()) does not match the request's frozen Action revision."
        case .redundantRequest(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) does not expand the parent run's bounded scope."
        case .invalidCoordinationKey:
            "The Agent coordination key is invalid."
        case .expiredCoordinationKey:
            "The Agent coordination key has expired."
        case .coordinationRequestAlreadyBound(let id):
            "The Agent coordination key is already bound to request \(id.uuidString.lowercased())."
        case .continuationUnavailable(let id):
            "Agent Note Change request \(id.uuidString.lowercased()) has no current, independently authorized continuation."
        }
    }
}

extension WorkspaceHandle {
    func submitAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let record = try await submitAgentNoteChangeRequestWithinCoordination(
            request,
            receivedAt: receivedAt,
            validFor: validFor
        )
        return try await applyingStandingPermissionIfPossible(
            to: record,
            decidedAt: receivedAt
        )
    }

    func applyStandingPermissionToAgentNoteChangeRequest(
        id: UUID,
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let record = try await currentAgentNoteChangeRequest(
            id: id,
            now: decidedAt
        )
        return try await applyingStandingPermissionIfPossible(
            to: record,
            decidedAt: decidedAt
        )
    }

    private func submitAgentNoteChangeRequestWithinCoordination(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date,
        validFor: TimeInterval,
        beforeFirstSubmission: (() async throws -> Void)? = nil
    ) async throws -> AgentNoteChangeRequestRecord {
        if let existing = try await services.agentNoteChangeRequestStore
            .recordIfPresent(id: request.id, now: receivedAt) {
            guard existing.request == request else {
                throw AgentNoteChangeRequestStoreError
                    .duplicateRequestPayload(request.id)
            }
            try await beforeFirstSubmission?()
            return try await currentAgentNoteChangeRequest(
                id: request.id,
                now: receivedAt
            )
        }
        try await authenticateParent(of: request)
        guard request.triptychID == services.manifest.id else {
            throw AgentNoteChangeOperationError.crossTriptych
        }
        guard try await requestExpandsParentScope(request) else {
            throw AgentNoteChangeOperationError.redundantRequest(request.id)
        }
        let isCurrent = try await isCurrentAgentNoteChangeRequest(request)
        try await beforeFirstSubmission?()
        return try await services.agentNoteChangeRequestStore.submitValidated(
            request,
            isCurrent: isCurrent,
            receivedAt: receivedAt,
            validFor: validFor
        )
    }

    func agentNoteChangeRequest(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        return try await currentAgentNoteChangeRequest(id: id, now: now)
    }

    private func currentAgentNoteChangeRequest(
        id: UUID,
        now: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        var record = try await services.agentNoteChangeRequestStore.record(
            id: id,
            now: now
        )
        if record.isUnresolved,
           !(try await isCurrentAgentNoteChangeRequest(record.request)) {
            record = try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: now
            )
        }
        return record
    }

    func pendingAgentNoteChangeRequests(
        now: Date = Date()
    ) async throws -> [AgentNoteChangeRequestRecord] {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let pending = try await services.agentNoteChangeRequestStore.pending(now: now)
        var current: [AgentNoteChangeRequestRecord] = []
        for record in pending {
            if try await isCurrentAgentNoteChangeRequest(record.request) {
                current.append(record)
            } else {
                _ = try await services.agentNoteChangeRequestStore.resolve(
                    id: record.id,
                    state: .stale,
                    decidedAt: now
                )
            }
        }
        return current
    }

    func submitAgentNoteChangeRequestFromBridge(
        _ request: AgentNoteChangeRequest,
        coordinationKey: String,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let execution = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: request.parentRunID,
            requestID: request.id,
            permitsUnboundRequest: true,
            at: receivedAt
        )
        try Task.checkCancellation()
        let grant = try requireCoordinationGrant(execution)
        let record = try await submitAgentNoteChangeRequestWithinCoordination(
            request,
            receivedAt: receivedAt,
            validFor: validFor,
            beforeFirstSubmission: {
                try Task.checkCancellation()
                _ = try await self.services.localResearchExecutionStore
                    .bindAgentCoordinationRequest(
                        runID: request.parentRunID,
                        expectedGrant: grant,
                        requestID: request.id
                    )
            }
        )
        return record
    }

    func resolveAgentNoteChangeRequest(
        id: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        guard state == .allowedSubset
                || state == .continueWithoutChanges
                || state == .cancelled else {
            throw AgentNoteChangeContractError.invalidDecision
        }
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }

        let current: AgentNoteChangeRequestRecord
        if state == .cancelled {
            current = try await currentAgentNoteChangeRequestForCancellation(
                id: id,
                now: decidedAt
            )
        } else {
            current = try await currentAgentNoteChangeRequest(id: id, now: decidedAt)
        }
        guard current.isUnresolved else { return current }
        _ = try await evaluateStandingPermission(for: current.request)
        let parentBeforeDecision = try await services.localResearchExecutionStore
            .record(id: current.request.parentRunID)
        let permitsCancelledParent = state == .cancelled
            && parentBeforeDecision.completion?.state == .cancelled
        guard try await isCurrentAgentNoteChangeRequest(
            current.request,
            permittingCancelledParent: permitsCancelledParent
        ) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: decidedAt
            )
        }

        if state == .cancelled {
            let parent = try await services.localResearchExecutionStore.record(
                id: current.request.parentRunID
            )
            if parent.completion == nil {
                try await cancelResearchFunction(runID: current.request.parentRunID)
            }
        }
        let continuationPlan = state == .allowedSubset
            ? try await makeAgentNoteChangeContinuationPlan(
                request: current.request,
                allowedNoteIDs: allowedNoteIDs
            )
            : nil
        return try await services.agentNoteChangeRequestStore.resolve(
            id: id,
            state: state,
            allowedNoteIDs: allowedNoteIDs,
            continuationPlan: continuationPlan,
            decidedAt: decidedAt
        )
    }

    /// Recovers the researcher-authored Cancel the Run decision if the parent
    /// cancellation committed but the request-store transition was interrupted.
    /// Other decisions continue to treat a cancelled parent as stale.
    private func currentAgentNoteChangeRequestForCancellation(
        id: UUID,
        now: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        var record = try await services.agentNoteChangeRequestStore.record(
            id: id,
            now: now
        )
        guard record.isUnresolved else { return record }
        let parent = try await services.localResearchExecutionStore.record(
            id: record.request.parentRunID
        )
        let isRecoveringCommittedCancellation = parent.completion?.state == .cancelled
        if !(try await isCurrentAgentNoteChangeRequest(
            record.request,
            permittingCancelledParent: isRecoveringCommittedCancellation
        )) {
            record = try await services.agentNoteChangeRequestStore.resolve(
                id: id,
                state: .stale,
                decidedAt: now
            )
        }
        return record
    }

    private func applyingStandingPermissionIfPossible(
        to record: AgentNoteChangeRequestRecord,
        decidedAt: Date
    ) async throws -> AgentNoteChangeRequestRecord {
        guard record.isUnresolved else { return record }
        let initialEvaluation = try await evaluateStandingPermission(
            for: record.request
        )
        guard initialEvaluation.disposition == .mayIssueBoundedGrant else {
            return record
        }
        guard try await isCurrentAgentNoteChangeRequest(record.request) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: record.id,
                state: .stale,
                decidedAt: max(decidedAt, record.receivedAt)
            )
        }
        let finalEvaluation = try await evaluateStandingPermission(
            for: record.request
        )
        guard finalEvaluation == initialEvaluation,
              finalEvaluation.disposition == .mayIssueBoundedGrant else {
            return record
        }
        guard try await isCurrentAgentNoteChangeRequest(record.request) else {
            return try await services.agentNoteChangeRequestStore.resolve(
                id: record.id,
                state: .stale,
                decidedAt: max(decidedAt, record.receivedAt)
            )
        }
        let continuationPlan = try await makeAgentNoteChangeContinuationPlan(
            request: record.request,
            allowedNoteIDs: record.request.targets.map(\.noteID)
        )
        return try await services.agentNoteChangeRequestStore.resolve(
            id: record.id,
            state: .allowedSubset,
            allowedNoteIDs: record.request.targets.map(\.noteID),
            continuationPlan: continuationPlan,
            decidedAt: max(decidedAt, record.receivedAt)
        )
    }

    func agentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let stored = try await services.agentNoteChangeRequestStore
            .recordForAuthentication(id: id)
        _ = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: stored.request.parentRunID,
            requestID: id,
            permitsUnboundRequest: false,
            at: now
        )
        try Task.checkCancellation()
        return try await currentAgentNoteChangeRequest(id: id, now: now)
    }

    func cancelAgentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try requireActive()
        try Task.checkCancellation()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }
        let stored = try await services.agentNoteChangeRequestStore
            .recordForAuthentication(id: id)
        _ = try await authenticateCoordinationKey(
            coordinationKey,
            parentRunID: stored.request.parentRunID,
            requestID: id,
            permitsUnboundRequest: false,
            at: now
        )
        try Task.checkCancellation()
        guard stored.isUnresolved else { return stored }
        return try await services.agentNoteChangeRequestStore.resolve(
            id: id,
            state: .cancelled,
            decidedAt: now
        )
    }

    private func authenticateCoordinationKey(
        _ key: String,
        parentRunID: UUID,
        requestID: UUID,
        permitsUnboundRequest: Bool,
        at date: Date
    ) async throws -> LocalResearchExecutionRecord {
        guard key.utf8.count == 73,
              let execution = try await services.localResearchExecutionStore
                .recordIfPresent(id: parentRunID),
              let grant = execution.agentCoordinationGrant,
              execution.triptychID == grant.triptychID,
              services.manifest.id == grant.triptychID,
              execution.id == grant.parentRunID,
              parentRunID == grant.parentRunID,
              let actionSnapshot = execution.snapshot.actionSnapshot,
              try AgentNoteChangeActionRevision(actionSnapshot: actionSnapshot)
                == grant.actionRevision else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        guard date < grant.expiresAt else {
            throw AgentNoteChangeOperationError.expiredCoordinationKey
        }
        let candidate = try grant.boundKeyDigest(coordinationKey: key)
        guard Self.constantTimeEqual(candidate, grant.keyDigest) else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        if let boundID = execution.agentCoordinationRequestID,
           boundID != requestID {
            throw AgentNoteChangeOperationError
                .coordinationRequestAlreadyBound(boundID)
        }
        if !permitsUnboundRequest,
           execution.agentCoordinationRequestID != requestID {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        return execution
    }

    private func requireCoordinationGrant(
        _ execution: LocalResearchExecutionRecord
    ) throws -> AgentCoordinationGrant {
        guard let grant = execution.agentCoordinationGrant else {
            throw AgentNoteChangeOperationError.invalidCoordinationKey
        }
        return grant
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(left.count ^ right.count)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            difference |= l ^ r
        }
        return difference == 0
    }

    private func authenticateParent(
        of request: AgentNoteChangeRequest
    ) async throws {
        guard request.triptychID == services.manifest.id else {
            throw AgentNoteChangeOperationError.crossTriptych
        }
        guard let record = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID) else {
            throw AgentNoteChangeOperationError
                .parentRunNotFound(request.parentRunID)
        }
        guard record.triptychID == services.manifest.id,
              let actionSnapshot = record.snapshot.actionSnapshot,
              actionSnapshot.actionID == request.parentAction.definition.id,
              try AgentNoteChangeActionRevision(actionSnapshot: actionSnapshot)
                == request.parentAction else {
            throw AgentNoteChangeOperationError
                .parentRunMismatch(request.parentRunID)
        }
    }

    private func requestExpandsParentScope(
        _ request: AgentNoteChangeRequest
    ) async throws -> Bool {
        guard let record = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID),
              let parent = record.snapshot.actionSnapshot else {
            throw AgentNoteChangeOperationError
                .parentRunNotFound(request.parentRunID)
        }
        let alreadyWritable = Set(parent.authority.writableNotes.map(\.noteID))
        let alreadyAllowedOperations = Set(parent.authority.writeOperations)
        return request.targets.contains {
            !alreadyWritable.contains($0.noteID)
        } || !Set(request.operations).isSubset(of: alreadyAllowedOperations)
            || request.requestedAction.definition != parent.definition
    }

    private func isCurrentAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest,
        permittingCancelledParent: Bool = false
    ) async throws -> Bool {
        do {
            try await authenticateParent(of: request)
        } catch is AgentNoteChangeOperationError {
            return false
        }
        guard let parent = try await services.localResearchExecutionStore
            .recordIfPresent(id: request.parentRunID),
              Self.parentPermitsChangeRequest(parent)
                || (permittingCancelledParent
                    && parent.completion?.state == .cancelled) else {
            return false
        }
        var currentTargets: [ResearchActionNoteSnapshot] = []
        var resolvedAction: ResearchActionAvailability?
        for target in request.targets {
            guard let currentTarget = try await currentAgentChangeTarget(
                target
            ) else {
                return false
            }
            currentTargets.append(currentTarget)
            let availability = try await researchActionAvailability(
                for: currentTarget
            )
            guard let action = availability.first(where: {
                $0.id == request.requestedAction.definition.id
            }), action.isEnabled,
            action.definition == request.requestedAction.definition,
            action.profile.origin == request.requestedAction.profileOrigin,
            action.profile.profileRevision
                == request.requestedAction.profileRevision,
            action.profile.profileDocumentRevision
                == request.requestedAction.profileDocumentRevision,
            action.profile.profile.capabilities.candidateWritableRoles
                .contains(currentTarget.role),
            Set(request.operations).isSubset(of: Set(
                action.profile.profile.capabilities.candidateWriteOperations
            )) else {
                return false
            }
            if let resolvedAction, resolvedAction != action {
                return false
            }
            resolvedAction = action
        }
        guard let action = resolvedAction,
              let first = currentTargets.first else { return false }

        let function = try ResearchActionFunctionMapping.function(
            for: action.definition,
            targetRole: first.role
        )
        let method: ResearchSkillBindingResolution
        switch action.profile.origin {
        case .applicationDefault:
            method = try await services.researchSkillStore
                .functionBindingResolution(
                    for: function,
                    actionID: action.id
                )
        case .researcher:
            method = try await services.researchSkillStore
                .profileActionBindingResolution(
                    for: function,
                    actionID: action.id
                )
        }
        guard method.issue == nil,
              let package = method.package,
              package.id == request.requestedAction.packageID,
              package.revision == request.requestedAction.skillRevision else {
            return false
        }

        return true
    }

    private func currentAgentChangeTarget(
        _ target: AgentNoteChangeTarget
    ) async throws -> ResearchActionNoteSnapshot? {
        guard let snapshot = currentSnapshot.document(id: target.note),
                  snapshot.lifecycle == .active,
                  snapshot.stableIdentity.resolvedID == target.noteID,
                  snapshot.fingerprint == target.expectedFingerprint,
                  Self.actionRole(
                    for: try vault(id: target.note.vaultID).role
                  ) == target.role,
                  let identity = try await services.controlStore.identityRecord(
                    vaultID: target.note.vaultID,
                    relativePath: target.note.relativePath
                  ),
                  identity.id == target.noteID else {
            return nil
        }
        let document = try await repository(vaultID: target.note.vaultID)
            .load(relativePath: target.note.relativePath)
        guard document.fingerprint == target.expectedFingerprint else {
            return nil
        }
        return ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            lifecycle: snapshot.lifecycle,
            fingerprint: target.expectedFingerprint,
            title: ResearchNoteTitleResolver.resolve(
                document: snapshot.document,
                vaultRole: snapshot.vaultRole
            ).title
        )
    }

    /// A normal completion may be the provenance for a separately authorized
    /// continuation. Cancellation or stale/incomplete completion evidence may
    /// not keep or revive an unresolved change request.
    static func parentPermitsChangeRequest(
        _ record: LocalResearchExecutionRecord
    ) -> Bool {
        guard let completion = record.completion else { return true }
        return completion.state == .complete
    }

    private func makeAgentNoteChangeContinuationPlan(
        request: AgentNoteChangeRequest,
        allowedNoteIDs: [UUID]
    ) async throws -> AgentNoteChangeContinuationPlan {
        let allowed = Set(allowedNoteIDs)
        guard !allowed.isEmpty,
              allowed.count == allowedNoteIDs.count,
              allowed.isSubset(of: Set(request.targets.map(\.noteID))),
              let parent = try await services.localResearchExecutionStore
                .recordIfPresent(id: request.parentRunID),
              Self.parentPermitsChangeRequest(parent) else {
            throw AgentNoteChangeOperationError.continuationUnavailable(
                request.id
            )
        }
        let groupID = parent.snapshot.continuationLineage?.groupID
            ?? parent.snapshot.runID
        return try AgentNoteChangeContinuationPlan(
            groupID: groupID,
            parentRunID: request.parentRunID,
            requestID: request.id,
            childPhases: allowed.map {
                AgentNoteChangeChildPhasePlan(noteID: $0)
            }
        )
    }

    func agentNoteChangeContinuations(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeContinuationResult {
        try requireActive()
        let coordinationID = try await beginAgentNoteChangeCoordination()
        defer { endAgentNoteChangeCoordination(coordinationID) }

        let record = try await services.agentNoteChangeRequestStore.record(
            id: id,
            now: now
        )
        guard record.decision.state == .allowedSubset,
              let plan = record.continuationPlan,
              plan.parentRunID == record.request.parentRunID,
              plan.requestID == record.id,
              let parent = try await services.localResearchExecutionStore
                .recordIfPresent(id: record.request.parentRunID),
              Self.parentPermitsChangeRequest(parent) else {
            throw AgentNoteChangeOperationError.continuationUnavailable(id)
        }

        var existingChildren: [UUID: LocalResearchExecutionRecord] = [:]
        for phase in plan.childPhases {
            if let existing = try await services.localResearchExecutionStore
                .recordIfPresent(id: phase.runID) {
                existingChildren[phase.runID] = existing
            }
        }
        var isExactReplay = existingChildren.count == plan.childPhases.count
        if !existingChildren.isEmpty, !isExactReplay {
            let lineage = ResearchContinuationLineage(
                groupID: plan.groupID,
                parentRunID: plan.parentRunID,
                requestID: plan.requestID,
                kind: .approvedAction
            )
            for phase in plan.childPhases {
                guard let existing = existingChildren[phase.runID],
                      let target = record.request.targets.first(where: {
                          $0.noteID == phase.noteID
                      }) else { continue }
                try validatePreparedAgentContinuation(
                    existing,
                    record: record,
                    target: target,
                    lineage: lineage
                )
                guard existing.completion == nil
                        || existing.completion?.state == .cancelled,
                      existing.grant?.state != .completed else {
                    throw AgentNoteChangeOperationError.continuationUnavailable(id)
                }
            }
            for existing in existingChildren.values {
                try await discardFailedAgentContinuation(
                    existing,
                    lineage: lineage
                )
            }
            existingChildren.removeAll()
            isExactReplay = false
        }
        if !isExactReplay,
           !(try await isCurrentAgentNoteChangeRequest(record.request)) {
            throw AgentNoteChangeOperationError.continuationUnavailable(id)
        }

        var createdRunIDs: [UUID] = []
        do {
            let contextNotes = isExactReplay
                ? []
                : try await agentContinuationContextNotes(parent: parent)
            var children: [AgentNoteChangeChildPreparation] = []
            for phase in plan.childPhases {
                try Task.checkCancellation()
                guard let requestedTarget = record.request.targets.first(where: {
                    $0.noteID == phase.noteID
                }) else {
                    throw AgentNoteChangeOperationError.continuationUnavailable(id)
                }
                let lineage = ResearchContinuationLineage(
                    groupID: plan.groupID,
                    parentRunID: plan.parentRunID,
                    requestID: plan.requestID,
                    kind: .approvedAction
                )
                let preparation: ResearchFunctionPreparation
                if let existing = existingChildren[phase.runID] {
                    try validatePreparedAgentContinuation(
                        existing,
                        record: record,
                        target: requestedTarget,
                        lineage: lineage
                    )
                    preparation = try await researchFunctionRun(id: phase.runID)
                } else {
                    guard let target = try await currentAgentChangeTarget(
                        requestedTarget
                    ) else {
                        throw AgentNoteChangeOperationError.continuationUnavailable(id)
                    }
                    let availability = try await researchActionAvailability(
                        for: target
                    )
                    guard let action = availability.first(where: {
                        $0.definition == record.request.requestedAction.definition
                            && $0.profile.origin
                                == record.request.requestedAction.profileOrigin
                            && $0.profile.profileRevision
                                == record.request.requestedAction.profileRevision
                            && $0.profile.profileDocumentRevision
                                == record.request.requestedAction
                                    .profileDocumentRevision
                    }), action.isEnabled else {
                        throw AgentNoteChangeOperationError.continuationUnavailable(id)
                    }
                    let parameters = agentContinuationParameterValues(
                        for: action.profile.profile,
                        target: target,
                        contextNotes: contextNotes
                    )
                    let execution = try await resolvedResearchActionExecution(
                        ResearchActionExecutionRequest(
                            actionID: action.id,
                            expectedExecutionKind: action.definition.executionKind,
                            expectedProfileRevision: action.profile.profileRevision,
                            expectedProfileDocumentRevision:
                                action.profile.profileDocumentRevision,
                            target: target,
                            parameterValues: parameters
                        )
                    )
                    guard execution.context.authority.writableNotes == [target],
                          !execution.context.authority.writeOperations.isEmpty,
                          Set(execution.context.authority.writeOperations)
                            .isSubset(of: Set(record.request.operations)) else {
                        throw AgentNoteChangeOperationError.continuationUnavailable(id)
                    }
                    preparation = try await prepareResearchFunction(
                        execution.request,
                        actionContext: execution.context,
                        runIDOverride: phase.runID,
                        continuationLineage: lineage,
                        requiresAutomaticCheckpoint: true,
                        suppressRefresh: true
                    )
                    createdRunIDs.append(phase.runID)
                }
                children.append(AgentNoteChangeChildPreparation(
                    noteID: phase.noteID,
                    preparation: preparation
                ))
            }

            let requestRemainsCurrent = isExactReplay
                ? true
                : try await isCurrentAgentNoteChangeRequest(record.request)
            guard requestRemainsCurrent,
                  let currentParent = try await services.localResearchExecutionStore
                    .recordIfPresent(id: record.request.parentRunID),
                  Self.parentPermitsChangeRequest(currentParent) else {
                throw AgentNoteChangeOperationError.continuationUnavailable(id)
            }
            return AgentNoteChangeContinuationResult(
                record: record,
                childPreparations: children
            )
        } catch {
            for runID in createdRunIDs {
                if let existing = try? await services.localResearchExecutionStore
                    .record(id: runID),
                   let lineage = existing.snapshot.continuationLineage {
                    do {
                        try await discardFailedAgentContinuation(
                            existing,
                            lineage: lineage
                        )
                    } catch {
                        try? await cancelResearchFunction(runID: runID)
                    }
                }
            }
            scheduleAgentContinuationCleanupRefresh()
            throw error
        }
    }

    private func discardFailedAgentContinuation(
        _ child: LocalResearchExecutionRecord,
        lineage: ResearchContinuationLineage
    ) async throws {
        guard child.snapshot.continuationLineage == lineage,
              let checkpointID = child.snapshot.checkpointID else {
            throw AgentNoteChangeOperationError.continuationUnavailable(
                lineage.requestID
            )
        }
        try await services.localResearchExecutionStore.discardFailedContinuation(
            runID: child.id,
            expectedLineage: lineage
        )
        activeResearchActivityKeys[child.id] = nil
        activeAgentCoordinationKeys[child.id] = nil
        _ = try? await services.checkpointStore.discardAutomaticCheckpoint(
            id: checkpointID
        )
    }

    private func scheduleAgentContinuationCleanupRefresh() {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.refresh(
                publication: .researchRecords,
                failureDisposition: .failed(affectedVaultIDs: [])
            )
        }
    }

    private func validatePreparedAgentContinuation(
        _ child: LocalResearchExecutionRecord,
        record: AgentNoteChangeRequestRecord,
        target: AgentNoteChangeTarget,
        lineage: ResearchContinuationLineage
    ) throws {
        guard child.triptychID == services.manifest.id,
              child.snapshot.runID == child.id,
              child.snapshot.continuationLineage == lineage,
              child.snapshot.checkpointID != nil,
              let action = child.snapshot.actionSnapshot,
              action.target.noteID == target.noteID,
              action.target.note == target.note,
              action.target.fingerprint == target.expectedFingerprint,
              try AgentNoteChangeActionRevision(actionSnapshot: action)
                == record.request.requestedAction,
              action.authority.writableNotes == [action.target],
              !action.authority.writeOperations.isEmpty,
              Set(action.authority.writeOperations).isSubset(
                  of: Set(record.request.operations)
              ),
              child.grant?.activityID == child.id,
              child.grant?.allowedTargets.map(\.noteID) == [target.noteID] else {
            throw AgentNoteChangeOperationError.continuationUnavailable(
                record.id
            )
        }
    }

    private func agentContinuationParameterValues(
        for profile: ResearchActionProfile,
        target: ResearchActionNoteSnapshot,
        contextNotes: [ResearchActionNoteSnapshot]
    ) -> [ResearchActionModuleID: ResearchActionParameterValue] {
        guard let module = profile.modules.first(where: {
            $0.kind == .materialSelector
        }) else { return [:] }
        let readableRoles = Set(profile.capabilities.readableRoles)
        let maximum = module.maximumSelectionCount ?? 0
        let selected = contextNotes.filter {
            $0.noteID != target.noteID && readableRoles.contains($0.role)
        }.prefix(maximum)
        guard !selected.isEmpty else { return [:] }
        return [module.id: .notes(Array(selected))]
    }

    private func agentContinuationContextNotes(
        parent: LocalResearchExecutionRecord
    ) async throws -> [ResearchActionNoteSnapshot] {
        guard let action = parent.snapshot.actionSnapshot else { return [] }
        var result: [ResearchActionNoteSnapshot] = []
        var seen: Set<UUID> = []
        let completion = parent.completion

        for prepared in action.authority.readableNotes {
            let expected: DocumentFingerprint
            if prepared.noteID == action.target.noteID,
               let completion {
                expected = completion.targetFingerprint
            } else if let completed = completion?.materialFingerprints[
                prepared.noteID
            ] {
                expected = completed
            } else {
                expected = prepared.fingerprint
            }
            let requested = try AgentNoteChangeTarget(
                noteID: prepared.noteID,
                note: prepared.note,
                role: prepared.role,
                expectedFingerprint: expected
            )
            guard let current = try await currentAgentChangeTarget(requested) else {
                throw AgentNoteChangeOperationError.continuationUnavailable(
                    parent.snapshot.runID
                )
            }
            if seen.insert(current.noteID).inserted { result.append(current) }
        }

        if let output = parent.snapshot.preparedOutput,
           let expected = completion?.outputFingerprint,
           let identity = try await services.controlStore.identityRecord(
                vaultID: output.note.vaultID,
                relativePath: output.note.relativePath
           ) {
            let requested = try AgentNoteChangeTarget(
                noteID: identity.id,
                note: output.note,
                role: .work,
                expectedFingerprint: expected
            )
            guard let current = try await currentAgentChangeTarget(requested) else {
                throw AgentNoteChangeOperationError.continuationUnavailable(
                    parent.snapshot.runID
                )
            }
            if seen.insert(current.noteID).inserted { result.insert(current, at: 0) }
        }
        return result
    }

    private static func actionRole(
        for vaultRole: VaultRole
    ) -> ResearchActionTargetRole? {
        switch vaultRole {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topic
        case .draftProject: .work
        case .other: nil
        }
    }
}

extension ResearchOperations {
    public func submitAgentNoteChangeRequest(
        _ request: AgentNoteChangeRequest,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        let handle = try await reference.requireHandle()
        let record = try await handle.submitAgentNoteChangeRequest(
            request,
            receivedAt: receivedAt,
            validFor: validFor
        )
        if record.decision.state == .allowedSubset {
            _ = try? await handle.agentNoteChangeContinuations(id: record.id)
        }
        return record
    }

    public func agentNoteChangeRequest(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().agentNoteChangeRequest(id: id, now: now)
    }

    public func pendingAgentNoteChangeRequests(
        now: Date = Date()
    ) async throws -> [AgentNoteChangeRequestRecord] {
        try await reference.requireHandle().pendingAgentNoteChangeRequests(now: now)
    }

    public func submitAgentNoteChangeRequestFromBridge(
        _ request: AgentNoteChangeRequest,
        coordinationKey: String,
        receivedAt: Date = Date(),
        validFor: TimeInterval = 10 * 60
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().submitAgentNoteChangeRequestFromBridge(
            request,
            coordinationKey: coordinationKey,
            receivedAt: receivedAt,
            validFor: validFor
        )
    }

    public func agentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().agentNoteChangeRequestFromBridge(
            id: id,
            coordinationKey: coordinationKey,
            now: now
        )
    }

    public func cancelAgentNoteChangeRequestFromBridge(
        id: UUID,
        coordinationKey: String,
        now: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        try await reference.requireHandle().cancelAgentNoteChangeRequestFromBridge(
            id: id,
            coordinationKey: coordinationKey,
            now: now
        )
    }

    public func resolveAgentNoteChangeRequest(
        id: UUID,
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID] = [],
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        let handle = try await reference.requireHandle()
        let record = try await handle.resolveAgentNoteChangeRequest(
            id: id,
            state: state,
            allowedNoteIDs: allowedNoteIDs,
            decidedAt: decidedAt
        )
        if record.decision.state == .allowedSubset {
            _ = try? await handle.agentNoteChangeContinuations(id: record.id)
        }
        return record
    }

    public func applyStandingPermissionToAgentNoteChangeRequest(
        id: UUID,
        decidedAt: Date = Date()
    ) async throws -> AgentNoteChangeRequestRecord {
        let handle = try await reference.requireHandle()
        let record = try await handle.applyStandingPermissionToAgentNoteChangeRequest(
                id: id,
                decidedAt: decidedAt
            )
        if record.decision.state == .allowedSubset {
            _ = try? await handle.agentNoteChangeContinuations(id: record.id)
        }
        return record
    }

    public func agentNoteChangeContinuations(
        id: UUID,
        now: Date = Date()
    ) async throws -> AgentNoteChangeContinuationResult {
        try await reference.requireHandle().agentNoteChangeContinuations(
            id: id,
            now: now
        )
    }
}
