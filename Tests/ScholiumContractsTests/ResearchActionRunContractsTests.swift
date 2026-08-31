import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action Run boundary contracts")
struct ResearchActionRunContractsTests {
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
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContinuationLineage.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "grant")
        object["schema_version"] = 99
        #expect(throws: ResearchActionRunContractError.self) {
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

    @Test("Completion submissions contain no reading-history testimony")
    func completionOmitsReadingHistory() throws {
        let submission = ResearchActionRunCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            recordTitle: try ResearchRecordTitle("Bounded synthesis"),
            summary: "The synthesis addresses its declared question.",
            didModifyTarget: false
        )
        let data = try JSONEncoder().encode(submission)
        #expect(try JSONDecoder().decode(
            ResearchActionRunCompletionSubmission.self,
            from: data
        ) == submission)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["actuallyUsedMaterialNoteIDs"] == nil)
        #expect(object["contextUseReport"] == nil)
    }

    @Test("Action roles, write authority, change evidence, and Fidelity requirements are explicit")
    func actionRoleMatrix() {
        #expect(ResearchActionID.analyze.allowedTargetRoles == [.analysis])
        #expect(ResearchActionID.synthesize.allowedTargetRoles == [.topic])
        #expect(ResearchActionID.critique.allowedTargetRoles == [.work])
        #expect(ResearchActionID.write.allowedTargetRoles == [.work])
        #expect(ResearchActionID.discuss.allowedTargetRoles == Set(ResearchActionTargetRole.allCases))
        #expect(ResearchActionID.checkFidelity.allowedTargetRoles == Set(ResearchActionTargetRole.allCases))

        #expect(ResearchActionID.analyze.writesTarget)
        #expect(ResearchActionID.synthesize.writesTarget)
        #expect(ResearchActionID.write.writesTarget)
        #expect(!ResearchActionID.discuss.writesTarget)
        #expect(!ResearchActionID.checkFidelity.writesTarget)
        #expect(!ResearchActionID.critique.writesTarget)

        #expect(ResearchActionID.analyze.requiresAgentChangeEvidence)
        #expect(ResearchActionID.synthesize.requiresAgentChangeEvidence)
        #expect(ResearchActionID.write.requiresAgentChangeEvidence)
        #expect(!ResearchActionID.critique.requiresAgentChangeEvidence)
        #expect(!ResearchActionID.discuss.requiresAgentChangeEvidence)
        #expect(!ResearchActionID.checkFidelity.requiresAgentChangeEvidence)
    }

    @Test("Requests reject duplicate Targets, invalid scopes, checks, and roles")
    func requestValidation() throws {
        let analysis = target(role: .analysis)
        let work = target(role: .work)
        let material = ResearchActionNoteSnapshot(
            noteID: analysis.noteID,
            note: analysis.note,
            role: analysis.role,
            fingerprint: analysis.fingerprint,
            title: analysis.title
        )
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .analyze,
                target: analysis,
                materials: [material]
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .analyze,
                target: work
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .analyze,
                target: analysis,
                scope: ResearchActionScope(kind: .passage)
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .analyze,
                target: analysis,
                checks: [.content]
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .checkFidelity,
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
        try ResearchActionRunRequest(
            actionID: .analyze,
            target: analysis,
            scope: .passage(anchor)
        ).validate()
    }

    @Test("Run snapshots reject contradictory request identity on construction and decode")
    func runSnapshotIdentityIsSingular() throws {
        let analysis = target(role: .analysis)
        let valid = try snapshot(
            target: analysis,
            scope: .whole,
            method: try method()
        )
        let contradictory = ResearchActionRunRequest(
            actionID: .analyze,
            target: analysis
        )
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try ResearchActionRunSnapshot(
                request: contradictory,
                actionSnapshot: valid.actionSnapshot
            )
        }

        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid))
                as? [String: Any]
        )
        var request = try #require(object["request"] as? [String: Any])
        request["actionID"] = ResearchActionID.analyze.rawValue
        request.removeValue(forKey: "checks")
        object["request"] = request
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionRunSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let differentTargetRequest = ResearchActionRunRequest(
            actionID: .checkFidelity,
            target: target(role: .analysis),
            checks: [.content]
        )
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try ResearchActionRunSnapshot(
                request: differentTargetRequest,
                actionSnapshot: valid.actionSnapshot
            )
        }
        object["request"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(differentTargetRequest)
        )
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionRunSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Retired conditional-resource fields fail closed")
    func retiredConditionalResourceFieldsAreRejected() throws {
        let target = target(role: .analysis)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var retired = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchActionRunRequest(
                    actionID: .analyze,
                    target: target
                ))
            ) as? [String: Any]
        )
        retired["conditional_resources"] = ["development_synthesis"]
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try decoder.decode(
                ResearchActionRunRequest.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
    }

    @Test("Retired snapshot fields fail closed")
    func retiredSnapshotFieldsAreRejected() throws {
        let encoder = JSONEncoder()
        var retired = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(try snapshot(
                    target: target(role: .analysis),
                    scope: nil,
                    method: method()
                ))
            ) as? [String: Any]
        )
        retired["recordKind"] = "function_envelope"
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionRunSnapshot.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
        retired.removeValue(forKey: "recordKind")
        retired["requiredChildFunctions"] = []
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionRunSnapshot.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }
    }

    @Test("Discuss module selection is ordered and request scoped")
    func discussResponseModuleSelection() throws {
        let analysis = target(role: .analysis)
        let selected = ResearchActionRunRequest(
            actionID: .discuss,
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

        let academicOutcomeOnly = ResearchActionRunRequest(
            actionID: .discuss,
            target: analysis,
            instruction: "State the bounded academic outcome.",
            dialogueResponseModules: []
        )
        #expect(academicOutcomeOnly.dialogueResponseModules == [])
        try academicOutcomeOnly.validate()

        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .discuss,
                target: analysis,
                instruction: "State the bounded academic outcome.",
                dialogueResponseModules: [
                    .remainingQuestions,
                    .remainingQuestions,
                ]
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try ResearchActionRunRequest(
                actionID: .analyze,
                target: analysis,
                dialogueResponseModules: []
            ).validate()
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let roundTrip = try decoder.decode(
            ResearchActionRunRequest.self,
            from: encoder.encode(selected)
        )
        #expect(roundTrip.dialogueResponseModules == selected.dialogueResponseModules)

        let defaultData = try JSONSerialization.data(withJSONObject: [
            "actionID": "discuss",
            "target": try JSONSerialization.jsonObject(with: encoder.encode(analysis)),
            "materials": [],
            "instruction": "State the bounded academic outcome.",
            "checks": [],
        ])
        let defaults = try decoder.decode(ResearchActionRunRequest.self, from: defaultData)
        #expect(defaults.dialogueResponseModules == nil)
    }

    @Test("Retired Comment evidence fields fail closed")
    func retiredCommentEvidenceFieldsAreRejected() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var request = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(ResearchActionRunRequest(
                    actionID: .analyze,
                    target: target(role: .analysis)
                ))
            ) as? [String: Any]
        )
        request["commentIDs"] = []
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try decoder.decode(
                ResearchActionRunRequest.self,
                from: JSONSerialization.data(withJSONObject: request)
            )
        }

        var snapshot = try #require(
            JSONSerialization.jsonObject(
                with: encoder.encode(try snapshot(
                    target: target(role: .analysis),
                    scope: nil,
                    method: method()
                ))
            ) as? [String: Any]
        )
        snapshot["evidenceRevisions"] = []
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try decoder.decode(
                ResearchActionRunSnapshot.self,
                from: JSONSerialization.data(withJSONObject: snapshot)
            )
        }
    }

    @Test("Unsupported Dialogue identifiers are rejected instead of projected")
    func unsupportedDialogueIdentifiersAreRejected() throws {
        let data = Data("\"dialogue\"".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchActionID.self, from: data)
        }
    }

    @Test("Retired write-scope fields fail closed while shared Fidelity targets remain typed")
    func retiredWriteScopeFieldsAreRejected() throws {
        let analysis = target(role: .analysis)
        let topic = target(role: .topic)
        let write = ResearchActionRunRequest(
            actionID: .analyze,
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
        #expect(throws: ResearchActionRunContractError.self) {
            _ = try decoder.decode(
                ResearchActionRunRequest.self,
                from: JSONSerialization.data(withJSONObject: retired)
            )
        }

        let fidelity = ResearchActionRunRequest(
            actionID: .checkFidelity,
            target: analysis,
            checks: [.content, .citations],
            fidelityTargets: [topic, analysis]
        )
        try fidelity.validate()
        let storedFidelity = try decoder.decode(
            ResearchActionRunRequest.self,
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
        let material = ResearchActionNoteSnapshot(
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
        let candidate = ResearchActionMaterialCandidate(
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
            ResearchActionMaterialCandidate.self,
            from: encoder.encode(candidate)
        ) == candidate)

    }

    @Test("Fidelity evidence identity is Run-local and changes with source or scope")
    func fidelityEvidenceIdentity() throws {
        let target = target(role: .analysis)
        let runID = UUID()
        let anchor = CommentAnchor(
            fingerprint: target.fingerprint,
            utf8Range: 0..<5,
            utf16Range: 0..<5,
            line: 1,
            endLine: 1,
            quotation: "claim"
        )
        let exactMethod = try method()
        let whole = try snapshot(
            target: target,
            scope: .whole,
            method: exactMethod,
            runID: runID
        )
        let implicitWhole = try snapshot(
            target: target,
            scope: nil,
            method: exactMethod,
            runID: runID
        )
        let passage = try snapshot(
            target: target,
            scope: .passage(anchor),
            method: exactMethod,
            runID: runID
        )
        let anotherRun = try snapshot(
            target: target,
            scope: .whole,
            method: exactMethod
        )
        let changedCitationStyle = try snapshot(
            target: target,
            scope: .whole,
            method: exactMethod,
            citationStyle: "chicago-author-date",
            runID: runID
        )
        let makeKey: (ResearchActionRunSnapshot) -> ResearchFidelityEvidenceKey = {
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
        #expect(makeKey(whole) != makeKey(anotherRun))
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
        #expect(throws: ResearchActionRunContractError.self) {
            try FidelityCheckOutcome(
                check: .content,
                state: .passed,
                summary: "Contradictory.",
                findings: ["An unresolved problem"]
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try FidelityCheckOutcome(
                check: .citations,
                state: .issuesFound,
                summary: "A problem exists."
            ).validate()
        }
        #expect(throws: ResearchActionRunContractError.self) {
            try FidelityCheckOutcome(
                check: .content,
                state: .unavailable,
                summary: " "
            ).validate()
        }
    }


    private func target(role: ResearchActionTargetRole) -> ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Target.md"),
            role: role,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Target"
        )
    }

    private func snapshot(
        target: ResearchActionNoteSnapshot,
        scope: ResearchActionScope?,
        method: ResearchSkillBindingSnapshot,
        citationStyle: String? = "apa-7",
        runID: UUID = UUID()
    ) throws -> ResearchActionRunSnapshot {
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
        return try ResearchActionRunSnapshot(
            runID: runID,
            request: ResearchActionRunRequest(
                actionID: .checkFidelity,
                target: target,
                scope: scope,
                checks: [.content]
            ),
            actionSnapshot: action,
            citationStyle: citationStyle
        )
    }

    private func method() throws -> ResearchSkillBindingSnapshot {
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(
                    uuidString: "00000000-0000-4000-8000-000000000050"
                )!
            ),
            actionID: .checkFidelity,
            displayName: "Content Fidelity",
            skillFolder: .machineLocal()
        )
        return try ResearchSkillBindingSnapshot(
            registration: registration,
            registrationRevision: DocumentFingerprint(content: "registrations"),
            skillFolderPath: "/Users/researcher/Skills/content-fidelity",
            skillFolderIsAvailable: true
        )
    }

    private func suggestionReason(
        _ kind: ResearchActionMaterialSuggestionReason.Kind,
        source: VaultQualifiedNoteID,
        lowerBound: Int
    ) -> ResearchActionMaterialSuggestionReason {
        ResearchActionMaterialSuggestionReason(
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
