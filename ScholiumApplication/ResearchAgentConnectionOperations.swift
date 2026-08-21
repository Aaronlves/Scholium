import Darwin
import Foundation
import ScholiumContracts
import ScholiumCore

struct WorkspaceResearchAgentConnectionDependencies: Sendable {
    let localResearchExecutionStore: LocalResearchExecutionStore
    let researchAgentSessions: ResearchAgentSessionAuthority?
    let controlStore: TriptychControlStore
}

extension WorkspaceServices {
    var researchAgentConnectionDependencies:
        WorkspaceResearchAgentConnectionDependencies {
        WorkspaceResearchAgentConnectionDependencies(
            localResearchExecutionStore: localResearchExecutionStore,
            researchAgentSessions: researchAgentSessions,
            controlStore: controlStore
        )
    }
}

extension WorkspaceRuntime {
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
              let functionRole = ResearchFunctionTargetRole(vaultRole: note.vaultRole) else {
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
            title: researchFunctionCoordinator.researchFunctionTitle(for: note)
        )
        let available = try await researchActionAvailability(
            for: target,
            checkingSourceAccess: !allowsResearcherProvidedSource
        )
        guard let action = available.first(where: {
            $0.id == request.actionID && $0.isEnabled
        }) else {
            throw ResearchActionExecutionContractError.actionUnavailable(
                request.actionID
            )
        }
        let academicInputs = try ResearchAcademicFieldValues(
            rawValues: request.academicPurpose.map {
                ["research-request": .freeText($0)]
            } ?? [:],
            definitions: action.profile.profile.academicInputFields
        )
        let execution = ResearchActionExecutionRequest(
            actionID: request.actionID,
            expectedExecutionKind: action.definition.executionKind,
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
        guard [ResearchActionRunState.prepared, .awaitingFidelity]
            .contains(preparation.state) else {
            throw ResearchAgentConnectionError.runUnavailable
        }
        return (preparation, target)
    }

    /// Starts Analyze from an absent Analysis path. Creation is intentionally
    /// a preflight of the existing Run preparation: the managed creator still
    /// owns the exact Settings revision, reserved identity, source/identity
    /// readback, and no-replace path claim, while the resulting Run keeps the
    /// ordinary target fingerprint and write authority. The optional Zotero
    /// relationship is portable metadata only; when it is absent, the
    /// researcher-provided source route is carried outside Scholium.
    func startNewAnalysisResearchAgentRun(
        _ request: ResearchAgentStartRequest
    ) async throws -> (preparation: ResearchActionPreparation, target: ResearchActionNoteSnapshot) {
        try requireCompleteWorkspace()
        guard request.actionID == .analyze,
              let creation = request.newAnalysis,
              request.target == nil,
              let analysisVaultID = self.assignment.vault(for: .paperAnalysis)?.id,
              creation.target.vaultID == analysisVaultID else {
            throw ResearchActionExecutionContractError.staleResolution
        }

        let settings = try await researchAgentConnectionDependencies.controlStore.settings()
        let reservedIdentity = try Self.agentStartDeterministicID(
            namespace: "agent-start-new-analysis",
            request: request
        )
        let runID = try Self.agentStartDeterministicID(
            namespace: "agent-start-run",
            request: request
        )
        let requestFingerprint = try Self.agentStartRequestFingerprint(request)
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
            guard existingRun.snapshot.runID == runID,
                  existingRun.snapshot.actionSnapshot?.actionID == .analyze,
                  existingRun.snapshot.request.target.note == creation.target,
                  existingRun.snapshot.analysisSourceRoute == expectedRoute,
                  let target = existingRun.snapshot.actionSnapshot?.target else {
                throw ResearchActionExecutionContractError.staleResolution
            }
            if let requestedBinding {
                try await requireCurrentAgentAnalysisBinding(
                    runID: runID,
                    expected: requestedBinding
                )
            }
            let preparation = try await researchActionRun(id: runID)
            guard [ResearchActionRunState.prepared, .awaitingFidelity]
                .contains(preparation.state) else {
                throw ResearchAgentConnectionError.runUnavailable
            }
            return (preparation, target)
        }

        let existingIdentity = try await researchAgentConnectionDependencies
            .controlStore.identityRecord(
                vaultID: creation.target.vaultID,
                relativePath: creation.target.relativePath
            )
        if let existingIdentity, existingIdentity.id != reservedIdentity {
            throw DocumentCreationError.portableIdentityAlreadyExists
        }
        if let requestedBinding {
            let expectedCreation = try LocalAgentAnalysisCreationRecord(
                triptychID: id,
                runID: runID,
                requestFingerprint: requestFingerprint,
                target: creation.target,
                reservedIdentityID: reservedIdentity,
                requestedBinding: requestedBinding
            )
            if let existing = try await researchAgentConnectionDependencies
                .localResearchExecutionStore.agentAnalysisCreationIfPresent(id: runID) {
                guard Self.matchesAgentAnalysisCreation(
                    existing,
                    expected: expectedCreation
                ) else {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
            } else {
                guard existingIdentity == nil else {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
                _ = try await researchAgentConnectionDependencies
                    .localResearchExecutionStore.createAgentAnalysisCreation(
                        expectedCreation
                    )
            }
        }

        let managedRequest = try ManagedNoteCreationRequest(
            vaultID: creation.target.vaultID,
            destination: .exact(relativePath: creation.target.relativePath),
            analysisMetadata: creation.metadata,
            authority: .authenticatedAgent(
                settingsRevision: settings.revision,
                reservedIdentity: reservedIdentity
            )
        )
        let commit: WorkspaceManagedNoteCommit
        if let existingIdentity {
            let existingDocument = try await repository(
                vaultID: creation.target.vaultID
            ).load(relativePath: creation.target.relativePath)
            guard existingIdentity.fingerprint == existingDocument.fingerprint else {
                throw ResearchActionExecutionContractError.staleResolution
            }
            commit = WorkspaceManagedNoteCommit(
                id: creation.target,
                vaultRole: .sourceCorpus,
                stableIdentity: .resolved(reservedIdentity),
                document: existingDocument
            )
        } else {
            commit = try await createManagedNote(managedRequest).committedValue
        }
        guard commit.id == creation.target,
              commit.stableIdentity.resolvedID == reservedIdentity else {
            throw ResearchActionExecutionContractError.staleResolution
        }

        // Creation already queued the one Workspace-owned refresh. Await that
        // owner instead of racing it with another generation. A failed
        // projection remains a committed-but-stale result, and an exact retry
        // resumes from the deterministic identity above without creating a
        // duplicate Note.
        _ = try await awaitCommittedSourceProjection(
            id: creation.target,
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
            target: creation.target,
            academicPurpose: request.academicPurpose,
            sourceRoute: creation.source == nil ? .researcherProvided : nil
        )
        return try await startResearchAgentRun(
            existingTargetRequest,
            expectedZoteroBinding: requestedBinding,
            runIDOverride: runID
        )
    }

    private func establishAgentAnalysisBinding(
        runID: UUID,
        expected: AnalysisZoteroBinding
    ) async throws {
        let store = researchAgentConnectionDependencies.localResearchExecutionStore
        let record = try await store.agentAnalysisCreation(id: runID)
        guard record.requestedBinding == expected else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
        let snapshot = try await researchAgentConnectionDependencies.controlStore
            .zoteroBindings()
        let current = snapshot.binding(for: expected.noteID)
        switch record.bindingState {
        case .reserved, .retryable:
            if let current {
                guard current == expected else {
                    throw ResearchAgentConnectionError.newAnalysisReplayConflict
                }
                _ = try await store.advanceAgentAnalysisCreationBinding(
                    runID: runID,
                    to: .committed
                )
            } else {
                _ = try await store.advanceAgentAnalysisCreationBinding(
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
                    _ = try await store.advanceAgentAnalysisCreationBinding(
                        runID: runID,
                        to: .committed
                    )
                } catch TriptychControlError.zoteroBindingsRevisionConflict {
                    _ = try? await store.advanceAgentAnalysisCreationBinding(
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
            if record.bindingState == .writing {
                _ = try await store.advanceAgentAnalysisCreationBinding(
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
            .localResearchExecutionStore.agentAnalysisCreation(id: runID)
        let current = try await researchAgentConnectionDependencies.controlStore
            .zoteroBindings().binding(for: expected.noteID)
        guard record.requestedBinding == expected,
              record.bindingState == .committed,
              current == expected else {
            throw ResearchAgentConnectionError.newAnalysisReplayConflict
        }
    }

    private static func matchesAgentAnalysisCreation(
        _ existing: LocalAgentAnalysisCreationRecord,
        expected: LocalAgentAnalysisCreationRecord
    ) -> Bool {
        existing.triptychID == expected.triptychID
            && existing.runID == expected.runID
            && existing.requestFingerprint == expected.requestFingerprint
            && existing.target == expected.target
            && existing.reservedIdentityID == expected.reservedIdentityID
            && existing.requestedBinding == expected.requestedBinding
    }

    private static func agentStartDeterministicID(
        namespace: String,
        request: ResearchAgentStartRequest
    ) throws -> UUID {
        var material = Data((namespace + "\u{0}").utf8)
        material.append(try agentStartCanonicalData(request))
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

    private static func agentStartRequestFingerprint(
        _ request: ResearchAgentStartRequest
    ) throws -> DocumentFingerprint {
        DocumentFingerprint(data: try agentStartCanonicalData(request))
    }

    private static func agentStartCanonicalData(
        _ request: ResearchAgentStartRequest
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(request)
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
        guard record.snapshot.request.function == .fidelity else { return nil }
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
            _ = try await researchFunctionCoordinator.validateResearchFunctionTarget(
                request.target,
                expected: expectedTarget,
                host: self
            )
        } catch ResearchFunctionContractError.targetChanged {
            throw ResearchAgentConnectionError.runStale(.targetChanged)
        } catch ResearchFunctionContractError.targetUnavailable {
            throw ResearchAgentConnectionError.runStale(.targetUnavailable)
        } catch ResearchFunctionContractError.targetIdentityChanged {
            throw ResearchAgentConnectionError.runStale(.targetIdentityChanged)
        } catch {
            throw error
        }
        for material in request.materials {
            do {
                _ = try await researchFunctionCoordinator
                    .validateResearchFunctionMaterial(
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
        guard action.actionID == .checkFidelity else { return [] }
        let defaultFidelityFields = ResearchAcademicProfileCatalog
            .defaultProfiles.first(where: { $0.actionID == .checkFidelity })?
            .academicResultFields ?? []
        let derivesDefaultAcademicResults =
            action.resultContract.academicFields == defaultFidelityFields
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
        let fidelityContract = try await authenticatedFidelityContract(for: record)
        let requiredUnavailable = fidelityContract?.requiredUnavailableChecks ?? []
        let evidenceLimitation = fidelityContract?.evidenceLimitation
        let outcomes: [[String: Any]] = record.snapshot.request.checks
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
        let template: [String: Any] = [
            "schema_version": ResearchAgentResultSubmission.currentSchemaVersion,
            "record_title": Self.fidelityRecordTitle(
                targetTitle: record.snapshot.request.target.title
            ),
            "disposition": "completed",
            "academic_results": ["values": academicValues],
            "context_use_claims": [],
            "fidelity_outcomes": outcomes,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: template,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return [AgentCommandAction(
            kind: .submitResult,
            label: derivesDefaultAcademicResults
                ? "Submit only the attributed Fidelity outcomes; Scholium derives the default aggregate Finding fields"
                : "Submit the attributed Fidelity outcomes and researcher-customized academic fields",
            command: [
                "scholium", "agent", "submit-result", "--run",
                run.rawValue, "--from", "-",
            ],
            inputTemplate: String(decoding: data, as: UTF8.self)
        )]
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

    private static func fidelityRecordTitle(targetTitle: String) -> String {
        var title = "Fidelity — "
            + targetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.utf8.count > ResearchRecordTitle.maximumUTF8Count,
              !title.isEmpty {
            title.removeLast()
        }
        return (try? ResearchRecordTitle(title))?.value ?? "Fidelity check"
    }

    private static func agentRunState(
        _ state: ResearchFunctionRunState
    ) -> ResearchActionRunState {
        switch state {
        case .prepared: .prepared
        case .awaitingFidelity: .awaitingFidelity
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
        try await researchFunctionCoordinator.cancelAction(
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
        guard record.triptychID == self.id,
              let action = record.snapshot.actionSnapshot else {
            throw ResearchAgentConnectionError.runUnavailable
        }
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
            properties: operations.contains(.inspectProperties),
            records: operations.contains(.queryRecords),
            researchState: operations.contains(.queryRecords),
            zotero: operations.contains(.useZotero),
            writeInitialObject: operations.contains(.modifyInitialNote),
            extendWriteSet: operations.contains(.extendWriteSet),
            continueResearch: operations.contains(.continueResearch),
            discussionReply: operations.contains(.discuss)
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
            case .inspectProperties: operations.contains(.inspectProperties)
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

public enum ResearchAgentConnectionError: LocalizedError, Hashable, Sendable {
    case secureRandomUnavailable
    case runUnavailable
    case capabilityUnavailable
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
        case .newAnalysisReplayConflict:
            "The Analysis creation request no longer matches its current Zotero relationship. Scholium preserved the newer researcher-owned relationship and refused replay."
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
