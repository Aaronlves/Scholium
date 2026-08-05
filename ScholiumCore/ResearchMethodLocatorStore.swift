import Darwin
import Foundation
import ScholiumContracts

/// Machine-local ownership of absolute primary-Method and optional Skill-folder
/// paths. Portable registration carries only the opaque registration key and a
/// `machine_local` marker; bookmark bytes and paths never enter `.scholium` or
/// a portable Research Record.
struct ResearchMethodLocatorStore {
    static let fileName = "method-locators-v1.json"

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
                try url.bookmarkData(
                    options: [.withSecurityScope],
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
        let primaryCanonicalPath: String
        let primaryBookmarkData: Data
        let skillFolderCanonicalPath: String?
        let skillFolderBookmarkData: Data?

        init(
            registrationKey: ResearchSkillRegistrationKey,
            primaryCanonicalPath: String,
            primaryBookmarkData: Data,
            skillFolderCanonicalPath: String?,
            skillFolderBookmarkData: Data?
        ) throws {
            guard Self.isCanonicalAbsolute(primaryCanonicalPath),
                  !primaryBookmarkData.isEmpty,
                  (skillFolderCanonicalPath == nil)
                    == (skillFolderBookmarkData == nil),
                  skillFolderBookmarkData.map({ !$0.isEmpty }) ?? true else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "The machine-local Method locator is invalid."
                )
            }
            if let skillFolderCanonicalPath {
                guard Self.isCanonicalAbsolute(skillFolderCanonicalPath),
                      Self.contains(
                        path: primaryCanonicalPath,
                        inFolder: skillFolderCanonicalPath
                      ) else {
                    throw ResearchConfigurationStoreError.invalidDocument(
                        "The primary Method is outside its registered Skill folder."
                    )
                }
            }
            self.registrationKey = registrationKey
            self.primaryCanonicalPath = primaryCanonicalPath
            self.primaryBookmarkData = primaryBookmarkData
            self.skillFolderCanonicalPath = skillFolderCanonicalPath
            self.skillFolderBookmarkData = skillFolderBookmarkData
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case registrationKey
            case primaryCanonicalPath
            case primaryBookmarkData
            case skillFolderCanonicalPath
            case skillFolderBookmarkData
        }

        init(from decoder: Decoder) throws {
            try ResearchMethodLocatorStore.rejectUnknownFields(
                decoder,
                allowed: CodingKeys.self
            )
            let values = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                registrationKey: values.decode(
                    ResearchSkillRegistrationKey.self,
                    forKey: .registrationKey
                ),
                primaryCanonicalPath: values.decode(
                    String.self,
                    forKey: .primaryCanonicalPath
                ),
                primaryBookmarkData: values.decode(
                    Data.self,
                    forKey: .primaryBookmarkData
                ),
                skillFolderCanonicalPath: values.decodeIfPresent(
                    String.self,
                    forKey: .skillFolderCanonicalPath
                ),
                skillFolderBookmarkData: values.decodeIfPresent(
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

        private static func contains(path: String, inFolder folder: String) -> Bool {
            let pathParts = URL(fileURLWithPath: path).pathComponents
            let folderParts = URL(fileURLWithPath: folder).pathComponents
            return pathParts.count > folderParts.count
                && Array(pathParts.prefix(folderParts.count)) == folderParts
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
                    "The machine-local Method locator document is invalid."
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
            try ResearchMethodLocatorStore.rejectUnknownFields(
                decoder,
                allowed: CodingKeys.self
            )
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let version = try values.decode(Int.self, forKey: .schemaVersion)
            guard version == Self.currentSchemaVersion else {
                throw ResearchConfigurationStoreError.invalidDocument(
                    "Unsupported machine-local Method locator schema \(version)."
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
        let snapshot = try store.snapshot()
        guard snapshot?.document.triptychID == triptychID || snapshot == nil else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Method locator belongs to another Triptych."
            )
        }
        return snapshot
    }

    func makeBinding(
        registrationKey: ResearchSkillRegistrationKey,
        primaryURL: URL,
        skillFolderURL: URL?
    ) throws -> Binding {
        let primary = primaryURL.standardizedFileURL
        let folder = skillFolderURL?.standardizedFileURL
        let primaryBookmark = try makeBookmark(for: primary)
        let folderBookmark = try folder.map(makeBookmark(for:))
        return try Binding(
            registrationKey: registrationKey,
            primaryCanonicalPath: primary.path,
            primaryBookmarkData: primaryBookmark,
            skillFolderCanonicalPath: folder?.path,
            skillFolderBookmarkData: folderBookmark
        )
    }

    func save(
        _ document: Document,
        expectedRevision: DocumentFingerprint?
    ) throws -> StoredResearchDocument<Document> {
        guard document.triptychID == triptychID else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Method locator belongs to another Triptych."
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
                "The machine-local Method locator is missing."
            )
        }
        return binding
    }

    func withPrimaryURL<Result>(
        for key: ResearchSkillRegistrationKey,
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        let binding = try binding(for: key)
        return try withResolvedBookmark(
            binding.primaryBookmarkData,
            expectedPath: binding.primaryCanonicalPath,
            operation
        )
    }

    func skillFolderStatus(
        for key: ResearchSkillRegistrationKey
    ) throws -> (path: String?, isAvailable: Bool?) {
        let binding = try binding(for: key)
        guard let path = binding.skillFolderCanonicalPath,
              let bookmark = binding.skillFolderBookmarkData else {
            return (nil, nil)
        }
        let available = (try? withResolvedBookmark(
            bookmark,
            expectedPath: path
        ) { url in
            let descriptor = try SecureResearchConfigurationIO
                .openAbsoluteDirectory(url)
            Darwin.close(descriptor)
            return true
        }) ?? false
        return (path, available)
    }

    private func makeBookmark(for url: URL) throws -> Data {
        guard bookmarkAccess.start(url) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The selected Method path did not grant local access."
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
                "The machine-local Method bookmark cannot be resolved."
            )
        }
        guard !resolution.isStale,
              bookmarkAccess.start(resolution.url) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Method bookmark is stale or unavailable."
            )
        }
        defer { bookmarkAccess.stop(resolution.url) }
        let canonical = resolution.url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == expectedPath else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "The machine-local Method bookmark changed identity."
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
                "Unsupported machine-local Method locator field \(unknown)."
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
