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

private enum ResearchCreationSourceObservation: Sendable {
    case missing
    case present(NoteDocument)
    case unavailable(String)
}

private enum ResearchCreationIdentityObservation: Sendable {
    case missing
    case present(NoteIdentityRecord)
    case unavailable(String)
}

private struct ResearchCreationObservation: Sendable {
    let source: ResearchCreationSourceObservation
    let identity: ResearchCreationIdentityObservation

    var observedRevision: DocumentFingerprint? {
        guard case .present(let document) = source else { return nil }
        return document.fingerprint
    }
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

    public func writeResearchZoteroBinding(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchZoteroBindingWriteIntent
    ) async throws -> ResearchZoteroBindingWriteResult {
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
        return try await handle.writeResearchZoteroBinding(
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

    public func writeAgentZoteroBinding(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchZoteroBindingWriteIntent
    ) async throws -> ResearchZoteroBindingWriteResult {
        let handle = try await reference.requireHandle()
        return try await handle.writeResearchZoteroBinding(
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
        let candidates = try await resolveWriteSetCandidates(
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
        let newCandidateCount = candidates.filter { candidate in
            !execution.boundedWriteSet.entries.contains {
                $0.noteID == candidate.noteID
            }
        }.count
        guard execution.boundedWriteSet.entries.count + newCandidateCount
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
        let requestFingerprint = try Self.fingerprint(intent)
        let baseOperationID = Self.stableOperationID(
            material: "\(authenticated.runID.uuidString.lowercased()):write:\(intent.requestID.uuidString.lowercased())"
        )
        if let existing = execution.documentWriteRecords.first(where: {
            $0.id == baseOperationID
        }) {
            if existing.state != .conflict
                || intent.operation == .createNote
                || entry.expectedRevision == existing.expectedRevision {
                return try await reconcileOrReturn(
                    existing,
                    execution: execution,
                    entry: entry,
                    intent: intent
                )
            }
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
            runID: authenticated.runID,
            wasUsed: execution.documentWriteRecords.contains {
                $0.target == entry.handle && $0.state == .committed
            }
        )
        if intent.operation == .createNote {
            return try await createResearchDocument(
                credential: credential,
                run: run,
                authenticated: authenticated,
                execution: execution,
                entry: entry,
                intent: intent,
                requestFingerprint: requestFingerprint,
                operationID: baseOperationID
            )
        }

        guard let expectedRevision = entry.expectedRevision,
              let checkpointID = entry.checkpointID else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }

        let current = try await exactCurrentDocument(for: entry)
        let changeSet: NoteChangeSet
        switch intent.operation {
        case .modifyMarkdown:
            guard current.frontmatterState != .malformed else {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            changeSet = .body(intent.content)
        case .modifyProperties:
            let suppliedKeys = Set(intent.properties.map(\.key))
            guard suppliedKeys.isSubset(of: Set(entry.allowedPropertyKeys)) else {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            let plans = Dictionary(
                uniqueKeysWithValues: entry.propertyWritePlans.map { ($0.key, $0) }
            )
            guard intent.properties.allSatisfy({ input in
                guard let plan = plans[input.key],
                      PropertyContractCatalog.supportsTargetedStructuredEditing(
                        input.value,
                        as: plan.valueKind
                      ) else { return false }
                guard let allowedValues = plan.allowedValues else { return true }
                guard case .string(let value) = input.value else { return false }
                return allowedValues.contains(value)
            }) else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            let edits = try Dictionary(uniqueKeysWithValues: intent.properties.map {
                ($0.key, try Self.frontmatterEditValue($0.value))
            })
            changeSet = .frontmatter(edits)
        case .createNote, .setZoteroBinding, .clearZoteroBinding:
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        let candidate = try current.applying(changeSet, timestampKey: nil)
        if intent.operation == .modifyMarkdown {
            let candidateDocument = NoteDocument(
                relativePath: entry.note.relativePath,
                rawContent: candidate
            )
            guard candidateDocument.frontmatterState == current.frontmatterState else {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
        }
        if intent.operation == .modifyProperties {
            let issues = PropertyContractCatalog.validate(
                NoteDocument(
                    relativePath: entry.note.relativePath,
                    rawContent: candidate
                ),
                profile: Self.schemaProfile(for: entry.role)
            )
            guard issues.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
        }
        let intendedRevision = DocumentFingerprint(content: candidate)
        let operationID: UUID
        if let baseWrite = execution.documentWriteRecords.first(where: {
            $0.id == baseOperationID
        }), baseWrite.state == .conflict,
           entry.state == .ready,
           expectedRevision != baseWrite.expectedRevision {
            operationID = Self.stableOperationID(
                material: "\(baseOperationID.uuidString.lowercased()):retry:\(expectedRevision.sha256)"
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
        guard current.fingerprint == expectedRevision else {
            let conflict = try ResearchDocumentWriteRecord(
                id: operationID,
                runID: authenticated.runID,
                target: entry.handle,
                actor: .agent,
                operation: intent.operation,
                requestFingerprint: requestFingerprint,
                expectedRevision: expectedRevision,
                intendedRevision: intendedRevision,
                observedRevision: current.fingerprint,
                state: .conflict,
                checkpointID: checkpointID,
                startedAt: Date(),
                finishedAt: Date(),
                warning: "The document changed outside this Run before the write began."
            )
            execution = try await services.localResearchExecutionStore
                .recordDocumentWriteOutcome(conflict, entryState: .conflict)
            entry = try requiredEntry(entry.handle, in: execution)
            return writeResult(conflict, entry: entry)
        }
        if intendedRevision == expectedRevision {
            let unchanged = try ResearchDocumentWriteRecord(
                id: operationID,
                runID: authenticated.runID,
                target: entry.handle,
                actor: .agent,
                operation: intent.operation,
                requestFingerprint: requestFingerprint,
                expectedRevision: expectedRevision,
                intendedRevision: intendedRevision,
                observedRevision: current.fingerprint,
                state: .unchanged,
                checkpointID: checkpointID,
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
            expectedRevision: expectedRevision,
            operationID: operationID
        )
        try await sessions.consumeWriteCapability(
            capability,
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: expectedRevision,
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
            expectedRevision: expectedRevision,
            intendedRevision: intendedRevision,
            state: .writing,
            checkpointID: checkpointID,
            startedAt: startedAt
        )
        _ = try await services.localResearchExecutionStore.beginDocumentWrite(writing)

        let save = try await saveResearchDocument(
            entry.note,
            changeSet: changeSet,
            expectedRevision: expectedRevision,
            transaction: ResearchDocumentSaveTransaction(
                runID: authenticated.runID,
                operationID: operationID,
                target: entry.handle,
                noteID: entry.noteID,
                role: entry.role
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
            case .targetIdentityChanged, .invalidFrontmatter,
                 .atomicCommitUnsupported:
                .abandoned
            }
            let observedRevision: DocumentFingerprint? = switch reason {
            case .conflict(let current): current
            case .targetIdentityChanged, .invalidFrontmatter,
                 .atomicCommitUnsupported:
                expectedRevision
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
            if case .targetIdentityChanged = reason {
                execution = try await services.localResearchExecutionStore
                    .markWriteSetEntryStale(
                        runID: authenticated.runID,
                        handle: entry.handle
                    )
            }
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

    func writeResearchZoteroBinding(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        intent: ResearchZoteroBindingWriteIntent
    ) async throws -> ResearchZoteroBindingWriteResult {
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
        guard entry.role == .analysis,
              entry.state == .ready,
              entry.expiresAt > Date(),
              entry.allowedOperations.contains(intent.operation),
              intent.operation.isZoteroBindingOperation,
              let expectedRevision = entry.zoteroBindingsRevision else {
            if !entry.allowedOperations.contains(intent.operation) {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        try await validateCurrentPolicy(
            for: entry,
            runID: authenticated.runID,
            wasUsed: execution.documentWriteRecords.contains {
                $0.target == entry.handle && $0.state == .committed
            } || execution.zoteroBindingWriteRecords.contains {
                $0.target == entry.handle && $0.state == .committed
            }
        )
        let currentDocument = try await exactCurrentDocument(for: entry)
        guard currentDocument.fingerprint == entry.expectedRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        let intendedBinding: AnalysisZoteroBinding? = switch intent.operation {
        case .setZoteroBinding:
            try AnalysisZoteroBinding(
                noteID: entry.noteID,
                library: intent.library!,
                itemKey: intent.itemKey!
            )
        case .clearZoteroBinding:
            nil
        case .createNote, .modifyMarkdown, .modifyProperties:
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        let requestFingerprint = try Self.fingerprint(intent)
        let operationID = Self.stableOperationID(
            material: "\(authenticated.runID.uuidString.lowercased()):zotero-binding-write:\(intent.requestID.uuidString.lowercased())"
        )
        if let existing = execution.zoteroBindingWriteRecords.first(where: {
            $0.id == operationID
        }) {
            return try await reconcileOrReturnZoteroBindingWrite(
                existing,
                execution: execution,
                entry: entry,
                intent: intent
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
            expectedRevision: expectedRevision,
            operationID: operationID
        )
        try await sessions.consumeWriteCapability(
            capability,
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: expectedRevision,
            operationID: operationID
        )
        let before = try await services.controlStore.zoteroBindings()
        let startedAt = Date()
        let writing = try ResearchZoteroBindingWriteRecord(
            id: operationID,
            runID: authenticated.runID,
            target: entry.handle,
            operation: intent.operation,
            requestFingerprint: requestFingerprint,
            expectedRevision: expectedRevision,
            intendedBinding: intendedBinding,
            state: .writing,
            startedAt: startedAt
        )
        _ = try await services.localResearchExecutionStore
            .beginZoteroBindingWrite(writing)

        let state: ResearchZoteroBindingWriteState
        let observedRevision: DocumentFingerprint?
        var warning: String?
        do {
            let result: AnalysisZoteroBindingMutationResult
            if let intendedBinding {
                result = try await setPortableZoteroBinding(
                    intendedBinding,
                    expectedRevision: expectedRevision
                )
            } else {
                result = try await clearPortableZoteroBinding(
                    noteID: entry.noteID,
                    expectedRevision: expectedRevision
                )
            }
            observedRevision = result.snapshot.revision
            warning = result.derivedRefreshWarning
            state = before.binding(for: entry.noteID) == intendedBinding
                ? .unchanged
                : .committed
        } catch {
            let observed = try? await services.controlStore.zoteroBindings()
            observedRevision = observed?.revision
            warning = error.localizedDescription
            if observed?.binding(for: entry.noteID) == intendedBinding,
               observed?.revision != expectedRevision {
                state = .committed
            } else if let controlError = error as? TriptychControlError,
                      case .zoteroBindingsRevisionConflict = controlError {
                state = .conflict
            } else if observed?.revision == expectedRevision {
                state = .abandoned
            } else {
                state = .recoveryRequired
            }
        }
        execution = try await services.localResearchExecutionStore
            .finishZoteroBindingWrite(
                runID: authenticated.runID,
                operationID: operationID,
                state: state,
                observedRevision: observedRevision,
                warning: warning,
                finishedAt: Date()
            )
        entry = try requiredEntry(entry.handle, in: execution)
        guard let completed = execution.zoteroBindingWriteRecords.first(where: {
            $0.id == operationID
        }) else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        return zoteroBindingWriteResult(completed, entry: entry)
    }

    private func reconcileOrReturnZoteroBindingWrite(
        _ write: ResearchZoteroBindingWriteRecord,
        execution: LocalResearchExecutionRecord,
        entry: ResearchBoundedWriteSetEntry,
        intent: ResearchZoteroBindingWriteIntent
    ) async throws -> ResearchZoteroBindingWriteResult {
        guard write.requestFingerprint == (try Self.fingerprint(intent)),
              write.target == entry.handle,
              write.operation == intent.operation else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        guard write.state == .writing else {
            return zoteroBindingWriteResult(write, entry: entry)
        }
        let observed = try await services.controlStore.zoteroBindings()
        let state: ResearchZoteroBindingWriteState
        if observed.binding(for: entry.noteID) == write.intendedBinding,
           observed.revision != write.expectedRevision {
            state = .committed
        } else if observed.revision == write.expectedRevision {
            state = .abandoned
        } else {
            state = .recoveryRequired
        }
        let updated = try await services.localResearchExecutionStore
            .finishZoteroBindingWrite(
                runID: write.runID,
                operationID: write.id,
                state: state,
                observedRevision: observed.revision,
                warning: state == .recoveryRequired
                    ? "The portable Zotero binding changed to neither the expected nor intended relationship."
                    : nil,
                finishedAt: Date()
            )
        guard let completed = updated.zoteroBindingWriteRecords.first(where: {
            $0.id == write.id
        }) else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        return zoteroBindingWriteResult(
            completed,
            entry: try requiredEntry(entry.handle, in: updated)
        )
    }

    private func zoteroBindingWriteResult(
        _ write: ResearchZoteroBindingWriteRecord,
        entry: ResearchBoundedWriteSetEntry
    ) -> ResearchZoteroBindingWriteResult {
        let message = switch write.state {
        case .writing: "The Zotero binding write is still in progress."
        case .committed: "The Zotero binding was updated."
        case .unchanged: "The Zotero binding already matched the requested relationship."
        case .conflict: "The Zotero binding changed before the authorized write began."
        case .recoveryRequired: "The Zotero binding outcome requires recovery."
        case .abandoned: "The Zotero binding was not changed."
        }
        return ResearchZoteroBindingWriteResult(
            operationID: write.id,
            state: write.state,
            target: ResearchBoundedWriteSetViewEntry(entry),
            message: message,
            warning: write.warning
        )
    }

    private func createResearchDocument(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        authenticated: ResearchAuthenticatedRun,
        execution initialExecution: LocalResearchExecutionRecord,
        entry: ResearchBoundedWriteSetEntry,
        intent: ResearchDocumentWriteIntent,
        requestFingerprint: DocumentFingerprint,
        operationID: UUID
    ) async throws -> ResearchDocumentWriteResult {
        guard entry.allowedOperations == [.createNote],
              entry.expectsAbsence,
              let settingsRevision = entry.settingsRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        let request = try ManagedNoteCreationRequest(
            vaultID: entry.note.vaultID,
            destination: .exact(relativePath: entry.note.relativePath),
            body: intent.content,
            analysisMetadata: intent.analysisMetadata,
            authority: .authenticatedAgent(
                settingsRevision: settingsRevision,
                reservedIdentity: entry.noteID
            )
        )
        let currentSettings = try await services.controlStore.settings()
        guard currentSettings.revision == settingsRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        let candidate = try managedCreationSource(
            request: request,
            slot: try requiredVaultSlot(for: entry.role),
            settings: currentSettings.settings
        )
        let intendedRevision = DocumentFingerprint(content: candidate)
        try await proveManagedCreationAbsence(
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        )

        guard let sessions = services.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let writeSetRevision = try initialExecution.boundedWriteSet
            .authorizationRevision()
        let capability = try await sessions.issueWriteCapability(
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: nil,
            operationID: operationID
        )
        try await sessions.consumeWriteCapability(
            capability,
            credential: credential,
            run: run,
            writeSetRevision: writeSetRevision,
            target: entry.handle,
            expectedRevision: nil,
            operationID: operationID
        )
        let writing = try ResearchDocumentWriteRecord(
            id: operationID,
            runID: authenticated.runID,
            target: entry.handle,
            actor: .agent,
            operation: .createNote,
            requestFingerprint: requestFingerprint,
            expectedRevision: nil,
            intendedRevision: intendedRevision,
            state: .writing,
            checkpointID: nil,
            startedAt: Date()
        )
        _ = try await services.localResearchExecutionStore.beginDocumentWrite(writing)

        var state: ResearchDocumentWriteState
        var observedRevision: DocumentFingerprint?
        var warning: String?
        var recoveryRecordID: UUID?
        do {
            let outcome = try await createManagedNote(request)
            let commit = outcome.committedValue
            observedRevision = commit.document.fingerprint
            if commit.stableIdentity.resolvedID == entry.noteID,
               observedRevision == intendedRevision,
               outcome.identityRecoveryWarning == nil {
                state = .committed
                warning = boundedResearchDocumentWriteWarning(
                    outcome.cleanupWarnings.map { Optional($0.message) } + [
                        outcome.derivedRefreshWarning,
                    ]
                )
            } else {
                let observation = await observeResearchCreation(entry)
                let classified = classifyResearchCreation(
                    observation,
                    intendedRevision: intendedRevision,
                    reservedIdentity: entry.noteID
                )
                state = classified.state
                observedRevision = classified.observedRevision
                warning = boundedResearchDocumentWriteWarning([
                    outcome.identityRecoveryWarning,
                    "The source or reserved stable identity could not be jointly verified.",
                ])
                if state == .recoveryRequired {
                    recoveryRecordID = try await persistResearchCreationRecovery(
                        write: writing,
                        entry: entry,
                        observation: observation,
                        failure: warning ?? "The created source and reserved identity require recovery."
                    ).id
                }
            }
        } catch let repositoryError as VaultRepositoryError {
            if case .fileAlreadyExists = repositoryError {
                state = .abandoned
                warning = "Another filesystem participant claimed the authorized path before Scholium created the Note."
            } else if case .pathCollision = repositoryError {
                state = .abandoned
                warning = "A comparison-equivalent path appeared before Scholium created the Note."
            } else {
                let observation = await observeResearchCreation(entry)
                let classified = classifyResearchCreation(
                    observation,
                    intendedRevision: intendedRevision,
                    reservedIdentity: entry.noteID
                )
                state = classified.state
                observedRevision = classified.observedRevision
                warning = repositoryError.localizedDescription
                if state == .recoveryRequired {
                    recoveryRecordID = try await persistResearchCreationRecovery(
                        write: writing,
                        entry: entry,
                        observation: observation,
                        failure: warning!
                    ).id
                }
            }
        } catch DocumentCreationError.portableIdentityAlreadyExists {
            state = .abandoned
            warning = "A portable Note identity claimed the authorized path before Scholium created the source."
        } catch CreatedDocumentIdentityRollbackError.sourceRolledBack {
            state = .abandoned
            warning = "Portable identity setup raced another participant, and exact rollback proved that no created source remains."
        } catch {
            let observation = await observeResearchCreation(entry)
            let classified = classifyResearchCreation(
                observation,
                intendedRevision: intendedRevision,
                reservedIdentity: entry.noteID
            )
            state = classified.state
            observedRevision = classified.observedRevision
            warning = error.localizedDescription
            if state == .recoveryRequired {
                recoveryRecordID = try await persistResearchCreationRecovery(
                    write: writing,
                    entry: entry,
                    observation: observation,
                    failure: warning!
                ).id
            }
        }
        let execution = try await services.localResearchExecutionStore
            .finishDocumentWrite(
                runID: authenticated.runID,
                operationID: operationID,
                state: state,
                observedRevision: observedRevision,
                warning: warning,
                recoveryRecordID: recoveryRecordID,
                finishedAt: Date()
            )
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

    private func observeResearchCreation(
        _ entry: ResearchBoundedWriteSetEntry
    ) async -> ResearchCreationObservation {
        let source: ResearchCreationSourceObservation
        do {
            source = .present(try await repository(vaultID: entry.note.vaultID)
                .load(relativePath: entry.note.relativePath))
        } catch VaultRepositoryError.fileDoesNotExist {
            source = .missing
        } catch {
            source = .unavailable(error.localizedDescription)
        }

        let identity: ResearchCreationIdentityObservation
        do {
            if let record = try await services.controlStore.identityRecord(
                vaultID: entry.note.vaultID,
                relativePath: entry.note.relativePath
            ) {
                identity = .present(record)
            } else {
                identity = .missing
            }
        } catch {
            identity = .unavailable(error.localizedDescription)
        }
        return ResearchCreationObservation(source: source, identity: identity)
    }

    private func classifyResearchCreation(
        _ observation: ResearchCreationObservation,
        intendedRevision: DocumentFingerprint,
        reservedIdentity: UUID
    ) -> (state: ResearchDocumentWriteState, observedRevision: DocumentFingerprint?) {
        if case .present(let document) = observation.source,
           document.fingerprint == intendedRevision,
           case .present(let identity) = observation.identity,
           identity.id == reservedIdentity,
           identity.fingerprint == intendedRevision {
            return (.committed, document.fingerprint)
        }
        if case .missing = observation.source,
           case .missing = observation.identity {
            return (.abandoned, nil)
        }
        return (.recoveryRequired, observation.observedRevision)
    }

    private func persistResearchCreationRecovery(
        write: ResearchDocumentWriteRecord,
        entry: ResearchBoundedWriteSetEntry,
        observation: ResearchCreationObservation,
        failure: String
    ) async throws -> TriptychMutationRecoveryRecord {
        let sourceState: TriptychMutationRecoveryState
        let sourceDetail: String
        switch observation.source {
        case .missing:
            sourceState = .missing
            sourceDetail = "The authorized path is currently absent."
        case .present(let document):
            sourceState = document.fingerprint == write.intendedRevision
                ? .intendedBytesRemain
                : .externallyChanged
            sourceDetail = "The authorized path currently has revision \(document.fingerprint.sha256)."
        case .unavailable(let reason):
            sourceState = .unreadable
            sourceDetail = "The authorized path could not be read: \(reason)"
        }
        let identityDetail: String = switch observation.identity {
        case .missing:
            "The reserved stable identity is absent."
        case .present(let identity):
            "The path is assigned identity \(identity.id.uuidString) at revision \(identity.fingerprint.sha256)."
        case .unavailable(let reason):
            "Portable identity state could not be read: \(reason)"
        }
        let recoveryID = Self.stableOperationID(
            material: "\(write.id.uuidString.lowercased()):note-creation-recovery"
        )
        let record = TriptychMutationRecoveryRecord(
            id: recoveryID,
            triptychID: id,
            operation: .noteCreation,
            failure: failure,
            files: [TriptychMutationRecoveryFile(
                vaultID: entry.note.vaultID,
                path: entry.note.relativePath,
                role: .createdNote,
                beforeRevision: nil,
                intendedRevision: write.intendedRevision,
                observedRevision: observation.observedRevision,
                state: sourceState,
                detail: sourceDetail + " " + identityDetail
            )],
            researchWrite: ResearchWriteRecoveryReference(
                runID: write.runID,
                operationID: write.id,
                target: write.target
            )
        )
        do {
            try await services.transactionRecoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return record
    }

    private func requiredVaultSlot(
        for role: ResearchActionTargetRole
    ) throws -> WorkspaceVaultSlot {
        switch role {
        case .analysis: .paperAnalysis
        case .topic: .topicKnowledge
        case .work: .output
        }
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
        guard !entry.expectsAbsence,
              !entry.wasCreated,
              let priorExpectedRevision = entry.expectedRevision else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
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
                runID: authenticated.runID,
                wasUsed: execution.documentWriteRecords.contains {
                    $0.target == entry.handle && $0.state == .committed
                }
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
                    allowedPropertyKeys: entry.allowedPropertyKeys,
                    propertyWritePlans: entry.propertyWritePlans,
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
                    priorExpectedRevision: priorExpectedRevision,
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
            let observed = latestConflict.observedRevision ?? priorExpectedRevision
            entry.state = .abandoned
            let resolution = try ResearchWriteConflictResolutionRecord(
                id: operationID,
                clientRequestID: intent.requestID,
                runID: authenticated.runID,
                target: entry.handle,
                conflictOperationID: latestConflict.id,
                action: intent.action,
                requestFingerprint: requestFingerprint,
                priorExpectedRevision: priorExpectedRevision,
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
    ) async throws -> [ResearchWriteSetCandidate] {
        let platform = try platformAction(action.actionID)
        let allowed = Set(platform.extensionWriteOperations)
        let settings = selectors.contains(where: { $0.operations == [.createNote] })
            ? try await services.controlStore.settings()
            : nil
        let zoteroBindings = selectors.contains(where: {
            $0.operations.contains(where: \.isZoteroBindingOperation)
        }) ? try await services.controlStore.zoteroBindings() : nil
        var candidates: [ResearchWriteSetCandidate] = []
        for selector in selectors {
            guard Set(selector.operations).isSubset(of: allowed),
                  let vault = currentSnapshot.vaults.first(where: {
                      $0.vault.role == Self.vaultRole(selector.role)
                  }) else {
                throw ResearchBoundedWriteSetError.targetUnavailable
            }
            if selector.operations == [.createNote] {
                guard !existing.entries.contains(where: {
                    $0.role == selector.role
                        && $0.note.relativePath == selector.relativePath
                }), let settings else {
                    throw ResearchBoundedWriteSetError.targetUnavailable
                }
                try await proveManagedCreationAbsence(
                    vaultID: vault.vault.id,
                    relativePath: selector.relativePath
                )
                let reservedID = Self.stableOperationID(
                    material: [
                        runID.uuidString.lowercased(),
                        "create-note",
                        selector.role.rawValue,
                        selector.relativePath,
                        settings.revision.fingerprint.sha256,
                    ].joined(separator: ":")
                )
                let note = VaultQualifiedNoteID(
                    vaultID: vault.vault.id,
                    relativePath: selector.relativePath
                )
                let analysisCreationPlans = selector.role == .analysis
                    ? try Self.analysisCreationPlans(settings: settings.settings)
                    : []
                candidates.append(try ResearchWriteSetCandidate(
                    handle: ResearchWriteTargetHandle(
                        runID: runID,
                        noteID: reservedID
                    ),
                    reservedNoteID: reservedID,
                    note: note,
                    role: selector.role,
                    title: URL(fileURLWithPath: selector.relativePath)
                        .deletingPathExtension().lastPathComponent,
                    settingsRevision: settings.revision,
                    analysisCreationPlans: analysisCreationPlans
                ))
                continue
            }
            if let existingEntry = existing.entries.first(where: {
                $0.role == selector.role
                    && $0.note.relativePath == selector.relativePath
            }) {
                guard existingEntry.state == .ready
                        || (existingEntry.state == .consumed
                            && existingEntry.wasCreated),
                      !selector.operations.contains(.createNote) else {
                    throw ResearchBoundedWriteSetError.staleAuthorization
                }
                let note = existingEntry.note
                guard let identity = try await services.controlStore.identityRecord(
                    vaultID: note.vaultID,
                    relativePath: note.relativePath
                ), identity.id == existingEntry.noteID,
                      WorkspaceDocumentLifecycle(
                          relativePath: note.relativePath
                      ) == .active else {
                    throw ResearchBoundedWriteSetError.targetUnavailable
                }
                let document = try await repository(vaultID: note.vaultID)
                    .load(relativePath: note.relativePath)
                guard document.fingerprint == existingEntry.expectedRevision else {
                    throw ResearchBoundedWriteSetError.staleAuthorization
                }
                guard !selector.operations.contains(.modifyMarkdown)
                        || document.frontmatterState != .malformed else {
                    throw ResearchBoundedWriteSetError.operationNotAuthorized
                }
                let priorOperations = Set(
                    existingEntry.allowedOperations.filter { $0 != .createNote }
                )
                let mergedOperations = priorOperations
                    .union(selector.operations)
                    .sorted { $0.rawValue < $1.rawValue }
                let mergedKeys = Set(existingEntry.allowedPropertyKeys)
                    .union(selector.propertyKeys)
                    .sorted()
                let propertyWritePlans = try Self.propertyWritePlans(
                    mergedKeys,
                    role: selector.role,
                    document: document
                )
                let bindingsRevision = mergedOperations.contains(
                    where: \.isZoteroBindingOperation
                ) ? zoteroBindings?.revision : nil
                if Set(mergedOperations) == priorOperations,
                   Set(mergedKeys) == Set(existingEntry.allowedPropertyKeys),
                   bindingsRevision == existingEntry.zoteroBindingsRevision {
                    continue
                }
                candidates.append(try ResearchWriteSetCandidate(
                    handle: existingEntry.handle,
                    noteID: existingEntry.noteID,
                    note: note,
                    role: existingEntry.role,
                    title: existingEntry.title,
                    operations: mergedOperations,
                    expectedRevision: document.fingerprint,
                    propertyKeys: mergedKeys,
                    propertyWritePlans: propertyWritePlans,
                    zoteroBindingsRevision: bindingsRevision
                ))
                continue
            }
            guard let note = vault.documents.first(where: {
                $0.id.relativePath == selector.relativePath
            }), note.lifecycle == .active,
                  let noteID = note.stableIdentity.resolvedID else {
                throw ResearchBoundedWriteSetError.targetUnavailable
            }
            guard !selector.operations.contains(.modifyMarkdown)
                    || note.document.frontmatterState != .malformed else {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            let propertyWritePlans = try Self.propertyWritePlans(
                selector.propertyKeys,
                role: selector.role,
                document: note.document
            )
            let bindingsRevision = selector.operations.contains(
                where: \.isZoteroBindingOperation
            ) ? zoteroBindings?.revision : nil
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
                expectedRevision: note.fingerprint,
                propertyKeys: selector.propertyKeys,
                propertyWritePlans: propertyWritePlans,
                zoteroBindingsRevision: bindingsRevision
            ))
        }
        return candidates.sorted { $0.handle.rawValue < $1.handle.rawValue }
    }

    private func proveManagedCreationAbsence(
        vaultID: UUID,
        relativePath: String
    ) async throws {
        do {
            guard try await services.controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: relativePath
            ) == nil else {
                throw ResearchBoundedWriteSetError.targetUnavailable
            }
        } catch ResearchBoundedWriteSetError.targetUnavailable {
            throw ResearchBoundedWriteSetError.targetUnavailable
        } catch {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        do {
            _ = try await repository(vaultID: vaultID).load(
                relativePath: relativePath
            )
            throw ResearchBoundedWriteSetError.targetUnavailable
        } catch VaultRepositoryError.fileDoesNotExist {
            return
        } catch ResearchBoundedWriteSetError.targetUnavailable {
            throw ResearchBoundedWriteSetError.targetUnavailable
        } catch {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
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
                switch candidate.expectation {
                case .absent(let settingsRevision):
                    let currentSettings = try await services.controlStore.settings()
                    guard currentSettings.revision == settingsRevision else {
                        throw ResearchBoundedWriteSetError.staleAuthorization
                    }
                    try await proveManagedCreationAbsence(
                        vaultID: candidate.note.vaultID,
                        relativePath: candidate.note.relativePath
                    )
                    entries.append(try ResearchBoundedWriteSetEntry(
                        handle: candidate.handle,
                        reservedNoteID: candidate.noteID,
                        note: candidate.note,
                        role: candidate.role,
                        title: candidate.title,
                        settingsRevision: settingsRevision,
                        analysisCreationPlans: candidate.analysisCreationPlans,
                        authorizationBasis: basis,
                        authorizationPolicy: basis == .collaborationPolicy
                            ? request.policy
                            : nil,
                        policyRevision: basis == .collaborationPolicy
                            ? request.policyRevision
                            : nil,
                        expiresAt: decidedAt.addingTimeInterval(24 * 60 * 60)
                    ))
                case .existing(let expectedRevision):
                    let current = try await exactCurrentCandidate(candidate)
                    guard current.fingerprint == expectedRevision else {
                        throw ResearchBoundedWriteSetError.staleAuthorization
                    }
                    if let expectedBindingsRevision = candidate.zoteroBindingsRevision {
                        guard try await services.controlStore.zoteroBindings().revision
                                == expectedBindingsRevision else {
                            throw ResearchBoundedWriteSetError.staleAuthorization
                        }
                    }
                    let checkpoint = try await services.checkpointStore
                        .createResearchContinuation(
                            name: "Before Agent Work",
                            key: Self.checkpointKey(candidate),
                            expectedFingerprint: expectedRevision,
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
                        expectedRevision: expectedRevision,
                        checkpointID: checkpoint.id,
                        allowedPropertyKeys: candidate.propertyKeys,
                        propertyWritePlans: candidate.propertyWritePlans,
                        zoteroBindingsRevision: candidate.zoteroBindingsRevision,
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
        guard let identity = try await services.controlStore.identityRecord(
            vaultID: candidate.note.vaultID,
            relativePath: candidate.note.relativePath
        ), identity.id == candidate.noteID,
              WorkspaceDocumentLifecycle(
                  relativePath: candidate.note.relativePath
              ) == .active,
              Self.vaultRole(candidate.role)
                == (try vault(id: candidate.note.vaultID).role) else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        let document = try await repository(vaultID: candidate.note.vaultID)
            .load(relativePath: candidate.note.relativePath)
        guard document.fingerprint == candidate.expectedRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        return document
    }

    private func exactCurrentDocument(
        for entry: ResearchBoundedWriteSetEntry
    ) async throws -> NoteDocument {
        guard let identity = try await services.controlStore.identityRecord(
            vaultID: entry.note.vaultID,
            relativePath: entry.note.relativePath
        ), identity.id == entry.noteID,
              WorkspaceDocumentLifecycle(
                  relativePath: entry.note.relativePath
              ) == .active,
              Self.vaultRole(entry.role)
                == (try vault(id: entry.note.vaultID).role) else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        return try await repository(vaultID: entry.note.vaultID)
            .load(relativePath: entry.note.relativePath)
    }

    private func validateCurrentPolicy(
        for entry: ResearchBoundedWriteSetEntry,
        runID: UUID,
        wasUsed: Bool
    ) async throws {
        guard entry.authorizationBasis == .collaborationPolicy else { return }
        let current = try await currentCollaborationPolicy()
        guard let original = entry.authorizationPolicy,
              let revision = entry.policyRevision else {
            throw ResearchBoundedWriteSetError.staleAuthorization
        }
        if current.revision == revision, current.document.policy == original { return }
        if wasUsed { return }
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
            let observedRevision: DocumentFingerprint?
            let state: ResearchDocumentWriteState
            var recoveryRecordID: UUID?
            if write.operation == .createNote {
                let observation = await observeResearchCreation(entry)
                let classified = classifyResearchCreation(
                    observation,
                    intendedRevision: write.intendedRevision,
                    reservedIdentity: entry.noteID
                )
                observedRevision = classified.observedRevision
                state = classified.state
                if state == .recoveryRequired {
                    recoveryRecordID = try await persistResearchCreationRecovery(
                        write: write,
                        entry: entry,
                        observation: observation,
                        failure: "The current source and reserved identity do not jointly prove the authorized creation outcome."
                    ).id
                }
            } else {
                let current = try await exactCurrentDocument(for: entry)
                observedRevision = current.fingerprint
                if current.fingerprint == write.intendedRevision {
                    state = .committed
                } else if current.fingerprint == write.expectedRevision {
                    state = .abandoned
                } else {
                    state = .recoveryRequired
                }
            }
            let updated = try await services.localResearchExecutionStore
                .finishDocumentWrite(
                    runID: write.runID,
                    operationID: write.id,
                    state: state,
                    observedRevision: observedRevision,
                    warning: state == .recoveryRequired
                        ? "The current source and identity do not match the authorized expected or intended state."
                        : nil,
                    recoveryRecordID: recoveryRecordID,
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
        case .targetIdentityChanged:
            "The authorized path no longer belongs to the same portable Note identity. No source was written."
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
            "Fresh authority is bound to this document. Reread its current Markdown, then retry the intended body or exact property edits."
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

    private static func analysisCreationPlans(
        settings: TriptychSettings
    ) throws -> [ResearchAnalysisCreationSourcePlan] {
        let seed = settings.properties[.paperAnalysis]?.newNoteYAML
        let seedKeys = try TriptychSettingsValidator.seedKeys(
            in: seed,
            role: .paperAnalysis
        )
        return try AnalysisSourceType.allCases.map { sourceType in
            let profile = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
            let required = Set(
                settings.analysisAgentCreation.requiredFields(for: sourceType)
            )
            let fields = try profile.serializationFieldOrder.compactMap {
                key -> ResearchAnalysisCreationFieldPlan? in
                guard key != "type", !seedKeys.contains(key),
                      let contract = PropertyContractCatalog.contract(
                        for: key,
                        profile: .analysis
                      ) else { return nil }
                return try ResearchAnalysisCreationFieldPlan(
                    key: key,
                    valueKind: contract.valueKind,
                    allowedValues: contract.allowedValues,
                    isRequired: required.contains(key)
                )
            }
            return try ResearchAnalysisCreationSourcePlan(
                sourceType: sourceType,
                fields: fields
            )
        }
    }

    private static func propertyWritePlans(
        _ keys: [String],
        role: ResearchActionTargetRole,
        document: NoteDocument
    ) throws -> [ResearchPropertyWriteFieldPlan] {
        guard !keys.isEmpty else { return [] }
        guard document.frontmatterState == .valid else {
            throw ResearchBoundedWriteSetError.operationNotAuthorized
        }
        let profile = schemaProfile(for: role)
        let otherProfiles = SchemaProfileID.allCases.filter { $0 != profile }
        return try keys.sorted().map { key in
            if let contract = PropertyContractCatalog.contract(
                for: key,
                profile: profile
            ) {
                return try ResearchPropertyWriteFieldPlan(
                    key: key,
                    valueKind: contract.valueKind,
                    allowedValues: contract.allowedValues
                )
            }
            let isCanonicalElsewhere = otherProfiles.contains { candidate in
                PropertyContractCatalog.contract(for: key, profile: candidate) != nil
            }
            guard !isCanonicalElsewhere,
                  let value = document.parsedFrontmatter[key],
                  let valueKind = observedCustomPropertyKind(value) else {
                throw ResearchBoundedWriteSetError.operationNotAuthorized
            }
            return try ResearchPropertyWriteFieldPlan(
                key: key,
                valueKind: valueKind
            )
        }
    }

    private static func observedCustomPropertyKind(
        _ value: YAMLValue
    ) -> PropertyValueKind? {
        switch value {
        case .string(let text):
            text.contains("\n") ? .multilineText : .text
        case .integer, .double:
            .number
        case .boolean:
            .boolean
        case .array(let values) where values.allSatisfy({
            if case .string = $0 { return true }
            return false
        }):
            .textList
        case .array, .object, .null:
            nil
        }
    }

    private static func schemaProfile(
        for role: ResearchActionTargetRole
    ) -> SchemaProfileID {
        switch role {
        case .analysis: .analysis
        case .topic: .topicMarkdown
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
