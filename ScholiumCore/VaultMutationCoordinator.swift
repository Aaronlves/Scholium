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
    case systemTrashBinding
    case systemTrashBound
    case systemTrashMoved
}

struct VaultMutationHooks: @unchecked Sendable {
    var didReach: ((VaultMutationPhase) throws -> Void)? = nil
    var presenceOverride: ((String) -> FilePresence?)? = nil

    static let none = VaultMutationHooks()
}

enum SystemTrashMoveError: LocalizedError, Sendable {
    case outcomeUnknown(resultingURL: URL?, reason: String)

    var errorDescription: String? {
        switch self {
        case .outcomeUnknown(_, let reason):
            "Scholium could not prove the final system Trash result: \(reason)"
        }
    }
}

enum SystemTrashBindingPath {
    static func directoryName(id: UUID) -> String {
        ".scholium-system-trash-\(id.uuidString.lowercased())"
    }

    static func itemURL(targetURL: URL, id: UUID, isDirectory: Bool) -> URL {
        targetURL.deletingLastPathComponent()
            .appendingPathComponent(directoryName(id: id), isDirectory: true)
            .appendingPathComponent(targetURL.lastPathComponent, isDirectory: isDirectory)
    }

    static func itemRelativePath(original: String, id: UUID) -> String {
        let components = original.split(separator: "/", omittingEmptySubsequences: false)
        let name = components.last.map(String.init) ?? original
        let parent = components.dropLast().joined(separator: "/")
        let bound = "\(directoryName(id: id))/\(name)"
        return parent.isEmpty ? bound : "\(parent)/\(bound)"
    }
}

/// Coordinates short-lived filesystem commits while descriptor-relative,
/// no-follow checks retain the actual authorization boundary.
final class VaultMutationCoordinator {
    private let resolver: VaultPathResolver
    private let descriptorAccess: VaultDescriptorAccess
    private let hooks: VaultMutationHooks

    init(
        resolver: VaultPathResolver,
        hooks: VaultMutationHooks = .none,
        descriptorAccess: VaultDescriptorAccess? = nil
    ) throws {
        self.resolver = resolver
        if let descriptorAccess {
            self.descriptorAccess = descriptorAccess
        } else {
            self.descriptorAccess = try VaultDescriptorAccess(
                rootURL: resolver.canonicalRoot
            )
        }
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

    /// Atomically binds the exact checked directory entry into a transaction-
    /// owned sibling before invoking Foundation's native system Trash. A
    /// retry can resume that binding after interruption, while a replacement
    /// that wins before the atomic bind is preserved and never sent to Trash.
    func moveToSystemTrash(
        path: MarkdownRelativePath,
        expectedRevision: DocumentFingerprint,
        bindingID: UUID
    ) throws -> URL? {
        let targetURL = try resolver.unresolvedURL(for: path)
        var resultingURL: URL?
        try coordinateWriting(targetURL, options: .forDeleting) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                resultingURL = try self.moveBoundItemToSystemTrash(
                    targetURL: targetURL,
                    parentFD: parentFD,
                    name: name,
                    bindingID: bindingID,
                    expectedDirectory: false,
                    itemDescription: "Note",
                    verifyCurrentParent: {
                        try self.descriptorAccess.verifyCurrentParent(
                            path,
                            retainedDescriptor: parentFD
                        )
                    },
                    validateOriginal: {
                        let data = try self.readFile(at: name, parentFD: parentFD)
                        let current = DocumentFingerprint(data: data)
                        guard current == expectedRevision else {
                            throw VaultRepositoryError.conflict(
                                expected: expectedRevision,
                                current: current
                            )
                        }
                    },
                    validateBound: { bindingFD, _ in
                        let data = try self.readFile(at: name, parentFD: bindingFD)
                        guard DocumentFingerprint(data: data) == expectedRevision else {
                            throw VaultRepositoryError.commitUncertain(
                                "The bound Note no longer matches the confirmed revision."
                            )
                        }
                    }
                )
            }
        }
        return resultingURL
    }

    /// Binds and validates the complete directory before the shared native
    /// Trash state machine; the repository supplies its exact manifest check.
    func moveDirectoryToSystemTrash(
        path: VaultRelativeFolderPath,
        bindingID: UUID,
        finalInventoryCheck: (URL) throws -> Void
    ) throws -> URL? {
        let targetURL = try resolver.unresolvedURL(for: path)
        var resultingURL: URL?
        try coordinateWriting(targetURL, options: .forDeleting) {
            try self.withParentDescriptor(path: path) { parentFD, name in
                resultingURL = try self.moveBoundItemToSystemTrash(
                    targetURL: targetURL,
                    parentFD: parentFD,
                    name: name,
                    bindingID: bindingID,
                    expectedDirectory: true,
                    itemDescription: "Folder",
                    verifyCurrentParent: {
                        try self.descriptorAccess.verifyCurrentParent(
                            path,
                            retainedDescriptor: parentFD
                        )
                    },
                    validateOriginal: {
                        try finalInventoryCheck(targetURL)
                    },
                    validateBound: { _, boundURL in
                        try finalInventoryCheck(boundURL)
                    }
                )
            }
        }
        return resultingURL
    }

    private func moveBoundItemToSystemTrash(
        targetURL: URL,
        parentFD: Int32,
        name: String,
        bindingID: UUID,
        expectedDirectory: Bool,
        itemDescription: String,
        verifyCurrentParent: () throws -> Void,
        validateOriginal: () throws -> Void,
        validateBound: (Int32, URL) throws -> Void
    ) throws -> URL? {
        let boundURL = SystemTrashBindingPath.itemURL(
            targetURL: targetURL,
            id: bindingID,
            isDirectory: expectedDirectory
        )
        return try withSystemTrashBindingDirectory(
            parentFD: parentFD,
            bindingID: bindingID,
            createIfMissing: true
        ) { bindingFD, bindingName in
            defer {
                if case .absent = self.filePresence(name: name, parentFD: bindingFD) {
                    try? self.removeSystemTrashBindingDirectory(
                        name: bindingName,
                        parentFD: parentFD
                    )
                }
            }
            switch self.filePresence(name: name, parentFD: bindingFD) {
            case .present:
                _ = try self.entryIdentity(
                    name: name,
                    parentFD: bindingFD,
                    expectedDirectory: expectedDirectory
                )
                try validateBound(bindingFD, boundURL)
            case .absent:
                let initialIdentity = try self.entryIdentity(
                    name: name,
                    parentFD: parentFD,
                    expectedDirectory: expectedDirectory
                )
                try self.hooks.didReach?(.finalCheck)
                try verifyCurrentParent()
                try validateOriginal()
                guard try self.entryIdentity(
                    name: name,
                    parentFD: parentFD,
                    expectedDirectory: expectedDirectory
                ) == initialIdentity else {
                    throw VaultRepositoryError.commitUncertain(
                        "The exact \(itemDescription.lowercased()) directory entry changed before the system Trash binding."
                    )
                }
                try self.hooks.didReach?(.systemTrashBinding)
                try self.moveIntoSystemTrashBinding(
                    name: name,
                    parentFD: parentFD,
                    bindingFD: bindingFD
                )
                let boundIdentity = try self.entryIdentity(
                    name: name,
                    parentFD: bindingFD,
                    expectedDirectory: expectedDirectory
                )
                guard boundIdentity == initialIdentity else {
                    _ = try self.restoreSystemTrashBinding(
                        name: name,
                        parentFD: parentFD,
                        bindingFD: bindingFD,
                        bindingName: bindingName
                    )
                    throw VaultRepositoryError.commitUncertain(
                        "A replacement reached the \(itemDescription.lowercased()) path before the atomic system-Trash binding; it was preserved and was not moved to Trash."
                    )
                }
                try validateBound(bindingFD, boundURL)
                try self.hooks.didReach?(.systemTrashBound)
            case .inaccessible(let code):
                throw VaultRepositoryError.commitUncertain(
                    "The retained \(itemDescription.lowercased()) system-Trash binding is inaccessible (errno \(code))."
                )
            }

            try verifyCurrentParent()
            try self.verifySystemTrashBindingDirectory(
                name: bindingName,
                parentFD: parentFD,
                bindingFD: bindingFD
            )
            var systemResult: NSURL?
            do {
                try FileManager.default.trashItem(
                    at: boundURL,
                    resultingItemURL: &systemResult
                )
            } catch {
                try self.handleSystemTrashFailure(
                    error,
                    systemResult: systemResult as URL?,
                    name: name,
                    parentFD: parentFD,
                    bindingFD: bindingFD,
                    bindingName: bindingName
                )
            }
            let resultingURL = systemResult as URL?
            try self.hooks.didReach?(.systemTrashMoved)
            guard case .absent = self.filePresence(name: name, parentFD: bindingFD) else {
                throw SystemTrashMoveError.outcomeUnknown(
                    resultingURL: resultingURL,
                    reason: "The bound \(itemDescription.lowercased()) remained present after Foundation returned."
                )
            }
            try self.removeSystemTrashBindingDirectory(
                name: bindingName,
                parentFD: parentFD
            )
            guard case .absent = self.filePresence(name: name, parentFD: parentFD) else {
                throw SystemTrashMoveError.outcomeUnknown(
                    resultingURL: resultingURL,
                    reason: "The original \(itemDescription.lowercased()) path was occupied again before readback."
                )
            }
            try verifyCurrentParent()
            return resultingURL
        }
    }

    func systemTrashBindingContains(
        path: MarkdownRelativePath,
        bindingID: UUID
    ) throws -> Bool {
        try withParentDescriptor(path: path) { parentFD, name in
            try systemTrashBindingContains(
                name: name,
                parentFD: parentFD,
                bindingID: bindingID
            )
        }
    }

    func systemTrashBindingContains(
        path: VaultRelativeFolderPath,
        bindingID: UUID
    ) throws -> Bool {
        try withParentDescriptor(path: path) { parentFD, name in
            try systemTrashBindingContains(
                name: name,
                parentFD: parentFD,
                bindingID: bindingID
            )
        }
    }

    private func systemTrashBindingContains(
        name: String,
        parentFD: Int32,
        bindingID: UUID
    ) throws -> Bool {
        var contains = false
        do {
            try withSystemTrashBindingDirectory(
                parentFD: parentFD,
                bindingID: bindingID,
                createIfMissing: false
            ) { bindingFD, _ in
                switch filePresence(name: name, parentFD: bindingFD) {
                case .present:
                    contains = true
                case .absent:
                    contains = false
                case .inaccessible(let code):
                    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                }
            }
        } catch let error as POSIXError where error.code == .ENOENT {
            return false
        }
        return contains
    }

    private func withSystemTrashBindingDirectory<T>(
        parentFD: Int32,
        bindingID: UUID,
        createIfMissing: Bool,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        let bindingName = SystemTrashBindingPath.directoryName(id: bindingID)
        if createIfMissing,
           mkdirat(parentFD, bindingName, S_IRWXU) != 0,
           errno != EEXIST {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let bindingFD = openat(
            parentFD,
            bindingName,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard bindingFD >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(bindingFD) }
        return try body(bindingFD, bindingName)
    }

    private func moveIntoSystemTrashBinding(
        name: String,
        parentFD: Int32,
        bindingFD: Int32
    ) throws {
        guard renameatx_np(
            parentFD,
            name,
            bindingFD,
            name,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            let code = errno
            if code == EEXIST {
                throw VaultRepositoryError.commitUncertain(
                    "The system-Trash binding already contains another directory entry."
                )
            }
            if code == ENOTSUP || code == EINVAL || code == ENOSYS {
                throw VaultRepositoryError.atomicCommitUnsupported(
                    String(cString: strerror(code))
                )
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        guard fsync(parentFD) == 0, fsync(bindingFD) == 0 else {
            throw VaultRepositoryError.commitUncertain(
                "The exact source was bound for system Trash but its directory transition could not be synchronized."
            )
        }
    }

    private func restoreSystemTrashBinding(
        name: String,
        parentFD: Int32,
        bindingFD: Int32,
        bindingName: String
    ) throws -> Bool {
        switch filePresence(name: name, parentFD: parentFD) {
        case .present:
            return false
        case .inaccessible(let code):
            throw VaultRepositoryError.commitUncertain(
                "The original path could not be checked while preserving its system-Trash binding (errno \(code))."
            )
        case .absent:
            break
        }
        guard renameatx_np(
            bindingFD,
            name,
            parentFD,
            name,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            if errno == EEXIST { return false }
            throw VaultRepositoryError.commitUncertain(
                "The exact source remains preserved in its system-Trash binding because restoration failed: \(String(cString: strerror(errno)))."
            )
        }
        guard fsync(bindingFD) == 0, fsync(parentFD) == 0 else {
            throw VaultRepositoryError.commitUncertain(
                "The exact source was restored from its system-Trash binding but the directory transition could not be synchronized."
            )
        }
        try removeSystemTrashBindingDirectory(name: bindingName, parentFD: parentFD)
        return true
    }

    private func handleSystemTrashFailure(
        _ error: Error,
        systemResult: URL?,
        name: String,
        parentFD: Int32,
        bindingFD: Int32,
        bindingName: String
    ) throws -> Never {
        switch filePresence(name: name, parentFD: bindingFD) {
        case .present:
            if try restoreSystemTrashBinding(
                name: name,
                parentFD: parentFD,
                bindingFD: bindingFD,
                bindingName: bindingName
            ) {
                throw error
            }
            throw SystemTrashMoveError.outcomeUnknown(
                resultingURL: systemResult,
                reason: "Foundation failed and the exact source remains preserved in its binding because the original path is occupied: \(error.localizedDescription)"
            )
        case .absent:
            throw SystemTrashMoveError.outcomeUnknown(
                resultingURL: systemResult,
                reason: error.localizedDescription
            )
        case .inaccessible(let code):
            throw SystemTrashMoveError.outcomeUnknown(
                resultingURL: systemResult,
                reason: "The bound source outcome is inaccessible (errno \(code)): \(error.localizedDescription)"
            )
        }
    }

    private func removeSystemTrashBindingDirectory(
        name: String,
        parentFD: Int32
    ) throws {
        guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 || errno == ENOENT else {
            throw VaultRepositoryError.commitUncertain(
                "The empty system-Trash binding directory could not be removed: \(String(cString: strerror(errno)))."
            )
        }
        guard fsync(parentFD) == 0 else {
            throw VaultRepositoryError.commitUncertain(
                "The system-Trash binding cleanup could not be synchronized."
            )
        }
    }

    private func verifySystemTrashBindingDirectory(
        name: String,
        parentFD: Int32,
        bindingFD: Int32
    ) throws {
        let retainedIdentity = try VaultDescriptorAccess.identity(descriptor: bindingFD)
        guard try entryIdentity(
            name: name,
            parentFD: parentFD,
            expectedDirectory: true
        ) == retainedIdentity else {
            throw VaultRepositoryError.commitUncertain(
                "The transaction-owned system-Trash binding directory changed identity before the native move."
            )
        }
    }

    private func entryIdentity(
        name: String,
        parentFD: Int32,
        expectedDirectory: Bool
    ) throws -> VaultDescriptorAccess.FileIdentity {
        var status = stat()
        guard fstatat(parentFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let expectedMode = expectedDirectory ? S_IFDIR : S_IFREG
        guard (status.st_mode & S_IFMT) == expectedMode else {
            throw VaultRepositoryError.notRegularFile(name)
        }
        return VaultDescriptorAccess.FileIdentity(status)
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
