import Foundation
import ScholiumContracts
import Testing

@Suite("Research Function boundary contracts")
struct ResearchFunctionContractsTests {
    @Test("Continuation lineage round-trips as strict non-authorizing provenance")
    func continuationLineageRoundTrip() throws {
        let lineage = ResearchContinuationLineage(
            groupID: UUID(),
            parentRunID: UUID(),
            requestID: UUID(),
            kind: .approvedAction
        )
        let data = try JSONEncoder().encode(lineage)
        #expect(try JSONDecoder().decode(
            ResearchContinuationLineage.self,
            from: data
        ) == lineage)

        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["grant"] = true
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContinuationLineage.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "grant")
        object["schema_version"] = 99
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContinuationLineage.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let resynthesis = ResearchContinuationLineage(
            groupID: UUID(),
            parentRunID: UUID(),
            requestID: UUID(),
            kind: .resynthesis
        )
        #expect(try JSONDecoder().decode(
            ResearchContinuationLineage.self,
            from: JSONEncoder().encode(resynthesis)
        ) == resynthesis)
    }

    @Test("Actually-used Material testimony preserves explicit empty and retained missing states")
    func actuallyUsedMaterialTestimonyCompatibility() throws {
        let first = UUID()
        let second = UUID()
        let submission = ResearchFunctionCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            actuallyUsedMaterialNoteIDs: [second, first],
            summary: "Used both selected analyses.",
            didModifyTarget: false
        )
        let data = try JSONEncoder().encode(submission)
        #expect(submission.actuallyUsedMaterialNoteIDs == [first, second].sorted {
            $0.uuidString < $1.uuidString
        })
        #expect(try JSONDecoder().decode(
            ResearchFunctionCompletionSubmission.self,
            from: data
        ) == submission)

        let explicitlyEmpty = ResearchFunctionCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            actuallyUsedMaterialNoteIDs: [],
            summary: "No selected Material was actually used.",
            didModifyTarget: false
        )
        let emptyData = try JSONEncoder().encode(explicitlyEmpty)
        let emptyObject = try #require(
            JSONSerialization.jsonObject(with: emptyData) as? [String: Any]
        )
        #expect(explicitlyEmpty.actuallyUsedMaterialNoteIDs == [])
        #expect((emptyObject["actuallyUsedMaterialNoteIDs"] as? [String]) == [])

        var legacy = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        legacy.removeValue(forKey: "actuallyUsedMaterialNoteIDs")
        let decodedLegacy = try JSONDecoder().decode(
            ResearchFunctionCompletionSubmission.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(decodedLegacy.actuallyUsedMaterialNoteIDs == nil)
    }

    @Test("Function roles, write authority, checkpoints, and Fidelity requirements are explicit")
    func functionRoleMatrix() {
        #expect(ResearchFunctionID.develop.allowedTargetRoles == [.analysis, .topic])
        #expect(ResearchFunctionID.critique.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.revise.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.manuscript.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.discuss.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))
        #expect(ResearchFunctionID.fidelity.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))

        #expect(ResearchFunctionID.develop.writesTarget)
        #expect(ResearchFunctionID.revise.writesTarget)
        #expect(ResearchFunctionID.manuscript.writesTarget)
        #expect(!ResearchFunctionID.discuss.writesTarget)
        #expect(!ResearchFunctionID.fidelity.writesTarget)
        #expect(!ResearchFunctionID.critique.writesTarget)

        #expect(ResearchFunctionID.develop.requiresCheckpoint)
        #expect(ResearchFunctionID.critique.requiresCheckpoint)
        #expect(ResearchFunctionID.revise.requiresCheckpoint)
        #expect(ResearchFunctionID.manuscript.requiresCheckpoint)
        #expect(!ResearchFunctionID.discuss.requiresCheckpoint)
        #expect(!ResearchFunctionID.fidelity.requiresCheckpoint)
    }

    @Test("Requests reject duplicate Targets, invalid scopes, checks, roles, and conditional resources")
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
                conditionalResources: [.revisionFeedback]
            ).validate()
        }

        let anchor = CommentAnchor(
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
            conditionalResources: []
        ).validate()
    }

    @Test("Legacy conditional resources remain decodable but are not active Method modes")
    func legacyResourceSelectionIsInactive() throws {
        let target = target(role: .analysis)
        let inherited = ResearchFunctionRequest(function: .develop, target: target)
        let explicitEmpty = ResearchFunctionRequest(
            function: .develop,
            target: target,
            conditionalResources: []
        )
        #expect(inherited.conditionalResources == nil)
        #expect(explicitEmpty.conditionalResources == [])
        #expect(!inherited.awaitsResourceSelection)
        #expect(!explicitEmpty.awaitsResourceSelection)
        #expect(ResearchFunctionID.develop.conditionalResources.isEmpty)
        #expect(ResearchFunctionID.discuss.conditionalResources.isEmpty)
        #expect(ResearchFunctionConditionalResource.developmentSynthesis.kind == .method)
        #expect(ResearchFunctionConditionalResource.revisionOutputContracts.kind == .template)
        #expect(ResearchFunctionConditionalResource.manuscriptGates.kind == .checklist)

        #expect(throws: ResearchFunctionContractError.self) {
            try inherited.selectingResources([.developmentSynthesis])
        }

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
        #expect(inheritedRoundTrip.conditionalResources == nil)
        #expect(explicitRoundTrip.conditionalResources == [])
        let legacy = ResearchFunctionRequest(
            function: .develop,
            target: target,
            conditionalResources: [.developmentSynthesis]
        )
        let encodedRequest = String(decoding: try encoder.encode(legacy), as: UTF8.self)
        #expect(encodedRequest.contains("conditional_resources"))
        #expect(try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(legacy)
        ) == legacy)
        #expect(throws: ResearchFunctionContractError.self) {
            try legacy.validate()
        }

        let submission = ResearchFunctionResourceSelectionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            resources: [.developmentSynthesis]
        )
        #expect(try decoder.decode(
            ResearchFunctionResourceSelectionSubmission.self,
            from: encoder.encode(submission)
        ) == submission)
        let encodedSubmission = String(decoding: try encoder.encode(submission), as: UTF8.self)
        #expect(encodedSubmission.contains("\"resources\""))
        #expect(!encodedSubmission.contains("\"methods\""))

    }

    @Test("Discuss module selection is ordered and request scoped")
    func discussResponseModuleSelection() throws {
        let analysis = target(role: .analysis)
        let selected = ResearchFunctionRequest(
            function: .discuss,
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
            function: .discuss,
            target: analysis,
            instruction: "State the bounded academic outcome.",
            dialogueResponseModules: []
        )
        #expect(academicOutcomeOnly.dialogueResponseModules == [])
        try academicOutcomeOnly.validate()

        #expect(throws: ResearchFunctionContractError.self) {
            try ResearchFunctionRequest(
                function: .discuss,
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

        let defaultData = try JSONSerialization.data(withJSONObject: [
            "function": "discuss",
            "target": try JSONSerialization.jsonObject(with: encoder.encode(analysis)),
            "materials": [],
            "instruction": "State the bounded academic outcome.",
            "checks": [],
            "commentIDs": [],
        ])
        let defaults = try decoder.decode(ResearchFunctionRequest.self, from: defaultData)
        #expect(defaults.dialogueResponseModules == nil)
    }

    @Test("Unsupported Dialogue identifiers are rejected instead of projected")
    func legacyDialogueIdentifiersAreRejected() throws {
        let data = Data("\"dialogue\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchFunctionID.self, from: data)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchFunctionRecordKind.self, from: data)
        }
    }

    @Test("Legacy multi-target writes round-trip but cannot authorize a current Action")
    func legacyMultiTargetWriteRoundTripIsInactive() throws {
        let analysis = target(role: .analysis)
        let topic = target(role: .topic)
        let write = ResearchFunctionRequest(
            function: .develop,
            target: analysis,
            conditionalResources: [],
            writeScope: .selectedNotes,
            authorizedWriteTargets: [analysis, topic]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let storedWrite = try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(write)
        )
        #expect(storedWrite == write)
        #expect(storedWrite.writeScope == .selectedNotes)
        #expect(Set(storedWrite.authorizedWriteTargets.map(\.noteID)) == [
            analysis.noteID,
            topic.noteID,
        ])
        #expect(throws: ResearchFunctionContractError.self) {
            try storedWrite.validate()
        }

        let fidelity = ResearchFunctionRequest(
            function: .fidelity,
            target: analysis,
            checks: [.content, .citations],
            fidelityTargets: [topic, analysis]
        )
        try fidelity.validate()
        let storedFidelity = try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(fidelity)
        )
        #expect(storedFidelity == fidelity)
        #expect(Set(storedFidelity.resolvedFidelityTargets.map(\.noteID)) == [
            analysis.noteID,
            topic.noteID,
        ])
    }

    @Test("Citation style selection is explicit")
    func citationStyleSelection() throws {
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

    @Test("Material candidate metadata is deterministic")
    func materialCandidateMetadata() throws {
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

    }

    @Test("Fidelity evidence identity changes with revision, scope, comments, and loaded audit resources")
    func fidelityEvidenceIdentity() {
        let target = target(role: .analysis)
        let anchor = CommentAnchor(
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
