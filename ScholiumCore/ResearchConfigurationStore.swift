import Darwin
import Foundation
import ScholiumContracts

public enum ResearchConfigurationStoreError: LocalizedError, Hashable, Sendable {
    case unsafeStorage
    case staleDocument
    case missingRegistrations
    case missingProfiles
    case missingRegistration(ResearchActionID)
    case disabledRegistration(ResearchActionID)
    case missingSkillFolder(String)
    case invalidSkillFolder(String)
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeStorage:
            "Research configuration storage is unsafe or changed during access."
        case .staleDocument:
            "Research configuration changed on disk. Reload before saving."
        case .missingRegistrations:
            "The current Research Skill registration document is missing."
        case .missingProfiles:
            "The current academic Action Profile document is missing."
        case .missingRegistration(let actionID):
            "Action \(actionID.rawValue) has no current Research Skill registration."
        case .disabledRegistration(let actionID):
            "The Research Skill registered for \(actionID.rawValue) is disabled."
        case .missingSkillFolder(let path):
            "The registered Research Skill folder is missing: \(path)"
        case .invalidSkillFolder(let path):
            "The registered Research Skill folder is invalid: \(path)"
        case .invalidDocument(let reason):
            "The current research configuration is invalid. \(reason)"
        }
    }
}

public actor ResearchConfigurationStore {
    public static let registrationFileName = "skill-registrations-v3.json"
    public static let profileFileName = "academic-action-profiles-v1.json"
    public static let citationMethodFileName = "citation-method-v1.json"

    private let controlURL: URL
    private let triptychID: UUID
    private let fileManager: FileManager
    private let registrations: StrictResearchJSONStore<ResearchSkillRegistrationDocument>
    private let profiles: StrictResearchJSONStore<ResearchAcademicProfileDocument>
    private let citationMethod: StrictResearchJSONStore<ResearchCitationMethodDocument>
    private let skillFolderLocators: ResearchSkillFolderLocatorStore?

    public init(
        controlURL: URL,
        triptychID: UUID,
        machineStorageURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let root = controlURL.standardizedFileURL
        self.controlURL = root
        self.triptychID = triptychID
        self.fileManager = fileManager
        registrations = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.registrationFileName,
            maximumByteCount: 1_048_576,
            fileManager: fileManager
        )
        profiles = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.profileFileName,
            maximumByteCount: 4_194_304,
            fileManager: fileManager
        )
        citationMethod = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.citationMethodFileName,
            maximumByteCount: 65_536,
            fileManager: fileManager
        )
        skillFolderLocators = machineStorageURL.map {
            ResearchSkillFolderLocatorStore(
                storageURL: $0,
                triptychID: triptychID,
                fileManager: fileManager
            )
        }
    }

    /// Internal identity projections for the source-only project Skill
    /// discovery assembly. They do not expose mutable storage or a public
    /// delivery contract.
    var skillDiscoveryControlURL: URL { controlURL }
    var skillDiscoveryTriptychID: UUID { triptychID }

    public func registrationSnapshot() throws -> ResearchSkillRegistrationSnapshot? {
        try registrations.snapshot().map {
            ResearchSkillRegistrationSnapshot(document: $0.document, revision: $0.revision)
        }
    }

    /// Idempotently installs only the current target owners for a new
    /// Triptych. Existing current documents are never overwritten or filled
    /// from retired package/binding/permission files.
    public func bootstrapDefaults() throws {
        try ensureControlDirectory()
        if try registrationSnapshot() == nil {
            let installed = try BundledResearchSkillDefaults.install(into: controlURL)
            _ = try saveRegistrations(
                ResearchSkillRegistrationDocument(registrations: installed),
                expectedRevision: nil
            )
        }
        if try profileSnapshot() == nil {
            _ = try saveProfiles(
                ResearchAcademicProfileCatalog.defaultDocument,
                expectedRevision: nil
            )
        }
        if try citationMethodSnapshot() == nil {
            _ = try saveCitationMethod(
                try ResearchCitationMethodDocument(triptychID: triptychID),
                expectedRevision: nil
            )
        }
    }

    @discardableResult
    public func preserveInvalidMachineLocalSkillFolderLocatorsAndReset() throws
        -> URL?
    {
        guard let skillFolderLocators else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Machine-local Skill-folder locator storage is unavailable."
            )
        }
        return try skillFolderLocators.preserveInvalidAndReset()
    }

    public func saveRegistrations(
        _ document: ResearchSkillRegistrationDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchSkillRegistrationSnapshot {
        let saved = try registrations.save(document, expectedRevision: expectedRevision)
        return ResearchSkillRegistrationSnapshot(
            document: saved.document,
            revision: saved.revision
        )
    }

    /// Replaces one Action's current Skill relation with a researcher-selected
    /// folder. Portable state records only a machine-local marker; the private
    /// locator stores its path and read-only reveal bookmark. Neither this
    /// transaction nor its readback opens or interprets folder contents.
    public func registerExternalSkillFolder(
        actionID: ResearchActionID,
        displayName: String,
        skillFolderPath: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) throws -> ResearchSkillBindingSnapshot {
        guard let current = try registrationSnapshot(),
              current.revision == expectedRegistrationRevision else {
            throw ResearchConfigurationStoreError.staleDocument
        }
        let folder = URL(fileURLWithPath: skillFolderPath, isDirectory: true)
            .standardizedFileURL
        guard let skillFolderLocators else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Machine-local Skill-folder locator storage is unavailable."
            )
        }
        let key = ResearchSkillRegistrationKey()
        let originalLocators = try skillFolderLocators.snapshot()
        let binding = try skillFolderLocators.makeBinding(
            registrationKey: key,
            skillFolderURL: folder
        )
        let locatorDocument = try (
            originalLocators?.document
                ?? ResearchSkillFolderLocatorStore.Document(triptychID: triptychID)
        ).replacing(binding)
        let savedLocators = try skillFolderLocators.save(
            locatorDocument,
            expectedRevision: originalLocators?.revision
        )
        let registration = try ResearchSkillRegistration(
            key: key,
            actionID: actionID,
            displayName: displayName,
            skillFolder: .machineLocal(),
            isEnabled: true
        )
        var savedRegistration: ResearchSkillRegistrationSnapshot?
        do {
            savedRegistration = try saveRegistrations(
                current.document.replacing(registration),
                expectedRevision: current.revision
            )
            let readback = try skillBindingSnapshot(for: actionID)
            guard readback.registration == registration,
                  readback.skillFolderPath == folder.path else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The registered Skill-folder relation could not be read back exactly."
                )
            }
            if let previous = current.document.registration(for: actionID),
               previous.skillFolder.kind == .machineLocal {
                try? removeUnusedMachineLocator(
                    previous.key,
                    retaining: registration.key
                )
            }
            return readback
        } catch {
            let registrationRolledBack: Bool
            if let savedRegistration {
                registrationRolledBack = (try? saveRegistrations(
                    current.document,
                    expectedRevision: savedRegistration.revision
                )) != nil
            } else if let observed = try? registrationSnapshot() {
                if observed.document == current.document {
                    registrationRolledBack = true
                } else if observed.document == (try? current.document.replacing(
                    registration
                )) {
                    registrationRolledBack = (try? saveRegistrations(
                        current.document,
                        expectedRevision: observed.revision
                    )) != nil
                } else {
                    registrationRolledBack = false
                }
            } else {
                registrationRolledBack = false
            }
            if registrationRolledBack {
                _ = try? skillFolderLocators.save(
                    originalLocators?.document
                        ?? ResearchSkillFolderLocatorStore.Document(triptychID: triptychID),
                    expectedRevision: savedLocators.revision
                )
            }
            throw error
        }
    }

    public func profileSnapshot() throws -> ResearchAcademicProfileSnapshot? {
        try profiles.snapshot().map {
            ResearchAcademicProfileSnapshot(document: $0.document, revision: $0.revision)
        }
    }

    public func saveProfiles(
        _ document: ResearchAcademicProfileDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchAcademicProfileSnapshot {
        for profile in document.profiles {
            guard let platform = PlatformActionCatalog.definition(for: profile.actionID) else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "No protected Platform Action exists for \(profile.actionID.rawValue)."
                )
            }
            try platform.validate(profile: profile)
        }
        let saved = try profiles.save(document, expectedRevision: expectedRevision)
        return ResearchAcademicProfileSnapshot(
            document: saved.document,
            revision: saved.revision
        )
    }

    /// Reidentification is safe only after every portable Triptych-bound
    /// configuration owner already names the same stable manifest identity.
    /// This is a read-only preflight; it never repairs a partial identity
    /// change or treats one document as authority for another.
    public func validatePortableIdentityForReidentification(
        _ stableID: UUID
    ) throws {
        guard let citationDocument = try citationMethod.snapshot()?.document,
              citationDocument.triptychID == stableID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The Citation Method does not name the proposed stable Triptych."
            )
        }
    }

    public func citationMethodSnapshot() throws -> ResearchCitationMethodSnapshot? {
        try citationMethod.snapshot().map { stored in
            guard stored.document.triptychID == triptychID else {
                throw ResearchCitationMethodContractError.triptychMismatch
            }
            return ResearchCitationMethodSnapshot(
                document: stored.document,
                revision: stored.revision
            )
        }
    }

    public func saveCitationMethod(
        _ document: ResearchCitationMethodDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchCitationMethodSnapshot {
        guard document.triptychID == triptychID else {
            throw ResearchCitationMethodContractError.triptychMismatch
        }
        let saved = try citationMethod.save(
            document,
            expectedRevision: expectedRevision
        )
        return ResearchCitationMethodSnapshot(
            document: saved.document,
            revision: saved.revision
        )
    }

    /// Resolves only the registered Skill-folder relation. It never opens,
    /// enumerates, snapshots, or interprets any file inside the folder.
    public func skillBindingSnapshot(
        for actionID: ResearchActionID
    ) throws -> ResearchSkillBindingSnapshot {
        guard let registrations = try registrationSnapshot(),
              let registration = registrations.document.registration(for: actionID) else {
            throw ResearchConfigurationStoreError.missingRegistration(actionID)
        }
        let folder = try resolvedSkillFolder(for: registration)
        return try ResearchSkillBindingSnapshot(
            registration: registration,
            registrationRevision: registrations.revision,
            skillFolderPath: folder.path,
            skillFolderIsAvailable: folder.isAvailable
        )
    }

    /// Begins the shortest security-scoped access needed to reveal the
    /// registered folder in Finder. The returned lease owns no file-content
    /// operation and must remain alive through the reveal call.
    public func skillFolderAccess(
        for actionID: ResearchActionID
    ) throws -> any ResearchSkillFolderAccess {
        guard let registrations = try registrationSnapshot(),
              let registration = registrations.document.registration(for: actionID)
        else {
            throw ResearchConfigurationStoreError.missingRegistration(actionID)
        }
        switch registration.skillFolder.kind {
        case .triptychControl:
            let url = try triptychURL(for: registration.skillFolder)
            guard Self.directoryIsAvailable(at: url) else {
                throw ResearchConfigurationStoreError.missingSkillFolder(url.path)
            }
            return ResearchSkillFolderAccessLease(url: url, stopAccess: {})
        case .machineLocal:
            guard let skillFolderLocators else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Machine-local Skill-folder locator storage is unavailable."
                )
            }
            return try skillFolderLocators.skillFolderAccess(
                for: registration.key
            )
        }
    }

    private func resolvedSkillFolder(
        for registration: ResearchSkillRegistration
    ) throws -> (path: String, isAvailable: Bool) {
        switch registration.skillFolder.kind {
        case .triptychControl:
            let url = try triptychURL(for: registration.skillFolder)
            return (
                url.path,
                Self.directoryIsAvailable(at: url)
            )
        case .machineLocal:
            guard let skillFolderLocators else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Machine-local Skill-folder locator storage is unavailable."
                )
            }
            return try skillFolderLocators.skillFolderStatus(for: registration.key)
        }
    }

    private func triptychURL(
        for location: ResearchSkillFolderLocation
    ) throws -> URL {
        guard location.kind == .triptychControl,
              let relativePath = location.triptychRelativePath else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "A machine-local Skill folder cannot resolve through portable state."
            )
        }
        return controlURL.appendingPathComponent(relativePath).standardizedFileURL
    }

    private func removeUnusedMachineLocator(
        _ key: ResearchSkillRegistrationKey,
        retaining retainedKey: ResearchSkillRegistrationKey
    ) throws {
        guard key != retainedKey, let skillFolderLocators,
              let snapshot = try skillFolderLocators.snapshot() else { return }
        _ = try skillFolderLocators.save(
            try snapshot.document.removing(key),
            expectedRevision: snapshot.revision
        )
    }

    private static func directoryIsAvailable(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private func ensureControlDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchConfigurationStoreError.unsafeStorage
        }
    }
}

struct StoredResearchDocument<Document: Codable & Sendable>: Sendable {
    let document: Document
    let revision: DocumentFingerprint
}

struct StrictResearchJSONStore<Document: Codable & Sendable> {
    let controlURL: URL
    let fileName: String
    let maximumByteCount: Int
    let fileManager: FileManager

    func snapshot() throws -> StoredResearchDocument<Document>? {
        guard fileManager.fileExists(atPath: controlURL.path) else { return nil }
        let root = try SecureResearchConfigurationIO.openAbsoluteDirectory(controlURL)
        defer { Darwin.close(root) }
        let identity = try SecureResearchConfigurationIO.identity(
            of: root,
            path: controlURL.path
        )
        guard let data = try SecureResearchConfigurationIO.dataFileIfPresent(
            parentDescriptor: root,
            leaf: fileName,
            path: controlURL.appendingPathComponent(fileName).path,
            maximumByteCount: maximumByteCount
        ) else { return nil }
        guard try SecureResearchConfigurationIO.pathStillRefersToDirectory(
            controlURL,
            identity: identity
        ) else { throw ResearchConfigurationStoreError.unsafeStorage }
        do {
            return StoredResearchDocument(
                document: try JSONDecoder().decode(Document.self, from: data),
                revision: DocumentFingerprint(data: data)
            )
        } catch {
            throw ResearchConfigurationStoreError.invalidDocument(
                error.localizedDescription
            )
        }
    }

    func save(
        _ document: Document,
        expectedRevision: DocumentFingerprint?
    ) throws -> StoredResearchDocument<Document> {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(document)
        guard data.count <= maximumByteCount else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The encoded document exceeds its bounded storage contract."
            )
        }
        let root = try SecureResearchConfigurationIO.openAbsoluteDirectory(controlURL)
        defer { Darwin.close(root) }
        let identity = try SecureResearchConfigurationIO.identity(
            of: root,
            path: controlURL.path
        )
        let current = try SecureResearchConfigurationIO.dataFileIfPresent(
            parentDescriptor: root,
            leaf: fileName,
            path: controlURL.appendingPathComponent(fileName).path,
            maximumByteCount: maximumByteCount
        )
        if let current {
            guard expectedRevision == DocumentFingerprint(data: current) else {
                throw ResearchConfigurationStoreError.staleDocument
            }
        } else if expectedRevision != nil {
            throw ResearchConfigurationStoreError.staleDocument
        }

        let stage = ".research-config-\(UUID().uuidString.lowercased())"
        var stageExists = false
        var committed = false
        do {
            try SecureResearchConfigurationIO.createDataFile(
                parentDescriptor: root,
                leaf: stage,
                data: data,
                path: stage
            )
            stageExists = true
            if current == nil {
                try SecureResearchConfigurationIO.moveEntryExclusively(
                    parentDescriptor: root,
                    source: stage,
                    destination: fileName
                )
                stageExists = false
            } else {
                try SecureResearchConfigurationIO.swapEntries(
                    parentDescriptor: root,
                    first: fileName,
                    second: stage
                )
            }
            committed = true
            guard fsync(root) == 0 else {
                throw ResearchConfigurationStoreError.unsafeStorage
            }
            let readback = try SecureResearchConfigurationIO.readDataFile(
                parentDescriptor: root,
                leaf: fileName,
                path: fileName,
                maximumByteCount: maximumByteCount
            )
            guard readback == data,
                  try SecureResearchConfigurationIO.pathStillRefersToDirectory(
                    controlURL,
                    identity: identity
                  ) else {
                throw ResearchConfigurationStoreError.unsafeStorage
            }
            if stageExists {
                try SecureResearchConfigurationIO.removeDataFile(
                    parentDescriptor: root,
                    leaf: stage,
                    path: stage
                )
            }
            return StoredResearchDocument(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
        } catch {
            if stageExists && !committed {
                try? SecureResearchConfigurationIO.removeDataFile(
                    parentDescriptor: root,
                    leaf: stage,
                    path: stage
                )
            }
            throw error
        }
    }

    private func ensureControlDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchConfigurationStoreError.unsafeStorage
        }
    }
}
