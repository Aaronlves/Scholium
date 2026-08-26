import ScholiumContracts
import Foundation
import ScholiumApplication

/// One immutable-membership Application runtime for a CLI invocation.
///
/// The context resolves current selectors against the runtime's frozen
/// Triptych assignments. It never constructs repositories, indexes, stores,
/// or watchers in the delivery target.
struct CLIContext: Sendable {
    let runtime: WorkspaceRuntime

    static func make() async throws -> CLIContext {
        let homeURL = ScholiumPaths.cliHomeURL()
        let applicationSupportURL = if ProcessInfo.processInfo.environment["SCHOLIUM_HOME"] != nil {
            homeURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
        } else {
            try ScholiumPaths.sharedApplicationSupportURL()
        }
        let registryStorageURL = try ScholiumPaths.workspaceRegistryURL()
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )
        return CLIContext(runtime: runtime)
    }

    /// Creates only the local Agent bridge adapter. It deliberately does not
    /// construct the ordinary snapshot runtime or touch vault state.
    static func makeAgentBridge() throws -> AgentBridgeOperations {
        let environment = ProcessInfo.processInfo.environment
        let bridgeContainerURL = try ScholiumPaths.agentBridgeContainerURL(
            environment: environment
        )
        return try AgentBridgeOperations(
            applicationSupportURL: bridgeContainerURL
        )
    }

    static func makeAgentCredentialStore() throws -> AgentSessionCredentialStore {
        AgentSessionCredentialStore(
            directoryURL: try ScholiumPaths.agentSessionCredentialDirectoryURL()
        )
    }

    func shutdown() async {
        await runtime.shutdown()
    }

    func assignments() async throws -> [TriptychAssignment] {
        try await runtime.availableWorkspaces()
    }

    func selectedTriptych(selector: String?) async throws -> TriptychAssignment {
        guard let selector else {
            return try await runtime.defaultWorkspace()
        }
        return try await triptych(selector: selector)
    }

    func triptych(selector: String) async throws -> TriptychAssignment {
        let assignments = try await assignments()
        if let id = UUID(uuidString: selector),
           let assignment = assignments.first(where: { $0.id == id }) {
            return assignment
        }
        let matches = assignments.filter {
            $0.triptych.name.caseInsensitiveCompare(selector) == .orderedSame
        }
        guard !matches.isEmpty else {
            throw WorkspaceRegistryError.triptychSelectorNotFound(selector)
        }
        guard matches.count == 1 else {
            throw WorkspaceRegistryError.ambiguousTriptychSelector(selector)
        }
        return matches[0]
    }

    func triptych(containing requiredVaultIDs: Set<UUID>) async throws -> TriptychAssignment {
        let matches = try await assignments().filter { assignment in
            let assigned = Set(assignment.vaults.values.map(\.id))
            return requiredVaultIDs.isSubset(of: assigned)
        }
        guard !matches.isEmpty else {
            throw CLIError.usage(
                "The selected vaults do not belong to one registered Scholium Triptych."
            )
        }
        guard matches.count == 1 else {
            throw CLIError.usage(
                "The selected vaults belong to more than one registered Triptych; specify unique vault paths or IDs."
            )
        }
        return matches[0]
    }

    func resolveVault(_ selector: String) async throws -> RegisteredVault {
        let vaults = uniqueVaults(in: try await assignments())
        if let id = UUID(uuidString: selector),
           let match = vaults.first(where: { $0.id == id }) {
            return match
        }
        let standardizedPath = URL(
            fileURLWithPath: (selector as NSString).expandingTildeInPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL.path
        let matches = vaults.filter {
            $0.name.caseInsensitiveCompare(selector) == .orderedSame
                || $0.canonicalPath == standardizedPath
        }
        guard !matches.isEmpty else {
            throw WorkspaceRegistryError.vaultNotFound(selector)
        }
        guard matches.count == 1 else {
            throw WorkspaceRegistryError.ambiguousSelector(selector)
        }
        return matches[0]
    }

    func resolveTarget(
        _ specification: String,
        within triptych: TriptychAssignment? = nil
    ) async throws -> (vault: RegisteredVault, relativePath: String) {
        guard let separator = specification.firstIndex(of: ":") else {
            throw CLIError.usage("Target must use <vault>:<relative-path> syntax.")
        }
        let selector = String(specification[..<separator])
        let relativePath = String(specification[specification.index(after: separator)...])
        guard !selector.isEmpty, !relativePath.isEmpty else {
            throw CLIError.usage("Target must use <vault>:<relative-path> syntax.")
        }

        if let triptych {
            let standardizedPath = URL(
                fileURLWithPath: (selector as NSString).expandingTildeInPath,
                isDirectory: true
            ).resolvingSymlinksInPath().standardizedFileURL.path
            let matches = uniqueVaults(in: [triptych]).filter { vault in
                vault.id.uuidString.caseInsensitiveCompare(selector) == .orderedSame
                    || vault.name.caseInsensitiveCompare(selector) == .orderedSame
                    || vault.canonicalPath == standardizedPath
            }
            guard !matches.isEmpty else {
                throw WorkspaceRegistryError.vaultNotFound(selector)
            }
            guard matches.count == 1 else {
                throw WorkspaceRegistryError.ambiguousSelector(selector)
            }
            return (matches[0], relativePath)
        }

        let vault = try await resolveVault(selector)
        _ = try await self.triptych(containing: [vault.id])
        return (vault, relativePath)
    }

    func handle(for assignment: TriptychAssignment) async throws -> WorkspaceHandle {
        try await runtime.openWorkspace(id: assignment.id)
    }

    private func uniqueVaults(in assignments: [TriptychAssignment]) -> [RegisteredVault] {
        var byID: [UUID: RegisteredVault] = [:]
        for assignment in assignments {
            for vault in assignment.vaults.values where byID[vault.id] == nil {
                byID[vault.id] = vault
            }
        }
        return byID.values.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.canonicalPath != $1.canonicalPath { return $0.canonicalPath < $1.canonicalPath }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
