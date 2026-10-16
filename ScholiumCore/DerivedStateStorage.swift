import Darwin
import Foundation
import ScholiumContracts
import os

public enum DerivedStateStorageError: Error, LocalizedError, Equatable {
    case inUse
    case unavailable
    case futurePolicy
    case unrecognizedPolicy

    public var errorDescription: String? {
        switch self {
        case .inUse: "Another active owner is using this local derived state."
        case .unavailable: "Local derived-state storage is unavailable or changed identity."
        case .futurePolicy: "This local index requires a newer Scholium version and has been preserved unchanged."
        case .unrecognizedPolicy: "This local index has an unrecognized policy and has been preserved unchanged."
        }
    }
}

/// Counts only disposable generated files. No source paths or content enter diagnostics.
public struct DerivedStateMaintenanceSummary: Sendable, Equatable {
    public internal(set) var removedFiles = 0
    public internal(set) var removedBytes: Int64 = 0
    public internal(set) var busyDirectories = 0
    public internal(set) var failedDirectories = 0
    public internal(set) var failedFiles = 0
    public internal(set) var preservedFiles = 0

    public init(failedDirectories: Int = 0) { self.failedDirectories = max(0, failedDirectories) }
}

/// One descriptor per borrower. The lock inode is permanent, including after
/// removal of a registration; unlinking it would split cooperating owners.
public final class DerivedStateStorageLease: Sendable {
    private let descriptor: Int32
    private let storage: SecureRecordDirectory
    private let exclusiveAuthority: OSAllocatedUnfairLock<Bool>
    private let didClose: (@Sendable () -> Void)?

    /// The optional, per-owner close observation is used only by ownership tests.
    init(storage: SecureRecordDirectory, exclusive: Bool, wait: Bool = false, didClose: (@Sendable () -> Void)? = nil) throws {
        let openedDescriptor = try storage.openLockFile(DerivedStateStorage.lockFileName)
        do {
            var status = stat()
            guard fstat(openedDescriptor, &status) == 0,
                status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1
            else { throw DerivedStateStorageError.unavailable }
            if status.st_mode & 0o777 != 0o600 {
                guard fchmod(openedDescriptor, 0o600) == 0 else { throw DerivedStateStorageError.unavailable }
            }
            let flags = (exclusive ? LOCK_EX : LOCK_SH) | (wait ? 0 : LOCK_NB)
            while flock(openedDescriptor, flags) != 0 {
                if errno == EINTR { continue }
                if errno == EWOULDBLOCK { throw DerivedStateStorageError.inUse }
                throw DerivedStateStorageError.unavailable
            }
            // Bind the held lock to the current descriptor-relative path too.
            let parent = try storage.openStorageDirectory(createIfMissing: false)
            defer { Darwin.close(parent) }
            var current = stat()
            guard
                DerivedStateStorage.lockFileName.withCString({
                    fstatat(parent, $0, &current, AT_SYMLINK_NOFOLLOW)
                }) == 0, current.st_dev == status.st_dev, current.st_ino == status.st_ino,
                current.st_mode & S_IFMT == S_IFREG, current.st_nlink == 1
            else { throw DerivedStateStorageError.unavailable }
        } catch {
            Darwin.close(openedDescriptor)
            didClose?()
            throw error
        }
        self.storage = storage
        exclusiveAuthority = .init(initialState: exclusive)
        self.didClose = didClose
        descriptor = openedDescriptor
    }

    func downgrade() throws {
        try exclusiveAuthority.withLock { exclusive in
            guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else { throw DerivedStateStorageError.unavailable }
            exclusive = false
        }
    }

    fileprivate func admitWordRemoval() throws {
        try exclusiveAuthority.withLock { exclusive in
            // The permanent Word root is already exclusive. No new job
            // borrower can appear while this completed owner's shared lock
            // is converted to the removal lock on the same descriptor.
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DerivedStateStorageError.inUse }
            exclusive = true
        }
    }

    /// Immutable SQLite inspection is permitted only while this exact exclusive
    /// owner proves no WAL exists. A shared opening must observe the live WAL.
    func inspectSearchPolicy<Value: Sendable>(
        fileName: String, _ inspect: @Sendable (SearchSQLiteDatabase) throws -> Value
    ) throws -> Value {
        try exclusiveAuthority.withLock { exclusive in
            try validateDatabaseFile(fileName, permitsMissing: false)
            try validateDatabaseFile(fileName + "-shm", permitsMissing: true)
            let parent = try storage.openStorageDirectory(createIfMissing: false)
            defer { Darwin.close(parent) }
            var initialMain = stat()
            guard fileName.withCString({ fstatat(parent, $0, &initialMain, AT_SYMLINK_NOFOLLOW) }) == 0 else {
                throw DerivedStateStorageError.unavailable
            }
            var wal = stat()
            let walStatus = (fileName + "-wal").withCString { fstatat(parent, $0, &wal, AT_SYMLINK_NOFOLLOW) }
            let noWAL = walStatus != 0 && errno == ENOENT
            guard noWAL || (walStatus == 0 && wal.st_mode & S_IFMT == S_IFREG && wal.st_nlink == 1) else {
                throw DerivedStateStorageError.unavailable
            }
            let reader = try SearchSQLiteDatabase(
                path: try databasePath(fileName: fileName),
                readOnly: true, immutable: exclusive && noWAL)
            defer { reader.close() }
            let outcome = Result { try inspect(reader) }
            if exclusive && noWAL {
                var finalMain = stat()
                var finalWAL = stat()
                guard fileName.withCString({ fstatat(parent, $0, &finalMain, AT_SYMLINK_NOFOLLOW) }) == 0,
                    SecureRecordDirectory.sameFile(initialMain, finalMain),
                    (fileName + "-wal").withCString({ fstatat(parent, $0, &finalWAL, AT_SYMLINK_NOFOLLOW) }) != 0,
                    errno == ENOENT
                else { throw DerivedStateStorageError.unavailable }
            }
            try validateCurrent()
            return try outcome.get()
        }
    }

    func databasePath(fileName: String) throws -> String {
        try validateCurrent()
        let path = try storage.physicalFilePath(fileName: fileName)
        try validateCurrent()
        return path
    }

    func validateSearchAdmission(fileName: String) throws {
        try validateCurrent()
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        let inventory = DerivedStateStorage.SearchStorageInventory(names: try storage.fileNames(parent: parent, includingStaging: true))
        try validateCurrent()
        guard !inventory.ambiguousOrigins.contains(fileName) else { throw DerivedStateStorageError.unrecognizedPolicy }
    }

    func validateCurrent() throws {
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        try validateLock(in: parent)
    }

    fileprivate func validateLock(in parent: Int32) throws {
        var owned = stat()
        var current = stat()
        guard fstat(descriptor, &owned) == 0,
            DerivedStateStorage.lockFileName.withCString({ fstatat(parent, $0, &current, AT_SYMLINK_NOFOLLOW) }) == 0,
            owned.st_dev == current.st_dev, owned.st_ino == current.st_ino,
            current.st_mode & S_IFMT == S_IFREG, current.st_nlink == 1
        else { throw DerivedStateStorageError.unavailable }
    }

    func validateDatabaseFile(_ name: String, permitsMissing: Bool) throws {
        try validateCurrent()
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        var status = stat()
        let found = name.withCString { fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }
        if found != 0, errno == ENOENT, permitsMissing { return }
        guard found == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
            throw DerivedStateStorageError.unavailable
        }
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        didClose?()
    }
}

/// One generated Word package. Work holds only the job lease; creation and
/// removal share a permanent root lock, so completed job directories can vanish
/// without splitting a live lock inode or retaining empty UUID directories.
public final class ScholiumWordTemporaryDirectory: Sendable {
    public let url: URL
    private let root: SecureRecordDirectory
    private let storage: SecureRecordDirectory
    private let lease: DerivedStateStorageLease
    private let device: dev_t
    private let inode: ino_t

    fileprivate init(root: SecureRecordDirectory, storage: SecureRecordDirectory, lease: DerivedStateStorageLease, status: stat) {
        url = storage.directoryURL
        self.root = root
        self.storage = storage
        self.lease = lease
        device = status.st_dev
        inode = status.st_ino
    }

    public func remove() throws {
        let coordinator = try DerivedStateStorageLease(storage: root, exclusive: true, wait: true)
        defer { withExtendedLifetime(coordinator) {} }
        do {
            let descriptor = try storage.openStorageDirectory(createIfMissing: false)
            defer { Darwin.close(descriptor) }
            var status = stat()
            guard fstat(descriptor, &status) == 0, status.st_dev == device, status.st_ino == inode else {
                throw DerivedStateStorageError.unavailable
            }
        } catch SecureRecordDirectoryError.notFound { return }
        try lease.validateCurrent()
        try lease.admitWordRemoval()
        let result = try DerivedStateStorage.removeWordJob(root: root, storage: storage, coordinator: coordinator, lease: lease, checksCancellation: false)
        guard result.failedFiles == 0, result.preservedFiles == 0 else { throw DerivedStateStorageError.unavailable }
    }
}

/// The single policy for machine-local derived artifacts. Registration/research
/// records and unknown or future formats are outside this owner's deletion set.
public enum DerivedStateStorage {
    static let lockFileName = ".derived-state.lock"
    static let wordTemporaryDirectoryName = "WordExports-v1"

    public static func makeWordTemporaryDirectory(applicationSupportURL: URL) throws -> ScholiumWordTemporaryDirectory {
        try Task.checkCancellation()
        let root = wordTemporaryStorage(applicationSupportURL)
        let coordinator = try DerivedStateStorageLease(storage: root, exclusive: true, wait: true)
        defer { withExtendedLifetime(coordinator) {} }
        let parent = try root.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        try coordinator.validateCurrent()
        let name = UUID().uuidString.lowercased()
        guard name.withCString({ mkdirat(parent, $0, 0o700) }) == 0 else { throw DerivedStateStorageError.unavailable }
        let job = storage(root: root.trustedRootURL, components: root.components + [name])
        let lease = try DerivedStateStorageLease(storage: job, exclusive: false)
        let descriptor = try job.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw DerivedStateStorageError.unavailable }
        try lease.validateCurrent()
        return ScholiumWordTemporaryDirectory(root: root, storage: job, lease: lease, status: status)
    }

    /// Deletes only this format's inactive generated jobs. It never examines
    /// the system temporary directory, a Runtime root, or future Word formats.
    public static func clearWordTemporaryDirectories(applicationSupportURL: URL) throws -> ScholiumStorageClearResult {
        try Task.checkCancellation()
        let root = wordTemporaryStorage(applicationSupportURL)
        do {
            let existing = try root.openStorageDirectory(createIfMissing: false)
            Darwin.close(existing)
        } catch SecureRecordDirectoryError.notFound { return .init() }
        let coordinator: DerivedStateStorageLease
        do { coordinator = try DerivedStateStorageLease(storage: root, exclusive: true) } catch DerivedStateStorageError.inUse {
            return .init(busyDirectories: 1)
        }
        defer { withExtendedLifetime(coordinator) {} }
        let parent = try root.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        var counts = WordRemovalCounts()
        for name in try root.fileNames(parent: parent, includingStaging: true) {
            try Task.checkCancellation()
            if name == lockFileName { continue }
            guard isRecognizedWordJobName(name) else {
                counts.preservedFiles += 1
                continue
            }
            var status = stat()
            guard name.withCString({ fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else {
                counts.failedFiles += 1
                continue
            }
            guard status.st_mode & S_IFMT == S_IFDIR else {
                counts.preservedFiles += 1
                continue
            }
            let job = storage(root: root.trustedRootURL, components: root.components + [name])
            do {
                let existing = try job.openStorageDirectory(createIfMissing: false)
                let names: [String]
                do { names = try job.fileNames(parent: existing, includingStaging: true) } catch {
                    Darwin.close(existing)
                    throw error
                }
                Darwin.close(existing)
                // A crashed mkdir can leave an empty job. A nonempty directory
                // without our lock is not admitted as this format's job.
                guard names.isEmpty || names.contains(lockFileName) else {
                    counts.preservedFiles += 1
                    continue
                }
                let lease = try DerivedStateStorageLease(storage: job, exclusive: true)
                defer { withExtendedLifetime(lease) {} }
                let result = try removeWordJob(root: root, storage: job, coordinator: coordinator, lease: lease)
                counts.add(result)
            } catch DerivedStateStorageError.inUse { counts.busyDirectories += 1 } catch is CancellationError { throw CancellationError() } catch {
                counts.failedFiles += 1
            }
        }
        return counts.result
    }

    static func isRecognizedSearchArtifact(_ name: String) -> Bool { searchArtifact(name) != nil }
    static func isRecognizedCacheStaging(_ name: String) -> Bool { isStaging(name, cache: true) }
    static func isRecognizedWordJobName(_ name: String) -> Bool {
        let value = name.hasPrefix(".word-removing-") ? String(name.dropFirst(".word-removing-".count)) : name
        return UUID(uuidString: value)?.uuidString.lowercased() == value.lowercased()
    }

    private static func wordTemporaryStorage(_ applicationSupportURL: URL) -> SecureRecordDirectory {
        storage(root: applicationSupportURL, components: ["Temporary", wordTemporaryDirectoryName])
    }

    private struct WordRemovalCounts {
        var removedFiles = 0
        var removedBytes: Int64 = 0
        var preservedFiles = 0
        var failedFiles = 0
        var busyDirectories = 0
        var result: ScholiumStorageClearResult {
            .init(
                removedFiles: removedFiles, removedBytes: removedBytes, preservedFiles: preservedFiles, failedFiles: failedFiles,
                busyDirectories: busyDirectories)
        }
        mutating func add(_ result: ScholiumStorageClearResult) {
            removedFiles += result.removedFiles
            addBytes(result.removedBytes)
            preservedFiles += result.preservedFiles
            failedFiles += result.failedFiles
            busyDirectories += result.busyDirectories
        }
        mutating func addBytes(_ count: Int64) {
            let total = removedBytes.addingReportingOverflow(max(0, count))
            removedBytes = total.overflow ? Int64.max : total.partialValue
            if total.overflow { failedFiles += 1 }
        }
    }

    fileprivate static func removeWordJob(
        root: SecureRecordDirectory, storage: SecureRecordDirectory, coordinator: DerivedStateStorageLease, lease: DerivedStateStorageLease,
        checksCancellation: Bool = true
    ) throws -> ScholiumStorageClearResult {
        if checksCancellation { try Task.checkCancellation() }
        try coordinator.validateCurrent()
        try lease.validateCurrent()
        let parent = try root.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        let job = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(job) }
        try lease.validateLock(in: job)
        var status = stat()
        guard fstat(job, &status) == 0 else { throw DerivedStateStorageError.unavailable }
        var remainingEntries = 100_000
        guard try wordTreeIsKnown(job, reader: storage, root: true, depth: 0, remainingEntries: &remainingEntries, checksCancellation: checksCancellation)
        else {
            return .init(preservedFiles: 1)
        }
        let name = storage.components.last!
        let isolated = name.hasPrefix(".word-removing-") ? name : ".word-removing-\(name)"
        if isolated != name {
            guard
                name.withCString({ source in isolated.withCString { destination in renameatx_np(parent, source, parent, destination, UInt32(RENAME_EXCL)) } })
                    == 0
            else {
                throw DerivedStateStorageError.unavailable
            }
        }
        var current = stat()
        guard isolated.withCString({ fstatat(parent, $0, &current, AT_SYMLINK_NOFOLLOW) }) == 0,
            current.st_dev == status.st_dev, current.st_ino == status.st_ino, current.st_mode & S_IFMT == S_IFDIR
        else { throw DerivedStateStorageError.unavailable }
        var counts = WordRemovalCounts()
        do {
            try removeWordContents(job, reader: storage, root: true, depth: 0, counts: &counts, checksCancellation: checksCancellation)
            try coordinator.validateCurrent()
            try lease.validateLock(in: job)
            // Keep the job lock until every payload has been removed. A
            // partial or cancelled cleanup must still block a live borrower.
            var lockStatus = stat()
            guard try storage.fileNames(parent: job, includingStaging: true) == [lockFileName],
                lockFileName.withCString({ fstatat(job, $0, &lockStatus, AT_SYMLINK_NOFOLLOW) }) == 0,
                lockFileName.withCString({ unlinkat(job, $0, 0) }) == 0
            else { throw DerivedStateStorageError.unavailable }
            counts.removedFiles += 1
            counts.addBytes(lockStatus.st_size)
            guard isolated.withCString({ unlinkat(parent, $0, AT_REMOVEDIR) }) == 0, fsync(parent) == 0 else {
                throw DerivedStateStorageError.unavailable
            }
        } catch is CancellationError { throw CancellationError() } catch { counts.failedFiles += 1 }
        return counts.result
    }

    private static func wordTreeIsKnown(
        _ parent: Int32, reader: SecureRecordDirectory, root: Bool, depth: Int, remainingEntries: inout Int, checksCancellation: Bool
    ) throws -> Bool {
        guard depth <= 64 else { return false }
        for name in try reader.fileNames(parent: parent, includingStaging: true) {
            if checksCancellation { try Task.checkCancellation() }
            if root, name == lockFileName { continue }
            remainingEntries -= 1
            guard remainingEntries >= 0 else { return false }
            var status = stat()
            guard name.withCString({ fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else { throw DerivedStateStorageError.unavailable }
            if status.st_mode & S_IFMT == S_IFDIR {
                guard !root || name == "package" else { return false }
                let child = name.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) }
                guard child >= 0 else { throw DerivedStateStorageError.unavailable }
                defer { Darwin.close(child) }
                var opened = stat()
                guard fstat(child, &opened) == 0, opened.st_dev == status.st_dev, opened.st_ino == status.st_ino,
                    try wordTreeIsKnown(
                        child, reader: reader, root: false, depth: depth + 1, remainingEntries: &remainingEntries, checksCancellation: checksCancellation)
                else { return false }
            } else {
                guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
                    !root || ["source.docx", "document.docx", lockFileName].contains(name)
                else { return false }
            }
        }
        return true
    }

    private static func removeWordContents(
        _ parent: Int32, reader: SecureRecordDirectory, root: Bool, depth: Int, counts: inout WordRemovalCounts, checksCancellation: Bool
    ) throws {
        guard depth <= 64 else { throw DerivedStateStorageError.unavailable }
        for name in try reader.fileNames(parent: parent, includingStaging: true) {
            if checksCancellation { try Task.checkCancellation() }
            if root, name == lockFileName { continue }
            var status = stat()
            guard name.withCString({ fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }) == 0 else { throw DerivedStateStorageError.unavailable }
            if status.st_mode & S_IFMT == S_IFDIR {
                guard !root || name == "package" else { throw DerivedStateStorageError.unavailable }
                let child = name.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW) }
                guard child >= 0 else { throw DerivedStateStorageError.unavailable }
                defer { Darwin.close(child) }
                var opened = stat()
                guard fstat(child, &opened) == 0, opened.st_dev == status.st_dev, opened.st_ino == status.st_ino else {
                    throw DerivedStateStorageError.unavailable
                }
                try removeWordContents(child, reader: reader, root: false, depth: depth + 1, counts: &counts, checksCancellation: checksCancellation)
                var linked = stat()
                guard name.withCString({ fstatat(parent, $0, &linked, AT_SYMLINK_NOFOLLOW) }) == 0,
                    linked.st_dev == opened.st_dev, linked.st_ino == opened.st_ino,
                    name.withCString({ unlinkat(parent, $0, AT_REMOVEDIR) }) == 0
                else { throw DerivedStateStorageError.unavailable }
            } else {
                guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
                    !root || ["source.docx", "document.docx", lockFileName].contains(name)
                else { throw DerivedStateStorageError.unavailable }
                guard name.withCString({ unlinkat(parent, $0, 0) }) == 0 else { throw DerivedStateStorageError.unavailable }
                counts.removedFiles += 1
                counts.addBytes(status.st_size)
            }
        }
    }

    public static func vaultCacheLease(applicationSupportURL: URL, vaultID: UUID) throws -> DerivedStateStorageLease {
        try leaseAndRecoverStaging(in: vaultStorage(applicationSupportURL, component: vaultID.uuidString), cache: true)
    }

    static func vaultCacheMutationLease(applicationSupportURL: URL, vaultID: UUID) throws -> DerivedStateStorageLease {
        try DerivedStateStorageLease(storage: vaultStorage(applicationSupportURL, component: vaultID.uuidString), exclusive: false)
    }

    static func searchLease(storage: SecureRecordDirectory) throws -> DerivedStateStorageLease {
        try leaseAndRecoverStaging(in: storage, cache: false, retainExclusive: true)
    }

    static func searchMaintenanceLease(storage: SecureRecordDirectory) throws -> DerivedStateStorageLease {
        try DerivedStateStorageLease(storage: storage, exclusive: true)
    }

    static func publishSearchRecovery(stagingURL: URL, databaseURL: URL, storage: SecureRecordDirectory, lease: DerivedStateStorageLease) throws {
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        try lease.validateCurrent()
        for name in [stagingURL.lastPathComponent, databaseURL.lastPathComponent] {
            var status = stat()
            let found = name.withCString { fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }
            if found != 0, errno == ENOENT, name == databaseURL.lastPathComponent { continue }
            guard found == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
                throw DerivedStateStorageError.unavailable
            }
        }
        let published = stagingURL.lastPathComponent.withCString { source in
            databaseURL.lastPathComponent.withCString { renameat(parent, source, parent, $0) }
        }
        guard published == 0 else { throw DerivedStateStorageError.unavailable }
        for suffix in ["-wal", "-shm"] {
            try lease.validateCurrent()
            let name = databaseURL.lastPathComponent + suffix
            var status = stat()
            let found = name.withCString { fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }
            if found != 0, errno == ENOENT { continue }
            guard found == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1,
                name.withCString({ unlinkat(parent, $0, 0) }) == 0
            else { throw DerivedStateStorageError.unavailable }
        }
        try lease.validateCurrent()
    }

    static func discardSearchStaging(storage: SecureRecordDirectory, lease: DerivedStateStorageLease) {
        var summary = DerivedStateMaintenanceSummary()
        try? removeCandidates(
            in: storage, lease: lease, cache: false, unreferenced: false,
            stagingOnly: true, summary: &summary)
    }

    static func registryLease(storageURL: URL, wait: Bool = true) throws -> DerivedStateStorageLease {
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        return try DerivedStateStorageLease(
            storage: storage(root: storageURL, components: [".registry-coordination"]), exclusive: true, wait: wait)
    }

    /// Only WorkspaceRegistry calls this in production, while its registration
    /// read/modify/write lock owns the exact current reference set.
    static func maintain(
        applicationSupportURL: URL, triptychIDs: Set<UUID>, vaultIDs: Set<UUID>
    ) -> DerivedStateMaintenanceSummary {
        var summary = DerivedStateMaintenanceSummary()
        for (rootName, isCache) in [("Triptychs", false), ("Vaults", true)] {
            let root = storage(root: applicationSupportURL, components: [rootName])
            do {
                let descriptor = try root.openStorageDirectory(createIfMissing: false)
                defer { Darwin.close(descriptor) }
                for component in try root.fileNames(parent: descriptor, includingStaging: true) {
                    guard let id = UUID(uuidString: component), id.uuidString.lowercased() == component.lowercased() else { continue }
                    let target = storage(
                        root: applicationSupportURL,
                        components: [rootName, component, isCache ? "source-projections-v1" : "indexes"])
                    do {
                        // Do not create absent artifact directories during enumeration.
                        let existing = try target.openStorageDirectory(createIfMissing: false)
                        Darwin.close(existing)
                        let lease = try DerivedStateStorageLease(storage: target, exclusive: true)
                        defer { withExtendedLifetime(lease) {} }
                        let referenced = (isCache ? vaultIDs : triptychIDs).contains(id)
                        try removeCandidates(in: target, lease: lease, cache: isCache, unreferenced: !referenced, summary: &summary)
                    } catch SecureRecordDirectoryError.notFound {
                        continue
                    } catch DerivedStateStorageError.inUse {
                        summary.busyDirectories += 1
                    } catch {
                        summary.failedDirectories += 1
                    }
                }
            } catch SecureRecordDirectoryError.notFound {
                continue
            } catch {
                summary.failedDirectories += 1
            }
        }
        return summary
    }

    private static func leaseAndRecoverStaging(in storage: SecureRecordDirectory, cache: Bool, retainExclusive: Bool = false) throws -> DerivedStateStorageLease
    {
        do {
            let exclusive = try DerivedStateStorageLease(storage: storage, exclusive: true)
            var ignored = DerivedStateMaintenanceSummary()
            // An abandoned temporary file never makes a compatible index unusable.
            try? removeCandidates(in: storage, lease: exclusive, cache: cache, unreferenced: false, stagingOnly: true, summary: &ignored)
            if !retainExclusive { try exclusive.downgrade() }
            return exclusive
        } catch DerivedStateStorageError.inUse {
            return try DerivedStateStorageLease(storage: storage, exclusive: false)
        }
    }

    static func isolatedSearchStorage(_ url: URL) -> SecureRecordDirectory {
        let parent = url.deletingLastPathComponent()
        return storage(root: parent.deletingLastPathComponent().resolvingSymlinksInPath(), components: [parent.lastPathComponent])
    }

    static func searchStorage(applicationSupportURL: URL, triptychID: UUID) -> SecureRecordDirectory {
        storage(root: applicationSupportURL.resolvingSymlinksInPath(), components: ["Triptychs", triptychID.uuidString.lowercased(), "indexes"])
    }

    private static func vaultStorage(_ root: URL, component: String) -> SecureRecordDirectory {
        storage(root: root, components: ["Vaults", component, "source-projections-v1"])
    }

    private static func storage(root: URL, components: [String]) -> SecureRecordDirectory {
        SecureRecordDirectory(
            trustedRootURL: root.resolvingSymlinksInPath(), components: components,
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 0)
    }

    private static func removeCandidates(
        in storage: SecureRecordDirectory, lease: DerivedStateStorageLease, cache: Bool, unreferenced: Bool,
        stagingOnly: Bool = false, summary: inout DerivedStateMaintenanceSummary
    ) throws {
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { Darwin.close(parent) }
        var directoryIdentity = stat()
        guard fstat(parent, &directoryIdentity) == 0 else { throw DerivedStateStorageError.unavailable }
        func validateDirectory() throws {
            try lease.validateCurrent()
            let current = try storage.openStorageDirectory(createIfMissing: false)
            defer { Darwin.close(current) }
            var status = stat()
            guard fstat(current, &status) == 0,
                status.st_dev == directoryIdentity.st_dev, status.st_ino == directoryIdentity.st_ino
            else { throw DerivedStateStorageError.unavailable }
        }
        let names = try storage.fileNames(parent: parent, includingStaging: true)
        let existingNames = Set(names)
        let inventory = SearchStorageInventory(names: cache ? [] : names)
        let preserveCurrent: Bool
        if !cache && unreferenced && !inventory.ambiguousOrigins.contains("search-v10.sqlite") {
            preserveCurrent = try preservesUnknownSearchPolicy(storage: storage, lease: lease)
        } else {
            preserveCurrent = false
        }
        var stagingPolicies: [String: Bool] = [:]
        for name in names {
            try Task.checkCancellation()
            if let artifact = inventory.artifacts[name], artifact.requiresPolicy,
                inventory.ambiguousOrigins.contains(artifact.logicalDatabaseName)
            {
                // Decide the entire uncertain cohort before eligibility or
                // policy inspection, so neither cleanup boundary can infer a
                // policy from a main whose WAL was moved independently.
                summary.preservedFiles += 1
                continue
            }
            if preserveCurrent, ["search-v10.sqlite", "search-v10.sqlite-wal", "search-v10.sqlite-shm"].contains(name) {
                summary.preservedFiles += 1
                continue
            }
            let staging = isStaging(name, cache: cache)
            guard staging || (!stagingOnly && isRetired(name, cache: cache, unreferenced: unreferenced)) else { continue }
            try validateDirectory()
            if !cache, staging, let artifact = inventory.artifacts[name] {
                // Keep the existing treatment of known retired versions;
                // only current-policy cohorts need the admission above.
                if !artifact.requiresPolicy,
                    (artifact.isSidecar && (artifact.isWrapped || !existingNames.contains(artifact.actualDatabaseName)))
                        || (artifact.isWrapped && !artifact.isSidecar && inventory.sidecarOrigins.contains(artifact.logicalDatabaseName))
                {
                    summary.preservedFiles += 1
                    continue
                }
                if artifact.requiresPolicy {
                    let databaseName = artifact.actualDatabaseName
                    let preserves: Bool
                    if let cached = stagingPolicies[databaseName] {
                        preserves = cached
                    } else {
                        preserves = try preservesUnknownSearchPolicy(storage: storage, lease: lease, fileName: databaseName)
                        stagingPolicies[databaseName] = preserves
                    }
                    if preserves {
                        summary.preservedFiles += 1
                        continue
                    }
                }
            }
            if cache {
                let records = SecureRecordDirectory(
                    trustedRootURL: storage.trustedRootURL, components: storage.components,
                    directoryMode: storage.directoryMode, fileMode: storage.fileMode,
                    maximumByteCount: SourceProjectionCache.maximumRecordByteCount, fileExtensions: [.json, .plist])
                let bytes: Data
                do { bytes = try records.read(parent: parent, fileName: name) } catch {
                    summary.failedFiles += 1
                    continue
                }
                let reclaimable: Bool
                if staging {
                    reclaimable = SourceProjectionCache.isReclaimableTemporaryRecord(bytes)
                } else if unreferenced || name.hasSuffix(".projection.json") {
                    reclaimable = SourceProjectionCache.isReclaimableRecord(bytes, fileName: name)
                } else {
                    switch SourceProjectionCache.recordPolicy(bytes, fileName: name) {
                    case .retired, .corrupt: reclaimable = true
                    case .current, .unknown: reclaimable = false
                    }
                }
                guard reclaimable else {
                    summary.preservedFiles += 1
                    continue
                }
                try validateDirectory()
            }
            var status = stat()
            let found = name.withCString { fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }
            if found != 0, errno == ENOENT { continue }
            guard found == 0, status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
                throw DerivedStateStorageError.unavailable
            }
            // Rename isolates the selected inode before removal. A leaf swap
            // cannot make us follow a link or delete a different named record.
            let isolated = ".derived-retired-\(UUID().uuidString.lowercased())-\(name)"
            let moved = name.withCString { source in
                isolated.withCString { destination in
                    renameatx_np(parent, source, parent, destination, UInt32(RENAME_EXCL))
                }
            }
            if moved != 0, errno == ENOENT { continue }
            guard moved == 0 else { throw DerivedStateStorageError.unavailable }
            var isolatedStatus = stat()
            let same =
                isolated.withCString { fstatat(parent, $0, &isolatedStatus, AT_SYMLINK_NOFOLLOW) } == 0
                && isolatedStatus.st_dev == status.st_dev && isolatedStatus.st_ino == status.st_ino
                && isolatedStatus.st_mode & S_IFMT == S_IFREG && isolatedStatus.st_nlink == 1
            do {
                try validateDirectory()
                guard same else { throw DerivedStateStorageError.unavailable }
                guard isolated.withCString({ unlinkat(parent, $0, 0) }) == 0 else { throw DerivedStateStorageError.unavailable }
                summary.removedFiles += 1
                summary.removedBytes += max(0, status.st_size)
            } catch {
                _ = isolated.withCString { source in
                    name.withCString { renameatx_np(parent, source, parent, $0, UInt32(RENAME_EXCL)) }
                }
                throw error
            }
        }
    }

    private static func preservesUnknownSearchPolicy(
        storage: SecureRecordDirectory, lease: DerivedStateStorageLease, fileName: String = "search-v10.sqlite"
    ) throws -> Bool {
        try lease.validateCurrent()
        do {
            return try lease.inspectSearchPolicy(fileName: fileName) { database in
                var policy: [Int]?
                do {
                    try database.query(
                        "SELECT schema_version, query_contract_version, tokenizer_policy_version, ranking_policy_version FROM search_index_state WHERE singleton = 1;"
                    ) { row in policy = (0..<4).map { row.int(at: $0) } }
                } catch SearchIndexError.corruptDatabase {
                    return false
                } catch { return true }
                guard let policy, policy.allSatisfy({ $0 >= 1 }) else { return true }
                return zip(
                    policy,
                    [SearchContract.schemaVersion, SearchContract.currentVersion, SearchContract.tokenizerPolicyVersion, SearchContract.rankingPolicyVersion]
                )
                .contains { $0 > $1 }
            }
        } catch SearchIndexError.corruptDatabase {
            return false
        } catch {
            // Missing is normal. Any other unreadable state is nonauthorizing.
            let parent = try storage.openStorageDirectory(createIfMissing: false)
            defer { Darwin.close(parent) }
            var status = stat()
            let found = fileName.withCString { fstatat(parent, $0, &status, AT_SYMLINK_NOFOLLOW) }
            if found != 0, errno == ENOENT { return false }
            return true
        }
    }

    fileprivate struct SearchStorageArtifact {
        let actualDatabaseName: String
        let logicalDatabaseName: String
        let isSidecar: Bool
        let isWrapped: Bool
        let isStaging: Bool
        let requiresPolicy: Bool
    }

    /// The same directory cohort admits SQLite opens and bounds cleanup. A
    /// filename proves a sidecar's association only while its original main
    /// exists and no independently isolated variant of that origin remains.
    fileprivate struct SearchStorageInventory {
        let artifacts: [String: SearchStorageArtifact]
        let sidecarOrigins: Set<String>
        let ambiguousOrigins: Set<String>

        init(names: [String]) {
            let artifacts = Dictionary(uniqueKeysWithValues: names.compactMap { name in DerivedStateStorage.searchArtifact(name).map { (name, $0) } })
            self.artifacts = artifacts
            sidecarOrigins = Set(artifacts.values.filter(\.isSidecar).map(\.logicalDatabaseName))
            ambiguousOrigins = Set(
                Dictionary(grouping: artifacts.values.filter(\.requiresPolicy), by: \.logicalDatabaseName)
                    .compactMap { origin, cohort in
                        guard cohort.contains(where: \.isSidecar) else { return nil as String? }
                        // Isolation gives every file its own UUID, so even
                        // equal wrapper stems do not authorize an association.
                        let wrapped = cohort.contains(where: \.isWrapped)
                        let originalMain = cohort.contains { !$0.isWrapped && !$0.isSidecar }
                        return wrapped || !originalMain ? origin : nil
                    })
        }
    }

    /// Unwrap only our reserved, UUID-bound isolation names. The actual name
    /// remains the policy read target; the embedded old name supplies ownership
    /// classification and possible sidecar origins, never a substitute file.
    private static func searchArtifact(_ name: String) -> SearchStorageArtifact? {
        var logical = name
        var wrapped = false
        while logical.hasPrefix(".derived-retired-") {
            let remainder = String(logical.dropFirst(".derived-retired-".count))
            guard remainder.count > 37, UUID(uuidString: String(remainder.prefix(36))) != nil,
                remainder.dropFirst(36).first == "-"
            else { return nil }
            logical = String(remainder.dropFirst(37))
            wrapped = true
        }
        let sidecar = logical.hasSuffix("-wal") || logical.hasSuffix("-shm")
        let database = sidecar ? String(logical.dropLast(4)) : logical
        let staging: Bool
        if database.hasPrefix(".search-v10-staging-"), database.hasSuffix(".sqlite") {
            guard UUID(uuidString: String(database.dropFirst(".search-v10-staging-".count).dropLast(".sqlite".count))) != nil else {
                return nil
            }
            staging = true
        } else {
            guard (1...10).contains(where: { database == "search-v\($0).sqlite" }) else { return nil }
            staging = false
        }
        return SearchStorageArtifact(
            actualDatabaseName: sidecar ? String(name.dropLast(4)) : name,
            logicalDatabaseName: database, isSidecar: sidecar, isWrapped: wrapped,
            isStaging: staging || wrapped, requiresPolicy: staging || database == "search-v10.sqlite")
    }

    private static func isStaging(_ name: String, cache: Bool) -> Bool {
        if !cache { return searchArtifact(name)?.isStaging == true }
        if name.hasPrefix(".derived-retired-") {
            let remainder = String(name.dropFirst(".derived-retired-".count))
            guard remainder.count > 37, UUID(uuidString: String(remainder.prefix(36))) != nil,
                remainder.dropFirst(36).first == "-"
            else { return false }
            let original = String(remainder.dropFirst(37))
            return isStaging(original, cache: cache) || isRetired(original, cache: cache, unreferenced: true)
        }
        if cache, name.hasPrefix(".scholium-pending-") {
            return UUID(uuidString: String(name.dropFirst(".scholium-pending-".count))) != nil
        }
        for suffix in [".sqlite", ".sqlite-wal", ".sqlite-shm"] where name.hasSuffix(suffix) {
            guard name.hasPrefix(".search-v10-staging-") else { continue }
            return UUID(uuidString: String(name.dropFirst(".search-v10-staging-".count).dropLast(suffix.count))) != nil
        }
        return false
    }

    private static func isRetired(_ name: String, cache: Bool, unreferenced: Bool) -> Bool {
        if cache {
            for suffix in [".projection.json", ".projection.plist", ".catalog.plist"] where name.hasSuffix(suffix) {
                let key = name.dropLast(suffix.count)
                guard key.count == 64, key.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return false }
                return true
            }
            return false
        }
        for version in 1...(unreferenced ? 10 : 9) {
            for suffix in ["", "-wal", "-shm"] where name == "search-v\(version).sqlite\(suffix)" { return true }
        }
        return false
    }
}
