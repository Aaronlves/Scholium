import Foundation
import Yams

public enum ResearchSkillOrigin: String, Sendable {
    case bundled
    case triptych
    case customizedBundled

    public var displayName: String {
        switch self {
        case .bundled: "Bundled"
        case .triptych, .customizedBundled: "Triptych"
        }
    }
}

public struct ResearchSkillPackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let source: String
    public let origin: ResearchSkillOrigin
    public let validationIssues: [String]
    public let revision: DocumentFingerprint?

    public var isValid: Bool { validationIssues.isEmpty }
    public var isTriptychLocal: Bool { origin != .bundled }

    public init(
        id: String,
        name: String,
        description: String,
        source: String,
        origin: ResearchSkillOrigin,
        validationIssues: [String] = [],
        revision: DocumentFingerprint? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
        self.origin = origin
        self.validationIssues = validationIssues
        self.revision = revision
    }
}

public enum ResearchSkillError: LocalizedError, Sendable {
    case invalidIdentifier(String)
    case unsafeSkillsRoot
    case unsafePackage(String)
    case packageNotFound(String)
    case packageAlreadyExists(String)
    case bundledPackageIsReadOnly(String)
    case stalePackage(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier(let id):
            "Skill identifiers must use 1–64 lowercase letters, numbers, or hyphens: \(id)"
        case .unsafeSkillsRoot:
            "The Triptych Skills folder is a symbolic link or is outside the portable control directory."
        case .unsafePackage(let id):
            "The skill package is not a safe regular package: \(id)"
        case .packageNotFound(let id):
            "The Triptych skill no longer exists: \(id)"
        case .packageAlreadyExists(let id):
            "A Triptych skill already uses the identifier \(id)."
        case .bundledPackageIsReadOnly(let id):
            "Bundled skill \(id) must be duplicated into the Triptych before editing."
        case .stalePackage(let id):
            "The skill changed on disk. Reload it before saving, renaming, or deleting: \(id)"
        }
    }
}

/// Owns the only supported user-skill root:
/// `.scholium/skills/<skill-id>/SKILL.md` beside the Works vault.
public actor ResearchSkillStore {
    public nonisolated let skillsURL: URL

    private let controlURL: URL
    private let fileManager: FileManager

    public init(controlURL: URL, fileManager: FileManager = .default) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL
            .appendingPathComponent("skills", isDirectory: true)
        self.fileManager = fileManager
    }

    public nonisolated static func inspect(
        id: String,
        source: String,
        origin: ResearchSkillOrigin = .triptych
    ) -> ResearchSkillPackage {
        parse(id: id, source: source, origin: origin)
    }

    public func skills() throws -> [ResearchSkillPackage] {
        let local = try localSkills()
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let merged = Self.bundledSkills.map { bundled in
            localByID[bundled.id] ?? bundled
        } + local.filter { local in
            !Self.bundledSkills.contains { $0.id == local.id }
        }
        return merged.sorted {
            if $0.origin != $1.origin { return $0.origin.rawValue < $1.origin.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func create(id: String, source: String) throws -> ResearchSkillPackage {
        let packageURL = try safePackageURL(id: id)
        try ensureSkillsDirectory()
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(id)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)
        try write(source, id: id, expectedRevision: nil, requiresExisting: false)
        return Self.parse(id: id, source: source, origin: origin(for: id))
    }

    public func duplicateBundled(id: String, as newID: String) throws -> ResearchSkillPackage {
        guard let bundled = Self.bundledSkills.first(where: { $0.id == id }) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        return try create(id: newID, source: bundled.source)
    }

    public func save(id: String, source: String, expectedRevision: DocumentFingerprint) throws -> ResearchSkillPackage {
        try write(source, id: id, expectedRevision: expectedRevision, requiresExisting: true)
        return Self.parse(id: id, source: source, origin: origin(for: id))
    }

    public func rename(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        let sourceURL = try existingRegularSkillURL(id: id, expectedRevision: expectedRevision)
        let sourcePackageURL = sourceURL.deletingLastPathComponent()
        let destinationPackageURL = try safePackageURL(id: newID)
        guard !fileManager.fileExists(atPath: destinationPackageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(newID)
        }
        try fileManager.moveItem(at: sourcePackageURL, to: destinationPackageURL)
        let source = try String(contentsOf: destinationPackageURL.appendingPathComponent("SKILL.md"), encoding: .utf8)
        return Self.parse(id: newID, source: source, origin: origin(for: newID))
    }

    public func delete(id: String, expectedRevision: DocumentFingerprint) throws {
        let sourceURL = try existingRegularSkillURL(id: id, expectedRevision: expectedRevision)
        try fileManager.removeItem(at: sourceURL.deletingLastPathComponent())
    }

    public func resetBundledCustomization(id: String, expectedRevision: DocumentFingerprint) throws {
        guard Self.bundledSkills.contains(where: { $0.id == id }) else {
            throw ResearchSkillError.bundledPackageIsReadOnly(id)
        }
        try delete(id: id, expectedRevision: expectedRevision)
    }

    public func instructionAssembly() throws -> String {
        let valid = try skills().filter(\.isValid)
        guard !valid.isEmpty else { return "" }
        let packages = valid.map { skill in
            """
            <skill id="\(skill.id)">
            \(skill.source)
            </skill>
            """
        }
        return (["Reusable research guidance (apply only when relevant):"] + packages)
            .joined(separator: "\n\n")
    }

    public func prepareSkillsFolder() throws -> URL {
        try ensureSkillsDirectory()
        return skillsURL
    }

    private func localSkills() throws -> [ResearchSkillPackage] {
        guard fileManager.fileExists(atPath: skillsURL.path) else { return [] }
        try validateDirectory(skillsURL, error: .unsafeSkillsRoot)
        let entries = try fileManager.contentsOfDirectory(
            at: skillsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return try entries.compactMap { packageURL in
            let id = packageURL.lastPathComponent
            guard Self.isValidIdentifier(id) else { return nil }
            let values = try packageURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let sourceURL = packageURL.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }
            let sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
                return Self.parse(
                    id: id,
                    source: "",
                    origin: origin(for: id),
                    additionalIssues: ["SKILL.md must be a regular file and must not be a symbolic link."]
                )
            }
            do {
                let source = try String(contentsOf: sourceURL, encoding: .utf8)
                return Self.parse(id: id, source: source, origin: origin(for: id))
            } catch {
                return Self.parse(
                    id: id,
                    source: "",
                    origin: origin(for: id),
                    additionalIssues: ["SKILL.md must contain valid UTF-8 text."]
                )
            }
        }
    }

    private func write(
        _ source: String,
        id: String,
        expectedRevision: DocumentFingerprint?,
        requiresExisting: Bool
    ) throws {
        let packageURL = try safePackageURL(id: id)
        let sourceURL = packageURL.appendingPathComponent("SKILL.md")
        if requiresExisting {
            guard let expectedRevision else { throw ResearchSkillError.stalePackage(id) }
            _ = try existingRegularSkillURL(id: id, expectedRevision: expectedRevision)
        } else {
            try validateDirectory(packageURL, error: .unsafePackage(id))
        }
        try Data(source.utf8).write(to: sourceURL, options: .atomic)
    }

    private func existingRegularSkillURL(
        id: String,
        expectedRevision: DocumentFingerprint
    ) throws -> URL {
        let packageURL = try safePackageURL(id: id)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        try validateDirectory(packageURL, error: .unsafePackage(id))
        let sourceURL = packageURL.appendingPathComponent("SKILL.md")
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResearchSkillError.unsafePackage(id)
        }
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        guard DocumentFingerprint(content: source) == expectedRevision else {
            throw ResearchSkillError.stalePackage(id)
        }
        return sourceURL
    }

    private func ensureSkillsDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: skillsURL.path) {
            try fileManager.createDirectory(at: skillsURL, withIntermediateDirectories: false)
        }
        try validateDirectory(skillsURL, error: .unsafeSkillsRoot)
    }

    private func safePackageURL(id: String) throws -> URL {
        guard Self.isValidIdentifier(id) else { throw ResearchSkillError.invalidIdentifier(id) }
        let url = skillsURL.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard url.deletingLastPathComponent() == skillsURL.standardizedFileURL else {
            throw ResearchSkillError.invalidIdentifier(id)
        }
        return url
    }

    private func validateDirectory(_ url: URL, error: ResearchSkillError) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw error }
    }

    private func origin(for id: String) -> ResearchSkillOrigin {
        Self.bundledSkills.contains(where: { $0.id == id }) ? .customizedBundled : .triptych
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    private static func parse(
        id: String,
        source: String,
        origin: ResearchSkillOrigin,
        additionalIssues: [String] = []
    ) -> ResearchSkillPackage {
        var issues = additionalIssues
        if !isValidIdentifier(id) {
            issues.append("The package identifier must use 1–64 lowercase letters, numbers, or hyphens.")
        }
        var name = id
        var description = ""
        let lines = source.components(separatedBy: .newlines)
        if lines.first != "---",
           !source.isEmpty {
            issues.append("SKILL.md must begin with YAML frontmatter delimited by ---.")
        } else if let closing = lines.dropFirst().firstIndex(of: "---") {
            let yaml = lines[1..<closing].joined(separator: "\n")
            do {
                let metadata = try Yams.load(yaml: yaml) as? [String: Any]
                name = (metadata?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                description = (metadata?["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.isEmpty { issues.append("Frontmatter requires a nonempty name.") }
                if description.isEmpty { issues.append("Frontmatter requires a nonempty description.") }
            } catch {
                issues.append("Frontmatter is malformed YAML: \(error.localizedDescription)")
            }
            let body = lines[(closing + 1)...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { issues.append("SKILL.md requires instruction content after frontmatter.") }
        } else if !source.isEmpty {
            issues.append("SKILL.md is missing its closing frontmatter delimiter.")
        }
        if source.isEmpty, issues.isEmpty { issues.append("SKILL.md is empty.") }
        return ResearchSkillPackage(
            id: id,
            name: name.isEmpty ? id : name,
            description: description,
            source: source,
            origin: origin,
            validationIssues: issues,
            revision: additionalIssues.isEmpty ? DocumentFingerprint(content: source) : nil
        )
    }

    private static let bundledSkills: [ResearchSkillPackage] = [
        parse(
            id: "scholium-source-fidelity",
            source: """
            ---
            name: Scholium Source Fidelity
            description: Preserve evidential layers, exact source, and explicit uncertainty in research work.
            ---
            Keep primary texts, cited passages, research notes, and your own reconstruction distinct. Do not attribute a claim, definition, objection, or dialectical role without support in the available source. Preserve exact Markdown and YAML outside the requested edit, and mark uncertainty explicitly.
            """,
            origin: .bundled
        ),
        parse(
            id: "scholium-triptych-editing",
            source: """
            ---
            name: Scholium Triptych Editing
            description: Apply Scholium's path, fingerprint, relationship, and recovery boundaries.
            ---
            Inspect current Triptych files before editing. Treat fingerprints as stale-write checks, not permission tokens. Keep neutral links and transitive paths evidentially neutral. Use explicit paths, preserve provenance, and do not edit `.scholium` machine files directly.
            """,
            origin: .bundled
        ),
    ]
}
