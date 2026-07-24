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
        let snapshot = try ResearchActionSnapshot(
            definition: .analyze,
            targetRole: .analysis
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let encoded = String(decoding: data, as: UTF8.self)

        #expect(encoded == #"{"action_id":"analyze","execution_kind":"analysis","schema_version":1,"target_role":"analysis"}"#)
        #expect(try JSONDecoder().decode(ResearchActionSnapshot.self, from: data) == snapshot)
    }

    @Test("Unknown snapshot versions and execution kinds fail closed")
    func unknownSchemaAndKind() {
        let unknownVersion = Data(
            #"{"schema_version":2,"action_id":"analyze","execution_kind":"analysis","target_role":"analysis"}"#.utf8
        )
        #expect(throws: ResearchActionContractError.self) {
            try JSONDecoder().decode(ResearchActionSnapshot.self, from: unknownVersion)
        }

        let internalFunctionName = Data(
            #"{"schema_version":1,"action_id":"analyze","execution_kind":"develop","target_role":"analysis"}"#.utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResearchActionSnapshot.self, from: internalFunctionName)
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
            try ResearchActionSnapshot(definition: .analyze, targetRole: .topic)
        }

        let mismatchedRole = Data(
            #"{"schema_version":1,"action_id":"write","execution_kind":"writing","target_role":"analysis"}"#.utf8
        )
        #expect(throws: ResearchActionContractError.self) {
            try JSONDecoder().decode(ResearchActionSnapshot.self, from: mismatchedRole)
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
        let snapshot = try ResearchActionSnapshot(
            definition: definition,
            targetRole: .topic
        )
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
        let snapshot = try ResearchActionSnapshot(
            definition: .analyze,
            targetRole: .analysis
        )
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
            try ResearchActionSnapshot(definition: .analyze, targetRole: .analysis),
            try ResearchActionSnapshot(definition: .synthesize, targetRole: .topic),
            try ResearchActionSnapshot(definition: .write, targetRole: .work),
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
}
