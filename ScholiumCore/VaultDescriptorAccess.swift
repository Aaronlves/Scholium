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

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func read(_ path: MarkdownRelativePath) throws -> Data {
        try withOpenRegularFile(path) {
            descriptor, parentDescriptor, name, initialStatus in
            let data = try Self.readAll(from: descriptor)
            var finalStatus = stat()
            guard fstat(descriptor, &finalStatus) == 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            let initialIdentity = FileIdentity(initialStatus)
            guard FileIdentity(finalStatus) == initialIdentity,
                  Int(finalStatus.st_size) == data.count else {
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
                throw VaultRepositoryError.fileDoesNotExist(path.rawValue)
            }
            guard currentIdentity == initialIdentity else {
                throw VaultRepositoryError.commitUncertain(
                    "The source path changed identity while its exact bytes were being read."
                )
            }
            try verifyCurrentParent(path, retainedDescriptor: parentDescriptor)
            return data
        }
    }

    func presence(_ path: MarkdownRelativePath) throws -> FilePresence {
        let components = path.components.map(String.init)
        guard let name = components.last else {
            throw VaultRepositoryError.invalidRelativePath(path.rawValue)
        }
        let rootDescriptor = open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else { return .inaccessible(errno) }
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
        try withParentDescriptor(path) { parentDescriptor, name in
            let descriptor = openat(
                parentDescriptor,
                name,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw Self.openError(code: errno, path: path.rawValue)
            }
            defer { close(descriptor) }

            var status = stat()
            guard fstat(descriptor, &status) == 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            guard (status.st_mode & S_IFMT) == S_IFREG else {
                throw VaultRepositoryError.notRegularFile(path.rawValue)
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
        let rootDescriptor = open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw Self.openError(code: errno, path: rawValue)
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
                throw Self.openError(code: errno, path: rawValue)
            }
            if let ownedDescriptor { close(ownedDescriptor) }
            ownedDescriptor = nextDescriptor
            currentDescriptor = nextDescriptor
        }
        return try body(currentDescriptor, name)
    }

    static func readAll(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count == 0 { return data }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                throw POSIXError(posixCode(errno))
            }
            data.append(buffer, count: count)
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
