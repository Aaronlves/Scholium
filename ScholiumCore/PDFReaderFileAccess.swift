import Darwin
import Foundation
import ScholiumContracts

/// Binary access uses the same descriptor-relative attachment boundary; path
/// spelling is never sufficient save authority.
enum PDFReaderFileAccess {
    static let maximumBytes = 512 * 1_024 * 1_024

    struct Read: Sendable {
        let data: Data
        let revision: PDFReaderRevision
    }

    static func read(at url: URL, root: URL? = nil) throws -> Read {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Read, Error>?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinated in
            result = Result {
                guard coordinated.standardizedFileURL == url.standardizedFileURL else { throw PDFReaderError.changed }
                return try readExact(at: url, root: root)
            }
        }
        if let coordinationError { throw mapped(coordinationError) }
        guard let result else { throw PDFReaderError.unreadable }
        return try result.get()
    }

    static func readExact(at url: URL, root: URL? = nil) throws -> Read {
        let parentURL = url.deletingLastPathComponent()
        let parent = try openParent(of: url, root: root)
        defer { Darwin.close(parent) }
        let parentStatus = try checkedDirectory(parent, at: parentURL)
        let name = url.lastPathComponent
        let file = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { throw posix() }
        defer { Darwin.close(file) }
        var before = stat()
        guard fstat(file, &before) == 0 else { throw posix() }
        guard (before.st_mode & S_IFMT) == S_IFREG, before.st_nlink == 1 else { throw PDFReaderError.unsafePath }
        guard before.st_mode & 0o444 != 0 else { throw PDFReaderError.unreadable }
        guard before.st_size >= 0, before.st_size <= maximumBytes else { throw PDFReaderError.tooLarge }
        let bytes = try VaultDescriptorAccess.readAll(from: file, maximumByteCount: maximumBytes)
        var after = stat()
        var named = stat()
        guard fstat(file, &after) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw posix() }
        guard sameState(before, after), sameState(after, named), Int(after.st_size) == bytes.count else { throw PDFReaderError.changed }
        _ = try checkedDirectory(parent, at: parentURL)
        let freshParent = try openParent(of: url, root: root)
        defer { Darwin.close(freshParent) }
        let freshStatus = try checkedDirectory(freshParent, at: parentURL)
        guard freshStatus.st_dev == parentStatus.st_dev, freshStatus.st_ino == parentStatus.st_ino else { throw PDFReaderError.changed }
        return Read(
            data: bytes,
            revision: PDFReaderRevision(
                fingerprint: DocumentFingerprint(data: bytes), device: UInt64(after.st_dev), inode: UInt64(after.st_ino),
                parentDevice: UInt64(parentStatus.st_dev), parentInode: UInt64(parentStatus.st_ino)))
    }

    private static func openParent(of url: URL, root: URL?) throws -> Int32 {
        let parentURL = url.deletingLastPathComponent()
        guard let root else {
            let fd = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw posix() }
            return fd
        }
        let rootParts = root.standardizedFileURL.pathComponents
        let parentParts = parentURL.standardizedFileURL.pathComponents
        guard parentParts.count >= rootParts.count, Array(parentParts.prefix(rootParts.count)) == rootParts else { throw PDFReaderError.unsafePath }
        var descriptor = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw posix() }
        do {
            for component in parentParts.dropFirst(rootParts.count) {
                let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw posix() }
                Darwin.close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func checkedDirectory(_ descriptor: Int32, at url: URL) throws -> stat {
        var opened = stat()
        var named = stat()
        guard fstat(descriptor, &opened) == 0, lstat(url.path, &named) == 0 else { throw posix() }
        guard (named.st_mode & S_IFMT) == S_IFDIR, opened.st_dev == named.st_dev, opened.st_ino == named.st_ino else { throw PDFReaderError.unsafePath }
        return opened
    }

    private static func sameState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino && (rhs.st_mode & S_IFMT) == S_IFREG
            && lhs.st_size == rhs.st_size && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    static func posix() -> PDFReaderError {
        switch errno {
        case ENOENT: .missing
        case EACCES, EPERM: .unreadable
        case ELOOP, ENOTDIR, EINVAL: .unsafePath
        case EFBIG: .tooLarge
        default: .io(String(cString: strerror(errno)))
        }
    }

    static func mapped(_ error: NSError) -> PDFReaderError {
        if error.domain == NSCocoaErrorDomain {
            if [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return .unreadable }
            if [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { return .missing }
        }
        return .io(error.localizedDescription)
    }
}
