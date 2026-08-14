import Darwin
import Foundation
import ScholiumContracts

enum VaultMutationPhase: Equatable, Sendable {
    case initialRead
    case staged
    case finalCheck
    case replacing
    case replaced
    case readback
    case completedReplacement
}

struct VaultMutationHooks: @unchecked Sendable {
    var didReach: ((VaultMutationPhase) throws -> Void)? = nil
    var presenceOverride: ((String) -> FilePresence?)? = nil

    static let none = VaultMutationHooks()
}

/// Coordinates short-lived filesystem commits while descriptor-relative,
/// no-follow checks retain the actual authorization boundary.
final class VaultMutationCoordinator {
    private let resolver: VaultPathResolver
    private let descriptorAccess: VaultDescriptorAccess
    private let hooks: VaultMutationHooks

    init(resolver: VaultPathResolver, hooks: VaultMutationHooks = .none) {
        self.resolver = resolver
        self.descriptorAccess = VaultDescriptorAccess(rootURL: resolver.canonicalRoot)
        self.hooks = hooks
    }

    func updateExisting(
        path: MarkdownRelativePath,
        expected: Data,
        candidate: Data
    ) throws {
        let targetURL = try resolver.unresolvedURL(for: path)
        var replacementCompleted = false
        try coordinateWriting(targetURL, options: .forReplacing) {
            try self.descriptorAccess.withOpenRegularFile(path) {
                originalFD, parentFD, name, originalStatus in
                let originalIdentity = VaultDescriptorAccess.FileIdentity(originalStatus)
                let initial = try self.readFile(descriptor: originalFD)
                try self.hooks.didReach?(.initialRead)
                guard initial == expected else {
                    throw VaultRepositoryError.conflict(
                        expected: DocumentFingerprint(data: expected),
                        current: DocumentFingerprint(data: initial)
                    )
                }

                let stagingName = ".scholium-replacement-\(UUID().uuidString.lowercased()).md"
                let stagingFD = try self.openNewFile(
                    candidate,
                    name: stagingName,
                    parentFD: parentFD
                )
                defer { close(stagingFD) }
                defer { _ = unlinkat(parentFD, stagingName, 0) }
                try self.hooks.didReach?(.staged)

                let rechecked = try self.readFile(at: name, parentFD: parentFD)
                let recheckedIdentity = try VaultDescriptorAccess.identity(
                    name: name,
                    parentDescriptor: parentFD
                )
                try self.hooks.didReach?(.finalCheck)
                guard rechecked == expected,
                      recheckedIdentity == originalIdentity else {
                    throw VaultRepositoryError.conflict(
                        expected: DocumentFingerprint(data: expected),
                        current: DocumentFingerprint(data: rechecked)
                    )
                }
                try self.descriptorAccess.verifyCurrentParent(
                    path,
                    retainedDescriptor: parentFD
                )

                let stagingURL = targetURL.deletingLastPathComponent()
                    .appendingPathComponent(stagingName, isDirectory: false)
                try self.hooks.didReach?(.replacing)
                do {
                    _ = try FileManager.default.replaceItemAt(
                        targetURL,
                        withItemAt: stagingURL,
                        backupItemName: nil,
                        options: []
                    )
                } catch {
                    throw VaultRepositoryError.commitUncertain(
                        "The coordinated system replacement did not return a proven result: \(error.localizedDescription)"
                    )
                }
                try self.hooks.didReach?(.replaced)
                try self.hooks.didReach?(.readback)
                let canonical = try self.readFile(at: name, parentFD: parentFD)
                guard canonical == candidate else {
                    throw VaultRepositoryError.readbackMismatch(
                        expected: DocumentFingerprint(data: candidate),
                        current: DocumentFingerprint(data: canonical)
                    )
                }
                try self.descriptorAccess.verifyCurrentParent(
                    path,
                    retainedDescriptor: parentFD
                )
                try self.hooks.didReach?(.completedReplacement)
                replacementCompleted = true
            }
        }
        guard replacementCompleted else {
            throw VaultRepositoryError.commitUncertain(
                "The coordinated replacement did not produce an exact canonical readback."
            )
        }
    }

    func create(path: MarkdownRelativePath, data: Data) throws {
        let destinationURL = try resolver.unresolvedURL(for: path)
        try coordinateWriting(destinationURL, options: .forReplacing) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                let stagingName = ".scholium-create-\(UUID().uuidString.lowercased()).md"
                try self.writeNewFile(data, name: stagingName, parentFD: parentFD)
                defer { _ = unlinkat(parentFD, stagingName, 0) }
                try self.hooks.didReach?(.staged)
                try self.descriptorAccess.verifyCurrentParent(
                    path,
                    retainedDescriptor: parentFD
                )
                guard renameatx_np(parentFD, stagingName, parentFD, name, UInt32(RENAME_EXCL)) == 0 else {
                    let code = errno
                    if code == EEXIST { throw VaultRepositoryError.fileAlreadyExists(path.rawValue) }
                    if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                        throw VaultRepositoryError.atomicCommitUnsupported(String(cString: strerror(code)))
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                let readback = try self.readFile(at: name, parentFD: parentFD)
                guard readback == data else {
                    throw VaultRepositoryError.commitUncertain("Created file readback did not match the staged bytes.")
                }
                guard fsync(parentFD) == 0 else {
                    throw VaultRepositoryError.commitUncertain(
                        "The created file was verified but its parent directory could not be synchronized."
                    )
                }
                do {
                    try self.descriptorAccess.verifyCurrentParent(
                        path,
                        retainedDescriptor: parentFD
                    )
                } catch {
                    throw VaultRepositoryError.commitUncertain(
                        "The created file's parent changed identity after commit: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func createDirectory(path: VaultRelativeFolderPath) throws {
        let destinationURL = try resolver.unresolvedURL(for: path)
        try coordinateWriting(destinationURL, options: .forReplacing) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                try self.descriptorAccess.verifyCurrentParent(
                    path,
                    retainedDescriptor: parentFD
                )
                guard mkdirat(parentFD, name, S_IRWXU) == 0 else {
                    let code = errno
                    if code == EEXIST {
                        throw VaultRepositoryError.fileAlreadyExists(path.rawValue)
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                var status = stat()
                guard fstatat(parentFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
                      (status.st_mode & S_IFMT) == S_IFDIR else {
                    throw VaultRepositoryError.commitUncertain(
                        "Created folder could not be verified as a directory."
                    )
                }
                guard fsync(parentFD) == 0 else {
                    throw VaultRepositoryError.commitUncertain(
                        "The created folder was verified but its parent directory could not be synchronized."
                    )
                }
                do {
                    try self.descriptorAccess.verifyCurrentParent(
                        path,
                        retainedDescriptor: parentFD
                    )
                } catch {
                    throw VaultRepositoryError.commitUncertain(
                        "The created folder's parent changed identity after commit: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    func move(
        source: MarkdownRelativePath,
        destination: MarkdownRelativePath,
        expected: Data
    ) throws {
        let sourceURL = try resolver.unresolvedURL(for: source)
        let destinationURL = try resolver.unresolvedURL(for: destination)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { _, _ in
            operationResult = Result {
                try self.withTwoParentDescriptors(source: source, destination: destination) {
                    sourceParent, sourceName, destinationParent, destinationName in
                    let current = try self.readFile(at: sourceName, parentFD: sourceParent)
                    guard current == expected else {
                        throw VaultRepositoryError.conflict(
                            expected: DocumentFingerprint(data: expected),
                            current: DocumentFingerprint(data: current)
                        )
                    }
                    try self.hooks.didReach?(.finalCheck)
                    try self.descriptorAccess.verifyCurrentParent(
                        source,
                        retainedDescriptor: sourceParent
                    )
                    try self.descriptorAccess.verifyCurrentParent(
                        destination,
                        retainedDescriptor: destinationParent
                    )
                    guard renameatx_np(
                        sourceParent,
                        sourceName,
                        destinationParent,
                        destinationName,
                        UInt32(RENAME_EXCL)
                    ) == 0 else {
                        let code = errno
                        if code == EEXIST {
                            throw VaultRepositoryError.fileAlreadyExists(destination.rawValue)
                        }
                        if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                            throw VaultRepositoryError.atomicCommitUnsupported(String(cString: strerror(code)))
                        }
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    }
                    let readback = try self.readFile(at: destinationName, parentFD: destinationParent)
                    guard readback == expected else {
                        throw VaultRepositoryError.commitUncertain("Moved-file readback did not match its authorized preimage.")
                    }
                    guard fsync(sourceParent) == 0, fsync(destinationParent) == 0 else {
                        throw VaultRepositoryError.commitUncertain(
                            "The moved file was verified but a parent directory could not be synchronized."
                        )
                    }
                    do {
                        try self.descriptorAccess.verifyCurrentParent(
                            source,
                            retainedDescriptor: sourceParent
                        )
                        try self.descriptorAccess.verifyCurrentParent(
                            destination,
                            retainedDescriptor: destinationParent
                        )
                    } catch {
                        throw VaultRepositoryError.commitUncertain(
                            "A moved-file parent changed identity after commit: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        if let coordinationError { throw coordinationError }
        try operationResult?.get()
    }

    func moveDirectory(
        source: VaultRelativeFolderPath,
        destination: VaultRelativeFolderPath
    ) throws {
        let sourceURL = try resolver.unresolvedURL(for: source)
        let destinationURL = try resolver.unresolvedURL(for: destination)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { _, _ in
            operationResult = Result {
                try self.withTwoParentDescriptors(source: source, destination: destination) {
                    sourceParent, sourceName, destinationParent, destinationName in
                    var sourceStatus = stat()
                    guard fstatat(
                        sourceParent,
                        sourceName,
                        &sourceStatus,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    guard (sourceStatus.st_mode & S_IFMT) == S_IFDIR else {
                        throw VaultRepositoryError.notRegularFile(source.rawValue)
                    }
                    try self.hooks.didReach?(.finalCheck)
                    try self.descriptorAccess.verifyCurrentParent(
                        source,
                        retainedDescriptor: sourceParent
                    )
                    try self.descriptorAccess.verifyCurrentParent(
                        destination,
                        retainedDescriptor: destinationParent
                    )

                    let sourceKey = self.resolver.comparisonKey(for: source)
                    let destinationKey = self.resolver.comparisonKey(for: destination)
                    let result: Int32
                    if sourceKey == destinationKey {
                        var destinationStatus = stat()
                        let destinationExists = fstatat(
                            destinationParent,
                            destinationName,
                            &destinationStatus,
                            AT_SYMLINK_NOFOLLOW
                        ) == 0
                        if destinationExists,
                           (destinationStatus.st_dev != sourceStatus.st_dev
                            || destinationStatus.st_ino != sourceStatus.st_ino) {
                            throw VaultRepositoryError.fileAlreadyExists(destination.rawValue)
                        }
                        result = renameat(
                            sourceParent,
                            sourceName,
                            destinationParent,
                            destinationName
                        )
                    } else {
                        result = renameatx_np(
                            sourceParent,
                            sourceName,
                            destinationParent,
                            destinationName,
                            UInt32(RENAME_EXCL)
                        )
                    }
                    guard result == 0 else {
                        let code = errno
                        if code == EEXIST {
                            throw VaultRepositoryError.fileAlreadyExists(destination.rawValue)
                        }
                        if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                            throw VaultRepositoryError.atomicCommitUnsupported(
                                String(cString: strerror(code))
                            )
                        }
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    }

                    var committedStatus = stat()
                    guard fstatat(
                        destinationParent,
                        destinationName,
                        &committedStatus,
                        AT_SYMLINK_NOFOLLOW
                    ) == 0,
                          (committedStatus.st_mode & S_IFMT) == S_IFDIR,
                          committedStatus.st_dev == sourceStatus.st_dev,
                          committedStatus.st_ino == sourceStatus.st_ino else {
                        throw VaultRepositoryError.commitUncertain(
                            "The moved folder could not be verified at its destination."
                        )
                    }
                    guard fsync(sourceParent) == 0, fsync(destinationParent) == 0 else {
                        throw VaultRepositoryError.commitUncertain(
                            "The moved folder was verified but a parent directory could not be synchronized."
                        )
                    }
                    do {
                        try self.descriptorAccess.verifyCurrentParent(
                            source,
                            retainedDescriptor: sourceParent
                        )
                        try self.descriptorAccess.verifyCurrentParent(
                            destination,
                            retainedDescriptor: destinationParent
                        )
                    } catch {
                        throw VaultRepositoryError.commitUncertain(
                            "A moved-folder parent changed identity after commit: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let operationResult else {
            throw VaultRepositoryError.commitUncertain(
                "The coordinated folder accessor did not run."
            )
        }
        try operationResult.get()
    }

    func delete(path: MarkdownRelativePath, expected: Data) throws {
        let targetURL = try resolver.unresolvedURL(for: path)
        try coordinateWriting(targetURL, options: .forDeleting) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                let current = try self.readFile(at: name, parentFD: parentFD)
                guard current == expected else {
                    throw VaultRepositoryError.conflict(
                        expected: DocumentFingerprint(data: expected),
                        current: DocumentFingerprint(data: current)
                    )
                }
                try self.hooks.didReach?(.finalCheck)
                try self.descriptorAccess.verifyCurrentParent(
                    path,
                    retainedDescriptor: parentFD
                )
                guard unlinkat(parentFD, name, 0) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                switch self.filePresence(name: name, parentFD: parentFD) {
                case .absent:
                    break
                case .present:
                    throw VaultRepositoryError.commitUncertain(
                        "The deleted path was recreated before commit verification."
                    )
                case .inaccessible(let code):
                    throw VaultRepositoryError.commitUncertain(
                        "Deletion presence could not be verified (errno \(code)); absence was not assumed."
                    )
                }
                guard fsync(parentFD) == 0 else {
                    throw VaultRepositoryError.commitUncertain(
                        "The deletion was verified but its parent directory could not be synchronized."
                    )
                }
                do {
                    try self.descriptorAccess.verifyCurrentParent(
                        path,
                        retainedDescriptor: parentFD
                    )
                } catch {
                    throw VaultRepositoryError.commitUncertain(
                        "The deleted path's parent changed identity after commit: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func coordinateWriting(
        _ url: URL,
        options: NSFileCoordinator.WritingOptions,
        operation: () throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { _ in
            result = Result { try operation() }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
            throw VaultRepositoryError.commitUncertain("The coordinated accessor did not run.")
        }
        try result.get()
    }

    private func withParentDescriptor<T>(
        path: MarkdownRelativePath,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        try descriptorAccess.withParentDescriptor(path, body)
    }

    private func withParentDescriptor<T>(
        path: VaultRelativeFolderPath,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        try descriptorAccess.withParentDescriptor(path, body)
    }

    private func withTwoParentDescriptors<T>(
        source: MarkdownRelativePath,
        destination: MarkdownRelativePath,
        _ body: (Int32, String, Int32, String) throws -> T
    ) throws -> T {
        try withParentDescriptor(path: source) { sourceFD, sourceName in
            try withParentDescriptor(path: destination) { destinationFD, destinationName in
                try body(sourceFD, sourceName, destinationFD, destinationName)
            }
        }
    }

    private func withTwoParentDescriptors<T>(
        source: VaultRelativeFolderPath,
        destination: VaultRelativeFolderPath,
        _ body: (Int32, String, Int32, String) throws -> T
    ) throws -> T {
        try withParentDescriptor(path: source) { sourceFD, sourceName in
            try withParentDescriptor(path: destination) { destinationFD, destinationName in
                try body(sourceFD, sourceName, destinationFD, destinationName)
            }
        }
    }

    private func readFile(at name: String, parentFD: Int32) throws -> Data {
        let fd = openat(
            parentFD,
            name,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            throw VaultRepositoryError.notRegularFile(name)
        }
        return try readFile(descriptor: fd)
    }

    private func readFile(descriptor: Int32) throws -> Data {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return try VaultDescriptorAccess.readAll(from: descriptor)
    }

    private func writeNewFile(_ data: Data, name: String, parentFD: Int32) throws {
        let fd = try openNewFile(data, name: name, parentFD: parentFD)
        close(fd)
    }

    private func openNewFile(_ data: Data, name: String, parentFD: Int32) throws -> Int32 {
        let fd = openat(
            parentFD,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            try data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    offset += count
                }
            }
            guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
            return fd
        } catch {
            close(fd)
            throw error
        }
    }

    private func filePresence(name: String, parentFD: Int32) -> FilePresence {
        if let overridden = hooks.presenceOverride?(name) { return overridden }
        return VaultDescriptorAccess.presence(name: name, parentDescriptor: parentFD)
    }
}
