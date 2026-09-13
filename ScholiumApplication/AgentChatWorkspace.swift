import Foundation
import ScholiumContracts

/// Portable Chat inputs; authentication and runtime state retain their machine-local home.
public enum AgentChatWorkspace {
    public static let instructionByteLimit = 32 * 1_024

    public static func skillsDirectory(in workspace: URL) -> URL {
        workspace.appendingPathComponent("skills", isDirectory: true)
    }

    public static func prepare(_ workspace: URL, runtimeHome: URL) throws -> URL {
        let workspace = workspace.standardizedFileURL
        let values = try workspace.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard workspace.isFileURL, values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let canonical = workspace.resolvingSymlinksInPath().standardizedFileURL
        let home = runtimeHome.resolvingSymlinksInPath().standardizedFileURL.path
        guard home != canonical.path, !home.hasPrefix(canonical.path + "/") else {
            throw ScholiumMCPFailure(
                code: .invalidRequest, message: "Codex settings must stay outside the Triptych Chat workspace.",
                recovery: "Use the default Codex settings folder in Advanced Options.")
        }
        let skills = skillsDirectory(in: workspace)
        do {
            try FileManager.default.createDirectory(at: skills, withIntermediateDirectories: false)
        } catch CocoaError.fileWriteFileExists {
            // Validate the existing directory below, including reconnects.
        }
        let skillValues = try skills.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard skillValues.isDirectory == true, skillValues.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let instructions = workspace.appendingPathComponent("AGENTS.md")
        do {
            try Data("# Triptych instructions\n\n".utf8).write(to: instructions, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            // This file belongs to the researcher; reconnect never rewrites it.
        }
        return workspace
    }
}
