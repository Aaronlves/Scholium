import Foundation
import ScholiumContracts

/// Pure dependency and activation policy for already-inspected Skill packages.
/// Filesystem discovery and mutation remain outside this value.
struct ResearchSkillResolver {
    func validatedLocalPackages(
        _ rawLocal: [ResearchSkillPackage],
        bundled: [ResearchSkillPackage]
    ) -> [ResearchSkillPackage] {
        let protectedIDs = Set(bundled.map(\.id))
        let noncolliding = rawLocal.filter { !protectedIDs.contains($0.id) }
        let combined = bundled + noncolliding
        let byID = Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0) })

        var memoizedIssues: [String: [String]] = [:]
        func graphIssues(for id: String, path: Set<String>) -> [String] {
            if path.contains(id) {
                return ["The package dependency graph contains a cycle."]
            }
            if let cached = memoizedIssues[id] { return cached }
            guard let package = byID[id] else { return [] }
            var issues = package.validationIssues
            var nextPath = path
            nextPath.insert(id)
            for dependencyID in package.requiredSkillIDs {
                guard let dependency = byID[dependencyID] else {
                    issues.append("Required Skill does not exist: \(dependencyID).")
                    continue
                }
                if !dependency.isValid {
                    issues.append(
                        "Required Skill is structurally invalid: \(dependencyID)."
                    )
                }
                if dependency.role == "method" {
                    issues.append(
                        "A Triptych-local package cannot execute Method \(dependencyID) as a dependency. Each Action graph must contain only its one bound complete Method."
                    )
                }
                for mode in package.supportedModes where !dependency.supports(mode) {
                    issues.append(
                        "Required Skill \(dependencyID) does not support \(mode.rawValue) mode."
                    )
                }
                let dependencyIssues = graphIssues(
                    for: dependencyID,
                    path: nextPath
                )
                if !dependencyIssues.isEmpty {
                    issues.append(
                        "Required Skill has an invalid dependency graph: \(dependencyID)."
                    )
                }
                if dependencyIssues.contains(where: {
                    $0.localizedCaseInsensitiveContains("cycle")
                }) {
                    issues.append("The package dependency graph contains a cycle.")
                }
            }
            let result = Self.unique(issues)
            memoizedIssues[id] = result
            return result
        }

        return rawLocal.map { package in
            guard !protectedIDs.contains(package.id) else { return package }
            let additional = graphIssues(for: package.id, path: [])
                .filter { !package.validationIssues.contains($0) }
            return package.addingValidationIssues(additional)
        }
    }

    func resolvedPackages(
        catalog: ResearchSkillCatalog,
        bundled: [ResearchSkillPackage],
        local: [ResearchSkillPackage],
        mode: ResearchSkillMode,
        requestedSkillIDs: [String]
    ) throws -> [ResearchSkillPackage] {
        guard mode != .mixed else {
            throw ResearchSkillCatalogError.mixedModeRequiresPhases
        }
        let packages = bundled + local
        let byID = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
        let automatic = catalog.entries.filter {
            $0.skillClass == .system && $0.activatesAutomatically(in: mode)
        }.map(\.id)
        let seeds = Self.unique(automatic + requestedSkillIDs)
        var visiting: Set<String> = []
        var included: Set<String> = []
        var ordered: [ResearchSkillPackage] = []

        func visit(_ id: String) throws {
            guard let package = byID[id] else {
                throw ResearchSkillError.packageNotFound(id)
            }
            guard package.isValid else {
                throw ResearchSkillError.invalidPackage(
                    id,
                    package.validationIssues
                )
            }
            guard package.supports(mode) else {
                throw ResearchSkillCatalogError.unsupportedMode(
                    skillID: id,
                    mode: mode
                )
            }
            guard !included.contains(id) else { return }
            guard visiting.insert(id).inserted else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Dependency cycle includes \(id)."
                )
            }
            for dependency in package.requiredSkillIDs {
                try visit(dependency)
            }
            visiting.remove(id)
            included.insert(id)
            ordered.append(package)
        }

        for seed in seeds {
            try visit(seed)
        }
        return ordered
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
