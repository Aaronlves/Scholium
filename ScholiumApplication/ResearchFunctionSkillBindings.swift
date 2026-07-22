import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func researchFunctionSkillBindingStatus(
        for function: ResearchFunctionID
    ) async throws -> ResearchFunctionSkillBindingStatus {
        try requireActive()
        let store = services.researchSkillStore
        let revision = try? await store.bindingFileRevision()
        let candidates = try await researchFunctionSkillCandidates(
            for: function,
            store: store
        )
        do {
            let selection = try await store.functionSkillSelection(for: function)
            let compatible = try await store.compatiblePracticeIDs(
                for: function,
                primaryPackageID: selection.primaryPackageID
            )
            if let incompatible = selection.selectedPractices.first(where: {
                !compatible.contains($0.practiceID)
            }) {
                return ResearchFunctionSkillBindingStatus(
                    function: function,
                    candidates: candidates,
                    selection: selection,
                    bindingRevision: revision,
                    issue: ResearchFunctionSkillBindingIssue(
                        code: .invalidPractice,
                        selectedPackageID: incompatible.packageID,
                        selectedPracticeID: incompatible.practiceID
                    )
                )
            }
            return ResearchFunctionSkillBindingStatus(
                function: function,
                candidates: candidates,
                selection: selection,
                bindingRevision: revision,
                issue: nil
            )
        } catch {
            return ResearchFunctionSkillBindingStatus(
                function: function,
                candidates: candidates,
                selection: ResearchFunctionSkillSelection(function: function),
                bindingRevision: revision,
                issue: ResearchFunctionSkillBindingIssue(code: .malformedBinding)
            )
        }
    }

    func saveResearchFunctionSkillSelection(
        _ selection: ResearchFunctionSkillSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus {
        try requireActive()
        _ = try await services.researchSkillStore.saveFunctionSkillSelection(
            selection,
            expectedBindingRevision: expectedBindingRevision
        )
        return try await researchFunctionSkillBindingStatus(for: selection.function)
    }

    func clearResearchFunctionSkillSelection(
        for function: ResearchFunctionID,
        expectedBindingRevision: DocumentFingerprint?
    ) async throws -> ResearchFunctionSkillBindingStatus {
        try requireActive()
        _ = try await services.researchSkillStore.clearFunctionSkillSelection(
            for: function,
            expectedBindingRevision: expectedBindingRevision
        )
        return try await researchFunctionSkillBindingStatus(for: function)
    }

    private func researchFunctionSkillCandidates(
        for function: ResearchFunctionID,
        store: ResearchSkillStore
    ) async throws -> [ResearchFunctionSkillCandidate] {
        let packages = try await store.skills().filter { package in
            package.origin == .triptych
                && package.isValid
                && package.supports(function)
                && !isCitationMethodPackage(package)
        }
        var candidates: [ResearchFunctionSkillCandidate] = []
        for package in packages {
            let roles: [ResearchFunctionSkillBindingRole]
            if package.role == "practice" {
                guard function != .discuss else { continue }
                roles = [.practice]
            } else if package.role == "workflow" {
                guard function != .discuss else { continue }
                roles = [.primary]
            } else {
                var composesWithFunction = false
                for dependencyID in package.requiredSkillIDs {
                    if let dependency = try? await store.package(id: dependencyID),
                       dependency.supports(function) {
                        composesWithFunction = true
                        break
                    }
                }
                if function == .discuss, !composesWithFunction {
                    continue
                }
                if composesWithFunction {
                    roles = [.supplemental]
                } else {
                    roles = [.primary]
                }
            }
            candidates.append(ResearchFunctionSkillCandidate(
                packageID: package.id,
                name: researcherFacingSkillName(package),
                description: package.description,
                version: package.version,
                supportedFunctions: package.supportedFunctions,
                availableRoles: roles,
                practiceIDs: roles.contains(.practice)
                    ? Array(package.practiceResources.keys)
                    : []
            ))
        }
        return candidates
    }

    private func isCitationMethodPackage(_ package: ResearchSkillPackage) -> Bool {
        package.provides(.citationVerification)
            || package.provides(.citationFormatting)
            || !package.citationStyleResources.isEmpty
    }

    private func researcherFacingSkillName(_ package: ResearchSkillPackage) -> String {
        let normalized = package.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.hasPrefix("scholium-") else { return normalized }
        let words = normalized.split(separator: "-").map(String.init)
        let meaningful = words.first == "scholium" ? Array(words.dropFirst()) : words
        return meaningful.map { word in
            word.prefix(1).uppercased() + String(word.dropFirst())
        }.joined(separator: " ")
    }
}
