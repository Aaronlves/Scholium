import Darwin
import Foundation
import ScholiumContracts

public enum ResearchPermissionPolicyStoreError: LocalizedError, Hashable, Sendable {
    case staleRevision
    case corruptStore
    case unsafeStore

    public var errorDescription: String? {
        switch self {
        case .staleRevision:
            "The Research Permission policy changed. Reload it before saving."
        case .corruptStore:
            "The machine-local Research Permission policy is malformed or unreadable."
        case .unsafeStore:
            "The machine-local Research Permission policy location is unsafe or changed during saving."
        }
    }
}

/// Machine-local standing policy storage for one Triptych.
///
/// The policy is configuration rather than research data or a bearer token.
/// It remains under Application Support and is revision checked, mode private,
/// no-follow, atomically replaced, read back, and Triptych identity bound.
public actor ResearchPermissionPolicyStore {
    private static let payloadSchemaVersion = 1
    private static let directoryMode = mode_t(0o700)
    private static let fileMode = mode_t(0o600)
    private static let maximumStoreByteCount = 1024 * 1024
    private static let policyFileName = "standing-permissions-v1.json"
    private static let lockFileName = ".standing-permissions-v1.lock"
    /// BSD `flock` is not a sufficient serialization boundary between two
    /// independently opened descriptors in one process on every supported
    /// runtime. Keep the file lock for other processes, and serialize the
    /// short policy transaction in-process as well.
    private static let processLock = NSLock()

    private struct Payload: Codable, Hashable {
        let schemaVersion: Int
        let triptychID: UUID
        let document: ResearchPermissionPolicyDocument

        init(triptychID: UUID, document: ResearchPermissionPolicyDocument) {
            schemaVersion = ResearchPermissionPolicyStore.payloadSchemaVersion
            self.triptychID = triptychID
            self.document = document
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schemaVersion = "schema_version"
            case triptychID = "triptych_id"
            case document
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyCodingKey.self)
            let allowed = Set(CodingKeys.allCases.map(\.stringValue))
            guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
                throw ResearchPermissionPolicyStoreError.corruptStore
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let version = try container.decode(Int.self, forKey: .schemaVersion)
            guard version == ResearchPermissionPolicyStore.payloadSchemaVersion else {
                throw ResearchPermissionPolicyStoreError.corruptStore
            }
            schemaVersion = version
            triptychID = try container.decode(UUID.self, forKey: .triptychID)
            document = try container.decode(
                ResearchPermissionPolicyDocument.self,
                forKey: .document
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

    private let triptychID: UUID
    private let trustedRootURL: URL
    private let storageComponents: [String]

    public init(applicationSupportURL: URL, triptychID: UUID) {
        self.triptychID = triptychID
        trustedRootURL = applicationSupportURL.standardizedFileURL
        storageComponents = [
            "Triptychs",
            triptychID.uuidString,
            "research-guidance",
            "standing-permissions-v1",
        ]
    }

    init(storageURL: URL, triptychID: UUID) {
        self.triptychID = triptychID
        trustedRootURL = storageURL.deletingLastPathComponent().standardizedFileURL
        storageComponents = [storageURL.lastPathComponent]
    }

    public func snapshot() throws -> ResearchPermissionPolicySnapshot {
        let directory = try openStorageDirectory(createIfMissing: false)
        guard directory >= 0 else { return try Self.defaultSnapshot() }
        defer { close(directory) }
        return try withLock(in: directory, exclusive: false) {
            try loadSnapshot(from: directory)
        }
    }

    public func saveTriptychDefault(
        _ policy: ResearchPermissionPolicy,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchPermissionPolicySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            try document.replacingTriptychDefault(policy)
        }
    }

    public func saveOverride(
        packageID: String,
        policy: ResearchPermissionPolicy,
        approvedEnvelopeDigest: DocumentFingerprint,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchPermissionPolicySnapshot {
        let override = try ResearchSkillPermissionOverride(
            packageID: packageID,
            policy: policy,
            approvedEnvelopeDigest: approvedEnvelopeDigest
        )
        return try mutate(expectedRevision: expectedRevision) { document in
            try document.replacingOverride(override)
        }
    }

    public func removeOverride(
        packageID: String,
        expectedRevision: DocumentFingerprint?
    ) throws -> ResearchPermissionPolicySnapshot {
        try mutate(expectedRevision: expectedRevision) { document in
            try document.removingOverride(for: packageID)
        }
    }

    private func mutate(
        expectedRevision: DocumentFingerprint?,
        transform: (ResearchPermissionPolicyDocument) throws
            -> ResearchPermissionPolicyDocument
    ) throws -> ResearchPermissionPolicySnapshot {
        let directory = try openStorageDirectory(createIfMissing: true)
        guard directory >= 0 else { throw ResearchPermissionPolicyStoreError.unsafeStore }
        defer { close(directory) }
        return try withLock(in: directory, exclusive: true) {
            let current = try loadSnapshot(from: directory)
            guard current.revision == expectedRevision else {
                throw ResearchPermissionPolicyStoreError.staleRevision
            }
            return try persist(
                transform(current.document),
                to: directory
            )
        }
    }

    private static func defaultSnapshot() throws -> ResearchPermissionPolicySnapshot {
        ResearchPermissionPolicySnapshot(
            document: try ResearchPermissionPolicyDocument(),
            revision: nil
        )
    }

    private func loadSnapshot(
        from directoryDescriptor: Int32
    ) throws -> ResearchPermissionPolicySnapshot {
        guard let data = try readPolicyData(from: directoryDescriptor) else {
            return try Self.defaultSnapshot()
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.triptychID == triptychID else {
                throw ResearchPermissionPolicyStoreError.corruptStore
            }
            return ResearchPermissionPolicySnapshot(
                document: payload.document,
                revision: DocumentFingerprint(data: data)
            )
        } catch let error as ResearchPermissionPolicyStoreError {
            throw error
        } catch {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
    }

    private func persist(
        _ document: ResearchPermissionPolicyDocument,
        to directoryDescriptor: Int32
    ) throws -> ResearchPermissionPolicySnapshot {
        do {
            let payload = Payload(triptychID: triptychID, document: document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            guard data.count <= Self.maximumStoreByteCount else {
                throw ResearchPermissionPolicyStoreError.corruptStore
            }
            try rejectUnsafePolicyLeaf(in: directoryDescriptor)

            var originalDirectoryState = stat()
            guard fstat(directoryDescriptor, &originalDirectoryState) == 0 else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }

            let temporaryName = ".standing-permissions-\(UUID().uuidString).tmp"
            let temporaryDescriptor = temporaryName.withCString { name in
                openat(
                    directoryDescriptor,
                    name,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    Self.fileMode
                )
            }
            guard temporaryDescriptor >= 0 else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            var removeTemporary = true
            defer {
                close(temporaryDescriptor)
                if removeTemporary {
                    _ = temporaryName.withCString {
                        unlinkat(directoryDescriptor, $0, 0)
                    }
                }
            }
            try Self.writeAll(data, to: temporaryDescriptor)
            guard fchmod(temporaryDescriptor, Self.fileMode) == 0,
                  fsync(temporaryDescriptor) == 0 else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            let renameResult = temporaryName.withCString { temporary in
                Self.policyFileName.withCString { destination in
                    renameat(
                        directoryDescriptor,
                        temporary,
                        directoryDescriptor,
                        destination
                    )
                }
            }
            guard renameResult == 0 else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            removeTemporary = false
            guard fsync(directoryDescriptor) == 0,
                  try storagePathStillIdentifies(originalDirectoryState),
                  let readback = try readPolicyData(from: directoryDescriptor),
                  readback == data else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            let decoded = try JSONDecoder().decode(Payload.self, from: readback)
            guard decoded == payload else {
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            return ResearchPermissionPolicySnapshot(
                document: document,
                revision: DocumentFingerprint(data: readback)
            )
        } catch let error as ResearchPermissionPolicyStoreError {
            throw error
        } catch {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
    }

    private func openStorageDirectory(createIfMissing: Bool) throws -> Int32 {
        var current = trustedRootURL.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard current >= 0 else {
            throw ResearchPermissionPolicyStoreError.unsafeStore
        }
        for (index, component) in storageComponents.enumerated() {
            let isFinal = index == storageComponents.index(before: storageComponents.endIndex)
            var metadata = stat()
            var result = component.withCString {
                fstatat(current, $0, &metadata, AT_SYMLINK_NOFOLLOW)
            }
            if result != 0, errno == ENOENT {
                guard createIfMissing else {
                    close(current)
                    return -1
                }
                result = component.withCString {
                    mkdirat(current, $0, Self.directoryMode)
                }
                guard result == 0 || errno == EEXIST else {
                    close(current)
                    throw ResearchPermissionPolicyStoreError.unsafeStore
                }
            } else {
                guard result == 0,
                      (metadata.st_mode & S_IFMT) == S_IFDIR else {
                    close(current)
                    throw ResearchPermissionPolicyStoreError.unsafeStore
                }
            }
            let next = component.withCString {
                openat(current, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else {
                close(current)
                throw ResearchPermissionPolicyStoreError.unsafeStore
            }
            close(current)
            current = next
            if isFinal {
                var opened = stat()
                guard fstat(current, &opened) == 0,
                      (opened.st_mode & S_IFMT) == S_IFDIR,
                      opened.st_nlink >= 1 else {
                    close(current)
                    throw ResearchPermissionPolicyStoreError.unsafeStore
                }
                if opened.st_mode & 0o777 != Self.directoryMode {
                    guard fchmod(current, Self.directoryMode) == 0,
                          fsync(current) == 0 else {
                        close(current)
                        throw ResearchPermissionPolicyStoreError.unsafeStore
                    }
                }
            }
        }
        return current
    }

    private func storagePathStillIdentifies(_ expected: stat) throws -> Bool {
        let current = try openStorageDirectory(createIfMissing: false)
        guard current >= 0 else { return false }
        defer { close(current) }
        var observed = stat()
        return fstat(current, &observed) == 0
            && observed.st_dev == expected.st_dev
            && observed.st_ino == expected.st_ino
    }

    private func withLock<T>(
        in directoryDescriptor: Int32,
        exclusive: Bool,
        operation: () throws -> T
    ) throws -> T {
        Self.processLock.lock()
        defer { Self.processLock.unlock() }
        let lockDescriptor = Self.lockFileName.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                Self.fileMode
            )
        }
        guard lockDescriptor >= 0 else {
            throw ResearchPermissionPolicyStoreError.unsafeStore
        }
        defer { close(lockDescriptor) }
        var metadata = stat()
        guard fstat(lockDescriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_mode & 0o777 == Self.fileMode else {
            throw ResearchPermissionPolicyStoreError.unsafeStore
        }
        let lockOperation = exclusive ? LOCK_EX : LOCK_SH
        guard flock(lockDescriptor, lockOperation) == 0 else {
            throw ResearchPermissionPolicyStoreError.unsafeStore
        }
        defer { _ = flock(lockDescriptor, LOCK_UN) }
        return try operation()
    }

    private func readPolicyData(from directoryDescriptor: Int32) throws -> Data? {
        let descriptor = Self.policyFileName.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_mode & 0o777 == Self.fileMode,
              before.st_size >= 0,
              before.st_size <= Self.maximumStoreByteCount else {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
        let expectedCount = Int(before.st_size)
        guard let data = try handle.read(upToCount: expectedCount + 1),
              data.count == expectedCount else {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              Self.sameFileState(before, after) else {
            throw ResearchPermissionPolicyStoreError.corruptStore
        }
        return data
    }

    private func rejectUnsafePolicyLeaf(in directoryDescriptor: Int32) throws {
        var metadata = stat()
        let result = Self.policyFileName.withCString {
            fstatat(directoryDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0, errno == ENOENT { return }
        guard result == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1,
              metadata.st_mode & 0o777 == Self.fileMode else {
            throw ResearchPermissionPolicyStoreError.unsafeStore
        }
    }

    private nonisolated static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard var pointer = bytes.baseAddress else { return }
            var remaining = bytes.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, pointer, remaining)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else {
                    throw ResearchPermissionPolicyStoreError.unsafeStore
                }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }

    private nonisolated static func sameFileState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
