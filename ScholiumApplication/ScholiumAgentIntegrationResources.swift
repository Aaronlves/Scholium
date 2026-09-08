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
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
        ]
        return candidates.lazy.compactMap { executableURL(at: $0) }.first
    }

    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        try BundledResearchSkillResources.coreProtocolSkillDirectoryURL()
    }

    public static func scholiumCLIURL(
        fileManager: FileManager = .default
    ) -> URL? {
        let candidate = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/scholium", isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue,
           fileManager.isExecutableFile(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }
}
