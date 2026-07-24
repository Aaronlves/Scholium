import ScholiumContracts

/// Compatibility-only routing from the public Action contract into the
/// protected Function coordinator. This mapping is internal to Application
/// and never enters an Action snapshot or researcher-facing record.
enum ResearchActionFunctionMapping {
    static func function(
        for definition: ResearchActionDefinition,
        targetRole: ResearchActionTargetRole
    ) throws -> ResearchFunctionID {
        try definition.validate(targetRole: targetRole)

        let function: ResearchFunctionID = switch definition.executionKind {
        case .discussion: .discuss
        case .analysis, .synthesis: .develop
        case .writing: .revise
        case .critique: .critique
        case .checkFidelity: .fidelity
        case .manuscript: .manuscript
        }

        guard function.allowedTargetRoles.contains(targetRole.functionTargetRole) else {
            throw ResearchActionContractError.invalidTargetRole(
                actionID: definition.id,
                executionKind: definition.executionKind,
                role: targetRole
            )
        }
        return function
    }
}

private extension ResearchActionTargetRole {
    var functionTargetRole: ResearchFunctionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}
