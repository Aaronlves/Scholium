import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchFunctionOperationsTests {
    @Test("Current Methods need no package-resource selection")
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
        #expect(!preflight.awaitsResourceSelection)
        #expect(preflight.instructions.contains("authenticated Agent CLI"))
        #expect(preflight.instructions.contains("frozen Result Contract"))
        #expect(preflight.instructions.contains("source-grounded literature recommendations"))
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

    @Test("Action-backed write phases install only the resolved initial Target in the bounded write set")
    func actionWriteSetStartsWithCurrentTargetOnly() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let valid = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .develop, target: analysis)
        )
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: valid.runID
        )
        #expect(stored.boundedWriteSet.entries.map(\.noteID) == [
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
        let write = try await writePreparedResearchDocument(
            for: develop,
            content: original.rawContent + "\nA developed claim.\n",
            handle: handle
        )
        #expect(write.state == .committed)
        let saved = try await handle.documents.load(fixture.analysisID)
        let recommendations = [try ResearchLiteratureRecommendationSubmission(
            rawCitation: "A. Author, Frozen Reading Lead (2025)",
            reason: "The analyzed source identifies this work as a live objection."
        )]
        let awaiting = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed one bounded claim.",
                didModifyTarget: true,
                literatureRecommendations: recommendations
            )
        )
        #expect(awaiting.state == .awaitingFidelity)

        let afterCompletion = try await handle.services.localResearchExecutionStore.listing().records
        #expect(afterCompletion.filter { record in
            record.snapshot.resolvedFidelityInvocation == .automatic(
                parentRunID: develop.runID
            )
        }.count == 1)

        let automatic = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: develop.runID
        )
        #expect(automatic.state == .prepared)
        #expect(automatic.preparation.snapshot.resolvedFidelityInvocation == .automatic(
            parentRunID: develop.runID
        ))
        #expect(automatic.preparation.snapshot.request.target.fingerprint
            == saved.fingerprint)
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

        let fidelityCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: automatic.preparation.runID,
                confirmationToken: automatic.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: saved.fingerprint,
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

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await completeTestProtectedFunction(handle: handle, submission:
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "Developed and checked one bounded claim.",
                    didModifyTarget: true,
                    literatureRecommendations: [
                        try ResearchLiteratureRecommendationSubmission(
                            rawCitation: "B. Author, Replacement Lead (2026)",
                            reason: "A later payload must not replace the first report."
                        ),
                    ],
                    childRunIDs: [automatic.preparation.runID]
                )
            )
        }

        let verified = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                literatureRecommendations: recommendations,
                childRunIDs: [automatic.preparation.runID]
            )
        )
        #expect(verified.state == .complete)
        #expect(verified.reusedFidelityRunID == fidelityCompletion.runID)
        let portable = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first { $0.id == develop.runID }
        )
        #expect(portable.literatureRecommendations.map(\.rawCitation) == [
            "A. Author, Frozen Reading Lead (2025)",
        ])

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
        let write = try await writePreparedResearchDocument(
            for: parent,
            content: original.rawContent + "\nA source-bound claim.\n",
            handle: handle
        )
        #expect(write.state == .committed)
        let saved = try await handle.documents.load(fixture.analysisID)
        let submittedAt = Date()
        let awaiting = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: parent.runID,
                confirmationToken: parent.snapshot.confirmationToken,
                summary: "Added one source-bound claim.",
                didModifyTarget: true,
                literatureRecommendations: [],
                submittedAt: submittedAt
            )
        )
        #expect(awaiting.state == .awaitingFidelity)
        let automatic = try await handle.research.prepareProtectedAutomaticFidelity(
            parentRunID: parent.runID
        )
        let fidelitySubmittedAt = Date()
        _ = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: automatic.preparation.runID,
                confirmationToken: automatic.preparation.snapshot.confirmationToken,
                finalTargetFingerprint: saved.fingerprint,
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
            literatureRecommendations: [],
            submittedAt: submittedAt
        )
        let localURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v8", isDirectory: true)
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
            _ = try await completeTestProtectedFunction(handle: handle, submission: retry)
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

        let completed = try await completeTestProtectedFunction(handle: handle, submission: retry)
        #expect(completed.state == .complete)
        #expect(completed.actuallyUsedMaterialNoteIDs == [])
        #expect(completed.childRunIDs == [automatic.effectiveFidelityRunID])
        #expect(try await completeTestProtectedFunction(handle: handle, submission: retry) == completed)
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
        _ = try await completeTestProtectedFunction(handle: handle, submission:
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
            _ = try await completeTestProtectedFunction(handle: handle, submission:
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "No Analysis change was needed.",
                    didModifyTarget: false,
                    literatureRecommendations: [],
                    childRunIDs: [manual.runID]
                )
            )
        }

        let unchangedDevelop = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "No Analysis change was needed.",
                didModifyTarget: false,
                literatureRecommendations: []
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
        let unchangedRevise = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "No Work change was needed.",
                didModifyTarget: false
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
        _ = try await writePreparedResearchDocument(
            for: develop,
            content: original.rawContent + "\nA developed claim.\n",
            handle: handle
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
        let manualCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: manual.runID,
                confirmationToken: manual.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact final revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )

        let completed = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed one bounded claim.",
                didModifyTarget: true,
                literatureRecommendations: []
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
        #expect(develop.snapshot.checkpointID != nil)
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(develop.snapshot.fidelityHandoff?.checks == [.content])
        #expect(develop.snapshot.fidelityHandoff?.preparedTargetFingerprint == target.fingerprint)
        #expect(!develop.instructions.contains("## Isolated phase 2: fidelity"))
        #expect(develop.instructions.contains("authenticated Agent CLI"))
        #expect(develop.instructions.contains("frozen Result Contract"))
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
        _ = try await completeTestProtectedFunction(handle: handle, submission:
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
        _ = try await writePreparedResearchDocument(
            for: develop,
            content: original.rawContent + "\nA bounded developed claim.\n",
            handle: handle
        )
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == develop.runID
        })
        let awaitingSubmission = ResearchFunctionCompletionSubmission(
            runID: develop.runID,
            confirmationToken: develop.snapshot.confirmationToken,
            summary: "Developed one bounded claim.",
            didModifyTarget: true,
            literatureRecommendations: []
        )
        let awaiting = try await completeTestProtectedFunction(handle: handle, submission: awaitingSubmission)
        #expect(awaiting.state == .awaitingFidelity)
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await completeTestProtectedFunction(handle: handle, submission:
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "Tried to reuse an audit of the pre-edit revision.",
                    didModifyTarget: true,
                    literatureRecommendations: [],
                    childRunIDs: [preEditFidelity.runID]
                )
            )
        }
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await completeTestProtectedFunction(handle: handle, submission:
                ResearchFunctionCompletionSubmission(
                    runID: develop.runID,
                    confirmationToken: develop.snapshot.confirmationToken,
                    summary: "Tried to attach an unprepared audit claim.",
                    didModifyTarget: true,
                    fidelityOutcomes: [.passedContent],
                    literatureRecommendations: []
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
        let finalFidelityCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: finalFidelity.runID,
                confirmationToken: finalFidelity.snapshot.confirmationToken,
                finalTargetFingerprint: finalTarget.fingerprint,
                summary: "Checked the exact post-edit Analysis revision.",
                didModifyTarget: false,
                fidelityOutcomes: [.passedContent]
            )
        )
        let verified = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: develop.runID,
                confirmationToken: develop.snapshot.confirmationToken,
                summary: "Developed and checked one bounded claim.",
                didModifyTarget: true,
                literatureRecommendations: [],
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

        let current = try await handle.research.citationMethodStatus()
        let status = try await handle.research.activateCitationMethod(
            selection: ResearchCitationMethodSelection(citationStyle: "apa-7"),
            expectedConfigurationRevision: current.configurationRevision
        )
        #expect(status.activeCitationStyle == "apa-7")

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
        #expect(fidelity.snapshot.citationStyle == "apa-7")
        #expect(fidelity.instructions.contains("Citation style: apa-7"))

        let completion = try await completeTestProtectedFunction(handle: handle, submission:
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
        #expect(develop.snapshot.requiredChildFunctions == [.fidelity])
        #expect(!develop.instructions.contains("Citation style: apa-7"))
        try await handle.research.cancelProtectedFunction(runID: develop.runID)
        await runtime.shutdown()
    }

    @Test("An established Triptych uses the current registration document without reviving binding v2")
    func establishedTriptychUsesCurrentRegistrations() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let bindingURL = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            )
        if FileManager.default.fileExists(atPath: bindingURL.path) {
            try FileManager.default.removeItem(at: bindingURL)
        }

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(!FileManager.default.fileExists(atPath: bindingURL.path))

        let registrations = try await handle.research.researchSkillRegistrations()
        #expect(registrations.document.registration(for: .analyze)?.isEnabled == true)

        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let analyze = try #require(
            try await handle.research.availableActions(for: actionNote(analysis)).first {
                $0.id == .analyze
            }
        )
        #expect(analyze.isEnabled)
        await runtime.shutdown()
    }

    @Test("Critique uses its Result Contract, while Manuscript selects independent revision-specific child runs")
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
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: critique.runID
        ).boundedWriteSet.entries.isEmpty)
        #expect(critique.instructions.contains("frozen Result Contract"))
        let storedCritiqueInstructions = try #require(
            try await handle.services.localResearchExecutionStore.listing().records.first {
                $0.id == critique.runID
            }?.preparedInstructions
        )
        #expect(critique.instructions.hasPrefix(storedCritiqueInstructions))
        #expect(!storedCritiqueInstructions.contains("Coordination key:"))
        #expect(try await handle.services.localResearchExecutionStore.listing().records.contains {
            $0.id == critique.runID
        })
        _ = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: critique.runID,
                confirmationToken: critique.snapshot.confirmationToken,
                finalTargetFingerprint: work.fingerprint,
                summary: "Recorded one bounded Critique finding.",
                didModifyTarget: false
            )
        )
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
        let registrations = try await handle.research.researchSkillRegistrations()
        let manuscriptRegistration = try #require(
            registrations.document.registration(for: .manuscript)
        )
        _ = try await handle.research.saveResearchSkillRegistrations(
            try registrations.document.replacing(ResearchSkillRegistration(
                key: manuscriptRegistration.key,
                actionID: manuscriptRegistration.actionID,
                displayName: manuscriptRegistration.displayName,
                primaryMarkdown: manuscriptRegistration.primaryMarkdown,
                skillFolder: manuscriptRegistration.skillFolder,
                isEnabled: true
            )),
            expectedRevision: registrations.revision
        )
        let profiles = try await handle.research.academicActionProfiles()
        let manuscriptProfile = try #require(
            profiles.document.profile(for: .manuscript)
        )
        let enabledManuscriptProfile = try ResearchAcademicActionProfile(
            actionID: manuscriptProfile.actionID,
            displayName: manuscriptProfile.displayName,
            order: manuscriptProfile.order,
            isEnabled: true,
            applicableRoles: manuscriptProfile.applicableRoles,
            academicInputFields: manuscriptProfile.academicInputFields,
            academicResultFields: manuscriptProfile.academicResultFields
        )
        _ = try await handle.research.saveAcademicActionProfiles(
            try ResearchAcademicProfileDocument(
                profiles: profiles.document.profiles.filter {
                    $0.actionID != .manuscript
                } + [enabledManuscriptProfile]
            ),
            expectedRevision: profiles.revision
        )

        let manuscript = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .manuscript, target: work, conditionalResources: [])
        )
        #expect(manuscript.snapshot.requiredChildFunctions.isEmpty)
        #expect(!manuscript.instructions.contains("Critique, then Revise, then Fidelity"))
        let revise = try await handle.research.prepareProtectedFunction(
            ResearchFunctionRequest(function: .revise, target: work, conditionalResources: [])
        )
        let workDocument = try await handle.documents.load(fixture.workID)
        _ = try await writePreparedResearchDocument(
            for: revise,
            content: workDocument.rawContent
                + "\nAn explicit premise now supports the inference.\n",
            handle: handle
        )
        let awaitingRevision = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the inference; final Fidelity remains pending.",
                didModifyTarget: true
            )
        )
        #expect(awaitingRevision.state == .awaitingFidelity)
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
        _ = try await completeTestProtectedFunction(handle: handle, submission:
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
        let reviseCompletion = try await completeTestProtectedFunction(handle: handle, submission:
            ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                summary: "Revised the inference and linked final Fidelity evidence.",
                didModifyTarget: true,
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
        let completedManuscript = try await completeTestProtectedFunction(handle: handle, submission:
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
