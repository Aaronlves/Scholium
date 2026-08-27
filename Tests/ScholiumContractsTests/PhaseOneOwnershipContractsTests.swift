import Foundation
import ScholiumContracts
import Testing

@Suite("Phase-one Research Skill ownership contracts")
struct PhaseOneOwnershipContractsTests {
    @Test("Recommended Reading is a strict non-source directory")
    func recommendedReadingDirectoryContract() throws {
        let candidate = try ResearchRecommendedReadingCandidate(
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Value.md"
            ),
            role: .analysis,
            title: "Value Analysis",
            fingerprint: DocumentFingerprint(content: "# Value\n"),
            reasons: [.lexicalOverlap(RelatedContentLexicalReason(
                matchedFields: [.title, .body],
                seedMatches: [RelatedContentSeedTermMatch(
                    seedKind: .sourceNote,
                    terms: ["value"]
                )]
            ))]
        )
        let directory = try ResearchRecommendedReadingDirectory(
            seedFingerprint: DocumentFingerprint(content: "# Work\nValue"),
            freshnessToken: SearchFreshnessToken("triptych:test:1"),
            state: .current,
            candidates: [candidate],
            hasMore: false
        )
        let encoded = try JSONEncoder().encode(directory)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("# Value"))
        #expect(!text.contains("summary"))
        #expect(!text.contains("score"))
        #expect(try JSONDecoder().decode(
            ResearchRecommendedReadingDirectory.self,
            from: encoded
        ) == directory)

        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try ResearchRecommendedReadingDirectory(
                seedFingerprint: directory.seedFingerprint,
                freshnessToken: directory.freshnessToken,
                state: .current,
                candidates: [],
                hasMore: false
            )
        }
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["candidate_source"] = "forbidden"
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchRecommendedReadingDirectory.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Related Notes is a strict dynamically ordered non-source result")
    func relatedNotesResultContract() throws {
        let seed = try ResearchRelatedNotesResolvedSeed(
            inputName: "Agency",
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Agency.md"
            ),
            role: .topic,
            title: "Agency",
            fingerprint: DocumentFingerprint(content: "# Agency\n")
        )
        let candidate = try ResearchRelatedNotesCandidate(
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analysis.md"
            ),
            role: .analysis,
            title: "Analysis",
            fingerprint: DocumentFingerprint(content: "# Analysis\n"),
            matches: [try ResearchRelatedNotesSeedMatch(
                seed: seed,
                reasons: [.identityMention(
                    RelatedContentIdentityMentionReason(mentions: [
                        RelatedContentIdentityMention(
                            seedKind: .sourceNote,
                            identityKind: .title,
                            matchedIdentity: "Analysis",
                            seedField: .body
                        ),
                    ])
                )]
            )]
        )
        let result = try ResearchRelatedNotesResult(
            state: .current,
            resolvedSeeds: [seed],
            unresolvedNames: [],
            candidates: [candidate],
            hasMore: false
        )
        let encoded = try JSONEncoder().encode(result)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("# Analysis"))
        #expect(!text.contains("score"))
        #expect(try JSONDecoder().decode(
            ResearchRelatedNotesResult.self,
            from: encoded
        ) == result)

        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["candidate_source"] = "forbidden"
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchRelatedNotesResult.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        #expect(throws: ResearchContextContractError.self) {
            _ = try ResearchContextClause(
                kind: .relatedNotes,
                noteNames: ["Agency", "agency"],
                useEligibility: .referenceOnly
            )
        }
    }

    @Test("Authenticated Run context rejects retired schemas and undeclared authority")
    func authenticatedRunContextCleanCutover() {
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAuthenticatedRunContext.self,
                from: Data("{\"schema_version\":5}".utf8)
            )
        }
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAuthenticatedRunContext.self,
                from: Data(
                    "{\"schema_version\":6,\"blanket_write\":true}".utf8
                )
            )
        }
    }

    @Test("A required System Skill is strict identity data without authority fields")
    func requiredSystemSkillContract() throws {
        let requirement = try ResearchRequiredSkill.systemAdapter(
            .zoteroIntegration
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(requirement)
        let encodedText = String(decoding: encoded, as: UTF8.self)
        #expect(!encodedText.contains("capabilities"))
        #expect(!encodedText.contains("permission"))
        #expect(!encodedText.contains("write_authority"))
        #expect(try JSONDecoder().decode(
            ResearchRequiredSkill.self,
            from: encoded
        ) == requirement)

        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["library_write"] = true
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchRequiredSkill.self,
                from: JSONSerialization.data(withJSONObject: object)
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
            "editableMetadataKeys", "permission", "package",
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
