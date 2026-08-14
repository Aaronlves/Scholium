import Darwin
import Foundation
import ScholiumContracts

/// App-wide machine integration for the bundled CLI. The frontend receives
/// only status and install operations and never performs executable I/O.
public actor CommandLineToolInstaller {
    private let fileManager: FileManager
    private let environment: @Sendable () -> [String: String]
    private let homeDirectory: @Sendable () -> URL?
    private let bundleURL: @Sendable () -> URL
    private let version: String

    public init(
        fileManager: FileManager = .default,
        environment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        homeDirectory: (@Sendable () -> URL?)? = nil,
        bundleURL: @escaping @Sendable () -> URL = { Bundle.main.bundleURL },
        version: String = ScholiumProductIdentity.releaseLabel
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory ?? {
            Self.defaultInstallationHomeDirectory()
        }
        self.bundleURL = bundleURL
        self.version = version
    }

    public func commandLineToolStatus() async -> CommandLineToolStatus {
        let source = bundledExecutableURL()
        let sourceResources = bundledResourceURL()
        let sourceFingerprint = source.flatMap(fingerprintOfRegularFile)
        guard let destination = installedExecutableURL() else {
            return CommandLineToolStatus(
                state: .invalidInstallation,
                version: version,
                installPath: "~/.local/bin/scholium",
                isOnCurrentPATH: false,
                bundledRevision: sourceFingerprint,
                repairMessage: CommandLineToolInstallationError
                    .installationHomeUnavailable.localizedDescription
            )
        }
        let destinationResources = installedResourceURL(for: destination)
        let installationPathContainsLink = installationPathContainsSymbolicLink(
            destination,
            resources: destinationResources
        )
        let resourcesAreValid = validResourceBundle(destinationResources)
        let installedFingerprint = installationPathContainsLink
            ? nil
            : fingerprintOfRegularFile(destination)
        let state: CommandLineToolInstallationState
        let repair: String?
        if sourceFingerprint == nil || sourceResources == nil {
            state = .bundledToolUnavailable
            repair = "Use a packaged Scholium build that includes Contents/Helpers/scholium."
        } else if installationPathContainsLink || isSymbolicLink(destinationResources) {
            state = .invalidInstallation
            repair = CommandLineToolInstallationError.installationPathContainsSymbolicLink
                .localizedDescription
        } else if installedFingerprint == nil && !fileManager.fileExists(atPath: destination.path) {
            state = .notInstalled
            repair = nil
        } else if installedFingerprint == nil || !resourcesAreValid {
            state = .invalidInstallation
            repair = "Reinstall the CLI to restore its executable and protected Skill resources together."
        } else if installedFingerprint == sourceFingerprint {
            state = .installed
            repair = pathContains(destination.deletingLastPathComponent())
                ? nil
                : "Add \(destination.deletingLastPathComponent().path) to PATH, then start a new shell or agent task."
        } else {
            state = .updateAvailable
            repair = nil
        }
        return CommandLineToolStatus(
            state: state,
            version: version,
            installPath: destination.path,
            isOnCurrentPATH: pathContains(destination.deletingLastPathComponent()),
            installedRevision: installedFingerprint,
            bundledRevision: sourceFingerprint,
            repairMessage: repair
        )
    }

    public func installCommandLineTool() async throws -> CommandLineToolStatus {
        guard let source = bundledExecutableURL(),
              let sourceResources = bundledResourceURL(),
              let sourceFingerprint = fingerprintOfRegularFile(source) else {
            throw CommandLineToolInstallationError.bundledToolUnavailable
        }
        guard let destination = installedExecutableURL() else {
            throw CommandLineToolInstallationError.installationHomeUnavailable
        }
        let destinationResources = installedResourceURL(for: destination)
        guard !installationPathContainsSymbolicLink(
            destination,
            resources: destinationResources
        ) else {
            throw CommandLineToolInstallationError.installationPathContainsSymbolicLink
        }
        let directory = destination.deletingLastPathComponent()
        guard !isSymbolicLink(destinationResources) else {
            throw CommandLineToolInstallationError.installationPathContainsSymbolicLink
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        let resourceTemporary = directory.appendingPathComponent(
            ".Scholium_ScholiumCore.bundle.\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: resourceTemporary) }
        try fileManager.copyItem(at: sourceResources, to: resourceTemporary)
        if fileManager.fileExists(atPath: destinationResources.path) {
            _ = try fileManager.replaceItemAt(
                destinationResources,
                withItemAt: resourceTemporary,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: resourceTemporary, to: destinationResources)
        }
        let data = try Data(contentsOf: source, options: [.mappedIfSafe, .uncached])
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destination.path
        )
        guard fingerprintOfRegularFile(destination) == sourceFingerprint,
              fileManager.isExecutableFile(atPath: destination.path),
              validResourceBundle(destinationResources) else {
            throw CommandLineToolInstallationError.verificationFailed
        }
        return await commandLineToolStatus()
    }

    private func bundledExecutableURL() -> URL? {
        if let override = environment()["SCHOLIUM_BUNDLED_CLI"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return bundleURL()
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("scholium", isDirectory: false)
    }

    private func installedExecutableURL() -> URL? {
        if let override = environment()["SCHOLIUM_CLI_INSTALL_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return homeDirectory()?
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("scholium", isDirectory: false)
    }

    private func bundledResourceURL() -> URL? {
        let candidate = bundleURL()
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Scholium_ScholiumCore.bundle", isDirectory: true)
        return validResourceBundle(candidate) ? candidate : nil
    }

    private func installedResourceURL(for executable: URL) -> URL {
        executable.deletingLastPathComponent()
            .appendingPathComponent("Scholium_ScholiumCore.bundle", isDirectory: true)
    }

    private func validResourceBundle(_ url: URL) -> Bool {
        guard !isSymbolicLink(url) else { return false }
        let skills = url.appendingPathComponent(
            "Contents/Resources/Skills",
            isDirectory: true
        )
        let currentSentinels = [
            "README.md",
            "Scholium System Skills/scholium-core-protocol/SKILL.md",
            "Scholium System Skills/scholium-core-protocol/references/runtime-protocol.md",
            "Scholium Method Skills/scholium-analyze/SKILL.md",
        ]
        return currentSentinels.allSatisfy { relativePath in
            fingerprintOfRegularFile(skills.appendingPathComponent(relativePath)) != nil
        }
    }

    private func fingerprintOfRegularFile(_ url: URL) -> DocumentFingerprint? {
        guard !isSymbolicLink(url),
              let values = try? url.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .isSymbolicLinkKey,
              ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe, .uncached]) else {
            return nil
        }
        return DocumentFingerprint(data: data)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func installationPathContainsSymbolicLink(
        _ destination: URL,
        resources: URL
    ) -> Bool {
        let directory = destination.deletingLastPathComponent()
        return [
            destination,
            resources,
            directory,
            directory.deletingLastPathComponent(),
        ].contains(where: isSymbolicLink)
    }

    private func pathContains(_ directory: URL) -> Bool {
        let expected = directory.standardizedFileURL.path
        return (environment()["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .contains { URL(fileURLWithPath: $0).standardizedFileURL.path == expected }
    }

    static func installationHomeDirectory(
        accountHomePath: String?
    ) -> URL? {
        guard let accountHomePath,
              accountHomePath.hasPrefix("/") else {
            return nil
        }
        return URL(
            fileURLWithPath: accountHomePath,
            isDirectory: true
        ).standardizedFileURL
    }

    private static func defaultInstallationHomeDirectory() -> URL? {
        installationHomeDirectory(
            accountHomePath: currentAccountHomePath()
        )
    }

    private static func currentAccountHomePath() -> String? {
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
}
