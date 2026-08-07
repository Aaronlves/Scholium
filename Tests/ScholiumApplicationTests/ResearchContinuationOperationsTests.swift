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
                academicResults: values
            )
        )
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)
        return (preparation, handoff, credential, contextReference)
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
