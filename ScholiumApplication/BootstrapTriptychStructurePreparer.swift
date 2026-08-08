import Foundation

public enum BootstrapStructurePreparationError: LocalizedError {
    case invalidName
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName:
            "Enter a Triptych name that can be used as a folder name."
        case .destinationExists(let path):
            "A folder already exists at \(path). Choose Connect Existing Folders or use another name."
        }
    }
}

public struct BootstrapPreparedTriptychStructure: Equatable, Sendable {
    public let rootURL: URL
    public let analysesURL: URL
    public let topicsURL: URL
    public let worksURL: URL

    public init(
        rootURL: URL,
        analysesURL: URL,
        topicsURL: URL,
        worksURL: URL
    ) {
        self.rootURL = rootURL
        self.analysesURL = analysesURL
        self.topicsURL = topicsURL
        self.worksURL = worksURL
    }
}

/// Application-owned, non-overwriting creator for the one approved
/// create-new Bootstrap structure. The caller owns security-scope lifetime;
/// this actor owns only the bounded filesystem mutation.
public actor BootstrapTriptychStructurePreparer {
    private let fileManager = FileManager.default

    public init() {}

    public func prepare(
        parentURL: URL,
        name: String
    ) throws -> BootstrapPreparedTriptychStructure {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folderName = trimmedName.replacingOccurrences(of: "/", with: "-")
        guard !folderName.isEmpty, folderName != ".", folderName != ".." else {
            throw BootstrapStructurePreparationError.invalidName
        }

        let parent = parentURL.resolvingSymlinksInPath().standardizedFileURL
        let root = parent
            .appendingPathComponent(folderName, isDirectory: true)
            .standardizedFileURL
        guard root.deletingLastPathComponent().path == parent.path else {
            throw BootstrapStructurePreparationError.invalidName
        }
        guard !fileManager.fileExists(atPath: root.path) else {
            throw BootstrapStructurePreparationError.destinationExists(root.path)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        let portableControl = root.appendingPathComponent(".scholium", isDirectory: true)
        for folder in [analyses, topics, works, portableControl] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        return BootstrapPreparedTriptychStructure(
            rootURL: root,
            analysesURL: analyses,
            topicsURL: topics,
            worksURL: works
        )
    }
}
