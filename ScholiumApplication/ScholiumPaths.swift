import ScholiumContracts
import Darwin
import Foundation

public enum ScholiumPaths {
    public static let applicationSupportDirectoryName = "Scholium"
    public static let machineStateDirectoryName = "State-v1"
    public static let agentSessionDirectoryName = "Agent Sessions"
    public static let agentBridgeDirectoryName = "AgentBridge"

    /// Creates or normalizes a directory that contains private Scholium
    /// state. Both the App and the independently delivered CLI use this
    /// boundary so a fresh isolated Home cannot leave shared state readable
    /// by other local users.
    public static func ensurePrivateDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    /// Returns the current machine-state namespace. Unsupported pre-release
    /// bytes at the parent Scholium directory remain untouched and cannot
    /// authorize the current application.
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

        let current = base
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(machineStateDirectoryName, isDirectory: true)
        try ensurePrivateDirectory(at: current, fileManager: fileManager)
        return current
    }

    /// Returns the explicit isolated CLI home. Production machine state is
    /// stored under Application Support; `SCHOLIUM_HOME` is reserved for
    /// isolated launches and tests.
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

    /// Returns the protected local Session directory. Production credentials
    /// belong to the shared machine-state root and never to a portable
    /// Triptych. Explicit isolated launches keep the same ownership boundary
    /// below their private test home.
    public static func agentSessionCredentialDirectoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeURL: URL? = nil
    ) throws -> URL {
        if environment["SCHOLIUM_HOME"] != nil {
            return cliHomeURL(environment: environment, fileManager: fileManager)
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
                .appendingPathComponent(agentSessionDirectoryName, isDirectory: true)
        }

        let stateRoot: URL
        if let homeURL {
            stateRoot = homeURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent(machineStateDirectoryName, isDirectory: true)
        } else {
            stateRoot = try sharedApplicationSupportURL(fileManager: fileManager)
        }
        return stateRoot.appendingPathComponent(agentSessionDirectoryName, isDirectory: true)
    }

    /// Returns the login account's ordinary Application Support directory
    /// shared by the sandboxed app and independently delivered CLI. Supplying
    /// a base URL keeps tests and explicit isolated launches deterministic.
    public static func sharedApplicationSupportURL(
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        if let baseURL {
            return try applicationSupportURL(baseURL: baseURL, fileManager: fileManager)
        }
        guard let loginHome = loginAccountHomeURL(
            accountHomePath: currentLoginAccountHomePath()
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try applicationSupportURL(
            baseURL: loginHome.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    /// Stable logical namespace used by the local App and CLI to derive the
    /// same loopback port. The path is never created or used as IPC storage;
    /// research content, Runs, Records, recovery state, and Session semantics
    /// remain in their existing owners.
    public static func agentBridgeContainerURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeURL: URL? = nil,
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
                .appendingPathComponent("ApplicationSupport", isDirectory: true)
                .appendingPathComponent(agentBridgeDirectoryName, isDirectory: true)
        }
#if DEBUG
        if let debugFallbackURL {
            return debugFallbackURL
                .appendingPathComponent(agentBridgeDirectoryName, isDirectory: true)
        }
#endif
        let stateRoot: URL
        if let homeURL {
            stateRoot = homeURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
                .appendingPathComponent(machineStateDirectoryName, isDirectory: true)
        } else {
            stateRoot = try sharedApplicationSupportURL(fileManager: fileManager)
        }
        return stateRoot.appendingPathComponent(agentBridgeDirectoryName, isDirectory: true)
    }

    public static func loginAccountHomeURL(accountHomePath: String?) -> URL? {
        guard let accountHomePath,
              accountHomePath.hasPrefix("/") else {
            return nil
        }
        return URL(
            fileURLWithPath: accountHomePath,
            isDirectory: true
        ).standardizedFileURL
    }

    public static func currentLoginAccountHomePath() -> String? {
        var account = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let configuredSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        let bufferSize = configuredSize > 0 ? Int(configuredSize) : 16_384
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let status = getpwuid_r(
            getuid(),
            &account,
            &buffer,
            buffer.count,
            &result
        )
        guard status == 0,
              result != nil,
              account.pw_dir != nil else {
            return nil
        }
        return String(cString: account.pw_dir)
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
