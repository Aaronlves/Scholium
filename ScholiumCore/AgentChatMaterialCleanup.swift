import CryptoKit
import Darwin
import Foundation
import ScholiumContracts
import ScholiumNativeFileOperations
import UniformTypeIdentifiers

/// Explicit cleanup of unreferenced immutable Chat copies. Source files, runtime
/// storage and conversation history are outside this owner's authority. The
/// caller retains reference admission while inspecting and executing a plan.
public enum AgentChatMaterialCleanup {
    private static let maximumBytes = 20 * 1_024 * 1_024
    private static let isolationPrefix = ".chat-material-cleanup-"
    typealias Recycle = (URL, UInt64, UInt64, () throws -> Void) throws -> URL
    enum Checkpoint {
        case beforeIsolation(String)
        case afterIsolation(String)
        case afterTrashReadback(String)
    }

    public static func isRecognizedFileName(_ name: String) -> Bool { materialID(name) != nil }

    public static func inspect(
        rootURL: URL, referencedMaterialIDs: Set<UUID>, expectedHistoryFingerprint: DocumentFingerprint?
    ) throws -> AgentChatMaterialCleanupPlan {
        try Task.checkCancellation()
        let storage = try storage(rootURL)
        let history = try historySnapshot(storage)
        guard history.map({ DocumentFingerprint(sha256: $0.digest, byteCount: Int($0.byteCount)) }) == expectedHistoryFingerprint else {
            throw AgentChatMaterialCleanupError.changed
        }
        let parent: Int32
        do { parent = try storage.openStorageDirectory(createIfMissing: false) } catch SecureRecordDirectoryError.notFound {
            return makePlan(rootURL: storage.directoryURL, identity: nil, history: history, bindings: [], preserved: 0)
        }
        defer { close(parent) }
        let directoryIdentity = try identity(parent)
        var candidates: [AgentChatMaterialCleanupBinding] = []
        var preserved = 0
        for name in try storage.fileNames(parent: parent, includingStaging: true).sorted() {
            try Task.checkCancellation()
            guard let id = materialID(name), !referencedMaterialIDs.contains(id),
                let binding = try? snapshot(parent: parent, name: name)
            else {
                preserved += 1
                continue
            }
            candidates.append(binding)
        }
        try validateRoot(storage, parent: parent, expected: directoryIdentity)
        try validateHistory(storage, expected: history)
        return makePlan(rootURL: storage.directoryURL, identity: directoryIdentity, history: history, bindings: candidates, preserved: preserved)
    }

    public static func cleanup(
        _ plan: AgentChatMaterialCleanupPlan, referencedMaterialIDs: Set<UUID>, expectedHistoryFingerprint: DocumentFingerprint?
    ) throws -> AgentChatMaterialCleanupResult {
        try cleanup(
            plan, referencedMaterialIDs: referencedMaterialIDs, expectedHistoryFingerprint: expectedHistoryFingerprint, recycle: recycle, checkpoint: { _ in })
    }

    static func cleanup(
        _ plan: AgentChatMaterialCleanupPlan, referencedMaterialIDs: Set<UUID>, expectedHistoryFingerprint: DocumentFingerprint?,
        recycle: Recycle, checkpoint: (Checkpoint) throws -> Void = { _ in }
    ) throws -> AgentChatMaterialCleanupResult {
        // Preflight the complete cohort before the first filesystem effect.
        guard try inspect(rootURL: plan.rootURL, referencedMaterialIDs: referencedMaterialIDs, expectedHistoryFingerprint: expectedHistoryFingerprint) == plan
        else {
            throw AgentChatMaterialCleanupError.changed
        }
        guard let rootIdentity = plan.rootIdentity, !plan.bindings.isEmpty else {
            return .init(preservedFiles: plan.preservedFiles, rootURL: plan.rootURL)
        }
        let storage = try storage(plan.rootURL)
        let parent = try storage.openStorageDirectory(createIfMissing: false)
        defer { close(parent) }
        var moved = 0
        var failed = 0
        var uncertain = 0
        var bytes: Int64 = 0
        var preserved = plan.preservedFiles
        var historyChanged = false
        var wasCancelled = false
        var retained: [String] = []
        var destinations: [URL] = []
        var uncertainNames: [String] = []
        for binding in plan.bindings {
            if Task.isCancelled { wasCancelled = true }
            if historyChanged || wasCancelled {
                preserved += 1
                retained.append(binding.fileName)
                continue
            }
            let isolated = isolationPrefix + UUID().uuidString + "-" + originalName(binding.fileName)
            var didIsolate = false
            var didDispatch = false
            var destination: URL?
            do {
                try checkpoint(.beforeIsolation(binding.fileName))
                try validateRoot(storage, parent: parent, expected: rootIdentity)
                try validateHistory(storage, expected: plan.historyBinding)
                guard try snapshot(parent: parent, name: binding.fileName) == binding else {
                    throw AgentChatMaterialCleanupError.changed
                }
                let source = openat(parent, binding.fileName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard source >= 0 else { throw AgentChatMaterialCleanupError.changed }
                defer { close(source) }
                guard try identity(source) == binding.identity else { throw AgentChatMaterialCleanupError.changed }
                guard renameatx_np(parent, binding.fileName, parent, isolated, UInt32(RENAME_EXCL)) == 0 else {
                    throw AgentChatMaterialCleanupError.changed
                }
                didIsolate = true
                let isolatedBinding = try snapshot(parent: parent, name: isolated)
                guard samePayload(isolatedBinding, binding) else { throw AgentChatMaterialCleanupError.changed }
                try checkpoint(.afterIsolation(isolated))
                destination = try recycle(
                    storage.directoryURL.appendingPathComponent(isolated), binding.identity.device, binding.identity.inode
                ) {
                    try validateRoot(storage, parent: parent, expected: rootIdentity)
                    try validateHistory(storage, expected: plan.historyBinding)
                    guard try snapshot(parent: parent, name: isolated) == isolatedBinding else {
                        throw AgentChatMaterialCleanupError.changed
                    }
                    didDispatch = true
                }
                guard let destination else { throw AgentChatMaterialCleanupError.changed }
                guard samePayload(try snapshot(url: destination), binding), absent(parent: parent, name: isolated) else {
                    throw AgentChatMaterialCleanupError.changed
                }
                try checkpoint(.afterTrashReadback(binding.fileName))
                guard samePayload(try snapshot(url: destination), binding), absent(parent: parent, name: isolated) else {
                    throw AgentChatMaterialCleanupError.changed
                }
                try validateRoot(storage, parent: parent, expected: rootIdentity)
                try validateHistory(storage, expected: plan.historyBinding)
                moved += 1
                bytes += binding.byteCount
                destinations.append(destination)
            } catch {
                do { try validateHistory(storage, expected: plan.historyBinding) } catch { historyChanged = true }
                // A returned or missing native source with unverified readback is
                // uncertain. Never retry it, reconstruct it, or delete its bytes.
                let originalStillIsolated = (try? snapshot(parent: parent, name: isolated)).map { samePayload($0, binding) } == true
                if didDispatch, !originalStillIsolated {
                    uncertain += 1
                    uncertainNames.append(binding.fileName)
                    if let destination { destinations.append(destination) }
                    if !absent(parent: parent, name: isolated) { retained.append(isolated) }
                } else {
                    failed += 1
                    if didIsolate {
                        let restored =
                            originalStillIsolated
                            && renameatx_np(parent, isolated, parent, binding.fileName, UInt32(RENAME_EXCL)) == 0
                        retained.append(restored ? binding.fileName : isolated)
                    } else {
                        retained.append(binding.fileName)
                    }
                }
            }
        }
        wasCancelled = wasCancelled || Task.isCancelled
        return .init(
            movedFiles: moved, movedBytes: bytes, preservedFiles: preserved,
            failedFiles: failed, uncertainFiles: uncertain, uncertainFileNames: uncertainNames,
            wasCancelled: wasCancelled, rootURL: plan.rootURL,
            retainedFileNames: retained, resultingTrashURLs: destinations)
    }

    private static func recycle(_ url: URL, _ device: UInt64, _ inode: UInt64, validate: () throws -> Void) throws -> URL {
        var result: NSURL?
        var nativeError: NSError?
        var validationError: Error?
        let moved = ScholiumRecycleItem(
            url.path, device, inode,
            {
                do {
                    try validate()
                    return true
                } catch {
                    validationError = error
                    return false
                }
            }, &result, &nativeError)
        if let validationError { throw validationError }
        guard moved, let result else { throw nativeError ?? CocoaError(.fileWriteUnknown) as NSError }
        return result as URL
    }

    private static func storage(_ root: URL) throws -> SecureRecordDirectory {
        let root = root.standardizedFileURL
        let triptych = root.deletingLastPathComponent()
        let chat = triptych.deletingLastPathComponent()
        guard root.isFileURL, root.lastPathComponent == "Materials", UUID(uuidString: triptych.lastPathComponent) != nil,
            chat.lastPathComponent == "Chat"
        else { throw AgentChatMaterialCleanupError.invalidRoot }
        return SecureRecordDirectory(
            trustedRootURL: chat.deletingLastPathComponent(), components: ["Chat", triptych.lastPathComponent, "Materials"],
            directoryMode: 0o700, fileMode: 0o400, maximumByteCount: maximumBytes)
    }

    private static func originalName(_ name: String) -> String {
        guard name.hasPrefix(isolationPrefix) else { return name }
        let tail = String(name.dropFirst(isolationPrefix.count))
        guard tail.count > 37, UUID(uuidString: String(tail.prefix(36))) != nil, tail.dropFirst(36).first == "-" else { return name }
        return String(tail.dropFirst(37))
    }

    private static func materialID(_ name: String) -> UUID? {
        let name = originalName(name)
        guard name.count > 37, let id = UUID(uuidString: String(name.prefix(36))), name.dropFirst(36).first == "." else { return nil }
        let suffix = String(name.dropFirst(37))
        if suffix.hasPrefix("page-"), suffix.hasSuffix(".png") {
            let number = String(suffix.dropFirst(5).dropLast(4))
            return Int(number).flatMap { $0 > 0 && String($0) == number ? id : nil }
        }
        guard !suffix.contains("."), !suffix.contains("/"), !suffix.contains("\0") else { return nil }
        if ["data", "pdf"].contains(suffix) { return id }
        guard let type = UTType(filenameExtension: suffix), !type.isDynamic,
            type.preferredFilenameExtension == suffix
        else { return nil }
        return id
    }

    private static func identity(_ descriptor: Int32) throws -> AgentChatMaterialCleanupIdentity {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw AgentChatMaterialCleanupError.changed }
        return .init(device: UInt64(bitPattern: Int64(status.st_dev)), inode: UInt64(status.st_ino))
    }

    private static func validateRoot(_ storage: SecureRecordDirectory, parent: Int32, expected: AgentChatMaterialCleanupIdentity) throws {
        let current = try storage.openStorageDirectory(createIfMissing: false)
        defer { close(current) }
        guard try identity(current) == expected, try identity(parent) == expected else { throw AgentChatMaterialCleanupError.changed }
    }

    private static func absent(parent: Int32, name: String) -> Bool {
        var status = stat()
        return fstatat(parent, name, &status, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT
    }

    private static func historySnapshot(_ storage: SecureRecordDirectory) throws -> AgentChatMaterialCleanupBinding? {
        let history = SecureRecordDirectory(
            trustedRootURL: storage.trustedRootURL, components: Array(storage.components.dropLast()),
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 64 * 1_024 * 1_024)
        let parent: Int32
        do { parent = try history.openStorageDirectory(createIfMissing: false) } catch SecureRecordDirectoryError.notFound { return nil }
        defer { close(parent) }
        if absent(parent: parent, name: "conversations.json") { return nil }
        return try snapshot(parent: parent, name: "conversations.json", maximumByteCount: 64 * 1_024 * 1_024)
    }

    private static func validateHistory(_ storage: SecureRecordDirectory, expected: AgentChatMaterialCleanupBinding?) throws {
        guard try historySnapshot(storage) == expected else { throw AgentChatMaterialCleanupError.changed }
    }

    private static func snapshot(url: URL) throws -> AgentChatMaterialCleanupBinding {
        let source = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { throw AgentChatMaterialCleanupError.changed }
        defer { close(source) }
        let result = try snapshot(descriptor: source, name: url.lastPathComponent)
        var current = stat()
        guard lstat(url.path, &current) == 0, binding(name: result.fileName, status: current, digest: result.digest) == result else {
            throw AgentChatMaterialCleanupError.changed
        }
        return result
    }

    private static func snapshot(parent: Int32, name: String, maximumByteCount: Int = maximumBytes) throws -> AgentChatMaterialCleanupBinding {
        let source = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { throw AgentChatMaterialCleanupError.changed }
        defer { close(source) }
        let result = try snapshot(descriptor: source, name: name, maximumByteCount: maximumByteCount)
        var current = stat()
        guard fstatat(parent, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
            binding(name: name, status: current, digest: result.digest) == result
        else { throw AgentChatMaterialCleanupError.changed }
        return result
    }

    private static func snapshot(descriptor: Int32, name: String, maximumByteCount: Int = maximumBytes) throws -> AgentChatMaterialCleanupBinding {
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
            before.st_size >= 0, before.st_size <= maximumByteCount
        else { throw AgentChatMaterialCleanupError.changed }
        var hasher = SHA256()
        var offset = 0
        while true {
            var data = Data(count: min(64 * 1_024, maximumByteCount + 1 - offset))
            let count = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, off_t(offset)) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0, offset + count <= maximumByteCount else { throw AgentChatMaterialCleanupError.changed }
            if count == 0 { break }
            data.count = count
            hasher.update(data: data)
            offset += count
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, SecureRecordDirectory.sameFile(before, after), offset == after.st_size,
            after.st_mode & S_IFMT == S_IFREG, after.st_nlink == 1
        else { throw AgentChatMaterialCleanupError.changed }
        return binding(name: name, status: after, digest: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private static func binding(name: String, status: stat, digest: String) -> AgentChatMaterialCleanupBinding {
        .init(
            fileName: name, identity: .init(device: UInt64(bitPattern: Int64(status.st_dev)), inode: UInt64(status.st_ino)),
            byteCount: Int64(status.st_size), modifiedSeconds: Int64(status.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(status.st_mtimespec.tv_nsec),
            changedSeconds: Int64(status.st_ctimespec.tv_sec), changedNanoseconds: Int64(status.st_ctimespec.tv_nsec), digest: digest)
    }

    private static func samePayload(_ lhs: AgentChatMaterialCleanupBinding, _ rhs: AgentChatMaterialCleanupBinding) -> Bool {
        lhs.identity == rhs.identity && lhs.byteCount == rhs.byteCount && lhs.digest == rhs.digest
            && lhs.modifiedSeconds == rhs.modifiedSeconds && lhs.modifiedNanoseconds == rhs.modifiedNanoseconds
    }

    private static func makePlan(
        rootURL: URL, identity: AgentChatMaterialCleanupIdentity?, history: AgentChatMaterialCleanupBinding?,
        bindings: [AgentChatMaterialCleanupBinding], preserved: Int
    ) -> AgentChatMaterialCleanupPlan {
        let signature =
            String(describing: identity) + String(describing: history)
            + bindings.map { String(describing: $0) }.joined(separator: "\n") + "\n\(preserved)"
        return .init(
            rootURL: rootURL, rootIdentity: identity, historyBinding: history, bindings: bindings, preservedFiles: preserved,
            revision: SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined())
    }
}
