import Foundation
import ScholiumContracts
import Testing

@Suite("Phase-one Research Skill ownership contracts")
struct PhaseOneOwnershipContractsTests {
    @Test("Authenticated Run context rejects retired schemas and undeclared authority")
    func authenticatedRunContextCleanCutover() {
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAuthenticatedRunContext.self,
                from: Data("{\"schema_version\":3}".utf8)
            )
        }
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAuthenticatedRunContext.self,
                from: Data(
                    "{\"schema_version\":4,\"blanket_write\":true}".utf8
                )
            )
        }
    }

    @Test("One Action has one opaque registration without package or version semantics")
    func registrationIsOneActionRelation() throws {
        let analyze = try ResearchSkillRegistration(
            actionID: .analyze,
            displayName: "Analyze Philosophical Source",
            primaryMarkdown: .triptychControl("methods/analyze.md")
        )
        let document = try ResearchSkillRegistrationDocument(registrations: [analyze])
        #expect(document.registration(for: .analyze) == analyze)
        #expect(document.registration(for: .write) == nil)

        #expect(throws: ResearchSkillRegistrationError.self) {
            _ = try ResearchSkillRegistrationDocument(registrations: [
                analyze,
                ResearchSkillRegistration(
                    actionID: .analyze,
                    displayName: "Competing Analyzer",
                    primaryMarkdown: .triptychControl("methods/other-analyze.md")
                ),
            ])
        }

        let encoded = try JSONEncoder().encode(document)
        let text = String(decoding: encoded, as: UTF8.self)
        for forbidden in [
            "\"package\"", "\"version\"", "\"digest\"", "\"dependency\"",
            "\"capabilities\"", "\"updatePolicy\"", "\"history\"",
        ] {
            #expect(!text.contains(forbidden))
        }
        #expect(try JSONDecoder().decode(
            ResearchSkillRegistrationDocument.self,
            from: encoded
        ) == document)
    }

    @Test("Portable registration stores no machine-local path")
    func ordinaryFolderBoundary() throws {
        let registration = try ResearchSkillRegistration(
            actionID: .write,
            displayName: "Write",
            primaryMarkdown: .machineLocal(),
            skillFolder: .machineLocal()
        )
        #expect(registration.primaryMarkdown.kind == .machineLocal)
        #expect(registration.skillFolder?.kind == .machineLocal)
        let encoded = try JSONEncoder().encode(registration)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("/tmp/"))

        #expect(throws: ResearchSkillRegistrationError.self) {
            _ = try ResearchSkillRegistration(
                actionID: .write,
                displayName: "Escaped",
                primaryMarkdown: .triptychControl("skill-folders/write/SKILL.md"),
                skillFolder: .machineLocal()
            )
        }
        #expect(throws: ResearchSkillRegistrationError.self) {
            _ = try ResearchMethodFileLocation.triptychControl("../outside.md")
        }
        #expect(throws: ResearchSkillRegistrationError.self) {
            _ = try JSONDecoder().decode(
                ResearchSkillRegistrationDocument.self,
                from: Data(#"{"schemaVersion":1,"registrations":[]}"#.utf8)
            )
        }
    }

    @Test("Academic Profile has only flat academic fields and freezes one Result Contract")
    func academicProfileAndResultContract() throws {
        let outcome = try ResearchAcademicFieldDefinition.freeText(
            id: .academicOutcome,
            label: "Academic Outcome",
            helpText: "Give the source-grounded academic result and important limits.",
            requirement: .required
        )
        let profile = try ResearchAcademicActionProfile(
            actionID: .analyze,
            displayName: "Analyze Note",
            order: 10,
            isEnabled: true,
            applicableRoles: [.analysis],
            academicInputFields: [],
            academicResultFields: [outcome]
        )
        let definition = try #require(PlatformActionCatalog.definition(for: .analyze))
        try definition.validate(profile: profile)
        let result = try ResearchResultContract(
            profile: profile,
            registrationKey: ResearchSkillRegistrationKey(),
            profileRevision: DocumentFingerprint(content: "profile bytes")
        )
        #expect(result.academicFields.map(\.fieldID) == [.academicOutcome])
        #expect(result.machineFields == ResearchMachineResultFieldID.allCases)
        #expect(result.machineFields.allSatisfy { _ in true })
        #expect(result.machineFields.contains { $0.purpose == .safetyAndRecovery })
        #expect(result.machineFields.contains { $0.purpose == .researchContinuity })

        let profileJSON = String(
            decoding: try JSONEncoder().encode(profile),
            as: UTF8.self
        )
        for forbidden in [
            "capabilities", "sourceRequirement", "writeOperations",
            "editablePropertyKeys", "permission", "package",
        ] {
            #expect(!profileJSON.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test("Platform definitions reject a Profile that widens hard role support")
    func platformBoundaryCannotBeWidened() throws {
        let outcome = try ResearchAcademicFieldDefinition.freeText(
            id: .academicOutcome,
            label: "Academic Outcome",
            requirement: .optional
        )
        let invalid = try ResearchAcademicActionProfile(
            actionID: .analyze,
            displayName: "Analyze",
            order: 0,
            isEnabled: true,
            applicableRoles: [.analysis, .work],
            academicInputFields: [],
            academicResultFields: [outcome]
        )
        let definition = try #require(PlatformActionCatalog.definition(for: .analyze))
        #expect(throws: PlatformActionContractError.self) {
            try definition.validate(profile: invalid)
        }
    }

    @Test("Triptych collaboration is one policy without Skill overrides or digests")
    func oneCollaborationPolicy() throws {
        let triptychID = UUID()
        let document = ResearchCollaborationPolicyDocument(
            triptychID: triptychID,
            policy: .askOnlyForWorks
        )
        let encoded = try JSONEncoder().encode(document)
        let json = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(json.keys) == ["schemaVersion", "triptychID", "policy"])

        let initial = try ResearchCollaborationRequest(
            kind: .initialAction,
            requestedWritableRoles: [.analysis]
        )
        #expect(ResearchCollaborationPolicyResolver.evaluate(
            policy: .askEveryTime,
            request: initial
        ) == .initialObjectAuthorized)

        let topicExtension = try ResearchCollaborationRequest(
            kind: .writeSetExtension,
            requestedWritableRoles: [.topic]
        )
        let workExtension = try ResearchCollaborationRequest(
            kind: .writeSetExtension,
            requestedWritableRoles: [.work]
        )
        #expect(ResearchCollaborationPolicyResolver.evaluate(
            policy: .askOnlyForWorks,
            request: topicExtension
        ) == .mayProceed)
        #expect(ResearchCollaborationPolicyResolver.evaluate(
            policy: .askOnlyForWorks,
            request: workExtension
        ) == .requiresResearcherDecision)
    }
}
