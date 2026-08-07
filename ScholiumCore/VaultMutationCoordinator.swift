import Darwin
import Foundation
import ScholiumContracts

enum VaultMutationPhase: Equatable, Sendable {
    case initialRead
    case staged
    case finalCheck
    case swapped
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
    private struct MetadataSnapshot {
        let status: stat
        let extendedAttributes: [String: Data]
        let accessControlList: Data?
    }

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

                let stagingName = ".scholium-swap-\(UUID().uuidString.lowercased()).md"
                let stagingFD = try self.openNewFile(
                    candidate,
                    name: stagingName,
                    parentFD: parentFD
                )
                defer { close(stagingFD) }
                let candidateIdentity = try self.fileIdentity(descriptor: stagingFD)
                var shouldRemoveStaging = true
                defer {
                    if shouldRemoveStaging { _ = unlinkat(parentFD, stagingName, 0) }
                }
                let metadata = try self.copyAndVerifyMetadata(
                    from: originalFD,
                    originalStatus: originalStatus,
                    to: stagingFD
                )
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

                guard renameatx_np(parentFD, stagingName, parentFD, name, UInt32(RENAME_SWAP)) == 0 else {
                    let code = errno
                    if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                        throw VaultRepositoryError.atomicCommitUnsupported(String(cString: strerror(code)))
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }

                let canonical: Data
                let displaced: Data
                do {
                    try self.hooks.didReach?(.swapped)
                    try self.hooks.didReach?(.readback)
                    canonical = try self.readFile(at: name, parentFD: parentFD)
                    displaced = try self.readFile(at: stagingName, parentFD: parentFD)
                } catch {
                    // The swap happened, so an unreadable or replaced side is
                    // never a normal I/O failure. Attempt one guarded swap-back
                    // and retain staging regardless of the rollback result.
                    let restored = self.guardedSwapBack(
                        parentFD: parentFD,
                        canonicalName: name,
                        expectedCanonical: candidateIdentity,
                        stagingName: stagingName,
                        expectedStaging: originalIdentity
                    )
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "Post-swap bytes became unreadable or changed identity; guarded swap-back \(restored ? "succeeded" : "was refused or failed"): \(error.localizedDescription)"
                    )
                }
                guard canonical == candidate, displaced == expected else {
                    if canonical == candidate,
                       let observedStagingIdentity = try? VaultDescriptorAccess.identity(
                           name: stagingName,
                           parentDescriptor: parentFD
                       ) {
                        // Restore the observed displaced bytes, even when they
                        // are not the expected preimage. The outcome remains
                        // uncertain and every staged byte is retained.
                        _ = self.guardedSwapBack(
                            parentFD: parentFD,
                            canonicalName: name,
                            expectedCanonical: candidateIdentity,
                            stagingName: stagingName,
                            expectedStaging: observedStagingIdentity
                        )
                        shouldRemoveStaging = false
                    } else {
                        shouldRemoveStaging = false
                    }
                    throw VaultRepositoryError.commitUncertain(
                        "Expected candidate \(DocumentFingerprint(data: candidate).sha256) and displaced preimage \(DocumentFingerprint(data: expected).sha256); observed canonical \(DocumentFingerprint(data: canonical).sha256) and staging \(DocumentFingerprint(data: displaced).sha256)."
                    )
                }
                do {
                    guard fchflags(stagingFD, metadata.status.st_flags) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    try self.verifyCommittedMetadata(
                        descriptor: stagingFD,
                        metadata: metadata,
                        verifyFlags: true
                    )
                    guard fsync(stagingFD) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                } catch {
                    let restored = self.guardedSwapBack(
                        parentFD: parentFD,
                        canonicalName: name,
                        expectedCanonical: candidateIdentity,
                        stagingName: stagingName,
                        expectedStaging: originalIdentity
                    )
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "Committed metadata could not be verified; guarded swap-back \(restored ? "succeeded" : "failed"): \(error.localizedDescription)"
                    )
                }
                guard fsync(parentFD) == 0 else {
                    let code = errno
                    let restored = self.guardedSwapBack(
                        parentFD: parentFD,
                        canonicalName: name,
                        expectedCanonical: candidateIdentity,
                        stagingName: stagingName,
                        expectedStaging: originalIdentity
                    )
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "The parent directory could not be synchronized after the swap (errno \(code)); guarded swap-back \(restored ? "succeeded" : "was refused or failed")."
                    )
                }
                do {
                    try self.descriptorAccess.verifyCurrentParent(
                        path,
                        retainedDescriptor: parentFD
                    )
                } catch {
                    let restored = self.guardedSwapBack(
                        parentFD: parentFD,
                        canonicalName: name,
                        expectedCanonical: candidateIdentity,
                        stagingName: stagingName,
                        expectedStaging: originalIdentity
                    )
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "The committed parent changed identity; guarded swap-back \(restored ? "succeeded" : "was refused or failed"): \(error.localizedDescription)"
                    )
                }
                try self.hooks.didReach?(.completedReplacement)
            }
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

    private func fileIdentity(
        descriptor: Int32
    ) throws -> VaultDescriptorAccess.FileIdentity {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return VaultDescriptorAccess.FileIdentity(status)
    }

    /// Swaps back only while both directory entries still name the exact
    /// inodes held open across the original commit. An external replacement
    /// therefore turns rollback into retained evidence, never another write.
    private func guardedSwapBack(
        parentFD: Int32,
        canonicalName: String,
        expectedCanonical: VaultDescriptorAccess.FileIdentity,
        stagingName: String,
        expectedStaging: VaultDescriptorAccess.FileIdentity
    ) -> Bool {
        guard let canonical = try? VaultDescriptorAccess.identity(
            name: canonicalName,
            parentDescriptor: parentFD
        ), canonical == expectedCanonical,
        let staging = try? VaultDescriptorAccess.identity(
            name: stagingName,
            parentDescriptor: parentFD
        ), staging == expectedStaging else {
            return false
        }
        return renameatx_np(
            parentFD,
            stagingName,
            parentFD,
            canonicalName,
            UInt32(RENAME_SWAP)
        ) == 0
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

    private func copyAndVerifyMetadata(
        from originalFD: Int32,
        originalStatus: stat,
        to stagingFD: Int32
    ) throws -> MetadataSnapshot {
        var candidateStatus = stat()
        guard fstat(stagingFD, &candidateStatus) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let metadata = MetadataSnapshot(
            status: originalStatus,
            extendedAttributes: try extendedAttributes(descriptor: originalFD),
            accessControlList: try accessControlList(descriptor: originalFD)
        )
        guard fcopyfile(originalFD, stagingFD, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // Immutable/append flags would block final timestamp work and
        // readback. Reapply the complete captured flag word only after the
        // candidate has been swapped and its bytes have been verified.
        guard fchflags(stagingFD, 0) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
        var birthTime = originalStatus.st_birthtimespec
        guard fsetattrlist(
            stagingFD,
            &attributes,
            &birthTime,
            MemoryLayout<timespec>.size,
            0
        ) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var candidateModification = candidateStatus.st_mtimespec
        if Self.compare(candidateModification, originalStatus.st_mtimespec) <= 0 {
            candidateModification = originalStatus.st_mtimespec
            candidateModification.tv_nsec += 1
            if candidateModification.tv_nsec >= 1_000_000_000 {
                candidateModification.tv_sec += 1
                candidateModification.tv_nsec = 0
            }
        }
        let times = [originalStatus.st_atimespec, candidateModification]
        guard times.withUnsafeBufferPointer({ futimens(stagingFD, $0.baseAddress) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try verifyCommittedMetadata(
            descriptor: stagingFD,
            metadata: metadata,
            verifyFlags: false
        )
        guard fsync(stagingFD) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return metadata
    }

    private func verifyCommittedMetadata(
        descriptor: Int32,
        metadata: MetadataSnapshot,
        verifyFlags: Bool
    ) throws {
        var observed = stat()
        guard fstat(descriptor, &observed) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let originalStatus = metadata.status
        let permissionMask = mode_t(S_IRWXU | S_IRWXG | S_IRWXO | S_ISUID | S_ISGID | S_ISVTX)
        let observedExtendedAttributes = try extendedAttributes(descriptor: descriptor)
        let observedAccessControlList = try accessControlList(descriptor: descriptor)
        guard observed.st_mode & permissionMask == originalStatus.st_mode & permissionMask,
              observed.st_uid == originalStatus.st_uid,
              observed.st_gid == originalStatus.st_gid,
              (!verifyFlags || observed.st_flags == originalStatus.st_flags),
              observed.st_birthtimespec.tv_sec == originalStatus.st_birthtimespec.tv_sec,
              observed.st_birthtimespec.tv_nsec == originalStatus.st_birthtimespec.tv_nsec,
              Self.extendedAttributesAreEquivalent(
                  expected: metadata.extendedAttributes,
                  observed: observedExtendedAttributes
              ),
              observedAccessControlList == metadata.accessControlList,
              Self.compare(observed.st_mtimespec, originalStatus.st_mtimespec) > 0 else {
            let expectedAttributeNames = Set(metadata.extendedAttributes.keys)
            let observedAttributeNames = Set(observedExtendedAttributes.keys)
            let missingAttributes = expectedAttributeNames
                .subtracting(observedAttributeNames)
                .sorted()
            let addedAttributes = observedAttributeNames
                .subtracting(expectedAttributeNames)
                .sorted()
            let changedAttributes = expectedAttributeNames
                .intersection(observedAttributeNames)
                .filter {
                    guard let expected = metadata.extendedAttributes[$0],
                          let current = observedExtendedAttributes[$0] else {
                        return true
                    }
                    return !Self.extendedAttributeIsEquivalent(
                        name: $0,
                        expected: expected,
                        observed: current
                    )
                }
                .sorted()
            throw VaultRepositoryError.commitUncertain(
                "The staged file did not preserve the authorized metadata envelope "
                    + "(mode \(String(observed.st_mode & permissionMask, radix: 8))/\(String(originalStatus.st_mode & permissionMask, radix: 8)), "
                    + "owner \(observed.st_uid):\(observed.st_gid)/\(originalStatus.st_uid):\(originalStatus.st_gid), "
                    + "flags \(observed.st_flags)/\(originalStatus.st_flags), "
                    + "birth \(observed.st_birthtimespec.tv_sec).\(observed.st_birthtimespec.tv_nsec)/\(originalStatus.st_birthtimespec.tv_sec).\(originalStatus.st_birthtimespec.tv_nsec), "
                    + "mtime \(observed.st_mtimespec.tv_sec).\(observed.st_mtimespec.tv_nsec)/\(originalStatus.st_mtimespec.tv_sec).\(originalStatus.st_mtimespec.tv_nsec), "
                    + "xattrs missing \(missingAttributes), added \(addedAttributes), changed \(changedAttributes), "
                    + "ACL equal \(observedAccessControlList == metadata.accessControlList))."
            )
        }
    }

    private func extendedAttributes(
        descriptor: Int32
    ) throws -> [String: Data] {
        let required = flistxattr(descriptor, nil, 0, 0)
        guard required >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard required > 0 else { return [:] }
        var names = [CChar](repeating: 0, count: required)
        let received = flistxattr(descriptor, &names, names.count, 0)
        guard received == required else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var result: [String: Data] = [:]
        var start = 0
        while start < received {
            var end = start
            while end < received, names[end] != 0 { end += 1 }
            guard end < received else {
                throw POSIXError(.EIO)
            }
            let name = names.withUnsafeBufferPointer { buffer in
                String(cString: buffer.baseAddress!.advanced(by: start))
            }
            let valueSize = name.withCString {
                fgetxattr(descriptor, $0, nil, 0, 0, 0)
            }
            guard valueSize >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            var value = Data(count: valueSize)
            let valueCount = value.withUnsafeMutableBytes { bytes in
                name.withCString {
                    fgetxattr(
                        descriptor,
                        $0,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        0
                    )
                }
            }
            guard valueCount == valueSize else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            result[name] = value
            start = end + 1
        }
        return result
    }

    private static func extendedAttributesAreEquivalent(
        expected: [String: Data],
        observed: [String: Data]
    ) -> Bool {
        let expectedNames = Set(expected.keys)
        let observedNames = Set(observed.keys)
        guard expectedNames.isSubset(of: observedNames) else { return false }
        let addedNames = observedNames.subtracting(expectedNames)
        if !addedNames.isEmpty {
            // A sandboxed process may attach a quarantine envelope to the
            // newly created staging inode. Keep that system security metadata
            // in place, but accept no other addition and no malformed value.
            guard addedNames == [quarantineAttributeName],
                  let addedQuarantine = observed[quarantineAttributeName],
                  QuarantineAttribute(addedQuarantine) != nil else {
                return false
            }
        }
        return expected.allSatisfy { name, expectedValue in
            guard let observedValue = observed[name] else { return false }
            return extendedAttributeIsEquivalent(
                name: name,
                expected: expectedValue,
                observed: observedValue
            )
        }
    }

    private static func extendedAttributeIsEquivalent(
        name: String,
        expected: Data,
        observed: Data
    ) -> Bool {
        guard expected != observed else { return true }
        guard name == quarantineAttributeName,
              let expectedValue = QuarantineAttribute(expected),
              let observedValue = QuarantineAttribute(observed) else {
            return false
        }
        // LaunchServices may replace the setting process and timestamp. The
        // security flags and event identity remain the stable authority.
        return observedValue.flags == expectedValue.flags
            && observedValue.eventIdentifier == expectedValue.eventIdentifier
            && observedValue.timestamp >= expectedValue.timestamp
    }

    private static let quarantineAttributeName = "com.apple.quarantine"

    private func accessControlList(descriptor: Int32) throws -> Data? {
        errno = 0
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        let size = acl_size(acl)
        guard size >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var bytes = Data(count: size)
        let copied = bytes.withUnsafeMutableBytes {
            acl_copy_ext_native($0.baseAddress, acl, size)
        }
        guard copied == size else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return bytes
    }

    private static func compare(_ lhs: timespec, _ rhs: timespec) -> Int {
        if lhs.tv_sec != rhs.tv_sec { return lhs.tv_sec < rhs.tv_sec ? -1 : 1 }
        if lhs.tv_nsec != rhs.tv_nsec { return lhs.tv_nsec < rhs.tv_nsec ? -1 : 1 }
        return 0
    }

    private struct QuarantineAttribute {
        let flags: UInt64
        let timestamp: UInt64
        let eventIdentifier: String

        init?(_ data: Data) {
            guard let source = String(data: data, encoding: .utf8) else { return nil }
            let fields = source.split(separator: ";", omittingEmptySubsequences: false)
            guard fields.count == 4,
                  let flags = UInt64(fields[0], radix: 16),
                  let timestamp = UInt64(fields[1], radix: 16) else {
                return nil
            }
            self.flags = flags
            self.timestamp = timestamp
            eventIdentifier = fields[3].lowercased()
        }
    }
}
