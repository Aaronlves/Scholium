import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Continue Research Application boundary", .serialized)
struct ResearchContinuationOperationsTests {
    @Test("Policy, explicit decision, fresh authority, and child lineage are re-resolved per next Action")
    func policyAndFreshChildRun() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedParent(handle: handle, fixture: fixture)

        let returnedReference = parent.contextReference
        let wrongScopeReference = try SourceReferenceEnvelope(
            sourceKind: returnedReference.sourceKind,
            owner: returnedReference.owner,
            actorClass: returnedReference.actorClass,
            objectRole: returnedReference.objectRole,
            vaultRole: returnedReference.vaultRole,
            fingerprint: returnedReference.fingerprint,
            locator: returnedReference.locator,
            authorizedScope: .triptych(
                runID: UUID(),
                triptychID: returnedReference.authorizedScope.triptychID
            ),
            currentness: returnedReference.currentness,
            evidentialLayer: returnedReference.evidentialLayer,
            retrievalReason: returnedReference.retrievalReason,
            materialLimitations: returnedReference.materialLimitations
        )
        let wrongScopeRequest = try continuationRequest(
            actionID: .synthesize,
            role: .topic,
            path: "Agency.md",
            purpose: "A reference from another Run must not enter a handoff.",
            sourceReferences: [wrongScopeReference]
        )
        await #expect(throws: ResearchContinuationContractError.invalidHandoff) {
            _ = try await handle.research.continueAgentResearch(
                credential: parent.credential,
                run: parent.handoff.run,
                request: wrongScopeRequest
            )
        }

        let currentReferenceWithNewResponseID = try SourceReferenceEnvelope(
            sourceKind: returnedReference.sourceKind,
            owner: returnedReference.owner,
            actorClass: returnedReference.actorClass,
            objectRole: returnedReference.objectRole,
            vaultRole: returnedReference.vaultRole,
            fingerprint: returnedReference.fingerprint,
            locator: returnedReference.locator,
            authorizedScope: returnedReference.authorizedScope,
            currentness: returnedReference.currentness,
            evidentialLayer: returnedReference.evidentialLayer,
            retrievalReason: returnedReference.retrievalReason,
            materialLimitations: returnedReference.materialLimitations
        )
        #expect(currentReferenceWithNewResponseID.id != returnedReference.id)

        var policy = try await handle.research.collaborationPolicy()
        policy = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .fullAccess
            ),
            expectedRevision: policy.revision
        )
        let fullAccessRequest = try continuationRequest(
            actionID: .synthesize,
            role: .topic,
            path: "Agency.md",
            purpose: "Reassess the Topic synthesis using one explicit handoff.",
            sourceReferences: [currentReferenceWithNewResponseID]
        )
        let fullAccess = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: fullAccessRequest
        )
        #expect(fullAccess.state == .created)
        #expect(fullAccess.nextRun != nil)
        #expect(fullAccess.handoffContext?.initiator == .agent)

        let parentAfterFullAccess = try await handle.services
            .localResearchExecutionStore.record(id: parent.preparation.runID)
        let fullAccessDecision = try #require(
            parentAfterFullAccess.continuationRequests.first {
                $0.request == fullAccessRequest
            }
        )
        #expect(fullAccessDecision.state == .created)
        #expect(fullAccessDecision.authorizationBasis == .collaborationPolicy)
        let childID = try #require(fullAccessDecision.childRunID)
        let child = try await handle.services.localResearchExecutionStore.record(
            id: childID
        )
        #expect(child.snapshot.continuationLineage?.parentRunID
            == parent.preparation.runID)
        #expect(child.snapshot.continuationHandoff?.parentRecordID
            == parent.preparation.runID)
        #expect(child.snapshot.continuationHandoff?.referenceChecks.first?
            .sourceReference == currentReferenceWithNewResponseID)
        #expect(child.snapshot.continuationHandoff?.referenceChecks.first?.status
            == .current)
        #expect(child.snapshot.request.materials.isEmpty)
        #expect(child.documentWriteRecords.isEmpty)
        #expect(child.writeSetExtensionRecords.isEmpty)
        #expect(child.resultPayload == nil)
        #expect(child.completion == nil)
        #expect(child.boundedWriteSet.entries.map(\.note.relativePath) == ["Agency.md"])

        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let currentAction = try #require(
            try await handle.research.availableActions(
                for: ResearchFunctionOperationsTests().actionNote(target)
            ).first { $0.id == .synthesize }
        )
        #expect(child.snapshot.actionSnapshot?.resolvedProfile.profileRevision
            == currentAction.profile.profileRevision)

        policy = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .askEveryTime
            ),
            expectedRevision: policy.revision
        )
        let askRequest = try continuationRequest(
            actionID: .checkFidelity,
            role: .topic,
            path: "Agency.md",
            purpose: "Check the exact current Topic revision before further use."
        )
        let pending = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: askRequest
        )
        #expect(pending.state == .pendingResearcherDecision)
        #expect(pending.nextRun == nil)
        let pendingRecord = try #require(
            try await handle.research.pendingContinuationRequests().first {
                $0.request == askRequest
            }
        )
        let allowed = try await handle.research.resolveContinuationRequest(
            parentRunID: parent.preparation.runID,
            requestID: pendingRecord.id,
            allow: true
        )
        #expect(allowed.state == .allowed)
        #expect(allowed.authorizationBasis == .explicitResearcherDecision)
        let createdAfterDecision = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: askRequest
        )
        #expect(createdAfterDecision.state == .created)

        policy = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .askOnlyForWorks
            ),
            expectedRevision: policy.revision
        )
        let workRequest = try continuationRequest(
            actionID: .write,
            role: .work,
            path: "Draft Argument.md",
            purpose: "Revise the bounded Work only if the researcher allows it."
        )
        let workPending = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: workRequest
        )
        #expect(workPending.state == .pendingResearcherDecision)
        let workDecision = try #require(
            try await handle.research.pendingContinuationRequests().first {
                $0.request == workRequest
            }
        )
        _ = try await handle.research.resolveContinuationRequest(
            parentRunID: parent.preparation.runID,
            requestID: workDecision.id,
            allow: false
        )
        let declined = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: workRequest
        )
        #expect(declined.state == .declined)
        #expect(declined.nextRun == nil)

        let nonWorkRequest = try continuationRequest(
            actionID: .checkFidelity,
            role: .topic,
            path: "Agency.md",
            purpose: "Run a second bounded current-revision check."
        )
        let nonWork = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: nonWorkRequest
        )
        #expect(nonWork.state == .created)

        let portableParent = try await handle.services.portableResearchRecordStore
            .record(id: parent.preparation.runID)
        #expect(portableParent.continuationLineage == nil)
        await runtime.shutdown()
    }

    @Test("Researcher State is re-queried in the child Run and never inherited as an old envelope")
    func researcherStateRequiresChildRequery() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedResearcherStateParent(
            handle: handle,
            fixture: fixture
        )

        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        _ = try await handle.research.settle(
            target.note,
            expectedRevision: target.fingerprint,
            rationale: "A later researcher judgment replaced the parent Run state."
        )
        let staleParentState = try SourceReferenceEnvelope(
            id: parent.researcherStateReference.id,
            sourceKind: parent.researcherStateReference.sourceKind,
            owner: parent.researcherStateReference.owner,
            actorClass: parent.researcherStateReference.actorClass,
            objectRole: parent.researcherStateReference.objectRole,
            vaultRole: parent.researcherStateReference.vaultRole,
            fingerprint: parent.researcherStateReference.fingerprint,
            locator: parent.researcherStateReference.locator,
            authorizedScope: parent.researcherStateReference.authorizedScope,
            currentness: .stale,
            evidentialLayer: parent.researcherStateReference.evidentialLayer,
            retrievalReason: parent.researcherStateReference.retrievalReason,
            materialLimitations:
                parent.researcherStateReference.materialLimitations
        )
        #expect(staleParentState.currentness == .stale)
        var policy = try await handle.research.collaborationPolicy()
        policy = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .fullAccess
            ),
            expectedRevision: policy.revision
        )

        let request = try continuationRequest(
            actionID: .synthesize,
            role: .topic,
            path: "Agency.md",
            purpose: "Continue from the current researcher-owned state, not a copied view.",
            sourceReferences: [staleParentState]
        )
        let result = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: request
        )
        #expect(result.state == .created)
        #expect(result.handoffContext?.requiresResearcherStateRequery == true)
        #expect(result.handoffContext?.handoff.flatMap(\.sourceReferences).isEmpty
            == true)
        #expect(result.handoffContext?.referenceChecks.isEmpty == true)
        #expect(result.message.contains("inspect_researcher_state"))
        #expect(throws: ResearchContinuationContractError.self) {
            _ = try ResearchContinuationHandoffContext(
                parentRecordID: parent.preparation.runID,
                initiator: .agent,
                academicPurpose: request.academicPurpose,
                handoff: request.handoff,
                referenceChecks: [],
                requiresResearcherStateRequery: true
            )
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(
            ResearchContinuationResult.self,
            from: encoder.encode(result)
        ).handoffContext?.requiresResearcherStateRequery == true)
        let wire = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            continuationResult: result
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(wire)
        ).continuationResult?.handoffContext?.requiresResearcherStateRequery
            == true)

        let childRun = try #require(result.nextRun)
        let context = try await handle.research.authenticatedAgentContext(
            credential: parent.credential,
            run: childRun
        )
        #expect(context.continuationHandoff == result.handoffContext)
        #expect(try decoder.decode(
            ResearchAuthenticatedRunContext.self,
            from: encoder.encode(context)
        ).continuationHandoff?.requiresResearcherStateRequery == true)
        #expect(context.continuationHandoff?.handoff.flatMap(\.sourceReferences)
            .contains(where: { $0.sourceKind == .researcherState }) == false)

        let currentState = try await handle.research.queryAgentResearchContext(
            credential: parent.credential,
            run: childRun,
            request: try ResearchContextRequest(
                clauses: [try ResearchContextClause(
                    kind: .inspectResearcherState,
                    useEligibility: .contextUse
                )]
            )
        )
        let settlement = try #require(currentState.items.first {
            $0.sourceReference.owner.stableObjectIdentity.hasPrefix("settlement:")
        })
        #expect(settlement.semanticContent?.contains("later researcher judgment")
            == true)
        #expect(settlement.sourceReference.authorizedScope.runID
            != parent.researcherStateReference.authorizedScope.runID)
        #expect(settlement.sourceReference.owner
            != parent.researcherStateReference.owner)
        #expect(settlement.semanticContent?.localizedCaseInsensitiveContains("pin")
            == false)
        #expect(settlement.sourceReference.materialLimitations.contains {
            $0.contains("does not establish truth")
        })

        let replay = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: request
        )
        #expect(replay == result)

        let parentExecution = try await handle.services
            .localResearchExecutionStore.record(id: parent.preparation.runID)
        let childID = try #require(parentExecution.continuationRequests.first {
            $0.request == request
        }?.childRunID)
        let localExecutionStore = await handle.services
            .localResearchExecutionStore
        let childURL = localExecutionStore.storageURL
            .appendingPathComponent(
                childID.uuidString.lowercased() + ".json"
            )
        var childObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: childURL))
                as? [String: Any]
        )
        var snapshotObject = try #require(
            childObject["snapshot"] as? [String: Any]
        )
        var handoffObject = try #require(
            snapshotObject["continuationHandoff"] as? [String: Any]
        )
        handoffObject["requires_researcher_state_requery"] = false
        snapshotObject["continuationHandoff"] = handoffObject
        childObject["snapshot"] = snapshotObject
        try JSONSerialization.data(
            withJSONObject: childObject,
            options: [.sortedKeys]
        ).write(to: childURL, options: .atomic)

        do {
            _ = try await handle.research.continueAgentResearch(
                credential: parent.credential,
                run: parent.handoff.run,
                request: request
            )
            Issue.record("Expected a tampered child requery flag to fail closed.")
        } catch let error as ResearchContinuationContractError {
            #expect(error == .invalidRecord)
        }
        await runtime.shutdown()
    }

    @Test("Material handoff rechecks current, changed, missing, and unavailable source-owner states")
    func materialReferenceCurrentness() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedMaterialParent(handle: handle, fixture: fixture)
        var policy = try await handle.research.collaborationPolicy()
        policy = try await handle.research.saveCollaborationPolicy(
            ResearchCollaborationPolicyDocument(
                triptychID: fixture.assignment.id,
                policy: .fullAccess
            ),
            expectedRevision: policy.revision
        )

        func result(for purpose: String) async throws -> ResearchContinuationResult {
            let result = try await handle.research.continueAgentResearch(
                credential: parent.credential,
                run: parent.handoff.run,
                request: try continuationRequest(
                    actionID: .synthesize,
                    role: .topic,
                    path: "Agency.md",
                    purpose: purpose,
                    sourceReferences: [parent.materialReference]
                )
            )
            #expect(result.state == .created)
            return result
        }

        let current = try await result(for: "Current Material owner check.")
        #expect(current.handoffContext?.referenceChecks.first?.status == .current)

        try Data("Changed source bytes after the parent Run.".utf8).write(
            to: fixture.analysisSourceURL
        )
        let changed = try await result(for: "Changed Material owner check.")
        #expect(changed.handoffContext?.referenceChecks.first?.status == .changed)

        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        try await handle.research.removeSourceAccess(for: analysis)
        let missing = try await result(for: "Missing Material owner check.")
        #expect(missing.handoffContext?.referenceChecks.first?.status == .missing)

        let bindingURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(
                fixture.assignment.id.uuidString,
                isDirectory: true
            )
            .appendingPathComponent("source-access", isDirectory: true)
            .appendingPathComponent("source-bindings-v1.json")
        try Data("not a valid source binding".utf8).write(
            to: bindingURL,
            options: .atomic
        )
        let unavailablePurpose = "Unavailable Material owner check."
        let unavailable = try await result(for: unavailablePurpose)
        #expect(unavailable.handoffContext?.referenceChecks.first?.status
            == .unavailable)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let resultBytes = try encoder.encode(unavailable)
        #expect(try decoder.decode(
            ResearchContinuationResult.self,
            from: resultBytes
        ) == unavailable)
        var retiredResult = try #require(
            JSONSerialization.jsonObject(with: resultBytes) as? [String: Any]
        )
        #expect(retiredResult["schema_version"] as? Int == 3)
        retiredResult["schema_version"] = 2
        #expect(throws: ResearchContinuationContractError.self) {
            _ = try decoder.decode(
                ResearchContinuationResult.self,
                from: JSONSerialization.data(withJSONObject: retiredResult)
            )
        }

        let childRun = try #require(unavailable.nextRun)
        let parentRecord = try await handle.services.localResearchExecutionStore
            .record(id: parent.preparation.runID)
        let childID = try #require(parentRecord.continuationRequests.first {
            $0.request.academicPurpose == unavailablePurpose
        }?.childRunID)
        let child = try await handle.services.localResearchExecutionStore.record(
            id: childID
        )
        #expect(child.schemaVersion == 12)
        #expect(child.snapshot.continuationHandoff?.referenceChecks.first?.status
            == .unavailable)

        let context = try await handle.research.authenticatedAgentContext(
            credential: parent.credential,
            run: childRun
        )
        let contextBytes = try encoder.encode(context)
        #expect(try decoder.decode(
            ResearchAuthenticatedRunContext.self,
            from: contextBytes
        ) == context)
        var retiredContext = try #require(
            JSONSerialization.jsonObject(with: contextBytes) as? [String: Any]
        )
        #expect(retiredContext["schema_version"] as? Int == 6)
        retiredContext["schema_version"] = 5
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try decoder.decode(
                ResearchAuthenticatedRunContext.self,
                from: JSONSerialization.data(withJSONObject: retiredContext)
            )
        }

        let resultWire = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            continuationResult: unavailable
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(resultWire)
        ).continuationResult?.handoffContext?.referenceChecks.first?.status
            == .unavailable)
        let contextWire = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            context: context
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(contextWire)
        ).context?.continuationHandoff?.referenceChecks.first?.status
            == .unavailable)
        await runtime.shutdown()
    }

    private func finalizedParent(
        handle: WorkspaceHandle,
        fixture: ResearchFixture
    ) async throws -> (
        preparation: ResearchActionPreparation,
        handoff: ResearchAgentHandoff,
        credential: ResearchConnectionCredential,
        contextReference: SourceReferenceEnvelope
    ) {
        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let helpers = ResearchFunctionOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: helpers.actionNote(target)
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.queryAgentResearchContext(
            credential: credential,
            run: handoff.run,
            request: try ResearchContextRequest(
                clauses: [try ResearchContextClause(
                    kind: .readNote,
                    query: "path:Agency.md",
                    useEligibility: .contextUse
                )]
            )
        )
        let contextReference = try #require(context.items.first?.sourceReference)
        let values = try ResearchAcademicFieldValues(
            rawValues: [
                "synthesis-outcome": .freeText(
                    "The current evidence supports one qualified synthesis."
                ),
                "contribution": .multipleChoice(["qualifies"]),
            ],
            definitions: preparation.snapshot.resultContract.academicFields
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: credential,
            run: handoff.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: try ResearchRecordTitle("Continuation fixture result"),
                academicResults: values
            )
        )
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)
        return (preparation, handoff, credential, contextReference)
    }

    private func finalizedMaterialParent(
        handle: WorkspaceHandle,
        fixture: ResearchFixture
    ) async throws -> (
        preparation: ResearchActionPreparation,
        handoff: ResearchAgentHandoff,
        credential: ResearchConnectionCredential,
        materialReference: SourceReferenceEnvelope
    ) {
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let helpers = ResearchFunctionOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .analyze,
                target: helpers.actionNote(target)
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.queryAgentResearchContext(
            credential: credential,
            run: handoff.run,
            request: try ResearchContextRequest(
                clauses: [try ResearchContextClause(
                    kind: .inspectMaterials,
                    useEligibility: .contextUse
                )]
            )
        )
        let materialReference = try #require(
            context.items.first?.sourceReference
        )
        let values = try ResearchAcademicFieldValues(
            rawValues: [
                "source-reconstruction": .freeText(
                    "The exact source supports one bounded reconstruction."
                ),
                "coverage": .singleChoice("specified-part-only"),
                "reliability": .multipleChoice(["no-material-limitations"]),
            ],
            definitions: preparation.snapshot.resultContract.academicFields
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: credential,
            run: handoff.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: try ResearchRecordTitle("Material continuation fixture"),
                academicResults: values,
                contextUseClaims: [try ResearchContextUseClaim(
                    sourceReference: materialReference,
                    testimony: "The exact source constrained the reconstruction."
                )],
                literatureRecommendations: []
            )
        )
        #expect(receipt.state == .finalized)
        return (preparation, handoff, credential, materialReference)
    }

    private func finalizedResearcherStateParent(
        handle: WorkspaceHandle,
        fixture: ResearchFixture
    ) async throws -> (
        preparation: ResearchActionPreparation,
        handoff: ResearchAgentHandoff,
        credential: ResearchConnectionCredential,
        researcherStateReference: SourceReferenceEnvelope
    ) {
        let target = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        _ = try await handle.research.settle(
            target.note,
            expectedRevision: target.fingerprint,
            rationale: "The parent Run saw this earlier researcher judgment."
        )
        let helpers = ResearchFunctionOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: helpers.actionNote(target)
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await handle.research.queryAgentResearchContext(
            credential: credential,
            run: handoff.run,
            request: try ResearchContextRequest(
                clauses: [try ResearchContextClause(
                    kind: .inspectResearcherState,
                    useEligibility: .contextUse
                )]
            )
        )
        let reference = try #require(context.items.first {
            $0.sourceReference.owner.stableObjectIdentity.hasPrefix("settlement:")
        }?.sourceReference)
        let values = try ResearchAcademicFieldValues(
            rawValues: [
                "synthesis-outcome": .freeText(
                    "The current evidence supports one qualified synthesis."
                ),
                "contribution": .multipleChoice(["qualifies"]),
            ],
            definitions: preparation.snapshot.resultContract.academicFields
        )
        let receipt = try await handle.research.submitAgentResult(
            credential: credential,
            run: handoff.run,
            submission: ResearchAgentResultSubmission(
                recordTitle: try ResearchRecordTitle("Researcher State continuation fixture"),
                academicResults: values,
                contextUseClaims: [try ResearchContextUseClaim(
                    sourceReference: reference,
                    testimony: "The earlier exact Settlement constrained the parent synthesis."
                )]
            )
        )
        #expect(receipt.state == .finalized)
        return (preparation, handoff, credential, reference)
    }

    private func continuationRequest(
        actionID: ResearchActionID,
        role: ResearchActionTargetRole,
        path: String,
        purpose: String,
        sourceReferences: [SourceReferenceEnvelope] = []
    ) throws -> ResearchContinuationRequest {
        try ResearchContinuationRequest(
            nextActionID: actionID,
            targetRole: role,
            targetRelativePath: path,
            academicPurpose: purpose,
            handoff: [try ResearchContinuationHandoffItem(
                content: "The parent result is a qualified Agent reconstruction, not a researcher commitment.",
                epistemicStatus: .agentReconstruction,
                nextUse: "Treat it as a bounded lead and recheck current source and Note state.",
                sourceReferences: sourceReferences
            )],
            fidelityChecks: actionID == .checkFidelity ? [.content] : []
        )
    }
}
