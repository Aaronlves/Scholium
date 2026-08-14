import Foundation
import ScholiumContracts

public enum IndexedAttachmentAccessError: LocalizedError, Sendable {
    case damaged(String)
    case bookmarkUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .damaged(let reason):
            "The machine-local indexed-attachment access store is damaged: \(reason)"
        case .bookmarkUnavailable(let path):
            "Scholium could not retain read access to the indexed attachment at \(path)."
        }
    }
}

/// Machine-local read authorization for absolute-path Index records. The
/// portable catalog and authored Markdown retain only the absolute path;
/// bookmark bytes never enter a vault and never authorize path repair.
public actor IndexedAttachmentAccessStore {
    private static let currentSchemaVersion = 1
    private static let fileName = "indexed-attachments-v1.json"

    private struct Binding: Codable, Hashable {
        let attachmentID: UUID
        let absolutePath: String
        let bookmarkData: Data
    }

    private struct Payload: Codable, Hashable {
        let schemaVersion: Int
        let triptychID: UUID
        var bindings: [Binding]
    }

    private let triptychID: UUID
    private let directory: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        directory = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "attachment-access",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 16 * 1_024 * 1_024
        )
        try directory.ensureDirectories([])
        lock = try AdvisoryFileLock(
            directory: directory,
            fileName: "indexed-attachments.lock"
        )
    }

    @discardableResult
    public func register(
        attachmentID: UUID,
        selectedURL: URL,
        expectedAbsolutePath: String
    ) throws -> Bool {
        try lock.withExclusiveLock {
            let canonical = selectedURL.resolvingSymlinksInPath().standardizedFileURL
            guard canonical.path == expectedAbsolutePath else {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(
                    expectedAbsolutePath
                )
            }
            let direct = try selectedURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard direct.isRegularFile == true, direct.isSymbolicLink != true else {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(
                    expectedAbsolutePath
                )
            }
            let bookmark: Data
            do {
                bookmark = try canonical.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: [
                        .fileResourceIdentifierKey,
                        .isRegularFileKey,
                    ],
                    relativeTo: nil
                )
            } catch {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(
                    expectedAbsolutePath
                )
            }
            var stale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale,
                  resolved.resolvingSymlinksInPath().standardizedFileURL.path
                    == expectedAbsolutePath else {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(
                    expectedAbsolutePath
                )
            }
            let started = resolved.startAccessingSecurityScopedResource()
            defer {
                if started { resolved.stopAccessingSecurityScopedResource() }
            }
            let resolvedValues = try resolved.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard resolvedValues.isRegularFile == true,
                  resolvedValues.isSymbolicLink != true else {
                throw IndexedAttachmentAccessError.bookmarkUnavailable(
                    expectedAbsolutePath
                )
            }

            var payload = try load()
            let created = !payload.bindings.contains {
                $0.attachmentID == attachmentID
            }
            payload.bindings.removeAll { $0.attachmentID == attachmentID }
            payload.bindings.append(Binding(
                attachmentID: attachmentID,
                absolutePath: expectedAbsolutePath,
                bookmarkData: bookmark
            ))
            payload.bindings.sort {
                $0.attachmentID.uuidString < $1.attachmentID.uuidString
            }
            try persist(payload)
            return created
        }
    }

    public func isAvailable(
        attachmentID: UUID,
        expectedAbsolutePath: String
    ) throws -> Bool {
        try lock.withSharedLock {
            guard let binding = try load().bindings.first(where: {
                $0.attachmentID == attachmentID
            }), binding.absolutePath == expectedAbsolutePath else { return false }
            var stale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: binding.bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale,
                  resolved.resolvingSymlinksInPath().standardizedFileURL.path
                    == expectedAbsolutePath else { return false }
            let started = resolved.startAccessingSecurityScopedResource()
            defer {
                if started { resolved.stopAccessingSecurityScopedResource() }
            }
            guard let values = try? resolved.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }

    public func removeIfPresent(attachmentID: UUID) throws {
        try lock.withExclusiveLock {
            var payload = try load()
            let originalCount = payload.bindings.count
            payload.bindings.removeAll { $0.attachmentID == attachmentID }
            guard payload.bindings.count != originalCount else { return }
            try persist(payload)
        }
    }

    private func load() throws -> Payload {
        let data: Data?
        do {
            data = try directory.readIfPresent(
                directory: nil,
                fileName: Self.fileName
            )
        } catch {
            throw IndexedAttachmentAccessError.damaged(error.localizedDescription)
        }
        guard let data else {
            return Payload(
                schemaVersion: Self.currentSchemaVersion,
                triptychID: triptychID,
                bindings: []
            )
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.currentSchemaVersion,
              payload.triptychID == triptychID,
              Set(payload.bindings.map(\.attachmentID)).count
                == payload.bindings.count else {
            throw IndexedAttachmentAccessError.damaged(
                "The stored JSON is invalid or uses an unsupported schema."
            )
        }
        return payload
    }

    private func persist(_ payload: Payload) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let candidate = try encoder.encode(payload)
        do {
            if try directory.readIfPresent(
                directory: nil,
                fileName: Self.fileName
            ) == nil {
                _ = try directory.createExclusive(
                    candidate,
                    directory: nil,
                    fileName: Self.fileName
                )
            } else {
                _ = try directory.replace(
                    candidate,
                    directory: nil,
                    fileName: Self.fileName
                )
            }
        } catch {
            throw IndexedAttachmentAccessError.damaged(error.localizedDescription)
        }
    }
}
