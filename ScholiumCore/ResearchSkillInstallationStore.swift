import Darwin
import Foundation
import ScholiumContracts

public struct ResearchSkillInstallationDestination: Sendable {
    public let triptychID: UUID
    public let skillStore: ResearchSkillStore

    public init(triptychID: UUID, skillStore: ResearchSkillStore) {
        self.triptychID = triptychID
        self.skillStore = skillStore
    }
}

enum ResearchSkillInstallationFaultPoint: Sendable {
    case afterPackagePublished(UUID)
    case afterDestinationInstalled(UUID)
    case afterRollbackQuarantined(UUID)
}

struct ResearchSkillInstallationHooks: Sendable {
    let handler: @Sendable (ResearchSkillInstallationFaultPoint) throws -> Void

    static let none = Self { _ in }
}

private enum ResearchSkillInstallationPublishError: Error {
    case publishedStateUnverified(
        SecureResearchSkillPackageIO.DirectoryIdentity,
        ResearchSkillInstallationError
    )
}

private struct PublishedResearchSkillInstallation: Sendable {
    let destination: ResearchSkillInstallationDestination
    let identity: SecureResearchSkillPackageIO.DirectoryIdentity
}

/// Owns short-lived, nonexecuting installation preparations. Source paths and
/// bytes never enter the public preparation. Installation consumes one exact
/// preparation and publishes a separately copied package in every selected
/// Triptych without creating an Action binding or permission approval.
public actor ResearchSkillInstallationStore {
    private struct StagedPackage: Sendable {
        let preparation: ResearchSkillInstallationPreparation
        let sources: [String: String]
    }

    private static let defaultPreparationLifetime: TimeInterval = 15 * 60
    private static let maximumRetainedPreparationCount = 16

    private let hooks: ResearchSkillInstallationHooks
    private let preparationLifetime: TimeInterval
    private var stagedPackages: [UUID: StagedPackage] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]

    public init() {
        hooks = .none
        preparationLifetime = Self.defaultPreparationLifetime
    }

    init(
        hooks: ResearchSkillInstallationHooks,
        preparationLifetime: TimeInterval = 15 * 60
    ) {
        self.hooks = hooks
        self.preparationLifetime = preparationLifetime
    }

    public func stage(
        directoryURL: URL
    ) throws -> ResearchSkillInstallationPreparation {
        guard directoryURL.isFileURL else {
            throw ResearchSkillInstallationError.sourceMustBeLocalDirectory
        }
        discardExpiredPreparations(at: Date())
        guard stagedPackages.count < Self.maximumRetainedPreparationCount else {
            throw ResearchSkillInstallationError.unsafeSource(
                "Too many unconsumed installation preparations."
            )
        }

        let sourceURL = directoryURL.standardizedFileURL
        let packageID = sourceURL.lastPathComponent
        guard Self.isValidIdentifier(packageID) else {
            throw ResearchSkillInstallationError.invalidPackageID(packageID)
        }
        if try BundledResearchSkillLibrary.catalog().entries.contains(where: {
            $0.id == packageID
        }) {
            throw ResearchSkillInstallationError.protectedPackageCollision(packageID)
        }

        let sources = try Self.readBoundedPackage(at: sourceURL, packageID: packageID)
        let packageRevision = ResearchSkillProposedPackage(files: sources.map {
            ResearchSkillMaintenanceFile(relativePath: $0.key, source: $0.value)
        }).packageRevision
        let inspected = ResearchSkillInspector.inspect(
            id: packageID,
            source: sources["SKILL.md"] ?? "",
            origin: .triptych,
            revision: packageRevision
        )
        let package = inspected.addingValidationIssues(
            ResearchSkillStore.declaredResourceValidationIssues(
                for: inspected,
                availableResourcePaths: Set(sources.keys)
            )
        )
        guard package.isValid else {
            throw ResearchSkillInstallationError.malformedMetadata(
                package.validationIssues
            )
        }

        let now = Date()
        let preparation = ResearchSkillInstallationPreparation(
            id: UUID(),
            packageID: packageID,
            packageRevision: packageRevision,
            originDisplayName: sourceURL.lastPathComponent,
            files: sources.map { path, source in
                ResearchSkillInstallationFile(
                    relativePath: path,
                    utf8ByteCount: source.utf8.count,
                    revision: DocumentFingerprint(content: source)
                )
            },
            purpose: package.description,
            packageRole: package.role,
            applicableRoles: Self.applicableRoles(for: package.supportedActions),
            declaredCapabilities: package.capabilities,
            proposedActionIDs: package.supportedActions,
            preparedAt: now,
            expiresAt: now.addingTimeInterval(preparationLifetime)
        )
        stagedPackages[preparation.id] = StagedPackage(
            preparation: preparation,
            sources: sources
        )
        let lifetime = preparationLifetime
        expirationTasks[preparation.id] = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(lifetime)
                )
            } catch {
                return
            }
            await self?.expire(preparationID: preparation.id)
        }
        return preparation
    }

    public func install(
        _ preparation: ResearchSkillInstallationPreparation,
        destinations: [ResearchSkillInstallationDestination]
    ) async throws -> ResearchSkillInstallationOutcome {
        guard !destinations.isEmpty else {
            throw ResearchSkillInstallationError.noTriptychsSelected
        }
        var destinationIDs: Set<UUID> = []
        for destination in destinations where !destinationIDs.insert(
            destination.triptychID
        ).inserted {
            throw ResearchSkillInstallationError.duplicateTriptych(
                destination.triptychID
            )
        }

        guard let staged = stagedPackages.removeValue(forKey: preparation.id) else {
            throw ResearchSkillInstallationError.preparationNotFound(preparation.id)
        }
        expirationTasks.removeValue(forKey: preparation.id)?.cancel()
        guard staged.preparation == preparation else {
            throw ResearchSkillInstallationError.preparationMismatch(preparation.id)
        }
        guard preparation.expiresAt > Date() else {
            throw ResearchSkillInstallationError.preparationExpired(preparation.id)
        }

        let orderedDestinations = destinations.sorted {
            $0.triptychID.uuidString < $1.triptychID.uuidString
        }
        for destination in orderedDestinations {
            try await destination.skillStore.preflightStagedResearcherSkillInstallation(
                id: preparation.packageID,
                sources: staged.sources,
                expectedRevision: preparation.packageRevision
            )
        }

        var installed: [PublishedResearchSkillInstallation] = []
        var unverifiedInstallation: PublishedResearchSkillInstallation?
        do {
            for destination in orderedDestinations {
                let identity: SecureResearchSkillPackageIO.DirectoryIdentity
                do {
                    let hooks = hooks
                    let triptychID = destination.triptychID
                    identity = try await destination.skillStore
                        .installStagedResearcherSkillPackage(
                            id: preparation.packageID,
                            sources: staged.sources,
                            expectedRevision: preparation.packageRevision,
                            afterPublish: {
                                try hooks.handler(.afterPackagePublished(triptychID))
                            }
                        )
                } catch ResearchSkillInstallationPublishError
                    .publishedStateUnverified(let identity, let failure) {
                    unverifiedInstallation = PublishedResearchSkillInstallation(
                        destination: destination,
                        identity: identity
                    )
                    throw failure
                }
                installed.append(PublishedResearchSkillInstallation(
                    destination: destination,
                    identity: identity
                ))
                try hooks.handler(.afterDestinationInstalled(destination.triptychID))
            }
        } catch {
            var recoveryRequired: [UUID] = []
            let rollbackCandidates = (unverifiedInstallation.map { [$0] } ?? [])
                + Array(installed.reversed())
            for published in rollbackCandidates {
                do {
                    try await published.destination.skillStore
                        .quarantineExactStagedResearcherSkillPackage(
                            id: preparation.packageID,
                            expectedIdentity: published.identity
                        )
                    try? hooks.handler(
                        .afterRollbackQuarantined(published.destination.triptychID)
                    )
                } catch {
                    recoveryRequired.append(published.destination.triptychID)
                }
            }
            if !recoveryRequired.isEmpty {
                throw ResearchSkillInstallationError.destinationRecoveryRequired(
                    recoveryRequired.sorted { $0.uuidString < $1.uuidString }
                )
            }
            throw error
        }

        return ResearchSkillInstallationOutcome(
            preparationID: preparation.id,
            packageID: preparation.packageID,
            packageRevision: preparation.packageRevision,
            installations: orderedDestinations.map {
                ResearchSkillInstallationResult(
                    triptychID: $0.triptychID,
                    packageID: preparation.packageID,
                    packageRevision: preparation.packageRevision
                )
            }
        )
    }

    public func discard(preparationID: UUID) {
        stagedPackages.removeValue(forKey: preparationID)
        expirationTasks.removeValue(forKey: preparationID)?.cancel()
    }

    public func discardAll() {
        stagedPackages.removeAll()
        for task in expirationTasks.values { task.cancel() }
        expirationTasks.removeAll()
    }

    private func discardExpiredPreparations(at now: Date) {
        for (id, staged) in stagedPackages
            where staged.preparation.expiresAt <= now {
            expire(preparationID: id)
        }
    }

    private func expire(preparationID: UUID) {
        stagedPackages.removeValue(forKey: preparationID)
        expirationTasks.removeValue(forKey: preparationID)?.cancel()
    }

    private static func applicableRoles(
        for actionIDs: [ResearchActionID]
    ) -> [ResearchActionTargetRole] {
        let definitions = ResearchActionDefinition.defaultDefinitions + [.manuscript]
        let roles = definitions.filter { actionIDs.contains($0.id) }
            .reduce(into: Set<ResearchActionTargetRole>()) {
                $0.formUnion($1.allowedTargetRoles)
            }
        return ResearchActionTargetRole.allCases.filter(roles.contains)
    }

    private static func readBoundedPackage(
        at sourceURL: URL,
        packageID: String
    ) throws -> [String: String] {
        let packageDescriptor: Int32
        do {
            packageDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
                sourceURL
            )
        } catch {
            throw ResearchSkillInstallationError.unsafeSource(packageID)
        }
        defer { Darwin.close(packageDescriptor) }

        return try readBoundedPackage(
            packageDescriptor: packageDescriptor,
            packageID: packageID
        )
    }

    static func readBoundedPackage(
        packageDescriptor: Int32,
        packageID: String
    ) throws -> [String: String] {
        var sources: [String: String] = [:]
        var totalByteCount = 0
        for name in try installationEntryNames(
            descriptor: packageDescriptor,
            path: packageID,
            maximumEntryCount: 5
        ) {
            if name == "SKILL.md" {
                sources[name] = try readInstallationFile(
                    parentDescriptor: packageDescriptor,
                    leaf: name,
                    relativePath: name,
                    totalByteCount: &totalByteCount
                )
                try validateFileCount(sources.count)
                continue
            }
            guard ["references", "templates", "evals"].contains(name) else {
                throw ResearchSkillInstallationError.unsupportedResource(name)
            }
            let resourceDescriptor: Int32
            do {
                resourceDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                    parentDescriptor: packageDescriptor,
                    name: name,
                    path: "\(packageID)/\(name)"
                )
            } catch {
                throw ResearchSkillInstallationError.unsupportedResource(name)
            }
            do {
                let remainingFileCount = ResearchSkillInstallationPreparation
                    .maximumFileCount - sources.count
                for resource in try installationEntryNames(
                    descriptor: resourceDescriptor,
                    path: "\(packageID)/\(name)",
                    maximumEntryCount: remainingFileCount
                ) {
                    let relativePath = "\(name)/\(resource)"
                    guard ResearchSkillMaintenancePath.isAllowed(relativePath) else {
                        throw ResearchSkillInstallationError.unsupportedResource(
                            relativePath
                        )
                    }
                    sources[relativePath] = try readInstallationFile(
                        parentDescriptor: resourceDescriptor,
                        leaf: resource,
                        relativePath: relativePath,
                        totalByteCount: &totalByteCount
                    )
                    try validateFileCount(sources.count)
                }
                Darwin.close(resourceDescriptor)
            } catch {
                Darwin.close(resourceDescriptor)
                throw error
            }
        }
        guard sources["SKILL.md"] != nil else {
            throw ResearchSkillMaintenanceError.missingEntryPoint
        }
        return sources
    }

    private static func installationEntryNames(
        descriptor: Int32,
        path: String,
        maximumEntryCount: Int
    ) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw ResearchSkillInstallationError.unsafeSource(path)
        }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(MAXNAMLEN) + 1
                ) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." {
                guard names.count < maximumEntryCount else {
                    throw ResearchSkillInstallationError.tooManyFiles(
                        ResearchSkillInstallationPreparation.maximumFileCount + 1
                    )
                }
                names.append(name)
            }
            errno = 0
        }
        guard errno == 0 else {
            throw ResearchSkillInstallationError.unsafeSource(path)
        }
        return names.sorted()
    }

    private static func readInstallationFile(
        parentDescriptor: Int32,
        leaf: String,
        relativePath: String,
        totalByteCount: inout Int
    ) throws -> String {
        var observed = stat()
        let inspect = leaf.withCString {
            fstatat(parentDescriptor, $0, &observed, AT_SYMLINK_NOFOLLOW)
        }
        guard inspect == 0 else {
            throw ResearchSkillInstallationError.unsafeSource(relativePath)
        }
        guard (observed.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              observed.st_nlink == 1 else {
            throw ResearchSkillInstallationError.unsupportedResource(relativePath)
        }
        guard observed.st_mode & mode_t(0o111) == 0 else {
            throw ResearchSkillInstallationError.executableResource(relativePath)
        }
        guard observed.st_size >= 0,
              observed.st_size <= off_t(
                  ResearchSkillInstallationPreparation.maximumFileUTF8ByteCount
              ) else {
            throw ResearchSkillInstallationError.fileTooLarge(relativePath)
        }

        let descriptor = leaf.withCString {
            openat(
                parentDescriptor,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            throw ResearchSkillInstallationError.unsafeSource(relativePath)
        }
        defer { Darwin.close(descriptor) }

        var opened = stat()
        guard fstat(descriptor, &opened) == 0,
              sameFile(observed, opened),
              (opened.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              opened.st_nlink == 1,
              opened.st_mode & mode_t(0o111) == 0 else {
            throw ResearchSkillInstallationError.unsafeSource(relativePath)
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw ResearchSkillInstallationError.unsafeSource(relativePath)
            }
            guard data.count + Int(count)
                    <= ResearchSkillInstallationPreparation.maximumFileUTF8ByteCount else {
                throw ResearchSkillInstallationError.fileTooLarge(relativePath)
            }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }

        var completed = stat()
        guard fstat(descriptor, &completed) == 0,
              sameSnapshot(opened, completed),
              completed.st_size == off_t(data.count) else {
            throw ResearchSkillInstallationError.unsafeSource(relativePath)
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw ResearchSkillInstallationError.invalidUTF8(relativePath)
        }
        let source = String(decoding: data, as: UTF8.self)
        if isScript(relativePath: relativePath, source: source) {
            throw ResearchSkillInstallationError.scriptResource(relativePath)
        }
        guard totalByteCount <= ResearchSkillInstallationPreparation
            .maximumPackageUTF8ByteCount - data.count else {
            throw ResearchSkillInstallationError.packageTooLarge
        }
        totalByteCount += data.count
        return source
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func sameSnapshot(_ lhs: stat, _ rhs: stat) -> Bool {
        sameFile(lhs, rhs)
            && lhs.st_size == rhs.st_size
            && lhs.st_mode == rhs.st_mode
            && lhs.st_nlink == rhs.st_nlink
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func validateFileCount(_ count: Int) throws {
        guard count <= ResearchSkillInstallationPreparation.maximumFileCount else {
            throw ResearchSkillInstallationError.tooManyFiles(count)
        }
    }

    private static func isScript(relativePath: String, source: String) -> Bool {
        if source.hasPrefix("#!") { return true }
        let extensionName = (relativePath as NSString).pathExtension.lowercased()
        return scriptExtensions.contains(extensionName)
            || scriptFileNames.contains(
                (relativePath as NSString).lastPathComponent.lowercased()
            )
    }

    private static let scriptExtensions: Set<String> = [
        "applescript", "bash", "bat", "cjs", "cmd", "command", "fish",
        "js", "jsx", "lua", "mjs", "php", "pl", "pm", "ps1", "py",
        "pyw", "r", "rb", "scpt", "sh", "swift", "ts", "tsx", "zsh",
    ]

    private static let scriptFileNames: Set<String> = [
        "cmakelists.txt", "makefile",
    ]

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }
}

extension ResearchSkillStore {
    func preflightStagedResearcherSkillInstallation(
        id: String,
        sources: [String: String],
        expectedRevision: DocumentFingerprint
    ) throws {
        let package = try validatedProposedResearcherPackage(
            id: id,
            sources: sources,
            revision: expectedRevision
        )
        guard package.isValid else {
            throw ResearchSkillInstallationError.malformedMetadata(
                package.validationIssues
            )
        }
        try ensureSkillsDirectoryForInstallation()
        do {
            guard try !hasExecutableBindingReferenceForInstallation(id: id) else {
                throw ResearchSkillInstallationError.destinationBindingConflict(id)
            }
        } catch let error as ResearchSkillInstallationError {
            throw error
        } catch {
            throw ResearchSkillInstallationError.destinationBindingStateUnverified
        }
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        guard try !SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        ) else {
            throw ResearchSkillError.packageAlreadyExists(id)
        }
    }

    func installStagedResearcherSkillPackage(
        id: String,
        sources: [String: String],
        expectedRevision: DocumentFingerprint,
        afterPublish: @Sendable () throws -> Void
    ) throws -> SecureResearchSkillPackageIO.DirectoryIdentity {
        try preflightStagedResearcherSkillInstallation(
            id: id,
            sources: sources,
            expectedRevision: expectedRevision
        )
        let installed: (
            package: ResearchSkillPackage,
            identity: SecureResearchSkillPackageIO.DirectoryIdentity
        )
        var publishedIdentity: SecureResearchSkillPackageIO.DirectoryIdentity?
        do {
            installed = try installPackageForInstallation(
                id: id,
                sources: sources,
                onPublished: { publishedIdentity = $0 }
            )
            try afterPublish()
            guard try !hasExecutableBindingReferenceForInstallation(id: id) else {
                throw ResearchSkillInstallationError.destinationBindingConflict(id)
            }
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
            defer { Darwin.close(packageDescriptor) }
            guard try SecureResearchSkillPackageIO.identity(
                of: packageDescriptor,
                path: id
            ) == installed.identity,
                  try ResearchSkillInstallationStore.readBoundedPackage(
                      packageDescriptor: packageDescriptor,
                      packageID: id
                  ) == sources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillError.stalePackage(id)
            }
            let recheckedDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: id,
                path: id
            )
            defer { Darwin.close(recheckedDescriptor) }
            guard try SecureResearchSkillPackageIO.identity(
                of: recheckedDescriptor,
                path: id
            ) == installed.identity,
                  try ResearchSkillInstallationStore.readBoundedPackage(
                      packageDescriptor: recheckedDescriptor,
                      packageID: id
                  ) == sources,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                      skillsURL,
                      identity: rootIdentity
                  ) else {
                throw ResearchSkillError.stalePackage(id)
            }
        } catch let error as ResearchSkillError {
            if case .packageAlreadyExists = error {
                // A competing participant won the no-replace publish race.
                // It is not Scholium's package and must never be removed.
                throw error
            }
            if let publishedIdentity {
                throw ResearchSkillInstallationPublishError
                    .publishedStateUnverified(
                        publishedIdentity,
                        .unsafeSource(id)
                    )
            }
            throw error
        } catch {
            if let publishedIdentity {
                let failure = (error as? ResearchSkillInstallationError)
                    ?? .unsafeSource(id)
                throw ResearchSkillInstallationPublishError
                    .publishedStateUnverified(publishedIdentity, failure)
            }
            throw error
        }
        guard installed.package.revision == expectedRevision,
              installed.package.isValid else {
            throw ResearchSkillInstallationPublishError
                .publishedStateUnverified(
                    installed.identity,
                    .malformedMetadata(installed.package.validationIssues)
                )
        }
        return installed.identity
    }

    private func hasExecutableBindingReferenceForInstallation(
        id: String
    ) throws -> Bool {
        if let current = try workingMethodBindingSnapshot(),
           current.document.actionBindings.values.contains(where: {
               $0.state != .disabled && $0.packageID == id
           }) {
            return true
        }

        let controlURL = bindingsURL.deletingLastPathComponent()
        let controlDescriptor = try SecureResearchSkillPackageIO
            .openAbsoluteDirectory(controlURL)
        defer { Darwin.close(controlDescriptor) }
        let controlIdentity = try SecureResearchSkillPackageIO.identity(
            of: controlDescriptor,
            path: controlURL.path
        )
        guard let data = try SecureResearchSkillPackageIO.dataFileIfPresent(
            parentDescriptor: controlDescriptor,
            leaf: bindingsURL.lastPathComponent,
            path: bindingsURL.path,
            maximumByteCount: 1_048_576
        ) else {
            return false
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            controlURL,
            identity: controlIdentity
        ) else {
            throw ResearchSkillBindingError.unsafeBindingFile
        }
        let document = try JSONDecoder().decode(
            ResearchSkillBindingDocument.self,
            from: data
        )
        guard document.schemaVersion == ResearchSkillBindingDocument
            .currentSchemaVersion else {
            throw ResearchSkillBindingError.invalidBindingDocument(
                "Unsupported retained binding schema version \(document.schemaVersion)."
            )
        }
        return document.citationBinding == id
            || document.bibliographyMethodBinding == id
    }

    func quarantineExactStagedResearcherSkillPackage(
        id: String,
        expectedIdentity: SecureResearchSkillPackageIO.DirectoryIdentity
    ) throws {
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsURL)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsURL.path
        )
        guard try SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        ) else {
            throw ResearchSkillInstallationPublishError
                .publishedStateUnverified(
                    expectedIdentity,
                    .unsafeSource(id)
                )
        }
        let packageDescriptor = try SecureResearchSkillPackageIO.openDirectory(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        )
        do {
            guard try SecureResearchSkillPackageIO.identity(
                of: packageDescriptor,
                path: id
            ) == expectedIdentity else {
                throw ResearchSkillError.stalePackage(id)
            }
            Darwin.close(packageDescriptor)
        } catch {
            Darwin.close(packageDescriptor)
            throw error
        }
        let rollbackName = ".install-recovery-\(UUID().uuidString.lowercased())"
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            skillsURL,
            identity: rootIdentity
        ) else {
            throw ResearchSkillInstallationPublishError
                .publishedStateUnverified(
                    expectedIdentity,
                    .unsafeSource(id)
                )
        }
        try SecureResearchSkillPackageIO.movePackageExclusively(
            rootDescriptor: rootDescriptor,
            source: id,
            destination: rollbackName
        )
        do {
            let rollbackDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: rollbackName,
                path: rollbackName
            )
            do {
                guard try SecureResearchSkillPackageIO.identity(
                    of: rollbackDescriptor,
                    path: rollbackName
                ) == expectedIdentity else {
                    throw ResearchSkillError.stalePackage(id)
                }
                Darwin.close(rollbackDescriptor)
            } catch {
                Darwin.close(rollbackDescriptor)
                throw error
            }
        } catch {
            do {
                try SecureResearchSkillPackageIO.movePackageExclusively(
                    rootDescriptor: rootDescriptor,
                    source: rollbackName,
                    destination: id
                )
                _ = fsync(rootDescriptor)
            } catch {
                // Preserve the hidden moved package for explicit recovery.
            }
            throw ResearchSkillInstallationPublishError
                .publishedStateUnverified(
                    expectedIdentity,
                    .unsafeSource(id)
                )
        }
        guard fsync(rootDescriptor) == 0,
              try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                  skillsURL,
                  identity: rootIdentity
              ),
              try !SecureResearchSkillPackageIO.directoryExists(
                  parentDescriptor: rootDescriptor,
                  name: id,
                  path: id
              ),
              try SecureResearchSkillPackageIO.directoryExists(
                  parentDescriptor: rootDescriptor,
                  name: rollbackName,
                  path: rollbackName
              ) else {
            throw ResearchSkillInstallationPublishError
                .publishedStateUnverified(
                    expectedIdentity,
                    .unsafeSource(id)
                )
        }
    }
}
