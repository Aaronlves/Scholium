import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchFunctionOperationsTests {
    @Test("Split Methods are complete and expose no legacy conditional mode selection")
    func splitMethodsNeedNoResourceSelection() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let material = try #require(
            try await handle.research.protectedMaterialCandidates(
                for: target,
                function: .develop
            ).first { $0.material.note == fixture.topicID }?.material
        )
        let preflight = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .develop,
                target: target,
                materials: [material]
            )
        )
        let baseResources = Set(preflight.snapshot.phases
            .flatMap(\.skills)
            .flatMap(\.loadedResources)
            .map(\.relativePath))
        #expect(baseResources.contains("references/method.md"))
        #expect(!baseResources.contains("references/synthesis.md"))
        #expect(!preflight.awaitsResourceSelection)
        #expect(preflight.instructions.contains("scholium action complete --from"))
        try await handle.research.cancelProtectedFunction(runID: preflight.runID)
        await runtime.shutdown()
    }

    @Test("Preparation rejects stale Target and Material fingerprints without checkpoint or record residue")
    func fingerprintValidationAndRollback() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.protectedMaterialCandidates(
            for: target,
            function: .develop
        )
        #expect(!candidates.contains { $0.material.noteID == target.noteID })
        let topic = try #require(candidates.first {
            $0.material.note == fixture.topicID
        }?.material)
        let originalRuns = try await handle.services.localResearchExecutionStore.listing().records.count
        let originalCheckpoints = try await handle.research.checkpoints().checkpoints.count

        let topicDocument = try await handle.documents.load(fixture.topicID)
        _ = try await handle.documents.save(
            fixture.topicID,
            changeSet: .exactContent(topicDocument.rawContent + "\nA changed Material.\n"),
            expectedRevision: topicDocument.fingerprint
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.prepareProtectedFunction(
                ResearchFunctionRequest(
                    function: .develop,
                    target: target,
                    materials: [topic]
                )
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.count == originalCheckpoints)
        #expect(try await handle.services.localResearchExecutionStore.listing().records.count == originalRuns)

        let targetDocument = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(targetDocument.rawContent + "\nA changed Target.\n"),
            expectedRevision: targetDocument.fingerprint
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.prepareProtectedFunction(
                ResearchFunctionRequest(function: .develop, target: target)
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.count == originalCheckpoints)
        #expect(try await handle.services.localResearchExecutionStore.listing().records.count == originalRuns)
        await runtime.shutdown()
    }

    @Test("Material suggestions use only resolved one-hop links and preserve catalog aliases")
    func materialCandidateSuggestions() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.protectedMaterialCandidates(
            for: target,
            function: .develop
        )

        let agency = try #require(candidates.first {
            $0.material.note == fixture.topicID
        })
        #expect(agency.aliases.contains("Freedom"))
        #expect(agency.suggestionReasons.map(\.kind) == [.linkedFromTarget])
        #expect(agency.suggestionReasons.first?.sourceNote == target.note)

        let work = try #require(candidates.first {
            $0.material.note == fixture.workID
        })
        #expect(work.suggestionReasons.map(\.kind) == [.linksDirectlyToTarget])
        #expect(work.suggestionReasons.first?.sourceNote == fixture.workID)

        let transitive = try #require(candidates.first {
            $0.material.note.relativePath == "Debates/Nested Topic.md"
        })
        #expect(transitive.suggestionReasons.isEmpty)
        #expect(!candidates.contains { $0.material.note == target.note })
        await runtime.shutdown()
    }

    @Test("Action-backed write phases reject multi-note grants before checkpoint")
    func actionWriteScopeIsCurrentTargetOnly() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let checkpointCount = try await handle.research.checkpoints().checkpoints.count
        let invalidRequests = [
            ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                writeScope: .selectedNotes,
                authorizedWriteTargets: [analysis, topic]
            ),
            ResearchFunctionRequest(
                function: .develop,
                target: topic,
                writeScope: .analysesAndTopics,
                authorizedWriteTargets: [analysis, topic]
            ),
            ResearchFunctionRequest(
                function: .revise,
                target: work,
                writeScope: .entireTriptych,
                authorizedWriteTargets: [analysis, topic, work]
            ),
        ]

        for request in invalidRequests {
            await #expect(throws: ResearchFunctionContractError.self) {
                _ = try await handle.research.prepareProtectedFunction(request)
            }
        }
        #expect(try await handle.research.checkpoints().checkpoints.count == checkpointCount)

        let valid = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: analysis)
        )
        #expect(valid.snapshot.request.writeScope == .currentNote)
        #expect(valid.snapshot.request.authorizedWriteTargets.map(\.noteID) == [
            analysis.noteID,
        ])
        try await handle.research.cancelProtectedFunction(runID: valid.runID)
        await runtime.shutdown()
    }

    @Test("Automatic Fidelity prepares an independent final-revision child and reuses its evidence")
    func automaticFidelityOrchestration() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA developed claim.\n"),
            expectedRevision: original.fingerprint
        ).committedValue
        let activityCompletion = try researchActivityCompletion(
            for: develop,
            candidateModifiedNotes: [fixture.analysisID],
            summary: "Developed one bounded claim."
        )
        let awaiting = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed one bounded claim.",
                didModifyTarget: true,
                activityCompletion: activityCompletion
            )
        )
        #expect(awaiting.state == .awaitingFidelity)

        let afterCompletion = try await handle.services.localResearchExecutionStore.listing().records
        #expect(afterCompletion.first { record in
            record.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        } == nil)

        let automatic = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(automatic.state == .prepared)
        #expect(automatic.preparation.snapshot.resolvedFidelityInvocation == .automatic(
            parentRunID: develop.runID
        ))
        #expect(automatic.preparation.snapshot.request.target.fingerprint
            == saved.document.fingerprint)
        #expect(automatic.preparation.snapshot.request.checks
            == develop.snapshot.fidelityHandoff?.checks)
        #expect(automatic.preparation.snapshot.request.materials
            == develop.snapshot.request.materials)
        #expect(automatic.preparation.snapshot.request.scope
            == develop.snapshot.request.scope)
        #expect(automatic.preparation.snapshot.request.commentIDs
            == develop.snapshot.request.commentIDs)

        let repeated = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(repeated.state == .prepared)
        #expect(repeated.effectiveFidelityRunID == automatic.effectiveFidelityRunID)
        #expect(try await handle.services.localResearchExecutionStore.listing().records.filter {
            $0.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        }.count == 1)

        let fidelityCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: automatic.preparation.runID,
                confirmationToken: automatic.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Checked the exact final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let completedProjection = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(completedProjection.state == .complete)
        #expect(completedProjection.effectiveFidelityRunID == fidelityCompletion.runID)

        let verified = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                activityCompletion: activityCompletion,
                childRunIDs: [automatic.preparation.runID]
            )
        )
        #expect(verified.state == .complete)
        #expect(verified.reusedFidelityRunID == fidelityCompletion.runID)

        let currentTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let manualReuse = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: currentTarget,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        #expect(manualReuse.state == .complete)
        #expect(manualReuse.reusedCompletion?.runID == fidelityCompletion.runID)
        #expect(manualReuse.snapshot.resolvedFidelityInvocation == .manual)
        await runtime.shutdown()
    }

    @Test("Local Action automatic Fidelity preserves the accepted external retry digest")
    func localActionAutomaticFidelityRetryIsIdempotent() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(target)
            )
        )
        let parent = try await handle.research.protectedFunctionRun(id: action.runID)
        let original = try await handle.documents.load(fixture.analysisID)
        let saved = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA source-bound claim.\n"),
            expectedRevision: original.fingerprint
        ).committedValue
        let submittedAt = Date()
        let activity = try researchActivityCompletion(
            for: parent,
            candidateModifiedNotes: [fixture.analysisID],
            summary: "Added one source-bound claim.",
            submittedAt: submittedAt
        )
        let awaiting = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: parent.runID,
                confirmationToken: parent.snapshot.confirmationToken,
                summary: "Added one source-bound claim.",
                didModifyTarget: true,
                activityCompletion: activity,
                submittedAt: submittedAt
            )
        )
        #expect(awaiting.state == .awaitingFidelity)
        let automatic = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: parent.runID
        )
        let fidelitySubmittedAt = Date()
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: automatic.preparation.runID,
                confirmationToken: automatic.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: saved.document.fingerprint,
                summary: "Checked the exact final Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent],
                submittedAt: fidelitySubmittedAt
            )
        )

        let retry = ResearchFunctionCompletionSubmission(
            runID: parent.runID,
            confirmationToken: parent.snapshot.confirmationToken,
            summary: "Added one source-bound claim.",
            didModifyTarget: true,
            submittedAt: submittedAt
        )
        let localURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v2", isDirectory: true)
            .appendingPathComponent(parent.runID.uuidString.lowercased() + ".json")
        let recordsURL = fixture.rootURL.appendingPathComponent(
            ".scholium/research-records/v1/records",
            isDirectory: true
        )
        let originalMode = try #require(
            (FileManager.default.attributesOfItem(atPath: recordsURL.path)[
                .posixPermissions
            ] as? NSNumber)?.intValue
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o500)],
            ofItemAtPath: recordsURL.path
        )
        await #expect(throws: Error.self) {
            _ = try await handle.research.completeProtectedFunction(retry)
        }
        let interruptedDecoder = JSONDecoder()
        interruptedDecoder.dateDecodingStrategy = .deferredToDate
        let interrupted = try interruptedDecoder.decode(
            LocalExecutionTestProjection.self,
            from: Data(contentsOf: localURL)
        )
        #expect(interrupted.completion?.state == .complete)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: originalMode)],
            ofItemAtPath: recordsURL.path
        )

        let completed = try await handle.research.completeProtectedFunction(retry)
        #expect(completed.state == .complete)
        #expect(completed.actuallyUsedMaterialNoteIDs == [])
        #expect(completed.childRunIDs == [automatic.effectiveFidelityRunID])
        #expect(try await handle.research.completeProtectedFunction(retry) == completed)
        let portableURL = recordsURL.appendingPathComponent(
            parent.runID.uuidString.lowercased() + ".json"
        )
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        #expect(portable.actuallyUsedMaterials.isEmpty)
        #expect(portable.fidelityCompletion == .completed)
        await runtime.shutdown()
    }

    @Test("Unchanged Develop and Revise runs complete without Automatic Fidelity")
    func unchangedWritesSkipAutomaticFidelity() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: analysis, conditionalResources: [])
        )

        // Even matching completed manual evidence cannot be attached to an
        // unchanged substantive run: there is no post-edit revision to audit.
        let manual = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: analysis,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: manual.runID,
                confirmationToken: manual.snapshot.confirmationToken,
                finalTargetFingerprint: analysis.fingerprint,
                summary: "Checked the unchanged Analysis revision manually.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "No Analysis change was needed.",
                    didModifyTarget: false,
                    activityCompletion: try researchActivityCompletion(
                        for: develop,
                        candidateModifiedNotes: [],
                        summary: "No Analysis change was needed."
                    ),
                    childRunIDs: [manual.runID]
                )
            )
        }

        let unchangedDevelopActivity = try researchActivityCompletion(
            for: develop,
            candidateModifiedNotes: [],
            summary: "No Analysis change was needed."
        )
        let unchangedDevelop = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "No Analysis change was needed.",
                didModifyTarget: false,
                activityCompletion: unchangedDevelopActivity
            )
        )
        #expect(unchangedDevelop.state == .complete)
        #expect(!unchangedDevelop.didModifyTarget)
        #expect(unchangedDevelop.childRunIDs == nil)
        #expect(unchangedDevelop.reusedFidelityRunID == nil)

        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let revise = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let unchangedReviseActivity = try researchActivityCompletion(
            for: revise,
            candidateModifiedNotes: [],
            summary: "No Work change was needed."
        )
        let unchangedRevise = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "No Work change was needed.",
                didModifyTarget: false,
                activityCompletion: unchangedReviseActivity
            )
        )
        #expect(unchangedRevise.state == .complete)
        #expect(!unchangedRevise.didModifyTarget)
        #expect(unchangedRevise.childRunIDs == nil)
        #expect(unchangedRevise.reusedFidelityRunID == nil)

        for parentRunID in [develop.runID, revise.runID] {
            await #expect(throws: ResearchFunctionContractError.self) {
                _ = try await handle.research.prepareProtectedAutomaticFidelity(
                    parentRunID: parentRunID
                )
            }
        }
        let records = try await handle.services.localResearchExecutionStore.listing().records
        let automaticChildren = records.filter { record in
            guard case .automatic(let parentRunID)? =
                    record.snapshot.resolvedFidelityInvocation else {
                return false
            }
            return parentRunID == develop.runID || parentRunID == revise.runID
        }
        #expect(automaticChildren.isEmpty)
        await runtime.shutdown()
    }

    @Test("Automatic Fidelity immediately links exact completed manual evidence")
    func automaticFidelityReusesCompletedManualEvidence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        let original = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA developed claim.\n"),
            expectedRevision: original.fingerprint
        )
        let finalTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let manual = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: try #require(develop.snapshot.fidelityHandoff).checks
            )
        )
        let manualCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: manual.runID,
                confirmationToken: manual.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )

        let activityCompletion = try researchActivityCompletion(
            for: develop,
            candidateModifiedNotes: [fixture.analysisID],
            summary: "Developed one bounded claim."
        )
        let awaiting = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed one bounded claim.",
                didModifyTarget: true,
                activityCompletion: activityCompletion
            )
        )
        #expect(awaiting.state == .awaitingFidelity)
        let completed = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed one bounded claim.",
                didModifyTarget: true,
                childRunIDs: [manualCompletion.runID]
            )
        )
        #expect(completed.state == .complete)
        #expect(completed.reusedFidelityRunID == manualCompletion.runID)
        #expect(completed.childRunIDs == [manualCompletion.runID])
        #expect(try await handle.services.localResearchExecutionStore.listing().records.filter {
            $0.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        }.isEmpty)
        await runtime.shutdown()
    }

    @Test("Develop records its exact Fidelity handoff, advances completion, deduplicates exact audits, and marks later evidence stale")
    func fidelityHandoffDeduplicationAndStaleness() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        #expect(develop.snapshot.checkpointID == nil)
        #expect(develop.snapshot.phases.map(\.function) == [.develop])
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(develop.snapshot.fidelityHandoff?.checks == [.content])
        #expect(develop.snapshot.fidelityHandoff?.preparedTargetFingerprint == target.fingerprint)
        #expect(!develop.instructions.contains("## Isolated phase 2: fidelity"))
        #expect(develop.instructions.contains(
            "Awaiting Fidelity only for a confirmed change"
        ))
        let developmentResources = Set(develop.snapshot.phases
            .first { $0.function == .develop }?.skills
            .flatMap(\.loadedResources).map(\.relativePath) ?? [])
        #expect(developmentResources.contains("references/method.md"))
        #expect(!developmentResources.contains("references/exploration.md"))
        #expect(!developmentResources.contains("references/synthesis.md"))
        #expect(!developmentResources.contains("references/expression.md"))
        #expect(!developmentResources.contains("references/definition-impact.md"))
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == develop.runID
        })

        let preEditFidelity = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content]
            )
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: preEditFidelity.runID,
                confirmationToken: preEditFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked only the pre-edit Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )

        let original = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(original.rawContent + "\nA bounded developed claim.\n"),
            expectedRevision: original.fingerprint
        )
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == develop.runID
        })
        let activityCompletion = try researchActivityCompletion(
            for: develop,
            candidateModifiedNotes: [fixture.analysisID],
            summary: "Developed one bounded claim."
        )
        let awaitingSubmission = ResearchFunctionCompletionSubmission(
            runID: develop.runID,
            confirmationToken: develop.snapshot.confirmationToken,
            summary: "Developed one bounded claim.",
            didModifyTarget: true,
            activityCompletion: activityCompletion
        )
        let awaiting = try await handle.research.completeProtectedFunction(awaitingSubmission)
        #expect(awaiting.state == .awaitingFidelity)
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "Tried to reuse an audit of the pre-edit revision.",
                    didModifyTarget: true,
                    activityCompletion: activityCompletion,
                    childRunIDs: [preEditFidelity.runID]
                )
            )
        }
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "Tried to attach an unprepared audit claim.",
                    didModifyTarget: true,
                    activityCompletion: activityCompletion,
                    fidelityOutcomes: [.passedContent]
                )
            )
        }

        let finalTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let finalFidelity = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: [.content]
            )
        )
        let finalFidelityCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: finalFidelity.runID,
                confirmationToken: finalFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact post-edit Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let verified = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                activityCompletion: activityCompletion,
                childRunIDs: [finalFidelity.runID]
            )
        )
        #expect(verified.state == .complete)
        #expect(verified.fidelityEvidenceKey == finalFidelityCompletion.fidelityEvidenceKey)
        #expect(verified.reusedFidelityRunID == finalFidelity.runID)

        let directReuse = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: finalTarget,
                checks: [.content]
            )
        )
        #expect(directReuse.state == .complete)
        #expect(directReuse.reusedCompletion?.runID == finalFidelity.runID)

        let auditRequest = ResearchFunctionRequest(
            function: .fidelity,
            target: finalTarget,
            checks: [.content]
        )
        let audit = try await handle.research.prepareProtectedFunction(auditRequest)
        #expect(audit.state == .complete)
        let auditCompletion = try #require(audit.reusedCompletion)
        let reused = try await handle.research.prepareProtectedFunction(auditRequest)
        #expect(reused.state == .complete)
        #expect(reused.reusedCompletion?.runID == auditCompletion.runID)

        let current = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(current.rawContent + "\nEvidence changed after audit.\n"),
            expectedRevision: current.fingerprint
        )
        let changedTarget = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let changedAudit = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: changedTarget,
                checks: [.content]
            )
        )
        #expect(changedAudit.state == .prepared)
        #expect(changedAudit.runID != auditCompletion.runID)
        try await handle.research.cancelProtectedFunction(runID: changedAudit.runID)
        await runtime.shutdown()
    }

    @Test("Explicit citation style reaches Fidelity resources, instructions, snapshots, and evidence")
    func citationStyleExecutionBinding() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let status = try await handle.research.adoptBundledCitationStarter(
            expectedBindingRevision: nil
        )
        #expect(status.activeCitationStyle == "apa-7")
        #expect(status.activePackageID != nil)

        let target = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let fidelity = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                checks: [.content, .citations]
            )
        )
        let phase = try #require(fidelity.snapshot.phases.first {
            $0.function == .fidelity
        })
        #expect(phase.citationStyle == "apa-7")
        #expect(phase.skills.flatMap(\.loadedResources).contains {
            $0.relativePath == "references/apa-7-starter.md"
        })
        #expect(fidelity.instructions.contains("Citation style: apa-7"))

        let completion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
                finalTargetFingerprint: target.fingerprint,
                summary: "Checked content and citations under the selected style.",
                didModifyTarget: false,
                fidelityOutcomes: [
                    .passed(.content),
                    .passed(.citations),
                ]
            )
        )
        #expect(completion.fidelityEvidenceKey != nil)

        let develop = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: target, conditionalResources: [])
        )
        #expect(develop.snapshot.fidelityHandoff?.checks == [.content, .citations])
        #expect(develop.snapshot.phases.map(\.function) == [.develop])
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(!develop.instructions.contains("Citation style: apa-7"))
        try await handle.research.cancelProtectedFunction(runID: develop.runID)
        await runtime.shutdown()
    }

    @Test("Draft inspection preserves protected package collisions")
    func draftInspectionPreservesProtectedCollision() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let source = """
        ---
        name: Conflicting Analyze
        description: A researcher-owned draft with a protected identifier.
        ---
        Keep the method explicit.
        """ + "\n"
        let packageURL = fixture.rootURL.appendingPathComponent(
            ".scholium/skills/scholium-analyze",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )
        try Data(source.utf8).write(
            to: packageURL.appendingPathComponent("SKILL.md"),
            options: .atomic
        )

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let inspected = await handle.research.inspectSkillDraft(
            id: "scholium-analyze",
            source: source,
            origin: .triptych
        )
        #expect(!inspected.isValid)
        #expect(inspected.validationIssues.contains {
            $0.contains("protected Scholium package")
        })
        await runtime.shutdown()
    }

    @Test("An established Triptych without binding v2 is not silently bootstrapped")
    func establishedTriptychDoesNotReceiveImplicitWorkingMethods() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let bindingURL = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            )
        try FileManager.default.removeItem(at: bindingURL)

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(try await handle.research.workingMethodBindings() == nil)
        #expect(!FileManager.default.fileExists(atPath: bindingURL.path))

        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let develop = try #require(
            try await handle.research.availableProtectedFunctions(for: analysis).first {
                $0.function == .develop
            }
        )
        #expect(!develop.isEnabled)
        #expect(develop.repairReasons.contains { $0.code == .missingWorkflow })

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let repaired = try await handle.research.installDefaultWorkingMethods()
        #expect(repaired.document.binding(for: .analyze)?.state == .installedDefault)
        let configurationEvent = try #require(await iterator.next())
        if case .researchConfigurationInvalidated = configurationEvent {
            #expect(configurationEvent.snapshot.triptych.id == fixture.assignment.id)
        } else {
            Issue.record(
                "Working Method installation did not invalidate Action availability."
            )
        }
        let repairedDevelop = try #require(
            try await handle.research.availableProtectedFunctions(for: analysis).first {
                $0.function == .develop
            }
        )
        #expect(repairedDevelop.isEnabled)
        await runtime.shutdown()
    }

    @Test("Critique completion binds a changed separate record, while Manuscript selects independent revision-specific child runs")
    func critiqueAndManuscriptChildren() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        var work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )

        let critique = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .critique,
                target: work,
                scope: .whole,
                conditionalResources: []
            )
        )
        let critiqueOutput = try #require(critique.snapshot.preparedOutput)
        #expect(critique.snapshot.request.authorizedWriteTargets.isEmpty)
        #expect(critique.instructions.contains(#""output" : {"#))
        #expect(critique.instructions.contains(critiqueOutput.note.relativePath))
        #expect(critique.instructions.contains(critiqueOutput.fingerprint.sha256))
        #expect(critique.snapshot.skills.first {
            $0.packageID == "scholium-research-integration"
        }?.loadedResources.contains {
            $0.relativePath == "references/persistence-method.md"
        } == true)
        let storedCritiqueInstructions = try #require(
            try await handle.services.localResearchExecutionStore.listing().records.first {
                $0.id == critique.runID
            }?.preparedInstructions
        )
        #expect(critique.instructions.hasPrefix(storedCritiqueInstructions))
        #expect(!storedCritiqueInstructions.contains("Coordination key:"))
        let missingOutput = ResearchFunctionCompletionSubmission(
            runID: critique.runID,
            confirmationToken: critique.snapshot.confirmationToken,
            finalTargetFingerprint: work.fingerprint,
            summary: "Critique completed.",
            didModifyTarget: false
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(missingOutput)
        }
        let critiqueDocument = try await handle.documents.load(critiqueOutput.note)
        let savedCritique = try await handle.documents.save(
            critiqueOutput.note,
            changeSet: .exactContent(
                critiqueDocument.rawContent
                    + "\n## Specific Findings\n\n"
                    + "### Traced: The inference needs an explicit premise\n\n"
                    + "- Target: \(fixture.workID.relativePath)\n"
                    + "- Target Line: 5\n"
            ),
            expectedRevision: critiqueDocument.fingerprint
        ).committedValue
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == critique.runID
        })
        let critiqueCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: critique.runID,
                confirmationToken: critique.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Recorded one bounded Critique finding.",
                didModifyTarget: false,
                outputFingerprint: savedCritique.document.fingerprint
            )
        )
        #expect(critiqueCompletion.outputFingerprint == savedCritique.document.fingerprint)
        #expect(try await handle.documents.load(fixture.workID).fingerprint == work.fingerprint)

        let defaultManuscript = try #require(
            try await handle.research.availableProtectedFunctions(for: work).first {
                $0.function == .manuscript
            }
        )
        #expect(!defaultManuscript.isEnabled)
        await #expect(throws: (any Error).self) {
            _ = try await handle.research.prepareProtectedFunction(
                ResearchFunctionRequest(
                    function: .manuscript,
                    target: work,
                    conditionalResources: []
                )
            )
        }
        let manuscriptMethod = try await handle.research.duplicateBundledSkill(
            id: "scholium-manuscript",
            as: "my-manuscript-method"
        )
        let manuscriptBindings = try #require(
            try await handle.research.workingMethodBindings()
        )
        _ = try await handle.research.activateResearcherSkill(
            packageID: manuscriptMethod.id,
            for: .manuscript,
            expectedBindingRevision: manuscriptBindings.revision
        )

        let manuscript = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .manuscript, target: work, conditionalResources: [])
        )
        #expect(manuscript.snapshot.requiredChildFunctions.isEmpty)
        #expect(manuscript.snapshot.skills.first {
            $0.packageID == "scholium-core-protocol"
        }?.loadedResources.contains {
            $0.relativePath == "references/mixed-mode.md"
        } == true)
        #expect(!manuscript.instructions.contains("Critique, then Revise, then Fidelity"))
        let revise = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let workDocument = try await handle.documents.load(fixture.workID)
        let revised = try await handle.documents.save(
            fixture.workID,
            changeSet: .exactContent(
                workDocument.rawContent
                    + "\nAn explicit premise now supports the inference.\n"
            ),
            expectedRevision: workDocument.fingerprint
        ).committedValue
        let reviseActivityCompletion = try researchActivityCompletion(
            for: revise,
            candidateModifiedNotes: [fixture.workID],
            summary: "Revised the inference."
        )
        let awaitingRevision = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the inference; final Fidelity remains pending.",
                didModifyTarget: true,
                activityCompletion: reviseActivityCompletion
            )
        )
        #expect(awaitingRevision.state == .awaitingFidelity)
        let critiqueAssociation = try #require(
            try await handle.snapshot().research.critiques.first {
                $0.workNoteID == work.noteID
            }
        )
        let critiqueRound = try #require(
            critiqueAssociation.rounds.first { $0.id == critique.runID }
        )
        let actionableFinding = try #require(critiqueRound.actionableFindings.first)
        #expect(critiqueRound.completedAt == nil)
        _ = try await handle.research.setCritiqueFindingDisposition(
            workNote: fixture.workID,
            roundID: critiqueRound.id,
            findingID: actionableFinding.id,
            decision: .accept,
            rationale: "The revision adds the missing premise.",
            noTextChangeRationale: nil,
            expectedRevision: revised.document.fingerprint
        )
        _ = try await handle.research.completeCritiqueRound(
            workNote: fixture.workID,
            roundID: critiqueRound.id,
            expectedRevision: revised.document.fingerprint
        )
        _ = try await handle.research.completeCritiqueRound(
            workNote: fixture.workID,
            roundID: critiqueRound.id,
            expectedRevision: revised.document.fingerprint
        )

        work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let revisionFidelity = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: work,
                checks: try #require(revise.snapshot.fidelityHandoff).checks
            )
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: revisionFidelity.runID,
                confirmationToken: revisionFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Checked the exact final Work revision.",
                didModifyTarget: false,
                fidelityOutcomes: try #require(revise.snapshot.fidelityHandoff).checks
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map(FidelityCheckOutcome.passed)
            )
        )
        let reviseCompletion = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the inference and linked final Fidelity evidence.",
                didModifyTarget: true,
                activityCompletion: reviseActivityCompletion,
                childRunIDs: [revisionFidelity.runID]
            )
        )
        #expect(reviseCompletion.state == .complete)
        let fidelityReuse = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(
                function: .fidelity,
                target: work,
                checks: [.content]
            )
        )
        #expect(fidelityReuse.state == .complete)
        #expect(fidelityReuse.reusedCompletion?.runID == revisionFidelity.runID)
        let completedManuscript = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: manuscript.runID,
                confirmationToken: manuscript.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Coordinated the selected manuscript activities.",
                didModifyTarget: true,
                childRunIDs: [revise.runID]
            )
        )
        #expect(completedManuscript.state == .complete)
        #expect(completedManuscript.childRunIDs == [revise.runID])
        #expect(completedManuscript.reusedFidelityRunID == revise.runID)
        await runtime.shutdown()
    }

}
