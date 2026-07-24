import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Research Action compatibility mapping")
struct ResearchActionFunctionMappingTests {
    @Test("Every bundled Action maps to one protected Function")
    func fixedMapping() throws {
        let cases: [(ResearchActionDefinition, ResearchActionTargetRole, ResearchFunctionID)] = [
            (.discuss, .analysis, .discuss),
            (.analyze, .analysis, .develop),
            (.synthesize, .topic, .develop),
            (.write, .work, .revise),
            (.critique, .work, .critique),
            (.checkFidelity, .topic, .fidelity),
            (.manuscript, .work, .manuscript),
        ]

        for (definition, role, expectedFunction) in cases {
            #expect(try ResearchActionFunctionMapping.function(
                for: definition,
                targetRole: role
            ) == expectedFunction)
        }
    }

    @Test("Custom Actions inherit only their declared execution boundary")
    func customMapping() throws {
        let identifier = try #require(
            ResearchActionID(researcherOwnedRawValue: "reanalyze-with-counterexamples")
        )
        let definition = try ResearchActionDefinition(
            researcherOwnedID: identifier,
            executionKind: .analysis
        )

        #expect(try ResearchActionFunctionMapping.function(
            for: definition,
            targetRole: .analysis
        ) == .develop)
        #expect(throws: ResearchActionContractError.self) {
            try ResearchActionFunctionMapping.function(
                for: definition,
                targetRole: .topic
            )
        }
    }
}
