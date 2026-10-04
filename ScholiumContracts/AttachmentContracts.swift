import Foundation
import Markdown

public enum AttachmentRelativePathError: LocalizedError, Equatable, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let path):
            "Invalid attachment vault-relative path: \(path)"
        }
    }
}

/// Byte-preserving path spelling for one regular attachment file inside a
/// vault. Finder owns the bytes; this value provides a contained portable
/// address for an imported attachment.
public struct AttachmentRelativePath: Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
            !rawValue.hasPrefix("/"),
            !rawValue.hasSuffix("/"),
            !rawValue.contains("\0")
        else {
            throw AttachmentRelativePathError.invalid(rawValue)
        }
        let components = rawValue.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard
            !components.contains(where: {
                $0.isEmpty || $0 == "." || $0 == ".."
            })
        else {
            throw AttachmentRelativePathError.invalid(rawValue)
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public var components: [Substring] {
        rawValue.split(separator: "/", omittingEmptySubsequences: false)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ExternalAttachmentReferenceError: LocalizedError, Equatable, Sendable {
    case invalidFilename(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFilename(let filename):
            "Invalid external attachment filename: \(filename)"
        }
    }
}

/// Portable description of a Finder-owned attachment. The selected path is
/// deliberately absent; it belongs to the machine-local access store.
public struct ExternalAttachmentReference: Codable, Hashable, Sendable {
    public let filename: String

    private enum CodingKeys: String, CodingKey {
        case filename
    }

    public init(filename: String) throws {
        guard !filename.isEmpty,
            !filename.contains("\0"),
            URL(fileURLWithPath: filename).lastPathComponent == filename,
            filename != ".",
            filename != ".."
        else {
            throw ExternalAttachmentReferenceError.invalidFilename(filename)
        }
        self.filename = filename
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(filename: container.decode(String.self, forKey: .filename))
    }
}

/// Portable attachment locations contain only a vault-relative address or a
/// neutral descriptor for a machine-local Finder reference. Absolute paths
/// and security-scoped bookmarks never cross this boundary.
public enum AttachmentLocation: Codable, Hashable, Sendable {
    case vaultRelative(AttachmentRelativePath)
    case external(ExternalAttachmentReference)

    public var filename: String {
        switch self {
        case .vaultRelative(let path):
            URL(fileURLWithPath: path.rawValue).lastPathComponent
        case .external(let reference):
            reference.filename
        }
    }

    public var isExternal: Bool {
        if case .external = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case filename
    }

    private enum Kind: String, Codable {
        case vaultRelative
        case external
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .vaultRelative:
            self = .vaultRelative(
                try AttachmentRelativePath(
                    container.decode(String.self, forKey: .path)
                ))
        case .external:
            self = .external(
                try ExternalAttachmentReference(
                    filename: container.decode(String.self, forKey: .filename)
                ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vaultRelative(let path):
            try container.encode(Kind.vaultRelative, forKey: .kind)
            try container.encode(path.rawValue, forKey: .path)
        case .external(let reference):
            try container.encode(Kind.external, forKey: .kind)
            try container.encode(reference.filename, forKey: .filename)
        }
    }
}

/// One portable identity-to-attachment association. External records retain
/// only a neutral filename; the machine-local access store owns the selected
/// path and security-scoped bookmark.
public struct PortableAttachmentRecord: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let id: UUID
    public let vaultID: UUID
    public let location: AttachmentLocation

    public init(
        id: UUID,
        vaultID: UUID,
        location: AttachmentLocation
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.vaultID = vaultID
        self.location = location
    }

    public var filename: String { location.filename }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case vaultID
        case location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported attachment schema \(schemaVersion)."
            )
        }
        self.schemaVersion = schemaVersion
        id = try container.decode(UUID.self, forKey: .id)
        vaultID = try container.decode(UUID.self, forKey: .vaultID)
        location = try container.decode(AttachmentLocation.self, forKey: .location)
    }
}

public struct PreparedSourceAttachment: Hashable, Sendable {
    public let record: PortableAttachmentRecord
    public let markdownDestination: String
    public let altText: String
    public let copiedFileFingerprint: DocumentFingerprint?
    public let createdCatalogRecord: Bool
    public let createdLocalAccessRecord: Bool

    public init(
        record: PortableAttachmentRecord,
        markdownDestination: String,
        altText: String,
        copiedFileFingerprint: DocumentFingerprint?,
        createdCatalogRecord: Bool,
        createdLocalAccessRecord: Bool = false
    ) {
        self.record = record
        self.markdownDestination = markdownDestination
        self.altText = altText
        self.copiedFileFingerprint = copiedFileFingerprint
        self.createdCatalogRecord = createdCatalogRecord
        self.createdLocalAccessRecord = createdLocalAccessRecord
    }

    public var editorArgument: String {
        let object = [
            "alt": altText,
            "destination": markdownDestination,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Exact Note identity and location checked before preparing or opening a source attachment.
public struct SourceAttachmentTarget: Hashable, Sendable {
    public let noteID: UUID
    public let vaultID: UUID
    public let relativePath: String

    public init(noteID: UUID, vaultID: UUID, relativePath: String) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
    }
}

public enum DocumentAttachmentManagement: String, Codable, Hashable, Sendable {
    case copyIntoTriptych
    case referenceOriginal
}

public enum DocumentAttachmentAvailability: String, Codable, Hashable, Sendable {
    case available
    case unavailable
}

/// Read-only source-derived file projection with machine-local availability.
public struct DocumentAttachmentSnapshot: Codable, Hashable, Sendable {
    public let record: PortableAttachmentRecord
    public let availability: DocumentAttachmentAvailability

    public init(
        record: PortableAttachmentRecord,
        availability: DocumentAttachmentAvailability
    ) {
        self.record = record
        self.availability = availability
    }
}

/// Bounded access prepared for one native Quick Look presentation. Callers
/// must release `accessToken` when the preview closes.
public struct DocumentAttachmentPreviewLease: Hashable, Sendable {
    public let accessToken: UUID
    public let attachmentID: UUID
    public let filename: String
    public let fileURL: URL

    public init(
        accessToken: UUID,
        attachmentID: UUID,
        filename: String,
        fileURL: URL
    ) {
        self.accessToken = accessToken
        self.attachmentID = attachmentID
        self.filename = filename
        self.fileURL = fileURL
    }
}

public enum DocumentAttachmentError: LocalizedError, Equatable, Sendable {
    case unsupportedDocument(String)
    case noteIdentityChanged(String)
    case unavailable(String)
    case cleanupRefused(String)
    case preparationCleanupFailed(operation: String, cleanup: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedDocument(let path):
            "Choose a regular document file rather than image, audio, or video media: \(path)"
        case .noteIdentityChanged(let path):
            "The Note identity at \(path) changed before the document could be attached. Reload the workspace and try again."
        case .unavailable(let filename):
            "The attached document is unavailable on this Mac: \(filename)"
        case .cleanupRefused(let path):
            "Scholium left the copied document at \(path) in place because it could not prove that the file was created by this attachment."
        case .preparationCleanupFailed(let operation, let cleanup):
            "Document attachment failed, and Scholium could not complete exact cleanup. Do not repeat the operation until the Triptych is inspected. Operation: \(operation) Cleanup: \(cleanup)"
        }
    }
}

public enum ImageAttachmentError: LocalizedError, Equatable, Sendable {
    case unsupportedImage(String)
    case sourceChanged(String)
    case invalidCatalog
    case catalogConflict
    case catalogCommitUncertain(String)
    case cleanupRefused(String)
    case preparationCleanupFailed(operation: String, cleanup: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedImage(let path):
            "Choose a supported image file: \(path)"
        case .sourceChanged(let path):
            "The selected image changed while Scholium was reading it: \(path)"
        case .invalidCatalog:
            "The portable attachment catalog is damaged or uses an unsupported schema. Its exact bytes were preserved."
        case .catalogConflict:
            "The portable attachment catalog changed while Scholium was updating it. Reload the workspace before trying again."
        case .catalogCommitUncertain(let reason):
            "Scholium could not prove the final state of the portable attachment catalog. The image file was preserved for inspection: \(reason)"
        case .cleanupRefused(let path):
            "Scholium left the attachment at \(path) in place because it could not prove that the file was created by this insertion."
        case .preparationCleanupFailed(let operation, let cleanup):
            "Attachment preparation failed, and Scholium could not complete exact cleanup. Do not repeat the insertion until the vault is inspected. Operation: \(operation) Cleanup: \(cleanup)"
        }
    }
}

public enum IndexedImageReferences {
    public static func relativePaths(in markdownSource: String, noteRelativePath: String) -> Set<AttachmentRelativePath> {
        var collector = RelativeImagePathCollector(directory: noteRelativePath.split(separator: "/").dropLast().map(String.init))
        collector.visit(Document(parsing: markdownSource, options: [.parseBlockDirectives, .parseSymbolLinks]))
        return collector.paths
    }

    public static func absolutePaths(in markdownSource: String) -> Set<String> {
        let document = Document(
            parsing: markdownSource,
            options: [.parseBlockDirectives, .parseSymbolLinks]
        )
        var collector = AbsoluteImagePathCollector()
        collector.visit(document)
        return collector.paths
    }
}

private struct RelativeImagePathCollector: MarkupWalker {
    let directory: [String]
    var paths: Set<AttachmentRelativePath> = []
    mutating func visitDocument(_ document: Document) { descendInto(document) }
    mutating func visitImage(_ image: Image) {
        guard let raw = image.source, let path = raw.removingPercentEncoding, !path.contains("\0") else { return }
        guard !path.hasPrefix("/") else { return }
        guard URLComponents(string: raw)?.scheme == nil, !raw.hasPrefix("//") else { return }
        var components = directory
        for part in path.split(separator: "/", omittingEmptySubsequences: false) {
            if part == "." { continue }
            if part == ".." {
                guard !components.isEmpty else { return }
                components.removeLast()
            } else {
                guard !part.isEmpty else { return }
                components.append(String(part))
            }
        }
        if let relative = try? AttachmentRelativePath(components.joined(separator: "/")) { paths.insert(relative) }
    }
}

private struct AbsoluteImagePathCollector: MarkupWalker {
    var paths: Set<String> = []

    mutating func visitDocument(_ document: Document) { descendInto(document) }

    mutating func visitImage(_ image: Image) {
        guard let destination = image.source,
            let decoded = destination.removingPercentEncoding,
            decoded.hasPrefix("/"),
            URL(fileURLWithPath: decoded).standardizedFileURL.path == decoded
        else { return }
        paths.insert(decoded)
    }
}
