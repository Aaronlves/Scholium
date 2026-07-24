import ScholiumContracts
import Foundation

/// Resolves packages and exact Practice references without persisting the task
/// contract or adding an embedded agent runtime.
public enum ResearchWorkflowAssembler {
    /// Resolves one semantic function without allowing delivery targets to
    /// select a package identifier or parse Skill metadata. A manuscript or a
    /// write-plus-Fidelity workflow calls this once per isolated semantic
    /// function; it never flattens phase authority.
    public static func resolveFunction(
        _ contract: ResearchWorkflowContract,
        function: ResearchFunctionID,
        actionID: ResearchActionID,
        fidelityChecks: Set<FidelityCheck> = [],
        citationStyle: String? = nil,
        primaryResourcePaths: Set<String> = [],
        conditionalResourcePaths: [String: Set<String>] = [:],
        store: ResearchSkillStore
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try contract.validate()
        let primaryResolution = try await store.functionBindingResolution(
            for: function,
            actionID: actionID
        )
        let primarySkillIDs = primaryResolution.package.map { [$0.id] } ?? []
        let effectiveContract = applyingPrimaryMethod(
            primarySkillIDs,
            to: contract
        )
        try effectiveContract.validate()
        var resolvedPhases: [ResolvedResearchWorkflowPhase] = []

        for phase in effectiveContract.phases {
            let practicePackageIDs = phase.selectedPractices.map(\.packageID)
            let additionalIDs = unique(phase.requiredSkillIDs + practicePackageIDs)
                .filter { $0 != primaryResolution.package?.id }
            var selectedPaths = conditionalResourcePaths
            var practicePackageRevisions: [String: DocumentFingerprint] = [:]
            var practiceReferences: [String: String] = [:]
            var blocking: [String] = []
            var warnings: [String] = []

            for selection in phase.selectedPractices {
                let package = try await store.package(id: selection.packageID)
                guard package.role == "practice" else {
                    throw ResearchWorkflowContractError.invalid(
                        "Selected package is not a Practice library: \(selection.packageID)."
                    )
                }
                guard let reference = package.practiceResources[selection.practiceID] else {
                    throw ResearchWorkflowContractError.invalid(
                        "Practice \(selection.selectionID) is not declared by its package."
                    )
                }
                guard let revision = package.revision else {
                    throw ResearchWorkflowContractError.invalid(
                        "Practice package has no exact revision: \(selection.packageID)."
                    )
                }
                if let existing = practicePackageRevisions[package.id],
                   existing != revision {
                    throw ResearchWorkflowContractError.invalid(
                        "Practice package changed while the phase was being prepared: \(package.id)."
                    )
                }
                practicePackageRevisions[package.id] = revision
                practiceReferences[selection.selectionID] = reference
                selectedPaths[package.id, default: []].insert(reference)
            }

            let packages = try await store.resolvedFunctionPackages(
                for: function,
                actionID: actionID,
                fidelityChecks: fidelityChecks,
                citationStyle: citationStyle,
                additionalSkillIDs: additionalIDs,
                primaryResourcePaths: primaryResourcePaths,
                additionalResourcePaths: selectedPaths,
                expectedAdditionalPackageRevisions: practicePackageRevisions,
                primaryResolution: primaryResolution
            )
            for selection in phase.selectedPractices {
                guard let expectedRevision = practicePackageRevisions[selection.packageID],
                      let reference = practiceReferences[selection.selectionID],
                      let resolved = packages.first(where: {
                          $0.id == selection.packageID
                      }),
                      resolved.packageRevision == expectedRevision,
                      resolved.loadedResources.contains(where: {
                          $0.relativePath == reference
                      }) else {
                    throw ResearchWorkflowContractError.invalid(
                        "Practice package changed while exact resources were being captured: \(selection.packageID)."
                    )
                }
            }
            let compatible = Set(
                primaryResolution.package?.compatiblePracticeIDs ?? []
            )
            for selection in phase.selectedPractices
            where !compatible.contains(selection.practiceID) {
                blocking.append(
                    "Practice \(selection.selectionID) is incompatible with the complete primary method for this phase and requires Research Guidance repair."
                )
            }

            blocking = unique(blocking)
            warnings = unique(warnings)
            let rendered = try render(
                phase: phase,
                packages: packages,
                warnings: warnings,
                blockingConflicts: blocking
            )
            resolvedPhases.append(ResolvedResearchWorkflowPhase(
                contract: phase,
                packages: packages,
                warnings: warnings,
                blockingConflicts: blocking,
                renderedInstructions: rendered
            ))
        }

        let warnings = unique(resolvedPhases.flatMap(\.warnings))
        let conflicts = unique(resolvedPhases.flatMap(\.blockingConflicts))
        let rendered = ([
            "# Scholium Research Function",
            "",
            "This is an ephemeral function packet. It does not grant permission, certify philosophical adequacy, or merge authority across phases.",
            "",
        ] + resolvedPhases.map(\.renderedInstructions)).joined(separator: "\n")
        return ResolvedResearchWorkflowEnvelope(
            contract: effectiveContract,
            phases: resolvedPhases,
            warnings: warnings,
            blockingConflicts: conflicts,
            renderedInstructions: rendered
        )
    }

    private static func applyingPrimaryMethod(
        _ primarySkillIDs: [String],
        to contract: ResearchWorkflowContract
    ) -> ResearchWorkflowContract {
        let phases = contract.phases.map { phase in
            return ResearchWorkflowPhaseContract(
                phase: phase.phase,
                mode: phase.mode,
                purpose: phase.purpose,
                requiredSkillIDs: unique(
                    primarySkillIDs
                        + phase.requiredSkillIDs
                ),
                selectedPractices: phase.selectedPractices,
                readSet: phase.readSet,
                writeSet: phase.writeSet,
                permission: phase.permission,
                permissionBasis: phase.permissionBasis,
                output: phase.output,
                stopCondition: phase.stopCondition,
                durability: phase.durability,
                handoff: phase.handoff,
                auditState: phase.auditState
            )
        }
        return ResearchWorkflowContract(
            schemaVersion: contract.schemaVersion,
            mode: contract.mode,
            taskObject: contract.taskObject,
            purpose: contract.purpose,
            originalReadSet: contract.originalReadSet,
            originalWriteSet: contract.originalWriteSet,
            researchUnit: contract.researchUnit,
            researchUnitAuthorization: contract.researchUnitAuthorization,
            dialogueTarget: contract.dialogueTarget,
            responseContractSource: contract.responseContractSource,
            phases: phases
        )
    }

    public static func resolve(
        _ contract: ResearchWorkflowContract,
        store: ResearchSkillStore
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try contract.validate()
        var resolvedPhases: [ResolvedResearchWorkflowPhase] = []

        for phase in contract.phases {
            let practicePackageIDs = phase.selectedPractices.map(\.packageID)
            let requestedIDs = unique(phase.requiredSkillIDs + practicePackageIDs)
            let packages = try await store.resolvedPackages(
                for: phase.mode,
                requestedSkillIDs: requestedIDs
            )
            let packagesByID = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
            var warnings: [String] = []
            var blocking: [String] = []
            var selectedPaths: [String: Set<String>] = [:]

            for package in packages {
                selectedPaths[package.id] = ["SKILL.md"]
            }
            let compatible = Set(
                packages.filter { $0.role == "method" }
                    .flatMap(\.compatiblePracticeIDs)
            )
            for selection in phase.selectedPractices {
                guard let package = packagesByID[selection.packageID] else {
                    throw ResearchWorkflowContractError.invalid(
                        "Selected Practice package is unavailable: \(selection.packageID)."
                    )
                }
                guard package.role == "practice" else {
                    throw ResearchWorkflowContractError.invalid(
                        "Selected package is not a Practice library: \(selection.packageID)."
                    )
                }
                guard let reference = package.practiceResources[selection.practiceID] else {
                    throw ResearchWorkflowContractError.invalid(
                        "Practice \(selection.selectionID) is not declared by its package."
                    )
                }
                selectedPaths[package.id, default: []].insert(reference)
                if !compatible.contains(selection.practiceID) {
                    blocking.append(
                        "Practice \(selection.selectionID) is incompatible with the complete primary method for this phase and requires Research Guidance repair."
                    )
                }
            }

            var resolvedPackages: [ResolvedResearchSkillSelection] = []
            for package in packages {
                guard let packageRevision = package.revision else {
                    throw ResearchSkillError.invalidPackage(
                        package.id,
                        package.validationIssues
                    )
                }
                let available = try await store.resourcePaths(id: package.id)
                let loadedPaths = (selectedPaths[package.id] ?? ["SKILL.md"]).sorted()
                var loaded: [ResolvedResearchSkillResource] = []
                for path in loadedPaths {
                    guard available.contains(path) else {
                        throw ResearchSkillCatalogError.resourceMissing(
                            "\(package.id)/\(path)"
                        )
                    }
                    let source = try await store.resource(id: package.id, relativePath: path)
                    loaded.append(ResolvedResearchSkillResource(
                        relativePath: path,
                        revision: DocumentFingerprint(content: source),
                        source: source
                    ))
                }
                resolvedPackages.append(ResolvedResearchSkillSelection(
                    id: package.id,
                    origin: package.origin,
                    version: package.version,
                    packageRevision: packageRevision,
                    availableResourcePaths: available,
                    loadedResources: loaded
                ))
            }

            blocking = unique(blocking)
            warnings = unique(warnings)
            let rendered = try render(
                phase: phase,
                packages: resolvedPackages,
                warnings: warnings,
                blockingConflicts: blocking
            )
            resolvedPhases.append(ResolvedResearchWorkflowPhase(
                contract: phase,
                packages: resolvedPackages,
                warnings: warnings,
                blockingConflicts: blocking,
                renderedInstructions: rendered
            ))
        }

        let warnings = unique(resolvedPhases.flatMap(\.warnings))
        let conflicts = unique(resolvedPhases.flatMap(\.blockingConflicts))
        let rendered = ([
            "# Scholium Workflow Contract",
            "",
            "This is an ephemeral structural task packet. It does not grant permission, certify philosophical adequacy, or become part of Discuss.",
            "",
        ] + resolvedPhases.map(\.renderedInstructions)).joined(separator: "\n")
        return ResolvedResearchWorkflowEnvelope(
            contract: contract,
            phases: resolvedPhases,
            warnings: warnings,
            blockingConflicts: conflicts,
            renderedInstructions: rendered
        )
    }

    private static func render(
        phase: ResearchWorkflowPhaseContract,
        packages: [ResolvedResearchSkillSelection],
        warnings: [String],
        blockingConflicts: [String]
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let packet = String(decoding: try encoder.encode(phase), as: UTF8.self)
        var sections = [
            "<workflow-phase phase=\"\(phase.phase)\" mode=\"\(phase.mode.rawValue)\">",
            "",
            "Reset retrieval context, method instructions, phase-local assumptions, permission, and write subset before this phase. Treat every handoff as provisional input.",
            "",
            "```json",
            packet,
            "```",
        ]
        if !warnings.isEmpty {
            sections.append("\nWarnings:\n" + warnings.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !blockingConflicts.isEmpty {
            sections.append(
                "\nBlocking methodological conflicts:\n"
                    + blockingConflicts.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        for package in packages {
            for resource in package.loadedResources {
                sections.append(
                    """

                    <skill-resource package="\(package.id)" path="\(resource.relativePath)" revision="\(resource.revision.sha256)">
                    \(resource.source)
                    </skill-resource>
                    """
                )
            }
        }
        sections.append("\n</workflow-phase>\n")
        return sections.joined(separator: "\n")
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
