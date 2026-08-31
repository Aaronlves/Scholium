import Darwin
import Foundation
import ScholiumContracts

/// Keeps one resolved security-scoped Skill-folder bookmark active only while
/// Presentation hands the folder URL to Finder. It grants no content mutation
/// and stops access deterministically when the short-lived value is released.
final class ResearchSkillFolderAccessLease: ResearchSkillFolderAccess, @unchecked Sendable {
    public let url: URL
    private let stopAccess: @Sendable () -> Void

    init(url: URL, stopAccess: @escaping @Sendable () -> Void) {
        self.url = url
        self.stopAccess = stopAccess
    }

    deinit { stopAccess() }
}

/// Machine-local ownership of researcher-selected Skill-folder paths. Portable
/// registration carries only the opaque registration key and a `machine_local`
/// marker; bookmark bytes and paths never enter `.scholium` or a portable
/// Research Record. The bookmark authorizes folder reveal only. Scholium never
/// reads or writes the folder's contents.
struct ResearchSkillFolderLocatorStore {
    static let fileName = "skill-folder-locators-v1.json"

    struct BookmarkResolution: Sendable {
        let url: URL
        let isStale: Bool
    }

    struct BookmarkAccess: Sendable {
        let create: @Sendable (URL) throws -> Data
        let resolve: @Sendable (Data) throws -> BookmarkResolution
        let start: @Sendable (URL) -> Bool
        let stop: @Sendable (URL) -> Void

        static let foundation = Self(
            create: { url in
                return try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: [
                        .fileResourceIdentifierKey,
                        .isRegularFileKey,
                        .isDirectoryKey,
                    ],
                    relativeTo: nil
                )
            },
            resolve: { data in
                var stale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                return BookmarkResolution(url: url, isStale: stale)
            },
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() }
        )
    }

    struct Binding: Codable, Hashable, Sendable {
        let registrationKey: ResearchSkillRegistrationKey
        let skillFolderCanonicalPath: String
        let skillFolderBookmarkData: Data

        init(
            registrationKey: ResearchSkillRegistrationKey,
            skillFolderCanonicalPath: String,
            skillFolderBookmarkData: Data
        ) throws {
            guard Self.isCanonicalAbsolute(skillFolderCanonicalPath),
                  !skillFolderBookmarkData.isEmpty else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The machine-local Skill-folder locator is invalid."
                )
            }
            self.registrationKey = registrationKey
            self.skillFolderCanonicalPath = skillFolderCanonicalPath
            self.skillFolderBookmarkData = skillFolderBookmarkData
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case registrationKey
            case skillFolderCanonicalPath
            case skillFolderBookmarkData
        }

        init(from decoder: Decoder) throws {
            try ResearchSkillFolderLocatorStore.rejectUnknownFields(
                decoder,
                allowed: CodingKeys.self
            )
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                registrationKey: values.decode(
                    ResearchSkillRegistrationKey.self,
                    forKey: .registrationKey
                ),
                skillFolderCanonicalPath: values.decode(
                    String.self,
                    forKey: .skillFolderCanonicalPath
                ),
                skillFolderBookmarkData: values.decode(
                    Data.self,
                    forKey: .skillFolderBookmarkData
                )
            )
        }

        private static func isCanonicalAbsolute(_ path: String) -> Bool {
            path.hasPrefix("/")
                && path != "/"
                && URL(fileURLWithPath: path).standardizedFileURL.path == path
                && !path.unicodeScalars.contains(
                    where: CharacterSet.controlCharacters.contains
                )
        }
    }

    struct Document: Codable, Hashable, Sendable {
        static let currentSchemaVersion = 1
        let schemaVersion: Int
        let triptychID: UUID
        let bindings: [Binding]

        init(triptychID: UUID, bindings: [Binding] = []) throws {
            guard bindings.count <= ResearchSkillRegistrationDocument
                .maximumRegistrationCount,
                Set(bindings.map(\.registrationKey)).count == bindings.count else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The machine-local Skill-folder locator document is invalid."
                )
            }
            schemaVersion = Self.currentSchemaVersion
            self.triptychID = triptychID
            self.bindings = bindings.sorted {
                $0.registrationKey.description < $1.registrationKey.description
            }
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion
            case triptychID
            case bindings
        }

        init(from decoder: Decoder) throws {
            try ResearchSkillFolderLocatorStore.rejectUnknownFields(
                decoder,
                allowed: CodingKeys.self
            )
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let version = try values.decode(Int.self, forKey: .schemaVersion)
            guard version == Self.currentSchemaVersion else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Unsupported machine-local Skill-folder locator schema \(version)."
                )
            }
            try self.init(
                triptychID: values.decode(UUID.self, forKey: .triptychID),
                bindings: values.decode([Binding].self, forKey: .bindings)
            )
        }

        func replacing(_ binding: Binding) throws -> Self {
            try Self(
                triptychID: triptychID,
                bindings: bindings.filter {
                    $0.registrationKey != binding.registrationKey
                } + [binding]
            )
        }

        func removing(_ key: ResearchSkillRegistrationKey) throws -> Self {
            try Self(
                triptychID: triptychID,
                bindings: bindings.filter { $0.registrationKey != key }
            )
        }
    }

    let triptychID: UUID
    let storageURL: URL
    let bookmarkAccess: BookmarkAccess
    let fileManager: FileManager
    let store: StrictResearchJSONStore<Document>

    init(
        storageURL: URL,
        triptychID: UUID,
        bookmarkAccess: BookmarkAccess = .foundation,
        fileManager: FileManager = .default
    ) {
        let root = storageURL.standardizedFileURL
        self.triptychID = triptychID
        self.storageURL = root
        self.bookmarkAccess = bookmarkAccess
        self.fileManager = fileManager
        store = StrictResearchJSONStore(
            controlURL: root,
            fileName: Self.fileName,
            maximumByteCount: 4_194_304,
            fileManager: fileManager
        )
    }

    func snapshot() throws -> StoredResearchDocument<Document>? {
        let snapshot: StoredResearchDocument<Document>?
        do {
            snapshot = try store.snapshot()
        } catch {
            throw ResearchSkillFolderLocatorError.invalid(
                error.localizedDescription
            )
        }
        guard snapshot?.document.triptychID == triptychID || snapshot == nil else {
            throw ResearchSkillFolderLocatorError.invalid(
                "The machine-local Skill-folder locator belongs to another Triptych."
            )
        }
        return snapshot
    }

    @discardableResult
    func preserveInvalidAndReset() throws -> URL? {
        do {
            _ = try snapshot()
            return nil
        } catch ResearchSkillFolderLocatorError.invalid {
            // Continue only for the typed invalid-document state established
            // by `snapshot`; unsafe directory or write errors never reach here.
        }
        let source = storageURL.appendingPathComponent(Self.fileName)
        let preserved = try ExactStatePreserver.preserve(
            source,
            kind: .regularFile,
            recoveryStem: "skill-folder-locators-v1.corrupt",
            recoveryExtension: "json",
            fileEligibility: { data in
                guard let document = try? JSONDecoder().decode(Document.self, from: data)
                else { return true }
                return document.triptychID != triptychID
            },
            fileManager: fileManager
        )
        _ = try save(Document(triptychID: triptychID), expectedRevision: nil)
        return preserved
    }

    func makeBinding(
        registrationKey: ResearchSkillRegistrationKey,
        skillFolderURL: URL
    ) throws -> Binding {
        let folder = skillFolderURL.standardizedFileURL
        let folderBookmark = try makeBookmark(for: folder)
        return try Binding(
            registrationKey: registrationKey,
            skillFolderCanonicalPath: folder.path,
            skillFolderBookmarkData: folderBookmark
        )
    }

    func save(
        _ document: Document,
        expectedRevision: DocumentFingerprint?
    ) throws -> StoredResearchDocument<Document> {
        guard document.triptychID == triptychID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder locator belongs to another Triptych."
            )
        }
        try ensurePrivateStorageDirectory()
        return try store.save(document, expectedRevision: expectedRevision)
    }

    func binding(for key: ResearchSkillRegistrationKey) throws -> Binding {
        guard let binding = try snapshot()?.document.bindings.first(where: {
            $0.registrationKey == key
        }) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder locator is missing."
            )
        }
        return binding
    }

    func withSkillFolderURL<Result>(
        for key: ResearchSkillRegistrationKey,
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        let binding = try binding(for: key)
        return try withResolvedBookmark(
            binding.skillFolderBookmarkData,
            expectedPath: binding.skillFolderCanonicalPath,
            operation
        )
    }

    func skillFolderStatus(
        for key: ResearchSkillRegistrationKey
    ) throws -> (path: String, isAvailable: Bool) {
        let binding = try binding(for: key)
        let available = (try? withResolvedBookmark(
            binding.skillFolderBookmarkData,
            expectedPath: binding.skillFolderCanonicalPath
        ) { url in
            let descriptor = try SecureResearchConfigurationIO
                .openAbsoluteDirectory(url)
            Darwin.close(descriptor)
            return true
        }) ?? false
        return (binding.skillFolderCanonicalPath, available)
    }

    func skillFolderAccess(
        for key: ResearchSkillRegistrationKey
    ) throws -> any ResearchSkillFolderAccess {
        let binding = try binding(for: key)
        let resolution: BookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(
                binding.skillFolderBookmarkData
            )
        } catch {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark cannot be resolved."
            )
        }
        guard !resolution.isStale,
              bookmarkAccess.start(resolution.url) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark is stale or unavailable."
            )
        }
        let canonical = resolution.url.resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonical.path == binding.skillFolderCanonicalPath else {
            bookmarkAccess.stop(resolution.url)
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark changed identity."
            )
        }
        let accessURL = resolution.url
        let stop = bookmarkAccess.stop
        return ResearchSkillFolderAccessLease(url: accessURL.standardizedFileURL) {
            stop(accessURL)
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        guard bookmarkAccess.start(url) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The selected Skill folder did not grant local access."
            )
        }
        defer { bookmarkAccess.stop(url) }
        let data = try bookmarkAccess.create(url)
        _ = try withResolvedBookmark(data, expectedPath: url.path) { $0 }
        return data
    }

    private func withResolvedBookmark<Result>(
        _ data: Data,
        expectedPath: String,
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        let resolution: BookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(data)
        } catch {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark cannot be resolved."
            )
        }
        guard !resolution.isStale,
              bookmarkAccess.start(resolution.url) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark is stale or unavailable."
            )
        }
        defer { bookmarkAccess.stop(resolution.url) }
        let canonical = resolution.url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == expectedPath else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Skill-folder bookmark changed identity."
            )
        }
        return try operation(resolution.url.standardizedFileURL)
    }

    private func ensurePrivateStorageDirectory() throws {
        let manager = fileManager
        if !manager.fileExists(atPath: storageURL.path) {
            try manager.createDirectory(
                at: storageURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        let values = try storageURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchConfigurationStoreError.unsafeStorage
        }
        try manager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: storageURL.path
        )
    }

    private static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let raw = try decoder.container(keyedBy: AnyCodingKey.self)
        let known = Set(Key.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !known.contains($0)
        }) {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Unsupported machine-local Skill-folder locator field \(unknown)."
            )
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
