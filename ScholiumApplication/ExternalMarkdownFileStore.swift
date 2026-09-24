import Darwin
import Foundation
import ScholiumContracts

public enum ExternalMarkdownFileError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedType
    case missing
    case notRegularFile
    case invalidUTF8
    case tooLarge
    case permissionDenied
    case changed
    case closed
    case commitUncertain
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "Choose a Markdown file (.md or .markdown)."
        case .missing: "The original Markdown file is missing."
        case .notRegularFile: "The original is not a regular, unlinked file."
        case .invalidUTF8: "The Markdown file is not valid UTF-8."
        case .tooLarge: "This Markdown file exceeds the 1 MB editor limit."
        case .permissionDenied: "Scholium no longer has permission to access this file."
        case .changed: "The original Markdown file changed. Your edits remain available in the editor."
        case .closed: "This external Markdown session is closed."
        case .commitUncertain:
            "The save could not be verified. Keep the editor open. Check the original; a prior copy may remain in a hidden Scholium file beside it."
        case .io(let description): "The Markdown file could not be accessed: \(description)"
        }
    }
}

public struct ExternalMarkdownFileIdentity: Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let parentDevice: UInt64
    public let parentInode: UInt64

    fileprivate init(file: stat, parent: stat) {
        device = UInt64(file.st_dev)
        inode = UInt64(file.st_ino)
        parentDevice = UInt64(parent.st_dev)
        parentInode = UInt64(parent.st_ino)
    }
}

public struct ExternalMarkdownFileSnapshot: Sendable {
    public let url: URL
    public let source: String
    public let fingerprint: DocumentFingerprint
    public let identity: ExternalMarkdownFileIdentity

    fileprivate let sessionID: UUID

    fileprivate init(url: URL, bytes: Data, identity: ExternalMarkdownFileIdentity, sessionID: UUID) throws {
        guard let source = NoteDocument.decodeUTF8PreservingBOM(bytes) else {
            throw ExternalMarkdownFileError.invalidUTF8
        }
        self.url = url
        self.source = source
        fingerprint = DocumentFingerprint(data: bytes)
        self.identity = identity
        self.sessionID = sessionID
    }
}

/// One authorized original file, separate from Chat's immutable material copy.
/// The caller owns the edited candidate after every failure. The session never
/// stages it in Chat storage or treats a replaced path as the same document.
public actor ExternalMarkdownFileSession {
    public static let maximumBytes = 1_024 * 1_024

    private let url: URL
    private let scope: ExternalMarkdownSecurityScope
    private let sessionID = UUID()
    private var currentIdentity: ExternalMarkdownFileIdentity
    private var isClosed = false
    private var beforeSwapForTesting: (@Sendable (URL) -> Void)?
    private var beforeRollbackForTesting: (@Sendable (URL) -> Void)?

    private init(url: URL, scope: ExternalMarkdownSecurityScope, identity: ExternalMarkdownFileIdentity) {
        self.url = url
        self.scope = scope
        currentIdentity = identity
    }

    /// Keep `session` alive while the external document is open. Call `close()`
    /// when its surface closes to release its security-scoped access promptly.
    public static func open(_ selectedURL: URL) throws -> (session: ExternalMarkdownFileSession, snapshot: ExternalMarkdownFileSnapshot) {
        guard selectedURL.isFileURL,
            ["md", "markdown"].contains(selectedURL.pathExtension.lowercased())
        else { throw ExternalMarkdownFileError.unsupportedType }
        let url = selectedURL.standardizedFileURL
        let scope = ExternalMarkdownSecurityScope(url: selectedURL)
        let read = try coordinatedRead(at: url)
        let session = ExternalMarkdownFileSession(url: url, scope: scope, identity: read.identity)
        let snapshot = try ExternalMarkdownFileSnapshot(
            url: url, bytes: read.bytes, identity: read.identity, sessionID: session.sessionID)
        return (session, snapshot)
    }

    /// Read only the same physical file and parent directory opened originally.
    /// A changed byte revision is returned so the caller can offer an explicit
    /// reload; a replaced path must be reopened with fresh user authority.
    public func load() throws -> ExternalMarkdownFileSnapshot {
        guard !isClosed else { throw ExternalMarkdownFileError.closed }
        let read = try Self.coordinatedRead(at: url)
        guard read.identity == currentIdentity else { throw ExternalMarkdownFileError.changed }
        return try ExternalMarkdownFileSnapshot(
            url: url, bytes: read.bytes, identity: read.identity, sessionID: sessionID)
    }

    /// Manual save of the checked editor buffer. This never accepts a Chat
    /// snapshot as its revision authority, and never modifies the candidate.
    public func save(candidate: String, expected: ExternalMarkdownFileSnapshot) throws -> ExternalMarkdownFileSnapshot {
        guard !isClosed else { throw ExternalMarkdownFileError.closed }
        guard expected.sessionID == sessionID, expected.url == url,
            expected.identity == currentIdentity,
            DocumentFingerprint(content: expected.source) == expected.fingerprint
        else { throw ExternalMarkdownFileError.changed }
        let candidateBytes = Data(candidate.utf8)
        guard candidateBytes.count <= Self.maximumBytes else { throw ExternalMarkdownFileError.tooLarge }
        let expectedBytes = Data(expected.source.utf8)
        if candidateBytes == expectedBytes {
            let current = try Self.coordinatedRead(at: url)
            guard current.identity == expected.identity, current.bytes == expectedBytes else {
                throw ExternalMarkdownFileError.changed
            }
            return expected
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<ExternalMarkdownFileSnapshot, Error>?
        var replacementMayHaveCommitted = false
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard coordinatedURL.standardizedFileURL == url else { throw ExternalMarkdownFileError.changed }
                let saved = try Self.replace(
                    at: url, expected: expectedBytes, identity: expected.identity,
                    candidate: candidateBytes, replacementMayHaveCommitted: &replacementMayHaveCommitted,
                    beforeSwapForTesting: beforeSwapForTesting,
                    beforeRollbackForTesting: beforeRollbackForTesting)
                return try ExternalMarkdownFileSnapshot(
                    url: url, bytes: saved.bytes, identity: saved.identity, sessionID: sessionID)
            }
        }
        if replacementMayHaveCommitted, coordinationError != nil {
            throw ExternalMarkdownFileError.commitUncertain
        }
        if let coordinationError { throw Self.mapped(coordinationError) }
        guard let outcome else { throw ExternalMarkdownFileError.io("File coordination did not run.") }
        let snapshot = try outcome.get()
        currentIdentity = snapshot.identity
        return snapshot
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        scope.close()
    }

    internal func installBeforeSwapTestHook(_ hook: @escaping @Sendable (URL) -> Void) {
        beforeSwapForTesting = hook
    }

    internal func installBeforeRollbackTestHook(_ hook: @escaping @Sendable (URL) -> Void) {
        beforeRollbackForTesting = hook
    }

    private struct ReadResult {
        let bytes: Data
        let identity: ExternalMarkdownFileIdentity
        let mode: mode_t
    }

    private static func coordinatedRead(at url: URL) throws -> ReadResult {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<ReadResult, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard coordinatedURL.standardizedFileURL == url else { throw ExternalMarkdownFileError.changed }
                return try readExact(at: url)
            }
        }
        if let coordinationError { throw mapped(coordinationError) }
        guard let outcome else { throw ExternalMarkdownFileError.io("File coordination did not run.") }
        return try outcome.get()
    }

    private static func readExact(at url: URL) throws -> ReadResult {
        let parentURL = url.deletingLastPathComponent()
        let directory = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw mappedErrno() }
        defer { Darwin.close(directory) }
        let parent = try checkedParent(directory, url: parentURL)
        let name = url.lastPathComponent
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw mappedErrno() }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw mappedErrno() }
        guard (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1 else {
            throw ExternalMarkdownFileError.notRegularFile
        }
        guard before.st_size >= 0, before.st_size <= maximumBytes else {
            throw ExternalMarkdownFileError.tooLarge
        }
        try verifyEntry(directory: directory, name: name, matches: before)
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw mappedErrno() }
            if count == 0 { break }
            guard bytes.count <= maximumBytes - count else { throw ExternalMarkdownFileError.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0 else { throw mappedErrno() }
        guard sameState(before, after), Int(after.st_size) == bytes.count else {
            throw ExternalMarkdownFileError.changed
        }
        try verifyEntry(directory: directory, name: name, matches: after)
        _ = try checkedParent(directory, url: parentURL)
        return ReadResult(bytes: bytes, identity: .init(file: after, parent: parent), mode: after.st_mode & 0o7777)
    }

    private static func replace(
        at url: URL, expected: Data, identity: ExternalMarkdownFileIdentity,
        candidate: Data, replacementMayHaveCommitted: inout Bool,
        beforeSwapForTesting: (@Sendable (URL) -> Void)?,
        beforeRollbackForTesting: (@Sendable (URL) -> Void)?
    ) throws -> ReadResult {
        let parentURL = url.deletingLastPathComponent()
        let directory = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw mappedErrno() }
        defer { Darwin.close(directory) }
        let parent = try checkedParent(directory, url: parentURL)
        guard parent.st_dev == identity.parentDevice, parent.st_ino == identity.parentInode else {
            throw ExternalMarkdownFileError.changed
        }
        let name = url.lastPathComponent
        let current = try readExact(at: url)
        guard current.identity == identity, current.bytes == expected else {
            throw ExternalMarkdownFileError.changed
        }
        let stagingName = ".\(name)-scholium-\(UUID().uuidString.lowercased())"
        let stage = openat(directory, stagingName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard stage >= 0 else { throw mappedErrno() }
        var stageExists = true
        var swapped = false
        defer {
            if stageExists && !swapped && entryMatches(stage, directory: directory, name: stagingName) {
                _ = unlinkat(directory, stagingName, 0)
            }
            Darwin.close(stage)
        }
        let originalDescriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard originalDescriptor >= 0 else { throw mappedErrno() }
        defer { Darwin.close(originalDescriptor) }
        var originalStatus = stat()
        guard fstat(originalDescriptor, &originalStatus) == 0 else { throw mappedErrno() }
        guard ExternalMarkdownFileIdentity(file: originalStatus, parent: parent) == identity else {
            throw ExternalMarkdownFileError.changed
        }
        try candidate.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(stage, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw mappedErrno() }
                offset += count
            }
        }
        // Atomic replacement must preserve user-owned file metadata as well
        // as Markdown bytes. Failure stops before the original is touched.
        guard fcopyfile(originalDescriptor, stage, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw mappedErrno()
        }
        guard fchmod(stage, current.mode) == 0 else { throw mappedErrno() }
        guard fsync(stage) == 0 else { throw mappedErrno() }
        let finalCheck = try readExact(at: url)
        guard finalCheck.identity == identity, finalCheck.bytes == expected else {
            throw ExternalMarkdownFileError.changed
        }
        _ = try checkedParent(directory, url: parentURL)
        guard entryMatches(stage, directory: directory, name: stagingName) else {
            throw ExternalMarkdownFileError.changed
        }
        beforeSwapForTesting?(parentURL.appendingPathComponent(stagingName))
        var stagedEntryAtSwap = stat()
        guard fstatat(directory, stagingName, &stagedEntryAtSwap, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw ExternalMarkdownFileError.changed
        }
        guard renameatx_np(directory, stagingName, directory, name, UInt32(RENAME_SWAP)) == 0 else {
            throw mappedErrno()
        }
        swapped = true
        replacementMayHaveCommitted = true
        if !entryMatches(stage, directory: directory, name: name) {
            // A peer replaced the stage name between its check and the swap.
            // The original is parked at the stage name; swap it back if it is
            // still the file we opened. Leave the peer's entry in its own name.
            beforeRollbackForTesting?(url)
            if entryMatches(originalDescriptor, directory: directory, name: stagingName),
                entryMatches(stagedEntryAtSwap, directory: directory, name: name),
                renameatx_np(directory, stagingName, directory, name, UInt32(RENAME_SWAP)) == 0,
                entryMatches(originalDescriptor, directory: directory, name: name),
                entryMatches(stagedEntryAtSwap, directory: directory, name: stagingName)
            {
                swapped = false
                replacementMayHaveCommitted = false
                throw ExternalMarkdownFileError.changed
            }
            throw ExternalMarkdownFileError.commitUncertain
        }
        do {
            let saved = try readExact(at: url)
            let displaced = try readExact(at: parentURL.appendingPathComponent(stagingName))
            guard saved.bytes == candidate else { throw ExternalMarkdownFileError.commitUncertain }
            if displaced.bytes != expected || displaced.identity != identity {
                // A non-cooperating writer replaced the name after our final
                // check. Restore that writer's file instead of accepting ours.
                guard renameatx_np(directory, stagingName, directory, name, UInt32(RENAME_SWAP)) == 0 else {
                    throw ExternalMarkdownFileError.commitUncertain
                }
                let restored = try readExact(at: url)
                guard restored.bytes == displaced.bytes, restored.identity == displaced.identity else {
                    throw ExternalMarkdownFileError.commitUncertain
                }
                swapped = false
                replacementMayHaveCommitted = false
                throw ExternalMarkdownFileError.changed
            }
            _ = try checkedParent(directory, url: parentURL)
            guard fsync(directory) == 0 else { throw mappedErrno() }
            guard entryMatches(originalDescriptor, directory: directory, name: stagingName) else {
                throw ExternalMarkdownFileError.commitUncertain
            }
            guard unlinkat(directory, stagingName, 0) == 0 else { throw mappedErrno() }
            stageExists = false
            _ = fsync(directory)
            return saved
        } catch let error as ExternalMarkdownFileError where error == .changed {
            throw error
        } catch {
            // The displaced original remains in the staging path whenever
            // post-swap proof fails. Never delete possibly unique source bytes.
            throw ExternalMarkdownFileError.commitUncertain
        }
    }

    private static func entryMatches(_ descriptor: Int32, directory: Int32, name: String) -> Bool {
        var opened = stat()
        var named = stat()
        guard fstat(descriptor, &opened) == 0,
            fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0
        else { return false }
        return (named.st_mode & S_IFMT) == S_IFREG
            && opened.st_dev == named.st_dev && opened.st_ino == named.st_ino
    }

    private static func entryMatches(_ expected: stat, directory: Int32, name: String) -> Bool {
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { return false }
        return expected.st_dev == named.st_dev && expected.st_ino == named.st_ino
            && (expected.st_mode & S_IFMT) == (named.st_mode & S_IFMT)
    }

    private static func checkedParent(_ descriptor: Int32, url: URL) throws -> stat {
        var opened = stat()
        var named = stat()
        guard fstat(descriptor, &opened) == 0 else { throw mappedErrno() }
        guard lstat(url.path, &named) == 0 else { throw mappedErrno() }
        guard (named.st_mode & S_IFMT) == S_IFDIR,
            opened.st_dev == named.st_dev, opened.st_ino == named.st_ino
        else { throw ExternalMarkdownFileError.changed }
        return opened
    }

    private static func verifyEntry(directory: Int32, name: String, matches opened: stat) throws {
        var named = stat()
        guard fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw mappedErrno() }
        guard (named.st_mode & S_IFMT) == S_IFREG,
            named.st_dev == opened.st_dev, named.st_ino == opened.st_ino
        else { throw ExternalMarkdownFileError.changed }
    }

    private static func sameState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func mappedErrno() -> ExternalMarkdownFileError {
        switch errno {
        case ENOENT: .missing
        case EACCES, EPERM: .permissionDenied
        case ELOOP, ENOTDIR, EINVAL: .notRegularFile
        case EFBIG: .tooLarge
        default: .io(String(cString: strerror(errno)))
        }
    }

    private static func mapped(_ error: NSError) -> ExternalMarkdownFileError {
        if error.domain == NSCocoaErrorDomain,
            [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)
        {
            return .permissionDenied
        }
        if error.domain == NSCocoaErrorDomain,
            [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
        {
            return .missing
        }
        return .io(error.localizedDescription)
    }
}

/// The URL itself is the user-granted capability. The session retains its
/// security scope, while an explicit close and deinit both release it once.
private final class ExternalMarkdownSecurityScope: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    func close() {
        lock.lock()
        let shouldStop = started
        started = false
        lock.unlock()
        if shouldStop { url.stopAccessingSecurityScopedResource() }
    }

    deinit { close() }
}
