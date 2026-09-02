import Foundation
import ScholiumCore

/// Public application-layer access to the release-bundled Core Protocol.
/// Delivery surfaces may reveal this ordinary Skill folder, but never edit or
/// install an external Agent host's configuration.
public enum ScholiumAgentIntegrationResources {
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
