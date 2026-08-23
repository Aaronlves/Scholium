import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action contracts")
struct ResearchActionContractsTests {
    @Test("Default Actions retain their role-specific order")
    func defaultRoleMatrix() {
        #expect(ResearchActionDefinition.defaultDefinitions(for: .analysis).map(\.id) == [
            .discuss, .analyze, .checkFidelity,
        ])
        #expect(ResearchActionDefinition.defaultDefinitions(for: .topic).map(\.id) == [
            .discuss, .synthesize, .checkFidelity,
        ])
        #expect(ResearchActionDefinition.defaultDefinitions(for: .work).map(\.id) == [
            .discuss, .write, .critique, .checkFidelity,
        ])
        #expect(ResearchActionDefinition.defaultDefinitions.count == 6)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionID.self,
                from: Data(#""manuscript""#.utf8)
            )
        }
    }

    @Test("Action snapshots round trip through the clean current schema")
    func snapshotRoundTrip() throws {
        let snapshot = try makeSnapshot(definition: .analyze, role: .analysis)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let encoded = String(decoding: data, as: UTF8.self)

        #expect(encoded.contains(#""schema_version":3"#))
        #expect(encoded.contains(#""action_id":"analyze""#))
        #expect(encoded.contains(#""registration""#))
        #expect(encoded.contains(#""result_contract""#))
        #expect(encoded.contains(#""platform_inputs""#))
        #expect(!encoded.localizedCaseInsensitiveContains("package"))
        #expect(!encoded.contains("loaded_resources"))
        #expect(try JSONDecoder().decode(ResearchActionSnapshot.self, from: data) == snapshot)
    }

    @Test("Unknown snapshot versions, fields, and internal execution names fail closed")
    func strictSnapshotDecoding() throws {
        let snapshot = try makeSnapshot(definition: .checkFidelity, role: .analysis)
        let data = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["unknown"] = true
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unknown")
        object["schema_version"] = 2
        #expect(throws: ResearchActionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        let internalFunctionName = Data(
            #"{"action_id":"analyze","execution_kind":"develop"}"#.utf8
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionDefinition.self,
                from: internalFunctionName
            )
        }
        #expect(ResearchActionID(rawValue: "custom-research-action") == nil)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionDefinition.self,
                from: Data(
                    #"{"action_id":"custom-research-action","execution_kind":"analysis"}"#.utf8
                )
            )
        }
    }

    @Test("Reserved identities and Platform roles cannot acquire different semantics")
    func reservedIdentityAndRoleValidation() throws {
        #expect(throws: ResearchActionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionDefinition.self,
                from: Data(
                    #"{"action_id":"analyze","execution_kind":"synthesis"}"#.utf8
                )
            )
        }
        let valid = try makeSnapshot(definition: .analyze, role: .analysis)
        let topic = note(role: .topic)
        #expect(throws: ResearchActionContractError.self) {
            _ = try ResearchActionSnapshot(
                definition: .analyze,
                target: topic,
                method: valid.method,
                resolvedProfile: valid.resolvedProfile,
                platformInputs: valid.platformInputs,
                academicInputs: valid.academicInputs,
                resultContract: valid.resultContract,
                authority: ResearchAuthorityEnvelope(
                    readableNotes: [topic],
                    writableNotes: [],
                    writeOperations: [],
                    editableMetadataKeys: []
                )
            )
        }
    }

    @Test("A Profile cannot turn a read-only Platform Action into a write")
    func readOnlyPlatformCannotWrite() throws {
        let valid = try makeSnapshot(definition: .critique, role: .work)
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try ResearchActionSnapshot(
                definition: .critique,
                target: valid.target,
                method: valid.method,
                resolvedProfile: valid.resolvedProfile,
                platformInputs: valid.platformInputs,
                academicInputs: valid.academicInputs,
                resultContract: valid.resultContract,
                authority: ResearchAuthorityEnvelope(
                    readableNotes: [valid.target],
                    writableNotes: [valid.target],
                    writeOperations: [.modifyMarkdown],
                    editableMetadataKeys: []
                )
            )
        }
    }

    @Test("Portable Records project only the versioned public Action identity")
    func recordIdentity() throws {
        let identity = ResearchActionRecordIdentity(
            snapshot: try makeSnapshot(definition: .analyze, role: .analysis)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(identity)
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(encoded == #"{"action_id":"analyze","schema_version":1}"#)
        #expect(!encoded.contains("function"))
    }

    private func makeSnapshot(
        definition: ResearchActionDefinition,
        role: ResearchActionTargetRole
    ) throws -> ResearchActionSnapshot {
        let target = note(role: role)
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == definition.id
            }
        )
        let profileRevision = try profile.contentRevision()
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            profile: profile,
            profileRevision: profileRevision,
            profileDocumentRevision: DocumentFingerprint(content: "profiles")
        )
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(
                    uuidString: "33333333-3333-4333-8333-333333333333"
                )!
            ),
            actionID: definition.id,
            displayName: profile.displayName,
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# \(profile.displayName)\n\nExact method.\n",
            practices: []
        )
        let platformInputs = try ResearchActionPlatformInputs(
            fidelityChecks: definition.id == .checkFidelity ? [.content] : []
        )
        let academicInputs = try ResearchAcademicFieldValues(
            values: [:],
            definitions: profile.academicInputFields
        )
        let writes = PlatformActionCatalog.definition(for: definition.id)?
            .operations.contains(.modifyInitialNote) == true
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: method,
            resolvedProfile: resolvedProfile,
            platformInputs: platformInputs,
            academicInputs: academicInputs,
            resultContract: ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: profileRevision
            ),
            authority: ResearchAuthorityEnvelope(
                readableNotes: [target],
                writableNotes: writes ? [target] : [],
                writeOperations: writes ? [.modifyMarkdown] : [],
                editableMetadataKeys: []
            )
        )
    }

    private func note(role: ResearchActionTargetRole) -> ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                relativePath: "Target.md"
            ),
            role: role,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Target"
        )
    }
}
