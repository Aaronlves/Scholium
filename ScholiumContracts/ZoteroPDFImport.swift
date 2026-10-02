import Foundation

/// Exact provenance for a separate Scholium PDF copy. Zotero remains the
/// authority for the library item; this value never authorizes a Zotero write.
public struct ZoteroPDFSource: Codable, Hashable, Sendable, Identifiable {
    public enum LinkMode: String, Codable, Hashable, Sendable {
        case importedFile = "imported_file"
        case importedURL = "imported_url"
        case linkedFile = "linked_file"
    }

    public let library: ZoteroLibraryMetadata
    public let item: ZoteroItemMetadata
    public let attachmentKey: String
    public let attachmentVersion: Int
    public let title: String
    public let filename: String
    public let linkMode: LinkMode
    public let serverID: String
    public let attachmentMetadataFingerprint: DocumentFingerprint

    public var id: String { stableIdentity }

    /// Local user-library key spaces are partitioned by their Zotero database.
    /// Prefixing the server ID's length avoids delimiter ambiguity.
    public var stableIdentity: String {
        let libraryID: String
        switch library.identity {
        case .user: libraryID = "user"
        case .group(let groupID): libraryID = "group:\(groupID)"
        }
        return "\(serverID.utf8.count):\(serverID):\(libraryID):\(attachmentKey)"
    }

    public var itemReference: ZoteroReference {
        // The initializer and decoder validate both references.
        try! ZoteroReference(library: library.identity, itemKey: item.key)
    }

    public var pdfReference: ZoteroReference {
        try! ZoteroReference(library: library.identity, kind: .pdf, itemKey: attachmentKey)
    }

    public init(
        library: ZoteroLibraryMetadata, item: ZoteroItemMetadata,
        attachmentKey: String, attachmentVersion: Int, title: String,
        filename: String, linkMode: LinkMode, serverID: String,
        attachmentMetadataFingerprint: DocumentFingerprint
    ) throws {
        guard ZoteroReference.normalizedKey(item.key) == item.key,
            ZoteroReference.normalizedKey(attachmentKey) == attachmentKey,
            attachmentVersion >= 0,
            !filename.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent,
            filename != ".", filename != "..", !filename.contains("\0"),
            URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf",
            Self.validServerID(serverID),
            attachmentMetadataFingerprint.sha256.utf8.count == 64,
            attachmentMetadataFingerprint.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            attachmentMetadataFingerprint.byteCount > 0
        else { throw ZoteroPDFImportError.invalidResponse }
        _ = try ZoteroReference(library: library.identity, itemKey: item.key)
        _ = try ZoteroReference(library: library.identity, kind: .pdf, itemKey: attachmentKey)
        self.library = library
        self.item = item
        self.attachmentKey = attachmentKey
        self.attachmentVersion = attachmentVersion
        self.title = title
        self.filename = filename
        self.linkMode = linkMode
        self.serverID = serverID
        self.attachmentMetadataFingerprint = attachmentMetadataFingerprint
    }

    public static func validServerID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256
            && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private enum CodingKeys: String, CodingKey {
        case library, item, title, filename, linkMode, serverID
        case attachmentKey, attachmentVersion, attachmentMetadataFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            library: container.decode(ZoteroLibraryMetadata.self, forKey: .library),
            item: container.decode(ZoteroItemMetadata.self, forKey: .item),
            attachmentKey: container.decode(String.self, forKey: .attachmentKey),
            attachmentVersion: container.decode(Int.self, forKey: .attachmentVersion),
            title: container.decode(String.self, forKey: .title),
            filename: container.decode(String.self, forKey: .filename),
            linkMode: container.decode(LinkMode.self, forKey: .linkMode),
            serverID: container.decode(String.self, forKey: .serverID),
            attachmentMetadataFingerprint: container.decode(DocumentFingerprint.self, forKey: .attachmentMetadataFingerprint))
    }
}

/// A validated local locator, not proof that original bytes exist or are readable.
/// The import owner reads a coordinated snapshot and revalidates before commit.
public struct ZoteroPDFImportCandidate: Hashable, Sendable {
    public let source: ZoteroPDFSource
    public let originalURL: URL

    public init(source: ZoteroPDFSource, originalURL: URL) {
        self.source = source
        self.originalURL = originalURL
    }
}

/// A session-only observation from an API without database identity. These
/// fields can detect observed drift; they never establish Zotero provenance.
public struct ZoteroPDFLocalCopyObservation: Hashable, Sendable {
    public let library: ZoteroLibraryMetadata
    public let observedLibraryID: Int
    public let item: ZoteroItemMetadata
    public let parentVersion: Int
    public let parentMetadataFingerprint: DocumentFingerprint
    public let attachmentKey: String
    public let attachmentVersion: Int
    public let attachmentMetadataFingerprint: DocumentFingerprint
    public let title: String
    public let filename: String
    public let linkMode: ZoteroPDFSource.LinkMode

    public init(
        library: ZoteroLibraryMetadata, observedLibraryID: Int, item: ZoteroItemMetadata,
        parentVersion: Int, parentMetadataFingerprint: DocumentFingerprint,
        attachmentKey: String, attachmentVersion: Int, attachmentMetadataFingerprint: DocumentFingerprint,
        title: String, filename: String, linkMode: ZoteroPDFSource.LinkMode
    ) throws {
        guard observedLibraryID >= 0, parentVersion >= 0, attachmentVersion >= 0,
            ZoteroReference.normalizedKey(item.key) == item.key,
            ZoteroReference.normalizedKey(attachmentKey) == attachmentKey,
            !filename.isEmpty, filename == URL(fileURLWithPath: filename).lastPathComponent,
            filename != ".", filename != "..", !filename.contains("\0"),
            URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf",
            Self.validFingerprint(parentMetadataFingerprint), Self.validFingerprint(attachmentMetadataFingerprint)
        else { throw ZoteroPDFImportError.invalidResponse }
        if case .group(let groupID) = library.identity {
            guard groupID > 0, observedLibraryID == groupID else { throw ZoteroPDFImportError.invalidResponse }
        }
        self.library = library
        self.observedLibraryID = observedLibraryID
        self.item = item
        self.parentVersion = parentVersion
        self.parentMetadataFingerprint = parentMetadataFingerprint
        self.attachmentKey = attachmentKey
        self.attachmentVersion = attachmentVersion
        self.attachmentMetadataFingerprint = attachmentMetadataFingerprint
        self.title = title
        self.filename = filename
        self.linkMode = linkMode
    }

    private static func validFingerprint(_ value: DocumentFingerprint) -> Bool {
        value.byteCount > 0 && value.sha256.utf8.count == 64
            && value.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    }
}

/// The researcher confirms this exact file as a local copy. It is deliberately
/// not Codable and carries no database identity or retained source mapping.
public struct ZoteroPDFLocalCopyCandidate: Hashable, Sendable {
    public let observation: ZoteroPDFLocalCopyObservation
    public let originalURL: URL

    public init(observation: ZoteroPDFLocalCopyObservation, originalURL: URL) {
        self.observation = observation
        self.originalURL = originalURL
    }
}

/// Discovery keeps verified provenance and a plain-file choice visibly distinct.
public enum ZoteroPDFImportOption: Hashable, Sendable, Identifiable {
    case verifiedSource(ZoteroPDFSource)
    case localCopy(ZoteroPDFLocalCopyObservation)

    /// Only a picker-session row identity for local copies, never durable dedup.
    public var id: String {
        switch self {
        case .verifiedSource(let source): source.id
        case .localCopy(let observation): "local:\(observation.library.id):\(observation.item.key):\(observation.attachmentKey)"
        }
    }

    public var title: String {
        switch self {
        case .verifiedSource(let source): source.title
        case .localCopy(let observation): observation.title
        }
    }

    public var filename: String {
        switch self {
        case .verifiedSource(let source): source.filename
        case .localCopy(let observation): observation.filename
        }
    }
}

public enum ZoteroPDFImportError: LocalizedError, Equatable, Sendable {
    case importUnavailable
    case invalidResponse
    case stableIdentityUnavailable
    case sourceChanged
    case tooManyAttachments
    case originalUnavailable

    public var errorDescription: String? {
        switch self {
        case .importUnavailable:
            "PDF import is unavailable through this Zotero connection."
        case .invalidResponse:
            "Zotero returned a PDF attachment Scholium could not verify. Refresh and choose the attachment again."
        case .stableIdentityUnavailable:
            "Scholium could not verify this Zotero connection's database identity. Check the connection and search again, or choose the PDF file directly."
        case .sourceChanged:
            "The Zotero item or attachment changed. Search again before importing its PDF."
        case .tooManyAttachments:
            "This Zotero item has too many attachments to select safely. Choose its PDF from Finder instead."
        case .originalUnavailable:
            "Zotero did not provide a local PDF file. Open the attachment in Zotero, download it if needed, and try again."
        }
    }
}

extension ZoteroUseCases {
    /// A substitute connection without PDF behavior fails explicitly. The live
    /// runtime-owned ZoteroOperations supplies the concrete operations.
    public func pdfAttachments(for hit: ZoteroSearchHit) async throws -> [ZoteroPDFSource] {
        throw ZoteroPDFImportError.importUnavailable
    }

    public func resolvePDFImport(_ source: ZoteroPDFSource) async throws -> ZoteroPDFImportCandidate {
        throw ZoteroPDFImportError.importUnavailable
    }

    public func revalidatePDFImport(_ candidate: ZoteroPDFImportCandidate) async throws {
        throw ZoteroPDFImportError.importUnavailable
    }

    public func pdfImportOptions(for hit: ZoteroSearchHit) async throws -> [ZoteroPDFImportOption] {
        throw ZoteroPDFImportError.importUnavailable
    }

    public func resolvePDFLocalCopy(_ observation: ZoteroPDFLocalCopyObservation) async throws -> ZoteroPDFLocalCopyCandidate {
        throw ZoteroPDFImportError.importUnavailable
    }

    public func revalidatePDFLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate) async throws {
        throw ZoteroPDFImportError.importUnavailable
    }
}
