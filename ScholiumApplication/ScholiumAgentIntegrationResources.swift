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

    public static func codexRuntimeURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationBundles = [
            URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
            home.appendingPathComponent("Applications/Codex.app", isDirectory: true),
            home.appendingPathComponent("Applications/ChatGPT.app", isDirectory: true),
        ]
        let standaloneCandidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
        ]
        return codexRuntimeURL(
            applicationBundles: applicationBundles,
            standaloneCandidates: standaloneCandidates)
    }

    static func codexRuntimeURL(applicationBundles: [URL], standaloneCandidates: [URL]) -> URL? {
        let candidates = applicationBundles.flatMap { codexRuntimeCandidates(in: $0) } + standaloneCandidates
        return candidates.lazy.compactMap { executableURL(at: $0.path) }.first
    }

    static func codexRuntimeCandidates(in applicationBundle: URL) -> [URL] {
        [
            applicationBundle.appendingPathComponent("Contents/Resources/codex"),
            applicationBundle.appendingPathComponent(
                "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
        ]
    }

    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        try BundledResearchSkillResources.coreProtocolSkillDirectoryURL()
    }

    public static func chatHelperURL(bundleURL: URL = Bundle.main.bundleURL) -> URL? {
        executableURL(at: bundleURL.appendingPathComponent("Contents/Helpers/ScholiumAgentHelper").path)
    }

}
