import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Continue Research Application boundary", .serialized)
struct ResearchContinuationOperationsTests {
    @Test("Agent continuation creates a fresh attributed child Run without another permission decision")
    func automaticFreshChildRun() async throws {
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

        let automaticRequest = try continuationRequest(
            actionID: .synthesize,
            role: .topic,
            path: "Agency.md",
            purpose: "Reassess the Topic synthesis using one explicit handoff.",
            sourceReferences: [currentReferenceWithNewResponseID]
        )
        let automaticContinuation = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: automaticRequest
        )
        #expect(automaticContinuation.state == .created)
        #expect(automaticContinuation.nextRun != nil)
        #expect(automaticContinuation.handoffContext?.initiator == .agent)
        #expect(automaticContinuation.context?.brief.run == automaticContinuation.nextRun)
        #expect(automaticContinuation.context?.requiredSkills.contains(.coreProtocol) == true)
        #expect(automaticContinuation.context?.requiredSkills.contains {
            $0.name == ResearchActionID.synthesize.projectSkillName
        } == true)

        let parentAfterFullAccess = try await handle.services
            .localResearchExecutionStore.record(id: parent.preparation.runID)
        let automaticRecord = try #require(
            parentAfterFullAccess.continuationRequests.first {
                $0.request == automaticRequest
            }
        )
        #expect(automaticRecord.state == .created)
        #expect(automaticRecord.origin == .agentInitiated)
        let childID = try #require(automaticRecord.childRunID)
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

        let target = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let currentAction = try #require(
            try await handle.research.availableActions(
                for: target
            ).first { $0.id == .synthesize }
        )
        #expect(child.snapshot.actionSnapshot.resolvedProfile.profileRevision
            == currentAction.profile.profileRevision)

        let askRequest = try continuationRequest(
            actionID: .checkFidelity,
            role: .topic,
            path: "Agency.md",
            purpose: "Check the exact current Topic revision before further use."
        )
        let createdWithoutDecision = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: askRequest
        )
        #expect(createdWithoutDecision.state == .created)
        #expect(createdWithoutDecision.nextRun != nil)

        let workRequest = try continuationRequest(
            actionID: .write,
            role: .work,
            path: "Draft Argument.md",
            purpose: "Revise the related Work and record the Agent-initiated lineage."
        )
        let workContinuation = try await handle.research.continueAgentResearch(
            credential: parent.credential,
            run: parent.handoff.run,
            request: workRequest
        )
        #expect(workContinuation.state == .created)
        #expect(workContinuation.nextRun != nil)

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

        let target = try await researchActionTarget(
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
        let context = try #require(result.context)
        #expect(context.brief.run == childRun)
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
        var envelopeObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: childURL))
                as? [String: Any]
        )
        let encodedPayload = try #require(envelopeObject["payload"] as? String)
        let payload = try #require(Data(base64Encoded: encodedPayload))
        var childObject = try #require(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
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
        let modifiedPayload = try JSONSerialization.data(
            withJSONObject: childObject,
            options: [.sortedKeys]
        )
        envelopeObject["payload"] = modifiedPayload.base64EncodedString()
        envelopeObject["payload_fingerprint"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DocumentFingerprint(data: modifiedPayload))
        )
        try JSONSerialization.data(
            withJSONObject: envelopeObject,
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

    @Test("Researcher Follow-up creates a fresh Action Run with separate lineage and parent feedback")
    func researcherFollowUpCreatesFreshRun() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedParent(handle: handle, fixture: fixture)
        let parentRecord = try await handle.services.portableResearchRecordStore
            .record(id: parent.preparation.runID)
        let parentFingerprint = try parentRecord.finalizedResultFingerprint()
        let context = try await handle.research.followUpContext(
            recordID: parentRecord.id,
            expectedFinalizedResultFingerprint: parentFingerprint
        )
        let requestField = try #require(
            ResearchAcademicFieldID(rawValue: "research-request")
        )
        let action = try await ResearchActionRunOperationsTests().actionRequest(
            handle: handle,
            actionID: .synthesize,
            target: context.target,
            academicValues: [
                requestField: .freeText(
                    "Test whether the qualified synthesis survives the new objection."
                ),
            ]
        )
        let preparation = try await handle.research.prepareFollowUp(
            try ResearchFollowUpRequest(
                parentRecordID: parentRecord.id,
                expectedFinalizedResultFingerprint: parentFingerprint,
                statement: try ResearchFollowUpStatement(
                    kind: .hypothesis,
                    text: "The qualification may fail when the objection targets authority rather than salience."
                ),
                action: action,
                methodFeedbackText:
                    "Ask for an explicit alternative-reading check before synthesis.",
                expectedMethodFeedbackRevision: nil
            )
        )

        #expect(preparation.runID != parent.preparation.runID)
        let child = try await handle.services.localResearchExecutionStore.record(
            id: preparation.runID
        )
        #expect(child.snapshot.continuationLineage?.kind == .followUp)
        #expect(child.snapshot.continuationLineage?.parentRunID == parentRecord.id)
        #expect(child.snapshot.continuationHandoff?.initiator == .researcher)
        #expect(child.snapshot.continuationHandoff?.handoff.first?.epistemicStatus
            == .hypothesisToVerify)
        #expect(child.snapshot.actionSnapshot.method.registration.key
            == preparation.snapshot.method.registration.key)
        #expect(child.documentWriteRecords.isEmpty)
        #expect(child.completion == nil)

        let updatedParent = try await handle.services.portableResearchRecordStore
            .record(id: parentRecord.id)
        #expect(updatedParent.methodFeedbackComment?.text
            == "Ask for an explicit alternative-reading check before synthesis.")
        #expect(try updatedParent.finalizedResultFingerprint() == parentFingerprint)
        #expect(updatedParent.continuationLineage == nil)
        await runtime.shutdown()
    }

    @Test("Saved Follow-up feedback reconciles its revision before a safe child retry")
    func followUpFeedbackReconcilesBeforeRetry() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedParent(handle: handle, fixture: fixture)
        let parentRecord = try await handle.services.portableResearchRecordStore
            .record(id: parent.preparation.runID)
        let parentFingerprint = try parentRecord.finalizedResultFingerprint()
        let context = try await handle.research.followUpContext(
            recordID: parentRecord.id,
            expectedFinalizedResultFingerprint: parentFingerprint
        )
        let requestField = try #require(
            ResearchAcademicFieldID(rawValue: "research-request")
        )
        let helpers = ResearchActionRunOperationsTests()
        let blockingDiscussion = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .discuss,
                target: context.target,
                academicValues: [
                    requestField: .freeText("Keep this Discussion active for the retry fixture."),
                ]
            )
        )
        let followUpAction = try await helpers.actionRequest(
            handle: handle,
            actionID: .discuss,
            target: context.target,
            academicValues: [
                requestField: .freeText("Test the objection in a fresh Discussion."),
            ]
        )
        let feedback = "Ask the Discussion to separate textual and dialectical objections."
        let statement = try ResearchFollowUpStatement(
            kind: .question,
            text: "Does the objection challenge the premise or only its dialectical role?"
        )

        let failure: ResearchFollowUpPreparationError
        do {
            _ = try await handle.research.prepareFollowUp(
                try ResearchFollowUpRequest(
                    parentRecordID: parentRecord.id,
                    expectedFinalizedResultFingerprint: parentFingerprint,
                    statement: statement,
                    action: followUpAction,
                    methodFeedbackText: feedback,
                    expectedMethodFeedbackRevision: nil
                )
            )
            Issue.record("Expected the existing Action-owned Discussion to block Follow-up.")
            return
        } catch let error as ResearchFollowUpPreparationError {
            failure = error
        }

        #expect(failure.methodFeedbackWasSaved)
        #expect(failure.latestContext.methodFeedbackText == feedback)
        let savedRevision = try #require(failure.latestContext.methodFeedbackRevision)
        let persistedParent = try await handle.services.portableResearchRecordStore
            .record(id: parentRecord.id)
        #expect(persistedParent.methodFeedbackComment?.revision == savedRevision)
        #expect(persistedParent.methodFeedbackComment?.text == feedback)
        #expect(try await handle.services.localResearchExecutionStore.listing().records
            .filter { $0.snapshot.continuationLineage?.kind == .followUp }
            .isEmpty)

        try await handle.research.cancelAction(runID: blockingDiscussion.runID)
        let retry = try await handle.research.prepareFollowUp(
            try ResearchFollowUpRequest(
                parentRecordID: parentRecord.id,
                expectedFinalizedResultFingerprint: parentFingerprint,
                statement: statement,
                action: followUpAction,
                methodFeedbackText: feedback,
                expectedMethodFeedbackRevision: savedRevision
            )
        )

        let retryParent = try await handle.services.portableResearchRecordStore
            .record(id: parentRecord.id)
        #expect(retryParent.methodFeedbackComment?.revision == savedRevision)
        let followUpRuns = try await handle.services.localResearchExecutionStore
            .listing().records.filter {
                $0.snapshot.continuationLineage?.kind == .followUp
            }
        #expect(followUpRuns.map(\.id) == [retry.runID])
        await runtime.shutdown()
    }

    @Test("Follow-up rejects a stale feedback revision even when its text still matches")
    func followUpRejectsStaleMatchingFeedbackRevision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedParent(handle: handle, fixture: fixture)
        let parentRecord = try await handle.services.portableResearchRecordStore
            .record(id: parent.preparation.runID)
        let parentFingerprint = try parentRecord.finalizedResultFingerprint()
        let initialContext = try await handle.research.followUpContext(
            recordID: parentRecord.id,
            expectedFinalizedResultFingerprint: parentFingerprint
        )
        let feedback = "Preserve the distinction between authority and salience."
        let externallyUpdated = try await handle.research.saveMethodFeedback(
            recordID: parentRecord.id,
            draft: try ResearchMethodFeedbackDraft(text: feedback),
            expectedMethodFeedbackRevision: initialContext.methodFeedbackRevision,
            expectedResultFingerprint: parentFingerprint
        )
        let requestField = try #require(
            ResearchAcademicFieldID(rawValue: "research-request")
        )
        let action = try await ResearchActionRunOperationsTests().actionRequest(
            handle: handle,
            actionID: .synthesize,
            target: initialContext.target,
            academicValues: [
                requestField: .freeText("Reassess the qualified synthesis."),
            ]
        )

        do {
            _ = try await handle.research.prepareFollowUp(
                try ResearchFollowUpRequest(
                    parentRecordID: parentRecord.id,
                    expectedFinalizedResultFingerprint: parentFingerprint,
                    statement: try ResearchFollowUpStatement(
                        kind: .question,
                        text: "Does the distinction survive the objection?"
                    ),
                    action: action,
                    methodFeedbackText: feedback,
                    expectedMethodFeedbackRevision: nil
                )
            )
            Issue.record("Expected a stale matching feedback revision to fail closed.")
        } catch let error as ResearchFollowUpPreparationError {
            #expect(!error.methodFeedbackWasSaved)
            #expect(error.latestContext.methodFeedbackRevision
                == externallyUpdated.methodFeedbackComment?.revision)
            #expect(error.latestContext.methodFeedbackText == feedback)
        }
        #expect(try await handle.services.localResearchExecutionStore.listing().records
            .filter { $0.snapshot.continuationLineage?.kind == .followUp }
            .isEmpty)
        await runtime.shutdown()
    }

    @Test("Material handoff rechecks current, changed, missing, and unavailable source-owner states")
    func materialReferenceCurrentness() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parent = try await finalizedMaterialParent(handle: handle, fixture: fixture)
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

        let analysis = try await researchActionTarget(
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
        #expect(retiredResult["schema_version"] as? Int == 4)
        retiredResult["schema_version"] = 3
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
        #expect(child.id == childID)
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
        #expect(retiredContext["schema_version"] as? Int
            == ResearchAuthenticatedRunContext.currentSchemaVersion)
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
        let target = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let helpers = ResearchActionRunOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: target
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
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let helpers = ResearchActionRunOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .analyze,
                target: target
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
        let target = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        _ = try await handle.research.settle(
            target.note,
            expectedRevision: target.fingerprint,
            rationale: "The parent Run saw this earlier researcher judgment."
        )
        let helpers = ResearchActionRunOperationsTests()
        let preparation = try await handle.research.prepareAction(
            try await helpers.actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: target
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
                academicResults: values
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
