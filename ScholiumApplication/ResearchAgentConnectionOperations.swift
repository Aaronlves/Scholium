import Darwin
import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchAgentConnectionDependencies: Sendable {
    let localResearchExecutionStore: LocalResearchExecutionStore
    let creationReservationStore: AgentAnalysisCreationReservationStore
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let controlStore: TriptychControlStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
}

extension WorkspaceServices {
    var researchAgentConnectionDependencies:
        WorkspaceResearchAgentConnectionDependencies {
        WorkspaceResearchAgentConnectionDependencies(
            localResearchExecutionStore: localResearchExecutionStore,
            creationReservationStore: agentAnalysisCreationReservationStore,
            researchAgentSessions: researchAgentSessions,
            controlStore: controlStore,
            transactionRecoveryStore: transactionRecoveryStore
        )
    }
}

extension WorkspaceRuntime {
    public func preflightResearchAgentAnalysisCreation(
        triptychID: UUID,
        request: ResearchAgentAnalysisCreationPreflightRequest
    ) async throws -> ResearchAgentAnalysisCreationPreflight {
        let handle = try await openWorkspace(id: triptychID)
        return try await handle.preflightResearchAgentAnalysisCreation(request)
    }

    public func startResearchAgentRun(
        triptychID: UUID,
        request: ResearchAgentStartRequest,
        sessionValidity: TimeInterval = 8 * 60 * 60
    ) async throws -> ResearchAgentStartedSession {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let handle = try await openWorkspace(id: triptychID)
        let started: (preparation: ResearchActionPreparation, target: ResearchActionNoteSnapshot)
        if request.newAnalysis != nil {
            started = try await handle.startNewAnalysisResearchAgentRun(request)
        } else {
            started = try await handle.startResearchAgentRun(request)
        }
        do {
            let session = try await sessions.issueAgentSession(
                runID: started.preparation.runID,
                triptychID: triptychID,
                canWrite: !started.preparation.snapshot.authority.writableNotes.isEmpty,
                sessionValidity: sessionValidity
            )
            let receipt = try ResearchAgentStartReceipt(
                run: session.run,
                actionID: started.preparation.snapshot.actionID,
                target: started.preparation.snapshot.target,
                state: started.preparation.state,
                message: "The Agent-originated Run is active. Fetch its authenticated context before continuing."
            )
            return ResearchAgentStartedSession(
                receipt: receipt,
                credential: session.credential
            )
        } catch {
            await sessions.revokeRun(started.preparation.runID)
            throw error
        }
    }

    public func researchAgentWorkspaceID(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        allowFinalized: Bool = false
    ) async throws -> UUID {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        return try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: allowFinalized
        ).triptychID
    }

    public func pairResearchAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval = 8 * 60 * 60
    ) async throws -> ResearchConnectionCredential {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let credential = try await sessions.exchange(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        do {
            let handle = try await openWorkspace(id: authenticated.triptychID)
            try await handle.validateActiveResearchAgentRun(authenticated.runID)
            return credential
        } catch {
            await sessions.revokeSession(credential.sessionID)
            throw error
        }
    }

    public func revokeResearchAgentSession(
        credential: ResearchConnectionCredential
    ) async throws -> ResearchAgentSessionRevocationReceipt {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        try await sessions.revokeSession(authenticating: credential)
        return ResearchAgentSessionRevocationReceipt(
            sessionID: credential.sessionID
        )
    }

    public func researchAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.authenticatedResearchAgentContext(
            credential: credential,
            run: run
        )
    }

    public func queryResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest
    ) async throws -> ResearchContextResponse {
        guard let sessions = researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        let handle = try await openWorkspace(id: authenticated.triptychID)
        return try await handle.authenticatedResearchContext(
            credential: credential,
            run: run,
            request: request
        )
    }

    public func endResearchAgentRun(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchRunEndReceipt {
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
        return try await handle.endResearchAgentRun(
            credential: credential,
            run: run
        )
    }
}

extension ResearchOperations {
    public func issueAgentHandoff(
        runID: UUID,
        validity: TimeInterval = 10 * 60
    ) async throws -> ResearchAgentHandoff {
        let handle = try await reference.requireHandle()
        return try await handle.issueResearchAgentHandoff(
            runID: runID,
            validity: validity
        )
    }

    public func pairAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval = 8 * 60 * 60
    ) async throws -> ResearchConnectionCredential {
        let handle = try await reference.requireHandle()
        return try await handle.pairResearchAgent(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
    }

    public func authenticatedAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        let handle = try await reference.requireHandle()
        return try await handle.authenticatedResearchAgentContext(
            credential: credential,
            run: run
        )
    }

    public func queryAgentResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest
    ) async throws -> ResearchContextResponse {
        let handle = try await reference.requireHandle()
        return try await handle.authenticatedResearchContext(
            credential: credential,
            run: run,
            request: request
        )
    }

    public func revokeAgentSession(_ sessionID: UUID) async throws {
        let handle = try await reference.requireHandle()
        try await handle.revokeResearchAgentSession(sessionID)
    }
}

extension WorkspaceHandle {
    func startResearchAgentRun(
        _ request: ResearchAgentStartRequest,
        expectedZoteroBinding: AnalysisZoteroBinding? = nil,
        runIDOverride: UUID? = nil
    ) async throws -> (preparation: ResearchActionPreparation, target: ResearchActionNoteSnapshot) {
        try requireCompleteWorkspace()
        guard let requestedTarget = request.target,
              let note = currentSnapshot.document(id: requestedTarget),
              note.id.vaultID == requestedTarget.vaultID,
              note.id.relativePath == requestedTarget.relativePath,
              let stableID = note.stableIdentity.resolvedID,
              let functionRole = ResearchActionTargetRole(vaultRole: note.vaultRole) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let allowsResearcherProvidedSource =
            request.sourceRoute == .researcherProvided
        guard !allowsResearcherProvidedSource
                || (request.actionID == .analyze && functionRole == .analysis) else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let role: ResearchActionTargetRole = switch functionRole {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
        let target = ResearchActionNoteSnapshot(
            noteID: stableID,
            note: note.id,
            role: role,
            fingerprint: note.fingerprint,
            title: researchActionRunCoordinator.researchActionTitle(for: note)
        )
        let available = try await researchActionAvailability(
            for: target,
            checkingSourceAccess: !allowsResearcherProvidedSource
        )
        guard let action = available.first(where: {
            $0.id == request.actionID
        }) else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                request.actionID
            )
        }
        guard action.isEnabled else {
            if let sourceFailure = action.repairReasons.first(where: {
                $0.code == .sourceAccessRequired
            })?.sourceAccessFailure {
                // Availability is deliberately non-authorizing, but a direct
                // Agent start still needs the same typed repair contract as a
                // later preparation failure. Do not flatten a missing source
                // route into the generic action-unavailable error.
                throw ResearchActionRunContractError.sourceAccessUnavailable(
                    sourceFailure
                )
            }
            throw ResearchActionExecutionContractError.actionUnavailable(
                request.actionID
            )
        }
        let academicInputs = try ResearchAcademicFieldValues(
            rawValues: request.academicInputs,
            definitions: action.profile.profile.academicInputFields
        )
        let execution = ResearchActionExecutionRequest(
            actionID: request.actionID,
            expectedProfileRevision: action.profile.profileRevision,
            expectedProfileDocumentRevision: action.profile.profileDocumentRevision,
            target: target,
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: academicInputs
        )
        let preparation = try await prepareResearchAction(
            execution,
            allowsResearcherProvidedSource: allowsResearcherProvidedSource,
            expectedZoteroBinding: expectedZoteroBinding,
            runIDOverride: runIDOverride
        )
        guard preparation.state == .prepared else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return (preparation, target)
    }

    /// Resolves one classification-bounded Analysis destination and current
    /// Settings plan without creating a Note, identity, Run, or Session.
    func preflightResearchAgentAnalysisCreation(
        _ request: ResearchAgentAnalysisCreationPreflightRequest
    ) async throws -> ResearchAgentAnalysisCreationPreflight {
        try requireCompleteWorkspace()
        guard let analysisVaultID = assignment.vault(for: .paperAnalysis)?.id else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let settings = try await researchAgentConnectionDependencies.controlStore.settings()
        let relativePath = request.destination.resolvedRelativePath
        let target = VaultQualifiedNoteID(
            vaultID: analysisVaultID,
            relativePath: relativePath
        )
        let metadataCatalog = NoteMetadataCatalog(settings: settings.settings)
        let applicable = metadataCatalog.analysisContracts(
            for: request.metadata.sourceType
        )
        let preferred = settings.settings.analysisAgentCreation.preferredFields(
            for: request.metadata.sourceType
        )
        let fixedYAMLFields = PropertyContractCatalog.authoredCanonicalKeys
        let runID = Self.agentStartDeterministicID(
            namespace: "agent-start-run",
            triptychID: id,
            requestID: request.requestID
        )
        let reservedIdentity = Self.agentStartDeterministicID(
            namespace: "agent-start-new-analysis",
            triptychID: id,
            requestID: request.requestID
        )
        let requestedBinding = try request.source.map {
            try AnalysisZoteroBinding(
                noteID: reservedIdentity,
                library: $0.library,
                itemKey: $0.itemKey
            )
        }
        let fingerprint = try Self.agentAnalysisCreationRequestFingerprint(request)
        let storedCreation = try await researchAgentConnectionDependencies
            .creationReservationStore.reservationIfPresent(id: runID)
        if let storedCreation,
           storedCreation.target != target
                || storedCreation.reservedIdentityID != reservedIdentity
                || storedCreation.requestedBinding != requestedBinding
                || storedCreation.sourceRoute != request.sourceRoute {
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                status: .replayConflict,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: true,
                    nextStep: .inspectOriginalRequestState
                ),
                message: "This request identity already belongs to different Analysis creation evidence. Scholium made no new change."
            )
        }
        if let storedCreation,
           (storedCreation.initialMetadata != request.metadata
                || storedCreation.initialAuthoredYAML != request.authoredYAML) {
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                status: .replayConflict,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: true,
                    nextStep: .inspectOriginalRequestState
                ),
                message: "This request identity cannot change its original authored YAML, source type, or managed metadata values. Scholium made no new change."
            )
        }
        if let storedCreation,
           storedCreation.requestFingerprint != fingerprint {
            let reservedState = await inspectAgentAnalysisCreationTarget(
                storedCreation.target,
                expectedIdentity: reservedIdentity
            )
            let existingExecution = try await researchAgentConnectionDependencies
                .localResearchExecutionStore.recordIfPresent(id: runID)
            guard existingExecution == nil,
                  reservedState.stableIdentity == nil,
                  reservedState.sourceState == .absent else {
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: reservedState,
                    status: .replayConflict,
                    recovery: AgentOperationRecovery(
                        safeToRetry: false,
                        mustReuseRequestIdentity: true,
                        nextStep: .inspectOriginalRequestState
                    ),
                    message: "Changed input conflicts with committed creation evidence. Scholium made no new change."
                )
            }
            // A request fingerprint may change only while this is still a
            // machine-local reservation with no source, identity, or Run, and
            // only under the immutable-intent check above.
        }

        let observed = await inspectAgentAnalysisCreationTarget(
            target,
            expectedIdentity: storedCreation == nil ? nil : reservedIdentity
        )
        if storedCreation != nil {
            if let observedIdentity = observed.stableIdentity,
               observedIdentity != reservedIdentity {
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    status: .identityOccupied,
                    recovery: AgentOperationRecovery(
                        safeToRetry: false,
                        mustReuseRequestIdentity: false,
                        nextStep: .startExistingAnalysis
                    ),
                    message: "The reserved destination now belongs to another portable Analysis identity. Scholium preserved both identities and made no new change."
                )
            }
            if observed.sourceState == .present,
               observed.stableIdentity == nil {
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    status: .pathOccupied,
                    recovery: AgentOperationRecovery(
                        safeToRetry: false,
                        mustReuseRequestIdentity: false,
                        nextStep: .requestResearcherDistinctFilenameAndPreflight
                    ),
                    message: "The reserved destination is now occupied by source without the reserved identity. Scholium did not overwrite it or invent another filename."
                )
            }
            if [.missing, .inSystemTrash, .missingOrInSystemTrash]
                .contains(observed.sourceState),
               observed.stableIdentity == reservedIdentity {
                return try await missingAgentAnalysisSourcePreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    creationOwned: true
                )
            }
            if observed.sourceState == .unreadable {
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    status: .sourceUnreadable,
                    recovery: AgentOperationRecovery(
                        safeToRetry: false,
                        mustReuseRequestIdentity: true,
                        nextStep: .resolveSourceAccess
                    ),
                    message: "Scholium cannot verify the reserved Analysis source. Restore access and rerun preflight without changing the request identity."
                )
            }
            if let execution = try await researchAgentConnectionDependencies
                .localResearchExecutionStore.recordIfPresent(id: runID) {
                guard observed.stableIdentity == reservedIdentity,
                      observed.sourceState == .present else {
                    return try await makeAgentAnalysisPreflight(
                        request: request,
                        analysisVaultID: analysisVaultID,
                        applicable: applicable,
                        preferred: preferred,
                        fixedYAMLFields: fixedYAMLFields,
                        target: target,
                        observed: observed,
                        status: .replayConflict,
                        recovery: AgentOperationRecovery(
                            safeToRetry: false,
                            mustReuseRequestIdentity: true,
                            nextStep: .inspectOriginalRequestState
                        ),
                        message: "The stored Run has no matching committed Analysis source and identity. Scholium made no new change."
                    )
                }
                if observed.fingerprint
                    != execution.snapshot.actionSnapshot.target.fingerprint {
                    return try await makeAgentAnalysisPreflight(
                        request: request,
                        analysisVaultID: analysisVaultID,
                        applicable: applicable,
                        preferred: preferred,
                        fixedYAMLFields: fixedYAMLFields,
                        target: target,
                        observed: observed,
                        status: .runStale,
                        recovery: AgentOperationRecovery(
                            safeToRetry: false,
                            mustReuseRequestIdentity: false,
                            nextStep: .startNewActionFromCurrentRevision
                        ),
                        message: "The restored Analysis source does not match the frozen Run revision. Inspect it and start a new Analyze Action from the current revision."
                    )
                }
                let status: ResearchAgentAnalysisCreationPreflightStatus =
                    execution.completion == nil ? .runPrepared : .replayConflict
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    status: status,
                    recovery: AgentOperationRecovery(
                        safeToRetry: execution.completion == nil,
                        mustReuseRequestIdentity: true,
                        nextStep: execution.completion == nil
                            ? .retryExactRequest
                            : .inspectOriginalRequestState
                    ),
                    message: execution.completion == nil
                        ? "The same Analysis Run is already prepared. Retry only the exact start request to receive a replacement Session."
                        : "This creation request already reached terminal Run state and cannot start another Run."
                )
            }
            if observed.stableIdentity == reservedIdentity,
               observed.sourceState == .present {
                if let committed = storedCreation?.committedSourceFingerprint,
                   committed != observed.fingerprint {
                    return try await makeAgentAnalysisPreflight(
                        request: request,
                        analysisVaultID: analysisVaultID,
                        applicable: applicable,
                        preferred: preferred,
                        fixedYAMLFields: fixedYAMLFields,
                        target: target,
                        observed: observed,
                        status: .replayConflict,
                        recovery: AgentOperationRecovery(
                            safeToRetry: false,
                            mustReuseRequestIdentity: true,
                            nextStep: .inspectOriginalRequestState
                        ),
                        message: "The committed Analysis source revision changed before Run preparation. Scholium refused exact replay."
                    )
                }
                return try await makeAgentAnalysisPreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    status: .sourceCommittedProjectionPending,
                    recovery: AgentOperationRecovery(
                        safeToRetry: true,
                        mustReuseRequestIdentity: true,
                        nextStep: .retryExactRequest
                    ),
                    message: "The authoritative Analysis source and reserved identity are committed. Retry only the exact start request so Scholium can finish projection and Run preparation."
                )
            }
            // A matching local reservation with no portable identity or source
            // is pre-commit state. Continue through current Settings and
            // metadata validation; do not manufacture a missing identity.
        }

        do {
            let validationRequest = try ManagedNoteCreationRequest(
                vaultID: analysisVaultID,
                destination: .exact(relativePath: target.relativePath),
                authoredYAML: request.authoredYAML,
                analysisMetadata: request.metadata,
                authority: .authenticatedAgent(reservedIdentity: reservedIdentity)
            )
            _ = try managedCreationSource(
                request: validationRequest,
                slot: .paperAnalysis
            )
        } catch let error as DocumentCreationError {
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                observed: observed,
                status: .invalidMetadata,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: true,
                    nextStep: .correctRequest
                ),
                message: error.localizedDescription
            )
        }

        if observed.stableIdentity != nil {
            if [.missing, .inSystemTrash, .missingOrInSystemTrash]
                .contains(observed.sourceState) {
                return try await missingAgentAnalysisSourcePreflight(
                    request: request,
                    analysisVaultID: analysisVaultID,
                    applicable: applicable,
                    preferred: preferred,
                    fixedYAMLFields: fixedYAMLFields,
                    target: target,
                    observed: observed,
                    creationOwned: false
                )
            }
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                observed: observed,
                status: .identityOccupied,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: false,
                    nextStep: .startExistingAnalysis
                ),
                message: "The root destination already belongs to an existing Analysis identity. Start that existing target or ask the researcher for a distinct root filename."
            )
        }
        if observed.sourceState == .present {
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                observed: observed,
                status: .pathOccupied,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: false,
                    nextStep: .requestResearcherDistinctFilenameAndPreflight
                ),
                message: "The exact destination is occupied by source without the requested new identity. Scholium will not overwrite or invent a retry name."
            )
        }
        if observed.sourceState == .unreadable {
            return try await makeAgentAnalysisPreflight(
                request: request,
                analysisVaultID: analysisVaultID,
                applicable: applicable,
                preferred: preferred,
                fixedYAMLFields: fixedYAMLFields,
                target: target,
                observed: observed,
                status: .sourceUnreadable,
                recovery: AgentOperationRecovery(
                    safeToRetry: false,
                    mustReuseRequestIdentity: true,
                    nextStep: .resolveSourceAccess
                ),
                message: "Scholium cannot verify whether the exact destination is absent. Restore access and rerun this preflight."
            )
        }
        let start = ResearchAgentNewAnalysisRequest(preflight: request)
        return ResearchAgentAnalysisCreationPreflight(
            request: request,
            analysisVaultID: analysisVaultID,
            applicableFields: applicable,
            preferredFields: preferred,
            fixedYAMLFields: fixedYAMLFields,
            targetState: observed,
            status: .ready,
            startNewAnalysis: start,
            recovery: AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .startWithReturnedTemplate
            ),
            message: "The managed default resolves this Analysis at the Analyses-vault root. A researcher-selected subfolder requires a researcher-created existing Analysis target."
        )
    }

    /// Starts Analyze only from the exact current preflight contract. A
    /// committed creation record resumes without consulting optional Settings
    /// guidance, so a preference change cannot invalidate source authority.
    func startNewAnalysisResearchAgentRun(
        _ request: ResearchAgentStartRequest
    ) async throws -> (preparation: ResearchActionPreparation, target: ResearchActionNoteSnapshot) {
        guard let creation = request.newAnalysis else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        let runID = Self.agentStartDeterministicID(
            namespace: "agent-start-run",
            triptychID: id,
            requestID: creation.requestID
        )
        let fingerprint = try Self.agentAnalysisStartRequestFingerprint(request)
        if let inFlight = agentAnalysisStartsInFlight[runID] {
            guard inFlight.startRequestFingerprint == fingerprint else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            return try await inFlight.task.value
        }
        let token = UUID()
        let task = Task {
            try await self.performNewAnalysisResearchAgentRun(request)
        }
        agentAnalysisStartsInFlight[runID] = AgentAnalysisStartInFlight(
            token: token,
            startRequestFingerprint: fingerprint,
            task: task
        )
        do {
            let result = try await task.value
            if agentAnalysisStartsInFlight[runID]?.token == token {
                agentAnalysisStartsInFlight[runID] = nil
            }
            return result
        } catch {
            if agentAnalysisStartsInFlight[runID]?.token == token {
                agentAnalysisStartsInFlight[runID] = nil
            }
            throw error
        }
    }

    private func performNewAnalysisResearchAgentRun(
        _ request: ResearchAgentStartRequest
    ) async throws -> (preparation: ResearchActionPreparation, target: ResearchActionNoteSnapshot) {
        try requireCompleteWorkspace()
        guard request.actionID == .analyze,
              let creation = request.newAnalysis,
              request.target == nil,
              request.sourceRoute == nil,
              let analysisVaultID = self.assignment.vault(for: .paperAnalysis)?.id else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        try await validateNewAnalysisAcademicInputs(request.academicInputs)
        let target = VaultQualifiedNoteID(
            vaultID: analysisVaultID,
            relativePath: creation.destination.resolvedRelativePath
        )
        let reservedIdentity = Self.agentStartDeterministicID(
            namespace: "agent-start-new-analysis",
            triptychID: id,
            requestID: creation.requestID
        )
        let runID = Self.agentStartDeterministicID(
            namespace: "agent-start-run",
            triptychID: id,
            requestID: creation.requestID
        )
        let requestFingerprint = try Self.agentAnalysisCreationRequestFingerprint(
            creation.preflight
        )
        let creationPayloadFingerprint = try Self.agentAnalysisCreationPayloadFingerprint(
            creation
        )
        let startRequestFingerprint = try Self.agentAnalysisStartRequestFingerprint(
            request
        )
        let requestedBinding = try creation.source.map {
            try AnalysisZoteroBinding(
                noteID: reservedIdentity,
                library: $0.library,
                itemKey: $0.itemKey
            )
        }

        if let existingRun = try await researchAgentConnectionDependencies
            .localResearchExecutionStore.recordIfPresent(id: runID) {
            let expectedRoute: ResearchAnalysisSourceRoute = creation.source == nil
                ? .researcherProvided
                : .externalZotero
            guard let storedCreation = try await researchAgentConnectionDependencies
                .creationReservationStore.reservationIfPresent(id: runID),
                  storedCreation.requestFingerprint == requestFingerprint,
                  storedCreation.creationPayloadFingerprint
                    == creationPayloadFingerprint,
                  storedCreation.startRequestFingerprint == startRequestFingerprint,
                  storedCreation.target == target,
                  storedCreation.reservedIdentityID == reservedIdentity else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            let snapshotTarget = existingRun.snapshot.actionSnapshot.target
            guard existingRun.snapshot.runID == runID,
                  existingRun.snapshot.actionSnapshot.actionID == .analyze,
                  existingRun.snapshot.request.target.note == target,
                  existingRun.snapshot.analysisSourceRoute == expectedRoute else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            let observed = await inspectAgentAnalysisCreationTarget(
                target,
                expectedIdentity: reservedIdentity
            )
            guard observed.stableIdentity == reservedIdentity else {
                if observed.stableIdentity != nil {
                    throw ResearchAgentConnectionError.analysisIdentityOccupied
                }
                if observed.sourceState == .present {
                    throw ResearchAgentConnectionError.analysisPathOccupied
                }
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            switch observed.sourceState {
            case .present:
                guard observed.fingerprint == snapshotTarget.fingerprint else {
                    throw ResearchAgentConnectionError.runStale(.targetChanged)
                }
            case .missing, .inSystemTrash, .missingOrInSystemTrash:
                throw ResearchAgentConnectionError
                    .analysisIdentitySourceMissingOrTrashed
            case .unreadable:
                throw ResearchAgentConnectionError.analysisSourceUnreadable
            case .absent:
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if let requestedBinding {
                try await requireCurrentAgentAnalysisBinding(
                    runID: runID,
                    expected: requestedBinding
                )
            }
            let preparation = try await researchActionRun(id: runID)
            guard preparation.state == .prepared else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            return (preparation, snapshotTarget)
        }
        let expectedCreation = try AgentAnalysisCreationReservation(
            triptychID: id,
            runID: runID,
            requestFingerprint: requestFingerprint,
            creationPayloadFingerprint: creationPayloadFingerprint,
            startRequestFingerprint: startRequestFingerprint,
            target: target,
            reservedIdentityID: reservedIdentity,
            requestedBinding: requestedBinding,
            sourceRoute: creation.sourceRoute,
            initialMetadata: creation.metadata,
            initialAuthoredYAML: creation.authoredYAML,
            academicPurpose: request.researchRequestText
        )
        var storedCreation = try await researchAgentConnectionDependencies
            .creationReservationStore.reservationIfPresent(id: runID)
        var hasCommittedSourceAndIdentity = false
        if let storedCreation {
            guard Self.matchesAgentAnalysisCreationReservation(
                storedCreation,
                expected: expectedCreation
            ) else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            let observed = await inspectAgentAnalysisCreationTarget(
                target,
                expectedIdentity: reservedIdentity
            )
            if let observedIdentity = observed.stableIdentity,
               observedIdentity != reservedIdentity {
                throw ResearchAgentConnectionError.analysisIdentityOccupied
            }
            if observed.sourceState == .present,
               observed.stableIdentity == nil {
                throw ResearchAgentConnectionError.analysisPathOccupied
            }
            if [.missing, .inSystemTrash, .missingOrInSystemTrash]
                .contains(observed.sourceState),
               observed.stableIdentity == reservedIdentity {
                throw ResearchAgentConnectionError
                    .analysisIdentitySourceMissingOrTrashed
            }
            if observed.sourceState == .unreadable {
                throw ResearchAgentConnectionError.analysisSourceUnreadable
            }
            hasCommittedSourceAndIdentity = observed.stableIdentity == reservedIdentity
                && observed.sourceState == .present
            if storedCreation.requestFingerprint != requestFingerprint,
               hasCommittedSourceAndIdentity {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if storedCreation.startRequestFingerprint != startRequestFingerprint,
               hasCommittedSourceAndIdentity {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if storedCreation.startRequestFingerprint != startRequestFingerprint,
               storedCreation.creationPayloadFingerprint
                == creationPayloadFingerprint {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if let committed = storedCreation.committedSourceFingerprint,
               hasCommittedSourceAndIdentity,
               committed != observed.fingerprint {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
        }
        if storedCreation == nil || !hasCommittedSourceAndIdentity {
            let preflight = try await preflightResearchAgentAnalysisCreation(
                creation.preflight
            )
            guard preflight.status == .ready,
                  preflight.startNewAnalysis == creation else {
                throw Self.creationPreflightError(preflight.status)
            }
            if let currentReservation = storedCreation,
               (currentReservation.initialMetadata != creation.metadata
                    || currentReservation.initialAuthoredYAML
                        != creation.authoredYAML) {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if storedCreation == nil {
                do {
                    storedCreation = try await researchAgentConnectionDependencies
                        .creationReservationStore.create(
                            expectedCreation
                        )
                } catch AgentAnalysisCreationReservationStoreError
                    .reservationAlreadyExists {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                } catch AgentAnalysisCreationReservationStoreError
                    .reservationMismatch {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
            } else if let currentReservation = storedCreation,
                      currentReservation.requestFingerprint != requestFingerprint
                        || currentReservation.creationPayloadFingerprint
                            != creationPayloadFingerprint
                        || currentReservation.startRequestFingerprint
                            != startRequestFingerprint {
                let replacement = try AgentAnalysisCreationReservation(
                    triptychID: expectedCreation.triptychID,
                    runID: expectedCreation.runID,
                    requestFingerprint: expectedCreation.requestFingerprint,
                    creationPayloadFingerprint: expectedCreation.creationPayloadFingerprint,
                    startRequestFingerprint: expectedCreation.startRequestFingerprint,
                    target: expectedCreation.target,
                    reservedIdentityID: expectedCreation.reservedIdentityID,
                    requestedBinding: expectedCreation.requestedBinding,
                    sourceRoute: expectedCreation.sourceRoute,
                    initialMetadata: currentReservation.initialMetadata,
                    initialAuthoredYAML: currentReservation.initialAuthoredYAML,
                    academicPurpose: expectedCreation.academicPurpose
                )
                do {
                    storedCreation = try await researchAgentConnectionDependencies
                        .creationReservationStore.revisePrecommit(
                            expected: currentReservation,
                            replacement: replacement
                        )
                } catch AgentAnalysisCreationReservationStoreError
                    .reservationMismatch {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
            }
        }
        let existingIdentity = try await researchAgentConnectionDependencies
            .controlStore.identityRecord(
                vaultID: target.vaultID,
                relativePath: target.relativePath
            )
        if let existingIdentity, existingIdentity.id != reservedIdentity {
            throw ResearchAgentConnectionError.analysisIdentityOccupied
        }

        let managedRequest = try ManagedNoteCreationRequest(
            vaultID: target.vaultID,
            destination: .exact(relativePath: target.relativePath),
            authoredYAML: creation.authoredYAML,
            analysisMetadata: creation.metadata,
            authority: .authenticatedAgent(reservedIdentity: reservedIdentity)
        )
        let commit: WorkspaceManagedNoteCommit
        if let existingIdentity {
            let existingDocument: NoteDocument
            do {
                existingDocument = try await repository(
                    vaultID: target.vaultID
                ).load(relativePath: target.relativePath)
            } catch VaultRepositoryError.fileDoesNotExist {
                throw ResearchAgentConnectionError
                    .analysisIdentitySourceMissingOrTrashed
            }
            guard existingIdentity.fingerprint == existingDocument.fingerprint else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            commit = WorkspaceManagedNoteCommit(
                id: target,
                vaultRole: .sourceCorpus,
                stableIdentity: .resolved(reservedIdentity),
                document: existingDocument
            )
        } else {
            commit = try await createManagedNote(managedRequest).committedValue
        }
        guard commit.id == target,
              commit.stableIdentity.resolvedID == reservedIdentity else {
            throw ResearchActionExecutionContractError.staleResolution
        }
        _ = try await researchAgentConnectionDependencies.creationReservationStore
            .confirmSource(
                runID: runID,
                fingerprint: commit.document.fingerprint
            )

        // Creation already queued the one Workspace-owned refresh. Await that
        // owner instead of racing it with another generation. A failed
        // projection remains a committed-but-stale result, and an exact retry
        // resumes from the deterministic identity above without creating a
        // duplicate Note.
        _ = try await awaitCommittedSourceProjection(
            id: target,
            stableIdentity: reservedIdentity,
            fingerprint: commit.document.fingerprint
        )

        if let requestedBinding {
            try await establishAgentAnalysisBinding(
                runID: runID,
                expected: requestedBinding
            )
            if let agentStartPostBindingBarrierForTesting {
                try await agentStartPostBindingBarrierForTesting()
            }
        }

        // Re-enter the existing target-based preparation path. This keeps
        // Action/Profile/Method/source-context resolution and Result handling
        // single-owned instead of introducing a parallel Analyze lifecycle.
        let existingTargetRequest = try ResearchAgentStartRequest(
            actionID: request.actionID,
            target: target,
            academicInputs: request.academicInputs,
            sourceRoute: creation.sourceRoute
        )
        return try await startResearchAgentRun(
            existingTargetRequest,
            expectedZoteroBinding: requestedBinding,
            runIDOverride: runID
        )
    }

    private func inspectAgentAnalysisCreationTarget(
        _ target: VaultQualifiedNoteID,
        expectedIdentity: UUID?
    ) async -> ResearchAgentAnalysisTargetState {
        let identity: NoteIdentityRecord?
        do {
            identity = try await researchAgentConnectionDependencies.controlStore
                .identityRecord(
                    vaultID: target.vaultID,
                    relativePath: target.relativePath
                )
        } catch {
            return ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: nil,
                fingerprint: nil,
                sourceState: .unreadable
            )
        }
        if let expectedIdentity,
           let identity,
           identity.id != expectedIdentity {
            return ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: identity.id,
                fingerprint: identity.fingerprint,
                sourceState: .unreadable
            )
        }
        do {
            let document = try await repository(vaultID: target.vaultID)
                .load(relativePath: target.relativePath)
            return ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: identity?.id,
                fingerprint: document.fingerprint,
                sourceState: .present
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            guard identity != nil else {
                return ResearchAgentAnalysisTargetState(
                    target: target,
                    stableIdentity: nil,
                    fingerprint: nil,
                    sourceState: .absent
                )
            }
            let pendingTrash = (try? await researchAgentConnectionDependencies
                .transactionRecoveryStore.pending())?
                .contains(where: { record in
                    record.files.contains(where: {
                        $0.vaultID == target.vaultID
                            && $0.path == target.relativePath
                            && $0.role == .trashedNote
                    })
                }) == true
            return ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: identity?.id,
                fingerprint: identity?.fingerprint,
                sourceState: pendingTrash
                    ? .inSystemTrash
                    : .missingOrInSystemTrash
            )
        } catch {
            return ResearchAgentAnalysisTargetState(
                target: target,
                stableIdentity: identity?.id,
                fingerprint: identity?.fingerprint,
                sourceState: .unreadable
            )
        }
    }

    private func validateNewAnalysisAcademicInputs(
        _ values: [String: ResearchAcademicFieldValue]
    ) async throws {
        guard let snapshot = try await researchActionResolverDependencies
            .researchConfigurationStore.profileSnapshot(),
              let profile = snapshot.document.profile(for: .analyze),
              profile.isEnabled,
              profile.applicableRoles.contains(.analysis) else {
            throw ResearchActionExecutionContractError.actionUnavailable(.analyze)
        }
        _ = try ResearchAcademicFieldValues(
            rawValues: values,
            definitions: profile.academicInputFields
        )
    }

    private func makeAgentAnalysisPreflight(
        request: ResearchAgentAnalysisCreationPreflightRequest,
        analysisVaultID: UUID,
        applicable: [PropertyContract],
        preferred: [String],
        fixedYAMLFields: [String],
        target: VaultQualifiedNoteID,
        observed: ResearchAgentAnalysisTargetState? = nil,
        status: ResearchAgentAnalysisCreationPreflightStatus,
        recovery: AgentOperationRecovery,
        message: String
    ) async throws -> ResearchAgentAnalysisCreationPreflight {
        let targetState = if let observed {
            observed
        } else {
            await inspectAgentAnalysisCreationTarget(target, expectedIdentity: nil)
        }
        return ResearchAgentAnalysisCreationPreflight(
            request: request,
            analysisVaultID: analysisVaultID,
            applicableFields: applicable,
            preferredFields: preferred,
            fixedYAMLFields: fixedYAMLFields,
            targetState: targetState,
            status: status,
            recovery: recovery,
            message: message
        )
    }

    private func missingAgentAnalysisSourcePreflight(
        request: ResearchAgentAnalysisCreationPreflightRequest,
        analysisVaultID: UUID,
        applicable: [PropertyContract],
        preferred: [String],
        fixedYAMLFields: [String],
        target: VaultQualifiedNoteID,
        observed: ResearchAgentAnalysisTargetState,
        creationOwned: Bool
    ) async throws -> ResearchAgentAnalysisCreationPreflight {
        try await makeAgentAnalysisPreflight(
            request: request,
            analysisVaultID: analysisVaultID,
            applicable: applicable,
            preferred: preferred,
            fixedYAMLFields: fixedYAMLFields,
            target: target,
            observed: observed,
            status: .identitySourceMissingOrTrashed,
            recovery: AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: false,
                nextStep: .requestResearcherRecoveryChoice,
                creationBranches: [
                    AgentCreationRecoveryBranch(
                        kind: .restoreOriginalSource,
                        mustReuseRequestIdentity: creationOwned,
                        nextStep: creationOwned
                            ? .retryExactRequest
                            : .startExistingAnalysis
                    ),
                    AgentCreationRecoveryBranch(
                        kind: .explicitlyCreateAtDistinctDestination,
                        mustReuseRequestIdentity: false,
                        nextStep: .requestResearcherDistinctFilenameAndPreflight
                    ),
                ]
            ),
            message: creationOwned
                ? "A request-owned portable Analysis identity remains but its source is missing or in the system Trash. Restore resumes only the original request identity; distinct creation requires a new identity. Scholium made no source change."
                : "An existing portable Analysis identity remains but its source is missing or in the system Trash. Restore returns to the existing Analysis; distinct creation requires a new identity. Scholium made no source change."
        )
    }

    private static func creationPreflightError(
        _ status: ResearchAgentAnalysisCreationPreflightStatus
    ) -> ResearchAgentConnectionError {
        switch status {
        case .invalidMetadata: .invalidAnalysisCreationMetadata
        case .pathOccupied: .analysisPathOccupied
        case .identityOccupied: .analysisIdentityOccupied
        case .identitySourceMissingOrTrashed:
            .analysisIdentitySourceMissingOrTrashed
        case .sourceUnreadable: .analysisSourceUnreadable
        case .replayConflict, .sourceCommittedProjectionPending, .runPrepared:
            .newAnalysisReplayConflict
        case .runStale: .runStale(.targetChanged)
        case .ready: .newAnalysisReplayConflict
        }
    }

    private func establishAgentAnalysisBinding(
        runID: UUID,
        expected: AnalysisZoteroBinding
    ) async throws {
        let store = researchAgentConnectionDependencies.creationReservationStore
        let record = try await store.reservation(id: runID)
        guard record.requestedBinding == expected else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
        let snapshot = try await researchAgentConnectionDependencies.controlStore
            .zoteroBindings()
        let current = snapshot.binding(for: expected.noteID)
        guard let bindingState = record.bindingState else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
        switch bindingState {
        case .reserved, .retryable:
            if let current {
                guard current == expected else {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
                _ = try await store.advanceBinding(
                    runID: runID,
                    to: .committed
                )
            } else {
                _ = try await store.advanceBinding(
                    runID: runID,
                    to: .writing
                )
                do {
                    let result = try await setPortableZoteroBinding(
                        expected,
                        expectedRevision: snapshot.revision
                    )
                    guard result.snapshot.binding(for: expected.noteID) == expected else {
                        throw ResearchAgentConnectionError.newAnalysisReplayConflict
                    }
                    _ = try await store.advanceBinding(
                        runID: runID,
                        to: .committed
                    )
                } catch TriptychControlError.zoteroBindingsRevisionConflict {
                    _ = try? await store.advanceBinding(
                        runID: runID,
                        to: .retryable
                    )
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
            }
        case .writing, .committed:
            guard current == expected else {
                throw ResearchAgentConnectionError.newAnalysisReplayConflict
            }
            if bindingState == .writing {
                _ = try await store.advanceBinding(
                    runID: runID,
                    to: .committed
                )
            }
        }
        try await requireCurrentAgentAnalysisBinding(
            runID: runID,
            expected: expected
        )
    }

    private func requireCurrentAgentAnalysisBinding(
        runID: UUID,
        expected: AnalysisZoteroBinding
    ) async throws {
        let record = try await researchAgentConnectionDependencies
            .creationReservationStore.reservation(id: runID)
        let current = try await researchAgentConnectionDependencies.controlStore
            .zoteroBindings().binding(for: expected.noteID)
        guard record.requestedBinding == expected,
              record.bindingState == .committed,
              current == expected else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
    }

    private static func matchesAgentAnalysisCreationReservation(
        _ existing: AgentAnalysisCreationReservation,
        expected: AgentAnalysisCreationReservation
    ) -> Bool {
        existing.triptychID == expected.triptychID
            && existing.runID == expected.runID
            && existing.target == expected.target
            && existing.reservedIdentityID == expected.reservedIdentityID
            && existing.requestedBinding == expected.requestedBinding
            && existing.sourceRoute == expected.sourceRoute
            && existing.initialMetadata == expected.initialMetadata
            && existing.initialAuthoredYAML == expected.initialAuthoredYAML
            && existing.academicPurpose == expected.academicPurpose
    }

    private static func agentStartDeterministicID(
        namespace: String,
        triptychID: UUID,
        requestID: UUID
    ) -> UUID {
        let material = Data(
            (namespace + "\u{0}" + triptychID.uuidString.lowercased()
                + "\u{0}" + requestID.uuidString.lowercased()).utf8
        )
        let digest = DocumentFingerprint(data: material).sha256
        let value = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }

    private static func agentAnalysisCreationRequestFingerprint(
        _ request: ResearchAgentAnalysisCreationPreflightRequest
    ) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(request))
    }

    private static func agentAnalysisStartRequestFingerprint(
        _ request: ResearchAgentStartRequest
    ) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(request))
    }

    private static func agentAnalysisCreationPayloadFingerprint(
        _ request: ResearchAgentNewAnalysisRequest
    ) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(request))
    }

    func validateActiveResearchAgentRun(_ runID: UUID) async throws {
        try requireActive()
        if let record = try await researchAgentConnectionDependencies.localResearchExecutionStore
            .recordIfPresent(id: runID) {
            _ = try activeAction(in: record)
            return
        }
        let improvement = try await researchAgentConnectionDependencies.localResearchExecutionStore
            .methodImprovement(id: runID)
        guard improvement.state == .prepared || improvement.state == .writing else {
            throw ResearchAgentConnectionError.runUnavailable
        }
    }

    func issueResearchAgentHandoff(
        runID: UUID,
        validity: TimeInterval
    ) async throws -> ResearchAgentHandoff {
        try requireActive()
        let record = try await researchAgentConnectionDependencies.localResearchExecutionStore.record(id: runID)
        let action = try activeAction(in: record)
        guard let sessions = researchAgentConnectionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        return try await sessions.issuePairing(
            runID: runID,
            triptychID: self.id,
            canWrite: !action.authority.writableNotes.isEmpty,
            validity: validity
        )
    }

    func pairResearchAgent(
        run: ResearchRunLocator,
        pairingCode: ResearchPairingCode,
        sessionValidity: TimeInterval
    ) async throws -> ResearchConnectionCredential {
        try requireActive()
        guard let sessions = researchAgentConnectionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let credential = try await sessions.exchange(
            run: run,
            pairingCode: pairingCode,
            sessionValidity: sessionValidity
        )
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == self.id else {
            await sessions.revokeSession(credential.sessionID)
            throw ResearchAgentSessionError.sessionRejected
        }
        try await validateActiveResearchAgentRun(authenticated.runID)
        return credential
    }

    func authenticatedResearchAgentContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchAuthenticatedRunContext {
        try requireActive()
        guard let sessions = researchAgentConnectionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let coreProtocol = try BundledResearchSkillResources.coreProtocol()
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let record = try await researchAgentConnectionDependencies.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        let action: ResearchActionSnapshot
        do {
            action = try activeAction(in: record)
        } catch {
            await sessions.revokeRun(authenticated.runID)
            throw error
        }
        guard action.target.noteID == record.snapshot.request.target.noteID else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        try await validateAuthenticatedAgentRunCurrent(record)
        let runState = Self.agentRunState(
            record.completion?.state ?? .prepared
        )
        let platform = try requiredPlatformAction(action.actionID)
        let shouldDeliverZoteroIntegrationAdapter =
            action.target.role == .analysis
                && record.snapshot.zoteroBibliographicContext != nil
                && platform.operations.contains(.useZotero)
        let zoteroIntegrationAdapter: ResearchZoteroIntegrationAdapter? =
            shouldDeliverZoteroIntegrationAdapter
            ? try BundledResearchSkillResources.zoteroIntegrationAdapter()
            : nil
        let discussionResponseContract = action.actionID == .discuss
            ? record.discussion?.responseContract
            : nil
        let purpose: String? = if case .freeText(let text)? =
            action.academicInputs.values["research-request"] { text } else { nil }
        let fidelityContract = try await authenticatedFidelityContract(
            for: record
        )
        return try ResearchAuthenticatedRunContext(
            coreProtocol: authenticated.shouldDeliverCoreProtocol
                ? coreProtocol
                : nil,
            brief: ResearchRunBrief(
                run: run,
                actionID: action.actionID,
                state: runState,
                initialObjectTitle: action.target.title,
                initialObjectRole: action.target.role,
                academicPurpose: purpose,
                capabilities: Self.capabilities(platform)
            ),
            method: ResearchMethodContext(snapshot: action.method),
            zoteroIntegrationAdapter: zoteroIntegrationAdapter,
            resultContract: action.resultContract,
            fidelityContract: fidelityContract,
            boundedWriteSet: record.boundedWriteSet.entries.map(
                ResearchBoundedWriteSetViewEntry.init
            ),
            continuationHandoff: record.snapshot.continuationHandoff,
            discussionResponseContract: discussionResponseContract,
            nextActions: try await authenticatedAgentNextActions(
                for: record,
                action: action,
                run: run
            )
        )
    }

    func authenticatedFidelityContract(
        for record: LocalResearchExecutionRecord
    ) async throws -> ResearchFidelityRunContract? {
        guard record.snapshot.request.actionID == .checkFidelity else { return nil }
        let evidence = try await effectiveResearchAgentEvidence(for: record)
        var requiredUnavailable: Set<FidelityCheck> = []
        var limitation: String?
        if record.snapshot.request.checks.contains(.citations),
           evidence.isAnalyzeAction,
           evidence.sourceReference == nil {
                requiredUnavailable.insert(.citations)
                limitation = "Scholium has no formal revision-bound source envelope for this Analyze Run. Citation Fidelity must remain unavailable; a URL declared in Note YAML or bibliographic metadata is not verified source evidence."
        }
        return try ResearchFidelityRunContract(
            checks: record.snapshot.request.checks,
            targets: record.snapshot.request.resolvedFidelityTargets,
            materials: record.snapshot.request.materials,
            scope: record.snapshot.request.scope,
            sourceReference: evidence.sourceReference,
            requiredUnavailableChecks: requiredUnavailable,
            evidenceLimitation: limitation,
            inspectionRequests: try fidelityInspectionRequests(
                for: record,
                includeSourceMaterial: evidence.isAnalyzeAction
            )
        )
    }

    func authenticatedResearchContext(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator,
        request: ResearchContextRequest,
        provider: any ResearchContextProviding = FoundationResearchContextProvider()
    ) async throws -> ResearchContextResponse {
        try requireActive()
        guard let sessions = researchAgentConnectionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        let record = try await researchAgentConnectionDependencies.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        let action = try activeAction(in: record)
        try await validateAuthenticatedAgentRunCurrent(record)
        let platform = try requiredPlatformAction(action.actionID)
        try Self.validateResearchContextCapability(
            request,
            platform: platform
        )
        let query = try ResearchContextQuery(
            request: request,
            runID: authenticated.runID,
            triptychID: authenticated.triptychID
        )
        let snapshot = currentSnapshot
        let evidence = try await effectiveResearchAgentEvidence(for: record)
        let response = try await provider.response(
            for: query,
            run: ResearchContextRunEvidence(
                action: action,
                sourceReference: evidence.sourceReference,
                zoteroBibliographicContext:
                    evidence.zoteroBibliographicContext
            ),
            workspace: snapshot,
            access: ResearchContextOwnerAccess(
                search: { [weak self] request in
                    guard let self else {
                        throw ResearchAgentConnectionError.runUnavailable
                    }
                    return try await self.search(request)
                },
                loadDocument: { [weak self] note in
                    guard let self else {
                        throw ResearchAgentConnectionError.runUnavailable
                    }
                    return try await self.loadDocument(note)
                },
                sourceMaterialStatus: { [weak self] in
                    guard let self else {
                        return .repairRequired(.bookmarkUnavailable)
                    }
                    return await self.researchSourceMaterialStatus(
                        for: record.snapshot.request.target.noteID
                    )
                }
            )
        )
        return response
    }

    private func validateAuthenticatedAgentRunCurrent(
        _ record: LocalResearchExecutionRecord
    ) async throws {
        let request = record.snapshot.request
        let expectedTarget = record.boundedWriteSet.entries.first(where: {
            $0.noteID == request.target.noteID
        })?.expectedRevision
            ?? record.completion?.targetFingerprint
            ?? request.target.fingerprint
        do {
            _ = try await researchActionRunCoordinator.validateResearchActionTarget(
                request.target,
                expected: expectedTarget,
                host: self
            )
        } catch ResearchActionRunContractError.targetChanged {
            throw ResearchAgentConnectionError.runStale(.targetChanged)
        } catch ResearchActionRunContractError.targetUnavailable {
            throw ResearchAgentConnectionError.runStale(.targetUnavailable)
        } catch ResearchActionRunContractError.targetIdentityChanged {
            throw ResearchAgentConnectionError.runStale(.targetIdentityChanged)
        } catch {
            throw error
        }
        for material in request.materials {
            do {
                _ = try await researchActionRunCoordinator
                    .validateResearchActionMaterial(
                        material,
                        expected: material.fingerprint,
                        host: self
                    )
            } catch {
                throw ResearchAgentConnectionError.runStale(.materialChanged)
            }
        }
        let evidence = try await effectiveResearchAgentEvidence(for: record)
        if let sourceReference = evidence.sourceReference {
            let status = await researchAgentResultDependencies
                .researchSourceAccessStore.status(
                    analysisNoteID: request.target.noteID
                )
            guard status.state == .available,
                  status.reference == sourceReference else {
                throw ResearchAgentConnectionError.runStale(.sourceChanged)
            }
        }
    }

    private func fidelityInspectionRequests(
        for record: LocalResearchExecutionRecord,
        includeSourceMaterial: Bool
    ) throws -> [ResearchContextRequest] {
        let request = record.snapshot.request
        var clauses: [ResearchContextClause] = try (
            request.resolvedFidelityTargets.map { target in
                try ResearchContextClause(
                    id: Self.stableAgentUUID(
                        runID: record.id,
                        label: "target:\(target.note.vaultID):\(target.note.relativePath)"
                    ),
                    kind: .readNote,
                    note: target.note,
                    expectedFingerprint: target.fingerprint,
                    limit: 1,
                    useEligibility: .contextUse
                )
            } + request.materials.map { material in
                try ResearchContextClause(
                    id: Self.stableAgentUUID(
                        runID: record.id,
                        label: "material:\(material.note.vaultID):\(material.note.relativePath)"
                    ),
                    kind: .readNote,
                    note: material.note,
                    expectedFingerprint: material.fingerprint,
                    limit: 1,
                    useEligibility: .contextUse
                )
            }
        )
        if includeSourceMaterial {
            clauses.append(try ResearchContextClause(
                id: Self.stableAgentUUID(
                    runID: record.id,
                    label: "formal-source-material"
                ),
                kind: .inspectMaterials,
                limit: 1,
                useEligibility: .contextUse
            ))
        }
        var requests: [ResearchContextRequest] = []
        for start in stride(
            from: 0,
            to: clauses.count,
            by: ResearchContextRequest.maximumClauses
        ) {
            let end = min(start + ResearchContextRequest.maximumClauses, clauses.count)
            requests.append(try ResearchContextRequest(
                id: Self.stableAgentUUID(
                    runID: record.id,
                    label: "fidelity-inspection:\(start)"
                ),
                clauses: Array(clauses[start..<end])
            ))
        }
        return requests
    }

    private func authenticatedAgentNextActions(
        for record: LocalResearchExecutionRecord,
        action: ResearchActionSnapshot,
        run: ResearchRunLocator
    ) async throws -> [AgentCommandAction] {
        if action.actionID == .discuss {
            return [
                AgentCommandAction(
                    kind: .reply,
                    label: "Append one attributed Agent turn to this Discussion",
                    command: [
                        "scholium", "agent", "discuss-reply", "--run",
                        run.rawValue, "--from", "-",
                    ],
                    inputTemplate: try Self.agentJSONTemplate([
                        "statement_id": "REPLACE_WITH_STABLE_UUID",
                        "attribution": "REPLACE_WITH_AGENT_NAME",
                        "text": "REPLACE_WITH_ATTRIBUTED_AGENT_TURN",
                    ])
                ),
                AgentCommandAction(
                    kind: .finish,
                    label: "Finish the Discussion after the final durable Agent turn and form its Record",
                    command: [
                        "scholium", "agent", "finish-discussion", "--run",
                        run.rawValue,
                    ]
                ),
            ]
        }
        var actions = try Self.authenticatedWriteActions(
            record.boundedWriteSet.entries,
            run: run
        )
        actions.append(try await authenticatedResultAction(
            for: record,
            action: action,
            run: run
        ))
        return actions
    }

    private func authenticatedResultAction(
        for record: LocalResearchExecutionRecord,
        action: ResearchActionSnapshot,
        run: ResearchRunLocator
    ) async throws -> AgentCommandAction {
        let defaultFidelityFields = ResearchAcademicProfileCatalog
            .defaultProfiles.first(where: { $0.actionID == .checkFidelity })?
            .academicResultFields ?? []
        let derivesDefaultAcademicResults =
            action.actionID == .checkFidelity
                && action.resultContract.academicFields == defaultFidelityFields
        var academicValues: [String: Any] = [:]
        if !derivesDefaultAcademicResults {
            for field in action.resultContract.academicFields
                where field.requirement != .excluded {
                let value: [String: Any] = switch field.kind {
                case .freeText:
                    ["kind": "freeText", "text": "REPLACE_WITH_\(field.fieldID.rawValue)"]
                case .singleChoice:
                    [
                        "kind": "singleChoice",
                        "choice": "REPLACE_WITH_ONE_OF_\(field.choices.map(\.value).joined(separator: "_OR_"))",
                    ]
                case .multipleChoice:
                    [
                        "kind": "multipleChoice",
                        "choices": ["REPLACE_WITH_ZERO_OR_MORE_OF_\(field.choices.map(\.value).joined(separator: "_OR_"))"],
                    ]
                }
                academicValues[field.fieldID.rawValue] = value
            }
        }
        let fidelityContract = action.actionID == .checkFidelity
            ? try await authenticatedFidelityContract(for: record)
            : nil
        let requiredUnavailable = fidelityContract?.requiredUnavailableChecks ?? []
        let evidenceLimitation = fidelityContract?.evidenceLimitation
        let outcomes: [[String: Any]] = action.actionID == .checkFidelity
            ? record.snapshot.request.checks
            .sorted { $0.rawValue < $1.rawValue }
            .map { check in
                let isUnavailable = requiredUnavailable.contains(check)
                return [
                    "check": check.rawValue,
                    "state": isUnavailable
                        ? "unavailable"
                        : "REPLACE_WITH_passed_OR_issues_found_OR_unavailable",
                    "summary": isUnavailable
                        ? evidenceLimitation
                            ?? "Scholium has no formal source envelope for this check."
                        : "REPLACE_WITH_ATTRIBUTED_CHECK_SUMMARY",
                    "findings": isUnavailable
                        ? []
                        : ["REMOVE_FOR_passed_OR_REPLACE_WITH_SPECIFIC_FINDING"],
                ]
            }
            : []
        let template: [String: Any] = [
            "schema_version": ResearchAgentResultSubmission.currentSchemaVersion,
            "record_title": Self.agentRecordTitle(
                actionName: action.resolvedProfile.profile.displayName,
                targetTitle: record.snapshot.request.target.title
            ),
            "disposition": "completed",
            "academic_results": ["values": academicValues],
            "context_use_claims": [],
            "fidelity_outcomes": outcomes,
        ]
        var completeTemplate = template
        if action.actionID == .analyze {
            completeTemplate["literature_recommendations"] = []
        }
        return AgentCommandAction(
            kind: .submitResult,
            label: action.actionID == .checkFidelity && derivesDefaultAcademicResults
                ? "Submit the attributed Fidelity outcomes; Scholium derives the default aggregate Finding fields"
                : "Submit this Action's frozen academic Result Contract",
            command: [
                "scholium", "agent", "submit-result", "--run",
                run.rawValue, "--from", "-",
            ],
            inputTemplate: try Self.agentJSONTemplate(completeTemplate)
        )
    }

    private static func authenticatedWriteActions(
        _ entries: [ResearchBoundedWriteSetEntry],
        run: ResearchRunLocator
    ) throws -> [AgentCommandAction] {
        try entries
            .filter { $0.state == .ready }
            .sorted {
                ($0.role.rawValue, $0.note.relativePath)
                    < ($1.role.rawValue, $1.note.relativePath)
            }
            .flatMap { entry in
                try entry.allowedOperations
                    .sorted { $0.rawValue < $1.rawValue }
                    .map { operation in
                        let command = operation.isZoteroBindingOperation
                            ? "write-zotero-binding"
                            : "write"
                        return AgentCommandAction(
                            kind: .write,
                            label: "Write \(entry.title) with \(operation.rawValue)",
                            command: [
                                "scholium", "agent", command, "--run",
                                run.rawValue, "--from", "-",
                            ],
                            inputTemplate: try agentWriteTemplate(
                                entry: entry,
                                operation: operation
                            )
                        )
                    }
            }
    }

    private static func agentWriteTemplate(
        entry: ResearchBoundedWriteSetEntry,
        operation: ResearchDocumentWriteOperation
    ) throws -> String {
        var template: [String: Any] = [
            "role": entry.role.rawValue,
            "relative_path": entry.note.relativePath,
            "operation": operation.rawValue,
        ]
        switch operation {
        case .modifyMarkdown:
            template["content"] = "REPLACE_WITH_COMPLETE_MARKDOWN_BODY"
        case .modifySource:
            template["source"] = "REPLACE_WITH_COMPLETE_AUTHORED_MARKDOWN_SOURCE"
        case .modifyMetadata:
            template["metadata"] = entry.allowedMetadataKeys.map {
                ["key": $0, "value": "REPLACE_WITH_TYPED_VALUE"]
            }
        case .createNote:
            template["content"] = "REPLACE_WITH_MARKDOWN_BODY_OR_EMPTY_STRING"
            template["authored_yaml"] = ["summary": NSNull(), "keywords": []]
            if entry.role == .analysis {
                template["analysis_metadata"] = [
                    "source_type": "REPLACE_WITH_ALLOWED_SOURCE_TYPE",
                    "fields": [],
                ]
            }
        case .setZoteroBinding:
            template["library"] = ["kind": "REPLACE_WITH_user_OR_group"]
            template["item_key"] = "REPLACE_WITH_EXACT_ZOTERO_ITEM_KEY"
        case .clearZoteroBinding:
            break
        }
        return try agentJSONTemplate(template)
    }

    private static func agentJSONTemplate(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func stableAgentUUID(runID: UUID, label: String) -> UUID {
        let fingerprint = DocumentFingerprint(
            content: runID.uuidString.lowercased() + "\u{001F}" + label
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func agentRecordTitle(
        actionName: String,
        targetTitle: String
    ) -> String {
        var title = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
            + " — "
            + targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.utf8.count > ResearchRecordTitle.maximumUTF8Count,
              !title.isEmpty {
            title.removeLast()
        }
        return (try? ResearchRecordTitle(title))?.value ?? "Research result"
    }

    private static func agentRunState(
        _ state: ResearchActionRunState
    ) -> ResearchActionRunState {
        switch state {
        case .prepared: .prepared
        case .complete: .complete
        case .unverified: .unverified
        case .stale: .stale
        case .cancelled: .cancelled
        }
    }

    func endResearchAgentRun(
        credential: ResearchConnectionCredential,
        run: ResearchRunLocator
    ) async throws -> ResearchRunEndReceipt {
        try requireActive()
        guard let sessions = researchAgentConnectionDependencies.researchAgentSessions else {
            throw ResearchAgentConnectionError.secureRandomUnavailable
        }
        let authenticated = try await sessions.authenticate(
            credential,
            run: run,
            requiresWrite: false,
            claimCoreProtocol: false,
            allowFinalized: true
        )
        guard authenticated.triptychID == self.id else {
            throw ResearchAgentSessionError.sessionRejected
        }
        if let improvement = try? await researchAgentConnectionDependencies.localResearchExecutionStore
            .methodImprovement(id: authenticated.runID) {
            let recoveryRetained = improvement.state == .writing
            await sessions.revokeRun(authenticated.runID)
            return try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: recoveryRetained,
                message: recoveryRetained
                    ? "The Method improvement Run ended. Its in-progress exact-revision outcome remains recorded for recovery; no new Agent operation is authorized."
                    : "The Method improvement Run ended and no new Agent operation is authorized."
            )
        }
        let record = try await researchAgentConnectionDependencies.localResearchExecutionStore.record(
            id: authenticated.runID
        )
        if let completion = record.completion,
           [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            await sessions.revokeRun(authenticated.runID)
            return try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: false,
                message: "The completed Run's local Session access ended; its Result, Record, confirmed changes, conflicts, and recovery evidence remain unchanged."
            )
        }
        _ = try activeAction(in: record)
        let hasPendingWriteRecovery = try await hasPendingResearchWriteRecovery(
            runID: authenticated.runID,
            writes: record.documentWriteRecords
        )
        let recoveryRetained = record.documentWriteRecords.contains {
            $0.state == .writing || $0.state == .recoveryRequired
        } || record.zoteroBindingWriteRecords.contains {
            $0.state == .writing || $0.state == .recoveryRequired
        } || record.boundedWriteSet.entries.contains {
            $0.state == .writing || $0.state == .recoveryRequired
        } || hasPendingWriteRecovery
        if recoveryRetained {
            await sessions.revokeRun(authenticated.runID)
            return try ResearchRunEndReceipt(
                run: run,
                recoveryRetained: true,
                message: "The Run retains an unresolved write recovery. Its Session access ended without recording cancellation; resolve the exact transaction before finalization."
            )
        }
        try await researchActionRunCoordinator.cancelAction(
            runID: authenticated.runID,
            host: self
        )
        return try ResearchRunEndReceipt(
            run: run,
            recoveryRetained: recoveryRetained,
            message: recoveryRetained
                ? "The Run ended and refuses new Agent operations. Confirmed changes, conflicts, and unresolved recovery duties remain in Scholium."
                : "The Run ended and refuses new Agent operations. Confirmed changes and conflicts remain in Scholium."
        )
    }

    private func activeAction(
        in record: LocalResearchExecutionRecord
    ) throws -> ResearchActionSnapshot {
        guard record.triptychID == self.id else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        let action = record.snapshot.actionSnapshot
        if let completion = record.completion,
           [.complete, .unverified, .stale, .cancelled].contains(completion.state) {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return action
    }

    private func requiredPlatformAction(
        _ actionID: ResearchActionID
    ) throws -> PlatformActionDefinition {
        guard let definition = PlatformActionCatalog.definition(for: actionID) else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return definition
    }

    private static func capabilities(
        _ definition: PlatformActionDefinition
    ) -> ResearchRunCapabilityAvailability {
        let operations = Set(definition.operations)
        return ResearchRunCapabilityAvailability(
            search: operations.contains(.search),
            read: operations.contains(.read),
            relations: operations.contains(.inspectRelations),
            metadata: operations.contains(.inspectMetadata),
            records: operations.contains(.queryRecords),
            researchState: operations.contains(.queryRecords),
            zotero: operations.contains(.useZotero),
            writeInitialObject: operations.contains(.modifyInitialNote),
            extendWriteSet: operations.contains(.extendWriteSet),
            continueResearch: operations.contains(.continueResearch),
            discussionReply: operations.contains(.discuss),
            discussionFinish: operations.contains(.discuss)
        )
    }

    private static func validateResearchContextCapability(
        _ request: ResearchContextRequest,
        platform: PlatformActionDefinition
    ) throws {
        let operations = Set(platform.operations)
        for clause in request.clauses {
            let permitted = switch clause.kind {
            case .discoverNote: operations.contains(.search)
            case .readNote: operations.contains(.read)
            case .inspectRelations: operations.contains(.inspectRelations)
            case .inspectMetadata: operations.contains(.inspectMetadata)
            case .inspectMaterials: operations.contains(.read)
            case .inspectRecords, .inspectResearcherState:
                operations.contains(.queryRecords)
            }
            guard permitted else {
                throw ResearchAgentConnectionError.capabilityUnavailable
            }
        }
    }

}

private extension ResearchAgentStartRequest {
    var researchRequestText: String? {
        guard case .freeText(let text)? = academicInputs["research-request"] else {
            return nil
        }
        return text
    }
}

public enum ResearchAgentConnectionError: LocalizedError, Hashable, Sendable {
    case secureRandomUnavailable
    case runUnavailable
    case capabilityUnavailable
    case invalidAnalysisCreationMetadata
    case analysisPathOccupied
    case analysisIdentityOccupied
    case analysisIdentitySourceMissingOrTrashed
    case analysisSourceUnreadable
    case newAnalysisReplayConflict
    case runStale(ResearchAgentRunStaleReason)

    public var errorDescription: String? {
        switch self {
        case .secureRandomUnavailable:
            "Scholium could not initialize its cryptographic local-session boundary; no handoff was issued."
        case .runUnavailable:
            "The Research Run is unavailable, ended, or no longer matches its frozen Action."
        case .capabilityUnavailable:
            "This Research Context channel is not available for the frozen Action."
        case .invalidAnalysisCreationMetadata:
            "The Analysis creation values do not match the source-type, managed Metadata, or fixed authored-YAML contract. Rerun preflight with corrected values."
        case .analysisPathOccupied:
            "The resolved Analysis destination is occupied. Scholium did not overwrite it or invent another filename."
        case .analysisIdentityOccupied:
            "The resolved Analysis destination already belongs to a portable Note identity. Use that existing Analysis or ask the researcher for a distinct root filename."
        case .analysisIdentitySourceMissingOrTrashed:
            "A portable Analysis identity remains but its source is missing or in the system Trash. Scholium did not recreate, overwrite, delete the identity, or create a retry file."
        case .analysisSourceUnreadable:
            "Scholium cannot verify the authoritative source state at the resolved Analysis destination."
        case .newAnalysisReplayConflict:
            "The Analysis creation request identity already belongs to different or terminal creation evidence. Scholium preserved the authoritative source, identity, relationship, Run, and recovery state and refused replay."
        case .runStale(let reason):
            "This exact Research Run is stale because \(reason.description). Do not submit or write against it. Inspect the current Note in Scholium and start a new Action from the current revision."
        }
    }
}

public enum ResearchAgentRunStaleReason: String, Hashable, Sendable {
    case targetChanged = "the Target revision changed"
    case targetUnavailable = "the Target is unavailable"
    case targetIdentityChanged = "the Target identity changed"
    case materialChanged = "a frozen Material changed"
    case sourceChanged = "the formal source envelope changed or became unavailable"

    var description: String { rawValue }
}
