import ScholiumContracts
import Foundation
import Yams

/// Loads only the release-managed package resources bundled with ScholiumCore.
public enum BundledResearchSkillLibrary {
    public static func catalog() throws -> ResearchSkillCatalog {
        let root = try resourceRoot()
        let url = root.appendingPathComponent("catalog.yaml", isDirectory: false)
        guard let yaml = try? String(contentsOf: url, encoding: .utf8) else {
            throw ResearchSkillCatalogError.resourceMissing("Skills/catalog.yaml")
        }
        let catalog = try ResearchSkillCatalog.parse(yaml: yaml)
        for entry in catalog.entries where !entry.practiceResources.isEmpty {
            let available = Set(try resourcePaths(for: entry))
            for required in [
                "SKILL.md",
                "references/FOUNDATIONAL-DIMENSIONS.md",
                "references/COMPOSITION-RULES.md",
            ] where !available.contains(required) {
                throw ResearchSkillCatalogError.resourceMissing(
                    "\(entry.resourcePath)/\(required)"
                )
            }
            for path in entry.practiceResources.values where !available.contains(path) {
                throw ResearchSkillCatalogError.resourceMissing(
                    "\(entry.resourcePath)/\(path)"
                )
            }
        }
        for entry in catalog.entries where !entry.citationStyleResources.isEmpty {
            let available = Set(try resourcePaths(for: entry))
            for path in entry.citationStyleResources.values where !available.contains(path) {
                throw ResearchSkillCatalogError.resourceMissing(
                    "\(entry.resourcePath)/\(path)"
                )
            }
        }
        return catalog
    }

    public static func source(for entry: ResearchSkillCatalogEntry) throws -> String {
        try resource(for: entry, relativePath: "SKILL.md")
    }

    /// Returns the validated, package-relative resources available to an
    /// external agent. Resource discovery never leaves the catalog entry's
    /// bundled directory and rejects symlinks.
    public static func resourcePaths(
        for entry: ResearchSkillCatalogEntry
    ) throws -> [String] {
        let packageRoot = try packageRoot(for: entry)
        var paths: [String] = []
        let fileManager = FileManager.default
        let entryPoint = packageRoot.appendingPathComponent("SKILL.md")
        let entryValues = try entryPoint.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        if entryValues.isRegularFile == true, entryValues.isSymbolicLink != true {
            paths.append("SKILL.md")
        }
        for directory in ["references", "templates", "evals"] {
            let directoryURL = packageRoot.appendingPathComponent(directory, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files {
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      ResearchSkillResourcePath.isAllowed("\(directory)/\(file.lastPathComponent)") else {
                    continue
                }
                paths.append("\(directory)/\(file.lastPathComponent)")
            }
        }
        return paths.sorted()
    }

    /// Fingerprints the complete bounded text package rather than only its
    /// entry point. A duplicated or selected Practice can therefore record
    /// the exact method resources that were available for the task.
    public static func revision(
        for entry: ResearchSkillCatalogEntry
    ) throws -> DocumentFingerprint {
        var bytes = Data()
        for path in try resourcePaths(for: entry) {
            let source = try resource(for: entry, relativePath: path)
            let data = Data(source.utf8)
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    /// Loads one package resource by its validated relative path. Only the
    /// entry point and one-level package resources are exposed; callers must
    /// ask for a resource explicitly.
    public static func resource(
        for entry: ResearchSkillCatalogEntry,
        relativePath: String
    ) throws -> String {
        guard ResearchSkillResourcePath.isAllowed(relativePath) else {
            throw ResearchSkillCatalogError.invalidResourcePath(relativePath)
        }
        let packageRoot = try packageRoot(for: entry)
        let resourceURL = packageRoot
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL
        guard resourceURL.path.hasPrefix(packageRoot.path + "/") else {
            throw ResearchSkillCatalogError.invalidResourcePath(relativePath)
        }
        let values = try resourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let source = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            throw ResearchSkillCatalogError.resourceMissing(
                "Skills/\(entry.resourcePath)/\(relativePath)"
            )
        }
        return source
    }

    private static func packageRoot(for entry: ResearchSkillCatalogEntry) throws -> URL {
        let root = try resourceRoot()
        let packageRoot = root.appendingPathComponent(entry.resourcePath, isDirectory: true)
            .standardizedFileURL
        guard packageRoot.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw ResearchSkillCatalogError.resourceMissing(entry.resourcePath)
        }
        return packageRoot
    }

    private static func resourceRoot() throws -> URL {
        guard let root = Bundle.module.url(forResource: "Skills", withExtension: nil) else {
            throw ResearchSkillCatalogError.resourceMissing("Skills")
        }
        return root
    }
}
