import ScholiumContracts
import Foundation

public enum ScholiumPaths {
    public static let applicationSupportDirectoryName = "Scholium"
    public static let legacyApplicationSupportDirectoryName = "KBManager"
    public static let applicationBundleIdentifier = "com.kbmanager.app"

    /// Returns Scholium's app-support directory and performs a non-destructive
    /// one-time copy of legacy KB Manager state when the new directory does not
    /// yet exist. The legacy directory is retained for rollback.
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
        let legacy = base.appendingPathComponent(legacyApplicationSupportDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacy, to: current)
        }
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
