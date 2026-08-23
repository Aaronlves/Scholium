import Foundation
import ScholiumContracts

public enum WorkspaceSkillDiscoveryError: LocalizedError, Hashable, Sendable {
    case workspaceRootMismatch(expected: String, actual: String)
    case unavailableMethodFolder(ResearchActionID)
    case invalidMethodMetadata(actionID: ResearchActionID, reason: String)

    public var errorDescription: String? {
        switch self {
        case .workspaceRootMismatch(let expected, let actual):
            "The Skill discovery workspace root does not own this Triptych control directory. Expected \(expected); received \(actual)."
        case .unavailableMethodFolder(let actionID):
            "The current \(actionID.rawValue) Method folder is unavailable for project Skill discovery."
        case .invalidMethodMetadata(let actionID, let reason):
            "The current \(actionID.rawValue) Method cannot be exposed for project Skill discovery. \(reason)"
        }
    }
}

extension ResearchConfigurationStore {
    /// Returns only exact, currently enabled Triptych-managed Method folders
    /// plus the release-managed Core Protocol. It never enumerates registered
    /// folders and never exposes machine-local Method locators before a Run.
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

        var sources = [try WorkspaceSkillSource(
            name: "scholium-core-protocol",
            sourceDirectory: try BundledResearchSkillResources
                .coreProtocolSkillDirectoryURL().path,
            ownership: .scholiumManaged
        )]

        for registration in registrations.document.registrations
            where registration.isEnabled
                && registration.skillFolder?.kind == .triptychControl
        {
            let method = try methodSnapshot(for: registration.actionID)
            guard let folderPath = method.skillFolderPath,
                  method.skillFolderIsAvailable == true else {
                throw WorkspaceSkillDiscoveryError.unavailableMethodFolder(
                    registration.actionID
                )
            }
            let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            guard folder.path.hasPrefix(actualControl.path + "/") else {
                throw WorkspaceSkillDiscoveryError.unavailableMethodFolder(
                    registration.actionID
                )
            }
            let discoveryName = try Self.discoveryName(for: registration.actionID)
            try Self.validateDiscoveryMetadata(
                method.primaryMarkdownSource,
                expectedName: discoveryName,
                actionID: registration.actionID
            )
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

    private static func discoveryName(for actionID: ResearchActionID) throws -> String {
        switch actionID {
        case .discuss: "scholium-discuss"
        case .analyze: "scholium-analyze"
        case .synthesize: "scholium-synthesize"
        case .write: "scholium-write"
        case .critique: "scholium-critique"
        case .checkFidelity: "scholium-content-fidelity"
        default:
            throw WorkspaceSkillDiscoveryError.invalidMethodMetadata(
                actionID: actionID,
                reason: "The Action has no stable project Skill name."
            )
        }
    }

    private static func validateDiscoveryMetadata(
        _ source: String,
        expectedName: String,
        actionID: ResearchActionID
    ) throws {
        let document = NoteDocument(relativePath: "SKILL.md", rawContent: source)
        guard document.frontmatterState == .valid else {
            throw WorkspaceSkillDiscoveryError.invalidMethodMetadata(
                actionID: actionID,
                reason: "SKILL.md must have valid YAML frontmatter."
            )
        }
        guard document.parsedFrontmatter["name"]?.scalarString == expectedName else {
            throw WorkspaceSkillDiscoveryError.invalidMethodMetadata(
                actionID: actionID,
                reason: "Its name must remain \(expectedName)."
            )
        }
        let rawDescription = document.parsedFrontmatter["description"]?.scalarString
        let description = rawDescription?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let description, !description.isEmpty,
              description.utf8.count <= 2_048 else {
            throw WorkspaceSkillDiscoveryError.invalidMethodMetadata(
                actionID: actionID,
                reason: "Its description must be nonempty and no larger than 2,048 UTF-8 bytes."
            )
        }
    }
}
