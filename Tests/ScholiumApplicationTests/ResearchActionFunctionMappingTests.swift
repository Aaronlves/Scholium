import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Research Action protected-function mapping")
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
        ]

        for (definition, role, expectedFunction) in cases {
            #expect(try ResearchActionFunctionMapping.function(
                for: definition,
                targetRole: role
            ) == expectedFunction)
        }
    }

    @Test("The protected Function coordinator recovers the exact Platform Action from Target role")
    func reverseMapping() throws {
        let cases: [(ResearchFunctionID, ResearchFunctionTargetRole, ResearchActionID)] = [
            (.discuss, .work, .discuss),
            (.develop, .analysis, .analyze),
            (.develop, .topic, .synthesize),
            (.revise, .work, .write),
            (.critique, .work, .critique),
            (.fidelity, .analysis, .checkFidelity),
        ]

        for (function, role, actionID) in cases {
            #expect(try ResearchActionFunctionMapping.definition(
                for: function,
                targetRole: role
            ).id == actionID)
        }

        #expect(throws: ResearchActionContractError.self) {
            try ResearchActionFunctionMapping.definition(
                for: .develop,
                targetRole: .work
            )
        }
    }
}
