import Darwin
import Foundation
import ScholiumContracts

/// The descriptor-authorized state of one vault-relative directory entry.
/// Only `ENOENT` is absence; every other lookup failure remains explicit.
enum FilePresence: Equatable, Sendable {
    case present
    case absent
    case inaccessible(Int32)
}

/// Opens one vault root for each top-level operation and resolves every path
/// component relative to that retained descriptor. Path strings are candidates
/// only; the opened descriptors are the final filesystem identity authority.
final class VaultDescriptorAccess {
    struct FileIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
        }
    }

    private let rootURL: URL
    private let authorizedRootIdentity: FileIdentity
    private(set) var rootAuthorityIsInvalid = false

    init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        let descriptor = try Self.openDirectory(rootURL: self.rootURL)
        defer { close(descriptor) }
        authorizedRootIdentity = try Self.directoryIdentity(descriptor: descriptor)
    }

    /// Proves that the registered path still names the exact directory object
    /// authorized when this access boundary was created.
    func verifyRootIdentity() throws {
        let descriptor = try openAuthorizedRoot()
        close(descriptor)
    }

    func read(_ path: MarkdownRelativePath) throws -> Data {
        do {
            return try read(
                rawValue: path.rawValue,
                components: path.components.map(String.init),
                maximumByteCount: VaultSourceReadLimits.maximumNoteByteCount
            )
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            throw VaultRepositoryError.sourceTooLarge(
                relativePath: path.rawValue,
                maximumByteCount: VaultSourceReadLimits.maximumNoteByteCount
            )
        }
    }

    func read(_ path: AttachmentRelativePath, maximumByteCount: Int) throws -> Data {
        try read(
            rawValue: path.rawValue,
            components: path.components.map(String.init),
            maximumByteCount: maximumByteCount
        )
    }

    private func read(
        rawValue: String, components: [String], maximumByteCount: Int
    ) throws -> Data {
        try withOpenRegularFile(rawValue: rawValue, components: components) {
            descriptor, parentDescriptor, name, initialStatus in
            let data = try Self.readAll(from: descriptor, maximumByteCount: maximumByteCount)
            var finalStatus = stat()
            guard fstat(descriptor, &finalStatus) == 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            let initialIdentity = FileIdentity(initialStatus)
            guard FileIdentity(finalStatus) == initialIdentity,
                finalStatus.st_size == initialStatus.st_size,
                finalStatus.st_mtimespec.tv_sec == initialStatus.st_mtimespec.tv_sec,
                finalStatus.st_mtimespec.tv_nsec == initialStatus.st_mtimespec.tv_nsec,
                finalStatus.st_ctimespec.tv_sec == initialStatus.st_ctimespec.tv_sec,
                finalStatus.st_ctimespec.tv_nsec == initialStatus.st_ctimespec.tv_nsec,
                Int(finalStatus.st_size) == data.count
            else {
                throw VaultRepositoryError.commitUncertain(
                    "The source changed while its exact bytes were being read."
                )
            }
            let currentIdentity: FileIdentity
            do {
                currentIdentity = try Self.identity(
                    name: name,
                    parentDescriptor: parentDescriptor
                )
            } catch let error as POSIXError where error.code == .ENOENT {
                throw VaultRepositoryError.fileDoesNotExist(rawValue)
            }
            guard currentIdentity == initialIdentity else {
                throw VaultRepositoryError.commitUncertain(
                    "The source path changed identity while its exact bytes were being read."
                )
            }
            let expectedParent = try Self.identity(descriptor: parentDescriptor)
            try withParentDescriptor(rawValue: rawValue, components: components) { observed, _ in
                guard try Self.identity(descriptor: observed) == expectedParent else {
                    throw VaultRepositoryError.commitUncertain(
                        "The authorized parent directory changed while source was being read."
                    )
                }
            }
            return data
        }
    }

    func presence(_ path: MarkdownRelativePath) throws -> FilePresence {
        let components = path.components.map(String.init)
        guard let name = components.last else {
            throw VaultRepositoryError.invalidRelativePath(path.rawValue)
        }
        let rootDescriptor: Int32
        do {
            rootDescriptor = try openAuthorizedRoot()
        } catch let error as POSIXError {
            return .inaccessible(error.code.rawValue)
        }
        defer { close(rootDescriptor) }

        var currentDescriptor = rootDescriptor
        var ownedDescriptor: Int32?
        defer {
            if let ownedDescriptor { close(ownedDescriptor) }
        }
        for component in components.dropLast() {
            let nextDescriptor = openat(
                currentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard nextDescriptor >= 0 else {
                return errno == ENOENT ? .absent : .inaccessible(errno)
            }
            if let ownedDescriptor { close(ownedDescriptor) }
            ownedDescriptor = nextDescriptor
            currentDescriptor = nextDescriptor
        }
        return Self.presence(name: name, parentDescriptor: currentDescriptor)
    }

    func withOpenRegularFile<T>(
        _ path: MarkdownRelativePath,
        _ body: (Int32, Int32, String, stat) throws -> T
    ) throws -> T {
        try withOpenRegularFile(
            rawValue: path.rawValue, components: path.components.map(String.init), body
        )
    }

    private func withOpenRegularFile<T>(
        rawValue: String, components: [String],
        _ body: (Int32, Int32, String, stat) throws -> T
    ) throws -> T {
        try withParentDescriptor(rawValue: rawValue, components: components) { parentDescriptor, name in
            let descriptor = openat(
                parentDescriptor,
                name,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw Self.openError(code: errno, path: rawValue)
            }
            defer { close(descriptor) }

            var status = stat()
            guard fstat(descriptor, &status) == 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            guard (status.st_mode & S_IFMT) == S_IFREG else {
                throw VaultRepositoryError.notRegularFile(rawValue)
            }
            return try body(descriptor, parentDescriptor, name, status)
        }
    }

    func withParentDescriptor<T>(
        _ path: MarkdownRelativePath,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        try withParentDescriptor(
            rawValue: path.rawValue,
            components: path.components.map(String.init),
            body
        )
    }

    func withParentDescriptor<T>(
        _ path: VaultRelativeFolderPath,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        try withParentDescriptor(
            rawValue: path.rawValue,
            components: path.components.map(String.init),
            body
        )
    }

    private func withParentDescriptor<T>(
        rawValue: String,
        components: [String],
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        guard let name = components.last else {
            throw VaultRepositoryError.invalidRelativePath(rawValue)
        }
        let rootDescriptor = try openAuthorizedRoot()
        defer { close(rootDescriptor) }

        var currentDescriptor = rootDescriptor
        var ownedDescriptor: Int32?
        defer {
            if let ownedDescriptor { close(ownedDescriptor) }
        }
        for component in components.dropLast() {
            let nextDescriptor = openat(
                currentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            guard nextDescriptor >= 0 else {
                throw Self.openError(code: errno, path: rawValue)
            }
            if let ownedDescriptor { close(ownedDescriptor) }
            ownedDescriptor = nextDescriptor
            currentDescriptor = nextDescriptor
        }
        return try body(currentDescriptor, name)
    }

    static func readNoteBytes(from descriptor: Int32, relativePath: String) throws -> Data {
        do {
            return try readAll(
                from: descriptor, maximumByteCount: VaultSourceReadLimits.maximumNoteByteCount
            )
        } catch let error as CocoaError where error.code == .fileReadTooLarge {
            throw VaultRepositoryError.sourceTooLarge(
                relativePath: relativePath,
                maximumByteCount: VaultSourceReadLimits.maximumNoteByteCount
            )
        }
    }

    static func readAll(from descriptor: Int32, maximumByteCount: Int) throws -> Data {
        try readAll(from: descriptor, maximumByteCount: maximumByteCount, afterChunkForTesting: nil)
    }

    /// Deterministic growth seam. Production callers use the overload above.
    static func readAll(
        from descriptor: Int32, maximumByteCount: Int,
        afterChunkForTesting: ((Int) throws -> Void)?
    ) throws -> Data {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw POSIXError(posixCode(errno)) }
        guard maximumByteCount >= 0, status.st_size >= 0, status.st_size <= maximumByteCount else {
            throw CocoaError(.fileReadTooLarge)
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                // Read at most one byte beyond the remaining allowance so
                // growth cannot cause an unbounded allocation before refusal.
                let remaining = maximumByteCount - data.count
                let readCount = remaining < bytes.count ? remaining + 1 : bytes.count
                return Darwin.read(descriptor, bytes.baseAddress, readCount)
            }
            if count == 0 { return data }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw POSIXError(posixCode(errno))
            }
            if count > maximumByteCount - data.count {
                throw CocoaError(.fileReadTooLarge)
            }
            data.append(buffer, count: count)
            try afterChunkForTesting?(data.count)
        }
    }

    static func presence(name: String, parentDescriptor: Int32) -> FilePresence {
        var status = stat()
        if fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 {
            return .present
        }
        let code = errno
        return code == ENOENT ? .absent : .inaccessible(code)
    }

    static func identity(
        name: String,
        parentDescriptor: Int32
    ) throws -> FileIdentity {
        var status = stat()
        guard fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw POSIXError(posixCode(errno))
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            throw VaultRepositoryError.notRegularFile(name)
        }
        return FileIdentity(status)
    }

    static func identity(descriptor: Int32) throws -> FileIdentity {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw POSIXError(posixCode(errno))
        }
        return FileIdentity(status)
    }

    private func openAuthorizedRoot() throws -> Int32 {
        guard !rootAuthorityIsInvalid else {
            throw VaultRepositoryError.rootUnavailable(rootURL.path)
        }
        let descriptor: Int32
        do {
            descriptor = try Self.openDirectory(rootURL: rootURL)
        } catch {
            rootAuthorityIsInvalid = true
            throw error
        }
        do {
            guard
                try Self.directoryIdentity(descriptor: descriptor)
                    == authorizedRootIdentity
            else {
                rootAuthorityIsInvalid = true
                throw VaultRepositoryError.rootUnavailable(rootURL.path)
            }
            return descriptor
        } catch {
            rootAuthorityIsInvalid = true
            close(descriptor)
            throw error
        }
    }

    private static func openDirectory(rootURL: URL) throws -> Int32 {
        let descriptor = open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw VaultRepositoryError.rootUnavailable(rootURL.path)
        }
        return descriptor
    }

    private static func directoryIdentity(descriptor: Int32) throws -> FileIdentity {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
            (status.st_mode & S_IFMT) == S_IFDIR
        else {
            throw VaultRepositoryError.rootUnavailable("authorized root")
        }
        return FileIdentity(status)
    }

    /// Rewalks the current root-relative spelling and proves it still reaches
    /// the directory descriptor retained by the caller. This detects a parent
    /// rename or symlink substitution before a commit is reported successful.
    func verifyCurrentParent(
        _ path: MarkdownRelativePath,
        retainedDescriptor: Int32
    ) throws {
        let expected = try Self.identity(descriptor: retainedDescriptor)
        try withParentDescriptor(path) { observedDescriptor, _ in
            guard try Self.identity(descriptor: observedDescriptor) == expected else {
                throw VaultRepositoryError.commitUncertain(
                    "The authorized parent directory changed before commit."
                )
            }
        }
    }

    func verifyCurrentParent(
        _ path: VaultRelativeFolderPath,
        retainedDescriptor: Int32
    ) throws {
        let expected = try Self.identity(descriptor: retainedDescriptor)
        try withParentDescriptor(path) { observedDescriptor, _ in
            guard try Self.identity(descriptor: observedDescriptor) == expected else {
                throw VaultRepositoryError.commitUncertain(
                    "The authorized parent directory changed before commit."
                )
            }
        }
    }

    private static func openError(code: Int32, path: String) -> any Error {
        switch code {
        case ENOENT:
            VaultRepositoryError.fileDoesNotExist(path)
        case ELOOP:
            VaultRepositoryError.notRegularFile(path)
        default:
            POSIXError(posixCode(code))
        }
    }

    private static func posixCode(_ code: Int32) -> POSIXErrorCode {
        POSIXErrorCode(rawValue: code) ?? .EIO
    }
}

/// Read-only configuration access reuses the vault's descriptor-relative,
/// no-follow source boundary, including parent and leaf identity rechecks.
package enum VaultConfigurationReader {
    package static func readObsidianFile(at vaultRootURL: URL, fileName: String) throws -> Data {
        let path = try AttachmentRelativePath(".obsidian/\(fileName)")
        let access = try VaultDescriptorAccess(rootURL: vaultRootURL)
        return try access.read(
            path, maximumByteCount: VaultSourceReadLimits.maximumObsidianConfigurationByteCount
        )
    }
}
