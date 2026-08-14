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
              !rawValue.contains("\0") else {
            throw AttachmentRelativePathError.invalid(rawValue)
        }
        let components = rawValue.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.contains(where: {
            $0.isEmpty || $0 == "." || $0 == ".."
        }) else {
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

public enum AttachmentLocation: Codable, Hashable, Sendable {
    case vaultRelative(AttachmentRelativePath)
    case absolutePath(String)

    public var path: String {
        switch self {
        case .vaultRelative(let path): path.rawValue
        case .absolutePath(let path): path
        }
    }

    public init(absolutePath: String) throws {
        guard absolutePath.hasPrefix("/"),
              !absolutePath.contains("\0"),
              URL(fileURLWithPath: absolutePath).standardizedFileURL.path
                == absolutePath else {
            throw ImageAttachmentError.invalidAbsolutePath(absolutePath)
        }
        self = .absolutePath(absolutePath)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
    }

    private enum Kind: String, Codable {
        case vaultRelative
        case absolutePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .vaultRelative:
            self = .vaultRelative(try AttachmentRelativePath(
                container.decode(String.self, forKey: .path)
            ))
        case .absolutePath:
            try self.init(absolutePath: container.decode(String.self, forKey: .path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vaultRelative(let path):
            try container.encode(Kind.vaultRelative, forKey: .kind)
            try container.encode(path.rawValue, forKey: .path)
        case .absolutePath(let path):
            try container.encode(Kind.absolutePath, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}

/// One portable identity-to-path association. The record intentionally owns
/// no attachment metadata and can never reconstruct, repair, move, or delete
/// the Finder-authoritative file.
public struct PortableAttachmentRecord: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

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

public struct PreparedImageAttachment: Hashable, Sendable {
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
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum ImageAttachmentError: LocalizedError, Equatable, Sendable {
    case unsupportedImage(String)
    case invalidAbsolutePath(String)
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
        case .invalidAbsolutePath(let path):
            "Choose a file with a valid absolute path: \(path)"
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

private struct AbsoluteImagePathCollector: MarkupWalker {
    var paths: Set<String> = []

    mutating func visitDocument(_ document: Document) { descendInto(document) }

    mutating func visitImage(_ image: Image) {
        guard let destination = image.source,
              let decoded = destination.removingPercentEncoding,
              decoded.hasPrefix("/"),
              let location = try? AttachmentLocation(absolutePath: decoded),
              case .absolutePath(let path) = location else { return }
        paths.insert(path)
    }
}
