import Foundation

public enum BundledResearchSkillResourceError: LocalizedError, Sendable {
    case unavailable
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The bundled Scholium Core Protocol is unavailable."
        case .invalid(let path):
            "The bundled Scholium Core Protocol is invalid at \(path)."
        }
    }
}

public enum BundledResearchSkillResources {
    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        guard let skillsRoot = Bundle.module.url(
            forResource: "Skills",
            withExtension: nil
        ) else {
            throw BundledResearchSkillResourceError.unavailable
        }
        let root = skillsRoot
            .appendingPathComponent(
                "Scholium System Skills/scholium-core-protocol",
                isDirectory: true
            )
            .standardizedFileURL
        let values = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw BundledResearchSkillResourceError.invalid(root.path)
        }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }
}
