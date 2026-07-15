import ScholiumContracts
import Foundation

/// Resolves packages and exact Practice references without persisting the task
/// contract or adding an embedded agent runtime.
public enum ResearchWorkflowAssembler {
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
            var blocking = replacementConflicts(in: phase.selectedPractices)
            var selectedPaths: [String: Set<String>] = [:]

            for package in packages {
                selectedPaths[package.id] = ["SKILL.md"]
            }
            let compatible = Set(
                packages.filter { $0.role == "workflow" }
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
                selectedPaths[package.id, default: []].formUnion([
                    "references/FOUNDATIONAL-DIMENSIONS.md",
                    "references/COMPOSITION-RULES.md",
                    reference,
                ])
                if !compatible.isEmpty, !compatible.contains(selection.practiceID) {
                    warnings.append(
                        "Practice \(selection.selectionID) is explicitly selected but is not listed as compatible with the phase's official Workflow Skill. Compatibility is advisory; preserve the methodological difference."
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
            "This is an ephemeral structural task packet. It does not grant permission, certify philosophical adequacy, or become part of Dialogue.",
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

    private static func replacementConflicts(
        in selections: [ResearchPracticeSelection]
    ) -> [String] {
        let replacements = selections.filter { $0.application == .replace }
        let groups = Dictionary(grouping: replacements) {
            "\($0.officialSkillID ?? "")::\($0.editablePoint ?? "")"
        }
        return groups.values.compactMap { group in
            guard group.count > 1 else { return nil }
            let precedence = group.compactMap(\.precedence)
            guard precedence.count == group.count,
                  Set(precedence).count == group.count else {
                return "Replacement Practices \(group.map(\.selectionID).joined(separator: ", ")) target the same editable point without unique researcher-declared precedence. Stop for researcher judgment."
            }
            return nil
        }
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
