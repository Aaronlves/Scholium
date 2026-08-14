import Darwin
import Foundation
import ImageIO
import ScholiumContracts
import UniformTypeIdentifiers

public struct PreparedVaultImageFile: Hashable, Sendable {
    public let location: AttachmentLocation
    public let markdownDestination: String
    public let altText: String
    public let copiedFileFingerprint: DocumentFingerprint?
    public let copiedRelativePath: AttachmentRelativePath?
}

public enum VaultImageAttachmentManagement: Equatable, Sendable {
    case indexAbsolutePath
    case importIntoAttachments
}

/// Owns only attachment-file preparation and exact rollback inside one vault.
/// Portable identity remains with `TriptychControlStore`; Markdown insertion
/// remains with the editor transaction.
public actor VaultAttachmentStore {
    private let vaultURL: URL
    private let canonicalRoot: URL
    private let fileManager: FileManager

    public init(vaultURL: URL, fileManager: FileManager = .default) {
        self.vaultURL = vaultURL.standardizedFileURL
        canonicalRoot = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        self.fileManager = fileManager
    }

    public func prepareImage(
        at sourceURL: URL,
        attachmentID: UUID,
        noteRelativePath: String,
        management: VaultImageAttachmentManagement
    ) throws -> PreparedVaultImageFile {
        let data = try readStableImage(at: sourceURL)
        let directValues = try sourceURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard directValues.isSymbolicLink != true else {
            throw ImageAttachmentError.unsupportedImage(sourceURL.path)
        }
        let resolvedSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let altText = resolvedSource.deletingPathExtension().lastPathComponent

        if management == .indexAbsolutePath {
            let location = try AttachmentLocation(absolutePath: resolvedSource.path)
            return PreparedVaultImageFile(
                location: location,
                markdownDestination: Self.absoluteMarkdownDestination(
                    resolvedSource.path
                ),
                altText: altText,
                copiedFileFingerprint: nil,
                copiedRelativePath: nil
            )
        }

        let filename = resolvedSource.lastPathComponent
        guard !filename.isEmpty, filename != ".", filename != ".." else {
            throw ImageAttachmentError.unsupportedImage(sourceURL.path)
        }
        return try prepareImportedImage(
            data,
            filename: filename,
            altText: altText,
            attachmentID: attachmentID,
            noteRelativePath: noteRelativePath
        )
    }

    public func preparePastedImage(
        data: Data,
        preferredFilename: String,
        attachmentID: UUID,
        noteRelativePath: String
    ) throws -> PreparedVaultImageFile {
        let type = try validateImageData(data, path: preferredFilename)
        var filename = URL(fileURLWithPath: preferredFilename).lastPathComponent
        if filename.isEmpty || filename == "." || filename == ".." {
            filename = "Pasted Image"
        }
        if URL(fileURLWithPath: filename).pathExtension.isEmpty,
           let pathExtension = type.preferredFilenameExtension {
            filename += ".\(pathExtension)"
        }
        return try prepareImportedImage(
            data,
            filename: filename,
            altText: URL(fileURLWithPath: filename)
                .deletingPathExtension()
                .lastPathComponent,
            attachmentID: attachmentID,
            noteRelativePath: noteRelativePath
        )
    }

    private func prepareImportedImage(
        _ data: Data,
        filename: String,
        altText: String,
        attachmentID: UUID,
        noteRelativePath: String
    ) throws -> PreparedVaultImageFile {
        let relativePath = try AttachmentRelativePath(
            "Attachments/\(attachmentID.uuidString.lowercased())/\(filename)"
        )
        let destination = vaultURL.appendingPathComponent(
            relativePath.rawValue,
            isDirectory: false
        )
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw VaultRepositoryError.fileAlreadyExists(relativePath.rawValue)
        }

        let fingerprint = DocumentFingerprint(data: data)
        do {
            try coordinatedCreate(
                data,
                relativePath: relativePath,
                coordinatingAt: destination
            )
        } catch {
            try? removeCopiedImageIfExact(
                relativePath: relativePath,
                expectedFingerprint: fingerprint
            )
            throw error
        }
        return PreparedVaultImageFile(
            location: .vaultRelative(relativePath),
            markdownDestination: Self.markdownDestination(
                from: noteRelativePath,
                to: relativePath
            ),
            altText: altText,
            copiedFileFingerprint: fingerprint,
            copiedRelativePath: relativePath
        )
    }

    public func removeCopiedImageIfExact(
        relativePath: AttachmentRelativePath,
        expectedFingerprint: DocumentFingerprint
    ) throws {
        let components = relativePath.components.map(String.init)
        guard components.count >= 3,
              components[0] == "Attachments",
              UUID(uuidString: components[1]) != nil else {
            throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
        }
        let candidate = vaultURL.appendingPathComponent(
            relativePath.rawValue,
            isDirectory: false
        )

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: candidate,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            outcome = Result {
                try self.deleteExactFile(
                    relativePath: relativePath,
                    expectedFingerprint: expectedFingerprint
                )
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else {
            throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
        }
        try outcome.get()
    }

    private func readStableImage(at url: URL) throws -> Data {
        let data: Data
        do {
            data = try Self.readStableRegularFile(at: url)
        } catch {
            throw ImageAttachmentError.unsupportedImage(url.path)
        }
        _ = try validateImageData(data, path: url.path)
        return data
    }

    private func validateImageData(_ data: Data, path: String) throws -> UTType {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              type.conforms(to: .image) else {
            throw ImageAttachmentError.unsupportedImage(path)
        }
        return type
    }

    private static func readStableRegularFile(at url: URL) throws -> Data {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        var initial = stat()
        guard fstat(descriptor, &initial) == 0,
              (initial.st_mode & S_IFMT) == S_IFREG else {
            throw ImageAttachmentError.unsupportedImage(url.path)
        }
        let data = try VaultDescriptorAccess.readAll(from: descriptor)
        var final = stat()
        guard fstat(descriptor, &final) == 0,
              initial.st_dev == final.st_dev,
              initial.st_ino == final.st_ino,
              initial.st_size == final.st_size,
              initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
              initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
              Int(final.st_size) == data.count else {
            throw ImageAttachmentError.sourceChanged(url.path)
        }
        var current = stat()
        guard lstat(url.path, &current) == 0,
              (current.st_mode & S_IFMT) == S_IFREG,
              current.st_dev == final.st_dev,
              current.st_ino == final.st_ino else {
            throw ImageAttachmentError.sourceChanged(url.path)
        }
        return data
    }

    private func coordinatedCreate(
        _ data: Data,
        relativePath: AttachmentRelativePath,
        coordinatingAt destination: URL
    ) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: destination,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            outcome = Result {
                try self.createExactFile(data, relativePath: relativePath)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        try outcome.get()
    }

    private func createExactFile(
        _ data: Data,
        relativePath: AttachmentRelativePath
    ) throws {
        try withParentDescriptor(relativePath: relativePath, createDirectories: true) {
            parentDescriptor, name in
            let descriptor = openat(
                parentDescriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o644)
            )
            guard descriptor >= 0 else {
                let code = errno
                if code == EEXIST {
                    throw VaultRepositoryError.fileAlreadyExists(relativePath.rawValue)
                }
                throw POSIXError(Self.posixCode(code))
            }
            var shouldRemove = true
            defer {
                Darwin.close(descriptor)
                if shouldRemove { _ = unlinkat(parentDescriptor, name, 0) }
            }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(
                        descriptor,
                        bytes.baseAddress?.advanced(by: offset),
                        bytes.count - offset
                    )
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else {
                        throw POSIXError(Self.posixCode(errno))
                    }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            var status = stat()
            guard fstat(descriptor, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFREG,
                  Int(status.st_size) == data.count else {
                throw VaultRepositoryError.commitUncertain(
                    "The imported attachment did not preserve its exact bytes."
                )
            }
            shouldRemove = false
            guard fsync(parentDescriptor) == 0 else {
                throw VaultRepositoryError.commitUncertain(
                    "The imported attachment directory could not be synchronized."
                )
            }
        }
        let readback = try Self.readStableRegularFile(
            at: canonicalRoot.appendingPathComponent(relativePath.rawValue)
        )
        guard readback == data else {
            throw VaultRepositoryError.commitUncertain(
                "The imported attachment did not preserve its exact bytes."
            )
        }
    }

    private func deleteExactFile(
        relativePath: AttachmentRelativePath,
        expectedFingerprint: DocumentFingerprint
    ) throws {
        try withParentDescriptor(relativePath: relativePath, createDirectories: false) {
            parentDescriptor, name in
            let descriptor = openat(
                parentDescriptor,
                name,
                O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            )
            guard descriptor >= 0 else {
                throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
            }
            defer { Darwin.close(descriptor) }
            var opened = stat()
            guard fstat(descriptor, &opened) == 0,
                  (opened.st_mode & S_IFMT) == S_IFREG else {
                throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
            }
            let data = try VaultDescriptorAccess.readAll(from: descriptor)
            var current = stat()
            guard fstatat(parentDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  current.st_dev == opened.st_dev,
                  current.st_ino == opened.st_ino,
                  DocumentFingerprint(data: data) == expectedFingerprint else {
                throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
            }
            guard unlinkat(parentDescriptor, name, 0) == 0,
                  fsync(parentDescriptor) == 0 else {
                throw ImageAttachmentError.cleanupRefused(relativePath.rawValue)
            }
        }
    }

    private func withParentDescriptor<T>(
        relativePath: AttachmentRelativePath,
        createDirectories: Bool,
        _ body: (Int32, String) throws -> T
    ) throws -> T {
        let components = relativePath.components.map(String.init)
        guard let name = components.last else {
            throw AttachmentRelativePathError.invalid(relativePath.rawValue)
        }
        let rootDescriptor = Darwin.open(
            canonicalRoot.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard rootDescriptor >= 0 else {
            throw POSIXError(Self.posixCode(errno))
        }
        defer { Darwin.close(rootDescriptor) }

        var currentDescriptor = rootDescriptor
        var ownedDescriptor: Int32?
        defer {
            if let ownedDescriptor { Darwin.close(ownedDescriptor) }
        }
        for component in components.dropLast() {
            var nextDescriptor = openat(
                currentDescriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
            if nextDescriptor < 0, errno == ENOENT, createDirectories {
                guard mkdirat(currentDescriptor, component, mode_t(0o755)) == 0
                        || errno == EEXIST else {
                    throw POSIXError(Self.posixCode(errno))
                }
                nextDescriptor = openat(
                    currentDescriptor,
                    component,
                    O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                )
            }
            guard nextDescriptor >= 0 else {
                throw POSIXError(Self.posixCode(errno))
            }
            if let ownedDescriptor { Darwin.close(ownedDescriptor) }
            ownedDescriptor = nextDescriptor
            currentDescriptor = nextDescriptor
        }
        return try body(currentDescriptor, name)
    }

    private static func posixCode(_ value: Int32) -> POSIXErrorCode {
        POSIXErrorCode(rawValue: value) ?? .EIO
    }

    private static func markdownDestination(
        from noteRelativePath: String,
        to attachmentPath: AttachmentRelativePath
    ) -> String {
        var noteComponents = noteRelativePath.split(separator: "/").map(String.init)
        if !noteComponents.isEmpty { noteComponents.removeLast() }
        var attachmentComponents = attachmentPath.components.map(String.init)
        while let noteFirst = noteComponents.first,
              let attachmentFirst = attachmentComponents.first,
              noteFirst == attachmentFirst {
            noteComponents.removeFirst()
            attachmentComponents.removeFirst()
        }
        let relativeComponents = Array(repeating: "..", count: noteComponents.count)
            + attachmentComponents
        return relativeComponents.map(percentEncodedPathComponent).joined(separator: "/")
    }

    private static func absoluteMarkdownDestination(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { percentEncodedPathComponent(String($0)) }
            .joined(separator: "/")
    }

    private static func percentEncodedPathComponent(_ component: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
