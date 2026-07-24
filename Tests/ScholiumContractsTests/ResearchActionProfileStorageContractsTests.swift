import Foundation
import ScholiumContracts
import Testing

@Suite("Research Action Profile storage contracts")
struct ResearchActionProfileStorageContractsTests {
    @Test("Profile bindings round-trip and retain deterministic order")
    func roundTripAndOrder() throws {
        let later = try binding(actionID: "counterexample-test", order: 8)
        let earlier = try binding(actionID: "compare-interpretations", order: 2)
        let document = try ResearchActionProfileDocument(actionBindings: [
            later.profile.actionID: later,
            earlier.profile.actionID: earlier,
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(document)
        let decoded = try JSONDecoder().decode(
            ResearchActionProfileDocument.self,
            from: data
        )

        #expect(decoded == document)
        #expect(decoded.orderedBindings.map(\.profile.actionID.rawValue) == [
            "compare-interpretations",
            "counterexample-test",
        ])
    }

    @Test("Storage rejects key mismatch, bundled replacement, and unknown fields")
    func failClosed() throws {
        let custom = try binding(actionID: "counterexample-test", order: 1)
        #expect(throws: ResearchActionProfileStorageError.self) {
            _ = try ResearchActionProfileDocument(actionBindings: [
                try #require(ResearchActionID(researcherOwnedRawValue: "different-action")): custom,
            ])
        }

        let bundled = try ResearchActionProfileBinding(
            packageID: "researcher-discuss",
            profile: ResearchActionProfile(
                definition: .discuss,
                buttonName: "Discuss Another Way",
                order: 1,
                applicableRoles: [.analysis],
                showInActions: true,
                modules: [],
                sourceRequirement: .none,
                capabilities: ResearchActionCapabilityDeclaration(
                    readableRoles: [.analysis]
                ),
                feedbackRequirement: .requested
            )
        )
        #expect(throws: ResearchActionProfileStorageError.self) {
            _ = try ResearchActionProfileDocument(actionBindings: [.discuss: bundled])
        }

        var object = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(
                try ResearchActionProfileDocument(actionBindings: [
                    custom.profile.actionID: custom,
                ])
            )
        ) as? [String: Any])
        object["executable"] = true
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ResearchActionProfileStorageError.self) {
            _ = try JSONDecoder().decode(ResearchActionProfileDocument.self, from: data)
        }
    }

    private func binding(
        actionID: String,
        order: Int
    ) throws -> ResearchActionProfileBinding {
        let id = try #require(ResearchActionID(researcherOwnedRawValue: actionID))
        let definition = try ResearchActionDefinition(
            researcherOwnedID: id,
            executionKind: .critique
        )
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: actionID.replacingOccurrences(of: "-", with: " ").capitalized,
            order: order,
            applicableRoles: [.work],
            showInActions: true,
            modules: [],
            sourceRequirement: .none,
            capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.work]),
            feedbackRequirement: .required
        )
        return try ResearchActionProfileBinding(
            packageID: "counterexample-method",
            profile: profile
        )
    }
}
