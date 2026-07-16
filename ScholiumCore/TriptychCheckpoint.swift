import ScholiumContracts
import CryptoKit
import Darwin
import Foundation

enum TriptychCheckpointRestoreFaultPoint: Hashable, Sendable {
    case beforePortableWrite(TriptychCheckpointFileKey)
    case beforePortableMove(TriptychCheckpointFileKey)
}

struct TriptychCheckpointRestoreHooks: Sendable {
    let handler: @Sendable (TriptychCheckpointRestoreFaultPoint) throws -> Void

    static let none = Self { _ in }

    func trigger(_ point: TriptychCheckpointRestoreFaultPoint) throws {
        try handler(point)
    }
}

/// Performs checkpoint mutations relative to an already-open Triptych root.
/// Every traversed directory and final file is opened without following a
/// symbolic link, so an external editor cannot redirect restore work between
/// validation and mutation.
private enum SecureTriptychFileOperations {
    private static let directoryMode = mode_t(0o755)
    private static let fileMode = mode_t(0o600)

    static func atomicWrite(_ data: Data, root: URL, relativePath: String) throws -> Data {
        let components = try validatedComponents(relativePath)
        let rootDescriptor = try openRoot(root, relativePath: relativePath)
        defer { Darwin.close(rootDescriptor) }
        let parentDescriptor = try openParent(
            rootDescriptor: rootDescriptor,
            components: Array(components.dropLast()),
            createDirectories: true,
            relativePath: relativePath
        )
        defer { Darwin.close(parentDescriptor) }

        let leaf = components[components.count - 1]
        var existingMode: mode_t?
        var existing = stat()
        let existingResult = leaf.withCString {
            fstatat(parentDescriptor, $0, &existing, AT_SYMLINK_NOFOLLOW)
        }
        if existingResult == 0 {
            guard (existing.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                throw unsafe(relativePath, "the destination is linked or is not a regular file")
            }
            existingMode = existing.st_mode & mode_t(0o7777)
        } else if errno != ENOENT {
            throw systemFailure(relativePath, operation: "inspect destination")
        }

        let temporaryName = ".scholium-restore-\(UUID().uuidString)"
        let temporaryDescriptor = temporaryName.withCString {
            openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard temporaryDescriptor >= 0 else {
            throw systemFailure(relativePath, operation: "create restore staging file")
        }
        var temporaryExists = true
        defer {
            Darwin.close(temporaryDescriptor)
            if temporaryExists {
                _ = temporaryName.withCString { unlinkat(parentDescriptor, $0, 0) }
            }
        }

        try writeAll(data, descriptor: temporaryDescriptor, relativePath: relativePath)
        if let existingMode, fchmod(temporaryDescriptor, existingMode) != 0 {
            throw systemFailure(relativePath, operation: "preserve file permissions")
        }
        guard fsync(temporaryDescriptor) == 0 else {
            throw systemFailure(relativePath, operation: "flush restored bytes")
        }

        let renameResult = temporaryName.withCString { sourceName in
            leaf.withCString { destinationName in
                renameat(parentDescriptor, sourceName, parentDescriptor, destinationName)
            }
        }
        guard renameResult == 0 else {
            throw systemFailure(relativePath, operation: "commit restored bytes")
        }
        temporaryExists = false

        return try readRegularFile(
            parentDescriptor: parentDescriptor,
            leaf: leaf,
            relativePath: relativePath
        )
    }

    static func moveRegularFile(
        root: URL,
        sourceRelativePath: String,
        destinationRelativePath: String
    ) throws {
        let sourceComponents = try validatedComponents(sourceRelativePath)
        let destinationComponents = try validatedComponents(destinationRelativePath)
        let rootDescriptor = try openRoot(root, relativePath: sourceRelativePath)
        defer { Darwin.close(rootDescriptor) }
        let sourceParent = try openParent(
            rootDescriptor: rootDescriptor,
            components: Array(sourceComponents.dropLast()),
            createDirectories: false,
            relativePath: sourceRelativePath
        )
        defer { Darwin.close(sourceParent) }
        let destinationParent = try openParent(
            rootDescriptor: rootDescriptor,
            components: Array(destinationComponents.dropLast()),
            createDirectories: true,
            relativePath: destinationRelativePath
        )
        defer { Darwin.close(destinationParent) }

        let sourceLeaf = sourceComponents[sourceComponents.count - 1]
        let destinationLeaf = destinationComponents[destinationComponents.count - 1]
        try requireRegularFile(
            parentDescriptor: sourceParent,
            leaf: sourceLeaf,
            relativePath: sourceRelativePath
        )

        var destination = stat()
        let destinationResult = destinationLeaf.withCString {
            fstatat(destinationParent, $0, &destination, AT_SYMLINK_NOFOLLOW)
        }
        if destinationResult == 0 {
            throw VaultRepositoryError.fileAlreadyExists(destinationRelativePath)
        }
        guard errno == ENOENT else {
            throw systemFailure(destinationRelativePath, operation: "inspect Trash destination")
        }

        let renameResult = sourceLeaf.withCString { sourceName in
            destinationLeaf.withCString { destinationName in
                renameatx_np(
                    sourceParent,
                    sourceName,
                    destinationParent,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            if errno == EEXIST {
                throw VaultRepositoryError.fileAlreadyExists(destinationRelativePath)
            }
            throw systemFailure(sourceRelativePath, operation: "move file to Trash")
        }

        do {
            try requireRegularFile(
                parentDescriptor: destinationParent,
                leaf: destinationLeaf,
                relativePath: destinationRelativePath
            )
        } catch {
            _ = destinationLeaf.withCString { destinationName in
                sourceLeaf.withCString { sourceName in
                    renameatx_np(
                        destinationParent,
                        destinationName,
                        sourceParent,
                        sourceName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            throw error
        }
    }

    private static func validatedComponents(_ relativePath: String) throws -> [String] {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
            throw TriptychCheckpointError.invalidRelativePath(relativePath)
        }
        return components
    }

    private static func openRoot(_ root: URL, relativePath: String) throws -> Int32 {
        let selectedRoot = root.standardizedFileURL
        let descriptor = selectedRoot.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw systemFailure(relativePath, operation: "open Triptych root")
        }
        return descriptor
    }

    private static func openParent(
        rootDescriptor: Int32,
        components: [String],
        createDirectories: Bool,
        relativePath: String
    ) throws -> Int32 {
        var current = dup(rootDescriptor)
        guard current >= 0 else {
            throw systemFailure(relativePath, operation: "duplicate Triptych root descriptor")
        }
        do {
            for component in components {
                var next = component.withCString {
                    openat(current, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                if next < 0, errno == ENOENT, createDirectories {
                    let createResult = component.withCString { mkdirat(current, $0, directoryMode) }
                    if createResult != 0, errno != EEXIST {
                        throw systemFailure(relativePath, operation: "create restore directory")
                    }
                    next = component.withCString {
                        openat(current, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                    }
                }
                guard next >= 0 else {
                    throw unsafe(relativePath, "a parent directory is missing, linked, or not a directory")
                }
                Darwin.close(current)
                current = next
            }
            return current
        } catch {
            Darwin.close(current)
            throw error
        }
    }

    private static func requireRegularFile(
        parentDescriptor: Int32,
        leaf: String,
        relativePath: String
    ) throws {
        var metadata = stat()
        let result = leaf.withCString {
            fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0 else {
            throw systemFailure(relativePath, operation: "inspect source file")
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw unsafe(relativePath, "the file is linked or is not a regular file")
        }
    }

    private static func readRegularFile(
        parentDescriptor: Int32,
        leaf: String,
        relativePath: String
    ) throws -> Data {
        let descriptor = leaf.withCString {
            openat(parentDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw systemFailure(relativePath, operation: "open restored file for verification")
        }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw unsafe(relativePath, "the restored destination is linked or is not a regular file")
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw systemFailure(relativePath, operation: "read restored bytes")
            }
            result.append(contentsOf: buffer.prefix(Int(count)))
        }
        return result
    }

    private static func writeAll(_ data: Data, descriptor: Int32, relativePath: String) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    rawBuffer.baseAddress?.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw systemFailure(relativePath, operation: "write restored bytes")
                }
                guard count > 0 else {
                    throw unsafe(relativePath, "the restore staging file accepted no bytes")
                }
                offset += count
            }
        }
    }

    private static func unsafe(_ relativePath: String, _ detail: String) -> TriptychCheckpointError {
        .unsafeRestorePath("\(relativePath): \(detail)")
    }

    private static func systemFailure(_ relativePath: String, operation: String) -> TriptychCheckpointError {
        let code = errno
        return .unsafeRestorePath(
            "\(relativePath): \(operation) failed (\(String(cString: strerror(code))))"
        )
    }
}

/// Stores self-contained Triptych checkpoints outside every research vault.

public actor TriptychCheckpointStore {
    private struct CheckpointIdentityPayload: Decodable {
        let records: [NoteIdentityRecord]
    }

    public nonisolated let triptychID: UUID
    public nonisolated let storageURL: URL

    private let fileManager: FileManager
    private let restoreHooks: TriptychCheckpointRestoreHooks

    public init(
        triptychID: UUID,
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("checkpoints", isDirectory: true)
        self.fileManager = fileManager
        self.restoreHooks = .none
    }

    init(
        triptychID: UUID,
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        restoreHooks: TriptychCheckpointRestoreHooks
    ) {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("checkpoints", isDirectory: true)
        self.fileManager = fileManager
        self.restoreHooks = restoreHooks
    }

    /// Returns the Core-owned checkpoint location after ensuring the app-state
    /// directory exists. Delivery targets may present this URL, but they do
    /// not construct or create checkpoint-store paths themselves.
    public func prepareStorageLocation() throws -> URL {
        try fileManager.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        return storageURL
    }

    @discardableResult
    public func create(
        name requestedName: String,
        kind: TriptychCheckpointKind,
        roots: TriptychRoots
    ) throws -> TriptychCheckpoint {
        try create(
            name: requestedName,
            kind: kind,
            roots: roots,
            pruneAutomaticAfterCreation: true
        )
    }

    private func create(
        name requestedName: String,
        kind: TriptychCheckpointKind,
        roots: TriptychRoots,
        pruneAutomaticAfterCreation: Bool
    ) throws -> TriptychCheckpoint {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw TriptychCheckpointError.invalidName }
        try validateRoots(roots)
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)

        let id = UUID()
        let temporary = storageURL.appendingPathComponent(".creating-\(id.uuidString)", isDirectory: true)
        let destination = storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let snapshot = temporary.appendingPathComponent("snapshot", isDirectory: true)
        try? fileManager.removeItem(at: temporary)

        do {
            try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)
            var files: [TriptychCheckpointFile] = []
            for area in TriptychCheckpointArea.allCases {
                let target = snapshot.appendingPathComponent(area.rawValue, isDirectory: true)
                files.append(contentsOf: try copyTree(
                    from: roots.url(for: area),
                    to: target,
                    area: area
                ))
            }
            files.sort(by: Self.fileOrder)
            let finalInventory = try inventory(roots: roots)
            guard files == finalInventory else {
                let captured = Dictionary(uniqueKeysWithValues: files.map { ($0.key, $0.fingerprint) })
                let observed = Dictionary(uniqueKeysWithValues: finalInventory.map { ($0.key, $0.fingerprint) })
                let changedKey = Set(captured.keys).union(observed.keys).sorted(by: Self.keyOrder).first {
                    captured[$0] != observed[$0]
                }
                let description = changedKey.map { "\($0.area.rawValue)/\($0.relativePath)" }
                    ?? "Triptych inventory"
                throw TriptychCheckpointError.sourceChangedDuringCapture(description)
            }
            let checkpoint = TriptychCheckpoint(
                id: id,
                triptychID: triptychID,
                name: name,
                kind: kind,
                triptychFingerprint: Self.aggregateFingerprint(files),
                files: files
            )
            try encode(checkpoint, to: temporary.appendingPathComponent("metadata.json"))
            try fileManager.moveItem(at: temporary, to: destination)
            if kind == .automatic, pruneAutomaticAfterCreation {
                try pruneAutomaticCheckpoints(preserving: checkpoint.id)
            }
            return checkpoint
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    public func checkpoints() -> [TriptychCheckpoint] {
        listing().checkpoints
    }

    public func listing() -> TriptychCheckpointListing {
        let directories: [URL]
        do {
            directories = try fileManager.contentsOfDirectory(
                at: storageURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            if !fileManager.fileExists(atPath: storageURL.path) {
                return TriptychCheckpointListing(checkpoints: [], unreadableEntries: [])
            }
            return TriptychCheckpointListing(
                checkpoints: [],
                unreadableEntries: ["Checkpoint folder: \(error.localizedDescription)"]
            )
        }
        var checkpoints: [TriptychCheckpoint] = []
        var unreadable: [String] = []
        for directory in directories {
            do {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw TriptychCheckpointError.unsafeRestorePath("\(directory.lastPathComponent): checkpoint entry is not a regular directory")
                }
                let checkpoint = try decode(
                    TriptychCheckpoint.self,
                    from: directory.appendingPathComponent("metadata.json")
                )
                guard checkpoint.schemaVersion == TriptychCheckpoint.currentSchemaVersion,
                      checkpoint.triptychID == triptychID,
                      directory.lastPathComponent == checkpoint.id.uuidString,
                      checkpoint.triptychFingerprint == Self.aggregateFingerprint(checkpoint.files),
                      Set(checkpoint.files.map(\.key)).count == checkpoint.files.count else {
                    throw TriptychCheckpointError.corruptCheckpoint(
                        checkpoint.id,
                        "metadata identity, schema, or inventory does not match"
                    )
                }
                checkpoints.append(checkpoint)
            } catch {
                unreadable.append("\(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
        checkpoints.sort {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
        return TriptychCheckpointListing(
            checkpoints: checkpoints,
            unreadableEntries: unreadable.sorted()
        )
    }

    public func checkpoint(id: UUID) throws -> TriptychCheckpoint {
        let metadata = checkpointURL(id: id).appendingPathComponent("metadata.json")
        guard fileManager.fileExists(atPath: metadata.path) else {
            throw TriptychCheckpointError.invalidCheckpoint(id)
        }
        let metadataValues = try metadata.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard metadataValues.isRegularFile == true, metadataValues.isSymbolicLink != true else {
            throw TriptychCheckpointError.corruptCheckpoint(id, "metadata.json is not a regular local file")
        }
        let checkpoint = try decode(TriptychCheckpoint.self, from: metadata)
        guard checkpoint.schemaVersion == TriptychCheckpoint.currentSchemaVersion,
              checkpoint.id == id else {
            throw TriptychCheckpointError.corruptCheckpoint(id, "metadata identity or schema does not match")
        }
        guard checkpoint.triptychID == triptychID else {
            throw TriptychCheckpointError.wrongTriptych(expected: triptychID, actual: checkpoint.triptychID)
        }
        let keys = checkpoint.files.map(\.key)
        guard Set(keys).count == keys.count else {
            throw TriptychCheckpointError.corruptCheckpoint(id, "the file inventory contains duplicate paths")
        }
        guard checkpoint.triptychFingerprint == Self.aggregateFingerprint(checkpoint.files) else {
            throw TriptychCheckpointError.corruptCheckpoint(id, "the inventory fingerprint does not match")
        }
        for file in checkpoint.files {
            let url = try validatedSnapshotFileURL(checkpointID: id, key: file.key)
            let observed = DocumentFingerprint(data: try Data(contentsOf: url, options: [.mappedIfSafe]))
            guard observed == file.fingerprint else {
                throw TriptychCheckpointError.corruptCheckpoint(
                    id,
                    "stored bytes for \(file.key.area.rawValue)/\(file.key.relativePath) do not match"
                )
            }
        }
        return checkpoint
    }

    /// Removes exactly one automatic checkpoint created by a preparation that
    /// subsequently failed. This is deliberately narrower than retention or
    /// note-purge operations: the metadata identity, Triptych, inventory, and
    /// automatic kind are all validated before one directory is removed.
    @discardableResult
    public func discardAutomaticCheckpoint(id: UUID) throws -> TriptychCheckpoint {
        let checkpoint = try checkpoint(id: id)
        guard checkpoint.kind == .automatic else {
            throw TriptychCheckpointError.cannotDiscardManualCheckpoint(id)
        }
        let destination = checkpointURL(id: id).standardizedFileURL
        guard destination.deletingLastPathComponent() == storageURL.standardizedFileURL,
              destination.lastPathComponent == id.uuidString else {
            throw TriptychCheckpointError.invalidCheckpoint(id)
        }
        let values = try destination.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw TriptychCheckpointError.corruptCheckpoint(
                id,
                "checkpoint entry is linked or is not a directory"
            )
        }
        try fileManager.removeItem(at: destination)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw TriptychCheckpointError.corruptCheckpoint(
                id,
                "automatic checkpoint remained after discard"
            )
        }
        return checkpoint
    }

    /// Permanently invalidates every checkpoint that contains the deleted
    /// note. Scholium removes the complete self-contained checkpoint instead
    /// of rewriting its inventory, identities, and portable associations in
    /// place. A corrupt checkpoint cannot be proven free of the note, so it is
    /// invalidated under the same privacy rule.
    @discardableResult
    public func purgeNoteCopies(
        noteID: UUID,
        area: TriptychCheckpointArea,
        currentRelativePath: String
    ) throws -> [UUID] {
        let prepared = try preparePurgeNoteCopies(
            noteID: noteID,
            area: area,
            currentRelativePath: currentRelativePath,
            additionalKeys: []
        )
        do {
            try applyPreparedCheckpointPurge(prepared)
            try finalizePreparedCheckpointPurge(prepared)
            return prepared.checkpointIDs
        } catch {
            try? rollbackPreparedCheckpointPurge(prepared)
            throw error
        }
    }

    func preparePurgeNoteCopies(
        noteID: UUID,
        area: TriptychCheckpointArea,
        currentRelativePath: String,
        additionalKeys: [TriptychCheckpointFileKey]
    ) throws -> PreparedCheckpointPurge {
        let listing = listing()
        var invalidated: Set<UUID> = []

        for checkpoint in listing.checkpoints {
            let currentKey = TriptychCheckpointFileKey(
                area: area,
                relativePath: currentRelativePath
            )
            let containsCurrentPath = checkpoint.files.contains { $0.key == currentKey }
            let containsStableIdentity: Bool
            do {
                containsStableIdentity = try noteFileKey(
                    checkpointID: checkpoint.id,
                    noteID: noteID,
                    area: area
                ) != nil
            } catch {
                // If identity metadata cannot be interpreted safely, retaining
                // the checkpoint could retain a recoverable deleted note.
                invalidated.insert(checkpoint.id)
                continue
            }
            let containsAdditionalPath = checkpoint.files.contains { additionalKeys.contains($0.key) }
            guard containsCurrentPath || containsStableIdentity || containsAdditionalPath else { continue }
            invalidated.insert(checkpoint.id)
        }

        for unreadable in listing.unreadableEntries {
            let candidate = String(unreadable.prefix { $0 != ":" })
            guard let id = UUID(uuidString: candidate), !invalidated.contains(id) else { continue }
            invalidated.insert(id)
        }

        return PreparedCheckpointPurge(
            stagingID: UUID(),
            checkpointIDs: invalidated.sorted { $0.uuidString < $1.uuidString }
        )
    }

    func applyPreparedCheckpointPurge(_ prepared: PreparedCheckpointPurge) throws {
        guard !prepared.checkpointIDs.isEmpty else { return }
        try fileManager.createDirectory(at: checkpointPurgeURL(prepared), withIntermediateDirectories: true)
        for id in prepared.checkpointIDs {
            let source = checkpointURL(id: id)
            let destination = checkpointPurgeURL(prepared).appendingPathComponent(id.uuidString, isDirectory: true)
            let sourceExists = fileManager.fileExists(atPath: source.path)
            let destinationExists = fileManager.fileExists(atPath: destination.path)
            if destinationExists, !sourceExists { continue }
            guard sourceExists, !destinationExists else {
                throw TriptychCheckpointError.corruptCheckpoint(
                    id,
                    "checkpoint purge staging contains conflicting live and staged copies"
                )
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    func rollbackPreparedCheckpointPurge(_ prepared: PreparedCheckpointPurge) throws {
        for id in prepared.checkpointIDs {
            let source = checkpointPurgeURL(prepared).appendingPathComponent(id.uuidString, isDirectory: true)
            let destination = checkpointURL(id: id)
            let sourceExists = fileManager.fileExists(atPath: source.path)
            let destinationExists = fileManager.fileExists(atPath: destination.path)
            if destinationExists, !sourceExists { continue }
            guard sourceExists, !destinationExists else {
                throw TriptychCheckpointError.corruptCheckpoint(
                    id,
                    "checkpoint rollback found conflicting live and staged copies"
                )
            }
            try fileManager.moveItem(at: source, to: destination)
        }
        let staging = checkpointPurgeURL(prepared)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
    }

    func finalizePreparedCheckpointPurge(_ prepared: PreparedCheckpointPurge) throws {
        let staging = checkpointPurgeURL(prepared)
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
    }

    private func checkpointPurgeURL(_ prepared: PreparedCheckpointPurge) -> URL {
        storageURL.appendingPathComponent(
            ".deleting-\(prepared.stagingID.uuidString)",
            isDirectory: true
        )
    }

    public func comparison(checkpointID: UUID, roots: TriptychRoots) throws -> [TriptychCheckpointChange] {
        let checkpoint = try checkpoint(id: checkpointID)
        let currentFiles = try inventory(roots: roots)
        let checkpointByKey = Dictionary(uniqueKeysWithValues: checkpoint.files.map { ($0.key, $0) })
        let currentByKey = Dictionary(uniqueKeysWithValues: currentFiles.map { ($0.key, $0) })
        var changes: [TriptychCheckpointChange] = []
        var unmatchedCheckpoint = Set(checkpointByKey.keys)
        var unmatchedCurrent = Set(currentByKey.keys)

        for key in Set(checkpointByKey.keys).intersection(currentByKey.keys) {
            guard let old = checkpointByKey[key], let current = currentByKey[key] else { continue }
            changes.append(TriptychCheckpointChange(
                kind: old.fingerprint == current.fingerprint ? .unchanged : .changed,
                area: key.area,
                checkpointPath: key.relativePath,
                currentPath: key.relativePath,
                checkpointFingerprint: old.fingerprint,
                currentFingerprint: current.fingerprint
            ))
            unmatchedCheckpoint.remove(key)
            unmatchedCurrent.remove(key)
        }

        let oldGroups = Dictionary(grouping: unmatchedCheckpoint.compactMap { key in
            checkpointByKey[key].map { (key: key, fingerprint: $0.fingerprint) }
        }, by: \.fingerprint).mapValues { $0.map(\.key) }
        let currentGroups = Dictionary(grouping: unmatchedCurrent.compactMap { key in
            currentByKey[key].map { (key: key, fingerprint: $0.fingerprint) }
        }, by: \.fingerprint).mapValues { $0.map(\.key) }
        for (fingerprint, oldKeys) in oldGroups where oldKeys.count == 1 {
            guard let newKeys = currentGroups[fingerprint], newKeys.count == 1,
                  oldKeys[0].area == newKeys[0].area else { continue }
            let old = oldKeys[0]
            let current = newKeys[0]
            changes.append(TriptychCheckpointChange(
                kind: .moved,
                area: old.area,
                checkpointPath: old.relativePath,
                currentPath: current.relativePath,
                checkpointFingerprint: fingerprint,
                currentFingerprint: fingerprint
            ))
            unmatchedCheckpoint.remove(old)
            unmatchedCurrent.remove(current)
        }

        for key in unmatchedCurrent {
            changes.append(TriptychCheckpointChange(
                kind: .created,
                area: key.area,
                checkpointPath: nil,
                currentPath: key.relativePath,
                checkpointFingerprint: nil,
                currentFingerprint: currentByKey[key]?.fingerprint
            ))
        }
        for key in unmatchedCheckpoint {
            changes.append(TriptychCheckpointChange(
                kind: .deleted,
                area: key.area,
                checkpointPath: key.relativePath,
                currentPath: nil,
                checkpointFingerprint: checkpointByKey[key]?.fingerprint,
                currentFingerprint: nil
            ))
        }
        return changes.sorted(by: Self.changeOrder)
    }

    /// Restores selected checkpoint files or the complete Triptych. A fresh
    /// recovery checkpoint is created before any mutation begins.
    public func restore(
        checkpointID: UUID,
        selection: TriptychCheckpointRestoreSelection,
        roots: TriptychRoots,
        repositories: [WorkspaceVaultSlot: VaultRepository]
    ) async throws -> TriptychCheckpointRestoreResult {
        let selectedCheckpoint = try checkpoint(id: checkpointID)
        // Retention is deliberately deferred until the restore completes. If
        // the researcher selects the oldest of ten automatic checkpoints, the
        // new safety checkpoint would otherwise prune the selected snapshot
        // before its files are read below. A failed restore keeps both recovery
        // sources; the next successful automatic creation reconciles retention.
        let recovery = try create(
            name: "Before Restore",
            kind: .automatic,
            roots: roots,
            pruneAutomaticAfterCreation: false
        )
        let selectedFiles: Set<TriptychCheckpointFileRestore>
        let restoreCompleteTriptych: Bool
        switch selection {
        case .files(let keys):
            selectedFiles = Set(keys.map { TriptychCheckpointFileRestore(source: $0, destination: $0) })
            restoreCompleteTriptych = false
        case .mappedFiles(let files):
            selectedFiles = files
            restoreCompleteTriptych = false
        case .completeTriptych:
            selectedFiles = Set(selectedCheckpoint.files.map {
                TriptychCheckpointFileRestore(source: $0.key, destination: $0.key)
            })
            restoreCompleteTriptych = true
        }
        guard Set(selectedFiles.map(\.destination)).count == selectedFiles.count,
              selectedFiles.allSatisfy({ $0.source.area == $0.destination.area }) else {
            throw TriptychCheckpointError.invalidRelativePath("checkpoint restore mapping")
        }

        var restored: [TriptychCheckpointFileKey] = []
        var trashed: [TriptychCheckpointFileKey] = []
        let selectedByKey = Dictionary(uniqueKeysWithValues: selectedCheckpoint.files.map { ($0.key, $0) })
        for file in selectedFiles.sorted(by: { Self.keyOrder($0.destination, $1.destination) }) {
            guard selectedByKey[file.source] != nil else { continue }
            guard let expected = selectedByKey[file.source] else { continue }
            let source = try validatedSnapshotFileURL(checkpointID: checkpointID, key: file.source)
            let data = try Data(contentsOf: source)
            guard DocumentFingerprint(data: data) == expected.fingerprint else {
                throw TriptychCheckpointError.corruptCheckpoint(
                    checkpointID,
                    "stored bytes changed while restoring \(file.source.area.rawValue)/\(file.source.relativePath)"
                )
            }
            try await restoreFile(data, key: file.destination, roots: roots, repositories: repositories)
            restored.append(file.destination)
        }

        if restoreCompleteTriptych {
            let checkpointKeys = Set(selectedCheckpoint.files.map(\.key))
            for current in try inventory(roots: roots) where !checkpointKeys.contains(current.key) {
                try await moveCreatedFileToTrash(
                    current.key,
                    checkpointName: selectedCheckpoint.name,
                    roots: roots,
                    repositories: repositories
                )
                trashed.append(current.key)
            }
        }
        try pruneAutomaticCheckpoints(preserving: recovery.id)
        return TriptychCheckpointRestoreResult(
            recoveryCheckpoint: recovery,
            restoredFiles: restored,
            movedToTrash: trashed
        )
    }

    public func checkpointURL(id: UUID) -> URL {
        storageURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Returns the exact bytes captured for one file without mutating the
    /// Triptych. Note History uses this for comparison before a selective
    /// restore.
    public func fileData(
        checkpointID: UUID,
        key: TriptychCheckpointFileKey
    ) throws -> Data {
        let checkpoint = try checkpoint(id: checkpointID)
        guard let expected = checkpoint.files.first(where: { $0.key == key })?.fingerprint else {
            throw TriptychCheckpointError.invalidRelativePath(key.relativePath)
        }
        let data = try Data(contentsOf: validatedSnapshotFileURL(checkpointID: checkpointID, key: key))
        guard DocumentFingerprint(data: data) == expected else {
            throw TriptychCheckpointError.corruptCheckpoint(
                checkpointID,
                "stored bytes changed for \(key.area.rawValue)/\(key.relativePath)"
            )
        }
        return data
    }

    /// Resolves the path a stable note identity had when a checkpoint was
    /// captured. This keeps Note History usable after a confirmed rename.
    public func noteFileKey(
        checkpointID: UUID,
        noteID: UUID,
        area: TriptychCheckpointArea
    ) throws -> TriptychCheckpointFileKey? {
        let checkpoint = try checkpoint(id: checkpointID)
        let identitiesKey = TriptychCheckpointFileKey(
            area: .control,
            relativePath: "identities.json"
        )
        guard let identityFile = checkpoint.files.first(where: { $0.key == identitiesKey }) else {
            return nil
        }
        let data = try Data(contentsOf: validatedSnapshotFileURL(
            checkpointID: checkpointID,
            key: identitiesKey
        ))
        guard DocumentFingerprint(data: data) == identityFile.fingerprint else {
            throw TriptychCheckpointError.corruptCheckpoint(
                checkpointID,
                "stored note identities changed after capture"
            )
        }
        // identities.json is written by TriptychControlStore with ISO-8601
        // dates. A default JSONDecoder expects numeric reference-date values
        // and therefore rejected real application checkpoints even though
        // tests using a default JSONEncoder happened to pass.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(CheckpointIdentityPayload.self, from: data)
        guard let record = payload.records.first(where: { $0.id == noteID }) else { return nil }
        let key = TriptychCheckpointFileKey(area: area, relativePath: record.relativePath)
        return checkpoint.files.contains(where: { $0.key == key }) ? key : nil
    }

    /// Restores one captured note into its current stable-identity location.
    /// The source and destination may differ after a rename, but they must stay
    /// in the same Triptych area.
    public func restoreNoteFile(
        checkpointID: UUID,
        sourceKey: TriptychCheckpointFileKey,
        destinationKey: TriptychCheckpointFileKey,
        expectedDestinationRevision: DocumentFingerprint? = nil,
        roots: TriptychRoots,
        repositories: [WorkspaceVaultSlot: VaultRepository]
    ) async throws -> TriptychCheckpointRestoreResult {
        guard sourceKey.area == destinationKey.area else {
            throw TriptychCheckpointError.invalidRelativePath(destinationKey.relativePath)
        }
        let checkpoint = try checkpoint(id: checkpointID)
        guard let sourceRecord = checkpoint.files.first(where: { $0.key == sourceKey }) else {
            throw TriptychCheckpointError.invalidRelativePath(sourceKey.relativePath)
        }
        let sourceURL = try validatedSnapshotFileURL(checkpointID: checkpointID, key: sourceKey)
        let data = try Data(contentsOf: sourceURL)
        guard DocumentFingerprint(data: data) == sourceRecord.fingerprint else {
            throw TriptychCheckpointError.corruptCheckpoint(
                checkpointID,
                "stored bytes changed while restoring \(sourceKey.area.rawValue)/\(sourceKey.relativePath)"
            )
        }

        let recovery = try create(
            name: "Before Restore",
            kind: .automatic,
            roots: roots,
            pruneAutomaticAfterCreation: false
        )
        try await restoreFile(
            data,
            key: destinationKey,
            expectedRevision: expectedDestinationRevision,
            roots: roots,
            repositories: repositories
        )
        try pruneAutomaticCheckpoints(preserving: recovery.id)
        return TriptychCheckpointRestoreResult(
            recoveryCheckpoint: recovery,
            restoredFiles: [destinationKey],
            movedToTrash: []
        )
    }

    private func restoreFile(
        _ data: Data,
        key: TriptychCheckpointFileKey,
        expectedRevision: DocumentFingerprint? = nil,
        roots: TriptychRoots,
        repositories: [WorkspaceVaultSlot: VaultRepository]
    ) async throws {
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data),
              URL(fileURLWithPath: key.relativePath).pathExtension.caseInsensitiveCompare("md") == .orderedSame,
              let slot = key.area.vaultSlot else {
            try writePortableFile(data, key: key, roots: roots)
            return
        }
        guard let repository = repositories[slot] else {
            throw TriptychCheckpointError.repositoryUnavailable(key.area)
        }
        do {
            let current = try await repository.load(relativePath: key.relativePath)
            if let expectedRevision, current.fingerprint != expectedRevision {
                throw VaultRepositoryError.conflict(
                    expected: expectedRevision,
                    current: current.fingerprint
                )
            }
            _ = try await repository.save(
                relativePath: key.relativePath,
                changeSet: .exactContent(content),
                expectedRevision: expectedRevision ?? current.fingerprint
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            guard expectedRevision == nil else {
                throw VaultRepositoryError.fileDoesNotExist(key.relativePath)
            }
            _ = try await repository.create(relativePath: key.relativePath, content: content)
        }
    }

    private func moveCreatedFileToTrash(
        _ key: TriptychCheckpointFileKey,
        checkpointName: String,
        roots: TriptychRoots,
        repositories: [WorkspaceVaultSlot: VaultRepository]
    ) async throws {
        if URL(fileURLWithPath: key.relativePath).pathExtension.caseInsensitiveCompare("md") == .orderedSame,
           let slot = key.area.vaultSlot,
           let repository = repositories[slot] {
            let current = try await repository.load(relativePath: key.relativePath)
            let component = Self.safePathComponent(checkpointName)
            _ = try await repository.move(
                relativePath: key.relativePath,
                to: "Trash/After \(component)/\(key.relativePath)",
                expectedRevision: current.fingerprint
            )
            return
        }

        let component = Self.safePathComponent(checkpointName)
        let destinationPath = "Trash/After \(component)/\(key.relativePath)"
        try restoreHooks.trigger(.beforePortableMove(key))
        try SecureTriptychFileOperations.moveRegularFile(
            root: roots.url(for: key.area),
            sourceRelativePath: key.relativePath,
            destinationRelativePath: destinationPath
        )
    }

    private func writePortableFile(_ data: Data, key: TriptychCheckpointFileKey, roots: TriptychRoots) throws {
        try restoreHooks.trigger(.beforePortableWrite(key))
        let readback = try SecureTriptychFileOperations.atomicWrite(
            data,
            root: roots.url(for: key.area),
            relativePath: key.relativePath
        )
        let expected = DocumentFingerprint(data: data)
        let actual = DocumentFingerprint(data: readback)
        guard expected == actual else {
            throw VaultRepositoryError.readbackMismatch(expected: expected, current: actual)
        }
    }

    private func inventory(roots: TriptychRoots) throws -> [TriptychCheckpointFile] {
        try validateRoots(roots)
        return try TriptychCheckpointArea.allCases.flatMap { area in
            try inventory(root: roots.url(for: area), area: area)
        }.sorted(by: Self.fileOrder)
    }

    private func inventory(root: URL, area: TriptychCheckpointArea) throws -> [TriptychCheckpointFile] {
        var result: [TriptychCheckpointFile] = []
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw TriptychCheckpointError.missingRoot(root.path) }
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw TriptychCheckpointError.symbolicLink(file.path)
            }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            let relativePath = Self.relativePath(of: file, under: root)
            result.append(TriptychCheckpointFile(
                key: TriptychCheckpointFileKey(area: area, relativePath: relativePath),
                fingerprint: DocumentFingerprint(data: try Data(contentsOf: file))
            ))
        }
        return result
    }

    private func copyTree(
        from source: URL,
        to destination: URL,
        area: TriptychCheckpointArea
    ) throws -> [TriptychCheckpointFile] {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let files = try inventory(root: source, area: area)
        for file in files {
            let sourceFile = source.appendingPathComponent(file.key.relativePath)
            let destinationFile = destination.appendingPathComponent(file.key.relativePath)
            try fileManager.createDirectory(at: destinationFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: sourceFile, options: [.mappedIfSafe])
            guard DocumentFingerprint(data: data) == file.fingerprint else {
                throw TriptychCheckpointError.sourceChangedDuringCapture(
                    "\(file.key.area.rawValue)/\(file.key.relativePath)"
                )
            }
            try data.write(to: destinationFile, options: .atomic)
            guard DocumentFingerprint(data: try Data(contentsOf: destinationFile)) == file.fingerprint else {
                throw TriptychCheckpointError.snapshotWriteFailed(
                    "\(file.key.area.rawValue)/\(file.key.relativePath)"
                )
            }
        }
        return files
    }

    private func validateRoots(_ roots: TriptychRoots) throws {
        for area in TriptychCheckpointArea.allCases {
            let url = roots.url(for: area)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw TriptychCheckpointError.missingRoot(url.path)
            }
        }
    }

    private func snapshotFileURL(checkpointID: UUID, key: TriptychCheckpointFileKey) -> URL {
        checkpointURL(id: checkpointID)
            .appendingPathComponent("snapshot", isDirectory: true)
            .appendingPathComponent(key.area.rawValue, isDirectory: true)
            .appendingPathComponent(key.relativePath)
    }

    private func validatedSnapshotFileURL(
        checkpointID: UUID,
        key: TriptychCheckpointFileKey
    ) throws -> URL {
        let components = key.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !key.relativePath.isEmpty,
              !key.relativePath.hasPrefix("/"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw TriptychCheckpointError.corruptCheckpoint(
                checkpointID,
                "the inventory contains an invalid relative path"
            )
        }
        let root = checkpointURL(id: checkpointID)
            .appendingPathComponent("snapshot", isDirectory: true)
            .standardizedFileURL
        let candidate = snapshotFileURL(checkpointID: checkpointID, key: key).standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(prefix), resolved.path.hasPrefix(prefix) else {
            throw TriptychCheckpointError.corruptCheckpoint(checkpointID, "a stored path escapes the snapshot")
        }
        let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw TriptychCheckpointError.corruptCheckpoint(
                checkpointID,
                "\(key.area.rawValue)/\(key.relativePath) is missing, linked, or not a regular file"
            )
        }
        return candidate
    }

    private func pruneAutomaticCheckpoints(preserving preservedID: UUID? = nil) throws {
        let automatic = checkpoints().filter { $0.kind == .automatic }
        guard automatic.count > 10 else { return }
        var retained = Array(automatic.prefix(10))
        if let preservedID,
           !retained.contains(where: { $0.id == preservedID }),
           let preserved = automatic.first(where: { $0.id == preservedID }) {
            retained.removeLast()
            retained.append(preserved)
        }
        let retainedIDs = Set(retained.map(\.id))
        for checkpoint in automatic where !retainedIDs.contains(checkpoint.id) {
            try fileManager.removeItem(at: checkpointURL(id: checkpoint.id))
        }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.timestampString(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.timestampDate(value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 checkpoint timestamp."
            )
        }
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func timestampDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func aggregateFingerprint(_ files: [TriptychCheckpointFile]) -> String {
        let source = files.map {
            "\($0.key.area.rawValue)/\($0.key.relativePath)\u{0}\($0.fingerprint.sha256)\u{0}\($0.fingerprint.byteCount)"
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(of file: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        return String(file.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private static func safePathComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:")
        let parts = value.components(separatedBy: forbidden).filter { !$0.isEmpty }
        return parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fileOrder(_ lhs: TriptychCheckpointFile, _ rhs: TriptychCheckpointFile) -> Bool {
        keyOrder(lhs.key, rhs.key)
    }

    private static func keyOrder(_ lhs: TriptychCheckpointFileKey, _ rhs: TriptychCheckpointFileKey) -> Bool {
        if lhs.area.rawValue == rhs.area.rawValue {
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        return lhs.area.rawValue < rhs.area.rawValue
    }

    private static func changeOrder(_ lhs: TriptychCheckpointChange, _ rhs: TriptychCheckpointChange) -> Bool {
        if lhs.kind.rawValue == rhs.kind.rawValue {
            if lhs.area.rawValue == rhs.area.rawValue {
                return (lhs.currentPath ?? lhs.checkpointPath ?? "") < (rhs.currentPath ?? rhs.checkpointPath ?? "")
            }
            return lhs.area.rawValue < rhs.area.rawValue
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
