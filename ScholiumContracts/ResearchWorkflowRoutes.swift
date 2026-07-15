import Foundation

/// Typed contracts for app-owned routes whose scholarly task boundary is
/// already explicit. These helpers describe scope for an external agent; they
/// do not grant permission independently of the researcher action that caused
/// the route to be prepared.
public enum ResearchWorkflowRouteContracts {
    /// Describes Request Critique as one version-bound review phase.
    ///
    /// The Work is read-only. The exact Critique document is the only durable
    /// write target, and its fingerprint remains a revision check rather than
    /// an authorization token.
    public static func critique(
        work: ResearchWorkflowObjectReference,
        critique: ResearchWorkflowObjectReference,
        purpose: String
    ) throws -> ResearchWorkflowContract {
        guard work.kind == .note, work.fingerprint != nil else {
            throw ResearchWorkflowContractError.invalid(
                "Request Critique requires an exact Work note revision."
            )
        }
        guard critique.kind == .note, critique.fingerprint != nil else {
            throw ResearchWorkflowContractError.invalid(
                "Request Critique requires an exact Critique note revision."
            )
        }

        let contract = ResearchWorkflowContract(
            mode: .review,
            taskObject: work.identifier,
            purpose: purpose,
            originalReadSet: [work, critique],
            originalWriteSet: [critique],
            phases: [
                ResearchWorkflowPhaseContract(
                    phase: 1,
                    mode: .review,
                    purpose: purpose,
                    requiredSkillIDs: [
                        "scholium-philosophical-review",
                        "scholium-research-integration",
                    ],
                    readSet: [work, critique],
                    writeSet: [critique],
                    permission: .directEditAuthorized,
                    permissionBasis: "The researcher invoked Request Critique for this exact Work and Critique target.",
                    output: "Update only the attributed Critique document; do not modify the Work.",
                    stopCondition: "Stop if an exact revision changed, required evidence is unavailable, or the task would require writing outside the Critique document.",
                    durability: .durableUpdate,
                    handoff: ResearchWorkflowHandoff(
                        summary: "Return a version-bound Critique for researcher inspection.",
                        evidenceStatus: "Agent-authored assessment; not researcher-settled knowledge.",
                        basis: [work],
                        unresolvedQuestions: [
                            "Any finding not supportable from the available Work and research context remains explicit."
                        ],
                        checksRequired: [
                            "Preserve the Work unchanged.",
                            "Bind findings to the exact Work revision and available evidence.",
                        ]
                    )
                )
            ]
        )
        try contract.validate()
        return contract
    }
}
