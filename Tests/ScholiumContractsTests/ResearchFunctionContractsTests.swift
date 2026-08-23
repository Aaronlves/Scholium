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
            kind: .resynthesis
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
            recordTitle: try ResearchRecordTitle("Used selected analyses"),
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
            recordTitle: try ResearchRecordTitle("No selected material used"),
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

    @Test("Function roles, write authority, change evidence, and Fidelity requirements are explicit")
    func functionRoleMatrix() {
        #expect(ResearchFunctionID.develop.allowedTargetRoles == [.analysis, .topic])
        #expect(ResearchFunctionID.critique.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.revise.allowedTargetRoles == [.work])
        #expect(ResearchFunctionID.discuss.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))
        #expect(ResearchFunctionID.fidelity.allowedTargetRoles == Set(ResearchFunctionTargetRole.allCases))

        #expect(ResearchFunctionID.develop.writesTarget)
        #expect(ResearchFunctionID.revise.writesTarget)
        #expect(!ResearchFunctionID.discuss.writesTarget)
        #expect(!ResearchFunctionID.fidelity.writesTarget)
        #expect(!ResearchFunctionID.critique.writesTarget)

        #expect(ResearchFunctionID.develop.requiresAgentChangeEvidence)
        #expect(ResearchFunctionID.revise.requiresAgentChangeEvidence)
        #expect(!ResearchFunctionID.critique.requiresAgentChangeEvidence)
        #expect(!ResearchFunctionID.discuss.requiresAgentChangeEvidence)
        #expect(!ResearchFunctionID.fidelity.requiresAgentChangeEvidence)
    }

    @Test("Requests reject duplicate Targets, invalid scopes, checks, and roles")
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
            scope: .passage(anchor)
        ).validate()
    }

    @Test("Retired conditional-resource fields fail closed")
    func retiredConditionalResourceFieldsAreRejected() throws {
        let target = target(role: .analysis)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var retired = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchFunctionRequest(
                    function: .develop,
                    target: target
                ))
            ) as? [String: Any]
        )
        retired["conditional_resources"] = ["development_synthesis"]
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try decoder.decode(
                ResearchFunctionRequest.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
    }

    @Test("Retired snapshot fields fail closed")
    func retiredSnapshotFieldsAreRejected() throws {
        let encoder = JSONEncoder()
        var retired = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchFunctionSnapshot(
                    request: ResearchFunctionRequest(
                        function: .develop,
                        target: target(role: .topic)
                    )
                ))
            ) as? [String: Any]
        )
        retired["recordKind"] = "function_envelope"
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchFunctionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
        retired.removeValue(forKey: "recordKind")
        retired["requiredChildFunctions"] = []
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchFunctionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
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
        ])
        let defaults = try decoder.decode(ResearchFunctionRequest.self, from: defaultData)
        #expect(defaults.dialogueResponseModules == nil)
    }

    @Test("Retired Comment evidence fields fail closed")
    func retiredCommentEvidenceFieldsAreRejected() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var request = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchFunctionRequest(
                    function: .develop,
                    target: target(role: .analysis)
                ))
            ) as? [String: Any]
        )
        request["commentIDs"] = []
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try decoder.decode(
                ResearchFunctionRequest.self,
                from: JSONSerialization.data(withJSONObject: request)
            )
        }

        var snapshot = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchFunctionSnapshot(
                    request: ResearchFunctionRequest(
                        function: .develop,
                        target: target(role: .analysis)
                    )
                ))
            ) as? [String: Any]
        )
        snapshot["evidenceRevisions"] = []
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try decoder.decode(
                ResearchFunctionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: snapshot)
            )
        }
    }

    @Test("Unsupported Dialogue identifiers are rejected instead of projected")
    func unsupportedDialogueIdentifiersAreRejected() throws {
        let data = Data("\"dialogue\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchFunctionID.self, from: data)
        }
    }

    @Test("Retired Function write-scope fields fail closed while shared Fidelity targets remain typed")
    func retiredWriteScopeFieldsAreRejected() throws {
        let analysis = target(role: .analysis)
        let topic = target(role: .topic)
        let write = ResearchFunctionRequest(
            function: .develop,
            target: analysis
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var retired = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(write))
                as? [String: Any]
        )
        retired["writeScope"] = "selected_notes"
        retired["authorizedWriteTargets"] = []
        #expect(throws: ResearchFunctionContractError.self) {
            _ = try decoder.decode(
                ResearchFunctionRequest.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
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

    @Test("Fidelity evidence identity changes with revision, scope, and exact Skill entry")
    func fidelityEvidenceIdentity() throws {
        let target = target(role: .analysis)
        let anchor = CommentAnchor(
            fingerprint: target.fingerprint,
            utf8Range: 0..<5,
            utf16Range: 0..<5,
            line: 1,
            endLine: 1,
            quotation: "claim"
        )
        let exactMethod = try method(
            primarySource: "# Fidelity\n\nCheck exact content.\n"
        )
        let whole = try snapshot(
            target: target,
            scope: .whole,
            method: exactMethod
        )
        let implicitWhole = try snapshot(
            target: target,
            scope: nil,
            method: exactMethod
        )
        let passage = try snapshot(
            target: target,
            scope: .passage(anchor),
            method: exactMethod
        )
        let changedSkill = try snapshot(
            target: target,
            scope: .whole,
            method: method(
                primarySource: "# Fidelity\n\nCheck exact content and roles.\n"
            )
        )
        let changedCitationStyle = try snapshot(
            target: target,
            scope: .whole,
            method: exactMethod,
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
        #expect(makeKey(whole) != makeKey(changedSkill))
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
        method: ResearchMethodSnapshot,
        citationStyle: String? = "apa-7"
    ) throws -> ResearchFunctionSnapshot {
        let actionTarget = ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: .analysis,
            fingerprint: target.fingerprint,
            title: target.title
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .checkFidelity
            }
        )
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: DocumentFingerprint(content: "profiles")
        )
        let platformInputs = try ResearchActionPlatformInputs(
            passage: scope?.selection,
            fidelityChecks: [.content]
        )
        let academicInputs = try ResearchAcademicFieldValues(
            values: [:],
            definitions: profile.academicInputFields
        )
        let resultContract = try ResearchResultContract(
            profile: profile,
            registrationKey: method.registration.key,
            profileRevision: resolvedProfile.profileRevision
        )
        let action = try ResearchActionSnapshot(
            definition: .checkFidelity,
            target: actionTarget,
            method: method,
            resolvedProfile: resolvedProfile,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: resultContract,
            authority: ResearchAuthorityEnvelope(
                readableNotes: [actionTarget],
                writableNotes: [],
                writeOperations: [],
                editableMetadataKeys: []
            )
        )
        return ResearchFunctionSnapshot(
            request: ResearchFunctionRequest(
                function: .fidelity,
                target: target,
                scope: scope,
                checks: [.content]
            ),
            actionSnapshot: action,
            citationStyle: citationStyle
        )
    }

    private func method(primarySource: String) throws -> ResearchMethodSnapshot {
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(
                    uuidString: "00000000-0000-4000-8000-000000000050"
                )!
            ),
            actionID: .checkFidelity,
            displayName: "Content Fidelity",
            primaryMarkdown: .machineLocal()
        )
        return try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: primarySource
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
