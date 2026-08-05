import ScholiumContracts

/// Closed routing from the public Platform Action contract into the
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

    /// Derives the public bundled Action selected by the retained Function
    /// coordinator for the exact Target role. The closed mapping is not a
    /// second source of product semantics.
    static func definition(
        for function: ResearchFunctionID,
        targetRole: ResearchFunctionTargetRole
    ) throws -> ResearchActionDefinition {
        let definition: ResearchActionDefinition = switch function {
        case .discuss: .discuss
        case .develop:
            switch targetRole {
            case .analysis: .analyze
            case .topic: .synthesize
            case .work:
                throw ResearchActionContractError.invalidTargetRole(
                    actionID: .analyze,
                    executionKind: .analysis,
                    role: .work
                )
            }
        case .fidelity: .checkFidelity
        case .critique: .critique
        case .revise: .write
        case .manuscript: .manuscript
        }
        try definition.validate(targetRole: targetRole.actionTargetRole)
        return definition
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

private extension ResearchFunctionTargetRole {
    var actionTargetRole: ResearchActionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}
