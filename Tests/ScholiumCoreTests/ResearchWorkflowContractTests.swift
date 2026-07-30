import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Stateless research workflow contracts")
struct ResearchWorkflowContractTests {
    @Test("The Critique route writes only the exact Critique revision")
    func critiqueRouteBoundary() throws {
        let work = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: "Works/Argument.md",
            fingerprint: DocumentFingerprint(content: "work")
        )
        let critique = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: "Critiques/Argument Critique.md",
            fingerprint: DocumentFingerprint(content: "critique")
        )

        let contract = try ResearchWorkflowRouteContracts.critique(
            work: work,
            critique: critique,
            purpose: "Review the exact Work version."
        )

        #expect(contract.mode == .review)
        #expect(contract.originalReadSet == [work, critique])
        #expect(contract.originalWriteSet == [critique])
        #expect(contract.phases[0].permission == .directEditAuthorized)
        #expect(contract.phases[0].writeSet == [critique])
        #expect(contract.phases[0].handoff.evidenceStatus.contains("not researcher-settled"))
        try contract.validate()
    }

    @Test("An ordinary contract keeps exact task boundaries and encodes stable keys")
    func ordinaryContractRoundTrip() throws {
        let source = object(.sourceFile, "paper.pdf")
        let contract = ResearchWorkflowContract(
            mode: .analyze,
            taskObject: "Analyze one declared source unit",
            purpose: "Reconstruct the source without exceeding its declared scope.",
            originalReadSet: [source],
            originalWriteSet: [],
            researchUnit: ResearchWorkflowResearchUnit(
                currentScope: "Chapter 2"
            ),
            researchUnitAuthorization: .scopeDeclared,
            phases: [phase(mode: .analyze, readSet: [source])]
        )

        try contract.validate()
        let data = try encoder.encode(contract)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"schema_version\""))
        #expect(json.contains("\"original_read_set\""))
        #expect(json.contains("\"research_unit_authorization\""))
        #expect(try decoder.decode(ResearchWorkflowContract.self, from: data) == contract)
    }

    @Test("One phase requires its ordinary top-level mode; several phases require Mixed")
    func modeShapeValidation() {
        let source = object(.sourceFile, "paper.pdf")
        let mismatched = ResearchWorkflowContract(
            mode: .review,
            taskObject: "Review",
            purpose: "Review a source analysis.",
            originalReadSet: [source],
            originalWriteSet: [],
            phases: [phase(mode: .analyze, readSet: [source])]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try mismatched.validate()
        }

        let notMixed = ResearchWorkflowContract(
            mode: .analyze,
            taskObject: "Analyze and review",
            purpose: "Run two bounded phases.",
            originalReadSet: [source],
            originalWriteSet: [],
            phases: [
                phase(number: 1, mode: .analyze, readSet: [source]),
                phase(number: 2, mode: .review, readSet: [source]),
            ]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try notMixed.validate()
        }

        let mixed = ResearchWorkflowContract(
            mode: .mixed,
            taskObject: "Analyze and review",
            purpose: "Run two bounded phases.",
            originalReadSet: [source],
            originalWriteSet: [],
            phases: [
                phase(number: 1, mode: .analyze, readSet: [source]),
                phase(number: 2, mode: .review, readSet: [source]),
            ]
        )
        #expect(throws: Never.self) { try mixed.validate() }
    }

    @Test("Each phase recomputes scope and permission without inheritance")
    func mixedScopeAndPermissionIsolation() throws {
        let source = object(.sourceFile, "paper.pdf")
        let current = DocumentFingerprint(content: "current note")
        let note = object(.note, "Analyses/Paper.md", fingerprint: current)
        let valid = ResearchWorkflowContract(
            mode: .mixed,
            taskObject: "Analyze and integrate",
            purpose: "Keep candidate analysis separate from one authorized update.",
            originalReadSet: [source, note],
            originalWriteSet: [note],
            phases: [
                phase(
                    number: 1,
                    mode: .analyze,
                    readSet: [source],
                    permission: .candidateOnly,
                    durability: .handoff
                ),
                phase(
                    number: 2,
                    mode: .integrate,
                    readSet: [source, note],
                    writeSet: [note],
                    permission: .directEditAuthorized,
                    permissionBasis: "The researcher explicitly requested this exact note update.",
                    durability: .durableUpdate
                ),
            ]
        )
        try valid.validate()

        let outside = object(.note, "Topics/Outside.md", fingerprint: current)
        let expanded = ResearchWorkflowContract(
            mode: .mixed,
            taskObject: valid.taskObject,
            purpose: valid.purpose,
            originalReadSet: [source, note],
            originalWriteSet: [note],
            phases: [
                phase(number: 1, mode: .analyze, readSet: [source]),
                phase(
                    number: 2,
                    mode: .integrate,
                    readSet: [source, note],
                    writeSet: [outside],
                    permission: .directEditAuthorized,
                    permissionBasis: "A previous phase suggested it.",
                    durability: .durableUpdate
                ),
            ]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try expanded.validate()
        }

        let nonprovisional = ResearchWorkflowContract(
            mode: .analyze,
            taskObject: "Analyze",
            purpose: "Reject automatic settlement.",
            originalReadSet: [source],
            originalWriteSet: [],
            phases: [phase(
                mode: .analyze,
                readSet: [source],
                handoff: ResearchWorkflowHandoff(
                    provisional: false,
                    summary: "Treat this as settled.",
                    evidenceStatus: "Unreviewed"
                )
            )]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try nonprovisional.validate()
        }
    }

    @Test("Direct edits require exact current fingerprints and a stated permission basis")
    func directEditRequirements() {
        let unfingerprinted = object(.note, "Works/Draft.md")
        let missingRevision = ResearchWorkflowContract(
            mode: .write,
            taskObject: "Revise one Work",
            purpose: "Apply an authorized philosophical revision.",
            originalReadSet: [unfingerprinted],
            originalWriteSet: [unfingerprinted],
            phases: [phase(
                mode: .write,
                readSet: [unfingerprinted],
                writeSet: [unfingerprinted],
                permission: .directEditAuthorized,
                permissionBasis: "The researcher requested the edit.",
                durability: .durableUpdate
            )]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try missingRevision.validate()
        }

        let note = object(
            .note,
            "Works/Draft.md",
            fingerprint: DocumentFingerprint(content: "draft")
        )
        let missingBasis = ResearchWorkflowContract(
            mode: .write,
            taskObject: "Revise one Work",
            purpose: "Apply an authorized philosophical revision.",
            originalReadSet: [note],
            originalWriteSet: [note],
            phases: [phase(
                mode: .write,
                readSet: [note],
                writeSet: [note],
                permission: .directEditAuthorized,
                permissionBasis: "",
                durability: .durableUpdate
            )]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try missingBasis.validate()
        }
    }

    @Test("A Research Unit scope change requires explicit scope-change authorization")
    func researchUnitAuthorization() throws {
        let source = object(.sourceFile, "book.pdf")
        let bounded = ResearchWorkflowResearchUnit(
            currentScope: "Chapters 1–2",
            proposedScope: "Chapters 1–3"
        )
        let unauthorized = ResearchWorkflowContract(
            mode: .analyze,
            taskObject: "Continue one cumulative monograph Analysis",
            purpose: "Extend the same Analysis only through actual reading progress.",
            originalReadSet: [source],
            originalWriteSet: [],
            researchUnit: bounded,
            researchUnitAuthorization: .scopeDeclared,
            phases: [phase(mode: .analyze, readSet: [source])]
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            try unauthorized.validate()
        }

        let authorized = ResearchWorkflowContract(
            mode: .analyze,
            taskObject: unauthorized.taskObject,
            purpose: unauthorized.purpose,
            originalReadSet: [source],
            originalWriteSet: [],
            researchUnit: bounded,
            researchUnitAuthorization: .scopeChangeAuthorized,
            phases: [phase(mode: .analyze, readSet: [source])]
        )
        try authorized.validate()
    }

    @Test("Assembly loads only the selected Practice references and fingerprints every resource")
    func boundedPracticeAssembly() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ResearchSkillTransactionCoordinator(controlURL: root.appendingPathComponent(".scholium"))
        let note = object(.note, "Works/Argument.md")
        let contract = ResearchWorkflowContract(
            mode: .review,
            taskObject: "Review an argument",
            purpose: "Evaluate the argument without editing it.",
            originalReadSet: [note],
            originalWriteSet: [],
            phases: [phase(
                mode: .review,
                requiredSkills: ["scholium-critique"],
                selectedPractices: [ResearchPracticeSelection(
                    packageID: "scholium-philosophical-practices",
                    practiceID: "reviewer"
                )],
                readSet: [note]
            )]
        )

        let envelope = try await ResearchWorkflowAssembler.resolve(contract, store: store)
        let practice = try #require(envelope.phases[0].packages.first {
            $0.id == "scholium-philosophical-practices"
        })
        let loaded = practice.loadedResources.map(\.relativePath)
        #expect(loaded == [
            "SKILL.md",
            "references/Reviewer.md",
        ])
        #expect(!loaded.contains("references/practice-catalog.md"))
        #expect(!loaded.contains("references/Dialectical-Partner.md"))
        #expect(practice.loadedResources.allSatisfy {
            $0.revision == DocumentFingerprint(content: $0.source)
        })
        #expect(envelope.isExecutable)
        #expect(envelope.warnings.isEmpty)
        #expect(envelope.renderedInstructions.contains("ephemeral structural task packet"))
        for protectedCapacity in [
            "Background-Grasping",
            "Concept-Understanding",
            "Philosophical Taste",
            "Logical and Dialectical Reasoning",
            "false consensus",
        ] {
            #expect(envelope.renderedInstructions.contains(protectedCapacity))
        }
        for unselectedPracticeID in [
            "research-explorer",
            "thesis-architect",
            "philosophical-expositor",
        ] {
            #expect(!envelope.renderedInstructions.contains(unselectedPracticeID))
        }
    }

    @Test("The audit planner keeps final substantive revisions and never self-schedules")
    func auditPlanning() throws {
        let target = object(.note, "Works/Argument.md")
        let old = DocumentFingerprint(content: "old")
        let final = DocumentFingerprint(content: "final")
        let evidence = DocumentFingerprint(content: "evidence-v2")
        let markers = [
            ResearchAuditMarker(
                target: target,
                fingerprint: old,
                auditScope: ["source-fidelity"],
                phase: 1,
                sourceMode: .write
            ),
            ResearchAuditMarker(
                target: target,
                fingerprint: final,
                auditScope: ["source-fidelity"],
                evidenceRevisions: [evidence],
                phase: 2,
                sourceMode: .write
            ),
            ResearchAuditMarker(
                target: target,
                fingerprint: final,
                auditScope: ["logical-validity"],
                evidenceRevisions: [evidence],
                phase: 2,
                sourceMode: .write
            ),
            ResearchAuditMarker(
                target: target,
                fingerprint: final,
                auditScope: ["source-fidelity"],
                phase: 3,
                sourceMode: .audit
            ),
        ]
        let completed = ResearchCompletedAudit(
            target: target,
            fingerprint: final,
            auditScope: ["source-fidelity"],
            evidenceRevisions: [evidence]
        )

        let plan = try ResearchAuditPlanner.plan(ResearchAuditPlanningInput(
            markers: markers,
            completedAudits: [completed]
        ))
        #expect(plan.reused.count == 1)
        #expect(plan.scheduled.count == 1)
        #expect(plan.scheduled[0].auditScope == ["logical-validity"])
        #expect(plan.ignoredAuditPhaseMarkers == 1)
        #expect(!plan.scheduled.contains { $0.fingerprint == old })

        let changedEvidence = ResearchCompletedAudit(
            target: target,
            fingerprint: final,
            auditScope: ["source-fidelity"],
            evidenceRevisions: [DocumentFingerprint(content: "stale evidence")]
        )
        let stalePlan = try ResearchAuditPlanner.plan(ResearchAuditPlanningInput(
            markers: [markers[1]],
            completedAudits: [changedEvidence]
        ))
        #expect(stalePlan.reused.isEmpty)
        #expect(stalePlan.scheduled.count == 1)

        let conflictingTarget = ResearchWorkflowObjectReference(
            kind: .note,
            identifier: target.identifier,
            fingerprint: old
        )
        #expect(throws: ResearchWorkflowContractError.self) {
            _ = try ResearchAuditPlanner.plan(ResearchAuditPlanningInput(markers: [
                ResearchAuditMarker(
                    target: conflictingTarget,
                    fingerprint: final,
                    auditScope: ["source-fidelity"],
                    phase: 1,
                    sourceMode: .write
                )
            ]))
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }

    private func object(
        _ kind: ResearchWorkflowObjectKind,
        _ identifier: String,
        fingerprint: DocumentFingerprint? = nil
    ) -> ResearchWorkflowObjectReference {
        ResearchWorkflowObjectReference(
            kind: kind,
            identifier: identifier,
            fingerprint: fingerprint
        )
    }

    private func phase(
        number: Int = 1,
        mode: ResearchSkillMode,
        requiredSkills: [String] = [],
        selectedPractices: [ResearchPracticeSelection] = [],
        readSet: [ResearchWorkflowObjectReference],
        writeSet: [ResearchWorkflowObjectReference] = [],
        permission: ResearchWorkflowPermission = .readOnly,
        permissionBasis: String = "",
        durability: ResearchWorkflowDurability = .ephemeral,
        handoff: ResearchWorkflowHandoff? = nil
    ) -> ResearchWorkflowPhaseContract {
        ResearchWorkflowPhaseContract(
            phase: number,
            mode: mode,
            purpose: "Perform only this bounded phase.",
            requiredSkillIDs: requiredSkills,
            selectedPractices: selectedPractices,
            readSet: readSet,
            writeSet: writeSet,
            permission: permission,
            permissionBasis: permissionBasis,
            output: "Return the declared scholarly result.",
            stopCondition: "Stop when the bounded phase is complete or evidence is unavailable.",
            durability: durability,
            handoff: handoff ?? ResearchWorkflowHandoff(
                summary: "A provisional phase result.",
                evidenceStatus: "Must be reassessed by any later phase."
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumWorkflow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
