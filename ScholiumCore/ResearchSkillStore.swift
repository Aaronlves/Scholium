import ScholiumContracts
import Foundation
import Yams

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
        ResearchSkillInspector.inspect(id: id, source: source, origin: origin)
    }

    public func skills() throws -> [ResearchSkillPackage] {
        let local = try validatedLocalSkills()
        let catalogPackages = try bundledCatalogPackages()
        let protectedIDs = Set(catalogPackages.map(\.id))
        let visibleLocal = local.map { package in
            guard protectedIDs.contains(package.id) else { return package }
            return ResearchSkillPackage(
                id: package.id,
                name: package.name,
                description: package.description,
                source: package.source,
                origin: package.origin,
                skillClass: package.skillClass,
                role: package.role,
                version: package.version,
                updatePolicy: package.updatePolicy,
                supportedModes: package.supportedModes,
                automaticModes: package.automaticModes,
                compatiblePracticeIDs: package.compatiblePracticeIDs,
                requiredSkillIDs: package.requiredSkillIDs,
                practiceResources: package.practiceResources,
                validationIssues: package.validationIssues + [
                    "This Triptych-local identifier conflicts with a protected Scholium package. Rename or delete the local package before it can be assembled."
                ],
                revision: package.revision
            )
        }
        let merged = catalogPackages + visibleLocal
        return merged.sorted {
            if $0.origin != $1.origin { return $0.origin.rawValue < $1.origin.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func create(id: String, source: String) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == id }) {
            throw ResearchSkillError.protectedPackageShadow(id)
        }
        let packageURL = try safePackageURL(id: id)
        try ensureSkillsDirectory()
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(id)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)
        try write(source, id: id, expectedRevision: nil, requiresExisting: false)
        return try localPackage(id: id)
    }

    public func duplicateBundled(id: String, as newID: String) throws -> ResearchSkillPackage {
        let entry: ResearchSkillCatalogEntry
        do {
            entry = try catalog().entry(id: id)
        } catch is ResearchSkillCatalogError {
            throw ResearchSkillError.packageNotFound(id)
        }
        guard entry.updatePolicy == "release-managed-duplicable"
                || entry.updatePolicy == "copy-on-adoption-researcher-owned" else {
            throw ResearchSkillError.bundledPackageIsNotDuplicable(id)
        }
        if newID != id, try catalog().entries.contains(where: { $0.id == newID }) {
            throw ResearchSkillError.protectedPackageShadow(newID)
        }
        let packageURL = try safePackageURL(id: newID)
        try ensureSkillsDirectory()
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(newID)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: false)
        do {
            for relativePath in try BundledResearchSkillLibrary.resourcePaths(for: entry) {
                let destination = packageURL.appendingPathComponent(relativePath)
                let parent = destination.deletingLastPathComponent()
                if parent != packageURL, !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
                }
                var source = try BundledResearchSkillLibrary.resource(
                    for: entry,
                    relativePath: relativePath
                )
                if relativePath == "SKILL.md" {
                    source = try Self.injectedResearcherRoutingMetadata(
                        into: source,
                        from: entry
                    )
                }
                try Data(source.utf8).write(to: destination, options: .atomic)
            }
            return try localPackage(id: newID)
        } catch {
            try? fileManager.removeItem(at: packageURL)
            throw error
        }
    }

    public func save(id: String, source: String, expectedRevision: DocumentFingerprint) throws -> ResearchSkillPackage {
        try write(source, id: id, expectedRevision: expectedRevision, requiresExisting: true)
        return try localPackage(id: id)
    }

    public func rename(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == newID }) {
            throw ResearchSkillError.protectedPackageShadow(newID)
        }
        let sourceURL = try existingRegularSkillURL(id: id, expectedRevision: expectedRevision)
        let sourcePackageURL = sourceURL.deletingLastPathComponent()
        let destinationPackageURL = try safePackageURL(id: newID)
        guard !fileManager.fileExists(atPath: destinationPackageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(newID)
        }
        try fileManager.moveItem(at: sourcePackageURL, to: destinationPackageURL)
        return try localPackage(id: newID)
    }

    public func delete(id: String, expectedRevision: DocumentFingerprint) throws {
        let sourceURL = try existingRegularSkillURL(id: id, expectedRevision: expectedRevision)
        try fileManager.removeItem(at: sourceURL.deletingLastPathComponent())
    }

    public func catalog() throws -> ResearchSkillCatalog {
        try BundledResearchSkillLibrary.catalog()
    }

    /// Returns one protected package by stable catalog identifier. This is
    /// the bounded package-retrieval API used by the CLI and Settings; it
    /// never searches a global Skill directory.
    public func bundledPackage(id: String) throws -> ResearchSkillPackage {
        let entry: ResearchSkillCatalogEntry
        do {
            entry = try catalog().entry(id: id)
        } catch {
            throw ResearchSkillError.packageNotFound(id)
        }
        do {
            return ResearchSkillInspector.inspect(
                id: entry.id,
                source: try BundledResearchSkillLibrary.source(for: entry),
                origin: .bundled,
                catalogEntry: entry,
                revision: try BundledResearchSkillLibrary.revision(for: entry)
            )
        } catch {
            throw ResearchSkillError.unsafePackage(id)
        }
    }

    /// Returns either one release-managed package or one direct
    /// Triptych-local package. No global Skill directory is searched.
    public func package(id: String) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == id }) {
            return try bundledPackage(id: id)
        }
        return try localPackage(id: id)
    }

    public func resourcePaths(id: String) throws -> [String] {
        if let entry = try? catalog().entry(id: id) {
            return try BundledResearchSkillLibrary.resourcePaths(for: entry)
        }
        let packageURL = try existingPackageURL(id: id)
        return try localResourcePaths(packageURL: packageURL)
    }

    public func resource(id: String, relativePath: String) throws -> String {
        if let entry = try? catalog().entry(id: id) {
            return try BundledResearchSkillLibrary.resource(
                for: entry,
                relativePath: relativePath
            )
        }
        guard ResearchSkillResourcePath.isAllowed(relativePath) else {
            throw ResearchSkillCatalogError.invalidResourcePath(relativePath)
        }
        let packageURL = try existingPackageURL(id: id)
        let resourceURL = packageURL.appendingPathComponent(relativePath).standardizedFileURL
        guard resourceURL.path.hasPrefix(packageURL.path + "/") else {
            throw ResearchSkillCatalogError.invalidResourcePath(relativePath)
        }
        let values = try resourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let source = try? String(contentsOf: resourceURL, encoding: .utf8) else {
            throw ResearchSkillCatalogError.resourceMissing(
                ".scholium/skills/\(id)/\(relativePath)"
            )
        }
        return source
    }

    public func resourceFingerprint(
        id: String,
        relativePath: String
    ) throws -> DocumentFingerprint {
        DocumentFingerprint(content: try resource(id: id, relativePath: relativePath))
    }

    /// Selectively assembles only the dependency closure for the requested
    /// mode. Official Workflow and Researcher packages are opt-in by ID;
    /// default mode assembly contains only the required protected System
    /// packages. Mixed mode keeps every phase in its own envelope.
    public func instructionAssembly(
        mode: ResearchSkillMode = .dialogue,
        requestedSkillIDs: [String] = [],
        mixedPhases: [ResearchSkillAssemblyPhase] = []
    ) throws -> String {
        let phaseSelections: [(ResearchSkillMode, [ResearchSkillPackage])]
        if mode == .mixed {
            guard !mixedPhases.isEmpty else {
                throw ResearchSkillCatalogError.mixedModeRequiresPhases
            }
            phaseSelections = try mixedPhases.map { phase in
                (
                    phase.mode,
                    try resolvedPackages(
                        for: phase.mode,
                        requestedSkillIDs: phase.skillIDs
                    )
                )
            }
        } else {
            phaseSelections = [(
                mode,
                try resolvedPackages(for: mode, requestedSkillIDs: requestedSkillIDs)
            )]
        }

        let renderedPhases = phaseSelections.map { phaseMode, packages in
            let rendered = packages.map { package in
                Self.render(id: package.id, source: package.source)
            }
            if mode == .mixed {
                return """
                <phase mode="\(phaseMode.rawValue)">
                \(rendered.joined(separator: "\n\n"))
                </phase>
                """
            }
            return rendered.joined(separator: "\n\n")
        }
        guard renderedPhases.contains(where: { !$0.isEmpty }) else { return "" }
        return (["Reusable research guidance (apply only when relevant):"] + renderedPhases)
            .joined(separator: "\n\n")
    }

    /// Resolves one phase against the combined protected and Triptych-local
    /// package graph. Local packages remain explicit-only; only protected
    /// System packages may activate automatically.
    public func resolvedPackages(
        for mode: ResearchSkillMode,
        requestedSkillIDs: [String]
    ) throws -> [ResearchSkillPackage] {
        guard mode != .mixed else {
            throw ResearchSkillCatalogError.mixedModeRequiresPhases
        }
        let protectedCatalog = try catalog()
        let bundled = try bundledCatalogPackages()
        let rawLocal = try localSkills()
        let protectedIDs = Set(bundled.map(\.id))
        if let shadow = rawLocal.first(where: { protectedIDs.contains($0.id) }) {
            throw ResearchSkillError.protectedPackageShadow(shadow.id)
        }
        let local = try validatedLocalSkills(rawLocal: rawLocal, bundled: bundled)
        let packages = bundled + local
        let byID = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
        let automatic = protectedCatalog.entries.filter {
            $0.skillClass == .system && $0.activatesAutomatically(in: mode)
        }.map(\.id)
        let seeds = Self.unique(automatic + requestedSkillIDs)
        var visiting: Set<String> = []
        var included: Set<String> = []
        var ordered: [ResearchSkillPackage] = []

        func visit(_ id: String) throws {
            guard let package = byID[id] else {
                throw ResearchSkillError.packageNotFound(id)
            }
            guard package.isValid else {
                throw ResearchSkillError.invalidPackage(id, package.validationIssues)
            }
            guard package.supports(mode) else {
                throw ResearchSkillCatalogError.unsupportedMode(skillID: id, mode: mode)
            }
            guard !included.contains(id) else { return }
            guard visiting.insert(id).inserted else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Dependency cycle includes \(id)."
                )
            }
            for dependency in package.requiredSkillIDs {
                try visit(dependency)
            }
            visiting.remove(id)
            included.insert(id)
            ordered.append(package)
        }

        for seed in seeds { try visit(seed) }
        return ordered
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
                return ResearchSkillInspector.inspect(
                    id: id,
                    source: "",
                    origin: .triptych,
                    additionalIssues: ["SKILL.md must be a regular file and must not be a symbolic link."]
                )
            }
            do {
                return try localPackage(id: id)
            } catch {
                return ResearchSkillInspector.inspect(
                    id: id,
                    source: "",
                    origin: .triptych,
                    additionalIssues: ["SKILL.md must contain valid UTF-8 text."]
                )
            }
        }
    }

    private func validatedLocalSkills() throws -> [ResearchSkillPackage] {
        try validatedLocalSkills(
            rawLocal: localSkills(),
            bundled: bundledCatalogPackages()
        )
    }

    private func validatedLocalSkills(
        rawLocal: [ResearchSkillPackage],
        bundled: [ResearchSkillPackage]
    ) throws -> [ResearchSkillPackage] {
        let protectedIDs = Set(bundled.map(\.id))
        let noncolliding = rawLocal.filter { !protectedIDs.contains($0.id) }
        let combined = bundled + noncolliding
        let byID = Dictionary(uniqueKeysWithValues: combined.map { ($0.id, $0) })

        func hasDependencyCycle(from root: String) -> Bool {
            var active: Set<String> = []
            var complete: Set<String> = []

            func visit(_ id: String) -> Bool {
                if active.contains(id) { return true }
                if complete.contains(id) { return false }
                guard let package = byID[id] else { return false }
                active.insert(id)
                for dependency in package.requiredSkillIDs where visit(dependency) {
                    return true
                }
                active.remove(id)
                complete.insert(id)
                return false
            }

            return visit(root)
        }

        return rawLocal.map { package in
            guard !protectedIDs.contains(package.id) else { return package }
            var issues: [String] = []
            for dependencyID in package.requiredSkillIDs {
                guard let dependency = byID[dependencyID] else {
                    issues.append("Required Skill does not exist: \(dependencyID).")
                    continue
                }
                if !dependency.isValid {
                    issues.append("Required Skill is structurally invalid: \(dependencyID).")
                }
                for mode in package.supportedModes where !dependency.supports(mode) {
                    issues.append(
                        "Required Skill \(dependencyID) does not support \(mode.rawValue) mode."
                    )
                }
            }
            if hasDependencyCycle(from: package.id) {
                issues.append("The package dependency graph contains a cycle.")
            }
            return package.addingValidationIssues(Self.unique(issues))
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
        _ = try String(contentsOf: sourceURL, encoding: .utf8)
        guard try packageRevision(packageURL: packageURL) == expectedRevision else {
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

    private func existingPackageURL(id: String) throws -> URL {
        let packageURL = try safePackageURL(id: id)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        try validateDirectory(packageURL, error: .unsafePackage(id))
        return packageURL
    }

    private func localPackage(id: String) throws -> ResearchSkillPackage {
        let packageURL = try existingPackageURL(id: id)
        let sourceURL = packageURL.appendingPathComponent("SKILL.md")
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResearchSkillError.unsafePackage(id)
        }
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let parsed = ResearchSkillInspector.inspect(
            id: id,
            source: source,
            origin: .triptych,
            revision: try packageRevision(packageURL: packageURL)
        )
        let resources = Set(try localResourcePaths(packageURL: packageURL))
        var issues: [String] = []
        if parsed.role == "practice" {
            for required in [
                "references/FOUNDATIONAL-DIMENSIONS.md",
                "references/COMPOSITION-RULES.md",
            ] where !resources.contains(required) {
                issues.append("Practice package requires \(required).")
            }
        }
        for path in parsed.practiceResources.values where !resources.contains(path) {
            issues.append("Declared Practice resource is missing: \(path).")
        }
        return parsed.addingValidationIssues(issues)
    }

    private func localResourcePaths(packageURL: URL) throws -> [String] {
        var paths: [String] = []
        let entryPoint = packageURL.appendingPathComponent("SKILL.md")
        let entryValues = try entryPoint.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        if entryValues.isRegularFile == true, entryValues.isSymbolicLink != true {
            paths.append("SKILL.md")
        }
        for directory in ["references", "templates"] {
            let directoryURL = packageURL.appendingPathComponent(directory, isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for file in files {
                let relativePath = "\(directory)/\(file.lastPathComponent)"
                let values = try file.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                )
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true,
                      ResearchSkillResourcePath.isAllowed(relativePath) else {
                    continue
                }
                paths.append(relativePath)
            }
        }
        return paths.sorted()
    }

    private func packageRevision(packageURL: URL) throws -> DocumentFingerprint {
        let paths = try localResourcePaths(packageURL: packageURL)
        var bytes = Data()
        for path in paths {
            let data = try Data(contentsOf: packageURL.appendingPathComponent(path))
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    private func bundledCatalogPackages() throws -> [ResearchSkillPackage] {
        try catalog().entries.map { entry in
            do {
                return ResearchSkillInspector.inspect(
                    id: entry.id,
                    source: try BundledResearchSkillLibrary.source(for: entry),
                    origin: .bundled,
                    catalogEntry: entry,
                    revision: try BundledResearchSkillLibrary.revision(for: entry)
                )
            } catch {
                return ResearchSkillInspector.inspect(
                    id: entry.id,
                    source: "",
                    origin: .bundled,
                    additionalIssues: [error.localizedDescription]
                )
            }
        }
    }

    private static func render(id: String, source: String) -> String {
        """
        <skill id="\(id)">
        \(source)
        </skill>
        """
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#, options: .regularExpression) != nil
    }

    private static func injectedResearcherRoutingMetadata(
        into source: String,
        from entry: ResearchSkillCatalogEntry
    ) throws -> String {
        let lines = source.components(separatedBy: .newlines)
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(of: "---") else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Bundled Skill \(entry.id) has malformed frontmatter."
            )
        }
        let yaml = lines[1..<closing].joined(separator: "\n")
        if let metadata = try Yams.load(yaml: yaml) as? [String: Any],
           metadata["scholium"] != nil {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Bundled Skill \(entry.id) already declares local scholium metadata."
            )
        }
        var routing = [
            "scholium:",
            "  role: \(entry.role)",
            "  supported_modes: [\(entry.supportedModes.map(\.rawValue).joined(separator: ", "))]",
            "  required_skills: [\(entry.requiredSkillIDs.joined(separator: ", "))]",
        ]
        if !entry.compatiblePracticeIDs.isEmpty {
            routing.append(
                "  compatible_practices: [\(entry.compatiblePracticeIDs.joined(separator: ", "))]"
            )
        }
        if !entry.practiceResources.isEmpty {
            routing.append("  practice_resources:")
            for identifier in entry.practiceResources.keys.sorted() {
                routing.append("    \(identifier): \(entry.practiceResources[identifier]!)")
            }
        }
        var result = Array(lines[...closing])
        result.insert(contentsOf: routing, at: closing)
        result.append(contentsOf: lines[(closing + 1)...])
        return result.joined(separator: "\n")
    }

}
