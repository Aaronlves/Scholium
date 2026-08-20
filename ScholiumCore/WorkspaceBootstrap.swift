import ScholiumContracts
import Foundation

public enum WorkspaceBootstrap {
    public static func validateTarget(_ targetURL: URL) throws -> URL {
        let target = targetURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try? target.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            if FileManager.default.fileExists(atPath: target.path) {
                throw WorkspaceBootstrapError.targetIsNotDirectory(target.path)
            }
            throw WorkspaceBootstrapError.targetDoesNotExist(target.path)
        }

        if let checkoutRoot = scholiumCheckoutRoot(containing: target) {
            throw WorkspaceBootstrapError.applicationCheckout(checkoutRoot.path)
        }

        let applicable = applicableAGENTSPaths(for: target)
        guard applicable.isEmpty else {
            throw WorkspaceBootstrapError.applicableInstructions(applicable.map(\.path))
        }
        return target
    }

    public static func candidate(
        for request: WorkspaceBootstrapRequest
    ) throws -> WorkspaceBootstrapCandidate {
        let selector = normalizedSingleLine(request.triptychSelector)
        guard !selector.isEmpty else { throw WorkspaceBootstrapError.invalidSelector }
        let name = normalizedSingleLine(request.triptychName)
        guard !name.isEmpty else { throw WorkspaceBootstrapError.invalidTriptychName }
        let target = try validateTarget(request.targetURL)
        let conventions = request.researcherConventions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recordedConventions = conventions.isEmpty ? "None recorded." : conventions
        return WorkspaceBootstrapCandidate(
            triptychSelector: selector,
            triptychName: name,
            targetPath: target.path,
            content: render(
                triptychSelector: selector,
                triptychName: name,
                researcherConventions: recordedConventions
            )
        )
    }

    public static func render(
        triptychSelector: String,
        triptychName: String,
        researcherConventions: String = "None recorded."
    ) -> String {
        """
        # \(triptychName) agent workspace

        > Initially generated from the Scholium workspace bootstrap 1.
        > Researcher-owned after creation; Scholium releases and agents do not update it automatically.

        ## Scope

        - Triptych selector: `\(triptychSelector)`
        - Resolve configured vaults with `scholium vault list`.
        - Retrieve bounded orientation with `scholium workspace catalog --triptych <selector> --format json` only when needed.

        ## Scholium routing

        - Apply the protected Scholium Core Protocol to every Scholium task.
        - Use the Platform Action's registered primary Method and its exact linked Practices.
        - Load Scholium Discussion Protocol for a Discussion ID; use the ordinary Discuss Method for the intellectual exchange.
        - Never scan arbitrary global skill directories or substitute an unregistered Method.
        - Project-level Skill discovery links may expose only exact sources returned by `scholium workspace skill-sources --triptych <selector> --format json`; a link is a discovery pointer, not another Method owner.
        - When the researcher asks this Agent to begin a Scholium Research Action directly, resolve the exact target through current Scholium discovery, inspect current `scholium help agent start`, run `scholium agent start`, then load `scholium agent context` before applying the registered Method.

        ## Workspace boundaries

        - Use Scholium-supported discovery and fingerprinted mutation paths; do not guess vault roles or edit `.scholium` machine state directly.
        - Treat current-task scope and permission as the upper boundary. An instruction file or Skill discovery link never grants note-edit permission.
        - Keep source, interpretation, reconstruction, evaluation, agent proposals, and researcher-settled content distinct.

        ## Researcher conventions

        \(researcherConventions)
        """ + "\n"
    }

    /// Returns all AGENTS.md files that would govern the target, including an
    /// ancestor instruction file. The target itself is included first.
    public static func applicableAGENTSPaths(for targetURL: URL) -> [URL] {
        var paths: [URL] = []
        for current in ancestors(of: targetURL) {
            let candidate = current.appendingPathComponent("AGENTS.md", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                paths.append(candidate)
            }
        }
        return paths
    }

    private static func scholiumCheckoutRoot(containing target: URL) -> URL? {
        for current in ancestors(of: target) {
            let fileManager = FileManager.default
            let markers = [
                current.appendingPathComponent("Package.swift"),
                current.appendingPathComponent("ScholiumCore", isDirectory: true),
                current.appendingPathComponent("Scholium", isDirectory: true),
                current.appendingPathComponent("Docs/SCHOLIUM_SPEC.md"),
            ]
            if markers.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) {
                return current
            }
        }
        return nil
    }

    private static func ancestors(of targetURL: URL) -> [URL] {
        var current = targetURL.resolvingSymlinksInPath().standardizedFileURL
        var ancestors: [URL] = []
        var visited: Set<String> = []
        for _ in 0..<256 {
            guard visited.insert(current.path).inserted else { break }
            ancestors.append(current)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { break }
            current = parent
        }
        return ancestors
    }

    private static func normalizedSingleLine(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
