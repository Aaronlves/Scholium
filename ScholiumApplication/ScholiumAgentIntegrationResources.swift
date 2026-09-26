import Foundation
import ScholiumCore

/// Public application-layer access to the release-bundled Core Protocol.
/// Delivery surfaces may reveal this ordinary Skill folder, but never edit or
/// install an external Agent host's configuration.
public enum ScholiumAgentIntegrationResources {
    public static func executableURL(at path: String) -> URL? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Finds a Codex CLI bundled in a Launch Services-registered application.
    public static func codexRuntimeURL(registeredApplicationBundles: [URL]) -> URL? {
        registeredApplicationBundles
            .lazy
            .flatMap { codexRuntimeCandidates(in: $0) }
            .compactMap { executableURL(at: $0.path) }
            .first
    }

    private static func codexRuntimeCandidates(in applicationBundle: URL) -> [URL] {
        let cliApplicationsDirectory =
            applicationBundle
            .appendingPathComponent("Contents/Resources/codex-cli", isDirectory: true)
        let bundledRuntimes =
            (try? FileManager.default.contentsOfDirectory(
                at: cliApplicationsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.appendingPathComponent("Contents/MacOS/codex") } ?? []

        return bundledRuntimes
    }

    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        try BundledResearchSkillResources.coreProtocolSkillDirectoryURL()
    }

    public static func chatHelperURL(bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        executableURL(at: bundleURL.appendingPathComponent("Contents/Helpers/ScholiumAgentHelper").path)
    }

}
