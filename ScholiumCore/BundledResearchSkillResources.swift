import Foundation
import ScholiumContracts

public enum BundledResearchSkillResources {
    public static func coreProtocolSkillDirectoryURL() throws -> URL {
        try systemSkillDirectoryURL(.coreProtocol)
    }

    public static func systemSkillDirectoryURL(
        _ id: ResearchSystemSkillID
    ) throws -> URL {
        try skillDirectory("Scholium System Skills/\(id.rawValue)")
    }

    public static func systemSkillDirectoryURLs() throws
        -> [(id: ResearchSystemSkillID, url: URL)]
    {
        try ResearchSystemSkillID.allCases.map {
            ($0, try systemSkillDirectoryURL($0))
        }
    }

    static func data(
        directory: String,
        relativePath: String
    ) throws -> Data {
        let root = try skillDirectory(directory)
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw ResearchConfigurationStoreError.invalidMethod(relativePath)
        }
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResearchConfigurationStoreError.invalidMethod(url.path)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= 1_048_576,
              String(data: data, encoding: .utf8) != nil else {
            throw ResearchConfigurationStoreError.invalidMethod(url.path)
        }
        return data
    }

    private static func skillDirectory(_ directory: String) throws -> URL {
        guard let skillsRoot = Bundle.module.url(
            forResource: "Skills",
            withExtension: nil
        ) else {
            throw ResearchConfigurationStoreError.invalidMethod("bundled Skills")
        }
        let root = skillsRoot
            .appendingPathComponent(directory, isDirectory: true)
            .standardizedFileURL
        let values = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchConfigurationStoreError.invalidMethod(root.path)
        }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }
}
