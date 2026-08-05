import Darwin
import Foundation

/// Descriptor-relative file operations used by current Research configuration.
/// Every path component is opened with `O_NOFOLLOW`; callers retain semantic
/// ownership of the exact documents being read or replaced.
enum SecureResearchConfigurationIO {
    private static let directoryMode = mode_t(0o700)
    private static let fileMode = mode_t(0o600)

    struct DirectoryIdentity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
    }

    static func openDirectory(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws -> Int32 {
        try requireLeaf(name)
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

    static func ensureDirectory(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws -> Int32 {
        try requireLeaf(name)
        let result = name.withCString { mkdirat(parentDescriptor, $0, directoryMode) }
        guard result == 0 || errno == EEXIST else {
            throw failure(path, operation: "create directory")
        }
        return try openDirectory(
            parentDescriptor: parentDescriptor,
            name: name,
            path: path
        )
    }

    static func createDirectory(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws -> Int32 {
        try requireLeaf(name)
        guard name.withCString({ mkdirat(parentDescriptor, $0, directoryMode) }) == 0 else {
            throw failure(path, operation: "create directory")
        }
        return try openDirectory(
            parentDescriptor: parentDescriptor,
            name: name,
            path: path
        )
    }

    static func removeDirectory(
        parentDescriptor: Int32,
        name: String,
        path: String
    ) throws {
        try requireLeaf(name)
        let result = name.withCString { unlinkat(parentDescriptor, $0, AT_REMOVEDIR) }
        if result != 0, errno == ENOENT { return }
        guard result == 0 else {
            throw failure(path, operation: "remove directory")
        }
    }

    static func identity(of descriptor: Int32, path: String) throws -> DirectoryIdentity {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw failure(path, operation: "inspect directory")
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

    static func swapEntries(
        parentDescriptor: Int32,
        first: String,
        second: String
    ) throws {
        try requireLeaf(first)
        try requireLeaf(second)
        let result = first.withCString { firstName in
            second.withCString { secondName in
                renameatx_np(
                    parentDescriptor,
                    firstName,
                    parentDescriptor,
                    secondName,
                    UInt32(RENAME_SWAP)
                )
            }
        }
        guard result == 0 else {
            throw failure(first, operation: "atomically exchange entries")
        }
    }

    static func moveEntryExclusively(
        parentDescriptor: Int32,
        source: String,
        destination: String
    ) throws {
        try requireLeaf(source)
        try requireLeaf(destination)
        let result = source.withCString { sourceName in
            destination.withCString { destinationName in
                renameatx_np(
                    parentDescriptor,
                    sourceName,
                    parentDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw failure(destination, operation: "install entry")
        }
    }

    static func openAbsoluteDirectory(_ url: URL) throws -> Int32 {
        let path = platformCanonicalPath(url.standardizedFileURL.path)
        guard path.hasPrefix("/") else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Research configuration requires an absolute directory path."
            )
        }
        // A security-scoped bookmark grants the selected directory, not each
        // ancestor needed to walk there from `/`. Opening the authorized path
        // in one operation lets App Sandbox apply that grant while Darwin's
        // O_NOFOLLOW_ANY preserves the stronger invariant that no component
        // in the complete path may be a symbolic link.
        let descriptor = path.withCString {
            Darwin.open(
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY
            )
        }
        guard descriptor >= 0 else {
            throw failure(path, operation: "open nonlinked directory")
        }
        return descriptor
    }

    static func entryNames(descriptor: Int32, path: String) throws -> [String] {
        let duplicate = dup(descriptor)
        guard duplicate >= 0, let directory = fdopendir(duplicate) else {
            if duplicate >= 0 { Darwin.close(duplicate) }
            throw failure(path, operation: "enumerate directory")
        }
        defer { closedir(directory) }
        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(MAXNAMLEN) + 1
                ) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
            errno = 0
        }
        guard errno == 0 else {
            throw failure(path, operation: "enumerate directory")
        }
        return names.sorted()
    }

    static func readDataFile(
        parentDescriptor: Int32,
        leaf: String,
        path: String,
        maximumByteCount: Int? = nil
    ) throws -> Data {
        try requireLeaf(leaf)
        let descriptor = leaf.withCString {
            openat(parentDescriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw failure(path, operation: "open data file")
        }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Research configuration path is not a regular file: \(path)"
            )
        }
        if let maximumByteCount, metadata.st_size > off_t(maximumByteCount) {
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
                throw failure(path, operation: "read data file")
            }
            if let maximumByteCount, data.count + Int(count) > maximumByteCount {
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
        try requireLeaf(leaf)
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
        try requireLeaf(leaf)
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
        try requireLeaf(leaf)
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

    private static func writeAll(
        _ data: Data,
        descriptor: Int32,
        path: String
    ) throws {
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
                    throw failure(path, operation: "write data file")
                }
                guard count > 0 else {
                    throw failure(path, operation: "write data file")
                }
                offset += count
            }
        }
    }

    private static func requireLeaf(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchConfigurationStoreError.invalidDocument(
                "Unsafe Research configuration path component."
            )
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

    private static func failure(
        _ path: String,
        operation: String
    ) -> ResearchConfigurationStoreError {
        let code = errno
        return .invalidDocument(
            "\(path) (\(operation) failed: \(String(cString: strerror(code))))"
        )
    }
}
