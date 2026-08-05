import ScholiumContracts
import Foundation

public enum ScholiumPaths {
    public static let applicationSupportDirectoryName = "Scholium"
    public static let applicationBundleIdentifier = "com.scholium.app"
    public static let applicationGroupIdentifier = "group.com.scholium.app"

    /// Returns Scholium's own app-support directory. Pre-release application
    /// state from other product identities is never imported automatically.
    public static func applicationSupportURL(
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let base: URL
        if let baseURL {
            base = baseURL
        } else if let discovered = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            base = discovered
        } else {
            throw CocoaError(.fileNoSuchFile)
        }

        let current = base.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        return current
    }

    /// Agent-facing CLI state is deliberately separate from authoritative
    /// vaults. `SCHOLIUM_HOME` makes the location explicit and testable.
    public static func cliHomeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["SCHOLIUM_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".scholium", isDirectory: true)
    }

    /// Returns the Application Support directory shared by the sandboxed app
    /// and the ordinary local CLI. Outside the sandbox, the CLI explicitly
    /// discovers the app container when it exists; otherwise development and
    /// unsandboxed builds fall back to the ordinary user Application Support.
    public static func sharedApplicationSupportURL(
        homeURL: URL? = nil,
        fallbackBaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let home = homeURL ?? fileManager.homeDirectoryForCurrentUser
        let container = home
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(applicationBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        if fileManager.fileExists(atPath: container.path) {
            return container
        }
        return try applicationSupportURL(baseURL: fallbackBaseURL, fileManager: fileManager)
    }

    /// Supported rendezvous location for the sandboxed App and signed CLI.
    /// This container owns only the Unix socket and its minimal owner lock;
    /// research content, Runs, Records, recovery state, and Session semantics
    /// remain in their existing owners.
    public static func agentBridgeContainerURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        debugFallbackURL: URL? = nil
    ) throws -> URL {
        if let explicit = environment["SCHOLIUM_AGENT_BRIDGE_CONTAINER"],
           !explicit.isEmpty {
            return URL(
                fileURLWithPath: (explicit as NSString).expandingTildeInPath,
                isDirectory: true
            ).standardizedFileURL
        }
        if environment["SCHOLIUM_HOME"] != nil {
            return cliHomeURL(environment: environment, fileManager: fileManager)
                .appendingPathComponent("AgentBridge", isDirectory: true)
        }
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: applicationGroupIdentifier
        ) {
            return group
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("ScholiumAgentBridge", isDirectory: true)
        }
#if DEBUG
        if let debugFallbackURL {
            return debugFallbackURL
                .appendingPathComponent("AgentBridge", isDirectory: true)
        }
#endif
        throw CocoaError(.fileNoSuchFile)
    }

    /// The app and the ordinary CLI share one role-aware vault registry. An
    /// explicit SCHOLIUM_HOME keeps tests and scripted environments isolated.
    public static func workspaceRegistryURL(
        homeURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> URL {
        if environment["SCHOLIUM_HOME"] != nil {
            return (homeURL ?? cliHomeURL(environment: environment, fileManager: fileManager))
                .appendingPathComponent("registry", isDirectory: true)
        }
        return try sharedApplicationSupportURL(fileManager: fileManager)
            .appendingPathComponent("Workspace", isDirectory: true)
    }
}
