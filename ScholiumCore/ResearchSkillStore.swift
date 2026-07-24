import ScholiumContracts
import Foundation
import Yams

/// Owns the only supported user-skill root:
/// `.scholium/skills/<skill-id>/SKILL.md` beside the Works vault.
public actor ResearchSkillStore {
    public nonisolated let skillsURL: URL
    public nonisolated let bindingsURL: URL

    private let controlURL: URL
    private let fileManager: FileManager

    public init(controlURL: URL, fileManager: FileManager = .default) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL
            .appendingPathComponent("skills", isDirectory: true)
        self.bindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent("research-skill-bindings.json", isDirectory: false)
        self.fileManager = fileManager
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

    /// Resolves the bundled Method for one public Action or one explicit
    /// Triptych override. The protected Function remains part of the current
    /// execution layer, but can no longer collapse Analyze and Synthesize into
    /// one ambiguous package.
    public func functionBindingResolution(
        for function: ResearchFunctionID,
        actionID: ResearchActionID
    ) throws -> ResearchSkillBindingResolution {
        let rawBindingRevision = try? bindingFileRevision()
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
        let snapshot: ResearchSkillBindingSnapshot?
        do {
            snapshot = try bindingSnapshot()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .malformed(error.localizedDescription),
                bindingRevision: rawBindingRevision
            )
        }

        if let id = snapshot?.document.functionBindings[function.rawValue] {
            let bound: ResearchSkillPackage
            do {
                bound = try package(id: id)
            } catch {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundledCandidates.isEmpty,
                    installedCandidateIDs: localCandidates,
                    issue: .invalidPackage(id),
                    bindingRevision: rawBindingRevision
                )
            }
            guard bound.isValid else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundledCandidates.isEmpty,
                    installedCandidateIDs: localCandidates,
                    issue: .invalidPackage(id),
                    bindingRevision: rawBindingRevision
                )
            }
            guard bound.supports(function) else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundledCandidates.isEmpty,
                    installedCandidateIDs: localCandidates,
                    issue: .unsupportedFunction(packageID: id, function: function),
                    bindingRevision: rawBindingRevision
                )
            }
            guard bound.supports(actionID) else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundledCandidates.isEmpty,
                    installedCandidateIDs: localCandidates,
                    issue: .unsupportedAction(packageID: id, actionID: actionID),
                    bindingRevision: rawBindingRevision
                )
            }
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                package: bound,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                bindingRevision: rawBindingRevision
            )
        }

        // Manuscript is an optional bundled reference, not a default Action.
        // A researcher must explicitly bind a Triptych-local Method before
        // the retained Function transport may prepare a new run.
        if actionID == .manuscript {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: .missing,
                bindingRevision: rawBindingRevision
            )
        }

        guard bundledCandidates.count == 1, let primary = bundledCandidates.first else {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundledCandidates.isEmpty,
                installedCandidateIDs: localCandidates,
                issue: bundledCandidates.isEmpty
                    ? .missing
                    : .malformed(
                        "More than one bundled Method supports Action \(actionID.rawValue)."
                    ),
                bindingRevision: rawBindingRevision
            )
        }
        return ResearchSkillBindingResolution(
            source: .bundledDefault,
            package: primary,
            bundledTemplateAvailable: true,
            installedCandidateIDs: localCandidates,
            bindingRevision: rawBindingRevision
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
        fidelityChecks: Set<FidelityCheck> = [],
        citationStyle: String? = nil,
        additionalSkillIDs: [String] = [],
        primaryResourcePaths: Set<String> = [],
        additionalResourcePaths: [String: Set<String>] = [:]
    ) throws -> [ResolvedResearchSkillSelection] {
        let primaryResolution = try functionBindingResolution(
            for: function,
            actionID: actionID
        )
        guard let primary = primaryResolution.package, primaryResolution.issue == nil else {
            throw ResearchSkillBindingError.unresolvedBinding(
                primaryResolution.issue ?? .missing
            )
        }

        // Protected Action mechanism is Application-owned. A researcher
        // Method may omit or even misstate dependencies without detaching the
        // exact read/write and completion adapter from a mediated run.
        var requestedIDs = [primary.id, "scholium-research-integration"]
            + additionalSkillIDs
        if actionID == .discuss {
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
            for: Self.skillMode(for: actionID),
            requestedSkillIDs: Self.unique(requestedIDs)
        )
        var selections: [ResolvedResearchSkillSelection] = []
        for package in packages {
            guard let packageRevision = package.revision else {
                throw ResearchSkillError.invalidPackage(package.id, package.validationIssues)
            }
            let resourceSnapshot = try packageResourceSnapshot(
                id: package.id,
                expectedRevision: packageRevision
            )
            var selected: Set<String> = ["SKILL.md"]
            selected.formUnion(Self.requiredSystemResourcePaths(
                for: package.id,
                actionID: actionID
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
                packageRevision: packageRevision,
                availableResourcePaths: resourceSnapshot.keys.sorted(),
                loadedResources: loaded
            ))
        }
        return selections
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

    private static func declaredResourceValidationIssues(
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
        actionID: ResearchActionID
    ) -> Set<String> {
        switch packageID {
        case "scholium-core-protocol" where actionID == .manuscript:
            return ["references/mixed-mode.md"]
        case "scholium-research-integration":
            var resources: Set<String> = ["references/cli-contract.md"]
            if [.analyze, .synthesize, .write, .critique].contains(actionID) {
                resources.insert("references/persistence-method.md")
            }
            return resources
        case "scholium-discussion-protocol" where actionID == .discuss:
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
            "  supported_actions: [\(entry.supportedActions.map(\.rawValue).joined(separator: ", "))]",
            "  supported_functions: [\(entry.supportedFunctions.map(\.rawValue).joined(separator: ", "))]",
            "  capabilities: [\(entry.capabilities.map(\.rawValue).joined(separator: ", "))]",
            "  citation_styles: [\(entry.citationStyles.joined(separator: ", "))]",
            "  allow_evolution: false",
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
