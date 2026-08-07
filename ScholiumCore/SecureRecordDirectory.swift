import Darwin
import Foundation

/// Shared descriptor-relative storage for bounded machine-local JSON state.
///
/// This primitive owns containment, no-follow access, byte limits, atomic
/// replacement, readback, and staging recovery. It does not interpret any
/// Record, recovery-policy, or execution semantics.
final class AdvisoryFileLock: @unchecked Sendable {
    private let descriptor: Int32

    init(directory: SecureRecordDirectory, fileName: String) throws {
        descriptor = try directory.openLockFile(fileName)
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink == 1 else {
            Darwin.close(descriptor)
            throw SecureRecordDirectoryError.unsafe(
                "The coordination lock is linked or is not a regular file."
            )
        }
        if status.st_mode & 0o777 != 0o600 {
            guard fchmod(descriptor, 0o600) == 0 else {
                Darwin.close(descriptor)
                throw SecureRecordDirectoryError.unsafe(
                    "Cannot restrict the coordination lock."
                )
            }
        }
    }

    deinit { Darwin.close(descriptor) }

    func withSharedLock<T>(_ operation: () throws -> T) throws -> T {
        try withLock(LOCK_SH, operation)
    }

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try withLock(LOCK_EX, operation)
    }

    private func withLock<T>(
        _ kind: Int32,
        _ operation: () throws -> T
    ) throws -> T {
        while flock(descriptor, kind) != 0 {
            if errno == EINTR { continue }
            throw SecureRecordDirectoryError.unsafe(
                "Cannot acquire the coordination lock (\(Self.message()))."
            )
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func message() -> String {
        String(cString: strerror(errno))
    }
}

enum SecureRecordDirectoryError: LocalizedError {
    case unsafe(String)
    case notFound(String)
    case alreadyExists(String)
    case replacementNotCommitted(String)
    case replacementCommitUncertain(String)

    var errorDescription: String? {
        switch self {
        case .unsafe(let reason): reason
        case .notFound(let file): "\(file) was not found."
        case .alreadyExists(let file): "\(file) already exists."
        case .replacementNotCommitted(let reason): reason
        case .replacementCommitUncertain(let reason): reason
        }
    }
}

/// Minimal descriptor-relative file primitive shared by machine-local stores.
/// It does not interpret caller semantics.
struct SecureRecordDirectory: Sendable {
    let trustedRootURL: URL
    let components: [String]
    let directoryMode: mode_t
    let fileMode: mode_t
    let maximumByteCount: Int
    /// Internal deterministic fault seam used to prove behavior after staging
    /// durability but before rename. Production construction always leaves it
    /// nil.
    let preCommitFault: (@Sendable (String) throws -> Void)?
    /// Internal deterministic fault seam used to prove behavior after rename
    /// but before directory durability/readback. Production construction
    /// always leaves it nil.
    let postCommitFault: (@Sendable (String) throws -> Void)?

    init(
        trustedRootURL: URL,
        components: [String],
        directoryMode: mode_t,
        fileMode: mode_t,
        maximumByteCount: Int,
        preCommitFault: (@Sendable (String) throws -> Void)? = nil,
        postCommitFault: (@Sendable (String) throws -> Void)? = nil
    ) {
        precondition(!components.isEmpty)
        precondition(components.allSatisfy(Self.isSafeComponent))
        self.trustedRootURL = trustedRootURL.standardizedFileURL
        self.components = components
        self.directoryMode = directoryMode
        self.fileMode = fileMode
        self.maximumByteCount = maximumByteCount
        self.preCommitFault = preCommitFault
        self.postCommitFault = postCommitFault
    }

    func ensureDirectories(_ children: [String]) throws {
        let root = try openStorageDirectory(createIfMissing: true)
        defer { Darwin.close(root) }
        for child in children {
            guard Self.isSafeComponent(child) else {
                throw SecureRecordDirectoryError.unsafe("Invalid storage directory name.")
            }
            let descriptor = try openChildDirectory(
                parent: root,
                name: child,
                createIfMissing: true
            )
            Darwin.close(descriptor)
        }
    }

    func createExclusive(
        _ data: Data,
        directory: String?,
        fileName: String
    ) throws -> Data {
        try write(data, directory: directory, fileName: fileName, exclusive: true)
    }

    func replace(
        _ data: Data,
        directory: String?,
        fileName: String
    ) throws -> Data {
        do {
            return try write(
                data,
                directory: directory,
                fileName: fileName,
                exclusive: false
            )
        } catch let error as SecureRecordDirectoryError {
            if case .replacementCommitUncertain = error { throw error }
            throw SecureRecordDirectoryError.replacementNotCommitted(
                error.localizedDescription
            )
        } catch {
            throw SecureRecordDirectoryError.replacementNotCommitted(
                error.localizedDescription
            )
        }
    }

    func read(directory: String?, fileName: String) throws -> Data {
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        return try read(parent: parent, fileName: fileName)
    }

    func readIfPresent(directory: String?, fileName: String) throws -> Data? {
        do {
            return try read(directory: directory, fileName: fileName)
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    func synchronize(directories: [String]) throws {
        for directory in directories {
            let descriptor = try openTargetDirectory(
                directory,
                createIfMissing: false
            )
            defer { Darwin.close(descriptor) }
            guard fsync(descriptor) == 0 else {
                throw unsafe("flush \(directory) storage directory")
            }
        }
    }

    func synchronize(directory: String?) throws {
        let descriptor = try openTargetDirectory(
            directory,
            createIfMissing: false
        )
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw unsafe("flush storage directory")
        }
    }

    func fileNames(in directory: String?) throws -> [String] {
        try fileNames(in: directory, includingStaging: false)
    }

    func removeAbandonedStagingFiles(in directories: [String?]) throws {
        for directory in directories {
            let parent = try openTargetDirectory(directory, createIfMissing: false)
            defer { Darwin.close(parent) }
            var removedAny = false
            for name in try fileNames(
                parent: parent,
                includingStaging: true
            ) where name.hasPrefix(".scholium-pending-") {
                let result = name.withCString { unlinkat(parent, $0, 0) }
                if result != 0, errno == ENOENT { continue }
                guard result == 0 else { throw unsafe("remove abandoned staging file") }
                removedAny = true
            }
            if removedAny, fsync(parent) != 0 {
                throw unsafe("flush staging recovery")
            }
        }
    }

    private func fileNames(
        in directory: String?,
        includingStaging: Bool
    ) throws -> [String] {
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        return try fileNames(parent: parent, includingStaging: includingStaging)
    }

    private func fileNames(
        parent: Int32,
        includingStaging: Bool
    ) throws -> [String] {
        let enumerationDescriptor = dup(parent)
        guard enumerationDescriptor >= 0 else {
            throw unsafe("duplicate storage directory")
        }
        guard let stream = fdopendir(enumerationDescriptor) else {
            Darwin.close(enumerationDescriptor)
            throw unsafe("enumerate storage directory")
        }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(MAXNAMLEN) + 1
                ) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            if !includingStaging, name.hasPrefix(".scholium-pending-") {
                continue
            }
            if !includingStaging, name.hasPrefix(".scholium-deleting-") {
                continue
            }
            names.append(name)
        }
        return names.sorted()
    }

    func removeIfPresent(directory: String?, fileName: String) throws {
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        let result = fileName.withCString { unlinkat(parent, $0, 0) }
        if result != 0, errno == ENOENT { return }
        guard result == 0, fsync(parent) == 0 else {
            throw unsafe("remove \(fileName)")
        }
    }

    func remove(directory: String?, fileName: String, expected: Data) throws {
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        let deletingName = ".scholium-deleting-\(fileName)"
        let renameResult = fileName.withCString { source in
            deletingName.withCString { destination in
                renameatx_np(
                    parent,
                    source,
                    parent,
                    destination,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        if renameResult != 0, errno == ENOENT {
            throw SecureRecordDirectoryError.notFound(fileName)
        }
        if renameResult != 0, errno == EEXIST {
            throw SecureRecordDirectoryError.unsafe(
                "An interrupted deletion already owns \(fileName)."
            )
        }
        guard renameResult == 0 else { throw unsafe("isolate \(fileName) for deletion") }

        do {
            let observed = try read(parent: parent, fileName: deletingName)
            guard observed == expected else {
                throw SecureRecordDirectoryError.replacementNotCommitted(
                    "Stored JSON \(fileName) changed before deletion."
                )
            }
            let unlinkResult = deletingName.withCString { unlinkat(parent, $0, 0) }
            guard unlinkResult == 0 else {
                throw SecureRecordDirectoryError.replacementCommitUncertain(
                    unsafe("delete isolated \(fileName)").localizedDescription
                )
            }
            do {
                try postCommitFault?(fileName)
            } catch {
                throw SecureRecordDirectoryError.replacementCommitUncertain(
                    error.localizedDescription
                )
            }
            guard fsync(parent) == 0 else {
                throw SecureRecordDirectoryError.replacementCommitUncertain(
                    unsafe("flush deleted storage directory").localizedDescription
                )
            }
        } catch let error as SecureRecordDirectoryError {
            var deletingStatus = stat()
            let stillExists = deletingName.withCString {
                fstatat(parent, $0, &deletingStatus, AT_SYMLINK_NOFOLLOW)
            } == 0
            guard stillExists else { throw error }
            let rollback = deletingName.withCString { source in
                fileName.withCString { destination in
                    renameatx_np(
                        parent,
                        source,
                        parent,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard rollback == 0, fsync(parent) == 0 else {
                throw SecureRecordDirectoryError.replacementCommitUncertain(
                    "The unverified stored JSON was preserved as \(deletingName)."
                )
            }
            throw error
        }
    }

    func recoverAbandonedDeletionFiles(in directory: String) throws {
        let parent = try openTargetDirectory(directory, createIfMissing: false)
        defer { Darwin.close(parent) }
        let prefix = ".scholium-deleting-"
        for deletingName in try fileNames(parent: parent, includingStaging: true)
            where deletingName.hasPrefix(prefix) {
            let fileName = String(deletingName.dropFirst(prefix.count))
            try validateFileName(fileName)
            let result = deletingName.withCString { source in
                fileName.withCString { destination in
                    renameatx_np(
                        parent,
                        source,
                        parent,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard result == 0 else {
                throw SecureRecordDirectoryError.unsafe(
                    "An interrupted deletion conflicts with \(fileName)."
                )
            }
            guard fsync(parent) == 0 else {
                throw unsafe("recover interrupted deletion of \(fileName)")
            }
        }
    }

    func openLockFile(_ fileName: String) throws -> Int32 {
        guard Self.isSafeComponent(fileName) else {
            throw SecureRecordDirectoryError.unsafe("Invalid coordination lock name.")
        }
        let parent = try openStorageDirectory(createIfMissing: true)
        defer { Darwin.close(parent) }
        let descriptor = fileName.withCString {
            openat(
                parent,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard descriptor >= 0 else { throw unsafe("open coordination lock") }
        return descriptor
    }

    private func write(
        _ data: Data,
        directory: String?,
        fileName: String,
        exclusive: Bool
    ) throws -> Data {
        guard data.count <= maximumByteCount else {
            throw SecureRecordDirectoryError.unsafe("Stored JSON exceeds its byte boundary.")
        }
        try validateFileName(fileName)
        let parent = try openTargetDirectory(directory, createIfMissing: true)
        defer { Darwin.close(parent) }

        var existing = stat()
        let existingResult = fileName.withCString {
            fstatat(parent, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if exclusive, existingResult == 0 {
            throw SecureRecordDirectoryError.alreadyExists(fileName)
        }
        if existingResult == 0 {
            guard (existing.st_mode & S_IFMT) == S_IFREG,
                  existing.st_nlink == 1 else {
                throw SecureRecordDirectoryError.unsafe(
                    "Destination \(fileName) is linked or is not a regular file."
                )
            }
        } else if errno != ENOENT {
            throw unsafe("inspect \(fileName)")
        }

        let temporaryName = ".scholium-pending-\(UUID().uuidString.lowercased())"
        let temporary = temporaryName.withCString {
            openat(
                parent,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard temporary >= 0 else { throw unsafe("create staging file") }
        var temporaryExists = true
        defer {
            Darwin.close(temporary)
            if temporaryExists {
                _ = temporaryName.withCString { unlinkat(parent, $0, 0) }
            }
        }
        try Self.writeAll(data, descriptor: temporary)
        guard fchmod(temporary, fileMode) == 0,
              fsync(temporary) == 0 else {
            throw unsafe("flush staging file")
        }
        try preCommitFault?(fileName)

        let result: Int32
        if exclusive {
            result = temporaryName.withCString { source in
                fileName.withCString { destination in
                    renameatx_np(
                        parent,
                        source,
                        parent,
                        destination,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
        } else {
            result = temporaryName.withCString { source in
                fileName.withCString { destination in
                    renameat(parent, source, parent, destination)
                }
            }
        }
        if result != 0, exclusive, errno == EEXIST {
            throw SecureRecordDirectoryError.alreadyExists(fileName)
        }
        guard result == 0 else { throw unsafe("commit \(fileName)") }
        temporaryExists = false
        do {
            try postCommitFault?(fileName)
        } catch {
            throw SecureRecordDirectoryError.replacementCommitUncertain(
                error.localizedDescription
            )
        }
        guard fsync(parent) == 0 else {
            throw SecureRecordDirectoryError.replacementCommitUncertain(
                unsafe("flush storage directory").localizedDescription
            )
        }
        let readback: Data
        do {
            readback = try read(parent: parent, fileName: fileName)
        } catch {
            throw SecureRecordDirectoryError.replacementCommitUncertain(
                error.localizedDescription
            )
        }
        guard readback == data else {
            throw SecureRecordDirectoryError.replacementCommitUncertain(
                "Committed stored JSON \(fileName) did not match readback."
            )
        }
        return readback
    }

    private func openTargetDirectory(
        _ directory: String?,
        createIfMissing: Bool
    ) throws -> Int32 {
        let root = try openStorageDirectory(createIfMissing: createIfMissing)
        guard let directory else { return root }
        guard Self.isSafeComponent(directory) else {
            Darwin.close(root)
            throw SecureRecordDirectoryError.unsafe("Invalid storage directory name.")
        }
        do {
            let child = try openChildDirectory(
                parent: root,
                name: directory,
                createIfMissing: createIfMissing
            )
            Darwin.close(root)
            return child
        } catch {
            Darwin.close(root)
            throw error
        }
    }

    private func openStorageDirectory(createIfMissing: Bool) throws -> Int32 {
        var current = trustedRootURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard current >= 0 else { throw unsafe("open trusted root") }
        do {
            for component in components {
                let next = try openChildDirectory(
                    parent: current,
                    name: component,
                    createIfMissing: createIfMissing
                )
                Darwin.close(current)
                current = next
            }
            var status = stat()
            guard fstat(current, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFDIR else {
                throw SecureRecordDirectoryError.unsafe(
                    "The storage root is not a directory."
                )
            }
            if status.st_mode & 0o777 != directoryMode {
                guard fchmod(current, directoryMode) == 0,
                      fsync(current) == 0 else {
                    throw unsafe("restrict storage root")
                }
            }
            return current
        } catch {
            Darwin.close(current)
            throw error
        }
    }

    private func openChildDirectory(
        parent: Int32,
        name: String,
        createIfMissing: Bool
    ) throws -> Int32 {
        var next = name.withCString {
            openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        if next < 0, errno == ENOENT, createIfMissing {
            let created = name.withCString { mkdirat(parent, $0, directoryMode) }
            guard created == 0 || errno == EEXIST else {
                throw unsafe("create directory \(name)")
            }
            next = name.withCString {
                openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
        }
        if next < 0, errno == ENOENT {
            throw SecureRecordDirectoryError.notFound(name)
        }
        guard next >= 0 else {
            throw SecureRecordDirectoryError.unsafe(
                "Directory \(name) is missing, linked, or unavailable."
            )
        }
        return next
    }

    private func read(parent: Int32, fileName: String) throws -> Data {
        let descriptor = fileName.withCString {
            openat(parent, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        if descriptor < 0, errno == ENOENT {
            throw SecureRecordDirectoryError.notFound(fileName)
        }
        guard descriptor >= 0 else { throw unsafe("open \(fileName)") }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size >= 0,
              before.st_size <= maximumByteCount else {
            throw SecureRecordDirectoryError.unsafe(
                "Stored JSON \(fileName) is linked, malformed, or too large."
            )
        }
        let expected = Int(before.st_size)
        var data = Data()
        data.reserveCapacity(expected)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < expected {
            let requested = min(buffer.count, expected - data.count)
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw unsafe("read \(fileName)") }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }
        var overflow: UInt8 = 0
        let overflowCount = Darwin.read(descriptor, &overflow, 1)
        var after = stat()
        guard overflowCount == 0,
              fstat(descriptor, &after) == 0,
              Self.sameFile(before, after) else {
            throw SecureRecordDirectoryError.unsafe(
                "Stored JSON \(fileName) changed while it was read."
            )
        }
        return data
    }

    private func validateFileName(_ fileName: String) throws {
        guard Self.isSafeComponent(fileName), fileName.hasSuffix(".json") else {
            throw SecureRecordDirectoryError.unsafe("Invalid stored JSON file name.")
        }
    }

    private static func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw SecureRecordDirectoryError.unsafe(
                        "The staging file accepted no bytes."
                    )
                }
                offset += count
            }
        }
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\0")
    }

    private func unsafe(_ operation: String) -> SecureRecordDirectoryError {
        .unsafe("\(operation) failed (\(String(cString: strerror(errno)))).")
    }
}
