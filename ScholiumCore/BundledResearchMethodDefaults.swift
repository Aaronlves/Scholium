import Darwin
import Foundation
import ScholiumContracts

enum BundledResearchSkillDefaults {
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
            resources: [
                "SKILL.md",
                "references/method.md",
                "references/Argument-Reconstructionist.md",
                "references/Conceptual-Analyst.md",
                "references/Dialectical-Partner.md",
                "references/Research-Explorer.md",
            ]
        ),
        Definition(
            actionID: .analyze,
            displayName: "Analyze Note",
            resourceDirectory: "Scholium Method Skills/scholium-analyze",
            resources: [
                "SKILL.md",
                "references/method.md",
                "references/method-fit.md",
                "references/literature-recommendations.md",
                "references/Argument-Reconstructionist.md",
                "references/Conceptual-Analyst.md",
                "references/Historical-Interpreter.md",
                "references/Research-Explorer.md",
            ]
        ),
        Definition(
            actionID: .synthesize,
            displayName: "Synthesize",
            resourceDirectory: "Scholium Method Skills/scholium-synthesize",
            resources: [
                "SKILL.md",
                "references/method.md",
                "references/Conceptual-Analyst.md",
                "references/Dialectical-Partner.md",
                "references/Systematizer.md",
            ]
        ),
        Definition(
            actionID: .write,
            displayName: "Write",
            resourceDirectory: "Scholium Method Skills/scholium-write",
            resources: [
                "SKILL.md",
                "references/method.md",
                "references/genre-and-revision.md",
                "references/feedback.md",
                "references/Dialectical-Partner.md",
                "references/Philosophical-Expositor.md",
                "references/Systematizer.md",
                "references/Thesis-Architect.md",
            ]
        ),
        Definition(
            actionID: .critique,
            displayName: "Critique",
            resourceDirectory: "Scholium Method Skills/scholium-critique",
            resources: [
                "SKILL.md",
                "references/method.md",
                "references/Argument-Reconstructionist.md",
                "references/Conceptual-Analyst.md",
                "references/Dialectical-Partner.md",
                "references/Reviewer.md",
            ]
        ),
        Definition(
            actionID: .checkFidelity,
            displayName: "Check Fidelity",
            resourceDirectory: "Scholium Method Skills/scholium-content-fidelity",
            resources: [
                "SKILL.md",
                "references/content.md",
                "references/citations.md",
                "references/Argument-Reconstructionist.md",
                "references/Conceptual-Analyst.md",
                "references/Historical-Interpreter.md",
            ]
        ),
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
                let destinationURLPath = folderURL.appendingPathComponent(resource).path
                if try SecureResearchConfigurationIO.dataFileIfPresent(
                    parentDescriptor: parent,
                    leaf: leaf,
                    path: destinationURLPath,
                    maximumByteCount: 1_048_576
                ) == nil {
                    try SecureResearchConfigurationIO.createDataFile(
                        parentDescriptor: parent,
                        leaf: leaf,
                        data: try BundledResearchSkillResources.data(
                            directory: definition.resourceDirectory,
                            relativePath: resource
                        ),
                        path: destinationURLPath
                    )
                }
            }
            registrations.append(try ResearchSkillRegistration(
                actionID: definition.actionID,
                displayName: definition.displayName,
                skillFolder: .triptychControl("skill-folders/\(folderName)"),
                isEnabled: definition.isEnabled
            ))
        }
        guard fsync(root) == 0 else {
            throw ResearchConfigurationStoreError.unsafeStorage
        }
        return registrations
    }

}
