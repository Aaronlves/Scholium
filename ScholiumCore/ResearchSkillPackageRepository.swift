import Darwin
import Foundation
import ScholiumContracts
import Yams

/// Owns bounded discovery and mutation of protected and Triptych-local Skill
/// packages. Callers serialize access; this value introduces no second writer.
struct ResearchSkillPackageRepository {
    let controlURL: URL
    let skillsURL: URL
    let fileManager: FileManager
    let resolver: ResearchSkillResolver

    init(
        controlURL: URL,
        fileManager: FileManager,
        resolver: ResearchSkillResolver
    ) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL.appendingPathComponent(
            "skills",
            isDirectory: true
        )
        self.fileManager = fileManager
        self.resolver = resolver
    }

    func packages() throws -> [ResearchSkillPackage] {
        let local = try validatedLocalPackages()
        let protected = try bundledPackages()
        let protectedIDs = Set(protected.map(\.id))
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
                supportedActions: package.supportedActions,
                supportedFunctions: package.supportedFunctions,
                capabilities: package.capabilities,
                citationStyles: package.citationStyles,
                citationStyleResources: package.citationStyleResources,
                allowsEvolution: package.allowsEvolution,
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
        return (protected + visibleLocal).sorted {
            if $0.origin != $1.origin {
                return $0.origin.rawValue < $1.origin.rawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func create(id: String, source: String) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == id }) {
            throw ResearchSkillError.protectedPackageShadow(id)
        }
        let packageURL = try safePackageURL(id: id)
        try ensureSkillsDirectory()
        guard !fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(id)
        }
        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: false
        )
        try write(
            source,
            id: id,
            expectedRevision: nil,
            requiresExisting: false
        )
        return try localPackage(id: id)
    }

    func duplicateBundled(
        id: String,
        as newID: String
    ) throws -> ResearchSkillPackage {
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
        try fileManager.createDirectory(
            at: packageURL,
            withIntermediateDirectories: false
        )
        do {
            for relativePath in try BundledResearchSkillLibrary.resourcePaths(
                for: entry
            ) {
                let destination = packageURL.appendingPathComponent(relativePath)
                let parent = destination.deletingLastPathComponent()
                if parent != packageURL,
                   !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(
                        at: parent,
                        withIntermediateDirectories: false
                    )
                }
                var source = try BundledResearchSkillLibrary.resource(
                    for: entry,
                    relativePath: relativePath
                )
                if relativePath == "SKILL.md" {
                    source = try injectedResearcherRoutingMetadata(
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

    func save(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        try write(
            source,
            id: id,
            expectedRevision: expectedRevision,
            requiresExisting: true
        )
        return try localPackage(id: id)
    }

    func rename(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == newID }) {
            throw ResearchSkillError.protectedPackageShadow(newID)
        }
        let sourceURL = try existingRegularSkillURL(
            id: id,
            expectedRevision: expectedRevision
        )
        let sourcePackageURL = sourceURL.deletingLastPathComponent()
        let destinationPackageURL = try safePackageURL(id: newID)
        guard !fileManager.fileExists(atPath: destinationPackageURL.path) else {
            throw ResearchSkillError.packageAlreadyExists(newID)
        }
        try fileManager.moveItem(at: sourcePackageURL, to: destinationPackageURL)
        return try localPackage(id: newID)
    }

    func catalog() throws -> ResearchSkillCatalog {
        try BundledResearchSkillLibrary.catalog()
    }

    func bundledPackage(id: String) throws -> ResearchSkillPackage {
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

    func package(id: String) throws -> ResearchSkillPackage {
        if try catalog().entries.contains(where: { $0.id == id }) {
            return try bundledPackage(id: id)
        }
        return try localPackage(id: id)
    }

    func resourcePaths(id: String) throws -> [String] {
        if let entry = try? catalog().entry(id: id) {
            return try BundledResearchSkillLibrary.resourcePaths(for: entry)
        }
        return try localResourcePaths(packageURL: existingPackageURL(id: id))
    }

    func resource(id: String, relativePath: String) throws -> String {
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
        let resourceURL = packageURL.appendingPathComponent(relativePath)
            .standardizedFileURL
        guard resourceURL.path.hasPrefix(packageURL.path + "/") else {
            throw ResearchSkillCatalogError.invalidResourcePath(relativePath)
        }
        let values = try resourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let source = try? String(
                  contentsOf: resourceURL,
                  encoding: .utf8
              ) else {
            throw ResearchSkillCatalogError.resourceMissing(
                ".scholium/skills/\(id)/\(relativePath)"
            )
        }
        return source
    }

    func resourceFingerprint(
        id: String,
        relativePath: String
    ) throws -> DocumentFingerprint {
        DocumentFingerprint(
            content: try resource(id: id, relativePath: relativePath)
        )
    }

    func prepareSkillsFolder() throws -> URL {
        try ensureSkillsDirectory()
        return skillsURL
    }

    func localPackages() throws -> [ResearchSkillPackage] {
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
            let values = try packageURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                return nil
            }
            let sourceURL = packageURL.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                return nil
            }
            let sourceValues = try sourceURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard sourceValues.isRegularFile == true,
                  sourceValues.isSymbolicLink != true else {
                return ResearchSkillInspector.inspect(
                    id: id,
                    source: "",
                    origin: .triptych,
                    additionalIssues: [
                        "SKILL.md must be a regular file and must not be a symbolic link."
                    ]
                )
            }
            do {
                return try localPackage(id: id)
            } catch {
                return ResearchSkillInspector.inspect(
                    id: id,
                    source: "",
                    origin: .triptych,
                    additionalIssues: [
                        "SKILL.md must contain valid UTF-8 text."
                    ]
                )
            }
        }
    }

    func validatedLocalPackages() throws -> [ResearchSkillPackage] {
        resolver.validatedLocalPackages(
            try localPackages(),
            bundled: try bundledPackages()
        )
    }

    func validatedProposedPackage(
        id: String,
        sources: [String: String],
        revision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        guard Self.isValidIdentifier(id) else {
            throw ResearchSkillError.invalidIdentifier(id)
        }
        if try catalog().entries.contains(where: { $0.id == id }) {
            throw ResearchSkillError.protectedPackageShadow(id)
        }
        guard sources.keys.allSatisfy(ResearchSkillMaintenancePath.isAllowed),
              let source = sources["SKILL.md"],
              packageRevision(sources: sources) == revision else {
            throw ResearchSkillError.unsafePackage(id)
        }

        let inspected = ResearchSkillInspector.inspect(
            id: id,
            source: source,
            origin: .triptych,
            revision: revision
        )
        let candidate = inspected.addingValidationIssues(
            Self.declaredResourceValidationIssues(
                for: inspected,
                availableResourcePaths: Set(sources.keys)
            )
        )
        let bundled = try bundledPackages()
        let local = try localPackages().filter { $0.id != id } + [candidate]
        let validated = resolver.validatedLocalPackages(local, bundled: bundled)
        guard let result = validated.first(where: { $0.id == id }) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        return result
    }

    func localPackage(id: String) throws -> ResearchSkillPackage {
        let packageURL = try existingPackageURL(id: id)
        let sourceURL = packageURL.appendingPathComponent("SKILL.md")
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw ResearchSkillError.unsafePackage(id)
        }
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let parsed = ResearchSkillInspector.inspect(
            id: id,
            source: source,
            origin: .triptych,
            revision: try packageRevision(packageURL: packageURL)
        )
        return parsed.addingValidationIssues(
            Self.declaredResourceValidationIssues(
                for: parsed,
                availableResourcePaths: Set(
                    try localResourcePaths(packageURL: packageURL)
                )
            )
        )
    }

    func safePackageURL(id: String) throws -> URL {
        guard Self.isValidIdentifier(id) else {
            throw ResearchSkillError.invalidIdentifier(id)
        }
        let url = skillsURL.appendingPathComponent(
            id,
            isDirectory: true
        ).standardizedFileURL
        guard url.deletingLastPathComponent() == skillsURL.standardizedFileURL else {
            throw ResearchSkillError.invalidIdentifier(id)
        }
        return url
    }

    func existingRegularSkillURL(
        id: String,
        expectedRevision: DocumentFingerprint
    ) throws -> URL {
        let packageURL = try safePackageURL(id: id)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        try validateDirectory(packageURL, error: .unsafePackage(id))
        let sourceURL = packageURL.appendingPathComponent("SKILL.md")
        let values = try sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw ResearchSkillError.unsafePackage(id)
        }
        _ = try String(contentsOf: sourceURL, encoding: .utf8)
        guard try packageRevision(packageURL: packageURL) == expectedRevision else {
            throw ResearchSkillError.stalePackage(id)
        }
        return sourceURL
    }

    func ensureSkillsDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
        }
        if !fileManager.fileExists(atPath: skillsURL.path) {
            try fileManager.createDirectory(
                at: skillsURL,
                withIntermediateDirectories: false
            )
        }
        try validateDirectory(skillsURL, error: .unsafeSkillsRoot)
    }

    func packageRevision(sources: [String: String]) -> DocumentFingerprint {
        var bytes = Data()
        for path in sources.keys.sorted() {
            let data = Data((sources[path] ?? "").utf8)
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    func workingMethodSources(
        bundledPackageID: String,
        actionID: ResearchActionID,
        function: ResearchFunctionID,
        workingPackageID: String
    ) throws -> [String: String] {
        let entry = try catalog().entry(id: bundledPackageID)
        guard entry.skillClass == .method,
              entry.supportedActions == [actionID],
              entry.supportedFunctions == [function] else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Bundled reference \(bundledPackageID) is not the unique Method for \(actionID.rawValue)."
            )
        }
        var sources: [String: String] = [:]
        for path in try BundledResearchSkillLibrary.resourcePaths(for: entry) {
            var source = try BundledResearchSkillLibrary.resource(
                for: entry,
                relativePath: path
            )
            if path == "SKILL.md" {
                source = try injectedResearcherRoutingMetadata(
                    into: source,
                    from: entry,
                    allowsEvolution: true
                )
                source = try replacingSkillName(
                    in: source,
                    with: workingPackageID
                )
            }
            sources[path] = source
        }
        return sources
    }

    func installLocalPackage(
        id: String,
        sources: [String: String],
        onPublished: ((SecureResearchSkillPackageIO.DirectoryIdentity) -> Void)? = nil
    ) throws -> (
        package: ResearchSkillPackage,
        identity: SecureResearchSkillPackageIO.DirectoryIdentity
    ) {
        guard Self.isValidIdentifier(id),
              !sources.isEmpty,
              sources.keys.allSatisfy(ResearchSkillMaintenancePath.isAllowed) else {
            throw ResearchSkillError.unsafePackage(id)
        }
        try ensureSkillsDirectory()
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsURL.path
        )
        guard try !SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        ) else {
            throw ResearchSkillError.packageAlreadyExists(id)
        }
        let stageName = ".working-install-\(id)-\(UUID().uuidString.lowercased())"
        var didInstall = false
        do {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: rootDescriptor,
                packageName: stageName,
                sources: sources
            )
            let stageDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: stageName,
                path: stageName
            )
            let stageIdentity: SecureResearchSkillPackageIO.DirectoryIdentity
            do {
                stageIdentity = try SecureResearchSkillPackageIO.identity(
                    of: stageDescriptor,
                    path: stageName
                )
                Darwin.close(stageDescriptor)
            } catch {
                Darwin.close(stageDescriptor)
                throw error
            }
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: stageName
            ) == sources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ),
                  try !SecureResearchSkillPackageIO.directoryExists(
                      parentDescriptor: rootDescriptor,
                      name: id,
                      path: id
                  ) else {
                throw ResearchSkillError.packageAlreadyExists(id)
            }
            try SecureResearchSkillPackageIO.movePackageExclusively(
                rootDescriptor: rootDescriptor,
                source: stageName,
                destination: id
            )
            didInstall = true
            onPublished?(stageIdentity)
            let installedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: id,
                path: id
            )
            defer { Darwin.close(installedDescriptor) }
            let installedIdentity = try SecureResearchSkillPackageIO.identity(
                of: installedDescriptor,
                path: id
            )
            guard installedIdentity == stageIdentity,
                  fsync(rootDescriptor) == 0,
                  try SecureResearchSkillPackageIO.strictPackageSources(
                      packageDescriptor: installedDescriptor,
                      packageID: id
                  ) == sources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError
                    .workingMethodEditRecoveryRequired(id)
            }
            let installed = try localPackage(id: id)
            let recheckedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: id,
                path: id
            )
            defer { Darwin.close(recheckedDescriptor) }
            guard installed.revision == packageRevision(sources: sources),
                  try SecureResearchSkillPackageIO.identity(
                      of: recheckedDescriptor,
                      path: id
                  ) == installedIdentity,
                  try SecureResearchSkillPackageIO.strictPackageSources(
                      packageDescriptor: recheckedDescriptor,
                      packageID: id
                  ) == sources else {
                throw ResearchSkillBindingError
                    .workingMethodEditRecoveryRequired(id)
            }
            return (installed, installedIdentity)
        } catch {
            if !didInstall {
                try? SecureResearchSkillPackageIO.removePackage(
                    rootDescriptor: rootDescriptor,
                    packageName: stageName
                )
            }
            throw error
        }
    }

    static func declaredResourceValidationIssues(
        for package: ResearchSkillPackage,
        availableResourcePaths: Set<String>
    ) -> [String] {
        var issues: [String] = []
        for path in package.practiceResources.values
            where !availableResourcePaths.contains(path) {
            issues.append("Declared Practice resource is missing: \(path).")
        }
        for (style, path) in package.citationStyleResources {
            if !package.citationStyles.contains(style) {
                issues.append(
                    "Citation style resource \(style) is not declared in citation_styles."
                )
            }
            if !availableResourcePaths.contains(path) {
                issues.append(
                    "Declared citation style resource is missing for \(style): \(path)."
                )
            }
        }
        for style in package.citationStyles
            where package.citationStyleResources[style] == nil {
            issues.append(
                "Citation style \(style) has no declared citation style resource."
            )
        }
        return Self.unique(issues)
    }

    private func existingPackageURL(id: String) throws -> URL {
        let packageURL = try safePackageURL(id: id)
        guard fileManager.fileExists(atPath: packageURL.path) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        try validateDirectory(packageURL, error: .unsafePackage(id))
        return packageURL
    }

    private func validateDirectory(
        _ url: URL,
        error: ResearchSkillError
    ) throws {
        let values = try url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw error
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
            guard let expectedRevision else {
                throw ResearchSkillError.stalePackage(id)
            }
            _ = try existingRegularSkillURL(
                id: id,
                expectedRevision: expectedRevision
            )
        } else {
            try validateDirectory(packageURL, error: .unsafePackage(id))
        }
        try Data(source.utf8).write(to: sourceURL, options: .atomic)
    }

    private func localResourcePaths(packageURL: URL) throws -> [String] {
        var paths: [String] = []
        let entryPoint = packageURL.appendingPathComponent("SKILL.md")
        let entryValues = try entryPoint.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        if entryValues.isRegularFile == true,
           entryValues.isSymbolicLink != true {
            paths.append("SKILL.md")
        }
        for directory in ["references", "templates", "evals"] {
            let directoryURL = packageURL.appendingPathComponent(
                directory,
                isDirectory: true
            )
            guard let files = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
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
            let data = try Data(
                contentsOf: packageURL.appendingPathComponent(path)
            )
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    func bundledPackages() throws -> [ResearchSkillPackage] {
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

    private func replacingSkillName(
        in source: String,
        with packageID: String
    ) throws -> String {
        var lines = source.components(separatedBy: .newlines)
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(of: "---"),
              let nameIndex = lines[1..<closing].firstIndex(where: {
                  $0.hasPrefix("name:")
              }) else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Bundled Working Method has no replaceable name field."
            )
        }
        lines[nameIndex] = "name: \(packageID)"
        return lines.joined(separator: "\n")
    }

    private func injectedResearcherRoutingMetadata(
        into source: String,
        from entry: ResearchSkillCatalogEntry,
        allowsEvolution: Bool = false
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
            "  supported_actions: [\(entry.supportedActions.map(\.rawValue).joined(separator: ", "))]",
            "  supported_functions: [\(entry.supportedFunctions.map(\.rawValue).joined(separator: ", "))]",
            "  capabilities: [\(entry.capabilities.map(\.rawValue).joined(separator: ", "))]",
            "  citation_styles: [\(entry.citationStyles.joined(separator: ", "))]",
            "  allow_evolution: \(allowsEvolution ? "true" : "false")",
            "  supported_modes: [\(entry.supportedModes.map(\.rawValue).joined(separator: ", "))]",
            "  required_skills: [\(entry.requiredSkillIDs.joined(separator: ", "))]",
        ]
        if !entry.citationStyleResources.isEmpty {
            routing.append("  citation_style_resources:")
            for style in entry.citationStyleResources.keys.sorted() {
                routing.append(
                    "    \(style): \(entry.citationStyleResources[style]!)"
                )
            }
        }
        if !entry.compatiblePracticeIDs.isEmpty {
            routing.append(
                "  compatible_practices: [\(entry.compatiblePracticeIDs.joined(separator: ", "))]"
            )
        }
        if !entry.practiceResources.isEmpty {
            routing.append("  practice_resources:")
            for identifier in entry.practiceResources.keys.sorted() {
                routing.append(
                    "    \(identifier): \(entry.practiceResources[identifier]!)"
                )
            }
        }
        var result = Array(lines[...closing])
        result.insert(contentsOf: routing, at: closing)
        result.append(contentsOf: lines[(closing + 1)...])
        return result.joined(separator: "\n")
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
