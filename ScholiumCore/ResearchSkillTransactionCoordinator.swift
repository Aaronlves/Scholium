import ScholiumContracts
import Darwin
import Foundation

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

/// Owns the only supported Triptych-local Skill root:
/// `.scholium/skills/<skill-id>/SKILL.md` beside the Works vault.
public actor ResearchSkillTransactionCoordinator {
    public nonisolated let skillsURL: URL
    public nonisolated let workingMethodBindingsURL: URL
    public nonisolated let actionProfileBindingsURL: URL
    public nonisolated let citationMethodBindingsURL: URL
    public nonisolated let bibliographyMethodBindingsURL: URL

    private let controlURL: URL
    nonisolated let legacyFunctionBindingsURL: URL
    private let fileManager: FileManager
    private let workingMethodHooks: ResearchWorkingMethodStoreHooks
    private let workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore?
    let workingMethods: ResearchWorkingMethodStore
    let actionProfiles: ResearchActionProfileStore
    let citationMethods: ResearchCitationMethodStore
    let bibliographyMethods: ResearchBibliographyMethodStore
    private let packageRepository: ResearchSkillPackageRepository

    public init(
        controlURL: URL,
        fileManager: FileManager = .default,
        workingMethodRecoveryStore: ResearchWorkingMethodRecoveryStore? = nil
    ) {
        self.controlURL = controlURL.standardizedFileURL
        self.skillsURL = controlURL.standardizedFileURL
            .appendingPathComponent("skills", isDirectory: true)
        self.legacyFunctionBindingsURL = controlURL.standardizedFileURL
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
        self.citationMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-citation-method-v1.json",
                isDirectory: false
            )
        self.bibliographyMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-bibliography-method-v1.json",
                isDirectory: false
            )
        self.fileManager = fileManager
        workingMethodHooks = .none
        self.workingMethodRecoveryStore = workingMethodRecoveryStore
        self.packageRepository = ResearchSkillPackageRepository(
            controlURL: controlURL,
            fileManager: fileManager,
            resolver: ResearchSkillResolver()
        )
        self.workingMethods = ResearchWorkingMethodStore(
            controlURL: controlURL.standardizedFileURL,
            documentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            ),
            fileManager: fileManager,
            hooks: .none
        )
        self.actionProfiles = ResearchActionProfileStore(
            controlURL: controlURL.standardizedFileURL,
            documentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-action-profiles-v1.json",
                isDirectory: false
            ),
            fileManager: fileManager,
            hooks: .none
        )
        self.citationMethods = ResearchCitationMethodStore(files: .init(
            controlURL: controlURL.standardizedFileURL,
            currentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-citation-method-v1.json",
                isDirectory: false
            ),
            legacyURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-skill-bindings.json",
                isDirectory: false
            ),
            fileManager: fileManager
        ))
        self.bibliographyMethods = ResearchBibliographyMethodStore(files: .init(
            controlURL: controlURL.standardizedFileURL,
            currentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-bibliography-method-v1.json",
                isDirectory: false
            ),
            legacyURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-skill-bindings.json",
                isDirectory: false
            ),
            fileManager: fileManager
        ))
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
        self.legacyFunctionBindingsURL = controlURL.standardizedFileURL
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
        self.citationMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-citation-method-v1.json",
                isDirectory: false
            )
        self.bibliographyMethodBindingsURL = controlURL.standardizedFileURL
            .appendingPathComponent(
                "research-bibliography-method-v1.json",
                isDirectory: false
            )
        self.fileManager = fileManager
        self.workingMethodRecoveryStore = workingMethodRecoveryStore
        self.workingMethodHooks = workingMethodHooks
        self.packageRepository = ResearchSkillPackageRepository(
            controlURL: controlURL,
            fileManager: fileManager,
            resolver: ResearchSkillResolver()
        )
        self.workingMethods = ResearchWorkingMethodStore(
            controlURL: controlURL.standardizedFileURL,
            documentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-working-method-bindings-v2.json",
                isDirectory: false
            ),
            fileManager: fileManager,
            hooks: workingMethodHooks
        )
        self.actionProfiles = ResearchActionProfileStore(
            controlURL: controlURL.standardizedFileURL,
            documentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-action-profiles-v1.json",
                isDirectory: false
            ),
            fileManager: fileManager,
            hooks: workingMethodHooks
        )
        self.citationMethods = ResearchCitationMethodStore(files: .init(
            controlURL: controlURL.standardizedFileURL,
            currentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-citation-method-v1.json",
                isDirectory: false
            ),
            legacyURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-skill-bindings.json",
                isDirectory: false
            ),
            fileManager: fileManager
        ))
        self.bibliographyMethods = ResearchBibliographyMethodStore(files: .init(
            controlURL: controlURL.standardizedFileURL,
            currentURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-bibliography-method-v1.json",
                isDirectory: false
            ),
            legacyURL: controlURL.standardizedFileURL.appendingPathComponent(
                "research-skill-bindings.json",
                isDirectory: false
            ),
            fileManager: fileManager
        ))
    }

    public nonisolated static func inspectDraft(
        id: String,
        source: String,
        origin: ResearchSkillOrigin = .triptych
    ) -> ResearchSkillPackage {
        ResearchSkillInspector.inspect(id: id, source: source, origin: origin)
    }

    public func skills() throws -> [ResearchSkillPackage] {
        try packageRepository.packages()
    }

    public func create(id: String, source: String) throws -> ResearchSkillPackage {
        try packageRepository.create(id: id, source: source)
    }

    public func duplicateBundled(id: String, as newID: String) throws -> ResearchSkillPackage {
        try packageRepository.duplicateBundled(id: id, as: newID)
    }

    public func save(id: String, source: String, expectedRevision: DocumentFingerprint) throws -> ResearchSkillPackage {
        try packageRepository.save(
            id: id,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    public func rename(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchSkillPackage {
        _ = try validatePackageIsUnused(id)
        return try packageRepository.rename(
            id: id,
            to: newID,
            expectedRevision: expectedRevision
        )
    }

    public func delete(id: String, expectedRevision: DocumentFingerprint) throws {
        let usage = try validatePackageIsUnused(id)
        try packageRepository.ensureSkillsDirectory()
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
        guard packageRepository.packageRevision(sources: sources) == expectedRevision else {
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
        try packageRepository.catalog()
    }

    /// Returns one protected package by stable catalog identifier. This is
    /// the bounded package-retrieval API used by the CLI and Settings; it
    /// never searches a global Skill directory.
    public func bundledPackage(id: String) throws -> ResearchSkillPackage {
        try packageRepository.bundledPackage(id: id)
    }

    /// Returns either one release-managed package or one direct
    /// Triptych-local package. No global Skill directory is searched.
    public func package(id: String) throws -> ResearchSkillPackage {
        try packageRepository.package(id: id)
    }

    public func resourcePaths(id: String) throws -> [String] {
        try packageRepository.resourcePaths(id: id)
    }

    public func resource(id: String, relativePath: String) throws -> String {
        try packageRepository.resource(id: id, relativePath: relativePath)
    }

    public func resourceFingerprint(
        id: String,
        relativePath: String
    ) throws -> DocumentFingerprint {
        try packageRepository.resourceFingerprint(
            id: id,
            relativePath: relativePath
        )
    }

    // MARK: - Citation Method

    public func citationMethodSnapshot() throws -> ResearchCitationMethodSnapshot? {
        try citationMethods.snapshotMigratingLegacyIfNeeded()
    }

    public func citationMethodBindingFileRevision() throws -> DocumentFingerprint? {
        try citationMethods.rawRevision()
    }

    @discardableResult
    public func activateCitationBinding(
        packageID: String,
        citationStyle: String? = nil,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchCitationMethodSnapshot {
        let observed = try citationMethods.rawRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        let package = try packageRepository.localPackage(id: packageID)
        let normalizedStyle = citationStyle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        return try citationMethods.save(
            ResearchCitationMethodDocument(
                packageID: packageID,
                citationStyle: normalizedStyle
            ),
            expectedRevision: expectedBindingRevision
        )
    }

    @discardableResult
    public func clearCitationBinding(
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchCitationMethodSnapshot {
        let observed = try citationMethods.rawRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        return try citationMethods.save(
            ResearchCitationMethodDocument(),
            expectedRevision: expectedBindingRevision
        )
    }

    public func adoptAPACitationStarter(
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchCitationMethodAdoption {
        let observed = try citationMethods.rawRevision()
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
            return ResearchCitationMethodAdoption(
                package: try packageRepository.localPackage(id: adopted.id),
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

        try packageRepository.ensureSkillsDirectory()
        do {
            var bindings: [ResearchActionID: ResearchWorkingMethodBinding] = [:]
            for descriptor in Self.defaultWorkingMethodDescriptors {
                let sources = try workingMethodSources(for: descriptor)
                let expectedRevision = packageRepository.packageRevision(sources: sources)
                let packageURL = try packageRepository.safePackageURL(id: descriptor.workingPackageID)
                if fileManager.fileExists(atPath: packageURL.path) {
                    let existing = try packageRepository.localPackage(id: descriptor.workingPackageID)
                    guard existing.revision == expectedRevision,
                          existing.isValid else {
                        throw ResearchSkillBindingError.invalidBindingDocument(
                            "A partial Working Method bootstrap conflicts with package \(descriptor.workingPackageID)."
                        )
                    }
                } else {
                    let installed = try packageRepository.installLocalPackage(
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
            return try workingMethods.save(
                document,
                expectedRevision: nil
            )
        } catch is ResearchWorkingMethodStoreWriteFailure {
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
        try workingMethods.snapshot()
    }

    public func workingMethodBindingFileRevision() throws -> DocumentFingerprint? {
        try workingMethods.rawRevision()
    }

    // MARK: - Researcher Action Profiles v1

    public func actionProfileSnapshot() throws -> ResearchActionProfileSnapshot? {
        try actionProfiles.snapshot()
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
        return try actionProfiles.save(
            document,
            expectedRevision: expectedRevision
        )
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
            return try workingMethods.save(
                replacement,
                expectedRevision: expectedBindingRevision
            )
        } catch is ResearchWorkingMethodStoreWriteFailure {
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
        let restoredRevision = packageRepository.packageRevision(sources: sources)
        _ = try validatedProposedResearcherPackage(
            id: descriptor.workingPackageID,
            sources: sources,
            revision: restoredRevision
        )
        try packageRepository.ensureSkillsDirectory()

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
            guard packageRepository.packageRevision(sources: currentSources) == expectedRevision else {
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
                    guard packageRepository.packageRevision(sources: rechecked) == expectedRevision else {
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

            let binding = try workingMethods.save(
                replacementDocument,
                expectedRevision: expectedBindingRevision
            )
            committedBinding = binding
            let package = try packageRepository.localPackage(id: descriptor.workingPackageID)
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
        } catch is ResearchWorkingMethodStoreWriteFailure {
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
                    rollbackPreservesExternalState = packageRepository.packageRevision(
                        sources: installedSources
                    ) == restoredRevision
                    if rollbackPreservesExternalState,
                       let displacedRevision {
                        let displacedSources = try SecureResearchSkillPackageIO
                            .strictPackageSources(
                                rootDescriptor: rootDescriptor,
                                packageID: stageName
                            )
                        rollbackPreservesExternalState = packageRepository.packageRevision(
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
                        packageRevision: packageRepository.packageRevision(sources: rollbackSources)
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

    /// Resolves the complete Source Analyzer used by the Triptych-owned
    /// Recommended Bibliography capability. A missing explicit binding uses
    /// the release-managed template; a broken explicit binding never falls
    /// back silently.
    public func bibliographyMethodBindingResolution() throws -> ResearchSkillBindingResolution {
        let revision = try? bibliographyMethods.rawRevision()
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
        let snapshot: ResearchBibliographyMethodSnapshot?
        do {
            snapshot = try bibliographyMethods.snapshotMigratingLegacyIfNeeded()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                issue: .malformed(error.localizedDescription),
                bindingRevision: revision
            )
        }
        let bindingRevision = snapshot?.revision ?? revision
        if let packageID = snapshot?.document.packageID {
            guard let package = installed.first(where: { $0.id == packageID }) else {
                return ResearchSkillBindingResolution(
                    source: .triptychBinding,
                    bundledTemplateAvailable: !bundled.isEmpty,
                    installedCandidateIDs: installed.map(\.id).sorted(),
                    issue: .invalidPackage(packageID),
                    bindingRevision: bindingRevision
                )
            }
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                package: package,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                bindingRevision: bindingRevision
            )
        }
        guard bundled.count == 1, let package = bundled.first else {
            return ResearchSkillBindingResolution(
                source: .bundledDefault,
                bundledTemplateAvailable: !bundled.isEmpty,
                installedCandidateIDs: installed.map(\.id).sorted(),
                issue: .missingCapability(.bibliographyRecommendation),
                bindingRevision: bindingRevision
            )
        }
        return ResearchSkillBindingResolution(
            source: .bundledDefault,
            package: package,
            bundledTemplateAvailable: true,
            installedCandidateIDs: installed.map(\.id).sorted(),
            bindingRevision: bindingRevision
        )
    }

    @discardableResult
    public func setBibliographyMethodBinding(
        packageID: String?,
        expectedBindingRevision: DocumentFingerprint?
    ) throws -> ResearchBibliographyMethodSnapshot {
        let observed = try bibliographyMethods.rawRevision()
        guard observed == expectedBindingRevision else {
            throw ResearchSkillBindingError.staleBindingFile
        }
        if let packageID {
            let package = try packageRepository.localPackage(id: packageID)
            guard package.origin == .triptych,
                  package.isValid,
                  package.role == "method",
                  package.provides(.bibliographyRecommendation) else {
                throw ResearchSkillBindingError.invalidBindingDocument(
                    "The bibliography method must be a valid Triptych-local complete Source Analyzer."
                )
            }
        }
        return try bibliographyMethods.save(
            ResearchBibliographyMethodDocument(packageID: packageID),
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
        let rawBindingRevision = try? citationMethods.rawRevision()
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
        let snapshot: ResearchCitationMethodSnapshot?
        do {
            snapshot = try citationMethods.snapshotMigratingLegacyIfNeeded()
        } catch {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .malformed(error.localizedDescription),
                bindingRevision: rawBindingRevision
            )
        }
        let bindingRevision = snapshot?.revision ?? rawBindingRevision
        guard let id = snapshot?.document.packageID else {
            return ResearchSkillBindingResolution(
                source: .none,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .missing,
                bindingRevision: bindingRevision
            )
        }
        guard let bound = localCandidates.first(where: { $0.id == id }) else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .invalidPackage(id),
                bindingRevision: bindingRevision
            )
        }
        guard let activeStyle = snapshot?.document.citationStyle else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .citationStyleMissing(packageID: id),
                bindingRevision: bindingRevision
            )
        }
        guard bound.citationStyles.contains(activeStyle),
              bound.citationStyleResources[activeStyle] != nil else {
            return ResearchSkillBindingResolution(
                source: .triptychBinding,
                bundledTemplateAvailable: bundledTemplateAvailable,
                installedCandidateIDs: localCandidates.map(\.id),
                issue: .citationStyleMismatch(packageID: id, requested: activeStyle),
                bindingRevision: bindingRevision
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
                    bindingRevision: bindingRevision
                )
            }
        }
        return ResearchSkillBindingResolution(
            source: .triptychBinding,
            package: bound,
            bundledTemplateAvailable: bundledTemplateAvailable,
            installedCandidateIDs: localCandidates.map(\.id),
            citationStyle: activeStyle,
            bindingRevision: bindingRevision
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
              let package = try? packageRepository.localPackage(id: binding.packageID),
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
        guard packageRepository.packageRevision(sources: sources) == expectedRevision else {
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
        let bundled = try packageRepository.bundledPackages()
        let rawLocal = try packageRepository.localPackages()
        let protectedIDs = Set(bundled.map(\.id))
        if let shadow = rawLocal.first(where: { protectedIDs.contains($0.id) }) {
            throw ResearchSkillError.protectedPackageShadow(shadow.id)
        }
        let local = packageRepository.resolver.validatedLocalPackages(
            rawLocal,
            bundled: bundled
        )
        return try packageRepository.resolver.resolvedPackages(
            catalog: protectedCatalog,
            bundled: bundled,
            local: local,
            mode: mode,
            requestedSkillIDs: requestedSkillIDs
        )
    }

    public func prepareSkillsFolder() throws -> URL {
        try packageRepository.prepareSkillsFolder()
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
        try packageRepository.ensureSkillsDirectory()
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
        guard packageRepository.packageRevision(sources: originalSources) == expectedPackageRevision else {
            throw ResearchSkillError.stalePackage(packageID)
        }
        var replacementSources = originalSources
        replacementSources["SKILL.md"] = source
        let replacementRevision = packageRepository.packageRevision(sources: replacementSources)
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
            let package = try packageRepository.localPackage(id: packageID)
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
                    packageRevision: packageRepository.packageRevision(sources: rollbackSources)
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

    func ensureSkillsDirectoryForInstallation() throws {
        try packageRepository.ensureSkillsDirectory()
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
        try packageRepository.installLocalPackage(
            id: id,
            sources: sources,
            onPublished: onPublished
        )
    }

    private func validateActionProfileBinding(
        _ binding: ResearchActionProfileBinding
    ) throws {
        let package: ResearchSkillPackage
        do {
            package = try packageRepository.localPackage(id: binding.packageID)
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
        let citationMethodRevision: DocumentFingerprint?
        let bibliographyMethodRevision: DocumentFingerprint?
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
        let citation = try citationMethods.snapshotMigratingLegacyIfNeeded()
        if citation?.document.packageID == packageID {
            throw ResearchActionProfileStorageError.packageInUse(packageID)
        }
        let bibliography = try bibliographyMethods.snapshotMigratingLegacyIfNeeded()
        if bibliography?.document.packageID == packageID {
            throw ResearchActionProfileStorageError.packageInUse(packageID)
        }
        return ResearchSkillUsageSnapshot(
            workingMethodRevision: working?.revision,
            actionProfileRevision: profiles?.revision,
            citationMethodRevision: citation?.revision,
            bibliographyMethodRevision: bibliography?.revision
        )
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

    private func isCitationMethod(_ package: ResearchSkillPackage) -> Bool {
        package.provides(.citationVerification)
            || package.provides(.citationFormatting)
            || !package.citationStyleResources.isEmpty
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
        try packageRepository.validatedProposedPackage(
            id: id,
            sources: sources,
            revision: revision
        )
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
        try packageRepository.workingMethodSources(
            bundledPackageID: descriptor.bundledPackageID,
            actionID: descriptor.actionID,
            function: descriptor.function,
            workingPackageID: descriptor.workingPackageID
        )
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

}
