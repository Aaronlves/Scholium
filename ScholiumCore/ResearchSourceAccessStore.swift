import CryptoKit
import Darwin
import Foundation
import ScholiumContracts

public struct ResolvedResearchSourceAccess: Hashable, Sendable {
    public let reference: ResearchSourceReference
    /// A machine-local locator for the current delivery packet only. This
    /// type is intentionally not Codable and never enters a portable record.
    public let fileURL: URL

    public init(reference: ResearchSourceReference, fileURL: URL) {
        self.reference = reference
        self.fileURL = fileURL
    }
}

public enum ResearchSourceAccessStoreError: LocalizedError, Sendable {
    case failure(ResearchSourceAccessFailure)

    public var failure: ResearchSourceAccessFailure {
        switch self {
        case .failure(let failure): failure
        }
    }

    public var errorDescription: String? {
        "Source access failed with \(failure.code.rawValue). Choose the source again."
    }
}

struct ResearchSourceBookmarkResolution: Sendable {
    let url: URL
    let isStale: Bool
}

struct ResearchSourceBookmarkAccess: Sendable {
    let create: @Sendable (URL) throws -> Data
    let resolve: @Sendable (Data) throws -> ResearchSourceBookmarkResolution
    let start: @Sendable (URL) -> Bool
    let stop: @Sendable (URL) -> Void

    static let foundation = Self(
        create: { url in
            try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [
                    .fileResourceIdentifierKey,
                    .isRegularFileKey,
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
            return ResearchSourceBookmarkResolution(url: url, isStale: stale)
        },
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )
}

/// Machine-local ownership of exact Analysis source bindings. The portable
/// source reference is embedded inside each private binding, while bookmark
/// bytes and canonical paths never leave this Application Support store.
public actor ResearchSourceAccessStore {
    private static let currentSchemaVersion = 1
    private static let directoryMode = mode_t(0o700)
    private static let fileMode = mode_t(0o600)
    private static let readChunkSize = 256 * 1024
    private static let maximumStoreByteCount = 4 * 1024 * 1024
    private static let bindingFileName = "source-bindings-v1.json"

    private struct Binding: Codable, Hashable {
        let analysisNoteID: UUID
        let reference: ResearchSourceReference
        let canonicalPath: String
        let bookmarkData: Data
    }

    private struct Payload: Codable, Hashable {
        let schemaVersion: Int
        let triptychID: UUID
        var bindings: [Binding]
    }

    private struct InspectedFile {
        let url: URL
        let fingerprint: DocumentFingerprint
    }

    private let triptychID: UUID
    private let trustedRootURL: URL
    private let storageComponents: [String]
    private let bookmarkAccess: ResearchSourceBookmarkAccess

    public init(applicationSupportURL: URL, triptychID: UUID) {
        self.init(
            trustedRootURL: applicationSupportURL,
            storageComponents: [
                "Triptychs",
                triptychID.uuidString,
                "source-access",
            ],
            triptychID: triptychID,
            bookmarkAccess: .foundation
        )
    }

    init(
        storageURL: URL,
        triptychID: UUID,
        bookmarkAccess: ResearchSourceBookmarkAccess
    ) {
        self.init(
            trustedRootURL: storageURL.deletingLastPathComponent(),
            storageComponents: [storageURL.lastPathComponent],
            triptychID: triptychID,
            bookmarkAccess: bookmarkAccess
        )
    }

    init(
        trustedRootURL: URL,
        storageComponents: [String],
        triptychID: UUID,
        bookmarkAccess: ResearchSourceBookmarkAccess
    ) {
        precondition(!storageComponents.isEmpty)
        precondition(storageComponents.allSatisfy(Self.isSafePathComponent))
        self.triptychID = triptychID
        self.trustedRootURL = trustedRootURL.standardizedFileURL
        self.storageComponents = storageComponents
        self.bookmarkAccess = bookmarkAccess
    }

    public func bindLocalFile(
        analysisNoteID: UUID,
        selectedURL: URL
    ) throws -> ResearchSourceReference {
        guard bookmarkAccess.start(selectedURL) else {
            throw Self.failure(.bookmarkUnavailable)
        }
        defer { bookmarkAccess.stop(selectedURL) }
        let selected = try Self.inspectFile(at: selectedURL)
        let payload = try loadForBinding()
        let previous = payload.bindings.first(where: {
            $0.analysisNoteID == analysisNoteID
                && $0.reference.identity.route == .localFile
                && $0.canonicalPath == selected.url.path
        })
        let identity = previous?.reference.identity ?? .localFile()
        return try bind(
            payload: payload,
            analysisNoteID: analysisNoteID,
            selected: selected,
            identity: identity,
            displayName: selected.url.lastPathComponent
        )
    }

    public func bindZoteroAttachment(
        analysisNoteID: UUID,
        itemKey: String,
        attachmentKey: String,
        selectedURL: URL,
        displayName: String? = nil
    ) throws -> ResearchSourceReference {
        guard bookmarkAccess.start(selectedURL) else {
            throw Self.failure(.bookmarkUnavailable)
        }
        defer { bookmarkAccess.stop(selectedURL) }
        let selected = try Self.inspectFile(at: selectedURL)
        let normalizedIdentity = try ResearchSourceIdentity.zoteroAttachment(
            itemKey: itemKey,
            attachmentKey: attachmentKey
        )
        let payload = try loadForBinding()
        let previous = payload.bindings.first(where: { binding in
            binding.analysisNoteID == analysisNoteID
                && binding.reference.identity.route == .zoteroAttachment
                && binding.reference.identity.zoteroItemKey
                    == normalizedIdentity.zoteroItemKey
                && binding.reference.identity.zoteroAttachmentKey
                    == normalizedIdentity.zoteroAttachmentKey
        })
        let identity: ResearchSourceIdentity
        if let previous {
            identity = try .zoteroAttachment(
                id: previous.reference.identity.id,
                itemKey: itemKey,
                attachmentKey: attachmentKey
            )
        } else {
            identity = normalizedIdentity
        }
        return try bind(
            payload: payload,
            analysisNoteID: analysisNoteID,
            selected: selected,
            identity: identity,
            displayName: displayName ?? selected.url.lastPathComponent
        )
    }

    public func status(analysisNoteID: UUID) -> ResearchSourceAccessStatus {
        do {
            return .available(try resolve(analysisNoteID: analysisNoteID).reference)
        } catch let error as ResearchSourceAccessStoreError {
            let reference = try? reference(analysisNoteID: analysisNoteID)
            return .repairRequired(error.failure.code, reference: reference)
        } catch {
            return .repairRequired(.corruptBinding)
        }
    }

    public func reference(analysisNoteID: UUID) throws -> ResearchSourceReference? {
        try binding(analysisNoteID: analysisNoteID)?.reference
    }

    /// Verifies only the private store envelope. It does not resolve or read
    /// any source, and is used before an irreversible note deletion begins.
    public func validateStoreHealth() throws {
        _ = try load()
    }

    public func resolve(
        analysisNoteID: UUID
    ) throws -> ResolvedResearchSourceAccess {
        guard let binding = try binding(analysisNoteID: analysisNoteID) else {
            throw Self.failure(.missingBinding)
        }
        let resolution: ResearchSourceBookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(binding.bookmarkData)
        } catch {
            throw Self.failure(.bookmarkUnavailable)
        }
        guard !resolution.isStale else { throw Self.failure(.bookmarkStale) }
        guard bookmarkAccess.start(resolution.url) else {
            throw Self.failure(.bookmarkUnavailable)
        }
        defer { bookmarkAccess.stop(resolution.url) }
        let canonical = resolution.url.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == binding.canonicalPath else {
            throw Self.failure(.bookmarkUnavailable)
        }

        let inspected = try Self.inspectFile(at: resolution.url)
        guard inspected.url.path == binding.canonicalPath else {
            throw Self.failure(.bookmarkUnavailable)
        }
        guard inspected.fingerprint == binding.reference.fingerprint else {
            throw Self.failure(.sourceChanged)
        }
        return ResolvedResearchSourceAccess(
            reference: binding.reference,
            fileURL: inspected.url
        )
    }

    public func remove(analysisNoteID: UUID) throws {
        var payload = try load()
        let originalCount = payload.bindings.count
        payload.bindings.removeAll { $0.analysisNoteID == analysisNoteID }
        guard payload.bindings.count != originalCount else { return }
        try persist(payload)
    }

    private func bind(
        payload originalPayload: Payload,
        analysisNoteID: UUID,
        selected: InspectedFile,
        identity: ResearchSourceIdentity,
        displayName: String
    ) throws -> ResearchSourceReference {
        let bookmarkData: Data
        do {
            bookmarkData = try bookmarkAccess.create(selected.url)
        } catch {
            throw Self.failure(.bookmarkUnavailable)
        }
        let resolution: ResearchSourceBookmarkResolution
        do {
            resolution = try bookmarkAccess.resolve(bookmarkData)
        } catch {
            throw Self.failure(.bookmarkUnavailable)
        }
        guard !resolution.isStale else { throw Self.failure(.bookmarkStale) }
        guard bookmarkAccess.start(resolution.url) else {
            throw Self.failure(.bookmarkUnavailable)
        }
        defer { bookmarkAccess.stop(resolution.url) }
        let resolvedCanonical = resolution.url.resolvingSymlinksInPath()
            .standardizedFileURL
        guard resolvedCanonical.path == selected.url.path else {
            throw Self.failure(.bookmarkUnavailable)
        }
        let confirmed = try Self.inspectFile(at: resolution.url)
        guard confirmed.url.path == selected.url.path else {
            throw Self.failure(.bookmarkUnavailable)
        }
        guard confirmed.fingerprint == selected.fingerprint else {
            throw Self.failure(.sourceChanged)
        }

        let reference = try ResearchSourceReference(
            identity: identity,
            displayName: displayName,
            fingerprint: confirmed.fingerprint
        )
        let binding = Binding(
            analysisNoteID: analysisNoteID,
            reference: reference,
            canonicalPath: confirmed.url.path,
            bookmarkData: bookmarkData
        )
        var payload = originalPayload
        payload.bindings.removeAll { $0.analysisNoteID == analysisNoteID }
        payload.bindings.append(binding)
        payload.bindings.sort {
            $0.analysisNoteID.uuidString < $1.analysisNoteID.uuidString
        }
        try persist(payload)
        return reference
    }

    private func binding(analysisNoteID: UUID) throws -> Binding? {
        try load().bindings.first { $0.analysisNoteID == analysisNoteID }
    }

    private func load() throws -> Payload {
        let directoryDescriptor = try openStorageDirectory(createIfMissing: false)
        guard directoryDescriptor >= 0 else {
            return Payload(
                schemaVersion: Self.currentSchemaVersion,
                triptychID: triptychID,
                bindings: []
            )
        }
        defer { close(directoryDescriptor) }
        do {
            guard let data = try readBindingData(from: directoryDescriptor) else {
                return Payload(
                    schemaVersion: Self.currentSchemaVersion,
                    triptychID: triptychID,
                    bindings: []
                )
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.schemaVersion == Self.currentSchemaVersion,
                  payload.triptychID == triptychID,
                  Set(payload.bindings.map(\.analysisNoteID)).count
                    == payload.bindings.count else {
                throw Self.failure(.corruptBinding)
            }
            return payload
        } catch let error as ResearchSourceAccessStoreError {
            throw error
        } catch {
            throw Self.failure(.corruptBinding)
        }
    }

    /// A valid, explicit source selection may recover an unreadable binding
    /// store. A private regular file is atomically replaced only after the new
    /// payload is durable; unsafe directory entries are moved aside without
    /// being followed. No app-owned bookmark backup is retained indefinitely.
    private func loadForBinding() throws -> Payload {
        do {
            return try load()
        } catch let error as ResearchSourceAccessStoreError
            where error.failure.code == .corruptBinding {
            try repairPrivateModes()
            if let repaired = try? load() {
                return repaired
            }
            if try !bindingLeafCanBeAtomicallyReplaced() {
                try quarantineCorruptBindingFile()
            }
            return Payload(
                schemaVersion: Self.currentSchemaVersion,
                triptychID: triptychID,
                bindings: []
            )
        }
    }

    private func bindingLeafCanBeAtomicallyReplaced() throws -> Bool {
        let directoryDescriptor = try openStorageDirectory(createIfMissing: false)
        guard directoryDescriptor >= 0 else { return true }
        defer { close(directoryDescriptor) }
        var status = stat()
        let result = Self.bindingFileName.withCString { name in
            fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0, errno == ENOENT { return true }
        guard result == 0 else { throw Self.failure(.corruptBinding) }
        return (status.st_mode & S_IFMT) == S_IFREG
            && status.st_nlink == 1
            && status.st_mode & 0o777 == Self.fileMode
    }

    private func repairPrivateModes() throws {
        let directoryDescriptor = try openStorageDirectory(
            createIfMissing: false,
            repairFinalMode: true
        )
        guard directoryDescriptor >= 0 else { return }
        defer { close(directoryDescriptor) }
        let descriptor = Self.bindingFileName.withCString { name in
            openat(
                directoryDescriptor,
                name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            // Unsafe leaves such as symlinks are handled by quarantine after
            // the retried strict load still fails.
            return
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw Self.failure(.corruptBinding)
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            // A non-regular leaf is unsafe to read but safe to move aside by
            // exact directory entry in quarantineCorruptBindingFile().
            return
        }
        guard status.st_nlink == 1 else { return }
        guard fchmod(descriptor, Self.fileMode) == 0,
              fsync(descriptor) == 0 else {
            throw Self.failure(.corruptBinding)
        }
    }

    private func persist(_ payload: Payload) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            guard data.count <= Self.maximumStoreByteCount else {
                throw Self.failure(.corruptBinding)
            }
            let directoryDescriptor = try openStorageDirectory(createIfMissing: true)
            guard directoryDescriptor >= 0 else {
                throw Self.failure(.corruptBinding)
            }
            defer { close(directoryDescriptor) }
            try rejectUnsafeExistingBinding(in: directoryDescriptor)
            let temporaryName = ".source-bindings-\(UUID().uuidString).tmp"
            let temporaryDescriptor = temporaryName.withCString { name in
                openat(
                    directoryDescriptor,
                    name,
                    O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                    Self.fileMode
                )
            }
            guard temporaryDescriptor >= 0 else {
                throw Self.failure(.corruptBinding)
            }
            var shouldRemoveTemporary = true
            defer {
                close(temporaryDescriptor)
                if shouldRemoveTemporary {
                    _ = temporaryName.withCString { name in
                        unlinkat(directoryDescriptor, name, 0)
                    }
                }
            }
            try Self.write(data, to: temporaryDescriptor)
            guard fchmod(temporaryDescriptor, Self.fileMode) == 0,
                  fsync(temporaryDescriptor) == 0 else {
                throw Self.failure(.corruptBinding)
            }
            let renamed = temporaryName.withCString { temporary in
                Self.bindingFileName.withCString { binding in
                    renameat(directoryDescriptor, temporary, directoryDescriptor, binding)
                }
            }
            guard renamed == 0 else { throw Self.failure(.corruptBinding) }
            shouldRemoveTemporary = false
            guard fsync(directoryDescriptor) == 0,
                  let readback = try readBindingData(from: directoryDescriptor) else {
                throw Self.failure(.corruptBinding)
            }
            guard readback == data,
                  try JSONDecoder().decode(Payload.self, from: readback) == payload else {
                throw Self.failure(.corruptBinding)
            }
        } catch let error as ResearchSourceAccessStoreError {
            throw error
        } catch {
            throw Self.failure(.corruptBinding)
        }
    }

    /// Returns -1 only when a missing directory is a valid empty-store state.
    private func openStorageDirectory(
        createIfMissing: Bool,
        repairFinalMode: Bool = false
    ) throws -> Int32 {
        var currentDescriptor = trustedRootURL.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard currentDescriptor >= 0 else {
            throw Self.failure(.corruptBinding)
        }
        for (index, component) in storageComponents.enumerated() {
            let isFinal = index == storageComponents.index(before: storageComponents.endIndex)
            var status = stat()
            var result = component.withCString { name in
                fstatat(currentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW)
            }
            if result != 0, errno == ENOENT {
                guard createIfMissing else {
                    close(currentDescriptor)
                    return -1
                }
                result = component.withCString { name in
                    mkdirat(currentDescriptor, name, Self.directoryMode)
                }
                guard result == 0 else {
                    close(currentDescriptor)
                    throw Self.failure(.corruptBinding)
                }
            } else {
                guard result == 0,
                      (status.st_mode & S_IFMT) == S_IFDIR else {
                    close(currentDescriptor)
                    throw Self.failure(.corruptBinding)
                }
            }
            let nextDescriptor = component.withCString { name in
                openat(
                    currentDescriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard nextDescriptor >= 0 else {
                close(currentDescriptor)
                throw Self.failure(.corruptBinding)
            }
            close(currentDescriptor)
            currentDescriptor = nextDescriptor
            var openedStatus = stat()
            guard fstat(currentDescriptor, &openedStatus) == 0,
                  (openedStatus.st_mode & S_IFMT) == S_IFDIR else {
                close(currentDescriptor)
                throw Self.failure(.corruptBinding)
            }
            if isFinal, openedStatus.st_mode & 0o777 != Self.directoryMode {
                guard repairFinalMode,
                      fchmod(currentDescriptor, Self.directoryMode) == 0,
                      fsync(currentDescriptor) == 0 else {
                    close(currentDescriptor)
                    throw Self.failure(.corruptBinding)
                }
            }
        }
        return currentDescriptor
    }

    private func readBindingData(from directoryDescriptor: Int32) throws -> Data? {
        let descriptor = Self.bindingFileName.withCString { name in
            openat(
                directoryDescriptor,
                name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        if descriptor < 0, errno == ENOENT { return nil }
        guard descriptor >= 0 else { throw Self.failure(.corruptBinding) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_mode & 0o777 == Self.fileMode,
              before.st_size >= 0,
              before.st_size <= Self.maximumStoreByteCount else {
            throw Self.failure(.corruptBinding)
        }
        let expectedByteCount = Int(before.st_size)
        var data = Data()
        data.reserveCapacity(expectedByteCount)
        while data.count < expectedByteCount {
            let requested = min(
                Self.readChunkSize,
                expectedByteCount - data.count
            )
            guard let chunk = try handle.read(upToCount: requested),
                  !chunk.isEmpty else {
                throw Self.failure(.corruptBinding)
            }
            data.append(chunk)
        }
        let overflow = try handle.read(upToCount: 1)
        var after = stat()
        guard overflow?.isEmpty != false,
              data.count == expectedByteCount,
              fstat(descriptor, &after) == 0,
              Self.sameFileState(before, after) else {
            throw Self.failure(.corruptBinding)
        }
        return data
    }

    private func rejectUnsafeExistingBinding(in directoryDescriptor: Int32) throws {
        var status = stat()
        let result = Self.bindingFileName.withCString { name in
            fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0, errno == ENOENT { return }
        guard result == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1,
              status.st_mode & 0o777 == Self.fileMode else {
            throw Self.failure(.corruptBinding)
        }
    }

    private func quarantineCorruptBindingFile() throws {
        let directoryDescriptor = try openStorageDirectory(
            createIfMissing: false,
            repairFinalMode: true
        )
        guard directoryDescriptor >= 0 else { return }
        defer { close(directoryDescriptor) }
        var status = stat()
        let exists = Self.bindingFileName.withCString { name in
            fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW)
        }
        if exists != 0, errno == ENOENT { return }
        guard exists == 0 else { throw Self.failure(.corruptBinding) }
        let quarantineName = "source-bindings-v1.corrupt-\(UUID().uuidString)"
        let result = Self.bindingFileName.withCString { binding in
            quarantineName.withCString { quarantine in
                renameat(directoryDescriptor, binding, directoryDescriptor, quarantine)
            }
        }
        guard result == 0, fsync(directoryDescriptor) == 0 else {
            throw Self.failure(.corruptBinding)
        }
    }

    private nonisolated static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(descriptor, pointer, remaining)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw failure(.corruptBinding) }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }

    private nonisolated static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\0")
    }

    private nonisolated static func inspectFile(at url: URL) throws -> InspectedFile {
        guard url.isFileURL else { throw failure(.sourceNotRegular) }
        let standardized = url.standardizedFileURL
        let canonical = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.path == canonical.path else {
            throw failure(.sourceIsSymbolicLink)
        }

        var pathStatus = stat()
        let lstatResult = standardized.path.withCString { lstat($0, &pathStatus) }
        guard lstatResult == 0 else {
            throw failure(errno == ENOENT ? .sourceMissing : .sourceUnreadable)
        }
        guard (pathStatus.st_mode & S_IFMT) != S_IFLNK else {
            throw failure(.sourceIsSymbolicLink)
        }
        let resourceValues: URLResourceValues
        do {
            resourceValues = try standardized.resourceValues(forKeys: [
                .isAliasFileKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
        } catch {
            throw failure(.sourceUnreadable)
        }
        guard resourceValues.isAliasFile != true,
              resourceValues.isSymbolicLink != true else {
            throw failure(.sourceIsSymbolicLink)
        }
        guard resourceValues.isRegularFile == true else {
            throw failure(.sourceNotRegular)
        }

        let descriptor = standardized.path.withCString {
            open(
                $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW_ANY | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            if errno == ELOOP { throw failure(.sourceIsSymbolicLink) }
            if errno == ENOENT { throw failure(.sourceMissing) }
            throw failure(.sourceUnreadable)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var openedStatus = stat()
        guard fstat(descriptor, &openedStatus) == 0 else {
            throw failure(.sourceUnreadable)
        }
        guard (openedStatus.st_mode & S_IFMT) == S_IFREG else {
            throw failure(.sourceNotRegular)
        }
        guard openedStatus.st_size >= 0,
              UInt64(openedStatus.st_size) <= UInt64(Int.max) else {
            throw failure(.sourceUnreadable)
        }
        let expectedByteCount = Int(openedStatus.st_size)
        var hasher = SHA256()
        var byteCount = 0
        do {
            while byteCount < expectedByteCount {
                let requested = min(
                    Self.readChunkSize,
                    expectedByteCount - byteCount
                )
                guard let data = try handle.read(upToCount: requested),
                      !data.isEmpty else {
                    throw failure(.sourceChanged)
                }
                hasher.update(data: data)
                byteCount += data.count
            }
            let overflow = try handle.read(upToCount: 1)
            guard overflow?.isEmpty != false else {
                throw failure(.sourceChanged)
            }
        } catch {
            if let error = error as? ResearchSourceAccessStoreError {
                throw error
            }
            throw failure(.sourceUnreadable)
        }
        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0,
              sameFileState(openedStatus, finalStatus),
              finalStatus.st_size == openedStatus.st_size,
              byteCount == expectedByteCount else {
            throw failure(.sourceChanged)
        }
        var finalPathStatus = stat()
        let finalPathResult = standardized.path.withCString {
            lstat($0, &finalPathStatus)
        }
        guard finalPathResult == 0,
              (finalPathStatus.st_mode & S_IFMT) == S_IFREG,
              finalPathStatus.st_dev == finalStatus.st_dev,
              finalPathStatus.st_ino == finalStatus.st_ino else {
            throw failure(.sourceChanged)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return InspectedFile(
            url: canonical,
            fingerprint: DocumentFingerprint(sha256: digest, byteCount: byteCount)
        )
    }

    private nonisolated static func failure(
        _ code: ResearchSourceAccessFailureCode
    ) -> ResearchSourceAccessStoreError {
        .failure(ResearchSourceAccessFailure(code: code))
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
