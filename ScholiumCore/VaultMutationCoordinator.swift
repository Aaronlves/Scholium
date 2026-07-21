import Darwin
import Foundation
import ScholiumContracts

enum VaultMutationPhase: Equatable, Sendable {
    case initialRead
    case staged
    case finalCheck
    case swapped
    case readback
}

struct VaultMutationHooks: @unchecked Sendable {
    var didReach: ((VaultMutationPhase) throws -> Void)?

    static let none = VaultMutationHooks()
}

/// Coordinates short-lived filesystem commits while descriptor-relative,
/// no-follow checks retain the actual authorization boundary.
final class VaultMutationCoordinator {
    private let resolver: VaultPathResolver
    private let hooks: VaultMutationHooks

    init(resolver: VaultPathResolver, hooks: VaultMutationHooks = .none) {
        self.resolver = resolver
        self.hooks = hooks
    }

    func updateExisting(
        path: MarkdownRelativePath,
        expected: Data,
        candidate: Data
    ) throws {
        let targetURL = try resolver.unresolvedURL(for: path)
        try coordinateWriting(targetURL, options: .forReplacing) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                let initial = try self.readFile(at: name, parentFD: parentFD)
                try self.hooks.didReach?(.initialRead)
                guard initial == expected else {
                    throw VaultRepositoryError.conflict(
                        expected: DocumentFingerprint(data: expected),
                        current: DocumentFingerprint(data: initial)
                    )
                }

                let stagingName = ".scholium-swap-\(UUID().uuidString.lowercased()).md"
                try self.writeNewFile(candidate, name: stagingName, parentFD: parentFD)
                var shouldRemoveStaging = true
                defer {
                    if shouldRemoveStaging { _ = unlinkat(parentFD, stagingName, 0) }
                }
                try self.hooks.didReach?(.staged)

                let rechecked = try self.readFile(at: name, parentFD: parentFD)
                try self.hooks.didReach?(.finalCheck)
                guard rechecked == expected else {
                    throw VaultRepositoryError.conflict(
                        expected: DocumentFingerprint(data: expected),
                        current: DocumentFingerprint(data: rechecked)
                    )
                }

                guard renameatx_np(parentFD, stagingName, parentFD, name, UInt32(RENAME_SWAP)) == 0 else {
                    let code = errno
                    if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                        throw VaultRepositoryError.atomicCommitUnsupported(String(cString: strerror(code)))
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
                try self.hooks.didReach?(.swapped)

                let canonical: Data
                let displaced: Data
                do {
                    try self.hooks.didReach?(.readback)
                    canonical = try self.readFile(at: name, parentFD: parentFD)
                    displaced = try self.readFile(at: stagingName, parentFD: parentFD)
                } catch {
                    // The swap happened, so an unreadable or replaced side is
                    // never a normal I/O failure. Attempt one guarded swap-back
                    // and retain staging regardless of the rollback result.
                    _ = renameatx_np(
                        parentFD, stagingName, parentFD, name, UInt32(RENAME_SWAP)
                    )
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "Post-swap bytes became unreadable or changed identity: \(error.localizedDescription)"
                    )
                }
                guard canonical == candidate, displaced == expected else {
                    if canonical == candidate {
                        // Restore the observed displaced bytes, even when they
                        // are not the expected preimage. The outcome remains
                        // uncertain and every staged byte is retained.
                        if renameatx_np(
                            parentFD, stagingName, parentFD, name, UInt32(RENAME_SWAP)
                        ) == 0 {
                            shouldRemoveStaging = false
                        } else {
                            shouldRemoveStaging = false
                        }
                    } else {
                        shouldRemoveStaging = false
                    }
                    throw VaultRepositoryError.commitUncertain(
                        "Expected candidate \(DocumentFingerprint(data: candidate).sha256) and displaced preimage \(DocumentFingerprint(data: expected).sha256); observed canonical \(DocumentFingerprint(data: canonical).sha256) and staging \(DocumentFingerprint(data: displaced).sha256)."
                    )
                }
                guard fsync(parentFD) == 0 else {
                    shouldRemoveStaging = false
                    throw VaultRepositoryError.commitUncertain(
                        "The parent directory could not be synchronized after the swap."
                    )
                }
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
                }
            }
        }
        if let coordinationError { throw coordinationError }
        try operationResult?.get()
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
                guard unlinkat(parentFD, name, 0) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                guard self.fileExists(name: name, parentFD: parentFD) == false else {
                    throw VaultRepositoryError.commitUncertain("The deleted path was recreated before commit verification.")
                }
                guard fsync(parentFD) == 0 else {
                    throw VaultRepositoryError.commitUncertain(
                        "The deletion was verified but its parent directory could not be synchronized."
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
        let components = path.components.map(String.init)
        guard let name = components.last else {
            throw VaultRepositoryError.invalidRelativePath(path.rawValue)
        }
        let rootFD = open(resolver.canonicalRoot.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard rootFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(rootFD) }
        var currentFD = rootFD
        var ownedFD: Int32?
        defer { if let ownedFD { close(ownedFD) } }
        for component in components.dropLast() {
            let next = openat(currentFD, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if let ownedFD { close(ownedFD) }
            ownedFD = next
            currentFD = next
        }
        return try body(currentFD, name)
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

    private func readFile(at name: String, parentFD: Int32) throws -> Data {
        let fd = openat(parentFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { return data }
            guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            data.append(buffer, count: count)
        }
    }

    private func writeNewFile(_ data: Data, name: String, parentFD: Int32) throws {
        let fd = openat(
            parentFD,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw POSIXError(.EIO) }
    }

    private func fileExists(name: String, parentFD: Int32) -> Bool {
        var status = stat()
        return fstatat(parentFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0
    }
}
