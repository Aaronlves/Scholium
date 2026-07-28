import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action execution contracts")
struct ResearchActionExecutionContractsTests {
    @Test("Unified parameters validate every declared native value")
    func unifiedParameters() throws {
        let profile = try parameterProfile()
        let noteID = ResearchActionModuleID(rawValue: "focal-notes")!
        let textID = ResearchActionModuleID(rawValue: "question")!
        let toggleID = ResearchActionModuleID(rawValue: "preserve-pressure")!
        let choiceID = ResearchActionModuleID(rawValue: "lenses")!
        let model = try ResearchActionParameterModel(
            profile: profile,
            values: [
                noteID: .notes([note(role: .analysis, seed: "material")]),
                textID: .text("Test the strongest reply."),
                toggleID: .boolean(true),
                choiceID: .choices([
                    ResearchActionModuleChoiceValue(rawValue: "counterexample")!,
                ]),
            ]
        )

        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(
            ResearchActionParameterModel.self,
            from: data
        )
        #expect(decoded == model)
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionParameterModel(
                profile: profile,
                rawValues: ["unknown": .text("value")]
            )
        }
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionParameterModel(
                profile: profile,
                values: [textID: .boolean(true)]
            )
        }
    }

    @Test("Authority requires exact read and write identity equality")
    func exactAuthorityIntersection() throws {
        let readable = note(role: .topic, seed: "one")
        let changed = ResearchActionNoteSnapshot(
            noteID: readable.noteID,
            note: readable.note,
            role: readable.role,
            lifecycle: readable.lifecycle,
            fingerprint: DocumentFingerprint(content: "changed"),
            title: readable.title
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchAuthorityEnvelope(
                readableNotes: [readable],
                writableNotes: [changed],
                writeOperations: [.modifyMarkdown],
                editablePropertyKeys: []
            )
        }

        let envelope = try ResearchAuthorityEnvelope(
            readableNotes: [readable],
            writableNotes: [readable],
            writeOperations: [.modifyMarkdown],
            editablePropertyKeys: []
        )
        #expect(try JSONDecoder().decode(
            ResearchAuthorityEnvelope.self,
            from: JSONEncoder().encode(envelope)
        ) == envelope)
    }

    @Test("Preparation may defer only the required machine-local source value")
    func deferredRequiredSource() throws {
        let requestID = ResearchActionModuleID(rawValue: "request")!
        let sourceID = ResearchActionModuleID(rawValue: "source")!
        let profile = try ResearchActionProfile(
            definition: .analyze,
            buttonName: "Analyze",
            order: 10,
            applicableRoles: [.analysis],
            showInActions: true,
            modules: [
                try .boundedText(
                    id: requestID,
                    label: "Request",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 512,
                    allowsMultipleLines: true
                ),
                try .sourceReference(
                    id: sourceID,
                    label: "Source",
                    isRequired: true
                ),
            ],
            sourceRequirement: .required,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis],
                candidateWritableRoles: [.analysis],
                candidateWriteOperations: [.modifyMarkdown]
            ),
            feedbackRequirement: .requested
        )

        let deferred = try ResearchActionParameterModel(
            deferringRequiredSourceFor: profile,
            rawValues: [requestID.rawValue: .text("Reanalyze the source.")]
        )
        #expect(deferred.values[sourceID.rawValue] == nil)
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionParameterModel(
                profile: profile,
                rawValues: deferred.values
            )
        }
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionParameterModel(
                deferringRequiredSourceFor: profile
            )
        }
    }

    @Test("Profile snapshots reject a revision that does not describe the Profile")
    func exactProfileRevision() throws {
        let profile = try parameterProfile()
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionResolvedProfileSnapshot(
                origin: .applicationDefault,
                profile: profile,
                profileRevision: DocumentFingerprint(content: "different"),
                profileDocumentRevision: nil
            )
        }
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionResolvedProfileSnapshot(
                origin: .researcher,
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: nil
            )
        }
    }

    @Test("Action snapshots cannot exceed their resolved Profile envelope")
    func snapshotCannotExceedProfile() throws {
        let actionID = ResearchActionID(researcherOwnedRawValue: "bounded-discussion")!
        let definition = try ResearchActionDefinition(
            researcherOwnedID: actionID,
            executionKind: .discussion
        )
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: "Bounded Discussion",
            order: 10,
            applicableRoles: [.topic],
            showInActions: true,
            modules: [],
            sourceRequirement: .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [.topic]
            ),
            feedbackRequirement: .none
        )
        let target = note(role: .topic, seed: "target")
        let outOfProfileRead = ResearchActionNoteSnapshot(
            noteID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            note: VaultQualifiedNoteID(
                vaultID: target.note.vaultID,
                relativePath: "Analysis.md"
            ),
            role: .analysis,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "analysis"),
            title: "Analysis"
        )
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            origin: .researcher,
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: DocumentFingerprint(content: "profiles")
        )
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionSnapshot(
                definition: definition,
                target: target,
                method: try ResearchActionMethodSnapshot(
                    packageID: "bounded-discussion",
                    origin: .triptych,
                    version: "local",
                    packageRevision: DocumentFingerprint(content: "package"),
                    loadedResources: [ResearchActionResourceSnapshot(
                        relativePath: "SKILL.md",
                        revision: DocumentFingerprint(content: "method")
                    )]
                ),
                resolvedProfile: resolvedProfile,
                parameters: try ResearchActionParameterModel(profile: profile),
                authority: try ResearchAuthorityEnvelope(
                    readableNotes: [target, outOfProfileRead],
                    writableNotes: [],
                    writeOperations: [],
                    editablePropertyKeys: []
                )
            )
        }
    }

    @Test("Public Action mutation inputs reject unknown fields")
    func publicMutationInputsFailClosed() throws {
        let target = note(role: .work, seed: "target")
        let request = ResearchActionExecutionRequest(
            actionID: .write,
            expectedExecutionKind: .writing,
            expectedProfileRevision: DocumentFingerprint(content: "profile"),
            expectedProfileDocumentRevision: nil,
            target: target
        )
        let completion = ResearchActionCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            finalTargetFingerprint: target.fingerprint,
            summary: "No change.",
            didModifyTarget: false
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        var requestObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        )
        requestObject["unsupported"] = true
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try decoder.decode(
                ResearchActionExecutionRequest.self,
                from: JSONSerialization.data(withJSONObject: requestObject)
            )
        }

        var completionObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(completion))
                as? [String: Any]
        )
        completionObject["unsupported"] = true
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try decoder.decode(
                ResearchActionCompletionSubmission.self,
                from: JSONSerialization.data(withJSONObject: completionObject)
            )
        }

        completionObject.removeValue(forKey: "unsupported")
        completionObject.removeValue(forKey: "actuallyUsedMaterialNoteIDs")
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(
                ResearchActionCompletionSubmission.self,
                from: JSONSerialization.data(withJSONObject: completionObject)
            )
        }
    }

    private func parameterProfile() throws -> ResearchActionProfile {
        let actionID = ResearchActionID(researcherOwnedRawValue: "stress-test")!
        let definition = try ResearchActionDefinition(
            researcherOwnedID: actionID,
            executionKind: .discussion
        )
        let counterexample = try ResearchActionModuleChoice(
            value: ResearchActionModuleChoiceValue(rawValue: "counterexample")!,
            label: "Counterexample"
        )
        let strongestReply = try ResearchActionModuleChoice(
            value: ResearchActionModuleChoiceValue(rawValue: "strongest-reply")!,
            label: "Strongest Reply"
        )
        return try ResearchActionProfile(
            definition: definition,
            buttonName: "Stress Test",
            order: 20,
            applicableRoles: [.topic],
            showInActions: true,
            modules: [
                try .notePicker(
                    id: ResearchActionModuleID(rawValue: "focal-notes")!,
                    label: "Focal Notes",
                    isRequired: false,
                    roleScope: [.analysis, .topic],
                    maximumSelectionCount: 2
                ),
                try .boundedText(
                    id: ResearchActionModuleID(rawValue: "question")!,
                    label: "Question",
                    isRequired: true,
                    maximumTextUTF8ByteCount: 512,
                    allowsMultipleLines: true
                ),
                try .boolean(
                    id: ResearchActionModuleID(rawValue: "preserve-pressure")!,
                    label: "Preserve Pressure",
                    isRequired: false,
                    defaultValue: true
                ),
                try .enumeration(
                    id: ResearchActionModuleID(rawValue: "lenses")!,
                    label: "Lenses",
                    isRequired: true,
                    choices: [counterexample, strongestReply],
                    maximumSelectionCount: 2
                ),
            ],
            sourceRequirement: .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis, .topic]
            ),
            feedbackRequirement: .requested
        )
    }

    private func note(
        role: ResearchActionTargetRole,
        seed: String
    ) -> ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                relativePath: "\(seed).md"
            ),
            role: role,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: seed),
            title: seed
        )
    }
}
