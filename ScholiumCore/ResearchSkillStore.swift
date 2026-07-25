import ScholiumContracts
import Darwin
import Foundation
import Yams

enum ResearchWorkingMethodStoreFaultPoint: Sendable {
    case beforePackageReplacement(packageID: String)
    case afterPackageReplacement(packageID: String)
    case afterDisplacedPackageArchive(packageID: String)
    case afterBindingCommit
    case afterActionProfileCommit
    case beforeFunctionPackageResolution(actionID: ResearchActionID)
}

struct ResearchWorkingMethodStoreHooks: Sendable {
    let handler: @Sendable (ResearchWorkingMethodStoreFaultPoint) throws -> Void

    static let none = Self { _ in }
}

private enum ResearchWorkingMethodBindingWriteFailure: Error {
    case committed(
        snapshot: ResearchWorkingMethodBindingSnapshot?,
        underlying: any Error
    )
}

/// Owns the only supported Triptych-local Skill root:
/// `.scholium/skills/<skill-id>/SKILL.md` beside the Works vault.
public actor ResearchSkillStore {
    public nonisolated let skillsURL: URL
    public nonisolated let bindingsURL: URL
    public nonisolated let workingMethodBindingsURL: URL
    public nonisolated let actionProfileBindingsURL: URL

    private let controlURL: URL
    private let fileManager: FileManager
    private let workingMethodHooks: ResearchWorkingMethodStoreHooks
    private let workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore?

    public init(
        controlURL: URL,
        fileManager: FileManager = .default,
        workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore? = nil
    ) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL
            .appendingPathComponent("skills", isDirectory: true)
        self.bindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent("research-skill-bindings.json", isDirectory: false)
        self.workingMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            )
        self.actionProfileBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-action-profiles-v1.json",
                isDirectory: false
            )
        self.fileManager = fileManager
        workingMethodHooks = .none
        self.workingMethodRecoveryStore = workingMethodRecoveryStore
    }

    init(
        controlURL: URL,
        fileManager: FileManager = .default,
        workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore? = nil,
        workingMethodHooks: ResearchWorkingMethodStoreHooks
    ) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL
            .appendingPathComponent("skills", isDirectory: true)
        self.bindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent("research-skill-bindings.json", isDirectory: false)
        self.workingMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            )
        self.actionProfileBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-action-profiles-v1.json",
                isDirectory: false
            )
        self.fileManager = fileManager
        self.workingMethodRecoveryStore = workingMethodRecoveryStore
        self.workingMethodHooks = workingMethodHooks
    }

    public nonisolated static func inspectDraft(
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
        _ = try validatePackageIsUnused(id)
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
        let usage = try validatePackageIsUnused(id)
        try ensureSkillsDirectory()
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsURL.path
        )
        let packageDescriptor = try SecureResearchSkillPackageIO.openDirectory(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        )
        let packageIdentity: SecureResearchSkillPackageIO.DirectoryIdentity
        let sources: [String: String]
        do {
            packageIdentity = try SecureResearchSkillPackageIO.identity(
                of: packageDescriptor,
                path: id
            )
            sources = try SecureResearchSkillPackageIO.strictPackageSources(
                packageDescriptor: packageDescriptor,
                packageID: id
            )
            Darwin.close(packageDescriptor)
        } catch {
            Darwin.close(packageDescriptor)
            throw error
        }
        guard Self.packageRevision(sources: sources) == expectedRevision else {
            throw ResearchSkillError.stalePackage(id)
        }

        let recheckedUsage = try validatePackageIsUnused(id)
        let recheckedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        )
        defer { Darwin.close(recheckedDescriptor) }
        guard usage == recheckedUsage,
              try SecureResearchSkillPackageIO.identity(
                  of: recheckedDescriptor,
                  path: id
              ) == packageIdentity,
              try SecureResearchSkillPackageIO.strictPackageSources(
                  packageDescriptor: recheckedDescriptor,
                  packageID: id
              ) == sources,
              try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                  skillsURL,
                  identity: rootIdentity
              ) else {
            throw ResearchSkillError.stalePackage(id)
        }

        let isolatedName = ".deleting-\(id)-\(UUID().uuidString.lowercased())"
        var isolated = false
        do {
            try SecureResearchSkillPackageIO.movePackageExclusively(
                rootDescriptor: rootDescriptor,
                source: id,
                destination: isolatedName
            )
            isolated = true
            guard fsync(rootDescriptor) == 0,
                  try !SecureResearchSkillPackageIO.directoryExists(
                      parentDescriptor: rootDescriptor,
                      name: id,
                      path: id
                  ) else {
                throw ResearchSkillError.packageDeletionRecoveryRequired(id)
            }
            let isolatedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: isolatedName,
                path: isolatedName
            )
            defer { Darwin.close(isolatedDescriptor) }
            guard try SecureResearchSkillPackageIO.identity(
                of: isolatedDescriptor,
                path: isolatedName
            ) == packageIdentity,
                  try SecureResearchSkillPackageIO.strictPackageSources(
                      packageDescriptor: isolatedDescriptor,
                      packageID: isolatedName
                  ) == sources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillError.packageDeletionRecoveryRequired(id)
            }
            if let workingMethodRecoveryStore {
                let reservation = workingMethodRecoveryStore.reserve(
                    packageID: id,
                    packageRevision: expectedRevision
                )
                try workingMethodRecoveryStore.archive(
                    sourceParentDescriptor: rootDescriptor,
                    sourceName: isolatedName,
                    reservation: reservation
                )
            }
            // Stores without a machine-local recovery owner are used only by
            // bounded Core fixtures. Keep their isolated hidden package rather
            // than recursively deleting bytes that an external descriptor may
            // still be changing.
        } catch {
            if isolated {
                throw ResearchSkillError.packageDeletionRecoveryRequired(id)
            }
            throw error
        }
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

    public func bindingSnapshot() throws -> ResearchSkillBindingSnapshot? {
        guard fileManager.fileExists(atPath: bindingsURL.path) else { return nil }
        let values = try bindingsURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        let data = try Data(contentsOf: bindingsURL)
        let document: ResearchSkillBindingDocument
        do {
            document = try JSONDecoder().decode(ResearchSkillBindingDocument.self, from: data)
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "The JSON cannot be decoded. \(error.localizedDescription)"
            )
        }
        try validateBindingDocument(document)
        return ResearchSkillBindingSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    /// Returns the revision of a safe binding file without decoding it. This
    /// is intentionally available for revision-checked repair of malformed
    /// researcher-controlled JSON.
    public func bindingFileRevision() throws -> DocumentFingerprint? {
        guard fileManager.fileExists(atPath: bindingsURL.path) else { return nil }
        let values = try bindingsURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        return DocumentFingerprint(data: try Data(contentsOf: bindingsURL))
    }

    @discardableResult
    public func saveBindingDocument(
        _ document: ResearchSkillBindingDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        try validateBindingDocument(document)
        try ensureControlDirectoryForGuidance()
        if fileManager.fileExists(atPath: bindingsURL.path) {
            let values = try bindingsURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let current = try Data(contentsOf: bindingsURL)
            guard let expectedRevision,
                  DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchSkillBindingError.staleBindingFile
            }
        } else if expectedRevision != nil {
            throw ResearchSkillBindingError.staleBindingFile
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        try data.write(to: bindingsURL, options: .atomic)
        let readback = try Data(contentsOf: bindingsURL)
        guard readback == data else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        return ResearchSkillBindingSnapshot(
            document: document,
            revision: DocumentFingerprint(data: readback)
        )
    }

    /// Activates one installed Triptych-local citation package while
    /// preserving function bindings. The raw expected revision permits a
    /// malformed but safe binding document to be replaced deliberately.
    @discardableResult
    public func activateCitationBinding(
        packageID: String,
        citationStyle: String? = nil,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        let observed = try bindingFileRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let package = try localPackage(id: packageID)
        let normalizedStyle = citationStyle?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard package.origin == .triptych,
              package.isValid,
              package.supports(.fidelity),
              package.provides(.citationVerification),
              package.provides(.citationFormatting),
              let normalizedStyle,
              package.citationStyles.contains(normalizedStyle),
              package.citationStyleResources[normalizedStyle] != nil else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "The selected package and style are not a valid installed citation method."
            )
        }
        let existing = (try? bindingSnapshot()?.document)
            ?? ResearchSkillBindingDocument()
        let replacement = ResearchSkillBindingDocument(
            functionBindings: existing.functionBindings,
            functionSkillBindings: existing.functionSkillBindings,
            functionPracticeBindings: existing.functionPracticeBindings,
            citationBinding: packageID,
            citationStyle: normalizedStyle,
            bibliographyMethodBinding: existing.bibliographyMethodBinding
        )
        return try saveBindingDocument(
            replacement,
            expectedRevision: expectedBindingRevision
        )
    }

    /// Clears the active citation package through the same revision-checked
    /// repair path. A safe malformed file is replaced by a valid empty binding
    /// document rather than edited in place.
    @discardableResult
    public func clearCitationBinding(
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        let observed = try bindingFileRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let existing = (try? bindingSnapshot()?.document)
            ?? ResearchSkillBindingDocument()
        return try saveBindingDocument(
            ResearchSkillBindingDocument(
                functionBindings: existing.functionBindings,
                functionSkillBindings: existing.functionSkillBindings,
                functionPracticeBindings: existing.functionPracticeBindings,
                citationBinding: nil,
                citationStyle: nil,
                bibliographyMethodBinding: existing.bibliographyMethodBinding
            ),
            expectedRevision: expectedBindingRevision
        )
    }

    /// Creates a noncolliding Triptych-local copy of the bundled APA starter
    /// and activates it as one transaction from the caller's perspective. A
    /// failed binding write removes only the just-created package.
    public func adoptAPACitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillCitationAdoption {
        let observed = try bindingFileRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let templates = try skills().filter { package in
            package.origin == .bundled
                && package.skillClass == .researcher
                && package.supports(.fidelity)
                && package.provides(.citationVerification)
                && package.provides(.citationFormatting)
                && package.citationStyles.contains("apa-7")
        }
        guard templates.count == 1, let template = templates.first else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Scholium could not identify exactly one bundled APA citation starter."
            )
        }
        let occupied = Set(try skills().map(\.id))
        let baseID = "apa-7-citation"
        var adoptedID = baseID
        var suffix = 2
        while occupied.contains(adoptedID) {
            adoptedID = "\(baseID)-\(suffix)"
            suffix += 1
        }
        let adopted = try duplicateBundled(id: template.id, as: adoptedID)
        do {
            let binding = try activateCitationBinding(
                packageID: adopted.id,
                citationStyle: "apa-7",
                expectedBindingRevision: expectedBindingRevision
            )
            return ResearchSkillCitationAdoption(
                package: try localPackage(id: adopted.id),
                binding: binding
            )
        } catch {
            do {
                guard let revision = adopted.revision else {
                    throw ResearchSkillError.unsafePackage(adopted.id)
                }
                try delete(id: adopted.id, expectedRevision: revision)
            } catch let rollbackError {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "Citation activation failed and the new local starter could not be rolled back: \(rollbackError.localizedDescription)"
                )
            }
            throw error
        }
    }

    /// Reads the complete Settings-owned Researcher Skill profile for one
    /// semantic function. Absence means the release-managed primary Method
    /// runs without a researcher-owned refinement.
    public func functionSkillSelection(
        for function: ResearchFunctionID
    ) throws -> ResearchFunctionSkillSelection {
        guard let document = try bindingSnapshot()?.document else {
            return ResearchFunctionSkillSelection(function: function)
        }
        return ResearchFunctionSkillSelection(
            function: function,
            primaryPackageID: document.functionBindings[function.rawValue],
            supplementalPackageIDs: document.functionSkillBindings[function.rawValue] ?? [],
            selectedPractices: document.functionPracticeBindings[function.rawValue] ?? []
        )
    }

    /// Atomically replaces one function's Researcher Skill profile through a
    /// raw-revision check. A valid explicit save may repair a malformed but
    /// safe JSON document; it never preserves unvalidated fragments from that
    /// document.
    @discardableResult
    public func saveFunctionSkillSelection(
        _ selection: ResearchFunctionSkillSelection,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        let observed = try bindingFileRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let compatiblePractices = try compatiblePracticeIDs(
            for: selection.function,
            primaryPackageID: selection.primaryPackageID
        )
        guard selection.selectedPractices.allSatisfy({
            compatiblePractices.contains($0.practiceID)
        }) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A selected Practice is not compatible with the complete primary method for \(selection.function.rawValue)."
            )
        }
        try validateFunctionSkillSelection(selection)

        let existing = (try? bindingSnapshot()?.document)
            ?? ResearchSkillBindingDocument()
        var primary = existing.functionBindings
        var supplemental = existing.functionSkillBindings
        var practices = existing.functionPracticeBindings
        let key = selection.function.rawValue

        if let packageID = selection.primaryPackageID {
            primary[key] = packageID
        } else {
            primary.removeValue(forKey: key)
        }
        if selection.supplementalPackageIDs.isEmpty {
            supplemental.removeValue(forKey: key)
        } else {
            supplemental[key] = selection.supplementalPackageIDs
        }
        if selection.selectedPractices.isEmpty {
            practices.removeValue(forKey: key)
        } else {
            practices[key] = selection.selectedPractices
        }

        return try saveBindingDocument(
            ResearchSkillBindingDocument(
                functionBindings: primary,
                functionSkillBindings: supplemental,
                functionPracticeBindings: practices,
                citationBinding: existing.citationBinding,
                citationStyle: existing.citationStyle,
                bibliographyMethodBinding: existing.bibliographyMethodBinding
            ),
            expectedRevision: expectedBindingRevision
        )
    }

    @discardableResult
    public func clearFunctionSkillSelection(
        for function: ResearchFunctionID,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        try saveFunctionSkillSelection(
            ResearchFunctionSkillSelection(function: function),
            expectedBindingRevision: expectedBindingRevision
        )
    }

    // MARK: - Action-keyed Working Method bindings v2

    /// Installs the six directly editable default Methods and one explicit
    /// disabled Manuscript binding when binding v2 is absent. Workspace
    /// bootstrap calls this before a new manifest; an established Triptych may
    /// reach it only through an explicit repair action. The binding is written
    /// last, so an interrupted install can retry exact task-owned packages
    /// without mistaking a partial install for active configuration.
    @discardableResult
    public func installDefaultWorkingMethods()
        throws -> ResearchWorkingMethodBindingSnapshot
    {
        if let existing = try workingMethodBindingSnapshot() {
            try validateNewTriptychWorkingMethodDocument(existing.document)
            for descriptor in Self.defaultWorkingMethodDescriptors {
                guard let binding = existing.document.binding(for: descriptor.actionID) else {
                    throw ResearchSkillBindingError.invalidBindingDocument(
                        "Working Method bootstrap is incomplete for \(descriptor.actionID.rawValue)."
                    )
                }
                try validateWorkingMethodBinding(binding, for: descriptor.actionID)
            }
            return existing
        }

        try ensureSkillsDirectory()
        do {
            var bindings: [ResearchActionID: ResearchWorkingMethodBinding] = [:]
            for descriptor in Self.defaultWorkingMethodDescriptors {
                let sources = try workingMethodSources(for: descriptor)
                let expectedRevision = Self.packageRevision(sources: sources)
                let packageURL = try safePackageURL(id: descriptor.workingPackageID)
                if fileManager.fileExists(atPath: packageURL.path) {
                    let existing = try localPackage(id: descriptor.workingPackageID)
                    guard existing.revision == expectedRevision,
                          existing.isValid else {
                        throw ResearchSkillBindingError.invalidBindingDocument(
                            "A partial Working Method bootstrap conflicts with package \(descriptor.workingPackageID)."
                        )
                    }
                } else {
                    let installed = try installLocalPackage(
                        id: descriptor.workingPackageID,
                        sources: sources
                    ).package
                    guard installed.revision == expectedRevision,
                          installed.isValid else {
                        throw ResearchSkillBindingError.invalidBindingDocument(
                            "Working Method \(descriptor.workingPackageID) failed structural readback."
                        )
                    }
                }
                bindings[descriptor.actionID] = try ResearchWorkingMethodBinding(
                    state: .installedDefault,
                    packageID: descriptor.workingPackageID
                )
            }
            bindings[.manuscript] = try ResearchWorkingMethodBinding(state: .disabled)
            let document = try ResearchWorkingMethodBindingDocument(
                actionBindings: bindings
            )
            try validateNewTriptychWorkingMethodDocument(document)
            return try saveWorkingMethodBindingDocument(
                document,
                expectedRevision: nil
            )
        } catch is ResearchWorkingMethodBindingWriteFailure {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        } catch {
            // Fully installed packages are intentionally retained. The v2
            // binding is the activation boundary, so a retry can reuse exact
            // task-owned packages without deleting any interposed edit.
            throw error
        }
    }

    public func workingMethodBindingSnapshot()
        throws -> ResearchWorkingMethodBindingSnapshot?
    {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let identity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: workingMethodBindingsURL.lastPathComponent,
            path: workingMethodBindingsURL.path,
            maximumByteCount: 1_048_576
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: identity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        guard data.count <= 1_048_576 else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method binding v2 exceeds the 1 MiB safety limit."
            )
        }
        let document: ResearchWorkingMethodBindingDocument
        do {
            document = try JSONDecoder().decode(
                ResearchWorkingMethodBindingDocument.self,
                from: data
            )
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method binding v2 cannot be decoded. \(error.localizedDescription)"
            )
        }
        guard document.actionBindings.count <= 256 else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method binding v2 exceeds 256 Actions."
            )
        }
        return ResearchWorkingMethodBindingSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    public func workingMethodBindingFileRevision() throws -> DocumentFingerprint? {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let identity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: workingMethodBindingsURL.lastPathComponent,
            path: workingMethodBindingsURL.path,
            maximumByteCount: 1_048_576
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: identity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        return DocumentFingerprint(data: data)
    }

    // MARK: - Researcher Action Profiles v1

    public func actionProfileSnapshot() throws -> ResearchActionProfileSnapshot? {
        guard fileManager.fileExists(atPath: controlURL.path) else {
            return nil
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: actionProfileBindingsURL.lastPathComponent,
            path: actionProfileBindingsURL.path,
            maximumByteCount: Self.maximumActionProfileDocumentByteCount
        ) else {
            return nil
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: rootIdentity
        ) else {
            throw ResearchActionProfileStorageError.unsafeDocument
        }
        let document: ResearchActionProfileDocument
        do {
            document = try JSONDecoder().decode(
                ResearchActionProfileDocument.self,
                from: data
            )
        } catch {
            throw ResearchActionProfileStorageError.invalidDocument(
                error.localizedDescription
            )
        }
        return ResearchActionProfileSnapshot(
            document: document,
            revision: DocumentFingerprint(data: data)
        )
    }

    /// Saves one structurally validated custom Action or optional Manuscript
    /// Profile. `nil` is valid only when the document is currently absent;
    /// every later replacement is revision checked.
    @discardableResult
    public func saveActionProfile(
        _ binding: ResearchActionProfileBinding,
        expectedDocumentRevision: DocumentFingerprint?
    ) throws -> ResearchActionProfileSnapshot {
        try validateActionProfileBinding(binding)
        let current = try actionProfileSnapshot()
        guard current?.revision == expectedDocumentRevision else {
            throw ResearchActionProfileStorageError.staleDocument
        }
        let document = try (current?.document ?? ResearchActionProfileDocument())
            .replacing(binding, for: binding.profile.actionID)
        return try saveActionProfileDocument(
            document,
            expectedRevision: expectedDocumentRevision
        )
    }

    @discardableResult
    public func removeActionProfile(
        actionID: ResearchActionID,
        expectedDocumentRevision: DocumentFingerprint
    ) throws -> ResearchActionProfileSnapshot {
        guard let current = try actionProfileSnapshot(),
              current.revision == expectedDocumentRevision,
              current.document.binding(for: actionID) != nil else {
            throw ResearchActionProfileStorageError.staleDocument
        }
        return try saveActionProfileDocument(
            current.document.removing(actionID),
            expectedRevision: expectedDocumentRevision
        )
    }

    /// Replaces all custom Profiles as one revision-checked unit. Settings uses
    /// this for deterministic reordering; it is not an Action resolver.
    @discardableResult
    public func saveActionProfileDocument(
        _ document: ResearchActionProfileDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchActionProfileSnapshot {
        for binding in document.actionBindings.values {
            try validateActionProfileBinding(binding)
        }
        try ensureControlDirectoryForGuidance()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumActionProfileDocumentByteCount else {
            throw ResearchActionProfileStorageError.invalidDocument(
                "The encoded document exceeds the 8 MiB storage boundary."
            )
        }

        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        let leaf = actionProfileBindingsURL.lastPathComponent
        let current = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: leaf,
            path: actionProfileBindingsURL.path,
            maximumByteCount: Self.maximumActionProfileDocumentByteCount
        )
        if let current {
            guard let expectedRevision,
                  DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchActionProfileStorageError.staleDocument
            }
        } else if expectedRevision != nil {
            throw ResearchActionProfileStorageError.staleDocument
        }

        let stageName = ".action-profiles-\(UUID().uuidString.lowercased())"
        var stageCreated = false
        var committed = false
        do {
            try SecureResearchSkillPackageIO.createDataFile(
                parentDescriptor: rootDescriptor,
                leaf: stageName,
                data: data,
                path: stageName
            )
            stageCreated = true
            if current != nil {
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: leaf,
                    second: stageName
                )
            } else {
                try SecureResearchSkillPackageIO.movePackageExclusively(
                    rootDescriptor: rootDescriptor,
                    source: stageName,
                    destination: leaf
                )
            }
            committed = true
            try workingMethodHooks.handler(.afterActionProfileCommit)
            guard fsync(rootDescriptor) == 0 else {
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            let readback = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: actionProfileBindingsURL.path,
                maximumByteCount: Self.maximumActionProfileDocumentByteCount
            )
            guard readback == data,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            if current != nil {
                try SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchActionProfileStorageError.unsafeDocument
                }
            }
            return ResearchActionProfileSnapshot(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
        } catch {
            if !committed, stageCreated {
                try? SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
            }
            if committed {
                // Once the exchange has happened, a failed directory flush,
                // cleanup, readback, or canonical-path identity check is not
                // success. The new bytes may be present through this already
                // open descriptor while the Triptych path refers elsewhere.
                // Preserve every artifact and force an explicit reload or
                // recovery instead of claiming that Settings saved safely.
                throw ResearchActionProfileStorageError.unsafeDocument
            }
            throw error
        }
    }

    /// Replaces one Action binding without interpreting absence as a default.
    @discardableResult
    public func saveWorkingMethodBinding(
        _ binding: ResearchWorkingMethodBinding,
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchWorkingMethodBindingSnapshot {
        guard let current = try workingMethodBindingSnapshot(),
              current.revision == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        try validateWorkingMethodBinding(binding, for: actionID)
        let replacement = try current.document.replacing(binding, for: actionID)
        do {
            return try saveWorkingMethodBindingDocument(
                replacement,
                expectedRevision: expectedBindingRevision
            )
        } catch is ResearchWorkingMethodBindingWriteFailure {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
    }

    @discardableResult
    public func disableWorkingMethod(
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchWorkingMethodBindingSnapshot {
        try saveWorkingMethodBinding(
            ResearchWorkingMethodBinding(state: .disabled),
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    @discardableResult
    public func activateResearcherSkill(
        packageID: String,
        for actionID: ResearchActionID,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchWorkingMethodBindingSnapshot {
        try saveWorkingMethodBinding(
            ResearchWorkingMethodBinding(
                state: .researcherSkill,
                packageID: packageID
            ),
            for: actionID,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    /// Directly edits the active installed-default package, or the optional
    /// stable Manuscript Working Method, through exact package and binding
    /// revisions. Invalid research prose is preserved as an identifiable
    /// revision but makes the Action unavailable at resolve.
    public func saveWorkingMethod(
        for actionID: ResearchActionID,
        source: String,
        expectedPackageRevision: DocumentFingerprint,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        guard let snapshot = try workingMethodBindingSnapshot(),
              snapshot.revision == expectedBindingRevision,
              let binding = snapshot.document.binding(for: actionID),
              let packageID = binding.packageID,
              packageID == Self.editableWorkingMethodPackageID(for: actionID),
              binding.state == .installedDefault
                || (actionID == .manuscript && binding.state == .researcherSkill) else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        return try atomicallyEditWorkingMethod(
            packageID: packageID,
            actionID: actionID,
            source: source,
            expectedPackageRevision: expectedPackageRevision,
            expectedBindingRevision: expectedBindingRevision
        )
    }

    /// Restores the exact bundled reference into the stable editable package
    /// identity and activates it. A precommit binding failure restores the
    /// prior package; a postcommit ambiguity preserves the coherent committed
    /// state and returns a recovery-required error.
    public func restoreBundledWorkingMethod(
        for actionID: ResearchActionID,
        expectedPackageState: ResearchWorkingMethodExpectedPackageState,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchWorkingMethodRestoreOutcome {
        guard let descriptor = Self.defaultWorkingMethodDescriptor(for: actionID),
              let currentBinding = try workingMethodBindingSnapshot(),
              currentBinding.revision == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let sources = try workingMethodSources(for: descriptor)
        let restoredRevision = Self.packageRevision(sources: sources)
        _ = try validatedProposedResearcherPackage(
            id: descriptor.workingPackageID,
            sources: sources,
            revision: restoredRevision
        )
        try ensureSkillsDirectory()

        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsURL.path
        )
        let packageExists = try SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: descriptor.workingPackageID,
            path: descriptor.workingPackageID
        )
        let displacedRevision: DocumentFingerprint?
        switch (expectedPackageState, packageExists) {
        case (.missing, false):
            displacedRevision = nil
        case (.present(let expectedRevision), true):
            let currentSources = try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: descriptor.workingPackageID
            )
            guard Self.packageRevision(sources: currentSources) == expectedRevision else {
                throw ResearchSkillError.stalePackage(descriptor.workingPackageID)
            }
            displacedRevision = expectedRevision
        default:
            throw ResearchSkillError.stalePackage(descriptor.workingPackageID)
        }

        let restoredBinding = try ResearchWorkingMethodBinding(
            state: .installedDefault,
            packageID: descriptor.workingPackageID
        )
        let replacementDocument = try currentBinding.document.replacing(
            restoredBinding,
            for: actionID
        )
        let stageName = ".working-method-\(UUID().uuidString.lowercased())"
        guard let workingMethodRecoveryStore else {
            throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                descriptor.workingPackageID
            )
        }
        let recoveryReservation = displacedRevision.map {
            workingMethodRecoveryStore.reserve(
                packageID: descriptor.workingPackageID,
                packageRevision: $0
            )
        }
        do {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: rootDescriptor,
                packageName: stageName,
                sources: sources
            )
        } catch {
            throw error
        }
        var replacementInstalled = false
        var committedBinding: ResearchWorkingMethodBindingSnapshot?
        let restoredPackage: ResearchSkillPackage
        do {
            guard let recheckedBinding = try workingMethodBindingSnapshot(),
                  recheckedBinding.revision == expectedBindingRevision,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.staleBindingFile
            }
            if packageExists {
                let rechecked = try SecureResearchSkillPackageIO.strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: descriptor.workingPackageID
                )
                if case .present(let expectedRevision) = expectedPackageState {
                    guard Self.packageRevision(sources: rechecked) == expectedRevision else {
                        throw ResearchSkillError.stalePackage(descriptor.workingPackageID)
                    }
                }
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: descriptor.workingPackageID,
                    second: stageName
                )
            } else {
                try SecureResearchSkillPackageIO.movePackageExclusively(
                    rootDescriptor: rootDescriptor,
                    source: stageName,
                    destination: descriptor.workingPackageID
                )
            }
            replacementInstalled = true
            guard fsync(rootDescriptor) == 0,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                    descriptor.workingPackageID
                )
            }

            let binding = try saveWorkingMethodBindingDocument(
                replacementDocument,
                expectedRevision: expectedBindingRevision
            )
            committedBinding = binding
            let package = try localPackage(id: descriptor.workingPackageID)
            guard package.revision == restoredRevision, package.isValid else {
                throw ResearchSkillError.stalePackage(descriptor.workingPackageID)
            }
            restoredPackage = package
            if let recoveryReservation {
                try workingMethodRecoveryStore.archive(
                    sourceParentDescriptor: rootDescriptor,
                    sourceName: stageName,
                    reservation: recoveryReservation
                )
            }
            guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                skillsURL,
                identity: rootIdentity
            ), try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: descriptor.workingPackageID
            ) == sources,
                  try workingMethodBindingMatches(
                      packageID: descriptor.workingPackageID,
                      actionID: actionID,
                      expectedRevision: binding.revision
                  ) else {
                throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                    descriptor.workingPackageID
                )
            }
        } catch is ResearchWorkingMethodBindingWriteFailure {
            // The binding exchange happened. Keep the restored package and all
            // displaced artifacts; trying to infer an uncommitted state here
            // could pair a rolled-back package with a newly active binding.
            if let recoveryReservation {
                _ = try? workingMethodRecoveryStore.archive(
                    sourceParentDescriptor: rootDescriptor,
                    sourceName: stageName,
                    reservation: recoveryReservation
                )
            }
            throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                descriptor.workingPackageID
            )
        } catch {
            if committedBinding != nil {
                if let recoveryReservation {
                    _ = try? workingMethodRecoveryStore.archive(
                        sourceParentDescriptor: rootDescriptor,
                        sourceName: stageName,
                        reservation: recoveryReservation
                    )
                }
                throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                    descriptor.workingPackageID
                )
            }
            var rollbackPreservesExternalState = true
            if replacementInstalled {
                do {
                    let installedSources = try SecureResearchSkillPackageIO
                        .strictPackageSources(
                            rootDescriptor: rootDescriptor,
                            packageID: descriptor.workingPackageID
                        )
                    rollbackPreservesExternalState = Self.packageRevision(
                        sources: installedSources
                    ) == restoredRevision
                    if rollbackPreservesExternalState,
                       let displacedRevision {
                        let displacedSources = try SecureResearchSkillPackageIO
                            .strictPackageSources(
                                rootDescriptor: rootDescriptor,
                                packageID: stageName
                            )
                        rollbackPreservesExternalState = Self.packageRevision(
                            sources: displacedSources
                        ) == displacedRevision
                    }
                } catch {
                    rollbackPreservesExternalState = false
                }
            }
            guard rollbackPreservesExternalState else {
                throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                    descriptor.workingPackageID
                )
            }
            if replacementInstalled {
                do {
                    try rollbackWorkingMethodReplacement(
                        rootDescriptor: rootDescriptor,
                        packageID: descriptor.workingPackageID,
                        stageName: stageName,
                        replacedExisting: packageExists
                    )
                    let rollbackSources = try SecureResearchSkillPackageIO
                        .strictPackageSources(
                            rootDescriptor: rootDescriptor,
                            packageID: stageName
                        )
                    let rollbackReservation = workingMethodRecoveryStore.reserve(
                        packageID: descriptor.workingPackageID,
                        packageRevision: Self.packageRevision(sources: rollbackSources)
                    )
                    try workingMethodRecoveryStore.archive(
                        sourceParentDescriptor: rootDescriptor,
                        sourceName: stageName,
                        reservation: rollbackReservation
                    )
                } catch {
                    throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                        descriptor.workingPackageID
                    )
                }
            } else {
                do {
                    try SecureResearchSkillPackageIO.removePackage(
                        rootDescriptor: rootDescriptor,
                        packageName: stageName
                    )
                } catch {
                    throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                        descriptor.workingPackageID
                    )
                }
            }
            throw error
        }
        guard let committedBinding else {
            throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                descriptor.workingPackageID
            )
        }
        return ResearchWorkingMethodRestoreOutcome(
            actionID: actionID,
            package: restoredPackage,
            binding: committedBinding
        )
    }

    /// Resolves the exact Practice IDs declared compatible by the complete
    /// primary method without consulting global Skill directories or inferring
    /// applicability from filenames.
    public func compatiblePracticeIDs(
        for function: ResearchFunctionID,
        primaryPackageID: String? = nil
    ) throws -> Set<String> {
        if let primaryPackageID {
            let package = try package(id: primaryPackageID)
            guard package.supports(function),
                  package.role == "method"
                    || (package.role == "specialist"
                        && !composesWithFunction(package, function: function)) else {
                return []
            }
            return Set(package.compatiblePracticeIDs)
        }
        let candidates = try skills().filter {
            $0.origin == .bundled
                && $0.skillClass == .method
                && $0.supports(function)
                && $0.isValid
        }
        guard let first = candidates.first else { return [] }
        // Binding v1 is still Function-keyed. When one protected Function
        // serves more than one Action, expose only Practices declared
        // compatible by every candidate Method; never widen one Action from
        // the other. Action-keyed bindings replace this compatibility bridge.
        return candidates.dropFirst().reduce(Set(first.compatiblePracticeIDs)) {
            compatible, package in
            compatible.intersection(package.compatiblePracticeIDs)
        }
    }

    /// Resolves the complete Source Analyzer used by the Analysis-only
    /// Recommended Bibliography capability. A missing explicit binding uses
    /// the release-managed template; a broken explicit binding never falls
    /// back silently.
    public func bibliographyMethodBindingResolution() throws -> ResearchSkillBindingResolution {
        let revision = try? bindingFileRevision()
        let all = try skills()
        let bundled = all.filter {
            $0.origin == .bundled
                && $0.isValid
                && $0.provides(.bibliographyRecommendation)
        }
        let installed = all.filter {
            $0.origin == .triptych
                && $0.isValid
                && $0.provides(.bibliographyRecommendation)
                && $0.role == "method"
        }
        let document: ResearchSkillBindingDocument?
        do {
            document = try bindingSnapshot()?.document
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                issue: .malformed(error.localizedDescription),
                bindingRevision: revision
            )
        }
        if let packageID = document?.bibliographyMethodBinding {
            guard let package = installed.first(where: { $0.id == packageID }) else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundled.isEmpty,
                    installedCandidateIDs: installed.map(\.id).sorted(),
                    issue: .invalidPackage(packageID),
                    bindingRevision: revision
                )
            }
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                package: package,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                bindingRevision: revision
            )
        }
        guard bundled.count == 1, let package = bundled.first else {
            return ResearchSkillBindingResolution(
                source: .bundledDefault,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                issue: .missingCapability(.bibliographyRecommendation),
                bindingRevision: revision
            )
        }
        return ResearchSkillBindingResolution(
            source: .bundledDefault,
            package: package,
            bundledTemplateAvailable: true,
            installedCandidateIDs: installed.map(\.id).sorted(),
            bindingRevision: revision
        )
    }

    @discardableResult
    public func setBibliographyMethodBinding(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchSkillBindingSnapshot {
        let observed = try bindingFileRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        if let packageID {
            let package = try localPackage(id: packageID)
            guard package.origin == .triptych,
                  package.isValid,
                  package.role == "method",
                  package.provides(.bibliographyRecommendation) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The bibliography method must be a valid Triptych-local complete Source Analyzer."
                )
            }
        }
        let existing = (try? bindingSnapshot()?.document)
            ?? ResearchSkillBindingDocument()
        return try saveBindingDocument(
            ResearchSkillBindingDocument(
                functionBindings: existing.functionBindings,
                functionSkillBindings: existing.functionSkillBindings,
                functionPracticeBindings: existing.functionPracticeBindings,
                citationBinding: existing.citationBinding,
                citationStyle: existing.citationStyle,
                bibliographyMethodBinding: packageID
            ),
            expectedRevision: expectedBindingRevision
        )
    }

    /// Resolves only the explicit Action-keyed binding-v2 Method. The retained
    /// Function-era file is neither decoded nor consulted here, and a missing
    /// v2 selection never activates the bundled reference.
    public func functionBindingResolution(
        for function: ResearchFunctionID,
        actionID: ResearchActionID
    ) throws -> ResearchSkillBindingResolution {
        let rawBindingRevision = try? workingMethodBindingFileRevision()
        let all = try skills()
        let localCandidates = all.filter {
            $0.origin == .triptych
                && $0.isValid
                && $0.supports(function)
                && $0.supports(actionID)
        }.map(\.id)
        let bundledCandidates = all.filter {
            $0.origin == .bundled
                && $0.skillClass == .method
                && $0.isValid
                && $0.supports(function)
                && $0.supports(actionID)
        }
        let snapshot: ResearchWorkingMethodBindingSnapshot?
        do {
            snapshot = try workingMethodBindingSnapshot()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .malformed(error.localizedDescription),
                bindingRevision: rawBindingRevision
            )
        }
        guard let binding = snapshot?.document.binding(for: actionID) else {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .missing,
                bindingRevision: rawBindingRevision
            )
        }
        guard binding.state != .disabled else {
            return ResearchSkillBindingResolution(
                source: .disabled,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .disabled,
                bindingRevision: rawBindingRevision
            )
        }
        guard let id = binding.packageID else {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .malformed(
                    "Active Working Method binding has no package for \(actionID.rawValue)."
                ),
                bindingRevision: rawBindingRevision
            )
        }
        if binding.state == .installedDefault,
           id != Self.defaultWorkingMethodDescriptor(for: actionID)?.workingPackageID {
            return ResearchSkillBindingResolution(
                source: .installedDefault,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .invalidPackage(id),
                bindingRevision: rawBindingRevision
            )
        }
        if binding.state == .researcherSkill,
           Self.defaultWorkingMethodDescriptors.contains(where: {
               $0.workingPackageID == id
           }) {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .invalidPackage(id),
                bindingRevision: rawBindingRevision
            )
        }
        let source: ResearchSkillBindingSource = binding.state == .installedDefault
            ? .installedDefault
            : .researcherSkill
        guard let bound = all.first(where: {
            $0.origin == .triptych && $0.id == id
        }) else {
            return ResearchSkillBindingResolution(
                source: source,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .invalidPackage(id),
                bindingRevision: rawBindingRevision
            )
        }
        guard bound.isValid, bound.role == "method" else {
            return ResearchSkillBindingResolution(
                source: source,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .invalidPackage(id),
                bindingRevision: rawBindingRevision
            )
        }
        guard bound.supports(function) else {
            return ResearchSkillBindingResolution(
                source: source,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .unsupportedFunction(packageID: id, function: function),
                bindingRevision: rawBindingRevision
            )
        }
        guard bound.supports(actionID) else {
            return ResearchSkillBindingResolution(
                source: source,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .unsupportedAction(packageID: id, actionID: actionID),
                bindingRevision: rawBindingRevision
            )
        }
        return ResearchSkillBindingResolution(
            source: source,
            package: bound,
            bundledTemplateAvailable: !bundledCandidates.isEmpty,
            installedCandidateIDs: localCandidates,
            bindingRevision: rawBindingRevision
        )
    }

    /// Resolves a researcher-owned Action Profile and its exact package
    /// without consulting or mutating Working Method bindings. A Profile is
    /// configuration, not authority; callers must still intersect it with the
    /// current Target, request, and Application hard limits.
    public func profileActionBindingResolution(
        for function: ResearchFunctionID,
        actionID: ResearchActionID
    ) throws -> ResearchSkillBindingResolution {
        let rawProfileRevision = (try? actionProfileSnapshot())?.revision
        let snapshot: ResearchActionProfileSnapshot?
        do {
            snapshot = try actionProfileSnapshot()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                issue: .malformed(error.localizedDescription),
                bindingRevision: rawProfileRevision
            )
        }
        guard let snapshot,
              let binding = snapshot.document.binding(for: actionID) else {
            return ResearchSkillBindingResolution(
                source: .none,
                issue: .missing,
                bindingRevision: rawProfileRevision
            )
        }
        guard binding.profile.definition.id == actionID else {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                issue: .malformed("The Action Profile definition is inconsistent."),
                bindingRevision: snapshot.revision
            )
        }
        let all = try skills()
        guard let package = all.first(where: {
            $0.origin == .triptych && $0.id == binding.packageID
        }) else {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                issue: .invalidPackage(binding.packageID),
                bindingRevision: snapshot.revision
            )
        }
        guard package.isValid, package.skillClass != .system else {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                issue: .invalidPackage(binding.packageID),
                bindingRevision: snapshot.revision
            )
        }
        guard package.supports(actionID) else {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                issue: .unsupportedAction(packageID: package.id, actionID: actionID),
                bindingRevision: snapshot.revision
            )
        }
        guard package.supports(function) else {
            return ResearchSkillBindingResolution(
                source: .researcherSkill,
                issue: .unsupportedFunction(packageID: package.id, function: function),
                bindingRevision: snapshot.revision
            )
        }
        return ResearchSkillBindingResolution(
            source: .researcherSkill,
            package: package,
            installedCandidateIDs: [package.id],
            bindingRevision: snapshot.revision
        )
    }

    /// Citation capability is active only through an explicit valid
    /// Triptych-local binding. Bundled copy-on-adoption templates are merely
    /// availability hints and can never satisfy the binding.
    public func citationBindingResolution(
        requiredCapabilities: Set<ResearchSkillCapability> = [
            .citationVerification,
            .citationFormatting,
        ],
        citationStyle: String? = nil
    ) throws -> ResearchSkillBindingResolution {
        let rawBindingRevision = try? bindingFileRevision()
        let all = try skills()
        let bundledTemplateAvailable = all.contains { package in
            package.origin == .bundled
                && package.skillClass == .researcher
                && requiredCapabilities.allSatisfy { package.provides($0) }
                && !package.citationStyleResources.isEmpty
        }
        let localCandidates = all.filter { package in
            package.origin == .triptych
                && package.isValid
                && package.supports(.fidelity)
                && requiredCapabilities.allSatisfy { package.provides($0) }
                && !package.citationStyleResources.isEmpty
        }
        let snapshot: ResearchSkillBindingSnapshot?
        do {
            snapshot = try bindingSnapshot()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .malformed(error.localizedDescription),
                bindingRevision: rawBindingRevision
            )
        }
        guard let id = snapshot?.document.citationBinding else {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .missing,
                bindingRevision: rawBindingRevision
            )
        }
        guard let bound = localCandidates.first(where: { $0.id == id }) else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .invalidPackage(id),
                bindingRevision: rawBindingRevision
            )
        }
        guard let activeStyle = snapshot?.document.citationStyle else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .citationStyleMissing(packageID: id),
                bindingRevision: rawBindingRevision
            )
        }
        guard bound.citationStyles.contains(activeStyle),
              bound.citationStyleResources[activeStyle] != nil else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .citationStyleMismatch(packageID: id, requested: activeStyle),
                bindingRevision: rawBindingRevision
            )
        }
        if let citationStyle {
            let normalized = citationStyle.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard normalized == activeStyle else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: bundledTemplateAvailable,
                    installedCandidateIDs: localCandidates.map(\.id),
                    issue: .citationStyleMismatch(packageID: id, requested: normalized),
                    bindingRevision: rawBindingRevision
                )
            }
        }
        return ResearchSkillBindingResolution(
            source: .triptychBinding,
            package: bound,
            bundledTemplateAvailable: bundledTemplateAvailable,
            installedCandidateIDs: localCandidates.map(\.id),
            citationStyle: activeStyle,
            bindingRevision: rawBindingRevision
        )
    }

    /// Resolves one Action-specific Method and fingerprints the exact resources
    /// loaded for this run. The package revision still covers the complete
    /// bounded package.
    public func resolvedFunctionPackages(
        for function: ResearchFunctionID,
        actionID: ResearchActionID,
        mode: ResearchSkillMode? = nil,
        fidelityChecks: Set<FidelityCheck> = [],
        citationStyle: String? = nil,
        additionalSkillIDs: [String] = [],
        primaryResourcePaths: Set<String> = [],
        additionalResourcePaths: [String: Set<String>] = [:],
        expectedAdditionalPackageRevisions: [String: DocumentFingerprint] = [:]
    ) throws -> [ResolvedResearchSkillSelection] {
        let primaryResolution = try functionBindingResolution(
            for: function,
            actionID: actionID
        )
        guard let bindingRevision = primaryResolution.bindingRevision else {
            throw ResearchSkillBindingError.unresolvedBinding(
                primaryResolution.issue ?? .missing
            )
        }
        return try resolvedFunctionPackages(
            for: function,
            actionID: actionID,
            mode: mode ?? Self.skillMode(for: actionID),
            fidelityChecks: fidelityChecks,
            citationStyle: citationStyle,
            additionalSkillIDs: additionalSkillIDs,
            primaryResourcePaths: primaryResourcePaths,
            additionalResourcePaths: additionalResourcePaths,
            expectedAdditionalPackageRevisions: expectedAdditionalPackageRevisions,
            primaryResolution: primaryResolution,
            primaryBindingProof: .workingMethod(
                actionID: actionID,
                packageID: primaryResolution.package?.id ?? "",
                revision: bindingRevision
            )
        )
    }

    public func resolvedProfileActionPackages(
        for function: ResearchFunctionID,
        actionID: ResearchActionID,
        mode: ResearchSkillMode? = nil,
        expectedBinding: ResearchActionProfileBinding,
        expectedProfileDocumentRevision: DocumentFingerprint,
        fidelityChecks: Set<FidelityCheck> = [],
        citationStyle: String? = nil,
        additionalSkillIDs: [String] = [],
        primaryResourcePaths: Set<String> = [],
        additionalResourcePaths: [String: Set<String>] = [:],
        expectedAdditionalPackageRevisions: [String: DocumentFingerprint] = [:]
    ) throws -> [ResolvedResearchSkillSelection] {
        let resolution = try profileActionBindingResolution(
            for: function,
            actionID: actionID
        )
        guard resolution.bindingRevision == expectedProfileDocumentRevision,
              resolution.package?.id == expectedBinding.packageID,
              try actionProfileBindingMatches(
                  expectedBinding,
                  actionID: actionID,
                  expectedRevision: expectedProfileDocumentRevision
              ) else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        return try resolvedFunctionPackages(
            for: function,
            actionID: actionID,
            mode: mode ?? Self.skillMode(for: actionID),
            fidelityChecks: fidelityChecks,
            citationStyle: citationStyle,
            additionalSkillIDs: additionalSkillIDs,
            primaryResourcePaths: primaryResourcePaths,
            additionalResourcePaths: additionalResourcePaths,
            expectedAdditionalPackageRevisions: expectedAdditionalPackageRevisions,
            primaryResolution: resolution,
            primaryBindingProof: .actionProfile(
                actionID: actionID,
                binding: expectedBinding,
                revision: expectedProfileDocumentRevision
            )
        )
    }

    private func resolvedFunctionPackages(
        for function: ResearchFunctionID,
        actionID: ResearchActionID,
        mode: ResearchSkillMode,
        fidelityChecks: Set<FidelityCheck>,
        citationStyle: String?,
        additionalSkillIDs: [String],
        primaryResourcePaths: Set<String>,
        additionalResourcePaths: [String: Set<String>],
        expectedAdditionalPackageRevisions: [String: DocumentFingerprint],
        primaryResolution: ResearchSkillBindingResolution,
        primaryBindingProof: PrimaryActionBindingProof
    ) throws -> [ResolvedResearchSkillSelection] {
        guard let primary = primaryResolution.package, primaryResolution.issue == nil else {
            throw ResearchSkillBindingError.unresolvedBinding(
                primaryResolution.issue ?? .missing
            )
        }
        guard let primaryRevision = primary.revision,
              primaryResolution.bindingRevision != nil else {
            throw ResearchSkillBindingError.unresolvedBinding(.invalidPackage(primary.id))
        }
        try workingMethodHooks.handler(
            .beforeFunctionPackageResolution(actionID: actionID)
        )
        guard try primaryBindingMatches(primaryBindingProof) else {
            throw ResearchSkillBindingError.staleBindingFile
        }

        // Protected Action mechanism is Application-owned. A researcher
        // Method may omit or even misstate dependencies without detaching the
        // exact read/write and completion adapter from a mediated run.
        var requestedIDs = [primary.id, "scholium-research-integration"]
            + additionalSkillIDs
        if mode == .discuss {
            requestedIDs.append("scholium-discussion-protocol")
        }
        var resolvedCitationID: String?
        var resolvedCitationStyle: String?
        if function == .fidelity, fidelityChecks.contains(.citations) {
            let capabilities: Set<ResearchSkillCapability> = [
                .citationVerification,
                .citationFormatting,
            ]
            let citation = try citationBindingResolution(
                requiredCapabilities: capabilities,
                citationStyle: citationStyle
            )
            guard let package = citation.package, citation.issue == nil else {
                throw ResearchSkillBindingError.unresolvedBinding(citation.issue ?? .missing)
            }
            resolvedCitationID = package.id
            resolvedCitationStyle = citation.citationStyle
            requestedIDs.append(package.id)
        }

        let packages = try resolvedPackages(
            for: mode,
            requestedSkillIDs: Self.unique(requestedIDs)
        )
        let resolvedPrimaries = packages.filter { $0.id == primary.id }
        let unexpectedMethods = packages.filter {
            $0.role == "method" && $0.id != primary.id
        }
        guard resolvedPrimaries.count == 1,
              unexpectedMethods.isEmpty,
              let resolvedPrimary = resolvedPrimaries.first,
              resolvedPrimary.revision == primaryRevision,
              resolvedPrimary.supports(function),
              resolvedPrimary.supports(actionID),
              primaryBindingProof.permits(primary: resolvedPrimary) else {
            throw ResearchSkillBindingError.unresolvedBinding(.invalidPackage(primary.id))
        }
        for (packageID, revision) in expectedAdditionalPackageRevisions {
            guard packages.first(where: { $0.id == packageID })?.revision == revision else {
                throw ResearchSkillError.stalePackage(packageID)
            }
        }
        var selections: [ResolvedResearchSkillSelection] = []
        for package in packages {
            guard let packageRevision = package.revision else {
                throw ResearchSkillError.invalidPackage(package.id, package.validationIssues)
            }
            let expectedResourceRevision = package.id == primary.id
                ? primaryRevision
                : packageRevision
            let resourceSnapshot = try packageResourceSnapshot(
                id: package.id,
                expectedRevision: expectedResourceRevision
            )
            var selected: Set<String> = ["SKILL.md"]
            selected.formUnion(Self.requiredSystemResourcePaths(
                for: package.id,
                mode: mode
            ))
            if package.id == primary.id {
                let actionDefaults = Self.defaultResourcePaths(
                    for: actionID,
                    fidelityChecks: fidelityChecks
                )
                if package.origin == .bundled {
                    selected.formUnion(actionDefaults)
                } else {
                    // A researcher Method may be self-contained. Reused
                    // conventional filenames are loaded when present, but
                    // their absence never imposes Scholium's bundled layout.
                    selected.formUnion(actionDefaults.filter {
                        resourceSnapshot[$0] != nil
                    })
                }
                selected.formUnion(primaryResourcePaths)
            }
            if package.origin == .triptych, package.role != "practice" {
                var declared = Self.declaredResourceClosure(
                    in: resourceSnapshot
                )
                if package.id == primary.id {
                    let selectedDefaults = Self.defaultResourcePaths(
                        for: actionID,
                        fidelityChecks: fidelityChecks
                    )
                    let allActionDefaults = Self.defaultResourcePaths(
                        for: actionID,
                        fidelityChecks: Set(FidelityCheck.allCases)
                    )
                    declared.subtract(allActionDefaults.subtracting(selectedDefaults))
                }
                if package.id == resolvedCitationID,
                   let resolvedCitationStyle {
                    let unselectedStyles = Set(package.citationStyleResources.values)
                        .subtracting([
                            package.citationStyleResources[resolvedCitationStyle]
                        ].compactMap { $0 })
                    declared.subtract(unselectedStyles)
                }
                selected.formUnion(declared)
            }
            if package.id == resolvedCitationID {
                guard let resolvedCitationStyle,
                      let styleResource = package.citationStyleResources[
                        resolvedCitationStyle
                      ] else {
                    throw ResearchSkillBindingError.unresolvedBinding(
                        .citationStyleMissing(packageID: package.id)
                    )
                }
                selected.insert(styleResource)
            }
            selected.formUnion(additionalResourcePaths[package.id] ?? [])
            var loaded: [ResolvedResearchSkillResource] = []
            for path in selected.sorted() {
                guard let source = resourceSnapshot[path] else {
                    throw ResearchSkillCatalogError.resourceMissing("\(package.id)/\(path)")
                }
                loaded.append(ResolvedResearchSkillResource(
                    relativePath: path,
                    revision: DocumentFingerprint(content: source),
                    source: source
                ))
            }
            selections.append(ResolvedResearchSkillSelection(
                id: package.id,
                origin: package.origin,
                version: package.version,
                packageRevision: expectedResourceRevision,
                availableResourcePaths: resourceSnapshot.keys.sorted(),
                loadedResources: loaded
            ))
        }
        guard try primaryBindingMatches(primaryBindingProof) else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        return selections
    }

    private enum PrimaryActionBindingProof {
        case workingMethod(
            actionID: ResearchActionID,
            packageID: String,
            revision: DocumentFingerprint
        )
        case actionProfile(
            actionID: ResearchActionID,
            binding: ResearchActionProfileBinding,
            revision: DocumentFingerprint
        )

        func permits(primary: ResearchSkillPackage) -> Bool {
            switch self {
            case .workingMethod:
                primary.role == "method"
            case .actionProfile:
                primary.skillClass != .system && primary.origin == .triptych
            }
        }

    }

    private func primaryBindingMatches(
        _ proof: PrimaryActionBindingProof
    ) throws -> Bool {
        switch proof {
        case .workingMethod(let actionID, let packageID, let revision):
            try workingMethodBindingMatches(
                packageID: packageID,
                actionID: actionID,
                expectedRevision: revision
            )
        case .actionProfile(let actionID, let binding, let revision):
            try actionProfileBindingMatches(
                binding,
                actionID: actionID,
                expectedRevision: revision
            )
        }
    }

    private func actionProfileBindingMatches(
        _ binding: ResearchActionProfileBinding,
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) throws -> Bool {
        guard let snapshot = try actionProfileSnapshot(),
              snapshot.revision == expectedRevision,
              snapshot.document.binding(for: actionID) == binding,
              let package = try? localPackage(id: binding.packageID),
              package.origin == .triptych,
              package.isValid,
              package.skillClass != .system,
              package.supports(actionID) else {
            return false
        }
        return true
    }

    private func workingMethodBindingMatches(
        packageID: String,
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) throws -> Bool {
        guard let snapshot = try workingMethodBindingSnapshot(),
              snapshot.revision == expectedRevision,
              let binding = snapshot.document.binding(for: actionID) else {
            return false
        }
        return binding.state != .disabled && binding.packageID == packageID
    }

    /// Captures one coherent bounded package revision. The caller supplies the
    /// revision observed during routing; an external edit between routing and
    /// resource capture fails closed instead of combining old identity with
    /// new or mixed instruction bytes.
    func packageResourceSnapshot(
        id: String,
        expectedRevision: DocumentFingerprint
    ) throws -> [String: String] {
        let paths = try resourcePaths(id: id)
        var sources: [String: String] = [:]
        for path in paths {
            sources[path] = try resource(id: id, relativePath: path)
        }
        guard Self.packageRevision(sources: sources) == expectedRevision else {
            throw ResearchSkillError.stalePackage(id)
        }
        return sources
    }

    /// Selectively assembles only the dependency closure for the requested
    /// mode. Bundled Method and Researcher packages are opt-in by ID;
    /// default mode assembly contains only the required protected System
    /// packages. Mixed mode keeps every phase in its own envelope.
    public func instructionAssembly(
        mode: ResearchSkillMode = .discuss,
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
        return ([
            "Reusable package entries only (apply only when relevant).",
            "Follow each selected entry's declared resource conditions; prepared workflows attach exact resources.",
        ] + renderedPhases)
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

        var memoizedIssues: [String: [String]] = [:]
        func graphIssues(for id: String, path: Set<String>) -> [String] {
            if path.contains(id) {
                return ["The package dependency graph contains a cycle."]
            }
            if let cached = memoizedIssues[id] { return cached }
            guard let package = byID[id] else { return [] }
            var issues = package.validationIssues
            var nextPath = path
            nextPath.insert(id)
            for dependencyID in package.requiredSkillIDs {
                guard let dependency = byID[dependencyID] else {
                    issues.append("Required Skill does not exist: \(dependencyID).")
                    continue
                }
                if !dependency.isValid {
                    issues.append("Required Skill is structurally invalid: \(dependencyID).")
                }
                if dependency.role == "method" {
                    issues.append(
                        "A Triptych-local package cannot execute Method \(dependencyID) as a dependency. Each Action graph must contain only its one bound complete Method."
                    )
                }
                for mode in package.supportedModes where !dependency.supports(mode) {
                    issues.append(
                        "Required Skill \(dependencyID) does not support \(mode.rawValue) mode."
                    )
                }
                let dependencyIssues = graphIssues(
                    for: dependencyID,
                    path: nextPath
                )
                if !dependencyIssues.isEmpty {
                    issues.append(
                        "Required Skill has an invalid dependency graph: \(dependencyID)."
                    )
                }
                if dependencyIssues.contains(where: {
                    $0.localizedCaseInsensitiveContains("cycle")
                }) {
                    issues.append("The package dependency graph contains a cycle.")
                }
            }
            let result = Self.unique(issues)
            memoizedIssues[id] = result
            return result
        }

        return rawLocal.map { package in
            guard !protectedIDs.contains(package.id) else { return package }
            let additional = graphIssues(for: package.id, path: [])
                .filter { !package.validationIssues.contains($0) }
            return package.addingValidationIssues(additional)
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

    /// Replaces one editable Working Method as a whole package. The package
    /// exchange is descriptor-relative and the Action binding is checked both
    /// immediately before and after it. Before archival begins, a failed
    /// post-exchange check restores the original package while preserving the
    /// competing revision. Once archival begins, a failure is recovery-required
    /// and never exchanges package identities again.
    private func atomicallyEditWorkingMethod(
        packageID: String,
        actionID: ResearchActionID,
        source: String,
        expectedPackageRevision: DocumentFingerprint,
        expectedBindingRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        try ensureSkillsDirectory()
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsURL.path
        )
        let originalSources = try SecureResearchSkillPackageIO.strictPackageSources(
            rootDescriptor: rootDescriptor,
            packageID: packageID
        )
        guard Self.packageRevision(sources: originalSources) == expectedPackageRevision else {
            throw ResearchSkillError.stalePackage(packageID)
        }
        var replacementSources = originalSources
        replacementSources["SKILL.md"] = source
        let replacementRevision = Self.packageRevision(sources: replacementSources)
        let stageName = ".working-edit-\(UUID().uuidString.lowercased())"
        guard let workingMethodRecoveryStore else {
            throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(packageID)
        }
        let recoveryReservation = workingMethodRecoveryStore.reserve(
            packageID: packageID,
            packageRevision: expectedPackageRevision
        )
        var didSwap = false
        var archiveAttempted = false
        do {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: rootDescriptor,
                packageName: stageName,
                sources: replacementSources
            )
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: stageName
            ) == replacementSources else {
                throw ResearchSkillError.stalePackage(packageID)
            }
            try workingMethodHooks.handler(
                .beforePackageReplacement(packageID: packageID)
            )
            guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                skillsURL,
                identity: rootIdentity
            ), try workingMethodBindingStillSelects(
                packageID: packageID,
                actionID: actionID,
                expectedRevision: expectedBindingRevision
            ) else {
                throw ResearchSkillBindingError.staleBindingFile
            }
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: packageID
            ) == originalSources else {
                throw ResearchSkillError.stalePackage(packageID)
            }
            try SecureResearchSkillPackageIO.swapPackages(
                rootDescriptor: rootDescriptor,
                first: packageID,
                second: stageName
            )
            didSwap = true
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: stageName
            ) == originalSources else {
                throw ResearchSkillError.stalePackage(packageID)
            }
            try workingMethodHooks.handler(
                .afterPackageReplacement(packageID: packageID)
            )
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: packageID
            ) == replacementSources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ),
                  try workingMethodBindingStillSelects(
                      packageID: packageID,
                      actionID: actionID,
                      expectedRevision: expectedBindingRevision
                  ), fsync(rootDescriptor) == 0 else {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            let package = try localPackage(id: packageID)
            guard package.revision == replacementRevision else {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            // The new package and unchanged binding are already committed and
            // verified. Archive the displaced package without discarding late
            // writes through an already-open descriptor.
            archiveAttempted = true
            try workingMethodRecoveryStore.archive(
                sourceParentDescriptor: rootDescriptor,
                sourceName: stageName,
                reservation: recoveryReservation
            )
            try workingMethodHooks.handler(
                .afterDisplacedPackageArchive(packageID: packageID)
            )
            guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                skillsURL,
                identity: rootIdentity
            ), try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: packageID
            ) == replacementSources,
                  try workingMethodBindingStillSelects(
                      packageID: packageID,
                      actionID: actionID,
                      expectedRevision: expectedBindingRevision
                  ) else {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            return package
        } catch {
            // Archive may have moved the displaced inode or published a
            // verified cross-volume copy. From this point onward, another
            // exchange could reassign an external participant's late writes
            // to the stable package path. Preserve every artifact and require
            // explicit recovery instead of attempting rollback.
            if archiveAttempted {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            guard didSwap else {
                do {
                    try SecureResearchSkillPackageIO.removePackage(
                        rootDescriptor: rootDescriptor,
                        packageName: stageName
                    )
                } catch {
                    throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                        packageID
                    )
                }
                throw error
            }
            do {
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: packageID,
                    second: stageName
                )
                guard try SecureResearchSkillPackageIO.strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: packageID
                ) == originalSources else {
                    throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                        packageID
                    )
                }
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                        packageID
                    )
                }
            } catch {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            do {
                let rollbackSources = try SecureResearchSkillPackageIO.strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: stageName
                )
                let rollbackReservation = workingMethodRecoveryStore.reserve(
                    packageID: packageID,
                    packageRevision: Self.packageRevision(sources: rollbackSources)
                )
                try workingMethodRecoveryStore.archive(
                    sourceParentDescriptor: rootDescriptor,
                    sourceName: stageName,
                    reservation: rollbackReservation
                )
            } catch {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(
                    packageID
                )
            }
            throw error
        }
    }

    private func workingMethodBindingStillSelects(
        packageID: String,
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) throws -> Bool {
        guard let snapshot = try workingMethodBindingSnapshot(),
              snapshot.revision == expectedRevision,
              let binding = snapshot.document.binding(for: actionID) else {
            return false
        }
        let editableState = binding.state == .installedDefault
            || (actionID == .manuscript && binding.state == .researcherSkill)
        return editableState && binding.packageID == packageID
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

    func ensureSkillsDirectoryForInstallation() throws {
        try ensureSkillsDirectory()
    }

    func installPackageForInstallation(
        id: String,
        sources: [String: String],
        onPublished: @escaping (
            SecureResearchSkillPackageIO.DirectoryIdentity
        ) -> Void
    ) throws -> (
        package: ResearchSkillPackage,
        identity: SecureResearchSkillPackageIO.DirectoryIdentity
    ) {
        try installLocalPackage(
            id: id,
            sources: sources,
            onPublished: onPublished
        )
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

    private func ensureControlDirectoryForGuidance() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
    }

    private static let maximumActionProfileDocumentByteCount = 8_388_608

    private func validateActionProfileBinding(
        _ binding: ResearchActionProfileBinding
    ) throws {
        let package: ResearchSkillPackage
        do {
            package = try localPackage(id: binding.packageID)
        } catch let error as ResearchSkillError {
            throw ResearchActionProfileStorageError.invalidPackage(
                binding.packageID,
                [error.localizedDescription]
            )
        }
        guard package.origin == .triptych,
              package.isValid,
              package.skillClass != .system else {
            throw ResearchActionProfileStorageError.invalidPackage(
                binding.packageID,
                package.validationIssues.isEmpty
                    ? ["Only a valid Triptych-local Method or Researcher Skill can own an Action Profile."]
                    : package.validationIssues
            )
        }
        guard package.supports(binding.profile.actionID) else {
            throw ResearchActionProfileStorageError.packageDoesNotSupportAction(
                packageID: binding.packageID,
                actionID: binding.profile.actionID
            )
        }
    }

    private struct ResearchSkillUsageSnapshot: Equatable {
        let workingMethodRevision: DocumentFingerprint?
        let actionProfileRevision: DocumentFingerprint?
        let retainedBindingRevision: DocumentFingerprint?
    }

    private func validatePackageIsUnused(
        _ packageID: String
    ) throws -> ResearchSkillUsageSnapshot {
        let working = try workingMethodBindingSnapshot()
        if working?.document.actionBindings.values.contains(where: {
               $0.packageID == packageID && $0.state != .disabled
           }) == true {
            throw ResearchActionProfileStorageError.packageInUse(packageID)
        }
        let profiles = try actionProfileSnapshot()
        if profiles?.document.actionBindings.values.contains(where: {
               $0.packageID == packageID
           }) == true {
            throw ResearchActionProfileStorageError.packageInUse(packageID)
        }
        let retained = try bindingSnapshot()
        if let legacy = retained?.document {
            let legacyReferences = Set(legacy.functionBindings.values)
                .union(legacy.functionSkillBindings.values.flatMap { $0 })
                .union(legacy.functionPracticeBindings.values.flatMap { values in
                    values.map(\.packageID)
                })
                .union([legacy.citationBinding, legacy.bibliographyMethodBinding].compactMap { $0 })
            if legacyReferences.contains(packageID) {
                throw ResearchActionProfileStorageError.packageInUse(packageID)
            }
        }
        return ResearchSkillUsageSnapshot(
            workingMethodRevision: working?.revision,
            actionProfileRevision: profiles?.revision,
            retainedBindingRevision: retained?.revision
        )
    }

    @discardableResult
    private func saveWorkingMethodBindingDocument(
        _ document: ResearchWorkingMethodBindingDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchWorkingMethodBindingSnapshot {
        try ensureControlDirectoryForGuidance()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= 1_048_576,
              document.actionBindings.count <= 256 else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method binding v2 exceeds its bounded storage contract."
            )
        }

        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            controlURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: controlURL.path
        )
        let leaf = workingMethodBindingsURL.lastPathComponent
        let current = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: rootDescriptor,
            leaf: leaf,
            path: workingMethodBindingsURL.path,
            maximumByteCount: 1_048_576
        )
        if let current {
            guard let expectedRevision,
                  DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchSkillBindingError.staleBindingFile
            }
        } else if expectedRevision != nil {
            throw ResearchSkillBindingError.staleBindingFile
        }

        let stageName = ".working-binding-\(UUID().uuidString.lowercased())"
        var stageCreated = false
        var didCommit = false
        do {
            try SecureResearchSkillPackageIO.createDataFile(
                parentDescriptor: rootDescriptor,
                leaf: stageName,
                data: data,
                path: stageName
            )
            stageCreated = true
            if current != nil {
                do {
                    try SecureResearchSkillPackageIO.swapPackages(
                        rootDescriptor: rootDescriptor,
                        first: leaf,
                        second: stageName
                    )
                } catch {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            } else {
                do {
                    try SecureResearchSkillPackageIO.movePackageExclusively(
                        rootDescriptor: rootDescriptor,
                        source: stageName,
                        destination: leaf
                    )
                } catch {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            }
            didCommit = true
            try workingMethodHooks.handler(.afterBindingCommit)
            if let current {
                let displaced = try SecureResearchSkillPackageIO.readDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName,
                    maximumByteCount: 1_048_576
                )
                guard displaced == current else {
                    throw ResearchSkillBindingError.staleBindingFile
                }
            }
            guard fsync(rootDescriptor) == 0 else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let readback = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: workingMethodBindingsURL.path,
                maximumByteCount: 1_048_576
            )
            guard readback == data,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      controlURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillBindingError.unsafeBindingFile
            }
            let snapshot = ResearchWorkingMethodBindingSnapshot(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
            if current != nil {
                try SecureResearchSkillPackageIO.removeDataFile(
                    parentDescriptor: rootDescriptor,
                    leaf: stageName,
                    path: stageName
                )
                guard fsync(rootDescriptor) == 0 else {
                    throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
                }
            }
            return snapshot
        } catch {
            guard didCommit else {
                if stageCreated {
                    try? SecureResearchSkillPackageIO.removeDataFile(
                        parentDescriptor: rootDescriptor,
                        leaf: stageName,
                        path: stageName
                    )
                }
                throw error
            }
            let readback = try? SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: rootDescriptor,
                leaf: leaf,
                path: workingMethodBindingsURL.path,
                maximumByteCount: 1_048_576
            )
            let snapshot = readback == data
                ? ResearchWorkingMethodBindingSnapshot(
                    document: document,
                    revision: DocumentFingerprint(data: data)
                )
                : nil
            throw ResearchWorkingMethodBindingWriteFailure.committed(
                snapshot: snapshot,
                underlying: error
            )
        }
    }

    private func validateNewTriptychWorkingMethodDocument(
        _ document: ResearchWorkingMethodBindingDocument
    ) throws {
        let expectedActions = Set(
            Self.defaultWorkingMethodDescriptors.map(\.actionID) + [.manuscript]
        )
        let actualActions = Set(document.actionBindings.keys.compactMap(
            ResearchActionID.init(rawValue:)
        ))
        guard actualActions == expectedActions,
              document.actionBindings.count == expectedActions.count else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A new Triptych requires six explicit Working Methods and disabled Manuscript."
            )
        }
        for descriptor in Self.defaultWorkingMethodDescriptors {
            guard let binding = document.binding(for: descriptor.actionID),
                  binding.state == .installedDefault,
                  binding.packageID == descriptor.workingPackageID else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "New-Triptych Working Method binding is incomplete for \(descriptor.actionID.rawValue)."
                )
            }
        }
        guard document.binding(for: .manuscript)?.state == .disabled else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Manuscript must be explicitly disabled during Triptych bootstrap."
            )
        }
    }

    private func validateWorkingMethodBinding(
        _ binding: ResearchWorkingMethodBinding,
        for actionID: ResearchActionID
    ) throws {
        guard binding.state != .disabled else { return }
        guard let packageID = binding.packageID else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "An active Working Method requires one package."
            )
        }
        if binding.state == .installedDefault {
            guard packageID == Self.defaultWorkingMethodDescriptor(for: actionID)?
                .workingPackageID else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The installed-default state must retain the stable Working Method package for \(actionID.rawValue)."
                )
            }
        } else if Self.defaultWorkingMethodDescriptors.contains(where: {
            $0.workingPackageID == packageID
        }) {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A default Working Method package cannot be relabeled as a Researcher Skill."
            )
        }
        guard let package = try skills().first(where: {
            $0.origin == .triptych && $0.id == packageID
        }) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Working Method package is not installed: \(packageID)."
            )
        }
        guard let expectedFunction = Self.expectedFunction(for: actionID) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Custom Action Methods require an Action Profile before activation."
            )
        }
        guard package.origin == .triptych,
              package.isValid,
              package.role == "method",
              package.supports(actionID),
              package.supports(expectedFunction),
              !isCitationMethod(package) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Package \(packageID) is not a valid complete Method for Action \(actionID.rawValue)."
            )
        }
    }

    private func validateBindingDocument(
        _ document: ResearchSkillBindingDocument
    ) throws {
        guard document.schemaVersion == ResearchSkillBindingDocument.currentSchemaVersion else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Unsupported schema version \(document.schemaVersion)."
            )
        }
        let functionKeys = Set(document.functionBindings.keys)
            .union(document.functionSkillBindings.keys)
            .union(document.functionPracticeBindings.keys)
        for rawFunction in functionKeys {
            guard let function = ResearchFunctionID(rawValue: rawFunction) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "Unknown or non-skill function binding: \(rawFunction)."
                )
            }
            try validateFunctionSkillSelection(ResearchFunctionSkillSelection(
                function: function,
                primaryPackageID: document.functionBindings[rawFunction],
                supplementalPackageIDs: document.functionSkillBindings[rawFunction] ?? [],
                selectedPractices: document.functionPracticeBindings[rawFunction] ?? []
            ))
        }
        if let packageID = document.citationBinding {
            guard Self.isValidIdentifier(packageID) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The citation binding has an invalid package identifier."
                )
            }
            let package: ResearchSkillPackage
            do {
                package = try localPackage(id: packageID)
            } catch {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The citation binding must name an installed Triptych-local package."
                )
            }
            guard package.origin == .triptych,
                  package.isValid,
                  package.supports(.fidelity),
                  package.provides(.citationVerification),
                  package.provides(.citationFormatting) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The citation binding lacks Fidelity or a required citation capability."
                )
            }
            // Missing style remains decodable so a pre-style binding can be
            // surfaced as a precise Settings repair. New writes always include
            // and validate the semantic style.
            if let style = document.citationStyle {
                guard package.citationStyles.contains(style),
                      package.citationStyleResources[style] != nil else {
                    throw ResearchSkillBindingError.invalidBindingDocument(
                        "The citation binding style is not explicitly supported by its package."
                    )
                }
            }
        } else if document.citationStyle != nil {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A citation style cannot be selected without a citation package."
            )
        }
        if let packageID = document.bibliographyMethodBinding {
            guard Self.isValidIdentifier(packageID) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The bibliography method binding has an invalid package identifier."
                )
            }
            let package: ResearchSkillPackage
            do {
                package = try localPackage(id: packageID)
            } catch {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The bibliography method binding must name an installed Triptych-local package."
                )
            }
            guard package.origin == .triptych,
                  package.isValid,
                  package.role == "method",
                  package.provides(.bibliographyRecommendation) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The bibliography method binding lacks the required capability."
                )
            }
        }
    }

    private func validateFunctionSkillSelection(
        _ selection: ResearchFunctionSkillSelection
    ) throws {
        if selection.function == .discuss, selection.primaryPackageID != nil {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Discuss transport is protected System guidance and cannot be replaced by a Researcher Skill."
            )
        }
        let selectedPracticeIDs = selection.selectedPractices.map(\.selectionID)
        guard Set(selectedPracticeIDs).count == selectedPracticeIDs.count else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A function cannot select the same Practice more than once."
            )
        }
        let supplementalIDs = selection.supplementalPackageIDs
        guard Set(supplementalIDs).count == supplementalIDs.count else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "A function cannot select the same supplemental Skill more than once."
            )
        }
        if let primary = selection.primaryPackageID,
           supplementalIDs.contains(primary) {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "The same package cannot be both primary and supplemental."
            )
        }

        if let packageID = selection.primaryPackageID {
            let package = try boundLocalPackage(
                id: packageID,
                function: selection.function,
                purpose: "primary"
            )
            guard package.role != "practice",
                  !isCitationMethod(package),
                  package.role == "method"
                    || (package.role == "specialist"
                        && !composesWithFunction(package, function: selection.function)) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The primary binding for \(selection.function.rawValue) must be a complete non-citation Researcher Skill."
                )
            }
        }

        for packageID in supplementalIDs {
            let package = try boundLocalPackage(
                id: packageID,
                function: selection.function,
                purpose: "supplemental"
            )
            guard package.role == "specialist",
                  !isCitationMethod(package),
                  composesWithFunction(package, function: selection.function) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "Supplemental binding \(packageID) must be a non-citation specialist that explicitly composes with this function."
                )
            }
        }

        for practice in selection.selectedPractices {
            guard Self.isValidIdentifier(practice.packageID),
                  Self.isValidIdentifier(practice.practiceID) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "Practice bindings require stable lowercase identifiers."
                )
            }
            let package = try boundLocalPackage(
                id: practice.packageID,
                function: selection.function,
                purpose: "Practice"
            )
            guard package.role == "practice",
                  package.practiceResources[practice.practiceID] != nil else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "Practice \(practice.selectionID) is not declared by a compatible Triptych-local Practice package."
                )
            }
        }
    }

    private func boundLocalPackage(
        id: String,
        function: ResearchFunctionID,
        purpose: String
    ) throws -> ResearchSkillPackage {
        guard Self.isValidIdentifier(id) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "The \(purpose) binding has an invalid package identifier."
            )
        }
        let package: ResearchSkillPackage
        do {
            package = try localPackage(id: id)
        } catch {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "The \(purpose) binding must name an installed Triptych-local package: \(id)."
            )
        }
        guard package.origin == .triptych,
              package.isValid,
              package.supports(function) else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Package \(id) does not validly support \(function.rawValue)."
            )
        }
        return package
    }

    private func isCitationMethod(_ package: ResearchSkillPackage) -> Bool {
        package.provides(.citationVerification)
            || package.provides(.citationFormatting)
            || !package.citationStyleResources.isEmpty
    }

    private func composesWithFunction(
        _ package: ResearchSkillPackage,
        function: ResearchFunctionID
    ) -> Bool {
        package.requiredSkillIDs.contains { dependencyID in
            (try? self.package(id: dependencyID))?.supports(function) == true
        }
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

    /// Validates a complete in-memory replacement through the same package,
    /// declared-resource, dependency, and cycle rules used for installed local
    /// packages. Nothing is written; callers use the returned package as the
    /// authoritative structural result before issuing maintenance confirmation.
    func validatedProposedResearcherPackage(
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
              Self.packageRevision(sources: sources) == revision else {
            throw ResearchSkillError.unsafePackage(id)
        }

        let resourcePaths = Set(sources.keys)
        let inspected = ResearchSkillInspector.inspect(
            id: id,
            source: source,
            origin: .triptych,
            revision: revision
        )
        let candidate = inspected.addingValidationIssues(
            Self.declaredResourceValidationIssues(
                for: inspected,
                availableResourcePaths: resourcePaths
            )
        )
        let bundled = try bundledCatalogPackages()
        let local = try localSkills().filter { $0.id != id } + [candidate]
        let validated = try validatedLocalSkills(rawLocal: local, bundled: bundled)
        guard let result = validated.first(where: { $0.id == id }) else {
            throw ResearchSkillError.packageNotFound(id)
        }
        return result
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
        return parsed.addingValidationIssues(
            Self.declaredResourceValidationIssues(
                for: parsed,
                availableResourcePaths: resources
            )
        )
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
            issues.append("Citation style \(style) has no declared citation style resource.")
        }
        return Self.unique(issues)
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
        for directory in ["references", "templates", "evals"] {
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

    private static func packageRevision(
        sources: [String: String]
    ) -> DocumentFingerprint {
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

    private static func skillMode(for actionID: ResearchActionID) -> ResearchSkillMode {
        switch actionID {
        case .discuss: .discuss
        case .analyze: .analyze
        case .synthesize: .synthesize
        case .write: .write
        case .critique: .review
        case .checkFidelity: .audit
        case .manuscript: .manuscript
        default: .all
        }
    }

    private static func defaultResourcePaths(
        for actionID: ResearchActionID,
        fidelityChecks: Set<FidelityCheck>
    ) -> Set<String> {
        switch actionID {
        case .analyze, .synthesize, .critique, .manuscript:
            ["references/method.md"]
        case .discuss:
            ["references/method.md", "references/response-contract.md"]
        case .write:
            ["references/method.md", "references/feedback.md"]
        case .checkFidelity:
            Set([
                fidelityChecks.contains(.content) ? "references/content.md" : nil,
                fidelityChecks.contains(.citations) ? "references/citations.md" : nil,
            ].compactMap { $0 })
        default:
            []
        }
    }

    private static func requiredSystemResourcePaths(
        for packageID: String,
        mode: ResearchSkillMode
    ) -> Set<String> {
        switch packageID {
        case "scholium-core-protocol" where mode == .manuscript:
            return ["references/mixed-mode.md"]
        case "scholium-research-integration":
            var resources: Set<String> = ["references/cli-contract.md"]
            if [.analyze, .synthesize, .write, .review].contains(mode) {
                resources.insert("references/persistence-method.md")
            }
            return resources
        case "scholium-discussion-protocol" where mode == .discuss:
            return ["references/record-contract.md"]
        default:
            return []
        }
    }

    /// Researcher-owned packages are not required to mirror Scholium's
    /// bundled file layout. Load only bounded resources explicitly named by
    /// their entry point or another already-declared resource.
    private static func declaredResourceClosure(
        in sources: [String: String]
    ) -> Set<String> {
        var selected: Set<String> = []
        var pending = ["SKILL.md"]
        while let path = pending.popLast() {
            guard let source = sources[path] else { continue }
            for candidate in sources.keys where candidate != "SKILL.md" {
                if source.contains(candidate), selected.insert(candidate).inserted {
                    pending.append(candidate)
                }
            }
        }
        return selected
    }

    private struct DefaultWorkingMethodDescriptor: Sendable {
        let actionID: ResearchActionID
        let function: ResearchFunctionID
        let bundledPackageID: String
        let workingPackageID: String
    }

    private static let defaultWorkingMethodDescriptors: [DefaultWorkingMethodDescriptor] = [
        DefaultWorkingMethodDescriptor(
            actionID: .discuss,
            function: .discuss,
            bundledPackageID: "scholium-discuss",
            workingPackageID: "scholium-working-discuss"
        ),
        DefaultWorkingMethodDescriptor(
            actionID: .analyze,
            function: .develop,
            bundledPackageID: "scholium-analyze",
            workingPackageID: "scholium-working-analyze"
        ),
        DefaultWorkingMethodDescriptor(
            actionID: .synthesize,
            function: .develop,
            bundledPackageID: "scholium-synthesize",
            workingPackageID: "scholium-working-synthesize"
        ),
        DefaultWorkingMethodDescriptor(
            actionID: .write,
            function: .revise,
            bundledPackageID: "scholium-write",
            workingPackageID: "scholium-working-write"
        ),
        DefaultWorkingMethodDescriptor(
            actionID: .critique,
            function: .critique,
            bundledPackageID: "scholium-critique",
            workingPackageID: "scholium-working-critique"
        ),
        DefaultWorkingMethodDescriptor(
            actionID: .checkFidelity,
            function: .fidelity,
            bundledPackageID: "scholium-content-fidelity",
            workingPackageID: "scholium-working-content-fidelity"
        ),
    ]

    private static func defaultWorkingMethodDescriptor(
        for actionID: ResearchActionID
    ) -> DefaultWorkingMethodDescriptor? {
        defaultWorkingMethodDescriptors.first { $0.actionID == actionID }
    }

    private static func editableWorkingMethodPackageID(
        for actionID: ResearchActionID
    ) -> String? {
        if actionID == .manuscript {
            return "scholium-working-manuscript"
        }
        return defaultWorkingMethodDescriptor(for: actionID)?.workingPackageID
    }

    private static func expectedFunction(
        for actionID: ResearchActionID
    ) -> ResearchFunctionID? {
        if let descriptor = defaultWorkingMethodDescriptor(for: actionID) {
            return descriptor.function
        }
        return actionID == .manuscript ? .manuscript : nil
    }

    private func workingMethodSources(
        for descriptor: DefaultWorkingMethodDescriptor
    ) throws -> [String: String] {
        let entry = try catalog().entry(id: descriptor.bundledPackageID)
        guard entry.skillClass == .method,
              entry.supportedActions == [descriptor.actionID],
              entry.supportedFunctions == [descriptor.function] else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "Bundled reference \(descriptor.bundledPackageID) is not the unique Method for \(descriptor.actionID.rawValue)."
            )
        }
        var sources: [String: String] = [:]
        for path in try BundledResearchSkillLibrary.resourcePaths(for: entry) {
            var source = try BundledResearchSkillLibrary.resource(
                for: entry,
                relativePath: path
            )
            if path == "SKILL.md" {
                source = try Self.injectedResearcherRoutingMetadata(
                    into: source,
                    from: entry,
                    allowsEvolution: true
                )
                source = try Self.replacingSkillName(
                    in: source,
                    with: descriptor.workingPackageID
                )
            }
            sources[path] = source
        }
        return sources
    }

    private func installLocalPackage(
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
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(id)
            }
            let installed = try localPackage(id: id)
            let recheckedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: id,
                path: id
            )
            defer { Darwin.close(recheckedDescriptor) }
            guard installed.revision == Self.packageRevision(sources: sources),
                  try SecureResearchSkillPackageIO.identity(
                      of: recheckedDescriptor,
                      path: id
                  ) == installedIdentity,
                  try SecureResearchSkillPackageIO.strictPackageSources(
                      packageDescriptor: recheckedDescriptor,
                      packageID: id
                  ) == sources else {
                throw ResearchSkillBindingError.workingMethodEditRecoveryRequired(id)
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

    private func rollbackWorkingMethodReplacement(
        rootDescriptor: Int32,
        packageID: String,
        stageName: String,
        replacedExisting: Bool
    ) throws {
        if replacedExisting {
            try SecureResearchSkillPackageIO.swapPackages(
                rootDescriptor: rootDescriptor,
                first: packageID,
                second: stageName
            )
        } else {
            try SecureResearchSkillPackageIO.movePackageExclusively(
                rootDescriptor: rootDescriptor,
                source: packageID,
                destination: stageName
            )
        }
        guard fsync(rootDescriptor) == 0 else {
            throw ResearchSkillBindingError.workingMethodRestoreRecoveryRequired(
                packageID
            )
        }
    }

    private static func replacingSkillName(
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

    private static func injectedResearcherRoutingMetadata(
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
                routing.append("    \(style): \(entry.citationStyleResources[style]!)")
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
                routing.append("    \(identifier): \(entry.practiceResources[identifier]!)")
            }
        }
        var result = Array(lines[...closing])
        result.insert(contentsOf: routing, at: closing)
        result.append(contentsOf: lines[(closing + 1)...])
        return result.joined(separator: "\n")
    }

}
