import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchFunctionOperationsTests {
    @Test("Standing permissions preserve explicit Action authority and escalate Works")
    func standingPermissionApplicationPolicy() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let initial = try await handle.research.permissionSettings()
        #expect(initial.policy.document.triptychDefault == .askEveryTime)

        let askForWorks = try await handle.research.saveTriptychPermissionPolicy(
            .askOnlyForWorks,
            expectedRevision: initial.policy.revision
        )
        let analysisStatus = try #require(askForWorks.skills.first {
            $0.packageID == "scholium-working-analyze"
        })
        #expect(analysisStatus.displayName == "Analyze")
        let analysis = try #require(analysisStatus.subject)
        let work = try #require(askForWorks.skills.first {
            $0.packageID == "scholium-working-write"
        }.flatMap(\.subject))

        let analysisRequest = try ResearchStandingPermissionRequest(
            kind: .additionalNoteChanges,
            packageID: analysis.packageID,
            currentEnvelopeDigest: analysis.envelopeDigest,
            requestedWritableRoles: [.analysis]
        )
        let analysisEvaluation = try await handle.research
            .evaluateStandingPermission(analysisRequest)
        #expect(analysisEvaluation.source == .triptychDefault)
        #expect(analysisEvaluation.disposition == .mayIssueBoundedGrant)

        let workRequest = try ResearchStandingPermissionRequest(
            kind: .writeCapableChildPhase,
            packageID: work.packageID,
            currentEnvelopeDigest: work.envelopeDigest,
            requestedWritableRoles: [.work]
        )
        let workEvaluation = try await handle.research
            .evaluateStandingPermission(workRequest)
        #expect(workEvaluation.disposition == .requiresResearcherDecision)

        let initialAction = try ResearchStandingPermissionRequest(
            kind: .initialAction,
            packageID: work.packageID,
            currentEnvelopeDigest: work.envelopeDigest,
            requestedWritableRoles: [.work]
        )
        let initialEvaluation = try await handle.research
            .evaluateStandingPermission(initialAction)
        #expect(initialEvaluation.source == .explicitAction)
        #expect(initialEvaluation.disposition == .initialTargetAuthorized)

        let wide = try await handle.research.saveTriptychPermissionPolicy(
            .triptychWide,
            expectedRevision: askForWorks.policy.revision
        )
        #expect(wide.policy.document.triptychDefault == .triptychWide)
        #expect(try await handle.research.evaluateStandingPermission(workRequest)
            .disposition == .mayIssueBoundedGrant)

        let manuscriptPackage = try await handle.research.duplicateBundledSkill(
            id: "scholium-manuscript",
            as: "scholium-working-manuscript"
        )
        let workingBindings = try #require(
            try await handle.research.workingMethodBindings()
        )
        _ = try await handle.research.activateResearcherSkill(
            packageID: manuscriptPackage.id,
            for: .manuscript,
            expectedBindingRevision: workingBindings.revision
        )
        let instructionID = try #require(
            ResearchActionModuleID(rawValue: "instruction")
        )
        let manuscriptProfile = try ResearchActionProfileBinding(
            packageID: manuscriptPackage.id,
            profile: ResearchActionProfile(
                definition: .manuscript,
                buttonName: "Manuscript",
                order: 100,
                applicableRoles: [.work],
                showInActions: true,
                modules: [try .boundedText(
                    id: instructionID,
                    label: "Instruction",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 4_000,
                    allowsMultipleLines: true
                )],
                sourceRequirement: .none,
                capabilities: try ResearchActionCapabilityDeclaration(
                    readableRoles: [.work]
                ),
                feedbackRequirement: .required
            )
        )
        let profileSnapshot = try await handle.research.saveActionProfile(
            manuscriptProfile,
            expectedDocumentRevision: nil
        )
        let withManuscript = try await handle.research.permissionSettings()
        let manuscript = try #require(withManuscript.skills.first {
            $0.packageID == manuscriptPackage.id
        })
        #expect(manuscript.displayName == "Manuscript")
        let manuscriptSubject = try #require(manuscript.subject)
        let exactProfile = try #require(manuscriptSubject.profiles.first)
        let expectedProfileRevision = try manuscriptProfile.profile.contentRevision()
        #expect(manuscriptSubject.profiles.count == 1)
        #expect(exactProfile.profileRevision == expectedProfileRevision)

        let manuscriptApproval = try await handle.research
            .saveSkillPermissionOverride(
                packageID: manuscriptSubject.packageID,
                policy: .triptychWide,
                expectedEnvelopeDigest: manuscriptSubject.envelopeDigest,
                expectedRevision: withManuscript.policy.revision
            )
        #expect(manuscriptApproval.skills.first {
            $0.packageID == manuscriptSubject.packageID
        }?.status == .approved)

        let revisedProfile = try ResearchActionProfileBinding(
            packageID: manuscriptPackage.id,
            profile: ResearchActionProfile(
                definition: .manuscript,
                buttonName: "Manuscript",
                order: 100,
                applicableRoles: [.work],
                showInActions: true,
                modules: [try .boundedText(
                    id: instructionID,
                    label: "Instruction",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 4_100,
                    allowsMultipleLines: true
                )],
                sourceRequirement: .none,
                capabilities: try ResearchActionCapabilityDeclaration(
                    readableRoles: [.work]
                ),
                feedbackRequirement: .required
            )
        )
        _ = try await handle.research.saveActionProfile(
            revisedProfile,
            expectedDocumentRevision: profileSnapshot.revision
        )
        let invalidatedManuscript = try await handle.research.permissionSettings()
        let manuscriptAfterProfileChange = try #require(
            invalidatedManuscript.skills.first {
                $0.packageID == manuscriptSubject.packageID
            }
        )
        #expect(manuscriptAfterProfileChange.status == .invalidated)
        #expect(manuscriptAfterProfileChange.effectivePolicy == .askEveryTime)
        await runtime.shutdown()
    }

    @Test("Skill changes invalidate exact-envelope overrides across window runtimes")
    func standingPermissionDigestInvalidationAndWindowConsistency() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let firstRuntime = fixture.runtime()
        let secondRuntime = fixture.runtime()
        let first = try await firstRuntime.openWorkspace(id: fixture.assignment.id)
        let second = try await secondRuntime.openWorkspace(id: fixture.assignment.id)

        let firstInitial = try await first.research.permissionSettings()
        let secondInitial = try await second.research.permissionSettings()
        #expect(firstInitial.policy.revision == nil)
        #expect(secondInitial.policy.revision == nil)
        let firstWide = try await first.research.saveTriptychPermissionPolicy(
            .triptychWide,
            expectedRevision: firstInitial.policy.revision
        )
        let secondObserved = try await second.research.permissionSettings()
        #expect(secondObserved.policy == firstWide.policy)
        await #expect(throws: (any Error).self) {
            _ = try await second.research.saveTriptychPermissionPolicy(
                .askOnlyForWorks,
                expectedRevision: secondInitial.policy.revision
            )
        }

        let subject = try #require(firstWide.skills.first {
            $0.packageID == "scholium-working-analyze"
        }.flatMap(\.subject))
        let binding = try #require(try await first.research
            .workingMethodBindings())
        let package = try #require(try await first.research.skills().first {
            $0.origin == .triptych && $0.id == subject.packageID
        })
        let packageRevision = try #require(package.revision)
        let firstEdit = try await first.research.saveWorkingMethod(
            for: .analyze,
            source: package.source + "\nPreserve the first explicit uncertainty boundary.\n",
            expectedPackageRevision: packageRevision,
            expectedBindingRevision: binding.revision
        )
        await #expect(throws: ResearchPermissionOperationError.self) {
            _ = try await second.research.saveSkillPermissionOverride(
                packageID: subject.packageID,
                policy: .triptychWide,
                expectedEnvelopeDigest: subject.envelopeDigest,
                expectedRevision: firstWide.policy.revision
            )
        }
        let afterStaleApproval = try await second.research.permissionSettings()
        let currentSubject = try #require(afterStaleApproval.skills.first {
            $0.packageID == subject.packageID
        }.flatMap(\.subject))
        #expect(currentSubject.envelopeDigest != subject.envelopeDigest)
        #expect(afterStaleApproval.policy.document.override(for: subject.packageID)
            == nil)

        let approved = try await first.research.saveSkillPermissionOverride(
            packageID: currentSubject.packageID,
            policy: .triptychWide,
            expectedEnvelopeDigest: currentSubject.envelopeDigest,
            expectedRevision: afterStaleApproval.policy.revision
        )
        #expect(approved.skills.first {
            $0.packageID == currentSubject.packageID
        }?.status == .approved)

        let firstEditRevision = try #require(firstEdit.revision)
        _ = try await first.research.saveWorkingMethod(
            for: .analyze,
            source: firstEdit.source + "\nPreserve the second explicit uncertainty boundary.\n",
            expectedPackageRevision: firstEditRevision,
            expectedBindingRevision: binding.revision
        )

        let invalidated = try await second.research.permissionSettings()
        let invalidatedSkill = try #require(invalidated.skills.first {
            $0.packageID == subject.packageID
        })
        #expect(invalidatedSkill.status == .invalidated)
        #expect(invalidatedSkill.effectivePolicy == .askEveryTime)
        let invalidatedSubject = try #require(invalidatedSkill.subject)
        let currentRequest = try ResearchStandingPermissionRequest(
            kind: .additionalNoteChanges,
            packageID: invalidatedSubject.packageID,
            currentEnvelopeDigest: invalidatedSubject.envelopeDigest,
            requestedWritableRoles: [.analysis]
        )
        let evaluation = try await second.research
            .evaluateStandingPermission(currentRequest)
        #expect(evaluation.source == .invalidatedOverride)
        #expect(evaluation.disposition == .requiresResearcherDecision)
        let staleRequest = try ResearchStandingPermissionRequest(
            kind: .additionalNoteChanges,
            packageID: subject.packageID,
            currentEnvelopeDigest: subject.envelopeDigest,
            requestedWritableRoles: [.analysis]
        )
        await #expect(throws: ResearchPermissionOperationError.self) {
            _ = try await first.research.evaluateStandingPermission(staleRequest)
        }

        await firstRuntime.shutdown()
        await secondRuntime.shutdown()
    }

    @Test("Allowed subsets prepare independent continuation children with recovery, Fidelity, and durable lineage")
    func permissionBoundContinuationChildren() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let topicSources = [
            ("Continuation One.md", "# Continuation One\n\nFirst candidate.\n"),
            ("Continuation Two.md", "# Continuation Two\n\nSecond candidate.\n"),
            ("Continuation Three.md", "# Continuation Three\n\nThird candidate.\n"),
            ("Continuation Four.md", "# Continuation Four\n\nUnapproved candidate.\n"),
        ]
        let topicsURL = fixture.rootURL.appendingPathComponent(
            "Topics",
            isDirectory: true
        )
        for (name, source) in topicSources {
            try Data(source.utf8).write(
                to: topicsURL.appendingPathComponent(name),
                options: .atomic
            )
        }

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topicVaultID = try #require(
            fixture.assignment.vault(for: .topicKnowledge)?.id
        )
        let topicIDs = topicSources.map {
            VaultQualifiedNoteID(vaultID: topicVaultID, relativePath: $0.0)
        }
        var topics: [ResearchFunctionTarget] = []
        for topicID in topicIDs {
            topics.append(try await researchFunctionTarget(
                topicID,
                role: .topic,
                handle: handle
            ))
        }
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let parent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let parentRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: parent.snapshot
        )
        let synthesisProbe = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topics[0])
            )
        )
        let requestedRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: synthesisProbe.snapshot
        )
        try await handle.research.cancelProtectedFunction(runID: synthesisProbe.runID)

        let localExecutionURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(
                fixture.assignment.id.uuidString,
                isDirectory: true
            )
            .appendingPathComponent("research-execution-v2", isDirectory: true)
        let parentRecordURL = localExecutionURL.appendingPathComponent(
            parent.runID.uuidString.lowercased() + ".json"
        )
        let parentBefore = try Data(contentsOf: parentRecordURL)
        let request = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: requestedRevision,
            targets: try topics.map { try agentChangeTarget($0) },
            operations: [.modifyMarkdown],
            agentReason: "Synthesize only the researcher-approved Topic subset."
        )
        let pending = try await handle.submitAgentNoteChangeRequest(request)
        #expect(pending.decision.state == .pending)
        let approvedIDs = topics.prefix(3).map(\.noteID)
        let allowed = try await handle.resolveAgentNoteChangeRequest(
            id: request.id,
            state: .allowedSubset,
            allowedNoteIDs: approvedIDs
        )
        #expect(allowed.continuationPlan?.childPhases.map(\.noteID).sorted {
            $0.uuidString < $1.uuidString
        } == approvedIDs.sorted { $0.uuidString < $1.uuidString })

        let continuation = try await handle.agentNoteChangeContinuations(
            id: request.id
        )
        #expect(continuation.childPreparations.count == 3)
        #expect(Set(continuation.childPreparations.map(\.noteID)) == Set(approvedIDs))
        #expect(!continuation.childPreparations.contains {
            $0.noteID == topics[3].noteID
        })
        #expect(try Data(contentsOf: parentRecordURL) == parentBefore)

        let plan = try #require(allowed.continuationPlan)
        var childrenByNote = Dictionary(uniqueKeysWithValues:
            continuation.childPreparations.map { ($0.noteID, $0.preparation) }
        )
        for approvedID in approvedIDs {
            let child = try #require(childrenByNote[approvedID])
            #expect(child.snapshot.actionSnapshot?.definition.id == .synthesize)
            #expect(child.snapshot.actionSnapshot?.authority.writableNotes.map(\.noteID)
                == [approvedID])
            #expect(child.snapshot.checkpointID != nil)
            #expect(child.snapshot.continuationLineage == ResearchContinuationLineage(
                groupID: plan.groupID,
                parentRunID: parent.runID,
                requestID: request.id,
                kind: .approvedAction
            ))
        }
        let firstRetry = try await handle.agentNoteChangeContinuations(id: request.id)
        #expect(firstRetry.childPreparations.map(\.preparation.runID)
            == continuation.childPreparations.map(\.preparation.runID))
        #expect(try Data(contentsOf: parentRecordURL) == parentBefore)

        // Model a process interruption after only part of the reserved child
        // set became durable. No caller can receive a partial result from the
        // production API; removing one undelivered fixture record recreates
        // that on-disk state deterministically for retry verification.
        let interruptedChild = try #require(
            childrenByNote[approvedIDs[2]]
        )
        let interruptedLineage = try #require(
            interruptedChild.snapshot.continuationLineage
        )
        try await handle.services.localResearchExecutionStore
            .discardFailedContinuation(
                runID: interruptedChild.runID,
                expectedLineage: interruptedLineage
            )
        _ = try await handle.services.checkpointStore.discardAutomaticCheckpoint(
            id: try #require(interruptedChild.snapshot.checkpointID)
        )
        let recoveredPreparation = try await handle.agentNoteChangeContinuations(
            id: request.id
        )
        #expect(recoveredPreparation.childPreparations.map(\.preparation.runID)
            == continuation.childPreparations.map(\.preparation.runID))
        #expect(recoveredPreparation.childPreparations.allSatisfy {
            $0.preparation.snapshot.continuationLineage == interruptedLineage
                && $0.preparation.snapshot.checkpointID != nil
        })
        childrenByNote = Dictionary(uniqueKeysWithValues:
            recoveredPreparation.childPreparations.map {
                ($0.noteID, $0.preparation)
            }
        )

        let firstChild = try #require(childrenByNote[topics[0].noteID])
        let firstMaterialFingerprints = Dictionary(uniqueKeysWithValues:
            firstChild.snapshot.request.materials.map {
                ($0.noteID, $0.fingerprint)
            }
        )
        let firstActivity = try researchActivityCompletion(
            for: firstChild,
            candidateModifiedNotes: [],
            summary: "The first approved Topic required no change."
        )
        let firstCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: firstChild.runID,
                confirmationToken: firstChild.snapshot.confirmationToken,
                finalMaterialFingerprints: firstMaterialFingerprints,
                summary: "The first approved Topic required no change.",
                didModifyTarget: false,
                activityCompletion: firstActivity
            )
        )
        #expect(firstCompletion.state == .complete)

        let secondChild = try #require(childrenByNote[topics[1].noteID])
        let secondMaterialFingerprints = Dictionary(uniqueKeysWithValues:
            secondChild.snapshot.request.materials.map {
                ($0.noteID, $0.fingerprint)
            }
        )
        let secondOriginal = try await handle.documents.load(topicIDs[1])
        let secondSaved = try await handle.documents.save(
            topicIDs[1],
            changeSet: .exactContent(
                secondOriginal.rawContent
                    + "\nA bounded synthesis of the selected Analysis.\n"
            ),
            expectedRevision: secondOriginal.fingerprint
        )
        let secondActivity = try researchActivityCompletion(
            for: secondChild,
            candidateModifiedNotes: [topicIDs[1]],
            summary: "Synthesized one bounded Topic claim."
        )
        let awaitingFidelity = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: secondChild.runID,
                confirmationToken: secondChild.snapshot.confirmationToken,
                finalMaterialFingerprints: secondMaterialFingerprints,
                summary: "Synthesized one bounded Topic claim.",
                didModifyTarget: true,
                activityCompletion: secondActivity
            )
        )
        #expect(awaitingFidelity.state == .awaitingFidelity)
        let automaticFidelity = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: secondChild.runID
        )
        #expect(automaticFidelity.preparation.snapshot.continuationLineage
            == ResearchContinuationLineage(
                groupID: plan.groupID,
                parentRunID: secondChild.runID,
                requestID: request.id,
                kind: .fidelity
            ))
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: automaticFidelity.preparation.runID,
                confirmationToken:
                    automaticFidelity.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: secondSaved.document.fingerprint,
                finalMaterialFingerprints: secondMaterialFingerprints,
                summary: "Checked the child final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let secondVerifiedSubmission = ResearchFunctionCompletionSubmission(
            runID: secondChild.runID,
            confirmationToken: secondChild.snapshot.confirmationToken,
            finalMaterialFingerprints: secondMaterialFingerprints,
            summary: "Synthesized one bounded Topic claim.",
            didModifyTarget: true,
            activityCompletion: secondActivity,
            childRunIDs: [automaticFidelity.preparation.runID]
        )
        let verifiedSecond = try await handle.research.completeProtectedFunction(
            secondVerifiedSubmission
        )
        #expect(verifiedSecond.state == .complete)
        #expect(verifiedSecond.childRunIDs == [automaticFidelity.preparation.runID])

        let thirdChild = try #require(childrenByNote[topics[2].noteID])
        let thirdCheckpointID = try #require(thirdChild.snapshot.checkpointID)
        let thirdOriginal = try await handle.documents.load(topicIDs[2])
        let conflictingSave = try await handle.documents.save(
            topicIDs[2],
            changeSet: .exactContent(
                thirdOriginal.rawContent + "\nA concurrent participant changed this Topic.\n"
            ),
            expectedRevision: thirdOriginal.fingerprint
        )
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await handle.documents.save(
                topicIDs[2],
                changeSet: .exactContent(
                    thirdOriginal.rawContent + "\nA stale child overwrite.\n"
                ),
                expectedRevision: thirdOriginal.fingerprint
            )
        }
        try await handle.research.cancelProtectedFunction(runID: thirdChild.runID)
        let cancelledChild = try await handle.research.protectedFunctionRun(
            id: thirdChild.runID
        )
        #expect(cancelledChild.state == .cancelled)
        #expect(cancelledChild.snapshot.checkpointID == thirdCheckpointID)
        _ = try await handle.research.restoreNote(
            topicIDs[2],
            from: thirdCheckpointID,
            expectedRevision: conflictingSave.document.fingerprint
        )
        #expect(try await handle.documents.load(topicIDs[2]).sourceBytes
            == thirdOriginal.sourceBytes)

        let runRecords = try await handle.services.localResearchExecutionStore.listing().records
        #expect(runRecords.first { $0.id == firstChild.runID }?.completion?.state
            == .complete)
        #expect(runRecords.first { $0.id == secondChild.runID }?.completion?.state
            == .complete)
        #expect(runRecords.first { $0.id == thirdChild.runID }?.completion?.state
            == .cancelled)
        let terminalReplay = try await handle.agentNoteChangeContinuations(
            id: request.id
        )
        #expect(terminalReplay.childPreparations.map(\.preparation.runID)
            == continuation.childPreparations.map(\.preparation.runID))
        #expect(terminalReplay.childPreparations.map(\.preparation.state).sorted {
            $0.rawValue < $1.rawValue
        } == [.cancelled, .complete, .complete])
        #expect(try Data(contentsOf: parentRecordURL) == parentBefore)
        try await handle.research.cancelProtectedFunction(runID: parent.runID)
        #expect(try await handle.research.completeProtectedFunction(
            secondVerifiedSubmission
        ) == verifiedSecond)
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(secondChild.runID.uuidString.lowercased() + ".json")
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        #expect(portable.continuationLineage == secondChild.snapshot.continuationLineage)
        let fidelityPortableURL = portableURL.deletingLastPathComponent()
            .appendingPathComponent(
                automaticFidelity.preparation.runID.uuidString.lowercased()
                    + ".json"
            )
        let fidelityPortable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: fidelityPortableURL)
        )
        #expect(fidelityPortable.continuationLineage
            == automaticFidelity.preparation.snapshot.continuationLineage)

        let independentParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let independentRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: independentParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: independentParent.snapshot
            ),
            requestedAction: requestedRevision,
            targets: [try agentChangeTarget(topics[3])],
            operations: [.modifyMarkdown],
            agentReason: "Complete this delivered child under only its own grant."
        )
        _ = try await handle.submitAgentNoteChangeRequest(independentRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: independentRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [topics[3].noteID]
        )
        let independentChild = try #require(
            try await handle.agentNoteChangeContinuations(
                id: independentRequest.id
            ).childPreparations.first?.preparation
        )
        try await handle.research.cancelProtectedFunction(runID: independentParent.runID)
        let independentMaterials = Dictionary(uniqueKeysWithValues:
            independentChild.snapshot.request.materials.map {
                ($0.noteID, $0.fingerprint)
            }
        )
        let independentCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: independentChild.runID,
                confirmationToken:
                    independentChild.snapshot.confirmationToken,
                finalMaterialFingerprints: independentMaterials,
                summary: "The independently granted child required no change.",
                didModifyTarget: false,
                activityCompletion: try researchActivityCompletion(
                    for: independentChild,
                    candidateModifiedNotes: [],
                    summary: "The independently granted child required no change."
                )
            )
        )
        #expect(independentCompletion.state == .complete)

        let cancellationParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let cancellationRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: cancellationParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: cancellationParent.snapshot
            ),
            requestedAction: requestedRevision,
            targets: [try agentChangeTarget(topics[3])],
            operations: [.modifyMarkdown],
            agentReason: "This child must not survive parent cancellation."
        )
        _ = try await handle.submitAgentNoteChangeRequest(cancellationRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: cancellationRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [topics[3].noteID]
        )
        try await handle.research.cancelProtectedFunction(runID: cancellationParent.runID)
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.agentNoteChangeContinuations(
                id: cancellationRequest.id
            )
        }

        let changedNoteParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let changedNoteRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: changedNoteParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: changedNoteParent.snapshot
            ),
            requestedAction: requestedRevision,
            targets: [try agentChangeTarget(topics[3])],
            operations: [.modifyMarkdown],
            agentReason: "Refuse this continuation if its approved Note changes."
        )
        _ = try await handle.submitAgentNoteChangeRequest(changedNoteRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: changedNoteRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [topics[3].noteID]
        )
        let fourthDocument = try await handle.documents.load(topicIDs[3])
        _ = try await handle.documents.save(
            topicIDs[3],
            changeSet: .exactContent(
                fourthDocument.rawContent + "\nChanged after approval.\n"
            ),
            expectedRevision: fourthDocument.fingerprint
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.agentNoteChangeContinuations(
                id: changedNoteRequest.id
            )
        }

        let stableTopic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let changedSkillParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let changedSkillRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: changedSkillParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: changedSkillParent.snapshot
            ),
            requestedAction: requestedRevision,
            targets: [try agentChangeTarget(stableTopic)],
            operations: [.modifyMarkdown],
            agentReason: "Refuse this continuation if its Method Skill changes."
        )
        _ = try await handle.submitAgentNoteChangeRequest(changedSkillRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: changedSkillRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [stableTopic.noteID]
        )
        let synthesizeSkill = try #require(
            try await handle.research.skills().first {
                $0.id == requestedRevision.packageID && $0.origin == .triptych
            }
        )
        let synthesizeSkillRevision = try #require(synthesizeSkill.revision)
        let synthesizeBindings = try #require(
            try await handle.research.workingMethodBindings()
        )
        _ = try await handle.research.saveWorkingMethod(
            for: .synthesize,
            source: synthesizeSkill.source
                + "\nPreserve the independently approved continuation boundary.\n",
            expectedPackageRevision: synthesizeSkillRevision,
            expectedBindingRevision: synthesizeBindings.revision
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.agentNoteChangeContinuations(
                id: changedSkillRequest.id
            )
        }

        let customActionID = try #require(
            ResearchActionID(researcherOwnedRawValue: "continuation-profile-race")
        )
        let customDefinition = try ResearchActionDefinition(
            researcherOwnedID: customActionID,
            executionKind: .writing
        )
        let customSkill = try await handle.research.createSkill(
            id: "continuation-profile-race",
            source: """
            ---
            name: Continuation Profile Race
            description: Exercise one revision-bound continuation Profile.
            scholium:
              role: specialist
              supported_actions: [continuation-profile-race]
              supported_functions: [revise]
              capabilities: []
              supported_modes: [all]
              required_skills: []
            ---
            Revise only the exact independently authorized Work.
            """ + "\n"
        )
        let initialCustomProfile = try ResearchActionProfileBinding(
            packageID: customSkill.id,
            profile: ResearchActionProfile(
                definition: customDefinition,
                buttonName: "Continuation Write",
                order: 30,
                applicableRoles: [.work],
                showInActions: true,
                modules: [],
                sourceRequirement: .none,
                capabilities: try ResearchActionCapabilityDeclaration(
                    readableRoles: [.work],
                    candidateWritableRoles: [.work],
                    candidateWriteOperations: [.modifyMarkdown]
                ),
                feedbackRequirement: .requested
            )
        )
        let initialProfileDocument = try await handle.research.saveActionProfile(
            initialCustomProfile,
            expectedDocumentRevision: nil
        )
        let stableWork = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let customProbe = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: customActionID,
                target: actionNote(stableWork)
            )
        )
        let customRequestedRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: customProbe.snapshot
        )
        try await handle.research.cancelProtectedFunction(runID: customProbe.runID)
        let changedProfileParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let changedProfileRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: changedProfileParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: changedProfileParent.snapshot
            ),
            requestedAction: customRequestedRevision,
            targets: [try agentChangeTarget(stableWork)],
            operations: [.modifyMarkdown],
            agentReason: "Refuse this continuation if its Action Profile changes."
        )
        _ = try await handle.submitAgentNoteChangeRequest(changedProfileRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: changedProfileRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [stableWork.noteID]
        )
        _ = try await handle.research.saveActionProfile(
            try ResearchActionProfileBinding(
                packageID: customSkill.id,
                profile: ResearchActionProfile(
                    definition: customDefinition,
                    buttonName: "Continuation Write Revised",
                    order: 31,
                    applicableRoles: [.work],
                    showInActions: true,
                    modules: [],
                    sourceRequirement: .none,
                    capabilities: try ResearchActionCapabilityDeclaration(
                        readableRoles: [.work, .topic],
                        candidateWritableRoles: [.work],
                        candidateWriteOperations: [.modifyMarkdown]
                    ),
                    feedbackRequirement: .requested
                )
            ),
            expectedDocumentRevision: initialProfileDocument.revision
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.agentNoteChangeContinuations(
                id: changedProfileRequest.id
            )
        }

        let reopenedProfileProbe = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: customActionID,
                target: actionNote(stableWork)
            )
        )
        let reopenedProfileRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: reopenedProfileProbe.snapshot
        )
        try await handle.research.cancelProtectedFunction(runID: reopenedProfileProbe.runID)
        let reopenParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let reopenRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: reopenParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: reopenParent.snapshot
            ),
            requestedAction: reopenedProfileRevision,
            targets: [try agentChangeTarget(stableWork)],
            operations: [.modifyMarkdown],
            agentReason: "Prove persisted lineage cannot restore a plaintext grant key."
        )
        _ = try await handle.submitAgentNoteChangeRequest(reopenRequest)
        _ = try await handle.resolveAgentNoteChangeRequest(
            id: reopenRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [stableWork.noteID]
        )
        let activeBeforeReopen = try #require(
            try await handle.agentNoteChangeContinuations(id: reopenRequest.id)
                .childPreparations.first?.preparation
        )
        #expect(activeBeforeReopen.instructions.contains("Write key:"))

        await runtime.shutdown()
        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(
            id: fixture.assignment.id
        )
        let reopenedChild = try await reopened.research.protectedFunctionRun(
            id: activeBeforeReopen.runID
        )
        #expect(reopenedChild.snapshot.continuationLineage
            == activeBeforeReopen.snapshot.continuationLineage)
        #expect(reopenedChild.state == .prepared)
        #expect(!reopenedChild.instructions.contains("Write key:"))
        #expect(reopenedChild.instructions.contains(
            "delivery-only write key is no longer available"
        ))
        let reopenedDelivery = try await reopened.agentNoteChangeContinuations(
            id: reopenRequest.id
        )
        #expect(reopenedDelivery.childPreparations.first?.preparation.runID
            == activeBeforeReopen.runID)
        #expect(!(reopenedDelivery.childPreparations.first?.preparation.instructions
            .contains("Activity key:") ?? true))
        try await reopened.research.cancelProtectedFunction(runID: activeBeforeReopen.runID)
        await reopenedRuntime.shutdown()
    }

    @Test("Critique and optional Manuscript parents prepare separate Write continuations")
    func critiqueAndManuscriptPermissionBoundContinuations() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let worksURL = fixture.rootURL.appendingPathComponent(
            "Works",
            isDirectory: true
        )
        let workSources = [
            ("Critique Continuation.md", "# Critique Continuation\n\nA bounded draft.\n"),
            ("Manuscript Continuation.md", "# Manuscript Continuation\n\nA chapter section.\n"),
        ]
        for (name, source) in workSources {
            try Data(source.utf8).write(
                to: worksURL.appendingPathComponent(name),
                options: .atomic
            )
        }

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let workVaultID = try #require(
            fixture.assignment.vault(for: .output)?.id
        )
        var continuationTargets: [ResearchFunctionTarget] = []
        for (name, _) in workSources {
            continuationTargets.append(try await researchFunctionTarget(
                VaultQualifiedNoteID(vaultID: workVaultID, relativePath: name),
                role: .work,
                handle: handle
            ))
        }
        let baseWork = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let writeProbe = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .write,
                target: actionNote(continuationTargets[0])
            )
        )
        let writeRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: writeProbe.snapshot
        )
        try await handle.research.cancelProtectedFunction(runID: writeProbe.runID)

        let critiqueParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .critique,
                target: actionNote(baseWork)
            )
        )
        let critiqueRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: critiqueParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: critiqueParent.snapshot
            ),
            requestedAction: writeRevision,
            targets: [try agentChangeTarget(continuationTargets[0])],
            operations: [.modifyMarkdown],
            agentReason: "Address the selected Critique in a separate Work child."
        )
        _ = try await handle.submitAgentNoteChangeRequest(critiqueRequest)
        let allowedCritique = try await handle.resolveAgentNoteChangeRequest(
            id: critiqueRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [continuationTargets[0].noteID]
        )
        let critiqueContinuation = try await handle.agentNoteChangeContinuations(
            id: critiqueRequest.id
        )
        let critiqueChild = try #require(
            critiqueContinuation.childPreparations.first?.preparation
        )
        #expect(critiqueChild.snapshot.actionSnapshot?.definition.id == .write)
        #expect(critiqueChild.snapshot.continuationLineage?.parentRunID
            == critiqueParent.runID)
        #expect(critiqueChild.snapshot.continuationLineage?.groupID
            == allowedCritique.continuationPlan?.groupID)
        try await handle.research.cancelProtectedFunction(runID: critiqueChild.runID)

        let manuscriptMethod = try await handle.research.duplicateBundledSkill(
            id: "scholium-manuscript",
            as: "session-18-manuscript-method"
        )
        let bindings = try #require(
            try await handle.research.workingMethodBindings()
        )
        _ = try await handle.research.activateResearcherSkill(
            packageID: manuscriptMethod.id,
            for: .manuscript,
            expectedBindingRevision: bindings.revision
        )
        _ = try await handle.research.saveActionProfile(
            try ResearchActionProfileBinding(
                packageID: manuscriptMethod.id,
                profile: ResearchActionProfile(
                    definition: .manuscript,
                    buttonName: "Manuscript",
                    order: 100,
                    applicableRoles: [.work],
                    showInActions: true,
                    modules: [],
                    sourceRequirement: .none,
                    capabilities: try ResearchActionCapabilityDeclaration(
                        readableRoles: [.work],
                        candidateWritableRoles: [.work],
                        candidateWriteOperations: [.modifyMarkdown]
                    ),
                    feedbackRequirement: .requested
                )
            ),
            expectedDocumentRevision: nil
        )
        let manuscriptParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .manuscript,
                target: actionNote(baseWork)
            )
        )
        let manuscriptRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: manuscriptParent.runID,
            parentAction: try AgentNoteChangeActionRevision(
                actionSnapshot: manuscriptParent.snapshot
            ),
            requestedAction: writeRevision,
            targets: [try agentChangeTarget(continuationTargets[1])],
            operations: [.modifyMarkdown],
            agentReason: "Coordinate this explicit Manuscript child as a separate Write."
        )
        _ = try await handle.submitAgentNoteChangeRequest(manuscriptRequest)
        let allowedManuscript = try await handle.resolveAgentNoteChangeRequest(
            id: manuscriptRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [continuationTargets[1].noteID]
        )
        let manuscriptContinuation = try await handle.agentNoteChangeContinuations(
            id: manuscriptRequest.id
        )
        let manuscriptChild = try #require(
            manuscriptContinuation.childPreparations.first?.preparation
        )
        #expect(manuscriptChild.snapshot.actionSnapshot?.definition.id == .write)
        #expect(manuscriptChild.snapshot.continuationLineage?.parentRunID
            == manuscriptParent.runID)
        #expect(manuscriptChild.snapshot.continuationLineage?.groupID
            == allowedManuscript.continuationPlan?.groupID)
        #expect(manuscriptChild.snapshot.continuationLineage?.groupID
            != critiqueChild.snapshot.continuationLineage?.groupID)
        try await handle.research.cancelProtectedFunction(runID: manuscriptChild.runID)
        await runtime.shutdown()
    }

    @Test("Agent Note Change requests authenticate parents, replay idempotently, expire, and reject stale scope")
    func agentNoteChangeRequestCoordination() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let alternativeURL = fixture.rootURL
            .appendingPathComponent("Works", isDirectory: true)
            .appendingPathComponent("Alternative Work.md")
        try Data("# Alternative Work\n\nA second bounded argument.\n".utf8)
            .write(to: alternativeURL, options: .atomic)

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parentTarget = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let parentNote = actionNote(parentTarget)
        let parentRequest = try await actionRequest(
            handle: handle,
            actionID: .write,
            target: parentNote
        )
        let parent = try await handle.research.prepareAction(parentRequest)
        let parentRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: parent.snapshot
        )

        let workVaultID = try #require(
            fixture.assignment.vault(for: .output)?.id
        )
        let alternativeID = VaultQualifiedNoteID(
            vaultID: workVaultID,
            relativePath: "Alternative Work.md"
        )
        var alternativeTarget = try await researchFunctionTarget(
            alternativeID,
            role: .work,
            handle: handle
        )
        let requestID = UUID()
        let request = try AgentNoteChangeRequest(
            requestID: requestID,
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Develop the second Work as an alternative argument."
        )
        let receivedAt = Date(timeIntervalSince1970: 10_000)
        let first = try await handle.research.submitAgentNoteChangeRequest(
            request,
            receivedAt: receivedAt,
            validFor: 1
        )
        let replay = try await handle.research.submitAgentNoteChangeRequest(
            request,
            receivedAt: receivedAt.addingTimeInterval(0.5),
            validFor: 1
        )
        #expect(replay == first)
        #expect(first.decision.state == .pending)

        let changedPayload = try AgentNoteChangeRequest(
            requestID: requestID,
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Use the same ID for a different request."
        )
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.submitAgentNoteChangeRequest(
                changedPayload,
                receivedAt: receivedAt
            )
        }
        let competing = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Compete for the same unresolved parent."
        )
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.submitAgentNoteChangeRequest(
                competing,
                receivedAt: receivedAt.addingTimeInterval(0.5)
            )
        }

        let forged = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: UUID(),
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Use a parent that Scholium never prepared."
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.research.submitAgentNoteChangeRequest(forged)
        }
        let crossTriptych = try AgentNoteChangeRequest(
            triptychID: UUID(),
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Cross a Triptych boundary."
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.research.submitAgentNoteChangeRequest(crossTriptych)
        }

        let expired = try await handle.research.agentNoteChangeRequest(
            id: requestID,
            now: receivedAt.addingTimeInterval(2)
        )
        #expect(expired.decision.state == .expired)

        let mismatchedSkillRevision = try AgentNoteChangeActionRevision(
            definition: parentRevision.definition,
            packageID: parentRevision.packageID,
            skillRevision: DocumentFingerprint(content: "different skill"),
            profileOrigin: parentRevision.profileOrigin,
            profileRevision: parentRevision.profileRevision,
            profileDocumentRevision: parentRevision.profileDocumentRevision
        )
        let skillMismatch = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: mismatchedSkillRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Claim a Method Skill revision that is not installed."
        )
        #expect(try await handle.research.submitAgentNoteChangeRequest(
            skillMismatch,
            receivedAt: receivedAt.addingTimeInterval(2.1)
        ).decision.state == .stale)

        let mismatchedProfileRevision = try AgentNoteChangeActionRevision(
            definition: parentRevision.definition,
            packageID: parentRevision.packageID,
            skillRevision: parentRevision.skillRevision,
            profileOrigin: parentRevision.profileOrigin,
            profileRevision: DocumentFingerprint(content: "different profile"),
            profileDocumentRevision: parentRevision.profileDocumentRevision
        )
        let profileMismatch = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: mismatchedProfileRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Claim an Action Profile revision that is not current."
        )
        #expect(try await handle.research.submitAgentNoteChangeRequest(
            profileMismatch,
            receivedAt: receivedAt.addingTimeInterval(2.2)
        ).decision.state == .stale)

        let oldTarget = actionNote(alternativeTarget)
        let document = try await handle.documents.load(alternativeID)
        let saved = try await handle.documents.save(
            alternativeID,
            changeSet: .exactContent(
                document.rawContent + "\nChanged after the request was assembled.\n"
            ),
            expectedRevision: document.fingerprint
        )
        #expect(saved.document.fingerprint != oldTarget.fingerprint)
        alternativeTarget = try await researchFunctionTarget(
            alternativeID,
            role: .work,
            handle: handle
        )
        #expect(alternativeTarget.fingerprint == saved.document.fingerprint)

        let stale = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: parentRevision,
            requestedAction: parentRevision,
            targets: [
                try AgentNoteChangeTarget(snapshot: parentNote),
                try AgentNoteChangeTarget(snapshot: oldTarget),
            ],
            operations: [.modifyMarkdown],
            agentReason: "Try a current first target and stale second target."
        )
        let staleRecord = try await handle.research.submitAgentNoteChangeRequest(
            stale,
            receivedAt: receivedAt.addingTimeInterval(3)
        )
        #expect(staleRecord.decision.state == .stale)
        #expect(try await handle.research.pendingAgentNoteChangeRequests(
            now: receivedAt.addingTimeInterval(4)
        ).isEmpty)

        let cancelledParent = try await handle.research.prepareAction(parentRequest)
        let cancelledParentRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: cancelledParent.snapshot
        )
        let pendingBeforeCancellation = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: cancelledParent.runID,
            parentAction: cancelledParentRevision,
            requestedAction: cancelledParentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Request another Work before the parent is cancelled."
        )
        let pendingRecord = try await handle.research.submitAgentNoteChangeRequest(
            pendingBeforeCancellation,
            receivedAt: receivedAt.addingTimeInterval(5),
            validFor: 60
        )
        #expect(pendingRecord.decision.state == .pending)
        try await handle.research.cancelProtectedFunction(runID: cancelledParent.runID)
        #expect(try await handle.research.agentNoteChangeRequest(
            id: pendingBeforeCancellation.id,
            now: receivedAt.addingTimeInterval(6)
        ).decision.state == .stale)

        let afterCancellation = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: cancelledParent.runID,
            parentAction: cancelledParentRevision,
            requestedAction: cancelledParentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "Try to continue from a cancelled parent."
        )
        #expect(try await handle.research.submitAgentNoteChangeRequest(
            afterCancellation,
            receivedAt: receivedAt.addingTimeInterval(7)
        ).decision.state == .stale)

        let deletionParent = try await handle.research.prepareAction(parentRequest)
        let deletionParentRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: deletionParent.snapshot
        )
        let requestRacingDeletion = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: deletionParent.runID,
            parentAction: deletionParentRevision,
            requestedAction: deletionParentRevision,
            targets: [try agentChangeTarget(alternativeTarget)],
            operations: [.modifyMarkdown],
            agentReason: "This private reason must not outlive permanent deletion of its parent."
        )
        let movedToTrash = try await handle.documents.moveToTrash(
            fixture.workID,
            expectedRevision: parentTarget.fingerprint
        )
        let trashedWork = try await handle.documents.load(movedToTrash.destination)
        let deletion = Task {
            try await handle.documents.deletePermanently(
                movedToTrash.destination,
                expectedRevision: trashedWork.fingerprint
            )
        }
        await Task.yield()
        do {
            _ = try await handle.research.submitAgentNoteChangeRequest(
                requestRacingDeletion
            )
        } catch let error as AgentNoteChangeOperationError {
            guard case .parentRunNotFound(let runID) = error,
                  runID == deletionParent.runID else {
                Issue.record("Unexpected deletion-race refusal: \(error)")
                _ = try await deletion.value
                await runtime.shutdown()
                return
            }
        }
        _ = try await deletion.value
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.agentNoteChangeRequest(
                id: requestRacingDeletion.id
            )
        }
        await runtime.shutdown()
    }

    @Test("Agent Note Change decisions revalidate live scope and standing policy")
    func agentNoteChangeDecisionRevalidation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let additionalURL = fixture.rootURL
            .appendingPathComponent("Works", isDirectory: true)
            .appendingPathComponent("Decision Target.md")
        try Data("# Decision Target\n\nA bounded candidate.\n".utf8)
            .write(to: additionalURL, options: .atomic)

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parentTarget = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let parentRequest = try await actionRequest(
            handle: handle,
            actionID: .write,
            target: actionNote(parentTarget)
        )
        let vaultID = try #require(fixture.assignment.vault(for: .output)?.id)
        let targetID = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Decision Target.md"
        )
        var target = try await researchFunctionTarget(
            targetID,
            role: .work,
            handle: handle
        )

        let firstParent = try await handle.research.prepareAction(parentRequest)
        let firstRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: firstParent.snapshot
        )
        let firstRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: firstParent.runID,
            parentAction: firstRevision,
            requestedAction: firstRevision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "Permit this exact additional Work only once."
        )
        let pending = try await handle.research.submitAgentNoteChangeRequest(
            firstRequest
        )
        #expect(pending.decision.state == .pending)
        let allowed = try await handle.research.resolveAgentNoteChangeRequest(
            id: firstRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [target.noteID]
        )
        #expect(allowed.decision.state == .allowedSubset)
        #expect(allowed.decision.allowedNoteIDs == [target.noteID])

        let secondParent = try await handle.research.prepareAction(parentRequest)
        let secondRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: secondParent.snapshot
        )
        let staleRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: secondParent.runID,
            parentAction: secondRevision,
            requestedAction: secondRevision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "This request must become stale after the Note changes."
        )
        _ = try await handle.research.submitAgentNoteChangeRequest(staleRequest)
        let document = try await handle.documents.load(targetID)
        _ = try await handle.documents.save(
            targetID,
            changeSet: .exactContent(document.rawContent + "\nChanged.\n"),
            expectedRevision: document.fingerprint
        )
        let stale = try await handle.research.resolveAgentNoteChangeRequest(
            id: staleRequest.id,
            state: .allowedSubset,
            allowedNoteIDs: [target.noteID]
        )
        #expect(stale.decision.state == .stale)
        target = try await researchFunctionTarget(
            targetID,
            role: .work,
            handle: handle
        )

        // This is the durable state left if Cancel the Run commits its parent
        // cancellation but the request decision write is interrupted.
        let cancellationParent = try await handle.research.prepareAction(parentRequest)
        let cancellationRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: cancellationParent.snapshot
        )
        let cancellationRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: cancellationParent.runID,
            parentAction: cancellationRevision,
            requestedAction: cancellationRevision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "Preserve the researcher's explicit cancellation on retry."
        )
        _ = try await handle.research.submitAgentNoteChangeRequest(
            cancellationRequest
        )
        try await handle.research.cancelProtectedFunction(runID: cancellationParent.runID)
        let recoveredCancellation = try await handle.research
            .resolveAgentNoteChangeRequest(
                id: cancellationRequest.id,
                state: .cancelled
            )
        #expect(recoveredCancellation.decision.state == .cancelled)

        let settings = try await handle.research.permissionSettings()
        _ = try await handle.research.saveTriptychPermissionPolicy(
            .triptychWide,
            expectedRevision: settings.policy.revision
        )
        let automaticParent = try await handle.research.prepareAction(parentRequest)
        let automaticRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: automaticParent.snapshot
        )
        let automaticRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: automaticParent.runID,
            parentAction: automaticRevision,
            requestedAction: automaticRevision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "Use the current Triptych-wide standing policy."
        )
        let automatic = try await handle.research.submitAgentNoteChangeRequest(
            automaticRequest
        )
        #expect(automatic.decision.state == .allowedSubset)
        #expect(automatic.decision.allowedNoteIDs == [target.noteID])

        await runtime.shutdown()
    }

    @Test("The Agent bridge key authenticates submit, status, and idempotent cancellation")
    func agentBridgeCoordinationKey() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let alternativeURL = fixture.rootURL
            .appendingPathComponent("Works", isDirectory: true)
            .appendingPathComponent("Bridge Target.md")
        try Data("# Bridge Target\n\nA bounded alternative.\n".utf8)
            .write(to: alternativeURL, options: .atomic)

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let parentTarget = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let parent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .write,
                target: actionNote(parentTarget)
            )
        )
        let marker = "Coordination key: "
        let line = try #require(parent.instructions.split(separator: "\n")
            .first(where: { $0.hasPrefix(marker) }))
        let key = String(line.dropFirst(marker.count))
        #expect(key.utf8.count == 73)

        let vaultID = try #require(fixture.assignment.vault(for: .output)?.id)
        let target = try await researchFunctionTarget(
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Bridge Target.md"),
            role: .work,
            handle: handle
        )
        let revision = try AgentNoteChangeActionRevision(
            actionSnapshot: parent.snapshot
        )
        let request = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: parent.runID,
            parentAction: revision,
            requestedAction: revision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "Continue with this additional Work only if Scholium permits it."
        )

        let copiedGrantParent = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .write,
                target: actionNote(parentTarget)
            )
        )
        let executionDirectory = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v2", isDirectory: true)
        let firstExecutionURL = executionDirectory
            .appendingPathComponent(parent.runID.uuidString.lowercased() + ".json")
        let copiedExecutionURL = executionDirectory.appendingPathComponent(
            copiedGrantParent.runID.uuidString.lowercased() + ".json"
        )
        let firstExecution = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: firstExecutionURL)
            ) as? [String: Any]
        )
        var copiedExecution = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: copiedExecutionURL)
            ) as? [String: Any]
        )
        copiedExecution["agent_coordination_grant"] = firstExecution[
            "agent_coordination_grant"
        ]
        try JSONSerialization.data(
            withJSONObject: copiedExecution,
            options: [.sortedKeys]
        ).write(to: copiedExecutionURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: copiedExecutionURL.path
        )
        let copiedRevision = try AgentNoteChangeActionRevision(
            actionSnapshot: copiedGrantParent.snapshot
        )
        let copiedGrantRequest = try AgentNoteChangeRequest(
            triptychID: fixture.assignment.id,
            parentRunID: copiedGrantParent.runID,
            parentAction: copiedRevision,
            requestedAction: copiedRevision,
            targets: [try agentChangeTarget(target)],
            operations: [.modifyMarkdown],
            agentReason: "Attempt to replay another parent run's copied grant."
        )
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.submitAgentNoteChangeRequestFromBridge(
                copiedGrantRequest,
                coordinationKey: key
            )
        }

        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.research.submitAgentNoteChangeRequestFromBridge(
                request,
                coordinationKey: String(repeating: "x", count: 73)
            )
        }
        let submitted = try await handle.research
            .submitAgentNoteChangeRequestFromBridge(
                request,
                coordinationKey: key
            )
        #expect(submitted.decision.state == .pending)
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.research.agentNoteChangeRequestFromBridge(
                id: request.id,
                coordinationKey: String(repeating: "x", count: 73),
                now: submitted.expiresAt.addingTimeInterval(1)
            )
        }
        let requestURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("agent-change-requests-v1", isDirectory: true)
            .appendingPathComponent(request.id.uuidString.lowercased() + ".json")
        let requestDecoder = JSONDecoder()
        requestDecoder.dateDecodingStrategy = .deferredToDate
        #expect(try requestDecoder.decode(
            AgentNoteChangeRequestRecord.self,
            from: Data(contentsOf: requestURL)
        ).decision.state == .pending)
        #expect(try await handle.research.agentNoteChangeRequestFromBridge(
            id: request.id,
            coordinationKey: key
        ) == submitted)
        let cancelled = try await handle.research
            .cancelAgentNoteChangeRequestFromBridge(
                id: request.id,
                coordinationKey: key
            )
        #expect(cancelled.decision.state == .cancelled)
        #expect(try await handle.research.cancelAgentNoteChangeRequestFromBridge(
            id: request.id,
            coordinationKey: key
        ) == cancelled)
        #expect(try await handle.research.submitAgentNoteChangeRequestFromBridge(
            request,
            coordinationKey: key
        ) == cancelled)
        let secondRequest = try AgentNoteChangeRequest(
            triptychID: request.triptychID,
            parentRunID: request.parentRunID,
            parentAction: request.parentAction,
            requestedAction: request.requestedAction,
            targets: request.targets,
            operations: request.operations,
            agentReason: "Attempt a second request after the first is terminal."
        )
        await #expect(throws: AgentNoteChangeOperationError.self) {
            _ = try await handle.research.submitAgentNoteChangeRequestFromBridge(
                secondRequest,
                coordinationKey: key
            )
        }

        let persistedFiles = FileManager.default.enumerator(
            at: fixture.applicationSupportURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = persistedFiles?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey])
                .isRegularFile == true else { continue }
            #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self)
                .contains(key))
        }
        await runtime.shutdown()
    }

    func actionNote(
        _ target: ResearchFunctionTarget
    ) -> ResearchActionNoteSnapshot {
        let role: ResearchActionTargetRole = switch target.role {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
        return ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: role,
            lifecycle: target.lifecycle,
            fingerprint: target.fingerprint,
            title: target.title
        )
    }

    func agentChangeTarget(
        _ target: ResearchFunctionTarget
    ) throws -> AgentNoteChangeTarget {
        try AgentNoteChangeTarget(snapshot: actionNote(target))
    }

    func actionRequest(
        handle: WorkspaceHandle,
        actionID: ResearchActionID,
        expectedExecutionKind: ResearchActionExecutionKind? = nil,
        target: ResearchActionNoteSnapshot,
        parameterValues: [ResearchActionModuleID: ResearchActionParameterValue] = [:]
    ) async throws -> ResearchActionExecutionRequest {
        let availability = try await handle.research.availableActions(for: target)
        let presented = try #require(availability.first { $0.id == actionID })
        return ResearchActionExecutionRequest(
            actionID: actionID,
            expectedExecutionKind:
                expectedExecutionKind ?? presented.definition.executionKind,
            expectedProfileRevision: presented.profile.profileRevision,
            expectedProfileDocumentRevision:
                presented.profile.profileDocumentRevision,
            target: target,
            parameterValues: parameterValues
        )
    }

    func customActionProfileBinding(
        actionID: ResearchActionID,
        packageID: String,
        moduleID: String,
        buttonName: String,
        readableRoles: [ResearchActionTargetRole] = [.topic],
        feedbackRequirement: ResearchActionFeedbackRequirement = .requested
    ) throws -> ResearchActionProfileBinding {
        let definition = try ResearchActionDefinition(
            researcherOwnedID: actionID,
            executionKind: .discussion
        )
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: buttonName,
            order: 25,
            applicableRoles: [.topic],
            showInActions: true,
            modules: [
                try .boundedText(
                    id: ResearchActionModuleID(rawValue: moduleID)!,
                    label: "Question",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 1_200,
                    allowsMultipleLines: true
                ),
            ],
            sourceRequirement: .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: readableRoles
            ),
            feedbackRequirement: feedbackRequirement
        )
        return try ResearchActionProfileBinding(
            packageID: packageID,
            profile: profile
        )
    }

    func customActionSkillSource(
        actionID: ResearchActionID
    ) -> String {
        """
        ---
        name: Socratic Pressure
        description: Develop one attributed dialectical exchange.
        scholium:
          role: specialist
          supported_actions: [\(actionID.rawValue)]
          supported_functions: [discuss]
          capabilities: []
          supported_modes: [all]
          required_skills: []
        ---
        Ask precise questions and preserve unresolved pressure.
        """ + "\n"
    }

    static let zoteroItemJSON = #"""
    {
      "key": "META0001",
      "data": {
        "key": "META0001",
        "itemType": "journalArticle",
        "title": "Fittingness",
        "creators": [
          {"creatorType":"author","firstName":"Richard","lastName":"Chappell"},
          {"creatorType":"editor","firstName":"Example","lastName":"Editor"}
        ],
        "date": "2012",
        "language": "en",
        "publicationTitle": "The Philosophical Quarterly",
        "volume": "62",
        "issue": "249",
        "pages": "684-704",
        "DOI": "10.1111/example",
        "ISSN": "0031-8094",
        "citationKey": "ChappellFittingness2012",
        "abstractNote": "A bibliographic abstract.",
        "tags": [{"tag":"fittingness"},{"tag":"value"}],
        "collections": [],
        "dateModified": "2026-07-12T10:30:00Z"
      }
    }
    """#
}
