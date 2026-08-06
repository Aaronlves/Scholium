import Darwin
import Foundation
import ScholiumContracts

enum BundledResearchMethodDefaults {
    struct Definition: Sendable {
        let actionID: ResearchActionID
        let displayName: String
        let resourceDirectory: String
        let resources: [String]
        let isEnabled: Bool

        init(
            actionID: ResearchActionID,
            displayName: String,
            resourceDirectory: String,
            resources: [String],
            isEnabled: Bool = true
        ) {
            self.actionID = actionID
            self.displayName = displayName
            self.resourceDirectory = resourceDirectory
            self.resources = resources
            self.isEnabled = isEnabled
        }
    }

    static let definitions: [Definition] = [
        Definition(
            actionID: .discuss,
            displayName: "Discuss",
            resourceDirectory: "Scholium Method Skills/scholium-discuss",
            resources: ["SKILL.md", "references/method.md", "references/response-contract.md"]
        ),
        Definition(
            actionID: .analyze,
            displayName: "Analyze Note",
            resourceDirectory: "Scholium Method Skills/scholium-analyze",
            resources: ["SKILL.md", "references/method.md", "references/literature-recommendations.md"]
        ),
        Definition(
            actionID: .synthesize,
            displayName: "Synthesize",
            resourceDirectory: "Scholium Method Skills/scholium-synthesize",
            resources: ["SKILL.md", "references/method.md"]
        ),
        Definition(
            actionID: .write,
            displayName: "Write",
            resourceDirectory: "Scholium Method Skills/scholium-write",
            resources: ["SKILL.md", "references/method.md", "references/feedback.md"]
        ),
        Definition(
            actionID: .critique,
            displayName: "Critique",
            resourceDirectory: "Scholium Method Skills/scholium-critique",
            resources: ["SKILL.md", "references/method.md"]
        ),
        Definition(
            actionID: .checkFidelity,
            displayName: "Check Fidelity",
            resourceDirectory: "Scholium Method Skills/scholium-content-fidelity",
            resources: ["SKILL.md", "references/content.md", "references/citations.md"]
        ),
        Definition(
            actionID: .manuscript,
            displayName: "Manuscript",
            resourceDirectory: "Scholium Method Skills/scholium-manuscript",
            resources: ["SKILL.md", "references/method.md"],
            isEnabled: false
        ),
    ]

    private static let practiceResources = [
        "Argument-Reconstructionist.md",
        "Conceptual-Analyst.md",
        "Dialectical-Partner.md",
        "Historical-Interpreter.md",
        "Philosophical-Expositor.md",
        "Research-Explorer.md",
        "Reviewer.md",
        "Systematizer.md",
        "Thesis-Architect.md",
    ]

    static func install(into controlURL: URL) throws -> [ResearchSkillRegistration] {
        let root = try SecureResearchConfigurationIO.openAbsoluteDirectory(controlURL)
        defer { Darwin.close(root) }
        let folders = try SecureResearchConfigurationIO.ensureDirectory(
            parentDescriptor: root,
            name: "skill-folders",
            path: controlURL.appendingPathComponent("skill-folders").path
        )
        defer { Darwin.close(folders) }

        var registrations: [ResearchSkillRegistration] = []
        for definition in definitions {
            let folderName = definition.actionID.rawValue
            let folderURL = controlURL
                .appendingPathComponent("skill-folders", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
                .standardizedFileURL
            let folder = try SecureResearchConfigurationIO.ensureDirectory(
                parentDescriptor: folders,
                name: folderName,
                path: folderURL.path
            )
            defer { Darwin.close(folder) }
            var referencesDescriptor: Int32?
            defer {
                if let referencesDescriptor { Darwin.close(referencesDescriptor) }
            }
            for resource in definition.resources {
                let components = resource.split(separator: "/").map(String.init)
                let parent: Int32
                let leaf: String
                if components.count == 1 {
                    parent = folder
                    leaf = components[0]
                } else {
                    if referencesDescriptor == nil {
                        referencesDescriptor = try SecureResearchConfigurationIO.ensureDirectory(
                            parentDescriptor: folder,
                            name: components[0],
                            path: folderURL.appendingPathComponent(components[0]).path
                        )
                    }
                    parent = referencesDescriptor!
                    leaf = components[1]
                }
                let destinationPath = folderURL.appendingPathComponent(resource).path
                if try SecureResearchConfigurationIO.dataFileIfPresent(
                    parentDescriptor: parent,
                    leaf: leaf,
                    path: destinationPath,
                    maximumByteCount: 1_048_576
                ) == nil {
                    try SecureResearchConfigurationIO.createDataFile(
                        parentDescriptor: parent,
                        leaf: leaf,
                        data: try BundledResearchSkillResources.data(
                            directory: definition.resourceDirectory,
                            relativePath: resource
                        ),
                        path: destinationPath
                    )
                }
            }
            registrations.append(try ResearchSkillRegistration(
                actionID: definition.actionID,
                displayName: definition.displayName,
                primaryMarkdown: .triptychControl(
                    "skill-folders/\(folderName)/SKILL.md"
                ),
                skillFolder: .triptychControl("skill-folders/\(folderName)"),
                isEnabled: definition.isEnabled
            ))
        }
        try installPractices(controlURL: controlURL, rootDescriptor: root)
        guard fsync(root) == 0 else {
            throw ResearchConfigurationStoreError.unsafeStorage
        }
        return registrations
    }

    static func primarySource(for actionID: ResearchActionID) throws -> String {
        guard let definition = definitions.first(where: { $0.actionID == actionID }) else {
            throw ResearchConfigurationStoreError.invalidMethod(actionID.rawValue)
        }
        return String(
            decoding: try BundledResearchSkillResources.data(
                directory: definition.resourceDirectory,
                relativePath: "SKILL.md"
            ),
            as: UTF8.self
        )
    }

    private static func installPractices(
        controlURL: URL,
        rootDescriptor: Int32
    ) throws {
        let directory = try SecureResearchConfigurationIO.ensureDirectory(
            parentDescriptor: rootDescriptor,
            name: ResearchConfigurationStore.practicesDirectoryName,
            path: controlURL.appendingPathComponent(
                ResearchConfigurationStore.practicesDirectoryName
            ).path
        )
        defer { Darwin.close(directory) }
        for resource in practiceResources {
            let path = controlURL
                .appendingPathComponent(ResearchConfigurationStore.practicesDirectoryName)
                .appendingPathComponent(resource)
                .path
            if try SecureResearchConfigurationIO.dataFileIfPresent(
                parentDescriptor: directory,
                leaf: resource,
                path: path,
                maximumByteCount: 1_048_576
            ) == nil {
                try SecureResearchConfigurationIO.createDataFile(
                    parentDescriptor: directory,
                    leaf: resource,
                    data: try BundledResearchSkillResources.data(
                        directory: "Philosophical Practices",
                        relativePath: resource
                    ),
                    path: path
                )
            }
        }
    }

}
