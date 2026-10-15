import Darwin
import Foundation
import ScholiumContracts

/// Read-only original access selected in native Settings. Zotero still owns
/// attachment identity and supplies the current URL; this store authorizes
/// only filesystem access beneath the researcher's explicit grants.
public actor ZoteroOriginalAccessStore {
    private struct Binding: Codable {
        let id: UUID
        let path: String
        let kind: ZoteroOriginalAccessGrant.Kind
        let bookmark: Data
        let device: Int32
        let inode: UInt64
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        var bindings: [Binding]
    }

    private static let fileName = "original-access-v1.json"
    private let directory: SecureRecordDirectory
    /// A synchronous, internal fault seam for substitution at the final read
    /// boundary. Production construction always leaves it nil.
    private let beforeReadbackFault: (@Sendable () throws -> Void)?
    private var coordinationLock: AdvisoryFileLock?

    public init(applicationSupportURL: URL) {
        directory = Self.storageDirectory(applicationSupportURL)
        beforeReadbackFault = nil
    }

    init(applicationSupportURL: URL, beforeReadbackFault: @escaping @Sendable () throws -> Void) {
        directory = Self.storageDirectory(applicationSupportURL)
        self.beforeReadbackFault = beforeReadbackFault
    }

    private static func storageDirectory(_ applicationSupportURL: URL) -> SecureRecordDirectory {
        SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Zotero", "original-access"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 16 * 1_024 * 1_024
        )
    }

    public func grants() throws -> [ZoteroOriginalAccessGrant] {
        let lock = try lock()
        return try lock.withSharedLock {
            try load().bindings.map { binding in
                let available =
                    (try? withResolvedAccess(binding) { _, descriptor in
                        try verifyRoot(descriptor, binding: binding)
                    }) != nil
                return ZoteroOriginalAccessGrant(
                    id: binding.id, path: binding.path, kind: binding.kind,
                    status: available ? .available : .accessRequired
                )
            }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
    }

    /// Called only with the native Open panel's selection. Reauthorization
    /// retains the exact grant identity and location; a different selection is
    /// a separate Add action.
    public func authorize(selectedURL: URL, replacing grantID: UUID? = nil) throws {
        let lock = try lock()
        try lock.withExclusiveLock {
            guard selectedURL.isFileURL, selectedURL.host == nil || selectedURL.host == "localhost" else {
                throw ZoteroOriginalAccessError.invalidSelection
            }
            let values = try selectedURL.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            ])
            guard values.isSymbolicLink != true,
                values.isRegularFile == true || values.isDirectory == true
            else { throw ZoteroOriginalAccessError.invalidSelection }
            let url = selectedURL.resolvingSymlinksInPath().standardizedFileURL
            guard url.path != "/", !url.path.contains("\0") else {
                throw ZoteroOriginalAccessError.invalidSelection
            }
            let kind: ZoteroOriginalAccessGrant.Kind = values.isDirectory == true ? .folder : .file
            var payload = try load()
            let previous = grantID.flatMap { id in payload.bindings.first { $0.id == id } }
            if grantID != nil {
                guard let previous else { throw ZoteroOriginalAccessError.grantMissing }
                guard previous.path == url.path, previous.kind == kind else {
                    throw ZoteroOriginalAccessError.invalidSelection
                }
            }
            guard
                payload.bindings.count < 128 || previous != nil
                    || payload.bindings.contains(where: { $0.path == url.path })
            else { throw ZoteroOriginalAccessError.invalidSelection }
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: [.fileResourceIdentifierKey], relativeTo: nil
            )
            guard !bookmark.isEmpty, bookmark.count <= 1_024 * 1_024 else {
                throw ZoteroOriginalAccessError.invalidSelection
            }
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            let descriptor = try openRoot(path: url.path, kind: kind)
            defer { Darwin.close(descriptor) }
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw posixFailure() }
            let binding = Binding(
                id: previous?.id ?? payload.bindings.first(where: { $0.path == url.path })?.id ?? UUID(),
                path: url.path, kind: kind, bookmark: bookmark,
                device: status.st_dev, inode: status.st_ino
            )
            // A persisted bookmark must already resolve to this exact resource.
            try withResolvedAccess(binding) { _, resolvedDescriptor in
                try verifyRoot(resolvedDescriptor, binding: binding)
            }
            payload.bindings.removeAll { $0.id == binding.id || $0.path == binding.path }
            payload.bindings.append(binding)
            try persist(payload)
        }
    }

    public func remove(grantID: UUID) throws {
        let lock = try lock()
        try lock.withExclusiveLock {
            var payload = try load()
            let count = payload.bindings.count
            payload.bindings.removeAll { $0.id == grantID }
            guard count != payload.bindings.count else { return }
            try persist(payload)
        }
    }

    /// A grant never authorizes a tool-supplied path. The Zotero server calls
    /// this only after resolving an exact attachment through its Local API.
    public func readOriginal(at url: URL, maximumByteCount: Int) throws -> Data {
        try Task.checkCancellation()
        guard url.isFileURL, url.host == nil || url.host == "localhost",
            url.path == url.standardizedFileURL.path,
            maximumByteCount > 0, maximumByteCount <= 20 * 1_024 * 1_024
        else { throw POSIXError(.ELOOP) }
        let lock = try lock()
        return try lock.withSharedLock {
            let bindings = try load().bindings.filter {
                $0.kind == .file ? url.path == $0.path : url.path.hasPrefix($0.path + "/")
            }.sorted { $0.path.count > $1.path.count }
            guard !bindings.isEmpty else { throw CocoaError(.fileReadNoPermission) }
            // Prefer the narrowest live grant; an expired exact-file grant
            // does not invalidate a separately selected parent folder.
            var accessFailure: Error = CocoaError(.fileReadNoPermission)
            for binding in bindings {
                do {
                    return try withResolvedAccess(binding) { _, root in
                        try verifyRoot(root, binding: binding)
                        return try coordinatedRead(url, root: root, binding: binding, maximumByteCount: maximumByteCount)
                    }
                } catch let error as CocoaError where error.code == .fileReadNoPermission {
                    accessFailure = error
                } catch let error as POSIXError where error.code == .EACCES || error.code == .EPERM {
                    accessFailure = error
                }
            }
            throw accessFailure
        }
    }

    private func lock() throws -> AdvisoryFileLock {
        if let coordinationLock { return coordinationLock }
        try directory.ensureDirectories([])
        let created = try AdvisoryFileLock(directory: directory, fileName: "original-access.lock")
        coordinationLock = created
        return created
    }

    private func load() throws -> Payload {
        guard let data = try directory.readIfPresent(directory: nil, fileName: Self.fileName) else {
            return Payload(schemaVersion: 1, bindings: [])
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.schemaVersion == 1, payload.bindings.count <= 128,
            Set(payload.bindings.map(\.id)).count == payload.bindings.count,
            Set(payload.bindings.map(\.path)).count == payload.bindings.count,
            payload.bindings.allSatisfy({
                $0.path.hasPrefix("/") && $0.path != "/" && !$0.path.contains("\0")
                    && $0.path == URL(fileURLWithPath: $0.path).standardizedFileURL.path
                    && !$0.bookmark.isEmpty && $0.bookmark.count <= 1_024 * 1_024
            })
        else { throw ZoteroOriginalAccessError.damagedConfiguration }
        return payload
    }

    private func persist(_ payload: Payload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        if try directory.readIfPresent(directory: nil, fileName: Self.fileName) == nil {
            _ = try directory.createExclusive(data, directory: nil, fileName: Self.fileName)
        } else {
            _ = try directory.replace(data, directory: nil, fileName: Self.fileName)
        }
    }

    private func withResolvedAccess<T>(_ binding: Binding, _ operation: (URL, Int32) throws -> T) throws -> T {
        var stale = false
        guard
            let resolved = try? URL(
                resolvingBookmarkData: binding.bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale
            ), !stale, resolved.standardizedFileURL.path == binding.path
        else {
            throw CocoaError(.fileReadNoPermission)
        }
        let started = resolved.startAccessingSecurityScopedResource()
        defer { if started { resolved.stopAccessingSecurityScopedResource() } }
        let descriptor = try openRoot(path: binding.path, kind: binding.kind)
        defer { Darwin.close(descriptor) }
        return try operation(resolved, descriptor)
    }

    private func openRoot(path: String, kind: ZoteroOriginalAccessGrant.Kind) throws -> Int32 {
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | (kind == .folder ? O_DIRECTORY : 0)
        let descriptor = path.withCString { Darwin.open($0, flags) }
        guard descriptor >= 0 else { throw posixFailure() }
        // F_GETPATH checks the descriptor's actual path after opening, so
        // parent-directory symlink substitution cannot escape the selected root.
        do {
            try verifyDescriptorPath(descriptor, expected: path)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    private func verifyRoot(_ descriptor: Int32, binding: Binding) throws {
        try verifyDescriptorPath(descriptor, expected: binding.path)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw posixFailure() }
        guard status.st_dev == binding.device, status.st_ino == binding.inode,
            status.st_mode & S_IFMT == (binding.kind == .folder ? S_IFDIR : S_IFREG)
        else { throw CocoaError(.fileReadNoPermission) }
    }

    private func coordinatedRead(_ url: URL, root: Int32, binding: Binding, maximumByteCount: Int) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { location in
            result = Result {
                try Task.checkCancellation()
                guard location.standardizedFileURL.path == url.path else { throw POSIXError(.ELOOP) }
                try verifyRoot(root, binding: binding)
                var current = root
                defer { if current != root { Darwin.close(current) } }
                if binding.kind == .folder {
                    current = try openContainedOriginal(url, root: root, binding: binding)
                }
                try verifyDescriptorPath(current, expected: url.path)
                let bytes = try read(current, maximumByteCount: maximumByteCount)
                try beforeReadbackFault?()
                try verifyRoot(root, binding: binding)
                try verifyDescriptorPath(current, expected: url.path)
                let readback =
                    binding.kind == .file
                    ? try openRoot(path: binding.path, kind: binding.kind)
                    : try openContainedOriginal(url, root: root, binding: binding)
                defer { Darwin.close(readback) }
                var originalStatus = stat()
                var readbackStatus = stat()
                guard fstat(current, &originalStatus) == 0, fstat(readback, &readbackStatus) == 0,
                    originalStatus.st_dev == readbackStatus.st_dev,
                    originalStatus.st_ino == readbackStatus.st_ino
                else { throw POSIXError(.EIO) }
                return bytes
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw POSIXError(.EIO) }
        return try result.get()
    }

    private func openContainedOriginal(_ url: URL, root: Int32, binding: Binding) throws -> Int32 {
        let suffix = String(url.path.dropFirst(binding.path.count + 1))
        let components = suffix.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy(Self.safeComponent) else { throw POSIXError(.ELOOP) }
        var current = root
        do {
            for (index, component) in components.enumerated() {
                let isLast = index == components.count - 1
                let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK | (isLast ? 0 : O_DIRECTORY)
                let next = component.withCString { openat(current, $0, flags) }
                guard next >= 0 else { throw posixFailure() }
                if current != root { Darwin.close(current) }
                current = next
            }
            return current
        } catch {
            if current != root { Darwin.close(current) }
            throw error
        }
    }

    private func verifyDescriptorPath(_ descriptor: Int32, expected path: String) throws {
        var actualPath = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = actualPath.withUnsafeMutableBufferPointer { fcntl(descriptor, F_GETPATH, $0.baseAddress!) }
        let observedPath = String(decoding: actualPath.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard result == 0, observedPath == path else { throw POSIXError(.ELOOP) }
    }

    private func read(_ descriptor: Int32, maximumByteCount: Int) throws -> Data {
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw posixFailure() }
        guard before.st_mode & S_IFMT == S_IFREG else { throw POSIXError(.ELOOP) }
        guard before.st_size >= 0, before.st_size <= maximumByteCount else { throw POSIXError(.EFBIG) }
        let expectedCount = Int(before.st_size)
        var data = Data()
        data.reserveCapacity(expectedCount)
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while data.count < expectedCount {
            try Task.checkCancellation()
            let requested = min(buffer.count, expectedCount - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, requested) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw POSIXError(.EIO) }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }
        var extra: UInt8 = 0
        let overflow = Darwin.read(descriptor, &extra, 1)
        var after = stat()
        guard overflow == 0, fstat(descriptor, &after) == 0,
            before.st_dev == after.st_dev, before.st_ino == after.st_ino,
            before.st_size == after.st_size,
            before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
            before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
            before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
            before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        else { throw POSIXError(.EIO) }
        return data
    }

    private static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("\0")
    }

    private func posixFailure() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
