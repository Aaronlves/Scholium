import Foundation
import ScholiumContracts

public enum WorkspaceSkillDiscoveryError: LocalizedError, Hashable, Sendable {
    case workspaceRootMismatch(expected: String, actual: String)
    case unavailableMethodFolder(ResearchActionID)

    public var errorDescription: String? {
        switch self {
        case .workspaceRootMismatch(let expected, let actual):
            "The Skill discovery workspace root does not own this Triptych control directory. Expected \(expected); received \(actual)."
        case .unavailableMethodFolder(let actionID):
            "The current \(actionID.rawValue) Method folder is unavailable for project Skill discovery."
        }
    }
}

extension ResearchConfigurationStore {
    /// Returns the release-managed System Skills plus every exact, currently
    /// enabled Method folder. It never enumerates folder contents; an
    /// authorized setup Agent maps only these sources into project discovery.
    public func skillDiscoverySourceManifest(
        workspaceRootURL: URL,
        triptychName: String
    ) throws -> WorkspaceSkillSourceManifest {
        let workspaceRoot = workspaceRootURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let expectedControl = workspaceRoot
            .appendingPathComponent(".scholium", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let actualControl = skillDiscoveryControlURL.resolvingSymlinksInPath()
            .standardizedFileURL
        guard expectedControl.path == actualControl.path else {
            throw WorkspaceSkillDiscoveryError.workspaceRootMismatch(
                expected: actualControl.deletingLastPathComponent().path,
                actual: workspaceRoot.path
            )
        }
        guard let registrations = try registrationSnapshot() else {
            throw ResearchConfigurationStoreError.missingRegistrations
        }

        var sources = try BundledResearchSkillResources.systemSkillDirectoryURLs()
            .map { source in
                try WorkspaceSkillSource(
                    name: source.id.rawValue,
                    sourceDirectory: source.url.path,
                    ownership: .scholiumManaged
                )
            }

        for registration in registrations.document.registrations
            where registration.isEnabled
        {
            let binding = try skillBindingSnapshot(for: registration.actionID)
            guard binding.skillFolderIsAvailable else {
                throw WorkspaceSkillDiscoveryError.unavailableMethodFolder(
                    registration.actionID
                )
            }
            let folder = URL(
                fileURLWithPath: binding.skillFolderPath,
                isDirectory: true
            )
                .resolvingSymlinksInPath().standardizedFileURL
            let discoveryName = registration.actionID.projectSkillName
            sources.append(try WorkspaceSkillSource(
                name: discoveryName,
                sourceDirectory: folder.path,
                ownership: .researcherOwned,
                actionID: registration.actionID
            ))
        }

        return try WorkspaceSkillSourceManifest(
            triptychID: skillDiscoveryTriptychID,
            triptychName: triptychName,
            workspaceRoot: workspaceRoot.path,
            skills: sources
        )
    }

}
