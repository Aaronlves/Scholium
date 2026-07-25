import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action contracts")
struct ResearchActionContractsTests {
    @Test("Default Actions retain their role-specific order")
    func defaultRoleMatrix() {
        #expect(ResearchActionDefinition.defaultDefinitions(for: .analysis).map(\.id) == [
            .discuss,
            .analyze,
            .checkFidelity,
        ])
        #expect(ResearchActionDefinition.defaultDefinitions(for: .topic).map(\.id) == [
            .discuss,
            .synthesize,
            .checkFidelity,
        ])
        #expect(ResearchActionDefinition.defaultDefinitions(for: .work).map(\.id) == [
            .discuss,
            .write,
            .critique,
            .checkFidelity,
        ])
        #expect(!ResearchActionDefinition.defaultDefinitions.contains(.manuscript))
        #expect(ResearchActionDefinition.manuscript.allowedTargetRoles == [.work])
    }

    @Test("Action snapshots round trip through one explicit public schema")
    func snapshotRoundTrip() throws {
        let snapshot = try makeSnapshot(definition: .analyze, role: .analysis)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let encoded = String(decoding: data, as: UTF8.self)

        #expect(encoded.contains(#""schema_version":2"#))
        #expect(encoded.contains(#""action_id":"analyze""#))
        #expect(encoded.contains(#""profile_revision""#))
        #expect(encoded.contains(#""package_revision""#))
        #expect(encoded.contains(#""readable_notes""#))
        #expect(try JSONDecoder().decode(ResearchActionSnapshot.self, from: data) == snapshot)
    }

    @Test("Unknown snapshot versions and execution kinds fail closed")
    func unknownSchemaAndKind() {
        let unknownVersion = Data(
            #"{"schema_version":3,"action_id":"analyze","execution_kind":"analysis"}"#.utf8
        )
        #expect(throws: ResearchActionContractError.self) {
            try JSONDecoder().decode(ResearchActionSnapshot.self, from: unknownVersion)
        }

        let internalFunctionName = Data(
            #"{"schema_version":2,"action_id":"analyze","execution_kind":"develop"}"#.utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchActionSnapshot.self, from: internalFunctionName)
        }
    }

    @Test("Action snapshots reject unknown nested fields and duplicate resources")
    func snapshotStructureFailsClosed() throws {
        let snapshot = try makeSnapshot(definition: .analyze, role: .analysis)
        let data = try JSONEncoder().encode(snapshot)
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        root["unknown"] = true
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        }
        root.removeValue(forKey: "unknown")

        var target = try #require(root["target"] as? [String: Any])
        target["unknown"] = true
        root["target"] = target
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        }
        target.removeValue(forKey: "unknown")
        root["target"] = target

        var method = try #require(root["method"] as? [String: Any])
        let resources = try #require(method["loaded_resources"] as? [[String: Any]])
        method["loaded_resources"] = resources + resources
        root["method"] = method
        #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchActionSnapshot.self,
                from: JSONSerialization.data(withJSONObject: root)
            )
        }
    }

    @Test("Reserved identities and Target roles cannot acquire different semantics")
    func reservedIdentityAndRoleValidation() throws {
        let mismatchedIdentity = Data(
            #"{"action_id":"analyze","execution_kind":"synthesis"}"#.utf8
        )
        #expect(throws: ResearchActionContractError.self) {
            try JSONDecoder().decode(
                ResearchActionDefinition.self,
                from: mismatchedIdentity
            )
        }
        #expect(throws: ResearchActionContractError.self) {
            let valid = try makeSnapshot(definition: .analyze, role: .analysis)
            let topicTarget = note(role: .topic)
            _ = try ResearchActionSnapshot(
                definition: .analyze,
                target: topicTarget,
                method: valid.method,
                resolvedProfile: valid.resolvedProfile,
                parameters: valid.parameters,
                authority: try ResearchAuthorityEnvelope(
                    readableNotes: [topicTarget],
                    writableNotes: [],
                    writeOperations: [],
                    editablePropertyKeys: []
                )
            )
        }
    }

    @Test("Researcher Action identities are bounded and remain versioned values")
    func researcherActionIdentity() throws {
        let identifier = try #require(
            ResearchActionID(researcherOwnedRawValue: "counterexample-stress-test")
        )
        let definition = try ResearchActionDefinition(
            researcherOwnedID: identifier,
            executionKind: .discussion
        )
        let snapshot = try makeSnapshot(definition: definition, role: .topic)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(ResearchActionSnapshot.self, from: data) == snapshot)

        for invalid in [
            "",
            "Uppercase",
            "contains_underscore",
            "-leading",
            "trailing-",
            "double--hyphen",
            "develop",
            "fidelity",
            "revise",
            "哲学",
            String(repeating: "a", count: 65),
        ] {
            #expect(ResearchActionID(rawValue: invalid) == nil)
            #expect(ResearchActionID(researcherOwnedRawValue: invalid) == nil)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    ResearchActionID.self,
                    from: Data("\"\(invalid)\"".utf8)
                )
            }
        }
    }

    @Test("Researcher-owned identities cannot collide with bundled Actions")
    func researcherIdentityCollision() {
        let bundledIDs: [ResearchActionID] = [
            .discuss,
            .analyze,
            .synthesize,
            .write,
            .critique,
            .checkFidelity,
            .manuscript,
        ]

        for identifier in bundledIDs {
            #expect(identifier.isReservedForBundledAction)
            #expect(ResearchActionID(rawValue: identifier.rawValue) == identifier)
            #expect(ResearchActionID(
                researcherOwnedRawValue: identifier.rawValue
            ) == nil)
        }

        #expect(throws: ResearchActionContractError.self) {
            try ResearchActionDefinition(
                researcherOwnedID: .analyze,
                executionKind: .analysis
            )
        }
    }

    @Test("Research Records project only versioned Action identity")
    func recordIdentity() throws {
        let snapshot = try makeSnapshot(definition: .analyze, role: .analysis)
        let identity = ResearchActionRecordIdentity(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(identity)
        let encoded = String(decoding: data, as: UTF8.self)

        #expect(encoded == #"{"action_id":"analyze","schema_version":1}"#)
        #expect(try JSONDecoder().decode(
            ResearchActionRecordIdentity.self,
            from: data
        ) == identity)
        #expect(!encoded.contains("execution_kind"))
        #expect(!encoded.contains("target_role"))
        #expect(!encoded.contains("function"))

        let unknownVersion = Data(
            #"{"schema_version":2,"action_id":"analyze"}"#.utf8
        )
        #expect(throws: ResearchActionContractError.self) {
            try JSONDecoder().decode(
                ResearchActionRecordIdentity.self,
                from: unknownVersion
            )
        }
    }

    @Test("Public Action snapshots never encode internal Function vocabulary")
    func internalFunctionNamesDoNotLeak() throws {
        let snapshots = [
            try makeSnapshot(definition: .analyze, role: .analysis),
            try makeSnapshot(definition: .synthesize, role: .topic),
            try makeSnapshot(definition: .write, role: .work),
        ]

        for snapshot in snapshots {
            let encoded = String(
                decoding: try JSONEncoder().encode(snapshot),
                as: UTF8.self
            )
            #expect(!encoded.contains("\"function\""))
            #expect(!encoded.contains("develop"))
            #expect(!encoded.contains("revise"))
        }
    }

    private func makeSnapshot(
        definition: ResearchActionDefinition,
        role: ResearchActionTargetRole
    ) throws -> ResearchActionSnapshot {
        let target = note(role: role)
        let profile = try actionProfile(definition: definition, role: role)
        var values: [ResearchActionModuleID: ResearchActionParameterValue] = [:]
        if definition.executionKind == .analysis {
            values[ResearchActionModuleID(rawValue: "source")!] = .source(
                try sourceReference()
            )
        }
        let parameters = try ResearchActionParameterModel(
            profile: profile,
            values: values
        )
        let writes = definition.executionKind.maximumCandidateWritableRoles
            .contains(role)
        let authority = try ResearchAuthorityEnvelope(
            readableNotes: [target],
            writableNotes: writes ? [target] : [],
            writeOperations: writes ? [.modifyMarkdown] : [],
            editablePropertyKeys: []
        )
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            origin: .applicationDefault,
            profile: profile,
            profileRevision: profile.contentRevision(),
            profileDocumentRevision: nil
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchActionMethodSnapshot(
                packageID: "working-method",
                origin: .triptych,
                version: "1",
                packageRevision: DocumentFingerprint(content: "package"),
                loadedResources: [
                    ResearchActionResourceSnapshot(
                        relativePath: "SKILL.md",
                        revision: DocumentFingerprint(content: "method")
                    ),
                ]
            ),
            resolvedProfile: resolvedProfile,
            parameters: parameters,
            authority: authority
        )
    }

    private func actionProfile(
        definition: ResearchActionDefinition,
        role: ResearchActionTargetRole
    ) throws -> ResearchActionProfile {
        let sourceID = ResearchActionModuleID(rawValue: "source")!
        let modules: [ResearchActionModuleDefinition] = definition.executionKind == .analysis
            ? [try .sourceReference(id: sourceID, label: "Source", isRequired: true)]
            : []
        let writes = definition.executionKind.maximumCandidateWritableRoles
            .contains(role)
        return try ResearchActionProfile(
            definition: definition,
            buttonName: "Test Action",
            order: 0,
            applicableRoles: [role],
            showInActions: true,
            modules: modules,
            sourceRequirement: definition.executionKind == .analysis ? .required : .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [role],
                candidateWritableRoles: writes ? [role] : [],
                candidateWriteOperations: writes ? [.modifyMarkdown] : []
            ),
            feedbackRequirement: .none
        )
    }

    private func note(
        role: ResearchActionTargetRole
    ) -> ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                relativePath: "Target.md"
            ),
            role: role,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "target"),
            title: "Target"
        )
    }

    private func sourceReference() throws -> ResearchSourceReference {
        try ResearchSourceReference(
            identity: .localFile(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
            ),
            displayName: "Source.pdf",
            fingerprint: DocumentFingerprint(content: "source")
        )
    }
}
