import Darwin
import Foundation
import ScholiumContracts

public enum ResearchConfigurationStoreError: LocalizedError, Hashable, Sendable {
    case unsafeStorage
    case staleDocument
    case missingRegistrations
    case missingProfiles
    case missingCollaborationPolicy
    case missingRegistration(ResearchActionID)
    case disabledRegistration(ResearchActionID)
    case missingMethod(String)
    case invalidMethod(String)
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
        case .missingCollaborationPolicy:
            "The current Triptych collaboration policy is missing."
        case .missingRegistration(let actionID):
            "Action \(actionID.rawValue) has no current Research Skill registration."
        case .disabledRegistration(let actionID):
            "The Research Skill registered for \(actionID.rawValue) is disabled."
        case .missingMethod(let path):
            "The registered primary Research Skill Markdown is missing: \(path)"
        case .invalidMethod(let path):
            "The registered primary Research Skill Markdown is invalid: \(path)"
        case .invalidDocument(let reason):
            "The current research configuration is invalid. \(reason)"
        }
    }
}

public actor ResearchConfigurationStore {
    public static let registrationFileName = "skill-registrations-v2.json"
    public static let profileFileName = "academic-action-profiles-v1.json"
    public static let collaborationFileName = "collaboration-policy-v1.json"
    public static let citationMethodFileName = "citation-method-v1.json"

    private let controlURL: URL
    private let triptychID: UUID
    private let fileManager: FileManager
    private let registrations: StrictResearchJSONStore<ResearchSkillRegistrationDocument>
    private let profiles: StrictResearchJSONStore<ResearchAcademicProfileDocument>
    private let collaboration: StrictResearchJSONStore<ResearchCollaborationPolicyDocument>
    private let citationMethod: StrictResearchJSONStore<ResearchCitationMethodDocument>
    private let methodLocators: ResearchMethodLocatorStore?

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
        collaboration = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.collaborationFileName,
            maximumByteCount: 65_536,
            fileManager: fileManager
        )
        citationMethod = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.citationMethodFileName,
            maximumByteCount: 65_536,
            fileManager: fileManager
        )
        methodLocators = machineStorageURL.map {
            ResearchMethodLocatorStore(
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
            let installed = try BundledResearchMethodDefaults.install(into: controlURL)
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
        if try collaborationSnapshot() == nil {
            _ = try saveCollaborationPolicy(
                ResearchCollaborationPolicyDocument(triptychID: triptychID),
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
    public func preserveInvalidMachineLocalMethodLocatorsAndReset() throws -> URL? {
        guard let methodLocators else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Machine-local Method locator storage is unavailable."
            )
        }
        return try methodLocators.preserveInvalidAndReset()
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
    /// primary Markdown file. Portable state records only machine-local
    /// markers; the private locator stores exact paths/bookmarks without
    /// enumerating or reading optional folder contents.
    public func registerExternalMethod(
        actionID: ResearchActionID,
        displayName: String,
        primaryMarkdownPath: String,
        skillFolderPath: String?,
        expectedRegistrationRevision: DocumentFingerprint
    ) throws -> ResearchMethodSnapshot {
        guard let current = try registrationSnapshot(),
              current.revision == expectedRegistrationRevision else {
            throw ResearchConfigurationStoreError.staleDocument
        }
        let primaryURL = URL(fileURLWithPath: primaryMarkdownPath)
            .standardizedFileURL
        guard primaryURL.pathExtension.lowercased() == "md" else {
            throw ResearchConfigurationStoreError.invalidMethod(primaryURL.path)
        }
        let folder = skillFolderPath.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        if let folder,
           !SecureResearchMethodIO.directoryIsAvailable(atPath: folder) {
            throw ResearchConfigurationStoreError.invalidMethod(folder)
        }
        guard let methodLocators else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Machine-local Method locator storage is unavailable."
            )
        }
        let key = ResearchSkillRegistrationKey()
        let originalLocators = try methodLocators.snapshot()
        let binding = try methodLocators.makeBinding(
            registrationKey: key,
            primaryURL: primaryURL,
            skillFolderURL: folder.map { URL(fileURLWithPath: $0) }
        )
        let locatorDocument = try (
            originalLocators?.document
                ?? ResearchMethodLocatorStore.Document(triptychID: triptychID)
        ).replacing(binding)
        let savedLocators = try methodLocators.save(
            locatorDocument,
            expectedRevision: originalLocators?.revision
        )
        let source: String
        do {
            source = try methodLocators.withPrimaryURL(for: key) {
                try SecureResearchMethodIO.read(at: $0)
            }
        } catch {
            _ = try? methodLocators.save(
                originalLocators?.document
                    ?? ResearchMethodLocatorStore.Document(triptychID: triptychID),
                expectedRevision: savedLocators.revision
            )
            throw error
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            _ = try? methodLocators.save(
                originalLocators?.document
                    ?? ResearchMethodLocatorStore.Document(triptychID: triptychID),
                expectedRevision: savedLocators.revision
            )
            throw ResearchConfigurationStoreError.invalidMethod(primaryURL.path)
        }
        let registration = try ResearchSkillRegistration(
            key: key,
            actionID: actionID,
            displayName: displayName,
            primaryMarkdown: .machineLocal(),
            skillFolder: folder == nil ? nil : .machineLocal(),
            isEnabled: true
        )
        var savedRegistration: ResearchSkillRegistrationSnapshot?
        do {
            savedRegistration = try saveRegistrations(
                current.document.replacing(registration),
                expectedRevision: current.revision
            )
            let readback = try methodSnapshot(for: actionID)
            guard readback.registration == registration,
                  readback.primaryMarkdownSource == source else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The registered Skill could not be read back exactly."
                )
            }
            if let previous = current.document.registration(for: actionID),
               previous.primaryMarkdown.kind == .machineLocal {
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
                _ = try? methodLocators.save(
                    originalLocators?.document
                        ?? ResearchMethodLocatorStore.Document(triptychID: triptychID),
                    expectedRevision: savedLocators.revision
                )
            }
            throw error
        }
    }

    /// Creates one ordinary local Skill folder owned by this Triptych and then
    /// installs its primary Markdown as the sole Action registration. Failure
    /// before the registration commit removes only the task-owned new folder.
    public func createPrimaryMethod(
        actionID: ResearchActionID,
        displayName: String,
        source: String,
        expectedRegistrationRevision: DocumentFingerprint
    ) throws -> ResearchMethodSnapshot {
        guard source.utf8.count <= SecureResearchMethodIO.maximumMethodByteCount,
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResearchConfigurationStoreError.invalidMethod(displayName)
        }
        guard let current = try registrationSnapshot(),
              current.revision == expectedRegistrationRevision else {
            throw ResearchConfigurationStoreError.staleDocument
        }
        let root = try SecureResearchConfigurationIO.openAbsoluteDirectory(controlURL)
        defer { Darwin.close(root) }
        let foldersURL = controlURL.appendingPathComponent("skill-folders", isDirectory: true)
        let folders = try SecureResearchConfigurationIO.ensureDirectory(
            parentDescriptor: root,
            name: "skill-folders",
            path: foldersURL.path
        )
        defer { Darwin.close(folders) }
        let folderName = "researcher-\(UUID().uuidString.lowercased())"
        let folderURL = foldersURL.appendingPathComponent(folderName, isDirectory: true)
        let folder = try SecureResearchConfigurationIO.createDirectory(
            parentDescriptor: folders,
            name: folderName,
            path: folderURL.path
        )
        defer { Darwin.close(folder) }
        try SecureResearchConfigurationIO.createDataFile(
            parentDescriptor: folder,
            leaf: "SKILL.md",
            data: Data(source.utf8),
            path: folderURL.appendingPathComponent("SKILL.md").path
        )
        var committed = false
        defer {
            if !committed {
                try? SecureResearchConfigurationIO.removeDataFile(
                    parentDescriptor: folder,
                    leaf: "SKILL.md",
                    path: folderURL.appendingPathComponent("SKILL.md").path
                )
                try? SecureResearchConfigurationIO.removeDirectory(
                    parentDescriptor: folders,
                    name: folderName,
                    path: folderURL.path
                )
            }
        }
        let registration = try ResearchSkillRegistration(
            actionID: actionID,
            displayName: displayName,
            primaryMarkdown: .triptychControl(
                "skill-folders/\(folderName)/SKILL.md"
            ),
            skillFolder: .triptychControl("skill-folders/\(folderName)"),
            isEnabled: true
        )
        let saved = try saveRegistrations(
            current.document.replacing(registration),
            expectedRevision: current.revision
        )
        do {
            let readback = try methodSnapshot(for: actionID)
            guard readback.registration == registration,
                  readback.primaryMarkdownSource == source else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The created Skill could not be read back exactly."
                )
            }
            committed = true
            return readback
        } catch {
            if (try? saveRegistrations(
                current.document,
                expectedRevision: saved.revision
            )) == nil {
                // A concurrent or external change now owns the document. Do
                // not remove bytes that its observed registration may refer to.
                committed = true
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

    public func collaborationSnapshot() throws -> ResearchCollaborationPolicySnapshot? {
        try collaboration.snapshot().map { stored in
            guard stored.document.triptychID == triptychID else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The collaboration policy belongs to another Triptych."
                )
            }
            return ResearchCollaborationPolicySnapshot(
                document: stored.document,
                revision: stored.revision
            )
        }
    }

    /// Reidentification is safe only after every portable Triptych-bound
    /// configuration owner already names the same stable manifest identity.
    /// This is a read-only preflight; it never repairs a partial identity
    /// change or treats one document as authority for another.
    public func validatePortableIdentityForReidentification(
        _ stableID: UUID
    ) throws {
        guard let collaborationDocument = try collaboration.snapshot()?.document,
              collaborationDocument.triptychID == stableID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The collaboration policy does not name the proposed stable Triptych."
            )
        }
        guard let citationDocument = try citationMethod.snapshot()?.document,
              citationDocument.triptychID == stableID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The Citation Method does not name the proposed stable Triptych."
            )
        }
    }

    public func saveCollaborationPolicy(
        _ document: ResearchCollaborationPolicyDocument,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchCollaborationPolicySnapshot {
        guard document.triptychID == triptychID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The collaboration policy belongs to another Triptych."
            )
        }
        let saved = try collaboration.save(document, expectedRevision: expectedRevision)
        return ResearchCollaborationPolicySnapshot(
            document: saved.document,
            revision: saved.revision
        )
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

    /// Resolves the registered Skill entry and the optional folder locator. It
    /// never enumerates, snapshots, or interprets ordinary reference files.
    public func methodSnapshot(for actionID: ResearchActionID) throws -> ResearchMethodSnapshot {
        guard let registration = try registrationSnapshot()?.document.registration(
            for: actionID
        ) else {
            throw ResearchConfigurationStoreError.missingRegistration(actionID)
        }
        guard registration.isEnabled else {
            throw ResearchConfigurationStoreError.disabledRegistration(actionID)
        }
        let primarySource = try withPrimaryURL(for: registration) {
            try SecureResearchMethodIO.read(at: $0)
        }
        let folder = try resolvedSkillFolder(for: registration)
        return try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: primarySource,
            skillFolderPath: folder.path,
            skillFolderIsAvailable: folder.isAvailable
        )
    }

    public func savePrimaryMethod(
        registrationKey: ResearchSkillRegistrationKey,
        source: String,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchMethodSnapshot {
        guard source.utf8.count <= SecureResearchMethodIO.maximumMethodByteCount,
              let registrations = try registrationSnapshot(),
              let registration = registrations.document.registrations.first(where: {
                  $0.key == registrationKey
              }) else {
            throw ResearchConfigurationStoreError.invalidMethod(
                registrationKey.description
            )
        }
        try withPrimaryURL(for: registration) { url in
            let current = try SecureResearchMethodIO.data(at: url)
            guard DocumentFingerprint(data: current) == expectedRevision else {
                throw ResearchConfigurationStoreError.staleDocument
            }
            _ = try SecureResearchMethodIO.replace(
                at: url,
                data: Data(source.utf8),
                expectedRevision: expectedRevision
            )
        }
        return try methodSnapshot(for: registration.actionID)
    }

    public func restoreDefaultPrimaryMethod(
        actionID: ResearchActionID,
        expectedRevision: DocumentFingerprint
    ) throws -> ResearchMethodSnapshot {
        guard let registration = try registrationSnapshot()?.document.registration(
            for: actionID
        ) else {
            throw ResearchConfigurationStoreError.missingRegistration(actionID)
        }
        return try savePrimaryMethod(
            registrationKey: registration.key,
            source: BundledResearchMethodDefaults.primarySource(for: actionID),
            expectedRevision: expectedRevision
        )
    }

    private func withPrimaryURL<Result>(
        for registration: ResearchSkillRegistration,
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        switch registration.primaryMarkdown.kind {
        case .triptychControl:
            return try operation(try triptychURL(for: registration.primaryMarkdown))
        case .machineLocal:
            guard let methodLocators else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Machine-local Method locator storage is unavailable."
                )
            }
            return try methodLocators.withPrimaryURL(
                for: registration.key,
                operation
            )
        }
    }

    private func resolvedSkillFolder(
        for registration: ResearchSkillRegistration
    ) throws -> (path: String?, isAvailable: Bool?) {
        guard let folder = registration.skillFolder else { return (nil, nil) }
        switch folder.kind {
        case .triptychControl:
            let url = try triptychURL(for: folder)
            return (
                url.path,
                SecureResearchMethodIO.directoryIsAvailable(atPath: url.path)
            )
        case .machineLocal:
            guard let methodLocators else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Machine-local Method locator storage is unavailable."
                )
            }
            let status = try methodLocators.skillFolderStatus(for: registration.key)
            guard status.path != nil else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The machine-local Skill-folder locator is missing."
                )
            }
            return status
        }
    }

    private func triptychURL(
        for location: ResearchMethodFileLocation
    ) throws -> URL {
        guard location.kind == .triptychControl,
              let relativePath = location.triptychRelativePath else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "A machine-local Method cannot resolve through portable state."
            )
        }
        return controlURL.appendingPathComponent(relativePath).standardizedFileURL
    }

    private func removeUnusedMachineLocator(
        _ key: ResearchSkillRegistrationKey,
        retaining retainedKey: ResearchSkillRegistrationKey
    ) throws {
        guard key != retainedKey, let methodLocators,
              let snapshot = try methodLocators.snapshot() else { return }
        _ = try methodLocators.save(
            try snapshot.document.removing(key),
            expectedRevision: snapshot.revision
        )
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

private enum SecureResearchMethodIO {
    static let maximumMethodByteCount = 1_048_576

    static func data(at url: URL) throws -> Data {
        let parent = try SecureResearchConfigurationIO.openAbsoluteDirectory(
            url.deletingLastPathComponent()
        )
        defer { Darwin.close(parent) }
        do {
            return try SecureResearchConfigurationIO.readDataFile(
                parentDescriptor: parent,
                leaf: url.lastPathComponent,
                path: url.path,
                maximumByteCount: maximumMethodByteCount
            )
        } catch {
            throw ResearchConfigurationStoreError.missingMethod(url.path)
        }
    }

    static func read(at url: URL) throws -> String {
        let data = try data(at: url)
        guard let source = String(data: data, encoding: .utf8) else {
            throw ResearchConfigurationStoreError.invalidMethod(url.path)
        }
        return source
    }

    static func replace(
        at url: URL,
        data: Data,
        expectedRevision: DocumentFingerprint
    ) throws -> DocumentFingerprint {
        guard data.count <= maximumMethodByteCount,
              String(data: data, encoding: .utf8) != nil else {
            throw ResearchConfigurationStoreError.invalidMethod(url.path)
        }
        let parentURL = url.deletingLastPathComponent()
        let parent = try SecureResearchConfigurationIO.openAbsoluteDirectory(parentURL)
        defer { Darwin.close(parent) }
        let identity = try SecureResearchConfigurationIO.identity(
            of: parent,
            path: parentURL.path
        )
        let current = try SecureResearchConfigurationIO.readDataFile(
            parentDescriptor: parent,
            leaf: url.lastPathComponent,
            path: url.path,
            maximumByteCount: maximumMethodByteCount
        )
        guard DocumentFingerprint(data: current) == expectedRevision else {
            throw ResearchConfigurationStoreError.staleDocument
        }
        let stage = ".method-edit-\(UUID().uuidString.lowercased())"
        var stageExists = false
        var committed = false
        do {
            try SecureResearchConfigurationIO.createDataFile(
                parentDescriptor: parent,
                leaf: stage,
                data: data,
                path: stage
            )
            stageExists = true
            try SecureResearchConfigurationIO.swapEntries(
                parentDescriptor: parent,
                first: url.lastPathComponent,
                second: stage
            )
            committed = true
            guard fsync(parent) == 0 else {
                throw ResearchConfigurationStoreError.unsafeStorage
            }
            let readback = try SecureResearchConfigurationIO.readDataFile(
                parentDescriptor: parent,
                leaf: url.lastPathComponent,
                path: url.path,
                maximumByteCount: maximumMethodByteCount
            )
            guard readback == data,
                  try SecureResearchConfigurationIO.pathStillRefersToDirectory(
                    parentURL,
                    identity: identity
                  ) else {
                throw ResearchConfigurationStoreError.unsafeStorage
            }
            try SecureResearchConfigurationIO.removeDataFile(
                parentDescriptor: parent,
                leaf: stage,
                path: stage
            )
            stageExists = false
            guard fsync(parent) == 0 else {
                throw ResearchConfigurationStoreError.unsafeStorage
            }
            return DocumentFingerprint(data: readback)
        } catch {
            if stageExists && !committed {
                try? SecureResearchConfigurationIO.removeDataFile(
                    parentDescriptor: parent,
                    leaf: stage,
                    path: stage
                )
            }
            throw error
        }
    }

    static func directoryIsAvailable(atPath path: String) -> Bool {
        do {
            let descriptor = try SecureResearchConfigurationIO.openAbsoluteDirectory(
                URL(fileURLWithPath: path)
            )
            Darwin.close(descriptor)
            return true
        } catch {
            return false
        }
    }

}
