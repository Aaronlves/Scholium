import Darwin
import Foundation
import ScholiumContracts

public struct ExactFileReplacementResult: Sendable {
    public let data: Data
    public let preservedOriginalURL: URL?
}

public struct ExactFileReplacementIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let parentDevice: UInt64
    public let parentInode: UInt64

    public init(device: UInt64, inode: UInt64, parentDevice: UInt64, parentInode: UInt64) {
        self.device = device
        self.inode = inode
        self.parentDevice = parentDevice
        self.parentInode = parentInode
    }
}

/// Exact-byte transactions for owned configuration and attachment files.
/// Callers retain object semantics, scope, recovery, and researcher confirmation.
public enum ExactFileReplacement {
    public static func replace(
        at url: URL,
        expected: Data?,
        candidate: Data,
        preserveOriginal: Bool = false,
        preCommitHook: (@Sendable (URL) throws -> Void)? = nil,
        postCommitHook: (@Sendable (URL) throws -> Void)? = nil,
        maximumByteCount: Int = 16 * 1_024 * 1_024,
        expectedIdentity: ExactFileReplacementIdentity? = nil
    ) throws -> ExactFileReplacementResult {
        try replace(
            at: url, expected: expected, candidate: candidate,
            preserveOriginal: preserveOriginal,
            preCommitHook: preCommitHook, postCommitHook: postCommitHook,
            preRollbackHook: nil, maximumByteCount: maximumByteCount, expectedIdentity: expectedIdentity
        )
    }

    /// Deterministic test seam at the rollback race boundary. Production
    /// callers use the public operation, which never supplies this hook.
    static func replace(
        at url: URL,
        expected: Data?,
        candidate: Data,
        preserveOriginal: Bool = false,
        preCommitHook: (@Sendable (URL) throws -> Void)? = nil,
        postCommitHook: (@Sendable (URL) throws -> Void)? = nil,
        preRollbackHook: (@Sendable (URL) throws -> Void)?,
        maximumByteCount: Int = 16 * 1_024 * 1_024,
        expectedIdentity: ExactFileReplacementIdentity? = nil
    ) throws -> ExactFileReplacementResult {
        let parentURL = url.deletingLastPathComponent()
        let directory = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw posixError() }
        defer { Darwin.close(directory) }
        let name = url.lastPathComponent
        guard candidate.count <= maximumByteCount else { throw POSIXError(.EFBIG) }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<ExactFileReplacementResult, Error>?
        var committed = false
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard coordinatedURL.standardizedFileURL == url.standardizedFileURL,
                    directoryMatches(directory, url: parentURL),
                    try readIfPresent(directory: directory, name: name, maximumByteCount: maximumByteCount) == expected,
                    expectedIdentity == nil || identityMatches(expectedIdentity!, directory: directory, name: name)
                else { throw ExactFileReplacementError.revisionConflict }

                var preservedURL: URL?
                var recoveryName: String?
                if preserveOriginal, let expected {
                    let backupName =
                        name == "settings.json"
                        ? "settings.recovery-\(UUID().uuidString.lowercased()).json"
                        : "\(name).recovery-\(UUID().uuidString.lowercased())"
                    try writeExclusive(expected, directory: directory, name: backupName)
                    guard fsync(directory) == 0,
                        try read(directory: directory, name: backupName, maximumByteCount: maximumByteCount) == expected
                    else { throw POSIXError(.EIO) }
                    recoveryName = backupName
                    preservedURL = parentURL.appendingPathComponent(backupName)
                }

                let stagingName = ".\(name)-staging-\(UUID().uuidString.lowercased())"
                var stagingExists = false
                defer { if stagingExists { _ = unlinkat(directory, stagingName, 0) } }
                try writeExclusive(candidate, directory: directory, name: stagingName)
                stagingExists = true
                guard try readIfPresent(directory: directory, name: name, maximumByteCount: maximumByteCount) == expected,
                    expectedIdentity == nil || identityMatches(expectedIdentity!, directory: directory, name: name)
                else {
                    throw ExactFileReplacementError.revisionConflict
                }
                try preCommitHook?(url)
                guard directoryMatches(directory, url: parentURL) else {
                    throw ExactFileReplacementError.revisionConflict
                }
                let flags = UInt32(expected == nil ? RENAME_EXCL : RENAME_SWAP)
                guard renameatx_np(directory, stagingName, directory, name, flags) == 0 else {
                    if errno == EEXIST || errno == ENOENT { throw ExactFileReplacementError.revisionConflict }
                    throw posixError()
                }
                committed = true
                if expected == nil { stagingExists = false }
                do {
                    try postCommitHook?(url)
                    let canonical = try read(directory: directory, name: name, maximumByteCount: maximumByteCount)
                    if let expected {
                        let displaced = try? read(directory: directory, name: stagingName, maximumByteCount: maximumByteCount)
                        guard canonical == candidate, displaced == expected,
                            expectedIdentity == nil || identityMatches(expectedIdentity!, directory: directory, name: stagingName)
                        else {
                            if canonical == candidate {
                                // A second external writer can replace the
                                // candidate after its read. Preserve whatever
                                // this rollback displaces until it is proven.
                                stagingExists = false
                                try preRollbackHook?(url)
                                guard renameatx_np(directory, stagingName, directory, name, UInt32(RENAME_SWAP)) == 0 else {
                                    throw ExactFileReplacementError.commitUncertain(
                                        "Conflict rollback did not complete. Displaced bytes remain in \(stagingName).")
                                }
                                guard try read(directory: directory, name: stagingName, maximumByteCount: maximumByteCount) == candidate,
                                    fsync(directory) == 0,
                                    directoryMatches(directory, url: parentURL)
                                else {
                                    throw ExactFileReplacementError.commitUncertain(
                                        "Conflict rollback could not be proven. Displaced bytes remain in \(stagingName).")
                                }
                                // Only a proven rollback displaced our own
                                // disposable candidate and may clean it up.
                                committed = false
                                stagingExists = true
                                throw ExactFileReplacementError.revisionConflict
                            }
                            throw ExactFileReplacementError.revisionConflict
                        }
                        // Keep the displaced original until preservation is proven.
                        if let recoveryName {
                            guard try read(directory: directory, name: recoveryName, maximumByteCount: maximumByteCount) == expected else {
                                stagingExists = false
                                throw ExactFileReplacementError.commitUncertain("The recovery copy changed. Original bytes remain in \(stagingName).")
                            }
                        }
                    } else {
                        guard canonical == candidate else { throw ExactFileReplacementError.revisionConflict }
                    }
                    guard fsync(directory) == 0 else { throw posixError() }
                    guard directoryMatches(directory, url: parentURL),
                        try read(directory: directory, name: name, maximumByteCount: maximumByteCount) == candidate
                    else { throw ExactFileReplacementError.revisionConflict }
                    if expected != nil {
                        guard unlinkat(directory, stagingName, 0) == 0 else { throw posixError() }
                        stagingExists = false
                        // The replacement was already flushed and verified;
                        // this flush only persists removal of disposable staging.
                        _ = fsync(directory)
                    }
                    return ExactFileReplacementResult(data: candidate, preservedOriginalURL: preservedURL)
                } catch {
                    if !committed { throw error }
                    // Retain the displaced exact original when a committed
                    // swap cannot be proven, including ordinary saves.
                    if expected != nil { stagingExists = false }
                    throw ExactFileReplacementError.commitUncertain(error.localizedDescription)
                }
            }
        }
        if let coordinationError {
            if committed { throw ExactFileReplacementError.commitUncertain(coordinationError.localizedDescription) }
            throw coordinationError
        }
        guard let outcome else { throw POSIXError(.EIO) }
        return try outcome.get()
    }

    private static func directoryMatches(_ descriptor: Int32, url: URL) -> Bool {
        var pinned = stat()
        var live = stat()
        return fstat(descriptor, &pinned) == 0 && lstat(url.path, &live) == 0
            && (live.st_mode & S_IFMT) == S_IFDIR
            && pinned.st_dev == live.st_dev && pinned.st_ino == live.st_ino
    }

    private static func readIfPresent(directory: Int32, name: String, maximumByteCount: Int) throws -> Data? {
        do { return try read(directory: directory, name: name, maximumByteCount: maximumByteCount) } catch let error as POSIXError where error.code == .ENOENT {
            return nil
        }
    }

    static func read(directory: Int32, name: String, maximumByteCount: Int = 16 * 1_024 * 1_024) throws -> Data {
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw posixError() }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
            (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1
        else { throw POSIXError(.EINVAL) }
        guard status.st_size >= 0, status.st_size <= maximumByteCount else { throw POSIXError(.EFBIG) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw posixError() }
            if count == 0 { return data }
            guard data.count <= maximumByteCount - count else { throw POSIXError(.EFBIG) }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeExclusive(_ data: Data, directory: Int32, name: String) throws {
        let descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        var completed = false
        defer {
            Darwin.close(descriptor)
            if !completed { _ = unlinkat(directory, name, 0) }
        }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else { throw posixError() }
        completed = true
    }

    private static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    private static func identityMatches(_ identity: ExactFileReplacementIdentity, directory: Int32, name: String) -> Bool {
        var parent = stat()
        var file = stat()
        return fstat(directory, &parent) == 0 && fstatat(directory, name, &file, AT_SYMLINK_NOFOLLOW) == 0
            && (file.st_mode & S_IFMT) == S_IFREG && file.st_nlink == 1
            && UInt64(parent.st_dev) == identity.parentDevice && UInt64(parent.st_ino) == identity.parentInode
            && UInt64(file.st_dev) == identity.device && UInt64(file.st_ino) == identity.inode
    }
}
