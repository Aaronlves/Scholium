import Foundation
import ScholiumContracts
import ScholiumCore

public struct ResearchWriteSetExtensionDelivery: Sendable {
    public let record: ResearchWriteSetExtensionRecord?
    public let result: ResearchWriteSetExtensionResult

    public init(
        record: ResearchWriteSetExtensionRecord?,
        result: ResearchWriteSetExtensionResult
    ) {
        self.record = record
        self.result = result
    }
}

func boundedResearchDocumentWriteWarning(_ warnings: [String?]) -> String? {
    let values: [String] = warnings.compactMap { warning -> String? in
        guard let warning, !warning.isEmpty else { return nil }
        return warning
    }
    guard !values.isEmpty else { return nil }
    let separator = "\n"
    let contentBudget = 4_096 - (values.count - 1) * separator.utf8.count
    let perWarningBudget = max(1, contentBudget / values.count)
    return values.map {
        boundedUTF8Prefix($0, maximumByteCount: perWarningBudget)
    }.joined(separator: separator)
}

private func boundedUTF8Prefix(
    _ value: String,
    maximumByteCount: Int
) -> String {
    guard value.utf8.count > maximumByteCount else { return value }
    let ellipsis = "…"
    let contentLimit = max(0, maximumByteCount - ellipsis.utf8.count)
    var result = ""
    var byteCount = 0
    for character in value {
        let text = String(character)
        let nextCount = byteCount + text.utf8.count
        guard nextCount <= contentLimit else { break }
        result.append(character)
        byteCount = nextCount
    }
    return result + (maximumByteCount >= ellipsis.utf8.count ? ellipsis : "")
}

extension WorkspaceRuntime {
    public func extendResearchWriteSet(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteSetExtensionIntent
    ) async throws -> ResearchWriteSetExtensionDelivery {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: true,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.extendResearchWriteSet(
            credential: credential,
            run: run,
            intent: intent
        )
    }

    public func writeResearchDocument(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchDocumentWriteIntent
    ) async throws -> ResearchDocumentWriteResult {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: true,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.writeResearchDocument(
            credential: credential,
            run: run,
            intent: intent
        )
    }

    public func resolveResearchWriteConflict(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteConflictResolutionIntent
    ) async throws -> ResearchWriteConflictResolutionResult {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: true,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.resolveResearchWriteConflict(
            credential: credential,
            run: run,
            intent: intent
        )
    }
}

extension ResearchOperations {
    public func extendAgentWriteSet(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteSetExtensionIntent
    ) async throws -> ResearchWriteSetExtensionResult {
        let handle = try await reference.requireHandle()
        return try await handle.extendResearchWriteSet(
            credential: credential,
            run: run,
            intent: intent
        ).result
    }

    public func writeAgentDocument(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchDocumentWriteIntent
    ) async throws -> ResearchDocumentWriteResult {
        let handle = try await reference.requireHandle()
        return try await handle.writeResearchDocument(
            credential: credential,
            run: run,
            intent: intent
        )
    }

    public func resolveAgentWriteConflict(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteConflictResolutionIntent
    ) async throws -> ResearchWriteConflictResolutionResult {
        let handle = try await reference.requireHandle()
        return try await handle.resolveResearchWriteConflict(
            credential: credential,
            run: run,
            intent: intent
        )
    }

    public func resolveAgentWriteSetExtension(
        requestID: UUID,
        state: ResearchWriteSetExtensionState,
        allowedHandles: [ResearchWriteTargetHandle]
    ) async throws -> ResearchWriteSetExtensionRecord {
        let handle = try await reference.requireHandle()
        return try await handle.resolveResearchWriteSetExtension(
            requestID: requestID,
            state: state,
            allowedHandles: allowedHandles
        )
    }

    public func pendingAgentWriteSetExtensions(
        at now: Date = Date()
    ) async throws -> [ResearchWriteSetExtensionRecord] {
        let handle = try await reference.requireHandle()
        return try await handle.pendingResearchWriteSetExtensions(at: now)
    }

    public func agentWriteSetExtension(
        requestID: UUID,
        at now: Date = Date()
    ) async throws -> ResearchWriteSetExtensionRecord {
        let handle = try await reference.requireHandle()
        return try await handle.researchWriteSetExtension(
            requestID: requestID,
            at: now
        )
    }
}

extension WorkspaceHandle {
    func pendingResearchWriteSetExtensions(
        at now: Date
    ) async throws -> [ResearchWriteSetExtensionRecord] {
        try requireActive()
        let listing = try await services.localResearchExecutionStore.listing()
        guard listing.issues.isEmpty else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        var result: [ResearchWriteSetExtensionRecord] = []
        for execution in listing.records {
            for request in execution.writeSetExtensionRecords where request.isUnresolved {
                if request.expiresAt <= now {
                    _ = try await services.localResearchExecutionStore
                        .resolveWriteSetExtension(
                            runID: request.runID,
                            requestID: request.id,
                            state: .expired,
                            entries: [],
                            decidedAt: now
                        )
                } else {
                    result.append(request)
                }
            }
        }
        return result.sorted { $0.receivedAt < $1.receivedAt }
    }

    func researchWriteSetExtension(
        requestID: UUID,
        at now: Date
    ) async throws -> ResearchWriteSetExtensionRecord {
        try requireActive()
        let listing = try await services.localResearchExecutionStore.listing()
        guard listing.issues.isEmpty,
              let execution = listing.records.first(where: { record in
                  record.writeSetExtensionRecords.contains { $0.id == requestID }
              }),
              let request = execution.writeSetExtensionRecords.first(where: {
                  $0.id == requestID
              }) else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        if request.isUnresolved, request.expiresAt <= now {
            _ = try await services.localResearchExecutionStore
                .resolveWriteSetExtension(
                    runID: request.runID,
                    requestID: request.id,
                    state: .expired,
                    entries: [],
                    decidedAt: now
                )
            return try await services.localResearchExecutionStore
                .writeSetExtension(runID: request.runID, requestID: request.id)
        }
        return request
    }

    func extendResearchWriteSet(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteSetExtensionIntent
    ) async throws -> ResearchWriteSetExtensionDelivery {
        try requireActive()
        let authenticated = try await authenticateResearchAgent(
            credential: credential,
            run: run,
            requiresWrite: true
        )
        var execution = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        let action = try activeResearchAction(execution)
        let platform = try platformAction(action.actionID)
        guard platform.operations.contains(.extendWriteSet),
              platform.operations.contains(.modifyInitialNote) else {
            throw ResearchAgentConnectionError.capabilityUnavailable
        }
        let candidates = try resolveWriteSetCandidates(
            intent.targets,
            runID: authenticated.runID,
            action: action,
            existing: execution.boundedWriteSet
        )
        if candidates.isEmpty {
            let requestID = Self.stableOperationID(
                material: "\(authenticated.runID.uuidString):write-set:already-present"
            )
            return ResearchWriteSetExtensionDelivery(
                record: nil,
                result: ResearchWriteSetExtensionResult(
                    requestID: requestID,
                    state: .continueWithoutChanges,
                    entries: execution.boundedWriteSet.entries.map(
                        ResearchBoundedWriteSetViewEntry.init
                    ),
                    message: "Every requested document is already in this Run's bounded write set."
                )
            )
        }
        guard execution.boundedWriteSet.entries.count + candidates.count
                <= ResearchBoundedWriteSet.maximumEntriesPerRun else {
            throw ResearchBoundedWriteSetError.limitExceeded
        }
        let policy = try await currentCollaborationPolicy()
        let intentDigest = try Self.fingerprint(intent)
        let candidateRevision = try Self.fingerprint(candidates)
        let requestID = Self.stableOperationID(
            material: "\(authenticated.runID.uuidString.lowercased()):write-set:\(intentDigest.sha256):\(candidateRevision.sha256)"
        )
        let now = Date()
        let pending = try ResearchWriteSetExtensionRecord(
            id: requestID,
            runID: authenticated.runID,
            triptychID: authenticated.triptychID,
            intent: intent,
            intentDigest: intentDigest,
            candidates: candidates,
            policy: policy.document.policy,
            policyRevision: policy.revision,
            state: .pending,
            receivedAt: now,
            expiresAt: now.addingTimeInterval(10 * 60)
        )
        execution = try await services.localResearchExecutionStore
            .installWriteSetExtension(pending)
        guard let stored = execution.writeSetExtensionRecords.first(where: {
            $0.id == requestID
        }) else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        if !stored.isUnresolved {
            return extensionDelivery(stored, execution: execution)
        }
        let collaborationRequest = try ResearchCollaborationRequest(
            kind: .writeSetExtension,
            requestedWritableRoles: Set(candidates.map(\.role))
        )
        let disposition = ResearchCollaborationPolicyResolver.evaluate(
            policy: policy.document.policy,
            request: collaborationRequest
        )
        if disposition == .mayProceed {
            _ = try await approveResearchWriteSetExtension(
                stored,
                allowedHandles: candidates.map(\.handle),
                basis: .collaborationPolicy,
                decidedAt: now
            )
            execution = try await services.localResearchExecutionStore.record(
                id: authenticated.runID
            )
        }
        let current = try await services.localResearchExecutionStore
            .writeSetExtension(runID: authenticated.runID, requestID: requestID)
        return extensionDelivery(current, execution: execution)
    }

    func resolveResearchWriteSetExtension(
        requestID: UUID,
        state: ResearchWriteSetExtensionState,
        allowedHandles: [ResearchWriteTargetHandle],
        decidedAt: Date = Date()
    ) async throws -> ResearchWriteSetExtensionRecord {
        try requireActive()
        let listing = try await services.localResearchExecutionStore.listing()
        guard listing.issues.isEmpty,
              let execution = listing.records.first(where: { record in
                  record.writeSetExtensionRecords.contains { $0.id == requestID }
              }),
              let request = execution.writeSetExtensionRecords.first(where: {
                  $0.id == requestID
              }) else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        guard request.isUnresolved else { return request }
        switch state {
        case .allowedSubset:
            _ = try await approveResearchWriteSetExtension(
                request,
                allowedHandles: allowedHandles,
                basis: .explicitResearcherDecision,
                decidedAt: decidedAt
            )
        case .continueWithoutChanges, .cancelled:
            guard allowedHandles.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidExtensionRecord
            }
            _ = try await services.localResearchExecutionStore
                .resolveWriteSetExtension(
                    runID: request.runID,
                    requestID: request.id,
                    state: state,
                    entries: [],
                    decidedAt: decidedAt
                )
        case .pending, .stale, .expired:
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        return try await services.localResearchExecutionStore.writeSetExtension(
            runID: request.runID,
            requestID: request.id
        )
    }

    func writeResearchDocument(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchDocumentWriteIntent
    ) async throws -> ResearchDocumentWriteResult {
        try requireActive()
        let authenticated = try await authenticateResearchAgent(
            credential: credential,
            run: run,
            requiresWrite: true
        )
        var execution = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        _ = try activeResearchAction(execution)
        guard var entry = execution.boundedWriteSet.entries.first(where: {
            $0.role == intent.role && $0.note.relativePath == intent.relativePath
        }) else {
            throw ResearchBoundedWriteSetError.targetNotAuthorized
        }
        guard entry.state == .ready,
              entry.expiresAt > Date(),
              entry.allowedOperations.contains(intent.operation) else {
            if !entry.allowedOperations.contains(intent.operation) {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        try await validateCurrentPolicy(
            for: entry,
            runID: authenticated.runID
        )
        let requestFingerprint = try Self.fingerprint(intent)
        let intendedRevision = DocumentFingerprint(content: intent.content)
        let baseOperationID = Self.stableOperationID(
            material: "\(authenticated.runID.uuidString.lowercased()):write:\(intent.requestID.uuidString.lowercased())"
        )
        let operationID: UUID
        if let baseWrite = execution.documentWriteRecords.first(where: {
            $0.id == baseOperationID
        }), baseWrite.state == .conflict,
           entry.state == .ready,
           entry.expectedRevision != baseWrite.expectedRevision {
            operationID = Self.stableOperationID(
                material: "\(baseOperationID.uuidString.lowercased()):retry:\(entry.expectedRevision.sha256)"
            )
        } else {
            operationID = baseOperationID
        }

        if let existing = execution.documentWriteRecords.first(where: {
            $0.id == operationID
        }) {
            return try await reconcileOrReturn(
                existing,
                execution: execution,
                entry: entry,
                intent: intent
            )
        }

        let current = try await exactCurrentDocument(for: entry)
        guard current.fingerprint == entry.expectedRevision else {
            let conflict = try ResearchDocumentWriteRecord(
                id: operationID,
                runID: authenticated.runID,
                target: entry.handle,
                actor: .agent,
                operation: intent.operation,
                requestFingerprint: requestFingerprint,
                expectedRevision: entry.expectedRevision,
                intendedRevision: intendedRevision,
                observedRevision: current.fingerprint,
                state: .conflict,
                checkpointID: entry.checkpointID,
                startedAt: Date(),
                finishedAt: Date(),
                warning: "The document changed outside this Run before the write began."
            )
            execution = try await services.localResearchExecutionStore
                .recordDocumentWriteOutcome(conflict, entryState: .conflict)
            entry = try requiredEntry(entry.handle, in: execution)
            return writeResult(conflict, entry: entry)
        }
        if intendedRevision == entry.expectedRevision {
            let unchanged = try ResearchDocumentWriteRecord(
                id: operationID,
                runID: authenticated.runID,
                target: entry.handle,
                actor: .agent,
                operation: intent.operation,
                requestFingerprint: requestFingerprint,
                expectedRevision: entry.expectedRevision,
                intendedRevision: intendedRevision,
                observedRevision: current.fingerprint,
                state: .unchanged,
                checkpointID: entry.checkpointID,
                startedAt: Date(),
                finishedAt: Date()
            )
            execution = try await services.localResearchExecutionStore
                .recordDocumentWriteOutcome(unchanged, entryState: .ready)
            return writeResult(
                unchanged,
                entry: try requiredEntry(entry.handle, in: execution)
            )
        }

        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let writeSetRevision = try execution.boundedWriteSet.authorizationRevision()
        let capability = try await sessions.issueWriteCapability(
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: entry.expectedRevision,
            operationID: operationID
        )
        try await sessions.consumeWriteCapability(
            capability,
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: entry.expectedRevision,
            operationID: operationID
        )
        let startedAt = Date()
        let writing = try ResearchDocumentWriteRecord(
            id: operationID,
            runID: authenticated.runID,
            target: entry.handle,
            actor: .agent,
            operation: intent.operation,
            requestFingerprint: requestFingerprint,
            expectedRevision: entry.expectedRevision,
            intendedRevision: intendedRevision,
            state: .writing,
            checkpointID: entry.checkpointID,
            startedAt: startedAt
        )
        _ = try await services.localResearchExecutionStore.beginDocumentWrite(writing)

        let save = try await saveResearchDocument(
            entry.note,
            changeSet: .exactContent(intent.content),
            expectedRevision: entry.expectedRevision,
            transaction: ResearchDocumentSaveTransaction(
                runID: authenticated.runID,
                operationID: operationID,
                target: entry.handle
            )
        )
        switch save {
        case .committed(let outcome):
            execution = try await services.localResearchExecutionStore
                .finishDocumentWrite(
                    runID: authenticated.runID,
                    operationID: operationID,
                    state: .committed,
                    observedRevision: outcome.committedValue.document.fingerprint,
                    warning: boundedResearchDocumentWriteWarning(
                        outcome.cleanupWarnings.map { Optional($0.message) } + [
                        outcome.derivedRefreshWarning,
                        outcome.identityRecoveryWarning,
                    ]),
                    recoveryRecordID: nil,
                    finishedAt: Date()
                )
        case .notWritten(let reason):
            let state: ResearchDocumentWriteState = switch reason {
            case .conflict:
                .conflict
            case .invalidFrontmatter, .atomicCommitUnsupported:
                .abandoned
            }
            let observedRevision: DocumentFingerprint? = switch reason {
            case .conflict(let current): current
            case .invalidFrontmatter, .atomicCommitUnsupported:
                entry.expectedRevision
            }
            execution = try await services.localResearchExecutionStore
                .finishDocumentWrite(
                    runID: authenticated.runID,
                    operationID: operationID,
                    state: state,
                    observedRevision: observedRevision,
                    warning: documentSaveWarning(reason),
                    recoveryRecordID: nil,
                    finishedAt: Date()
                )
        case .recoveryRequired(let recovery):
            execution = try await services.localResearchExecutionStore
                .finishDocumentWrite(
                    runID: authenticated.runID,
                    operationID: operationID,
                    state: .recoveryRequired,
                    observedRevision: recovery.files.first?.observedRevision,
                    warning: recovery.failure,
                    recoveryRecordID: recovery.id,
                    finishedAt: Date()
                )
        }
        guard let completed = execution.documentWriteRecords.first(where: {
            $0.id == operationID
        }) else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        return writeResult(
            completed,
            entry: try requiredEntry(entry.handle, in: execution)
        )
    }

    func resolveResearchWriteConflict(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchWriteConflictResolutionIntent
    ) async throws -> ResearchWriteConflictResolutionResult {
        try requireActive()
        let authenticated = try await authenticateResearchAgent(
            credential: credential,
            run: run,
            requiresWrite: true
        )
        var execution = try await services.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        _ = try activeResearchAction(execution)
        guard var entry = execution.boundedWriteSet.entries.first(where: {
            $0.role == intent.role && $0.note.relativePath == intent.relativePath
        }) else {
            throw ResearchBoundedWriteSetError.targetNotAuthorized
        }
        let requestFingerprint = try Self.fingerprint(intent)
        let matchingResolutions = execution.writeConflictResolutionRecords.filter {
            $0.clientRequestID == intent.requestID && $0.target == entry.handle
        }
        guard matchingResolutions.allSatisfy({
            $0.requestFingerprint == requestFingerprint && $0.action == intent.action
        }) else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
        }
        let latestConflict = execution.documentWriteRecords
            .filter({ $0.target == entry.handle && $0.state == .conflict })
            .max(by: { $0.startedAt < $1.startedAt })
        if entry.state != .conflict {
            guard let existing = matchingResolutions.max(by: {
                $0.resolvedAt < $1.resolvedAt
            }) else {
                throw ResearchBoundedWriteSetError.staleAuthorization
            }
            return try conflictResolutionResult(existing)
        }
        guard entry.expiresAt > Date(), let latestConflict else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        if let existing = matchingResolutions.first(where: {
            $0.conflictOperationID == latestConflict.id
        }) {
            return try conflictResolutionResult(existing)
        }
        let operationID = Self.stableOperationID(
            material: [
                authenticated.runID.uuidString.lowercased(),
                "write-conflict",
                intent.requestID.uuidString.lowercased(),
                latestConflict.id.uuidString.lowercased(),
            ].joined(separator: ":")
        )
        let now = Date()
        switch intent.action {
        case .refreshAuthority:
            try await validateCurrentPolicy(
                for: entry,
                runID: authenticated.runID
            )
            let current = try await exactCurrentDocument(for: entry)
            let checkpoint = try await services.checkpointStore
                .createResearchContinuation(
                    name: "Before Agent Work",
                    key: Self.checkpointKey(entry),
                    expectedFingerprint: current.fingerprint,
                    roots: services.roots
                )
            do {
                let refreshed = try ResearchBoundedWriteSetEntry(
                    handle: entry.handle,
                    noteID: entry.noteID,
                    note: entry.note,
                    role: entry.role,
                    title: entry.title,
                    allowedOperations: entry.allowedOperations,
                    expectedRevision: current.fingerprint,
                    checkpointID: checkpoint.id,
                    authorizationBasis: entry.authorizationBasis,
                    authorizationPolicy: entry.authorizationPolicy,
                    policyRevision: entry.policyRevision,
                    expiresAt: entry.expiresAt,
                    state: .ready
                )
                let resolution = try ResearchWriteConflictResolutionRecord(
                    id: operationID,
                    clientRequestID: intent.requestID,
                    runID: authenticated.runID,
                    target: entry.handle,
                    conflictOperationID: latestConflict.id,
                    action: intent.action,
                    requestFingerprint: requestFingerprint,
                    priorExpectedRevision: entry.expectedRevision,
                    observedRevision: current.fingerprint,
                    checkpointID: checkpoint.id,
                    state: .readyToRetry,
                    targetView: ResearchBoundedWriteSetViewEntry(refreshed),
                    resolvedAt: now
                )
                execution = try await services.localResearchExecutionStore
                    .resolveWriteConflict(resolution, refreshedEntry: refreshed)
                entry = try requiredEntry(entry.handle, in: execution)
                return try conflictResolutionResult(resolution)
            } catch {
                _ = try? await services.checkpointStore.discardAutomaticCheckpoint(
                    id: checkpoint.id
                )
                throw error
            }
        case .abandonWrite:
            let observed = latestConflict.observedRevision ?? entry.expectedRevision
            entry.state = .abandoned
            let resolution = try ResearchWriteConflictResolutionRecord(
                id: operationID,
                clientRequestID: intent.requestID,
                runID: authenticated.runID,
                target: entry.handle,
                conflictOperationID: latestConflict.id,
                action: intent.action,
                requestFingerprint: requestFingerprint,
                priorExpectedRevision: entry.expectedRevision,
                observedRevision: observed,
                state: .abandoned,
                targetView: ResearchBoundedWriteSetViewEntry(entry),
                resolvedAt: now
            )
            _ = try await services.localResearchExecutionStore
                .resolveWriteConflict(resolution, refreshedEntry: nil)
            return try conflictResolutionResult(resolution)
        }
    }

    private func authenticateResearchAgent(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        requiresWrite: Bool
    ) async throws -> ResearchAuthenticatedRun {
        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: requiresWrite,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == services.manifest.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        return authenticated
    }

    private func activeResearchAction(
        _ execution: LocalResearchExecutionRecord
    ) throws -> ResearchActionSnapshot {
        guard execution.triptychID == services.manifest.id,
              let action = execution.snapshot.actionSnapshot,
              execution.completion == nil else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return action
    }

    private func platformAction(
        _ actionID: ResearchActionID
    ) throws -> PlatformActionDefinition {
        guard let platform = PlatformActionCatalog.definition(for: actionID) else {
            throw ResearchAgentConnectionError.capabilityUnavailable
        }
        return platform
    }

    private func resolveWriteSetCandidates(
        _ selectors: [ResearchWriteSetTargetSelector],
        runID: UUID,
        action: ResearchActionSnapshot,
        existing: ResearchBoundedWriteSet
    ) throws -> [ResearchWriteSetCandidate] {
        let allowed = Set(action.authority.writeOperations.isEmpty
            ? [.modifyMarkdown, .modifyProperties]
            : action.authority.writeOperations)
        var candidates: [ResearchWriteSetCandidate] = []
        for selector in selectors {
            guard Set(selector.operations).isSubset(of: allowed),
                  let vault = currentSnapshot.vaults.first(where: {
                      $0.vault.role == Self.vaultRole(selector.role)
                  }),
                  let note = vault.documents.first(where: {
                      $0.id.relativePath == selector.relativePath
                  }),
                  note.lifecycle == .active,
                  let noteID = note.stableIdentity.resolvedID else {
                throw ResearchBoundedWriteSetError.targetUnavailable
            }
            if existing.entries.contains(where: { $0.noteID == noteID }) { continue }
            candidates.append(try ResearchWriteSetCandidate(
                handle: ResearchWriteTargetHandle(runID: runID, noteID: noteID),
                noteID: noteID,
                note: note.id,
                role: selector.role,
                title: ResearchNoteTitleResolver.resolve(
                    document: note.document,
                    profile: note.schemaProfile
                ).title,
                operations: selector.operations,
                expectedRevision: note.fingerprint
            ))
        }
        return candidates.sorted { $0.handle.rawValue < $1.handle.rawValue }
    }

    private func approveResearchWriteSetExtension(
        _ request: ResearchWriteSetExtensionRecord,
        allowedHandles: [ResearchWriteTargetHandle],
        basis: ResearchWriteSetAuthorizationBasis,
        decidedAt: Date
    ) async throws -> LocalResearchExecutionRecord {
        let allowed = Set(allowedHandles)
        guard !allowed.isEmpty,
              allowed.count == allowedHandles.count,
              allowed.isSubset(of: Set(request.candidates.map(\.handle))) else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        var checkpoints: [UUID] = []
        do {
            var entries: [ResearchBoundedWriteSetEntry] = []
            for candidate in request.candidates where allowed.contains(candidate.handle) {
                let current = try await exactCurrentCandidate(candidate)
                guard current.fingerprint == candidate.expectedRevision else {
                    throw ResearchBoundedWriteSetError.staleAuthorization
                }
                let checkpoint = try await services.checkpointStore
                    .createResearchContinuation(
                        name: "Before Agent Work",
                        key: Self.checkpointKey(candidate),
                        expectedFingerprint: candidate.expectedRevision,
                        roots: services.roots
                    )
                checkpoints.append(checkpoint.id)
                entries.append(try ResearchBoundedWriteSetEntry(
                    handle: candidate.handle,
                    noteID: candidate.noteID,
                    note: candidate.note,
                    role: candidate.role,
                    title: candidate.title,
                    allowedOperations: candidate.operations,
                    expectedRevision: candidate.expectedRevision,
                    checkpointID: checkpoint.id,
                    authorizationBasis: basis,
                    authorizationPolicy: basis == .collaborationPolicy
                        ? request.policy
                        : nil,
                    policyRevision: basis == .collaborationPolicy
                        ? request.policyRevision
                        : nil,
                    expiresAt: decidedAt.addingTimeInterval(24 * 60 * 60)
                ))
            }
            return try await services.localResearchExecutionStore
                .resolveWriteSetExtension(
                    runID: request.runID,
                    requestID: request.id,
                    state: .allowedSubset,
                    entries: entries,
                    decidedAt: decidedAt
                )
        } catch {
            for checkpointID in checkpoints {
                _ = try? await services.checkpointStore.discardAutomaticCheckpoint(
                    id: checkpointID
                )
            }
            throw error
        }
    }

    private func exactCurrentCandidate(
        _ candidate: ResearchWriteSetCandidate
    ) async throws -> NoteDocument {
        guard let snapshot = currentSnapshot.document(id: candidate.note),
              snapshot.stableIdentity.resolvedID == candidate.noteID,
              snapshot.lifecycle == .active else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        let document = try await loadDocument(candidate.note)
        guard document.fingerprint == snapshot.fingerprint else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        return document
    }

    private func exactCurrentDocument(
        for entry: ResearchBoundedWriteSetEntry
    ) async throws -> NoteDocument {
        guard let snapshot = currentSnapshot.document(id: entry.note),
              snapshot.stableIdentity.resolvedID == entry.noteID,
              snapshot.lifecycle == .active else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        return try await loadDocument(entry.note)
    }

    private func validateCurrentPolicy(
        for entry: ResearchBoundedWriteSetEntry,
        runID: UUID
    ) async throws {
        guard entry.authorizationBasis == .collaborationPolicy else { return }
        let current = try await currentCollaborationPolicy()
        guard let original = entry.authorizationPolicy,
              let revision = entry.policyRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        if current.revision == revision, current.document.policy == original { return }
        let request = try ResearchCollaborationRequest(
            kind: .writeSetExtension,
            requestedWritableRoles: [entry.role]
        )
        guard ResearchCollaborationPolicyResolver.evaluate(
            policy: current.document.policy,
            request: request
        ) == .mayProceed else {
            _ = try await services.localResearchExecutionStore
                .markWriteSetEntryStale(
                    runID: runID,
                    handle: entry.handle
                )
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
    }

    private func reconcileOrReturn(
        _ write: ResearchDocumentWriteRecord,
        execution: LocalResearchExecutionRecord,
        entry: ResearchBoundedWriteSetEntry,
        intent: ResearchDocumentWriteIntent
    ) async throws -> ResearchDocumentWriteResult {
        guard write.requestFingerprint == (try Self.fingerprint(intent)),
              write.target == entry.handle,
              entry.role == intent.role,
              entry.note.relativePath == intent.relativePath else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        if write.state == .writing {
            let current = try await exactCurrentDocument(for: entry)
            let state: ResearchDocumentWriteState
            if current.fingerprint == write.intendedRevision {
                state = .committed
            } else if current.fingerprint == write.expectedRevision {
                state = .abandoned
            } else {
                state = .recoveryRequired
            }
            let updated = try await services.localResearchExecutionStore
                .finishDocumentWrite(
                    runID: write.runID,
                    operationID: write.id,
                    state: state,
                    observedRevision: current.fingerprint,
                    warning: state == .recoveryRequired
                        ? "The current bytes match neither the expected nor intended revision."
                        : nil,
                    finishedAt: Date()
                )
            guard let settled = updated.documentWriteRecords.first(where: {
                $0.id == write.id
            }) else { throw ResearchBoundedWriteSetError.invalidWriteRecord }
            return writeResult(
                settled,
                entry: try requiredEntry(entry.handle, in: updated)
            )
        }
        return writeResult(write, entry: entry)
    }

    private func documentSaveWarning(_ reason: VaultSaveNotWrittenReason) -> String? {
        switch reason {
        case .conflict:
            nil
        case .invalidFrontmatter(let message),
             .atomicCommitUnsupported(let message):
            message
        }
    }

    private func requiredEntry(
        _ handle: ResearchWriteTargetHandle,
        in execution: LocalResearchExecutionRecord
    ) throws -> ResearchBoundedWriteSetEntry {
        guard let entry = execution.boundedWriteSet.entry(handle: handle) else {
            throw ResearchBoundedWriteSetError.targetNotAuthorized
        }
        return entry
    }

    private func extensionDelivery(
        _ record: ResearchWriteSetExtensionRecord,
        execution: LocalResearchExecutionRecord
    ) -> ResearchWriteSetExtensionDelivery {
        let message = switch record.state {
        case .pending: "The extension is waiting for one researcher decision."
        case .allowedSubset: "The approved documents are now in this Run's bounded write set."
        case .continueWithoutChanges: "The Run continues without adding documents."
        case .stale: "The extension became stale before authorization."
        case .expired: "The extension expired without granting authority."
        case .cancelled: "The extension was cancelled without granting authority."
        }
        return ResearchWriteSetExtensionDelivery(
            record: record,
            result: ResearchWriteSetExtensionResult(
                requestID: record.id,
                state: record.state,
                entries: execution.boundedWriteSet.entries.map(
                    ResearchBoundedWriteSetViewEntry.init
                ),
                message: message
            )
        )
    }

    private func writeResult(
        _ record: ResearchDocumentWriteRecord,
        entry: ResearchBoundedWriteSetEntry
    ) -> ResearchDocumentWriteResult {
        let message = switch record.state {
        case .writing: "The document write is still being checked."
        case .committed: "The exact document write committed and read back."
        case .unchanged: "The submitted bytes already matched the authorized revision."
        case .conflict: "The document changed; reread it and request fresh authority."
        case .recoveryRequired: "The write result is unknown and requires recovery."
        case .abandoned: "The write was confirmed not to have changed the document."
        }
        return ResearchDocumentWriteResult(
            operationID: record.id,
            state: record.state,
            target: ResearchBoundedWriteSetViewEntry(entry),
            message: message,
            warning: record.warning,
            recoveryRecordID: record.recoveryRecordID
        )
    }

    private func conflictResolutionResult(
        _ record: ResearchWriteConflictResolutionRecord
    ) throws -> ResearchWriteConflictResolutionResult {
        let message = switch record.state {
        case .readyToRetry:
            "Fresh authority is bound to this document. Reread its current Markdown, then retry one write with the intended complete bytes."
        case .abandoned:
            "This conflicted write was explicitly abandoned; the document was not changed by that attempt."
        }
        return try ResearchWriteConflictResolutionResult(
            operationID: record.id,
            state: record.state,
            target: record.targetView,
            message: message
        )
    }

    private static func vaultRole(
        _ role: ResearchActionTargetRole
    ) -> VaultRole {
        switch role {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        case .work: .draftProject
        }
    }

    private static func checkpointKey(
        _ candidate: ResearchWriteSetCandidate
    ) -> TriptychCheckpointFileKey {
        let area: TriptychCheckpointArea = switch candidate.role {
        case .analysis: .analyses
        case .topic: .topics
        case .work: .works
        }
        return TriptychCheckpointFileKey(
            area: area,
            relativePath: candidate.note.relativePath
        )
    }

    private static func checkpointKey(
        _ entry: ResearchBoundedWriteSetEntry
    ) -> TriptychCheckpointFileKey {
        let area: TriptychCheckpointArea = switch entry.role {
        case .analysis: .analyses
        case .topic: .topics
        case .work: .works
        }
        return TriptychCheckpointFileKey(
            area: area,
            relativePath: entry.note.relativePath
        )
    }

    private static func fingerprint<T: Encodable>(
        _ value: T
    ) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(value))
    }

    private static func stableOperationID(material: String) -> UUID {
        let digest = DocumentFingerprint(content: material).sha256
        let value = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }
}
