import Foundation
import ScholiumContracts
import Darwin

/// Descriptor-relative package I/O for the researcher-managed Skills root.
/// Opening every path component with `O_NOFOLLOW` rejects a linked `.scholium`
/// or another linked ancestor. All replacement work remains relative to the
/// already-open Skills directory, so swapping a parent path cannot redirect a
/// write into another project or arbitrary filesystem location.
enum SecureResearchSkillPackageIO {
    private static let directoryMode = mode_t(0o700)
    private static let fileMode = mode_t(0o600)

    struct DirectoryIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    static func openSkillsRoot(_ url: URL) throws -> Int32 {
        try openAbsoluteDirectory(url)
    }

    static func openDirectory(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws -> Int32 {
        let descriptor = name.withCString {
            openat(
                parentDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw failure(path, operation: "open directory")
        }
        return descriptor
    }

    static func directoryExists(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws -> Bool {
        var metadata = stat()
        let result = name.withCString {
            fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0, errno == ENOENT { return false }
        guard result == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw failure(path, operation: "inspect directory")
        }
        return true
    }

    static func identity(of descriptor: Int32, path: String) throws -> DirectoryIdentity {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw failure(path, operation: "inspect Skills directory")
        }
        return DirectoryIdentity(device: metadata.st_dev, inode: metadata.st_ino)
    }

    static func pathStillRefersToDirectory(
        _ url: URL,
        identity expected: DirectoryIdentity
    ) throws -> Bool {
        let descriptor = try openAbsoluteDirectory(url)
        defer { Darwin.close(descriptor) }
        return try identity(of: descriptor, path: url.path) == expected
    }

    static func strictPackageSources(
        rootDescriptor: Int32,
        packageID: String
    ) throws -> [String: String] {
        let packageDescriptor = packageID.withCString {
            openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard packageDescriptor >= 0 else {
            throw failure(packageID, operation: "open Researcher Skill package")
        }
        defer { Darwin.close(packageDescriptor) }
        return try strictPackageSources(
            packageDescriptor: packageDescriptor,
            packageID: packageID
        )
    }

    static func createPackage(
        rootDescriptor: Int32,
        packageName: String,
        sources: [String: String]
    ) throws {
        let createResult = packageName.withCString {
            mkdirat(rootDescriptor, $0, directoryMode)
        }
        guard createResult == 0 else {
            throw failure(packageName, operation: "create replacement staging package")
        }
        do {
            let packageDescriptor = packageName.withCString {
                openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard packageDescriptor >= 0 else {
                throw failure(packageName, operation: "open replacement staging package")
            }
            defer { Darwin.close(packageDescriptor) }

            var openedResourceDirectories: [String: Int32] = [:]
            defer {
                for descriptor in openedResourceDirectories.values {
                    Darwin.close(descriptor)
                }
            }
            for relativePath in sources.keys.sorted() {
                guard ResearchSkillMaintenancePath.isAllowed(relativePath),
                      let source = sources[relativePath] else {
                    throw ResearchSkillMaintenanceError.invalidResourcePath(relativePath)
                }
                let components = relativePath.split(separator: "/").map(String.init)
                let parentDescriptor: Int32
                let leaf: String
                if components.count == 1 {
                    parentDescriptor = packageDescriptor
                    leaf = components[0]
                } else {
                    let directory = components[0]
                    if let existing = openedResourceDirectories[directory] {
                        parentDescriptor = existing
                    } else {
                        let result = directory.withCString {
                            mkdirat(packageDescriptor, $0, directoryMode)
                        }
                        guard result == 0 || errno == EEXIST else {
                            throw failure(relativePath, operation: "create resource directory")
                        }
                        let descriptor = directory.withCString {
                            openat(
                                packageDescriptor,
                                $0,
                                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                            )
                        }
                        guard descriptor >= 0 else {
                            throw failure(relativePath, operation: "open resource directory")
                        }
                        openedResourceDirectories[directory] = descriptor
                        parentDescriptor = descriptor
                    }
                    leaf = components[1]
                }
                let descriptor = leaf.withCString {
                    openat(
                        parentDescriptor,
                        $0,
                        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                        fileMode
                    )
                }
                guard descriptor >= 0 else {
                    throw failure(relativePath, operation: "create replacement resource")
                }
                do {
                    try writeAll(Data(source.utf8), descriptor: descriptor, path: relativePath)
                    guard fsync(descriptor) == 0 else {
                        throw failure(relativePath, operation: "flush replacement resource")
                    }
                    Darwin.close(descriptor)
                } catch {
                    Darwin.close(descriptor)
                    throw error
                }
            }
            _ = try strictPackageSources(
                packageDescriptor: packageDescriptor,
                packageID: packageName
            )
        } catch {
            try? removePackage(rootDescriptor: rootDescriptor, packageName: packageName)
            throw error
        }
    }

    static func swapPackages(
        rootDescriptor: Int32,
        first: String,
        second: String
    ) throws {
        let result = first.withCString { firstName in
            second.withCString { secondName in
                renameatx_np(
                    rootDescriptor,
                    firstName,
                    rootDescriptor,
                    secondName,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard result == 0 else {
            throw failure(first, operation: "atomically exchange Researcher Skill packages")
        }
    }

    static func movePackageExclusively(
        rootDescriptor: Int32,
        source: String,
        destination: String
    ) throws {
        let result = source.withCString { sourceName in
            destination.withCString { destinationName in
                renameatx_np(
                    rootDescriptor,
                    sourceName,
                    rootDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw failure(destination, operation: "install missing Researcher Skill package")
        }
    }

    static func moveEntryExclusively(
        sourceParentDescriptor: Int32,
        source: String,
        destinationParentDescriptor: Int32,
        destination: String
    ) throws {
        let result = source.withCString { sourceName in
            destination.withCString { destinationName in
                renameatx_np(
                    sourceParentDescriptor,
                    sourceName,
                    destinationParentDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw failure(destination, operation: "archive displaced Working Method state")
        }
    }

    static func removePackage(rootDescriptor: Int32, packageName: String) throws {
        let packageDescriptor = packageName.withCString {
            openat(rootDescriptor, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        if packageDescriptor < 0, errno == ENOENT { return }
        guard packageDescriptor >= 0 else {
            throw failure(packageName, operation: "open obsolete package for removal")
        }
        var packageDescriptorIsOpen = true
        defer {
            if packageDescriptorIsOpen { Darwin.close(packageDescriptor) }
        }

        for name in try entryNames(descriptor: packageDescriptor, path: packageName) {
            var metadata = stat()
            let result = name.withCString {
                fstatat(packageDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
            }
            guard result == 0 else {
                throw failure("\(packageName)/\(name)", operation: "inspect obsolete package")
            }
            let kind = metadata.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFREG) {
                guard name.withCString({ unlinkat(packageDescriptor, $0, 0) }) == 0 else {
                    throw failure("\(packageName)/\(name)", operation: "remove obsolete resource")
                }
            } else if kind == mode_t(S_IFDIR) {
                let resourceDescriptor = name.withCString {
                    openat(
                        packageDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                    )
                }
                guard resourceDescriptor >= 0 else {
                    throw failure("\(packageName)/\(name)", operation: "open obsolete resource directory")
                }
                do {
                    for resource in try entryNames(
                        descriptor: resourceDescriptor,
                        path: "\(packageName)/\(name)"
                    ) {
                        var resourceMetadata = stat()
                        let inspect = resource.withCString {
                            fstatat(resourceDescriptor, $0, &resourceMetadata, AT_SYMLINK_NOFOLLOW)
                        }
                        guard inspect == 0,
                              (resourceMetadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                              resource.withCString({ unlinkat(resourceDescriptor, $0, 0) }) == 0 else {
                            throw failure(
                                "\(packageName)/\(name)/\(resource)",
                                operation: "remove obsolete resource"
                            )
                        }
                    }
                    Darwin.close(resourceDescriptor)
                } catch {
                    Darwin.close(resourceDescriptor)
                    throw error
                }
                guard name.withCString({ unlinkat(packageDescriptor, $0, AT_REMOVEDIR) }) == 0 else {
                    throw failure("\(packageName)/\(name)", operation: "remove obsolete resource directory")
                }
            } else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(
                    "\(packageName)/\(name)"
                )
            }
        }
        Darwin.close(packageDescriptor)
        packageDescriptorIsOpen = false
        guard packageName.withCString({ unlinkat(rootDescriptor, $0, AT_REMOVEDIR) }) == 0 else {
            throw failure(packageName, operation: "remove obsolete package")
        }
    }

    static func strictPackageSources(
        packageDescriptor: Int32,
        packageID: String
    ) throws -> [String: String] {
        var sources: [String: String] = [:]
        for name in try entryNames(descriptor: packageDescriptor, path: packageID) {
            guard !name.hasPrefix(".") else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(name)
            }
            var metadata = stat()
            let inspect = name.withCString {
                fstatat(packageDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
            }
            guard inspect == 0 else {
                throw failure("\(packageID)/\(name)", operation: "inspect package entry")
            }
            let kind = metadata.st_mode & mode_t(S_IFMT)
            if name == "SKILL.md" {
                guard kind == mode_t(S_IFREG) else {
                    throw ResearchSkillMaintenanceError.invalidResourcePath(name)
                }
                sources[name] = try readUTF8File(
                    parentDescriptor: packageDescriptor,
                    leaf: name,
                    path: "\(packageID)/\(name)"
                )
                continue
            }
            guard ["references", "templates", "evals"].contains(name),
                  kind == mode_t(S_IFDIR) else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(name)
            }
            let resourceDescriptor = name.withCString {
                openat(
                    packageDescriptor,
                    $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
            guard resourceDescriptor >= 0 else {
                throw failure("\(packageID)/\(name)", operation: "open package resource directory")
            }
            do {
                for resource in try entryNames(
                    descriptor: resourceDescriptor,
                    path: "\(packageID)/\(name)"
                ) {
                    let relativePath = "\(name)/\(resource)"
                    var resourceMetadata = stat()
                    let result = resource.withCString {
                        fstatat(resourceDescriptor, $0, &resourceMetadata, AT_SYMLINK_NOFOLLOW)
                    }
                    guard result == 0,
                          ResearchSkillMaintenancePath.isAllowed(relativePath),
                          (resourceMetadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
                        throw ResearchSkillMaintenanceError.invalidResourcePath(relativePath)
                    }
                    sources[relativePath] = try readUTF8File(
                        parentDescriptor: resourceDescriptor,
                        leaf: resource,
                        path: "\(packageID)/\(relativePath)"
                    )
                }
                Darwin.close(resourceDescriptor)
            } catch {
                Darwin.close(resourceDescriptor)
                throw error
            }
        }
        guard sources["SKILL.md"] != nil else {
            throw ResearchSkillMaintenanceError.missingEntryPoint
        }
        return sources
    }

    static func openAbsoluteDirectory(_ url: URL) throws -> Int32 {
        let path = platformCanonicalPath(url.standardizedFileURL.path)
        guard path.hasPrefix("/") else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard current >= 0 else {
            throw failure(path, operation: "open filesystem root")
        }
        do {
            for component in (path as NSString).pathComponents where component != "/" {
                let next = component.withCString {
                    openat(current, $0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                guard next >= 0 else {
                    throw failure(path, operation: "open nonlinked Skills ancestor")
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

    private static func platformCanonicalPath(_ path: String) -> String {
        for (alias, destination) in [
            ("/var", "/private/var"),
            ("/tmp", "/private/tmp"),
            ("/etc", "/private/etc"),
        ] where path == alias || path.hasPrefix(alias + "/") {
            return destination + path.dropFirst(alias.count)
        }
        return path
    }

    static func entryNames(descriptor: Int32, path: String) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw failure(path, operation: "enumerate package directory")
        }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }
            if name != "." && name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw failure(path, operation: "enumerate package directory")
        }
        return names.sorted()
    }

    static func readDataFile(
        parentDescriptor: Int32,
        leaf: String,
        path: String,
        maximumByteCount: Int? = nil
    ) throws -> Data {
        let descriptor = leaf.withCString {
            openat(parentDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw failure(path, operation: "open package resource")
        }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        if let maximumByteCount,
           metadata.st_size > off_t(maximumByteCount) {
            throw failure(path, operation: "read bounded data file")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw failure(path, operation: "read package resource")
            }
            if let maximumByteCount,
               data.count + Int(count) > maximumByteCount {
                throw failure(path, operation: "read bounded data file")
            }
            data.append(contentsOf: buffer.prefix(Int(count)))
        }
        return data
    }

    static func dataFileIfPresent(
        parentDescriptor: Int32,
        leaf: String,
        path: String,
        maximumByteCount: Int? = nil
    ) throws -> Data? {
        var metadata = stat()
        let result = leaf.withCString {
            fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0, errno == ENOENT { return nil }
        guard result == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw failure(path, operation: "inspect data file")
        }
        return try readDataFile(
            parentDescriptor: parentDescriptor,
            leaf: leaf,
            path: path,
            maximumByteCount: maximumByteCount
        )
    }

    static func createDataFile(
        parentDescriptor: Int32,
        leaf: String,
        data: Data,
        path: String
    ) throws {
        let descriptor = leaf.withCString {
            openat(
                parentDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                fileMode
            )
        }
        guard descriptor >= 0 else {
            throw failure(path, operation: "create data file")
        }
        do {
            try writeAll(data, descriptor: descriptor, path: path)
            guard fsync(descriptor) == 0 else {
                throw failure(path, operation: "flush data file")
            }
            Darwin.close(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func removeDataFile(
        parentDescriptor: Int32,
        leaf: String,
        path: String
    ) throws {
        var metadata = stat()
        let inspect = leaf.withCString {
            fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if inspect != 0, errno == ENOENT { return }
        guard inspect == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              leaf.withCString({ unlinkat(parentDescriptor, $0, 0) }) == 0 else {
            throw failure(path, operation: "remove data file")
        }
    }

    static func readUTF8File(
        parentDescriptor: Int32,
        leaf: String,
        path: String
    ) throws -> String {
        let data = try readDataFile(
            parentDescriptor: parentDescriptor,
            leaf: leaf,
            path: path
        )
        guard let source = String(data: data, encoding: .utf8) else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        return source
    }

    private static func writeAll(_ data: Data, descriptor: Int32, path: String) throws {
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
                    throw failure(path, operation: "write replacement resource")
                }
                guard count > 0 else {
                    throw failure(path, operation: "write replacement resource")
                }
                offset += count
            }
        }
    }

    private static func failure(
        _ path: String,
        operation: String
    ) -> ResearchSkillMaintenanceError {
        let code = errno
        return .invalidResourcePath(
            "\(path) (\(operation) failed: \(String(cString: strerror(code))))"
        )
    }
}

struct ResearchWorkingMethodRecoveryReservation: Sendable {
    let id: UUID
    let packageID: String
    let packageRevision: DocumentFingerprint
}

/// Archives a displaced Working Method package into the existing machine-local
/// Research Guidance snapshot root. Same-volume moves preserve late writes
/// through open descriptors. Cross-volume vaults use a verified snapshot copy,
/// recheck the source, and retain the hidden portable source inode so late
/// writes cannot be discarded. Published UUID directories use the existing
/// maintenance snapshot format, so listing and restore remain owned by
/// ResearchSkillMaintenanceStore rather than portable Skill storage.
public final class ResearchWorkingMethodRecoveryStore: @unchecked Sendable {
    public let snapshotRootURL: URL

    private let lock = NSLock()
    private let forceCopyFallback: Bool

    public init(snapshotRootURL: URL) {
        self.snapshotRootURL = snapshotRootURL.standardizedFileURL
        forceCopyFallback = false
    }

    init(snapshotRootURL: URL, forceCopyFallback: Bool) {
        self.snapshotRootURL = snapshotRootURL.standardizedFileURL
        self.forceCopyFallback = forceCopyFallback
    }

    func reserve(
        packageID: String,
        packageRevision: DocumentFingerprint
    ) -> ResearchWorkingMethodRecoveryReservation {
        ResearchWorkingMethodRecoveryReservation(
            id: UUID(),
            packageID: packageID,
            packageRevision: packageRevision
        )
    }

    @discardableResult
    func archive(
        sourceParentDescriptor: Int32,
        sourceName: String,
        reservation: ResearchWorkingMethodRecoveryReservation
    ) throws -> ResearchSkillMaintenanceSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let rootDescriptor = try openSnapshotRoot()
        defer { Darwin.close(rootDescriptor) }
        guard flock(rootDescriptor, LOCK_EX) == 0 else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        defer { _ = flock(rootDescriptor, LOCK_UN) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: snapshotRootURL.path
        )
        let temporaryName = ".creating-\(reservation.id.uuidString)"
        let destinationName = reservation.id.uuidString
        let sources = try SecureResearchSkillPackageIO.strictPackageSources(
            rootDescriptor: sourceParentDescriptor,
            packageID: sourceName
        )
        guard Self.packageRevision(sources: sources) == reservation.packageRevision else {
            throw ResearchSkillError.stalePackage(reservation.packageID)
        }
        guard try !SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: temporaryName,
            path: temporaryName
        ), try !SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: destinationName,
            path: destinationName
        ) else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        guard temporaryName.withCString({
            mkdirat(rootDescriptor, $0, mode_t(0o700))
        }) == 0 else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        let temporaryDescriptor = try SecureResearchSkillPackageIO.openDirectory(
            parentDescriptor: rootDescriptor,
            name: temporaryName,
            path: temporaryName
        )
        defer { Darwin.close(temporaryDescriptor) }

        var retainedPortableName: String?
        do {
            if forceCopyFallback {
                throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
            }
            try SecureResearchSkillPackageIO.moveEntryExclusively(
                sourceParentDescriptor: sourceParentDescriptor,
                source: sourceName,
                destinationParentDescriptor: temporaryDescriptor,
                destination: "package"
            )
        } catch {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: temporaryDescriptor,
                packageName: "package",
                sources: sources
            )
            guard try SecureResearchSkillPackageIO.strictPackageSources(
                rootDescriptor: temporaryDescriptor,
                packageID: "package"
            ) == sources,
                  try SecureResearchSkillPackageIO.strictPackageSources(
                      rootDescriptor: sourceParentDescriptor,
                      packageID: sourceName
                  ) == sources else {
                throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
            }
            // A cross-volume copy cannot atomically preserve late writes to
            // an already-open source inode. Keep the hidden portable package
            // and surface its live revision through the snapshot listing for
            // explicit researcher-authorized cleanup.
            retainedPortableName = sourceName
        }

        let manifest = ResearchSkillMaintenanceSnapshotManifest(
            id: reservation.id,
            packageID: reservation.packageID,
            packageRevision: reservation.packageRevision,
            retainedPortablePackageName: retainedPortableName
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try SecureResearchSkillPackageIO.createDataFile(
            parentDescriptor: temporaryDescriptor,
            leaf: "manifest.json",
            data: manifestData,
            path: "\(temporaryName)/manifest.json"
        )
        guard fsync(sourceParentDescriptor) == 0,
              fsync(temporaryDescriptor) == 0,
              fsync(rootDescriptor) == 0,
              try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                  snapshotRootURL,
                  identity: rootIdentity
              ) else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        try SecureResearchSkillPackageIO.movePackageExclusively(
            rootDescriptor: rootDescriptor,
            source: temporaryName,
            destination: destinationName
        )
        guard fsync(rootDescriptor) == 0,
              try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                  snapshotRootURL,
                  identity: rootIdentity
              ) else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        let snapshotDescriptor = try SecureResearchSkillPackageIO.openDirectory(
            parentDescriptor: rootDescriptor,
            name: destinationName,
            path: destinationName
        )
        defer { Darwin.close(snapshotDescriptor) }
        guard try SecureResearchSkillPackageIO.strictPackageSources(
            rootDescriptor: snapshotDescriptor,
            packageID: "package"
        ) == sources,
              try SecureResearchSkillPackageIO.readDataFile(
                  parentDescriptor: snapshotDescriptor,
                  leaf: "manifest.json",
                  path: "\(destinationName)/manifest.json",
                  maximumByteCount: 64 * 1024
              ) == manifestData else {
            throw ResearchSkillBindingError.workingMethodBindingRecoveryRequired
        }
        return ResearchSkillMaintenanceSnapshot(
            id: manifest.id,
            packageID: manifest.packageID,
            packageRevision: manifest.packageRevision,
            createdAt: manifest.createdAt,
            retainedPortablePackageRevision: try retainedPortableName.map { name in
                Self.packageRevision(sources: try SecureResearchSkillPackageIO
                    .strictPackageSources(
                        rootDescriptor: sourceParentDescriptor,
                        packageID: name
                    ))
            }
        )
    }

    private func openSnapshotRoot() throws -> Int32 {
        let parent = snapshotRootURL.deletingLastPathComponent()
        try validateExistingDirectoryChain(to: parent)
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try validateExistingDirectoryChain(to: parent)
        if !FileManager.default.fileExists(atPath: snapshotRootURL.path) {
            try FileManager.default.createDirectory(
                at: snapshotRootURL,
                withIntermediateDirectories: false
            )
        }
        try validateExistingDirectoryChain(to: snapshotRootURL)
        return try SecureResearchSkillPackageIO.openAbsoluteDirectory(snapshotRootURL)
    }

    private func validateExistingDirectoryChain(to directory: URL) throws {
        let path = directory.standardizedFileURL.path
        guard path.hasPrefix("/") else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in (path as NSString).pathComponents where component != "/" {
            cursor.appendPathComponent(component, isDirectory: true)
            guard FileManager.default.fileExists(atPath: cursor.path) else { continue }
            let values = try cursor.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            let platformAlias = values.isSymbolicLink == true
                && ["/var", "/tmp", "/etc"].contains(cursor.path)
            guard platformAlias
                    || (values.isDirectory == true && values.isSymbolicLink != true) else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(
                    cursor.lastPathComponent
                )
            }
        }
    }

    private static func packageRevision(
        sources: [String: String]
    ) -> DocumentFingerprint {
        var bytes = Data()
        for path in sources.keys.sorted() {
            let data = Data((sources[path] ?? "").utf8)
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }
}

private struct ResearchSkillMaintenanceSnapshotManifest: Codable, Hashable {
    let schemaVersion: Int
    let id: UUID
    let packageID: String
    let packageRevision: DocumentFingerprint
    let createdAt: Date
    let retainedPortablePackageName: String?

    init(
        id: UUID,
        packageID: String,
        packageRevision: DocumentFingerprint,
        retainedPortablePackageName: String? = nil,
        createdAt: Date = Date()
    ) {
        schemaVersion = 1
        self.id = id
        self.packageID = packageID
        self.packageRevision = packageRevision
        self.retainedPortablePackageName = retainedPortablePackageName
        self.createdAt = createdAt
    }
}

private struct LoadedResearchSkillMaintenanceSnapshot {
    let manifest: ResearchSkillMaintenanceSnapshotManifest
    let sources: [String: String]
}

private struct ResearchSkillMaintenanceSnapshotReadError: Error {
    let code: ResearchSkillMaintenanceSnapshotIssueCode
    let summary: String

    init(
        _ code: ResearchSkillMaintenanceSnapshotIssueCode,
        _ summary: String
    ) {
        self.code = code
        self.summary = summary
    }
}

private enum ResearchSkillMaintenanceReplacementFailure: Error {
    case rollbackUnproven
}

enum ResearchSkillMaintenanceReplacementFaultPoint: Sendable {
    case beforeReplacement
    case afterReplacement
}

struct ResearchSkillMaintenanceReplacementHooks: Sendable {
    let handler: @Sendable (ResearchSkillMaintenanceReplacementFaultPoint) throws -> Void

    static let none = Self { _ in }
}

/// Owns explicit Research Guidance maintenance for one Triptych. Research
/// Skill package discovery remains in `ResearchSkillStore`; this actor owns
/// only bounded whole-package evaluation, replacement, snapshot, and rollback.
/// Its snapshots are injected from Triptych-scoped Application Support and
/// never written into a research vault or portable `.scholium/` state.
public actor ResearchSkillMaintenanceStore {
    public nonisolated let snapshotRootURL: URL

    private let skillStore: ResearchSkillStore
    private let fileManager: FileManager
    private let replacementHooks: ResearchSkillMaintenanceReplacementHooks
    private var preparations: [UUID: ResearchSkillMaintenancePreparation] = [:]

    public init(
        skillStore: ResearchSkillStore,
        snapshotRootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.skillStore = skillStore
        self.snapshotRootURL = snapshotRootURL.standardizedFileURL
        self.fileManager = fileManager
        replacementHooks = .none
    }

    init(
        skillStore: ResearchSkillStore,
        snapshotRootURL: URL,
        fileManager: FileManager = .default,
        replacementHooks: ResearchSkillMaintenanceReplacementHooks
    ) {
        self.skillStore = skillStore
        self.snapshotRootURL = snapshotRootURL.standardizedFileURL
        self.fileManager = fileManager
        self.replacementHooks = replacementHooks
    }

    public func prepare(
        _ request: ResearchSkillMaintenanceRequest
    ) async throws -> ResearchSkillMaintenancePreparation {
        try request.validate()
        let current = try await skillStore.package(id: request.packageID)
        guard current.origin == .triptych, current.skillClass == .researcher else {
            throw ResearchSkillMaintenanceError.packageNotResearcherOwned(request.packageID)
        }
        guard current.allowsEvolution else {
            throw ResearchSkillMaintenanceError.evolutionNotEnabled(request.packageID)
        }
        _ = try packageURL(id: request.packageID)
        let currentFiles = try strictInstalledPackageSources(id: request.packageID)
        let currentRevision = Self.packageRevision(sources: currentFiles)
        guard currentRevision == request.expectedPackageRevision,
              current.revision == currentRevision else {
            throw ResearchSkillMaintenanceError.stalePackage(request.packageID)
        }

        let proposedFiles = Dictionary(
            uniqueKeysWithValues: request.proposedPackage.files.map {
                ($0.relativePath, $0.source)
            }
        )
        let proposedRevision = request.proposedPackage.packageRevision
        guard proposedRevision == Self.packageRevision(sources: proposedFiles) else {
            throw ResearchSkillMaintenanceError.stalePackage(request.packageID)
        }
        let validatedPackage = try await skillStore.validatedProposedResearcherPackage(
            id: request.packageID,
            sources: proposedFiles,
            revision: proposedRevision
        )
        let evaluation = Self.evaluateProposedPackage(
            package: validatedPackage,
            files: proposedFiles,
            revision: proposedRevision,
            evidence: request.evaluationEvidence
        )
        let id = UUID()
        let token = evaluation.status == .passed
            ? ResearchSkillMaintenanceConfirmationToken(
                preparationID: id,
                packageID: request.packageID,
                expectedPackageRevision: currentRevision,
                proposedPackageRevision: proposedRevision,
                expiresAt: Date().addingTimeInterval(15 * 60)
            )
            : nil
        let preparation = ResearchSkillMaintenancePreparation(
            id: id,
            request: request,
            proposedPackageRevision: proposedRevision,
            changes: Self.fileChanges(from: currentFiles, to: proposedFiles),
            evaluation: evaluation,
            confirmationToken: token
        )
        if token != nil {
            preparations[id] = preparation
        }
        return preparation
    }

    public func apply(
        _ preparation: ResearchSkillMaintenancePreparation,
        confirmationToken: ResearchSkillMaintenanceConfirmationToken
    ) async throws -> ResearchSkillMaintenanceApplyOutcome {
        guard preparation.evaluation.status == .passed,
              let issuedToken = preparation.confirmationToken,
              issuedToken == confirmationToken,
              let stored = preparations[preparation.id],
              stored == preparation else {
            throw ResearchSkillMaintenanceError.evaluationFailed
        }
        guard confirmationToken.preparationID == preparation.id,
              confirmationToken.packageID == preparation.request.packageID,
              confirmationToken.expectedPackageRevision
                == preparation.request.expectedPackageRevision,
              confirmationToken.proposedPackageRevision
                == preparation.proposedPackageRevision else {
            throw ResearchSkillMaintenanceError.invalidConfirmation
        }
        guard confirmationToken.expiresAt > Date() else {
            preparations.removeValue(forKey: preparation.id)
            throw ResearchSkillMaintenanceError.confirmationExpired
        }

        let current = try await skillStore.package(id: preparation.request.packageID)
        guard current.origin == .triptych, current.skillClass == .researcher else {
            throw ResearchSkillMaintenanceError.packageNotResearcherOwned(
                preparation.request.packageID
            )
        }
        guard current.allowsEvolution else {
            throw ResearchSkillMaintenanceError.evolutionNotEnabled(
                preparation.request.packageID
            )
        }
        _ = try packageURL(id: preparation.request.packageID)
        let currentFiles = try strictInstalledPackageSources(
            id: preparation.request.packageID
        )
        let currentRevision = Self.packageRevision(sources: currentFiles)
        guard currentRevision == preparation.request.expectedPackageRevision,
              current.revision == currentRevision else {
            throw ResearchSkillMaintenanceError.stalePackage(preparation.request.packageID)
        }

        let proposed = Dictionary(
            uniqueKeysWithValues: preparation.request.proposedPackage.files.map {
                ($0.relativePath, $0.source)
            }
        )
        let revalidatedPackage = try await skillStore.validatedProposedResearcherPackage(
            id: preparation.request.packageID,
            sources: proposed,
            revision: preparation.proposedPackageRevision
        )
        guard revalidatedPackage.isValid else {
            throw ResearchSkillMaintenanceError.evaluationFailed
        }
        let snapshotID = UUID()
        _ = try persistSnapshot(
            id: snapshotID,
            packageID: preparation.request.packageID,
            sources: currentFiles,
            revision: currentRevision
        )
        do {
            let rechecked = try strictInstalledPackageSources(
                id: preparation.request.packageID
            )
            guard Self.packageRevision(sources: rechecked) == currentRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(
                    preparation.request.packageID
                )
            }
            try atomicallyReplacePackage(
                id: preparation.request.packageID,
                sources: proposed,
                expectedRevision: preparation.proposedPackageRevision,
                previousRevision: currentRevision
            )
        } catch ResearchSkillMaintenanceReplacementFailure.rollbackUnproven {
            throw ResearchSkillMaintenanceError.replacementRecoveryRequired(snapshotID)
        } catch {
            throw error
        }
        preparations.removeValue(forKey: preparation.id)
        return ResearchSkillMaintenanceApplyOutcome(
            packageID: preparation.request.packageID,
            previousPackageRevision: currentRevision,
            packageRevision: preparation.proposedPackageRevision,
            snapshotID: snapshotID,
            evaluation: preparation.evaluation
        )
    }

    public func restore(
        snapshotID: UUID,
        expectedCurrentState: ResearchSkillMaintenanceExpectedCurrentState
    ) async throws -> ResearchSkillMaintenanceRestoreOutcome {
        let snapshot: LoadedResearchSkillMaintenanceSnapshot
        do {
            snapshot = try securelyLoadSnapshot(id: snapshotID)
            try await validateResearcherSnapshot(snapshot)
        } catch let error as ResearchSkillMaintenanceSnapshotReadError {
            throw ResearchSkillMaintenanceError.corruptSnapshot(snapshotID, error.code)
        }
        _ = try packageURL(id: snapshot.manifest.packageID)
        let currentRevision: DocumentFingerprint?
        let undoSnapshot: ResearchSkillMaintenanceSnapshot?
        switch expectedCurrentState {
        case .present(let expectedRevision):
            let currentSources = try strictInstalledPackageSources(
                id: snapshot.manifest.packageID
            )
            let revision = Self.packageRevision(sources: currentSources)
            guard revision == expectedRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(snapshot.manifest.packageID)
            }
            let undoID = UUID()
            undoSnapshot = try persistSnapshot(
                id: undoID,
                packageID: snapshot.manifest.packageID,
                sources: currentSources,
                revision: revision
            )
            currentRevision = revision
        case .missing:
            guard try installedPackageIsMissing(id: snapshot.manifest.packageID) else {
                throw ResearchSkillMaintenanceError.stalePackage(snapshot.manifest.packageID)
            }
            currentRevision = nil
            undoSnapshot = nil
        }
        do {
            if let currentRevision {
                try atomicallyReplacePackage(
                    id: snapshot.manifest.packageID,
                    sources: snapshot.sources,
                    expectedRevision: snapshot.manifest.packageRevision,
                    previousRevision: currentRevision
                )
            } else {
                try atomicallyInstallMissingPackage(
                    id: snapshot.manifest.packageID,
                    sources: snapshot.sources,
                    expectedRevision: snapshot.manifest.packageRevision
                )
            }
        } catch ResearchSkillMaintenanceReplacementFailure.rollbackUnproven {
            throw ResearchSkillMaintenanceError.replacementRecoveryRequired(
                undoSnapshot?.id ?? snapshotID
            )
        }
        return ResearchSkillMaintenanceRestoreOutcome(
            packageID: snapshot.manifest.packageID,
            replacedPackageRevision: currentRevision,
            restoredPackageRevision: snapshot.manifest.packageRevision,
            snapshotID: snapshotID,
            undoSnapshot: undoSnapshot
        )
    }

    /// Returns every independently validated snapshot together with typed
    /// evidence for corrupt entries. One bad entry never hides another
    /// package's valid recovery state.
    public func snapshots(
        packageID: String? = nil
    ) async throws -> ResearchSkillMaintenanceSnapshotListing {
        if let packageID {
            _ = try packageURL(id: packageID)
        }
        try ensureSnapshotRoot()
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            snapshotRootURL
        )
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: snapshotRootURL.path
        )
        let entryNames = try SecureResearchSkillPackageIO.entryNames(
            descriptor: rootDescriptor,
            path: snapshotRootURL.path
        )
        var result: [ResearchSkillMaintenanceSnapshot] = []
        var issues: [ResearchSkillMaintenanceSnapshotIssue] = []
        for entryName in entryNames {
            guard let id = UUID(uuidString: entryName) else {
                issues.append(ResearchSkillMaintenanceSnapshotIssue(
                    entryName: entryName,
                    snapshotID: nil,
                    code: .invalidEntryName,
                    summary: "Snapshot storage contains an entry without a stable snapshot identifier."
                ))
                continue
            }
            do {
                let loaded = try securelyLoadSnapshot(
                    id: id,
                    rootDescriptor: rootDescriptor
                )
                try await validateResearcherSnapshot(loaded)
                guard packageID == nil || loaded.manifest.packageID == packageID else {
                    continue
                }
                let retainedRevision: DocumentFingerprint?
                do {
                    retainedRevision = try retainedPortableRevision(
                        for: loaded.manifest
                    )
                } catch {
                    retainedRevision = nil
                    issues.append(ResearchSkillMaintenanceSnapshotIssue(
                        entryName: "\(entryName)/retained-portable",
                        snapshotID: id,
                        code: .unsafeEntry,
                        summary: "The machine-local snapshot is valid, but its optional retained portable package could not be inspected. \(error.localizedDescription)"
                    ))
                }
                result.append(ResearchSkillMaintenanceSnapshot(
                    id: loaded.manifest.id,
                    packageID: loaded.manifest.packageID,
                    packageRevision: loaded.manifest.packageRevision,
                    createdAt: loaded.manifest.createdAt,
                    retainedPortablePackageRevision: retainedRevision
                ))
            } catch let error as ResearchSkillMaintenanceSnapshotReadError {
                issues.append(ResearchSkillMaintenanceSnapshotIssue(
                    entryName: entryName,
                    snapshotID: id,
                    code: error.code,
                    summary: error.summary
                ))
            } catch {
                issues.append(ResearchSkillMaintenanceSnapshotIssue(
                    entryName: entryName,
                    snapshotID: id,
                    code: .invalidPackage,
                    summary: error.localizedDescription
                ))
            }
        }
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            snapshotRootURL,
            identity: rootIdentity
        ) else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(
                snapshotRootURL.lastPathComponent
            )
        }
        let sorted = result.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        return ResearchSkillMaintenanceSnapshotListing(
            snapshots: sorted,
            issues: issues.sorted { $0.entryName < $1.entryName }
        )
    }

    private func retainedPortableRevision(
        for manifest: ResearchSkillMaintenanceSnapshotManifest
    ) throws -> DocumentFingerprint? {
        guard let name = try validatedRetainedPortableName(manifest) else { return nil }
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(
            skillStore.skillsURL
        )
        defer { Darwin.close(rootDescriptor) }
        guard try SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: name,
            path: name
        ) else { return nil }
        return Self.packageRevision(sources: try SecureResearchSkillPackageIO
            .strictPackageSources(
                rootDescriptor: rootDescriptor,
                packageID: name
            ))
    }

    private func validatedRetainedPortableName(
        _ manifest: ResearchSkillMaintenanceSnapshotManifest
    ) throws -> String? {
        guard let name = manifest.retainedPortablePackageName else { return nil }
        let pattern = #"^\.working-(?:edit|method)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidManifest,
                "The snapshot names an invalid retained portable package."
            )
        }
        return name
    }

    private func packageURL(id: String) throws -> URL {
        guard id.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil else {
            throw ResearchSkillMaintenanceError.invalidPackageID(id)
        }
        let root = skillStore.skillsURL.standardizedFileURL
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(root)
        Darwin.close(rootDescriptor)
        let result = root.appendingPathComponent(id, isDirectory: true).standardizedFileURL
        guard result.deletingLastPathComponent() == root else {
            throw ResearchSkillMaintenanceError.invalidPackageID(id)
        }
        return result
    }

    private func strictInstalledPackageSources(id: String) throws -> [String: String] {
        let root = skillStore.skillsURL.standardizedFileURL
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(root)
        defer { Darwin.close(rootDescriptor) }
        return try SecureResearchSkillPackageIO.strictPackageSources(
            rootDescriptor: rootDescriptor,
            packageID: id
        )
    }

    private func strictPackageSources(at packageURL: URL) throws -> [String: String] {
        let values = try packageURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(
                packageURL.lastPathComponent
            )
        }
        let entries = try fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            ],
            options: []
        )
        var sources: [String: String] = [:]
        for entry in entries {
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(name)
            }
            let entryValues = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard entryValues.isSymbolicLink != true else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(name)
            }
            if name == "SKILL.md" {
                guard entryValues.isRegularFile == true,
                      let source = try? String(contentsOf: entry, encoding: .utf8) else {
                    throw ResearchSkillMaintenanceError.invalidResourcePath(name)
                }
                sources[name] = source
                continue
            }
            guard ["references", "templates", "evals"].contains(name),
                  entryValues.isDirectory == true else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(name)
            }
            let resources = try fileManager.contentsOfDirectory(
                at: entry,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ],
                options: []
            )
            for resource in resources {
                let path = "\(name)/\(resource.lastPathComponent)"
                let resourceValues = try resource.resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
                )
                guard ResearchSkillMaintenancePath.isAllowed(path),
                      resourceValues.isRegularFile == true,
                      resourceValues.isDirectory != true,
                      resourceValues.isSymbolicLink != true,
                      let source = try? String(contentsOf: resource, encoding: .utf8) else {
                    throw ResearchSkillMaintenanceError.invalidResourcePath(path)
                }
                sources[path] = source
            }
        }
        guard sources["SKILL.md"] != nil else {
            throw ResearchSkillMaintenanceError.missingEntryPoint
        }
        return sources
    }

    private static func packageRevision(
        sources: [String: String]
    ) -> DocumentFingerprint {
        var bytes = Data()
        for path in sources.keys.sorted() {
            let data = Data((sources[path] ?? "").utf8)
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(data.count).utf8))
            bytes.append(0)
            bytes.append(data)
            bytes.append(0)
        }
        return DocumentFingerprint(data: bytes)
    }

    /// Structural validation is deterministic. Until externally attributed
    /// semantic/adversarial evidence is bound to this exact revision, the
    /// evaluation remains incomplete and no confirmation token is issued.
    private static func evaluateProposedPackage(
        package: ResearchSkillPackage,
        files: [String: String],
        revision: DocumentFingerprint,
        evidence: ResearchSkillMaintenanceExternalEvaluation?
    ) -> ResearchSkillMaintenanceEvaluationResult {
        var issues = package.validationIssues
        let source = files["SKILL.md"] ?? ""
        let evals = files.filter {
            $0.key.hasPrefix("evals/")
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if evals.isEmpty {
            issues.append("Guided evolution requires at least one nonempty evals/ resource.")
        }
        let pattern = #"(?:references|templates|evals)/[A-Za-z0-9][A-Za-z0-9._-]*"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, range: range) {
                guard let swiftRange = Range(match.range, in: source) else { continue }
                let path = String(source[swiftRange])
                if files[path] == nil {
                    issues.append("SKILL.md references a missing package resource: \(path).")
                }
            }
        }
        issues = unique(issues)
        let structuralStatus: ResearchSkillMaintenanceEvaluationStatus = issues.isEmpty
            ? .passed
            : .failed
        let structural = ResearchSkillMaintenanceEvaluationCase(
            id: "core-structural-validation",
            status: structuralStatus,
            summary: issues.isEmpty
                ? "Core verified the bounded package structure and direct resource closure."
                : "Core found structural or resource-closure failures."
        )
        let externalStatus: ResearchSkillMaintenanceEvaluationStatus
        let externalCases: [ResearchSkillMaintenanceEvaluationCase]
        let evidenceCasesAreWellFormed = evidence.map { evidence in
            !evidence.cases.isEmpty
                && Set(evidence.cases.map(\.id)).count == evidence.cases.count
                && evidence.cases.allSatisfy {
                    !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && $0.status != .incomplete
                }
        } ?? false
        if let evidence,
           evidence.proposedPackageRevision == revision,
           !evidence.evaluator.isEmpty,
           !evidence.method.isEmpty,
           evidenceCasesAreWellFormed {
            let reportedCases = evidence.cases.map {
                ResearchSkillMaintenanceEvaluationCase(
                    id: "external-\($0.id)",
                    status: $0.status,
                    summary: $0.summary
                )
            }
            if evidence.status == .failed
                || reportedCases.contains(where: { $0.status == .failed }) {
                externalStatus = .failed
            } else if evidence.status == .passed
                && reportedCases.allSatisfy({ $0.status == .passed }) {
                externalStatus = .passed
            } else {
                externalStatus = .incomplete
            }
            externalCases = reportedCases
        } else {
            externalStatus = .incomplete
            let reason: String
            if let evidence, evidence.proposedPackageRevision != revision {
                reason = "External evaluation evidence targets a different proposed package revision."
            } else if let evidence,
                      evidence.evaluator.isEmpty || evidence.method.isEmpty {
                reason = "External evaluation evidence lacks attributed evaluator or method provenance."
            } else if evidence != nil, !evidenceCasesAreWellFormed {
                reason = "External evaluation cases require unique nonempty identifiers, nonempty summaries, and no incomplete case."
            } else {
                reason = "No externally attributed semantic/adversarial evaluation is bound to this proposed package revision."
            }
            externalCases = [ResearchSkillMaintenanceEvaluationCase(
                id: "external-semantic-evaluation",
                status: .incomplete,
                summary: reason
            )]
        }
        let combinedStatus: ResearchSkillMaintenanceEvaluationStatus
        if structuralStatus == .failed || externalStatus == .failed {
            combinedStatus = .failed
        } else if structuralStatus == .passed && externalStatus == .passed {
            combinedStatus = .passed
        } else {
            combinedStatus = .incomplete
        }
        return ResearchSkillMaintenanceEvaluationResult(
            status: combinedStatus,
            structuralStatus: structuralStatus,
            externalStatus: externalStatus,
            validationIssues: issues,
            cases: [structural] + externalCases,
            evaluator: evidence?.evaluator,
            method: evidence?.method,
            proposedPackageRevision: evidence?.proposedPackageRevision,
            evaluatedAt: evidence?.evaluatedAt ?? Date()
        )
    }

    private static func fileChanges(
        from current: [String: String],
        to proposed: [String: String]
    ) -> [ResearchSkillMaintenanceFileChange] {
        Set(current.keys).union(proposed.keys).sorted().map { path in
            let old = current[path].map(DocumentFingerprint.init(content:))
            let new = proposed[path].map(DocumentFingerprint.init(content:))
            let kind: ResearchSkillMaintenanceChangeKind = switch (old, new) {
            case (nil, .some): .added
            case (.some, nil): .removed
            case let (.some(lhs), .some(rhs)): lhs == rhs ? .unchanged : .modified
            case (nil, nil): .unchanged
            }
            return ResearchSkillMaintenanceFileChange(
                relativePath: path,
                kind: kind,
                previousRevision: old,
                proposedRevision: new
            )
        }
    }

    private func ensureSnapshotRoot() throws {
        let parent = snapshotRootURL.deletingLastPathComponent()
        try validateExistingDirectoryChain(to: parent)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try validateExistingDirectoryChain(to: parent)
        if !fileManager.fileExists(atPath: snapshotRootURL.path) {
            try fileManager.createDirectory(
                at: snapshotRootURL,
                withIntermediateDirectories: false
            )
        }
        try validateExistingDirectoryChain(to: snapshotRootURL)
    }

    /// Rejects linked ancestors as well as a linked leaf. A snapshot location
    /// may be created lazily, so missing descendants are allowed on the first
    /// pass and verified after creation.
    private func validateExistingDirectoryChain(to directory: URL) throws {
        let path = directory.standardizedFileURL.path
        guard path.hasPrefix("/") else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for pathComponent in (path as NSString).pathComponents where pathComponent != "/" {
            cursor.appendPathComponent(pathComponent, isDirectory: true)
            guard fileManager.fileExists(atPath: cursor.path) else { continue }
            let values = try cursor.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            // macOS exposes a few immutable root-level compatibility aliases
            // (notably /var -> /private/var). Permit only those platform
            // aliases; every package-owned or user-writable descendant must
            // remain a real directory.
            let isPlatformRootAlias = values.isSymbolicLink == true
                && ["/var", "/tmp", "/etc"].contains(cursor.path)
            guard isPlatformRootAlias
                    || (values.isDirectory == true && values.isSymbolicLink != true) else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(
                    cursor.lastPathComponent
                )
            }
        }
    }

    private func persistSnapshot(
        id: UUID,
        packageID: String,
        sources: [String: String],
        revision: DocumentFingerprint
    ) throws -> ResearchSkillMaintenanceSnapshot {
        try ensureSnapshotRoot()
        let temporary = snapshotRootURL.appendingPathComponent(
            ".creating-\(id.uuidString)", isDirectory: true
        )
        let destination = snapshotRootURL.appendingPathComponent(
            id.uuidString, isDirectory: true
        )
        guard !fileManager.fileExists(atPath: temporary.path),
              !fileManager.fileExists(atPath: destination.path) else {
            throw ResearchSkillMaintenanceError.invalidResourcePath(id.uuidString)
        }
        var published = false
        do {
            let package = temporary.appendingPathComponent("package", isDirectory: true)
            try fileManager.createDirectory(at: package, withIntermediateDirectories: true)
            try write(sources, to: package)
            guard Self.packageRevision(sources: try strictPackageSources(at: package))
                    == revision else {
                throw ResearchSkillMaintenanceError.stalePackage(packageID)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifest = ResearchSkillMaintenanceSnapshotManifest(
                id: id,
                packageID: packageID,
                packageRevision: revision
            )
            try encoder.encode(manifest).write(
                to: temporary.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try fileManager.moveItem(at: temporary, to: destination)
            published = true
            _ = try securelyLoadSnapshot(id: id)
            return ResearchSkillMaintenanceSnapshot(
                id: id,
                packageID: packageID,
                packageRevision: revision,
                createdAt: manifest.createdAt
            )
        } catch {
            try? fileManager.removeItem(at: temporary)
            if published {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    private func securelyLoadSnapshot(
        id: UUID
    ) throws -> LoadedResearchSkillMaintenanceSnapshot {
        try ensureSnapshotRoot()
        let rootDescriptor = try SecureResearchSkillPackageIO.openAbsoluteDirectory(
            snapshotRootURL
        )
        defer { Darwin.close(rootDescriptor) }
        let identity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: snapshotRootURL.path
        )
        let loaded = try securelyLoadSnapshot(id: id, rootDescriptor: rootDescriptor)
        guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
            snapshotRootURL,
            identity: identity
        ) else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .unsafeEntry,
                "The snapshot storage root changed while it was being read."
            )
        }
        return loaded
    }

    private func securelyLoadSnapshot(
        id: UUID,
        rootDescriptor: Int32
    ) throws -> LoadedResearchSkillMaintenanceSnapshot {
        let entryName = id.uuidString
        let exists: Bool
        do {
            exists = try SecureResearchSkillPackageIO.directoryExists(
                parentDescriptor: rootDescriptor,
                name: entryName,
                path: entryName
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .unsafeEntry,
                "Snapshot \(entryName) is not a nonlinked directory."
            )
        }
        guard exists else {
            throw ResearchSkillMaintenanceError.snapshotNotFound(id)
        }
        let snapshotDescriptor: Int32
        do {
            snapshotDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: rootDescriptor,
                name: entryName,
                path: entryName
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .unsafeEntry,
                "Snapshot \(entryName) could not be opened without following links."
            )
        }
        defer { Darwin.close(snapshotDescriptor) }
        let names: [String]
        do {
            names = try SecureResearchSkillPackageIO.entryNames(
                descriptor: snapshotDescriptor,
                path: entryName
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .unsafeEntry,
                "Snapshot \(entryName) could not be enumerated safely."
            )
        }
        guard Set(names) == ["manifest.json", "package"] else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .unsafeEntry,
                "Snapshot \(entryName) contains an unexpected entry set."
            )
        }
        let manifestData: Data
        do {
            manifestData = try SecureResearchSkillPackageIO.readDataFile(
                parentDescriptor: snapshotDescriptor,
                leaf: "manifest.json",
                path: "\(entryName)/manifest.json"
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidManifest,
                "Snapshot \(entryName) has no safe regular manifest."
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: ResearchSkillMaintenanceSnapshotManifest
        do {
            manifest = try decoder.decode(
                ResearchSkillMaintenanceSnapshotManifest.self,
                from: manifestData
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidManifest,
                "Snapshot \(entryName) has a malformed manifest."
            )
        }
        guard manifest.schemaVersion == 1,
              manifest.id == id,
              manifest.packageID.range(
                of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
                options: .regularExpression
              ) != nil else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidManifest,
                "Snapshot \(entryName) manifest identity or schema is invalid."
            )
        }
        let packageDescriptor: Int32
        do {
            packageDescriptor = try SecureResearchSkillPackageIO.openDirectory(
                parentDescriptor: snapshotDescriptor,
                name: "package",
                path: "\(entryName)/package"
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidPackage,
                "Snapshot \(entryName) has no safe bounded package directory."
            )
        }
        defer { Darwin.close(packageDescriptor) }
        let sources: [String: String]
        do {
            sources = try SecureResearchSkillPackageIO.strictPackageSources(
                packageDescriptor: packageDescriptor,
                packageID: manifest.packageID
            )
        } catch {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .invalidPackage,
                "Snapshot \(entryName) contains an unsafe or malformed package resource."
            )
        }
        guard Self.packageRevision(sources: sources) == manifest.packageRevision else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .revisionMismatch,
                "Snapshot \(entryName) package bytes do not match its manifest revision."
            )
        }
        return LoadedResearchSkillMaintenanceSnapshot(manifest: manifest, sources: sources)
    }

    private func validateResearcherSnapshot(
        _ snapshot: LoadedResearchSkillMaintenanceSnapshot
    ) async throws {
        let protectedIDs = Set(try await skillStore.catalog().entries.map(\.id))
        guard !protectedIDs.contains(snapshot.manifest.packageID),
              let entryPoint = snapshot.sources["SKILL.md"] else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .notResearcherSkill,
                "The snapshot does not identify a Triptych-local Researcher Skill."
            )
        }
        let package = ResearchSkillStore.inspectDraft(
            id: snapshot.manifest.packageID,
            source: entryPoint,
            origin: .triptych
        )
        guard package.origin == .triptych, package.skillClass == .researcher else {
            throw ResearchSkillMaintenanceSnapshotReadError(
                .notResearcherSkill,
                "The snapshot does not identify a Triptych-local Researcher Skill."
            )
        }
    }

    private func installedPackageIsMissing(id: String) throws -> Bool {
        let root = skillStore.skillsURL.standardizedFileURL
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(root)
        defer { Darwin.close(rootDescriptor) }
        return try !SecureResearchSkillPackageIO.directoryExists(
            parentDescriptor: rootDescriptor,
            name: id,
            path: id
        )
    }

    private func write(_ sources: [String: String], to packageURL: URL) throws {
        for path in sources.keys.sorted() {
            guard ResearchSkillMaintenancePath.isAllowed(path),
                  let source = sources[path] else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(path)
            }
            let destination = packageURL.appendingPathComponent(path).standardizedFileURL
            guard destination.path.hasPrefix(packageURL.standardizedFileURL.path + "/") else {
                throw ResearchSkillMaintenanceError.invalidResourcePath(path)
            }
            let parent = destination.deletingLastPathComponent()
            if parent != packageURL, !fileManager.fileExists(atPath: parent.path) {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
            }
            try Data(source.utf8).write(to: destination, options: .atomic)
        }
    }

    private func atomicallyReplacePackage(
        id: String,
        sources: [String: String],
        expectedRevision: DocumentFingerprint,
        previousRevision: DocumentFingerprint
    ) throws {
        _ = try packageURL(id: id)
        let skillsRoot = skillStore.skillsURL.standardizedFileURL
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsRoot)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsRoot.path
        )
        let stagingName = ".replacing-\(UUID().uuidString)"
        var didSwap = false
        do {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: rootDescriptor,
                packageName: stagingName,
                sources: sources
            )
            guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                .strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: stagingName
                ))
                    == expectedRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            try replacementHooks.handler(.beforeReplacement)
            guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                skillsRoot,
                identity: rootIdentity
            ) else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                .strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: id
                ))
                    == previousRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            try SecureResearchSkillPackageIO.swapPackages(
                rootDescriptor: rootDescriptor,
                first: id,
                second: stagingName
            )
            didSwap = true
            let displacedRevision = Self.packageRevision(
                sources: try SecureResearchSkillPackageIO.strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: stagingName
                )
            )
            guard displacedRevision == previousRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            try replacementHooks.handler(.afterReplacement)
            guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                .strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: id
                )) == expectedRevision,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                    skillsRoot,
                    identity: rootIdentity
                  ) else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            // The exchanged package is already committed and verified. Hidden
            // backup cleanup is non-authoritative: a filesystem cleanup failure
            // must not turn a sound commit into a destructive rollback attempt.
            try? SecureResearchSkillPackageIO.removePackage(
                rootDescriptor: rootDescriptor,
                packageName: stagingName
            )
        } catch {
            guard didSwap else {
                try? SecureResearchSkillPackageIO.removePackage(
                    rootDescriptor: rootDescriptor,
                    packageName: stagingName
                )
                throw error
            }
            do {
                try SecureResearchSkillPackageIO.swapPackages(
                    rootDescriptor: rootDescriptor,
                    first: id,
                    second: stagingName
                )
                guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                    .strictPackageSources(
                        rootDescriptor: rootDescriptor,
                        packageID: id
                    )) == previousRevision else {
                    throw ResearchSkillMaintenanceReplacementFailure.rollbackUnproven
                }
                // The original package has already been restored and verified;
                // an obsolete hidden staging directory can be reconciled later.
                try? SecureResearchSkillPackageIO.removePackage(
                    rootDescriptor: rootDescriptor,
                    packageName: stagingName
                )
            } catch {
                throw ResearchSkillMaintenanceReplacementFailure.rollbackUnproven
            }
            throw error
        }
    }

    /// Installs a validated snapshot only while the package identifier remains
    /// absent. `RENAME_EXCL` makes the absence assertion part of the atomic
    /// commit rather than a path check followed by a replacing rename.
    private func atomicallyInstallMissingPackage(
        id: String,
        sources: [String: String],
        expectedRevision: DocumentFingerprint
    ) throws {
        _ = try packageURL(id: id)
        let skillsRoot = skillStore.skillsURL.standardizedFileURL
        let rootDescriptor = try SecureResearchSkillPackageIO.openSkillsRoot(skillsRoot)
        defer { Darwin.close(rootDescriptor) }
        let rootIdentity = try SecureResearchSkillPackageIO.identity(
            of: rootDescriptor,
            path: skillsRoot.path
        )
        let stagingName = ".restoring-\(UUID().uuidString)"
        var didInstall = false
        do {
            try SecureResearchSkillPackageIO.createPackage(
                rootDescriptor: rootDescriptor,
                packageName: stagingName,
                sources: sources
            )
            guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                .strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: stagingName
                )) == expectedRevision else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            try replacementHooks.handler(.beforeReplacement)
            guard try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                skillsRoot,
                identity: rootIdentity
            ), try !SecureResearchSkillPackageIO.directoryExists(
                parentDescriptor: rootDescriptor,
                name: id,
                path: id
            ) else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
            try SecureResearchSkillPackageIO.movePackageExclusively(
                rootDescriptor: rootDescriptor,
                source: stagingName,
                destination: id
            )
            didInstall = true
            try replacementHooks.handler(.afterReplacement)
            guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                .strictPackageSources(
                    rootDescriptor: rootDescriptor,
                    packageID: id
                )) == expectedRevision,
                  try SecureResearchSkillPackageIO.pathStillRefersToDirectory(
                    skillsRoot,
                    identity: rootIdentity
                  ) else {
                throw ResearchSkillMaintenanceError.stalePackage(id)
            }
        } catch {
            guard didInstall else {
                try? SecureResearchSkillPackageIO.removePackage(
                    rootDescriptor: rootDescriptor,
                    packageName: stagingName
                )
                throw error
            }
            do {
                guard Self.packageRevision(sources: try SecureResearchSkillPackageIO
                    .strictPackageSources(
                        rootDescriptor: rootDescriptor,
                        packageID: id
                    )) == expectedRevision else {
                    throw ResearchSkillMaintenanceReplacementFailure.rollbackUnproven
                }
                try SecureResearchSkillPackageIO.removePackage(
                    rootDescriptor: rootDescriptor,
                    packageName: id
                )
                guard try !SecureResearchSkillPackageIO.directoryExists(
                    parentDescriptor: rootDescriptor,
                    name: id,
                    path: id
                ) else {
                    throw ResearchSkillMaintenanceReplacementFailure.rollbackUnproven
                }
            } catch {
                throw ResearchSkillMaintenanceReplacementFailure.rollbackUnproven
            }
            throw error
        }
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}
