import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchActionRunOperationsTests {
    @Test("Current Methods prepare without package-resource selection")
    func splitMethodsPrepareWithoutResourceSelection() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let material = try #require(
            try await handle.research.protectedMaterialCandidates(
                for: target,
                actionID: .analyze
            ).first { $0.material.note == fixture.topicID }?.material
        )
        let preflight = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .analyze,
                target: target,
                materials: [material]
            )
        )
        #expect(preflight.instructions.contains("authenticated Agent CLI"))
        #expect(preflight.instructions.contains("frozen Result Contract"))
        #expect(preflight.instructions.contains("source-grounded literature recommendations"))
        try await handle.research.cancelActionRun(runID: preflight.runID)
        await runtime.shutdown()
    }

    @Test("Preparation rejects stale Target and Material fingerprints without execution residue")
    func fingerprintValidationAndRollback() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.protectedMaterialCandidates(
            for: target,
            actionID: .analyze
        )
        #expect(!candidates.contains { $0.material.noteID == target.noteID })
        let topic = try #require(candidates.first {
            $0.material.note == fixture.topicID
        }?.material)
        let originalRuns = try await handle.services.localResearchExecutionStore.listing().records.count

        let topicDocument = try await handle.documents.load(fixture.topicID)
        _ = try await handle.documents.save(
            fixture.topicID,
            changeSet: .exactContent(topicDocument.rawContent + "\nA changed Material.\n"),
            expectedRevision: topicDocument.fingerprint
        )
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await handle.research.prepareActionRun(
                ResearchActionRunRequest(
                    actionID: .analyze,
                    target: target,
                    materials: [topic]
                )
            )
        }
        #expect(try await handle.services.localResearchExecutionStore.listing().records.count == originalRuns)

        let targetDocument = try await handle.documents.load(fixture.analysisID)
        _ = try await handle.documents.save(
            fixture.analysisID,
            changeSet: .exactContent(targetDocument.rawContent + "\nA changed Target.\n"),
            expectedRevision: targetDocument.fingerprint
        )
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await handle.research.prepareActionRun(
                ResearchActionRunRequest(actionID: .analyze, target: target)
            )
        }
        #expect(try await handle.services.localResearchExecutionStore.listing().records.count == originalRuns)
        await runtime.shutdown()
    }

    @Test("Material suggestions use only resolved one-hop links and preserve catalog aliases")
    func materialCandidateSuggestions() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let candidates = try await handle.research.protectedMaterialCandidates(
            for: target,
            actionID: .analyze
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
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let valid = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: analysis)
        )
        let stored = try await handle.services.localResearchExecutionStore.record(
            id: valid.runID
        )
        #expect(stored.boundedWriteSet.entries.map(\.noteID) == [
            analysis.noteID,
        ])
        try await handle.research.cancelActionRun(runID: valid.runID)
        await runtime.shutdown()
    }

    @Test("Analyze completion performs its bounded fidelity self-check without a Fidelity child Run")
    func analyzeCompletionDoesNotPrepareFidelityChild() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let analyze = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: target)
        )
        let original = try await handle.documents.load(fixture.analysisID)
        let write = try await writePreparedResearchDocument(
            for: analyze,
            body: original.body + "\nA bounded analyzed claim.\n",
            handle: handle
        )
        #expect(write.state == .committed)

        let completion = try await completeTestActionRun(
            handle: handle,
            submission: ResearchActionRunCompletionSubmission(
                runID: analyze.runID,
                confirmationToken: analyze.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                summary: "Analyzed one bounded claim and checked its source fidelity.",
                didModifyTarget: true
            )
        )
        #expect(completion.state == .complete)
        #expect(completion.childRunIDs?.isEmpty != false)

        let records = try await handle.services.localResearchExecutionStore.listing().records
        #expect(records.filter {
            $0.snapshot.request.actionID == .checkFidelity
        }.isEmpty)

        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first { $0.id == analyze.runID }
        )
        #expect(record.fidelityCompletion == .notRequired)
        await runtime.shutdown()
    }

    @Test("Explicit citation style reaches Check Fidelity resources, instructions, snapshots, and evidence")
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

        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let fidelity = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .checkFidelity,
                target: target,
                checks: [.content, .citations]
            )
        )
        #expect(fidelity.snapshot.citationStyle == "apa-7")
        #expect(fidelity.instructions.contains("Citation style: apa-7"))

        let completion = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
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

        let develop = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(actionID: .analyze, target: target)
        )
        #expect(!develop.instructions.contains("Citation style: apa-7"))
        try await handle.research.cancelActionRun(runID: develop.runID)
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

        let analysis = try await researchActionTarget(
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

    @Test("Critique uses its frozen Result Contract without write authority")
    func critiqueUsesFrozenResultContract() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try await researchActionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )

        let critique = try await handle.research.prepareActionRun(
            ResearchActionRunRequest(
                actionID: .critique,
                target: work,
                scope: .whole
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
        _ = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: critique.runID,
                confirmationToken: critique.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: work.fingerprint,
                summary: "Recorded one bounded Critique finding.",
                didModifyTarget: false
            )
        )
        #expect(try await handle.documents.load(fixture.workID).fingerprint == work.fingerprint)
        await runtime.shutdown()
    }

}
