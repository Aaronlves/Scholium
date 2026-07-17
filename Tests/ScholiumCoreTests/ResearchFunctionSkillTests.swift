import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Research Function Skill bindings and maintenance")
struct ResearchFunctionSkillTests {
    @Test("Five Workflow functions resolve one independently permissioned package")
    func fiveWorkflowFunctionBindings() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let expected: [ResearchFunctionID: String] = [
            .develop: "scholium-development",
            .critique: "scholium-critique",
            .revise: "scholium-revision",
            .fidelity: "scholium-content-fidelity",
            .manuscript: "scholium-manuscript",
        ]

        for (function, packageID) in expected {
            let resolution = try await store.functionBindingResolution(for: function)
            #expect(resolution.source == .bundledDefault)
            #expect(resolution.package?.id == packageID)
            #expect(resolution.package?.supportedFunctions == [function])
            #expect(resolution.issue == nil)
        }
        let review = try await store.functionBindingResolution(for: .review)
        #expect(review.source == .none)
        #expect(review.package == nil)
    }

    @Test("Citation status distinguishes template, installed candidate, active binding, and style mismatch")
    func citationBindingStates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        let missing = try await store.citationBindingResolution()
        #expect(missing.issue == .missing)
        #expect(missing.bundledTemplateAvailable)
        #expect(missing.installedCandidateIDs.isEmpty)
        #expect(missing.bindingRevision == nil)

        let local = try await store.duplicateBundled(
            id: "scholium-citation-verification",
            as: "my-apa-citations"
        )
        let installed = try await store.citationBindingResolution()
        #expect(installed.issue == .missing)
        #expect(installed.installedCandidateIDs == [local.id])
        #expect(installed.package == nil)

        let binding = try await store.activateCitationBinding(
            packageID: local.id,
            citationStyle: "apa-7",
            expectedBindingRevision: nil
        )
        let active = try await store.citationBindingResolution(citationStyle: "apa-7")
        #expect(active.source == .triptychBinding)
        #expect(active.package?.id == local.id)
        #expect(active.citationStyle == "apa-7")
        #expect(active.bindingRevision == binding.revision)
        #expect(active.issue == nil)

        let mismatch = try await store.citationBindingResolution(
            requiredCapabilities: [.citationVerification, .citationFormatting],
            citationStyle: "chicago-author-date"
        )
        #expect(
            mismatch.issue
                == .citationStyleMismatch(
                    packageID: local.id,
                    requested: "chicago-author-date"
                )
        )

        let selections = try await store.resolvedFunctionPackages(
            for: .fidelity,
            fidelityChecks: [.citations],
            citationStyle: "apa-7"
        )
        let citation = try #require(selections.first { $0.id == local.id })
        #expect(citation.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/apa-7-starter.md",
            "references/verification-method.md",
        ])
    }

    @Test("Legacy package-only citation bindings decode but require explicit style repair")
    func legacyCitationBindingNeedsStyleRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let local = try await store.duplicateBundled(
            id: "scholium-citation-verification",
            as: "legacy-citations"
        )
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        let legacy = """
        {
          "schema_version" : 1,
          "function_bindings" : {},
          "citation_binding" : "\(local.id)"
        }
        """
        try Data(legacy.utf8).write(to: store.bindingsURL, options: .atomic)

        let snapshot = try #require(try await store.bindingSnapshot())
        #expect(snapshot.document.citationStyle == nil)
        let resolution = try await store.citationBindingResolution()
        #expect(resolution.issue == .citationStyleMissing(packageID: local.id))
        #expect(!resolution.isActive)
    }

    @Test("Malformed citation bindings expose a raw repair revision")
    func malformedCitationBindingCanBeRepairedRevisionSafely() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        try Data("{ malformed".utf8).write(to: store.bindingsURL)

        let rawRevision = try #require(try await store.bindingFileRevision())
        let malformed = try await store.citationBindingResolution()
        #expect(malformed.bindingRevision == rawRevision)
        guard case .malformed = malformed.issue else {
            Issue.record("Expected a typed malformed-binding status.")
            return
        }

        let adopted = try await store.adoptAPACitationStarter(
            expectedBindingRevision: rawRevision
        )
        #expect(adopted.package.origin == .triptych)
        #expect(adopted.package.citationStyles == ["apa-7"])
        #expect(
            adopted.package.citationStyleResources["apa-7"]
                == "references/apa-7-starter.md"
        )
        let repaired = try await store.citationBindingResolution(citationStyle: "apa-7")
        #expect(repaired.package?.id == adopted.package.id)
        #expect(repaired.issue == nil)
    }

    @Test("Function assembly snapshots only selected conditional resources")
    func exactSelectiveResources() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)

        let selections = try await store.resolvedFunctionPackages(
            for: .develop,
            primaryResourcePaths: ["references/synthesis.md"]
        )
        let development = try #require(selections.first {
            $0.id == "scholium-development"
        })
        #expect(development.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/method.md",
            "references/synthesis.md",
        ])
        #expect(!development.loadedResources.map(\.relativePath).contains(
            "references/exploration.md"
        ))
        #expect(development.loadedResources.allSatisfy {
            $0.revision == DocumentFingerprint(content: $0.source)
        })

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.resolvedFunctionPackages(
                for: .fidelity,
                fidelityChecks: [.citations],
                citationStyle: "apa-7"
            )
        }
    }

    @Test("A revision-checked function binding activates and clears one local primary method")
    func functionPrimaryActivation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let local = try await store.duplicateBundled(
            id: "scholium-development",
            as: "my-development"
        )

        let saved = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .develop,
                primaryPackageID: local.id
            ),
            expectedBindingRevision: nil
        )
        let selected = try await store.functionSkillSelection(for: .develop)
        #expect(selected.primaryPackageID == local.id)
        let active = try await store.functionBindingResolution(for: .develop)
        #expect(active.source == .triptychBinding)
        #expect(active.package?.id == local.id)
        #expect(active.bindingRevision == saved.revision)

        let cleared = try await store.clearFunctionSkillSelection(
            for: .develop,
            expectedBindingRevision: saved.revision
        )
        #expect(try await store.functionSkillSelection(for: .develop).isEmpty)
        let fallback = try await store.functionBindingResolution(for: .develop)
        #expect(fallback.source == .bundledDefault)
        #expect(fallback.package?.id == "scholium-development")
        #expect(fallback.bindingRevision == cleared.revision)

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.saveFunctionSkillSelection(
                ResearchFunctionSkillSelection(
                    function: .develop,
                    primaryPackageID: local.id
                ),
                expectedBindingRevision: saved.revision
            )
        }
    }

    @Test("Active specialist and Practice bindings enter the effective function contract")
    func activeResearcherGuidanceEnrichesFunctionContract() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let prose = try await store.duplicateBundled(
            id: "scholium-prose-control",
            as: "my-prose-control"
        )
        let practices = try await store.duplicateBundled(
            id: "scholium-philosophical-practices",
            as: "my-practices"
        )
        let practice = ResearchPracticeSelection(
            packageID: practices.id,
            practiceID: "philosophical-expositor"
        )
        _ = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .revise,
                supplementalPackageIDs: [prose.id],
                selectedPractices: [practice]
            ),
            expectedBindingRevision: nil
        )

        let target = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: "Works/Argument.md"
        )
        let contract = ResearchWorkflowContract(
            mode: .write,
            taskObject: "Revise one Work",
            purpose: "Improve the expression without widening the write boundary.",
            originalReadSet: [target],
            originalWriteSet: [],
            phases: [ResearchWorkflowPhaseContract(
                phase: 1,
                mode: .write,
                purpose: "Revise one bounded passage.",
                requiredSkillIDs: [],
                readSet: [target],
                writeSet: [],
                permission: .readOnly,
                permissionBasis: "",
                output: "Return one bounded candidate revision.",
                stopCondition: "Stop rather than change a philosophical commitment.",
                durability: .handoff,
                handoff: ResearchWorkflowHandoff(
                    summary: "The candidate remains provisional.",
                    evidenceStatus: "Exact Work revision inspected."
                )
            )]
        )
        let envelope = try await ResearchWorkflowAssembler.resolveFunction(
            contract,
            function: .revise,
            store: store
        )
        let phase = try #require(envelope.contract.phases.first)
        #expect(phase.requiredSkillIDs == [
            "scholium-revision",
            prose.id,
        ])
        #expect(phase.selectedPractices == [practice])
        #expect(envelope.phases[0].packages.contains { $0.id == prose.id })
        let selectedPractice = try #require(
            envelope.phases[0].packages.first { $0.id == practices.id }
        )
        #expect(selectedPractice.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "references/Philosophical-Expositor.md",
        ])
        #expect(envelope.isExecutable)
    }

    @Test("Reviewer calibrates Critique only")
    func reviewerIsCritiqueOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let practices = try await store.duplicateBundled(
            id: "scholium-philosophical-practices",
            as: "my-review-practices"
        )
        let reviewer = ResearchPracticeSelection(
            packageID: practices.id,
            practiceID: "reviewer"
        )

        #expect(try await store.compatiblePracticeIDs(for: .critique) == ["reviewer"])
        #expect(!(try await store.compatiblePracticeIDs(for: .revise)).contains("reviewer"))
        #expect(!(try await store.compatiblePracticeIDs(for: .fidelity)).contains("reviewer"))
        #expect((try await store.compatiblePracticeIDs(for: .manuscript)).isEmpty)

        let saved = try await store.saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(
                function: .critique,
                selectedPractices: [reviewer]
            ),
            expectedBindingRevision: nil
        )
        #expect(try await store.functionSkillSelection(for: .critique)
            .selectedPractices == [reviewer])

        await #expect(throws: ResearchSkillBindingError.self) {
            _ = try await store.saveFunctionSkillSelection(
                ResearchFunctionSkillSelection(
                    function: .revise,
                    selectedPractices: [reviewer]
                ),
                expectedBindingRevision: saved.revision
            )
        }
    }

    @Test("Legacy binding JSON defaults new function refinement collections to empty")
    func legacyBindingDocumentDefaultsNewCollections() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        try FileManager.default.createDirectory(
            at: fixture.control,
            withIntermediateDirectories: true
        )
        try Data("{\"schema_version\":1,\"function_bindings\":{}}".utf8)
            .write(to: store.bindingsURL, options: .atomic)

        let snapshot = try #require(try await store.bindingSnapshot())
        #expect(snapshot.document.functionSkillBindings.isEmpty)
        #expect(snapshot.document.functionPracticeBindings.isEmpty)
    }

    @Test("Whole-package revisions bind every retained resource")
    func wholePackageRevision() {
        let entry = ResearchSkillMaintenanceFile(
            relativePath: "SKILL.md",
            source: "---\nname: Test\ndescription: Test.\n---\nBody"
        )
        let first = ResearchSkillProposedPackage(files: [
            entry,
            ResearchSkillMaintenanceFile(relativePath: "evals/cases.md", source: "A"),
        ])
        let changed = ResearchSkillProposedPackage(files: [
            entry,
            ResearchSkillMaintenanceFile(relativePath: "evals/cases.md", source: "B"),
        ])
        #expect(first.packageRevision != changed.packageRevision)
        #expect(throws: ResearchSkillMaintenanceError.self) {
            try ResearchSkillProposedPackage(files: [
                entry,
                ResearchSkillMaintenanceFile(relativePath: "../escape.md", source: "x"),
            ]).validate()
        }
        #expect(throws: ResearchSkillMaintenanceError.self) {
            try ResearchSkillProposedPackage(files: [
                entry,
                ResearchSkillMaintenanceFile(relativePath: "evals/unsafe\nname.md", source: "x"),
            ]).validate()
        }
    }

    @Test("Structural validation remains incomplete without revision-bound external evidence")
    func maintenanceEvaluationGates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "Improved instructions.")

        let incomplete = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow."
        ))
        #expect(incomplete.evaluation.structuralStatus == .passed)
        #expect(incomplete.evaluation.externalStatus == .incomplete)
        #expect(incomplete.evaluation.status == .incomplete)
        #expect(incomplete.confirmationToken == nil)

        let mismatchedEvidence = Self.passingEvidence(
            revision: DocumentFingerprint(content: "another proposal")
        )
        let mismatch = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: mismatchedEvidence
        ))
        #expect(mismatch.evaluation.externalStatus == .incomplete)
        #expect(mismatch.confirmationToken == nil)

        let invalidCases = ResearchSkillMaintenanceExternalEvaluation(
            proposedPackageRevision: proposal.packageRevision,
            evaluator: "External Research Agent",
            method: "Adversarial cases",
            status: .passed,
            cases: [
                ResearchSkillMaintenanceEvaluationCase(
                    id: "duplicate",
                    status: .passed,
                    summary: ""
                ),
                ResearchSkillMaintenanceEvaluationCase(
                    id: "duplicate",
                    status: .passed,
                    summary: "A second result."
                ),
            ]
        )
        let malformed = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: try #require(current.revision),
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: invalidCases
        ))
        #expect(malformed.evaluation.externalStatus == .incomplete)
        #expect(malformed.confirmationToken == nil)
    }

    @Test("Revision-bound external evaluation permits atomic apply and snapshot restore")
    func maintenanceApplyAndRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "Improved instructions.")
        let request = ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Adapt this method to the observed workflow.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        )
        let preparation = try await maintenance.prepare(request)
        #expect(preparation.evaluation.structuralStatus == .passed)
        #expect(preparation.evaluation.externalStatus == .passed)
        #expect(preparation.evaluation.status == .passed)
        let token = try #require(preparation.confirmationToken)

        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: token
        )
        #expect(applied.packageRevision == proposal.packageRevision)
        #expect(FileManager.default.fileExists(
            atPath: fixture.snapshotRoot
                .appendingPathComponent(applied.snapshotID.uuidString)
                .path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.control
                .appendingPathComponent("skill-maintenance-snapshots")
                .path
        ))
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Improved instructions."))

        let listed = try await maintenance.snapshots(packageID: current.id)
        #expect(listed.issues.isEmpty)
        #expect(listed.snapshots.count == 1)
        #expect(listed.snapshots.first?.id == applied.snapshotID)
        #expect(listed.snapshots.first?.packageID == current.id)
        #expect(listed.snapshots.first?.packageRevision == originalRevision)

        // Recovery metadata is reconstructed from durable Core state rather
        // than an in-memory Apply outcome retained by Settings.
        let reopenedMaintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        #expect(try await reopenedMaintenance.snapshots(packageID: current.id) == listed)

        let restored = try await reopenedMaintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .present(applied.packageRevision)
        )
        #expect(restored.restoredPackageRevision == originalRevision)
        let undo = try #require(restored.undoSnapshot)
        #expect(undo.packageRevision == applied.packageRevision)
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Original instructions."))

        let afterRestore = try await reopenedMaintenance.snapshots(packageID: current.id)
        #expect(afterRestore.issues.isEmpty)
        #expect(Set(afterRestore.snapshots.map(\.id)) == Set([applied.snapshotID, undo.id]))
        let roundTrip = try await reopenedMaintenance.restore(
            snapshotID: undo.id,
            expectedCurrentState: .present(originalRevision)
        )
        #expect(roundTrip.restoredPackageRevision == applied.packageRevision)
        #expect(roundTrip.undoSnapshot?.packageRevision == originalRevision)
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            .contains("Improved instructions."))
    }

    @Test("A durable snapshot restores an explicitly missing package without bypassing absence")
    func maintenanceRestoreMissingPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A temporary improved package.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Create a durable recovery snapshot.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )
        try await store.delete(id: current.id, expectedRevision: applied.packageRevision)

        let restored = try await maintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .missing
        )
        #expect(restored.replacedPackageRevision == nil)
        #expect(restored.undoSnapshot == nil)
        #expect(try await store.package(id: current.id).revision == originalRevision)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.restore(
                snapshotID: applied.snapshotID,
                expectedCurrentState: .missing
            )
        }
        #expect(try await store.package(id: current.id).revision == originalRevision)
    }

    @Test("Restore snapshots and round-trips a bounded semantically malformed package")
    func maintenanceRestoreMalformedPackage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A valid replacement.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Create the source recovery snapshot.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )
        let malformedSource = "---\nname: [unterminated\n---\nMalformed but bounded."
        let entryPoint = fixture.control.appendingPathComponent(
            "skills/\(current.id)/SKILL.md"
        )
        try Data(malformedSource.utf8).write(to: entryPoint, options: .atomic)
        let malformed = try await store.package(id: current.id)
        #expect(!malformed.isValid)
        let malformedRevision = try #require(malformed.revision)

        let restored = try await maintenance.restore(
            snapshotID: applied.snapshotID,
            expectedCurrentState: .present(malformedRevision)
        )
        let malformedUndo = try #require(restored.undoSnapshot)
        #expect(malformedUndo.packageRevision == malformedRevision)
        #expect(try await store.package(id: current.id).revision == originalRevision)

        let listing = try await maintenance.snapshots(packageID: current.id)
        #expect(listing.issues.isEmpty)
        #expect(listing.snapshots.contains { $0.id == malformedUndo.id })
        _ = try await maintenance.restore(
            snapshotID: malformedUndo.id,
            expectedCurrentState: .present(originalRevision)
        )
        #expect(try await store.resource(id: current.id, relativePath: "SKILL.md")
            == malformedSource)
    }

    @Test("A linked corrupt snapshot is reported without hiding valid recovery")
    func maintenanceSnapshotListingIsPartialAndNoFollow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let proposal = Self.proposal(body: "A replacement with one valid snapshot.")
        let preparation = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
            packageID: current.id,
            expectedPackageRevision: originalRevision,
            proposedPackage: proposal,
            instruction: "Exercise independent snapshot listing.",
            evaluationEvidence: Self.passingEvidence(revision: proposal.packageRevision)
        ))
        let applied = try await maintenance.apply(
            preparation,
            confirmationToken: try #require(preparation.confirmationToken)
        )

        let validRoot = fixture.snapshotRoot.appendingPathComponent(
            applied.snapshotID.uuidString,
            isDirectory: true
        )
        let corruptID = UUID()
        let corruptRoot = fixture.snapshotRoot.appendingPathComponent(
            corruptID.uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: false)
        let manifest = try String(
            contentsOf: validRoot.appendingPathComponent("manifest.json"),
            encoding: .utf8
        ).replacingOccurrences(
            of: applied.snapshotID.uuidString,
            with: corruptID.uuidString
        )
        try Data(manifest.utf8).write(
            to: corruptRoot.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try FileManager.default.createSymbolicLink(
            at: corruptRoot.appendingPathComponent("package", isDirectory: true),
            withDestinationURL: validRoot.appendingPathComponent("package", isDirectory: true)
        )

        let listing = try await maintenance.snapshots(packageID: current.id)
        #expect(listing.snapshots.map(\.id) == [applied.snapshotID])
        let issue = try #require(listing.issues.first { $0.snapshotID == corruptID })
        #expect(issue.code == .invalidPackage)
        #expect(try await store.package(id: current.id).revision == proposal.packageRevision)
    }

    @Test("Bundled and symlinked packages refuse evolution")
    func maintenanceBoundaries() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )
        let bundled = try await store.bundledPackage(id: "scholium-development")
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: bundled.id,
                expectedPackageRevision: try #require(bundled.revision),
                proposedPackage: Self.proposal(body: "No."),
                instruction: "Attempt to mutate bundled guidance."
            ))
        }

        let local = try await fixture.createEvolvablePackage(in: store, id: "linked-method")
        let outside = fixture.root.appendingPathComponent("outside.md")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: fixture.control
                .appendingPathComponent("skills/linked-method/references/linked.md"),
            withDestinationURL: outside
        )
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: local.id,
                expectedPackageRevision: try #require(local.revision),
                proposedPackage: Self.proposal(body: "No link following."),
                instruction: "Attempt maintenance with a linked resource."
            ))
        }
    }

    @Test("A linked control ancestor cannot redirect Researcher Skill maintenance")
    func linkedControlAncestorIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumLinkedControlMaintenance-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("Container", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        let outsideControl = root.appendingPathComponent("OutsideControl", isDirectory: true)
        let linkedControl = container.appendingPathComponent(".scholium", isDirectory: true)
        try FileManager.default.createDirectory(at: works, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: outsideControl,
            withIntermediateDirectories: true
        )
        let outsideStore = ResearchSkillStore(controlURL: outsideControl)
        let current = try await Self.createEvolvablePackage(
            in: outsideStore,
            controlURL: outsideControl
        )
        let originalRevision = try #require(current.revision)
        let originalSource = try await outsideStore.resource(
            id: current.id,
            relativePath: "SKILL.md"
        )
        try FileManager.default.createSymbolicLink(
            at: linkedControl,
            withDestinationURL: outsideControl
        )

        let linkedStore = ResearchSkillStore(controlURL: linkedControl)
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: linkedStore,
            snapshotRootURL: root.appendingPathComponent("Snapshots", isDirectory: true)
        )
        let proposal = Self.proposal(body: "This must not reach the outside package.")
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.prepare(ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise linked control containment.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            ))
        }
        #expect(try await outsideStore.package(id: current.id).revision == originalRevision)
        #expect(try await outsideStore.resource(
            id: current.id,
            relativePath: "SKILL.md"
        ) == originalSource)
    }

    @Test("A control-parent swap cannot redirect replacement or change external state")
    func parentSwapCannotRedirectReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that must be rejected.")

        let outsideControl = fixture.root.appendingPathComponent(
            "OutsideControl",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outsideControl,
            withIntermediateDirectories: true
        )
        let outsideStore = ResearchSkillStore(controlURL: outsideControl)
        let outside = try await Self.createEvolvablePackage(
            in: outsideStore,
            controlURL: outsideControl,
            id: current.id,
            body: "External state must remain exact."
        )
        let outsideRevision = try #require(outside.revision)
        let outsideSource = try await outsideStore.resource(
            id: outside.id,
            relativePath: "SKILL.md"
        )
        let displacedControl = fixture.root.appendingPathComponent(
            "OriginalControl",
            isDirectory: true
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .beforeReplacement = point {
                    try FileManager.default.moveItem(
                        at: fixture.control,
                        to: displacedControl
                    )
                    try FileManager.default.createSymbolicLink(
                        at: fixture.control,
                        withDestinationURL: outsideControl
                    )
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise parent substitution resistance.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }
        #expect(try await outsideStore.package(id: outside.id).revision == outsideRevision)
        #expect(try await outsideStore.resource(
            id: outside.id,
            relativePath: "SKILL.md"
        ) == outsideSource)
        let originalStore = ResearchSkillStore(controlURL: displacedControl)
        #expect(try await originalStore.package(id: current.id).revision == originalRevision)
        #expect(try FileManager.default.contentsOfDirectory(
            at: displacedControl.appendingPathComponent("skills", isDirectory: true),
            includingPropertiesForKeys: nil
        ).allSatisfy { !$0.lastPathComponent.hasPrefix(".replacing-") })
    }

    @Test("Maintenance applies the installed package dependency and resource rules")
    func fullInstalledPackageValidationPrecedesConfirmation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        _ = try await store.create(
            id: "cycle-peer",
            source: Self.routedMaintenanceSource(
                name: "Cycle Peer",
                role: "specialist",
                dependencies: [current.id]
            )
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot
        )

        let invalidProposals: [(String, ResearchSkillProposedPackage, String)] = [
            (
                "missing dependency",
                Self.maintenanceProposal(skillSource: Self.routedMaintenanceSource(
                    name: "Missing Dependency",
                    role: "specialist",
                    dependencies: ["missing-method"]
                )),
                "does not exist"
            ),
            (
                "dependency cycle",
                Self.maintenanceProposal(skillSource: Self.routedMaintenanceSource(
                    name: "Cycle Candidate",
                    role: "specialist",
                    dependencies: ["cycle-peer"]
                )),
                "cycle"
            ),
            (
                "undeclared citation style resource",
                Self.maintenanceProposal(
                    skillSource: Self.routedMaintenanceSource(
                        name: "Mismatched Citation Method",
                        role: "specialist",
                        dependencies: ["scholium-core-protocol"],
                        citationStyles: ["apa-7"],
                        citationStyleResources: ["chicago": "references/style.md"]
                    ),
                    resources: ["references/style.md": "# Style"]
                ),
                "not declared in citation_styles"
            ),
        ]

        for (label, proposal, expectedIssue) in invalidProposals {
            let preparation = try await maintenance.prepare(
                ResearchSkillMaintenanceRequest(
                    packageID: current.id,
                    expectedPackageRevision: originalRevision,
                    proposedPackage: proposal,
                    instruction: "Reject \(label) before confirmation.",
                    evaluationEvidence: Self.passingEvidence(
                        revision: proposal.packageRevision
                    )
                )
            )
            #expect(preparation.evaluation.structuralStatus == .failed)
            #expect(preparation.confirmationToken == nil)
            #expect(preparation.evaluation.validationIssues.contains {
                $0.localizedCaseInsensitiveContains(expectedIssue)
            })
        }

        let dependency = try await store.create(
            id: "temporary-dependency",
            source: Self.routedMaintenanceSource(
                name: "Temporary Dependency",
                role: "specialist",
                dependencies: ["scholium-core-protocol"]
            )
        )
        let validUntilApply = Self.maintenanceProposal(
            skillSource: Self.routedMaintenanceSource(
                name: "Apply Revalidation Candidate",
                role: "specialist",
                dependencies: [dependency.id]
            )
        )
        let prepared = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: validUntilApply,
                instruction: "Revalidate the dependency graph before snapshot and apply.",
                evaluationEvidence: Self.passingEvidence(
                    revision: validUntilApply.packageRevision
                )
            )
        )
        let token = try #require(prepared.confirmationToken)
        try await store.delete(
            id: dependency.id,
            expectedRevision: try #require(dependency.revision)
        )
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(prepared, confirmationToken: token)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.snapshotRoot.path))
        #expect(try await store.package(id: current.id).revision == originalRevision)
    }

    @Test("Maintenance snapshots refuse a symbolic-link storage root")
    func maintenanceSnapshotRootBoundary() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let outside = fixture.root.appendingPathComponent(
            "Outside Snapshots",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let linkedRoot = fixture.root.appendingPathComponent(
            "Linked Snapshot Root",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: outside
        )
        let proposal = Self.proposal(body: "A change that must not follow the link.")
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: linkedRoot
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise the snapshot trust boundary.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)
        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }

        #expect(try await store.package(id: current.id).revision == originalRevision)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("Failed atomic replacement restores the package and preserves its durable snapshot")
    func atomicReplacementRollbackPreservesSnapshot() async throws {
        enum InjectedFailure: Error { case afterReplacement }

        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that will fault.")
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .afterReplacement = point {
                    throw InjectedFailure.afterReplacement
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise rollback.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)
        await #expect(throws: InjectedFailure.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }

        #expect(try await store.package(id: current.id).revision == originalRevision)
        let snapshots = try FileManager.default.contentsOfDirectory(
            at: fixture.snapshotRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        #expect(snapshots.count == 1)
    }

    @Test("A concurrent package edit wins over a prepared replacement")
    func concurrentMaintenanceEditIsNeverOverwritten() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchSkillStore(controlURL: fixture.control)
        let current = try await fixture.createEvolvablePackage(in: store)
        let originalRevision = try #require(current.revision)
        let proposal = Self.proposal(body: "A replacement that must become stale.")
        let entryPoint = fixture.control
            .appendingPathComponent("skills", isDirectory: true)
            .appendingPathComponent(current.id, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let concurrentSource = Fixture.skillSource(
            body: "A concurrent researcher-authored change."
        )
        let maintenance = ResearchSkillMaintenanceStore(
            skillStore: store,
            snapshotRootURL: fixture.snapshotRoot,
            replacementHooks: ResearchSkillMaintenanceReplacementHooks { point in
                if case .beforeReplacement = point {
                    try Data(concurrentSource.utf8).write(to: entryPoint, options: .atomic)
                }
            }
        )
        let preparation = try await maintenance.prepare(
            ResearchSkillMaintenanceRequest(
                packageID: current.id,
                expectedPackageRevision: originalRevision,
                proposedPackage: proposal,
                instruction: "Exercise the package revision race.",
                evaluationEvidence: Self.passingEvidence(
                    revision: proposal.packageRevision
                )
            )
        )
        let token = try #require(preparation.confirmationToken)

        await #expect(throws: ResearchSkillMaintenanceError.self) {
            _ = try await maintenance.apply(preparation, confirmationToken: token)
        }
        #expect(try await store.resource(
            id: current.id,
            relativePath: "SKILL.md"
        ).contains("A concurrent researcher-authored change."))
        #expect(try await store.package(id: current.id).revision != proposal.packageRevision)
    }

    private static func createEvolvablePackage(
        in store: ResearchSkillStore,
        controlURL: URL,
        id: String = "evolving-method",
        body: String = "Original instructions."
    ) async throws -> ResearchSkillPackage {
        _ = try await store.create(id: id, source: Fixture.skillSource(body: body))
        let evals = controlURL.appendingPathComponent(
            "skills/\(id)/evals",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evals,
            withIntermediateDirectories: false
        )
        try "# Cases\n\n- Preserve source fidelity.".write(
            to: evals.appendingPathComponent("cases.md"),
            atomically: true,
            encoding: .utf8
        )
        let references = controlURL.appendingPathComponent(
            "skills/\(id)/references",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: references,
            withIntermediateDirectories: false
        )
        return try await store.package(id: id)
    }

    private static func routedMaintenanceSource(
        name: String,
        role: String,
        dependencies: [String],
        citationStyles: [String] = [],
        citationStyleResources: [String: String] = [:],
        practiceResources: [String: String] = [:]
    ) -> String {
        var routing = [
            "  role: \(role)",
            "  supported_functions: [fidelity]",
            "  capabilities: []",
            "  citation_styles: [\(citationStyles.joined(separator: ", "))]",
        ]
        if !citationStyleResources.isEmpty {
            routing.append("  citation_style_resources:")
            routing.append(contentsOf: citationStyleResources.keys.sorted().map {
                "    \($0): \(citationStyleResources[$0] ?? "")"
            })
        }
        routing.append(contentsOf: [
            "  allow_evolution: true",
            "  supported_modes: [audit]",
            "  required_skills: [\(dependencies.joined(separator: ", "))]",
        ])
        if !practiceResources.isEmpty {
            routing.append("  practice_resources:")
            routing.append(contentsOf: practiceResources.keys.sorted().map {
                "    \($0): \(practiceResources[$0] ?? "")"
            })
        }
        return """
        ---
        name: \(name)
        description: A maintenance validation candidate.
        scholium:
        \(routing.joined(separator: "\n"))
        ---

        # \(name)

        Validate this package with `evals/cases.md`.
        """
    }

    private static func maintenanceProposal(
        skillSource: String,
        resources: [String: String] = [:]
    ) -> ResearchSkillProposedPackage {
        var files = [ResearchSkillMaintenanceFile(
            relativePath: "SKILL.md",
            source: skillSource
        )]
        files.append(ResearchSkillMaintenanceFile(
            relativePath: "evals/cases.md",
            source: "# Cases\n\n- Preserve source fidelity."
        ))
        files.append(contentsOf: resources.keys.sorted().map {
            ResearchSkillMaintenanceFile(
                relativePath: $0,
                source: resources[$0] ?? ""
            )
        })
        return ResearchSkillProposedPackage(files: files)
    }

    private static func proposal(body: String) -> ResearchSkillProposedPackage {
        ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(
                relativePath: "SKILL.md",
                source: Fixture.skillSource(body: body)
            ),
            ResearchSkillMaintenanceFile(
                relativePath: "evals/cases.md",
                source: "# Cases\n\n- Preserve source fidelity."
            ),
        ])
    }

    private static func passingEvidence(
        revision: DocumentFingerprint
    ) -> ResearchSkillMaintenanceExternalEvaluation {
        ResearchSkillMaintenanceExternalEvaluation(
            proposedPackageRevision: revision,
            evaluator: "External Research Agent",
            method: "Positive, boundary, and adversarial cases",
            status: .passed,
            cases: [ResearchSkillMaintenanceEvaluationCase(
                id: "source-fidelity-boundary",
                status: .passed,
                summary: "The proposed method preserved evidential layers in the evaluated cases."
            )]
        )
    }
}

private struct Fixture {
    let root: URL
    let control: URL
    let snapshotRoot: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumFunctionSkills-\(UUID().uuidString)",
            isDirectory: true
        )
        control = root.appendingPathComponent("Works/.scholium", isDirectory: true)
        snapshotRoot = root.appendingPathComponent(
            "Application Support/Triptychs/Test/research-guidance/skill-snapshots",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: control,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func createEvolvablePackage(
        in store: ResearchSkillStore,
        id: String = "evolving-method"
    ) async throws -> ResearchSkillPackage {
        _ = try await store.create(
            id: id,
            source: Self.skillSource(body: "Original instructions.")
        )
        let evals = control.appendingPathComponent(
            "skills/\(id)/evals",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: evals,
            withIntermediateDirectories: false
        )
        try "# Cases\n\n- Preserve source fidelity.".write(
            to: evals.appendingPathComponent("cases.md"),
            atomically: true,
            encoding: .utf8
        )
        let references = control.appendingPathComponent(
            "skills/\(id)/references",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: references,
            withIntermediateDirectories: false
        )
        return try await store.package(id: id)
    }

    static func skillSource(body: String) -> String {
        """
        ---
        name: Evolving Method
        description: A bounded researcher-owned method used by maintenance tests.
        scholium:
          role: specialist
          supported_functions: [fidelity]
          capabilities: []
          citation_styles: []
          allow_evolution: true
          supported_modes: [audit]
          required_skills: [scholium-core-protocol]
        ---

        # Evolving Method

        \(body)

        Evaluate with `evals/cases.md` before applying a whole-package replacement.
        """
    }
}
