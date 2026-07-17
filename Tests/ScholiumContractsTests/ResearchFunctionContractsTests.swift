import Foundation
import ScholiumContracts
import Testing

@Suite("Research Function boundary contracts")
struct ResearchFunctionContractsTests {
    @Test("Function roles, write authority, checkpoints, and Fidelity requirements are explicit")
    func functionRoleMatrix() {
        #expect(ResearchFunctionID.develop.allowedTargetRoles == [.analysis, .topic])
        #expect(ResearchFunctionID.review.allowedTargetRoles == [.analysis, .topic])
        #expect(ResearchFunctionID.critique.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.revise.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.manuscript.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.dialogue.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))
        #expect(ResearchFunctionID.fidelity.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))

        #expect(ResearchFunctionID.develop.writesTarget)
        #expect(ResearchFunctionID.revise.writesTarget)
        #expect(ResearchFunctionID.manuscript.writesTarget)
        #expect(!ResearchFunctionID.dialogue.writesTarget)
        #expect(!ResearchFunctionID.review.writesTarget)
        #expect(!ResearchFunctionID.fidelity.writesTarget)
        #expect(!ResearchFunctionID.critique.writesTarget)

        #expect(ResearchFunctionID.develop.requiresCheckpoint)
        #expect(ResearchFunctionID.critique.requiresCheckpoint)
        #expect(ResearchFunctionID.revise.requiresCheckpoint)
        #expect(ResearchFunctionID.manuscript.requiresCheckpoint)
        #expect(!ResearchFunctionID.dialogue.requiresCheckpoint)
        #expect(!ResearchFunctionID.review.requiresCheckpoint)
        #expect(!ResearchFunctionID.fidelity.requiresCheckpoint)
    }

    @Test("Requests reject duplicate Targets, invalid scopes, checks, roles, and internal methods")
    func requestValidation() throws {
        let analysis = target(role: .analysis)
        let work = target(role: .work)
        let material = ResearchFunctionMaterial(
            noteID: analysis.noteID,
            note: analysis.note,
            role: analysis.role,
            fingerprint: analysis.fingerprint,
            title: analysis.title
        )
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                materials: [material]
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: work
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                scope: ResearchFunctionScope(kind: .passage)
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                checks: [.content]
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .fidelity,
                target: analysis
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                methods: [.revisionFeedback]
            ).validate()
        }

        let anchor = ResearcherCommentAnchor(
            fingerprint: analysis.fingerprint,
            utf8Range: 2..<7,
            utf16Range: 2..<7,
            line: 1,
            endLine: 1,
            quotation: "claim"
        )
        try ResearchFunctionRequest(
            function: .develop,
            target: analysis,
            scope: .passage(anchor),
            methods: []
        ).validate()
    }

    @Test("Nil and explicit-empty method selections survive their distinct Codable meanings")
    func methodSelectionCodable() throws {
        let target = target(role: .analysis)
        let inherited = ResearchFunctionRequest(function: .develop, target: target)
        let explicitEmpty = ResearchFunctionRequest(
            function: .develop,
            target: target,
            methods: []
        )
        #expect(inherited.methods == nil)
        #expect(explicitEmpty.methods == [])
        #expect(inherited.awaitsMethodSelection)
        #expect(!explicitEmpty.awaitsMethodSelection)
        #expect(ResearchFunctionID.develop.conditionalMethods.contains(
            .developmentSynthesis
        ))
        #expect(ResearchFunctionID.dialogue.conditionalMethods.isEmpty)

        let finalized = try inherited.selectingMethods([.developmentSynthesis])
        #expect(finalized.methods == [.developmentSynthesis])
        #expect(finalized.target == inherited.target)
        #expect(finalized.materials == inherited.materials)
        #expect(finalized.instruction == inherited.instruction)
        #expect(!finalized.awaitsMethodSelection)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        let inheritedRoundTrip = try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(inherited)
        )
        let explicitRoundTrip = try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(explicitEmpty)
        )
        #expect(inheritedRoundTrip.methods == nil)
        #expect(explicitRoundTrip.methods == [])

        let submission = ResearchFunctionMethodSelectionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            methods: [.developmentSynthesis]
        )
        #expect(try decoder.decode(
            ResearchFunctionMethodSelectionSubmission.self,
            from: encoder.encode(submission)
        ) == submission)
    }

    @Test("Dialogue module selection is ordered, request scoped, and legacy compatible")
    func dialogueResponseModuleSelection() throws {
        let analysis = target(role: .analysis)
        let selected = ResearchFunctionRequest(
            function: .dialogue,
            target: analysis,
            instruction: "State the bounded academic outcome.",
            dialogueResponseModules: [
                .researchDirections,
                .criticalReflection,
                .remainingQuestions,
            ]
        )
        #expect(selected.dialogueResponseModules == [
            .criticalReflection,
            .remainingQuestions,
            .researchDirections,
        ])
        try selected.validate()

        let academicOutcomeOnly = ResearchFunctionRequest(
            function: .dialogue,
            target: analysis,
            instruction: "State the bounded academic outcome.",
            dialogueResponseModules: []
        )
        #expect(academicOutcomeOnly.dialogueResponseModules == [])
        try academicOutcomeOnly.validate()

        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .dialogue,
                target: analysis,
                instruction: "State the bounded academic outcome.",
                dialogueResponseModules: [
                    .remainingQuestions,
                    .remainingQuestions,
                ]
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .develop,
                target: analysis,
                dialogueResponseModules: []
            ).validate()
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let roundTrip = try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(selected)
        )
        #expect(roundTrip.dialogueResponseModules == selected.dialogueResponseModules)

        let legacyData = try JSONSerialization.data(withJSONObject: [
            "function": "dialogue",
            "target": try JSONSerialization.jsonObject(with: encoder.encode(analysis)),
            "materials": [],
            "instruction": "State the bounded academic outcome.",
            "checks": [],
            "commentIDs": [],
        ])
        let legacy = try decoder.decode(ResearchFunctionRequest.self, from: legacyData)
        #expect(legacy.dialogueResponseModules == nil)
    }

    @Test("Citation style selection is explicit while legacy package-only input remains decodable")
    func citationStyleSelectionCompatibility() throws {
        let legacy = try JSONDecoder().decode(
            ResearchCitationMethodSelection.self,
            from: Data(#"{"packageID":"legacy-citations"}"#.utf8)
        )
        #expect(legacy.packageID == "legacy-citations")
        #expect(legacy.citationStyle == nil)

        let selected = ResearchCitationMethodSelection(
            packageID: "local-citations",
            citationStyle: " APA-7 "
        )
        #expect(selected.citationStyle == "apa-7")
        let roundTrip = try JSONDecoder().decode(
            ResearchCitationMethodSelection.self,
            from: JSONEncoder().encode(selected)
        )
        #expect(roundTrip == selected)
    }

    @Test("Material candidate metadata is deterministic and legacy compatible")
    func materialCandidateMetadataCompatibility() throws {
        let vaultID = UUID()
        let material = ResearchFunctionMaterial(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Debates/Agency.md"
            ),
            role: .topic,
            fingerprint: DocumentFingerprint(content: "agency"),
            title: "Agency"
        )
        let target = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Analyses/Source.md"
        )
        let candidate = ResearchFunctionMaterialCandidate(
            material: material,
            aliases: [" Freedom ", "Agency", "Freedom", ""],
            suggestionReasons: [
                suggestionReason(
                    .linksDirectlyToTarget,
                    source: material.note,
                    lowerBound: 40
                ),
                suggestionReason(
                    .linkedFromTarget,
                    source: target,
                    lowerBound: 20
                ),
                suggestionReason(
                    .linkedFromSelectedPassage,
                    source: target,
                    lowerBound: 20
                ),
            ]
        )

        #expect(candidate.aliases == ["Agency", "Freedom"])
        #expect(candidate.suggestionReasons.map(\.kind) == [
            .linkedFromSelectedPassage,
            .linkedFromTarget,
            .linksDirectlyToTarget,
        ])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(
            ResearchFunctionMaterialCandidate.self,
            from: encoder.encode(candidate)
        ) == candidate)

        let legacyData = try JSONSerialization.data(withJSONObject: [
            "material": try JSONSerialization.jsonObject(with: encoder.encode(material)),
            "isSelectable": true,
            "repairReasons": [],
        ])
        let legacy = try decoder.decode(
            ResearchFunctionMaterialCandidate.self,
            from: legacyData
        )
        #expect(legacy.aliases.isEmpty)
        #expect(legacy.suggestionReasons.isEmpty)
        #expect(legacy.material == material)
    }

    @Test("Fidelity invocation provenance round trips without changing evidence identity")
    func fidelityInvocationProvenance() throws {
        let target = target(role: .analysis)
        let request = ResearchFunctionRequest(
            function: .fidelity,
            target: target,
            checks: [.content]
        )
        let parentRunID = UUID()
        let manual = ResearchFunctionSnapshot(
            request: request,
            recordKind: .functionEnvelope,
            fidelityInvocation: .manual
        )
        let automatic = ResearchFunctionSnapshot(
            request: request,
            recordKind: .functionEnvelope,
            fidelityInvocation: .automatic(parentRunID: parentRunID)
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let roundTrip = try decoder.decode(
            ResearchFunctionSnapshot.self,
            from: encoder.encode(automatic)
        )
        #expect(roundTrip.resolvedFidelityInvocation == .automatic(
            parentRunID: parentRunID
        ))

        let makeKey: (ResearchFunctionSnapshot) -> ResearchFidelityEvidenceKey = {
            ResearchFidelityEvidenceKey(
                snapshot: $0,
                finalTargetFingerprint: target.fingerprint,
                finalMaterialFingerprints: [:],
                checks: [.content]
            )
        }
        #expect(makeKey(manual) == makeKey(automatic))

        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(manual))
                as? [String: Any]
        )
        legacyObject.removeValue(forKey: "fidelityInvocation")
        let legacy = try decoder.decode(
            ResearchFunctionSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        #expect(legacy.fidelityInvocation == nil)
        #expect(legacy.resolvedFidelityInvocation == .manual)
    }

    @Test("Fidelity evidence identity changes with revision, scope, comments, and loaded audit resources")
    func fidelityEvidenceIdentity() {
        let target = target(role: .analysis)
        let anchor = ResearcherCommentAnchor(
            fingerprint: target.fingerprint,
            utf8Range: 0..<5,
            utf16Range: 0..<5,
            line: 1,
            endLine: 1,
            quotation: "claim"
        )
        let skill = ResearchFunctionSkillSnapshot(
            packageID: "scholium-content-fidelity",
            origin: .bundled,
            version: "1.0.0",
            packageRevision: DocumentFingerprint(content: "package-v1"),
            loadedResources: [ResearchFunctionResourceSnapshot(
                relativePath: "references/content.md",
                revision: DocumentFingerprint(content: "content-v1")
            )]
        )
        let whole = snapshot(
            target: target,
            scope: .whole,
            evidence: [DocumentFingerprint(content: "comment-v1")],
            skill: skill
        )
        let implicitWhole = snapshot(
            target: target,
            scope: nil,
            evidence: [DocumentFingerprint(content: "comment-v1")],
            skill: skill
        )
        let passage = snapshot(
            target: target,
            scope: .passage(anchor),
            evidence: [DocumentFingerprint(content: "comment-v1")],
            skill: skill
        )
        let changedComment = snapshot(
            target: target,
            scope: .whole,
            evidence: [DocumentFingerprint(content: "comment-v2")],
            skill: skill
        )
        let changedResource = snapshot(
            target: target,
            scope: .whole,
            evidence: [DocumentFingerprint(content: "comment-v1")],
            skill: ResearchFunctionSkillSnapshot(
                packageID: skill.packageID,
                origin: skill.origin,
                version: skill.version,
                packageRevision: skill.packageRevision,
                loadedResources: [ResearchFunctionResourceSnapshot(
                    relativePath: "references/content.md",
                    revision: DocumentFingerprint(content: "content-v2")
                )]
            )
        )
        let changedCitationStyle = snapshot(
            target: target,
            scope: .whole,
            evidence: [DocumentFingerprint(content: "comment-v1")],
            skill: skill,
            citationStyle: "chicago-author-date"
        )
        let makeKey: (ResearchFunctionSnapshot) -> ResearchFidelityEvidenceKey = {
            ResearchFidelityEvidenceKey(
                snapshot: $0,
                finalTargetFingerprint: target.fingerprint,
                finalMaterialFingerprints: [:],
                checks: [.content]
            )
        }
        #expect(makeKey(whole) == makeKey(whole))
        #expect(makeKey(whole) == makeKey(implicitWhole))
        #expect(makeKey(whole) != makeKey(passage))
        #expect(makeKey(whole) != makeKey(changedComment))
        #expect(makeKey(whole) != makeKey(changedResource))
        #expect(makeKey(whole) != makeKey(changedCitationStyle))
        #expect(ResearchFidelityEvidenceKey(
            snapshot: whole,
            finalTargetFingerprint: DocumentFingerprint(content: "later target"),
            finalMaterialFingerprints: [:],
            checks: [.content]
        ) != makeKey(whole))
    }

    @Test("Fidelity outcomes cannot contradict their declared state")
    func fidelityOutcomeValidation() throws {
        try FidelityCheckOutcome(
            check: .content,
            state: .passed,
            summary: "No fidelity issue found."
        ).validate()
        #expect(throws: ResearchFunctionContractError.self) {
            try FidelityCheckOutcome(
                check: .content,
                state: .passed,
                summary: "Contradictory.",
                findings: ["An unresolved problem"]
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try FidelityCheckOutcome(
                check: .citations,
                state: .issuesFound,
                summary: "A problem exists."
            ).validate()
        }
        #expect(throws: ResearchFunctionContractError.self) {
            try FidelityCheckOutcome(
                check: .content,
                state: .unavailable,
                summary: " "
            ).validate()
        }
    }

    @Test("Returned maintenance files derive and verify exact source revisions")
    func maintenanceProposalFileRevisionDecoding() throws {
        let source = "---\nname: Evolving Method\ndescription: Test.\n---\nInstructions."
        let revisionlessData = try JSONSerialization.data(withJSONObject: [
            "files": [[
                "relativePath": "SKILL.md",
                "source": source,
            ]],
        ])
        let package = try JSONDecoder().decode(
            ResearchSkillProposedPackage.self,
            from: revisionlessData
        )
        #expect(package.entryPoint?.revision == DocumentFingerprint(content: source))
        try package.validate()

        let mismatchedData = try JSONSerialization.data(withJSONObject: [
            "files": [[
                "relativePath": "SKILL.md",
                "source": source,
                "revision": [
                    "sha256": DocumentFingerprint(content: "different").sha256,
                    "byteCount": 9,
                ],
            ]],
        ])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ResearchSkillProposedPackage.self,
                from: mismatchedData
            )
        }
    }

    private func target(role: ResearchFunctionTargetRole) -> ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Target.md"),
            role: role,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Target"
        )
    }

    private func snapshot(
        target: ResearchFunctionTarget,
        scope: ResearchFunctionScope?,
        evidence: [DocumentFingerprint],
        skill: ResearchFunctionSkillSnapshot,
        citationStyle: String? = "apa-7"
    ) -> ResearchFunctionSnapshot {
        ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                scope: scope,
                checks: [.content],
                commentIDs: [target.noteID]
            ),
            recordKind: .functionEnvelope,
            skills: [skill],
            phases: [ResearchFunctionPhaseSnapshot(
                phase: 1,
                function: .fidelity,
                skills: [skill],
                citationStyle: citationStyle
            )],
            evidenceRevisions: evidence
        )
    }

    private func suggestionReason(
        _ kind: ResearchFunctionMaterialSuggestionReason.Kind,
        source: VaultQualifiedNoteID,
        lowerBound: Int
    ) -> ResearchFunctionMaterialSuggestionReason {
        ResearchFunctionMaterialSuggestionReason(
            kind: kind,
            sourceNote: source,
            sourceSpan: SourceSpan(
                utf8LowerBound: lowerBound,
                utf8UpperBound: lowerBound + 5,
                utf16LowerBound: lowerBound,
                utf16UpperBound: lowerBound + 5,
                start: SourcePosition(
                    line: 1,
                    utf8Column: lowerBound + 1,
                    utf16Column: lowerBound + 1
                ),
                end: SourcePosition(
                    line: 1,
                    utf8Column: lowerBound + 6,
                    utf16Column: lowerBound + 6
                )
            )
        )
    }
}
