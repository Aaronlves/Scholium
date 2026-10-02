import Foundation
import ScholiumContracts

extension ZoteroOperations {
    /// Enumerates only actual PDF file attachments under the exact selected
    /// bibliographic item. Requests share the runtime's existing local transport.
    public func pdfAttachments(for hit: ZoteroSearchHit) async throws -> [ZoteroPDFSource] {
        guard ZoteroReference.normalizedKey(hit.item.key) == hit.item.key else { throw ZoteroUseCaseError.invalidItemKey }
        let parent = try await requestResponse(
            library: hit.library.identity, path: "items/\(hit.item.key)",
            query: [URLQueryItem(name: "format", value: "json")])
        return try await pdfAttachments(for: hit, parent: parent)
    }

    private func pdfAttachments(for hit: ZoteroSearchHit, parent: LocalReadResponse) async throws -> [ZoteroPDFSource] {
        let serverID = try Self.pdfServerID(parent.serverID)
        let item = try Self.pdfParent(from: parent.data, key: hit.item.key)
        guard item == hit.item else { throw ZoteroPDFImportError.sourceChanged }
        let response = try await requestResponse(
            library: hit.library.identity, path: "items/\(hit.item.key)/children",
            query: [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "itemType", value: "attachment"),
                URLQueryItem(name: "limit", value: "101"),
            ], serverID: serverID)
        let objects = try Self.pdfObjects(from: response.data)
        guard objects.count <= 100, response.totalResults.map({ $0 <= 100 }) != false else {
            throw ZoteroPDFImportError.tooManyAttachments
        }
        var sources: [ZoteroPDFSource] = []
        for object in objects {
            guard let data = object["data"] as? [String: Any] else { throw ZoteroPDFImportError.invalidResponse }
            guard data["itemType"] as? String == "attachment", data["contentType"] as? String == "application/pdf" else { continue }
            guard ZoteroPDFSource.LinkMode(rawValue: data["linkMode"] as? String ?? "") != nil else { continue }
            sources.append(try Self.pdfSource(object: object, library: hit.library, item: item, serverID: serverID))
        }
        guard Set(sources.map(\.attachmentKey)).count == sources.count else { throw ZoteroPDFImportError.invalidResponse }
        try Task.checkCancellation()
        return sources.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.attachmentKey < $1.attachmentKey : order == .orderedAscending
        }
    }

    /// A missing database ID offers only an explicit plain-file choice. A
    /// malformed ID never downgrades a server into the local-copy branch.
    public func pdfImportOptions(for hit: ZoteroSearchHit) async throws -> [ZoteroPDFImportOption] {
        guard ZoteroReference.normalizedKey(hit.item.key) == hit.item.key else { throw ZoteroUseCaseError.invalidItemKey }
        let parent = try await requestResponse(
            library: hit.library.identity, path: "items/\(hit.item.key)",
            query: [URLQueryItem(name: "format", value: "json")])
        if parent.serverID != nil {
            return try await pdfAttachments(for: hit, parent: parent).map(ZoteroPDFImportOption.verifiedSource)
        }
        let item = try Self.pdfParent(from: parent.data, key: hit.item.key)
        guard item == hit.item else { throw ZoteroPDFImportError.sourceChanged }
        let parentObject = try Self.pdfSingleObject(from: parent.data)
        let parentEnvelope = try Self.pdfObservedEnvelope(object: parentObject, library: hit.library.identity, key: item.key)
        let response = try await localCopyResponse(
            library: hit.library.identity, path: "items/\(item.key)/children",
            query: [
                URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "itemType", value: "attachment"),
                URLQueryItem(name: "limit", value: "101"),
            ])
        let objects = try Self.pdfObjects(from: response.data)
        guard objects.count <= 100, response.totalResults.map({ $0 <= 100 }) != false else { throw ZoteroPDFImportError.tooManyAttachments }
        var observations: [ZoteroPDFLocalCopyObservation] = []
        for object in objects {
            guard let data = object["data"] as? [String: Any] else { throw ZoteroPDFImportError.invalidResponse }
            guard data["itemType"] as? String == "attachment", data["contentType"] as? String == "application/pdf",
                ZoteroPDFSource.LinkMode(rawValue: data["linkMode"] as? String ?? "") != nil
            else { continue }
            observations.append(
                try Self.pdfLocalCopyObservation(
                    object: object, library: hit.library, item: item, parent: parentEnvelope))
        }
        guard Set(observations.map(\.attachmentKey)).count == observations.count else { throw ZoteroPDFImportError.invalidResponse }
        try Task.checkCancellation()
        return observations.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.attachmentKey < $1.attachmentKey : order == .orderedAscending
        }.map(ZoteroPDFImportOption.localCopy)
    }

    public func resolvePDFLocalCopy(_ observation: ZoteroPDFLocalCopyObservation) async throws -> ZoteroPDFLocalCopyCandidate {
        let attachment = try await localCopyResponse(
            library: observation.library.identity, path: "items/\(observation.attachmentKey)",
            query: [URLQueryItem(name: "format", value: "json")])
        let parent = try await localCopyResponse(
            library: observation.library.identity, path: "items/\(observation.item.key)",
            query: [URLQueryItem(name: "format", value: "json")])
        let parentEnvelope = try Self.pdfObservedEnvelope(
            object: Self.pdfSingleObject(from: parent.data), library: observation.library.identity, key: observation.item.key)
        guard parentEnvelope.version == observation.parentVersion,
            parentEnvelope.fingerprint == observation.parentMetadataFingerprint,
            parentEnvelope.libraryID == observation.observedLibraryID,
            try Self.pdfParent(from: parent.data, key: observation.item.key) == observation.item
        else { throw ZoteroPDFImportError.sourceChanged }
        let current = try Self.pdfLocalCopyObservation(
            object: Self.pdfSingleObject(from: attachment.data), library: observation.library, item: observation.item, parent: parentEnvelope)
        guard current == observation else { throw ZoteroPDFImportError.sourceChanged }
        let locator = try await localCopyResponse(
            library: observation.library.identity, path: "items/\(observation.attachmentKey)/file/view/url", query: [])
        let url = try Self.pdfOriginalURL(from: locator.data, filename: observation.filename)
        try Task.checkCancellation()
        return ZoteroPDFLocalCopyCandidate(observation: observation, originalURL: url)
    }

    /// Rechecking equal observations does not prove a database identity. It
    /// only admits the explicitly confirmed local file snapshot for copying.
    public func revalidatePDFLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate) async throws {
        let current = try await resolvePDFLocalCopy(candidate.observation)
        guard current.originalURL == candidate.originalURL else { throw ZoteroPDFImportError.sourceChanged }
    }

    private func localCopyResponse(library: ZoteroLibraryIdentity, path: String, query: [URLQueryItem]) async throws -> LocalReadResponse {
        let response = try await requestResponse(library: library, path: path, query: query)
        guard response.serverID == nil else { throw ZoteroPDFImportError.sourceChanged }
        return response
    }

    /// Resolves a selected attachment through Zotero's own current path mapping.
    /// Metadata paths are never used to derive or open the original file.
    public func resolvePDFImport(_ source: ZoteroPDFSource) async throws -> ZoteroPDFImportCandidate {
        let response = try await requestResponse(
            library: source.library.identity, path: "items/\(source.attachmentKey)",
            query: [URLQueryItem(name: "format", value: "json")], serverID: source.serverID)
        let objects = try Self.pdfObjects(from: response.data)
        guard objects.count == 1, let object = objects.first else { throw ZoteroPDFImportError.invalidResponse }
        let current = try Self.pdfSource(object: object, library: source.library, item: source.item, serverID: source.serverID)
        guard current == source else { throw ZoteroPDFImportError.sourceChanged }
        let parent = try await requestResponse(
            library: source.library.identity, path: "items/\(source.item.key)",
            query: [URLQueryItem(name: "format", value: "json")], serverID: source.serverID)
        guard try Self.pdfParent(from: parent.data, key: source.item.key) == source.item else { throw ZoteroPDFImportError.sourceChanged }
        let locator = try await requestResponse(
            library: source.library.identity, path: "items/\(source.attachmentKey)/file/view/url",
            query: [], serverID: source.serverID)
        let url = try Self.pdfOriginalURL(from: locator.data, filename: source.filename)
        try Task.checkCancellation()
        return ZoteroPDFImportCandidate(source: source, originalURL: url)
    }

    /// The copy owner calls this after its coordinated original-byte read and
    /// before committing the separate copy. A changed path or record fails closed.
    public func revalidatePDFImport(_ candidate: ZoteroPDFImportCandidate) async throws {
        let current = try await resolvePDFImport(candidate.source)
        guard current.originalURL == candidate.originalURL else { throw ZoteroPDFImportError.sourceChanged }
    }

    private static func pdfServerID(_ value: String?) throws -> String {
        guard let value, ZoteroPDFSource.validServerID(value) else { throw ZoteroPDFImportError.stableIdentityUnavailable }
        return value
    }

    private static func pdfParent(from bytes: Data, key: String) throws -> ZoteroItemMetadata {
        let items: [ZoteroItemMetadata]
        do { items = try ZoteroMetadataDecoder.decodeItems(from: bytes) } catch { throw ZoteroPDFImportError.invalidResponse }
        guard items.count == 1, let item = items.first, item.key == key,
            !["attachment", "annotation", "note"].contains(item.itemType?.lowercased() ?? "")
        else { throw ZoteroPDFImportError.invalidResponse }
        return item
    }

    private static func pdfObjects(from bytes: Data) throws -> [[String: Any]] {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: bytes) } catch { throw ZoteroPDFImportError.invalidResponse }
        if let objects = object as? [[String: Any]] { return objects }
        if let object = object as? [String: Any] { return [object] }
        throw ZoteroPDFImportError.invalidResponse
    }

    private static func pdfSingleObject(from bytes: Data) throws -> [String: Any] {
        let objects = try pdfObjects(from: bytes)
        guard objects.count == 1, let object = objects.first else { throw ZoteroPDFImportError.invalidResponse }
        return object
    }

    private struct PDFObservedEnvelope {
        let version: Int
        let libraryID: Int
        let fingerprint: DocumentFingerprint
    }

    private struct PDFObservedVersionEnvelope: Decodable {
        struct Library: Decodable {
            let type: String
            let id: Int
        }
        struct Payload: Decodable {
            let key: String
            let version: Int?
        }
        let key: String
        let version: Int?
        let library: Library
        let data: Payload
    }

    private static func pdfObservedEnvelope(object: [String: Any], library: ZoteroLibraryIdentity, key: String) throws -> PDFObservedEnvelope {
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let envelope: PDFObservedVersionEnvelope
        do { envelope = try JSONDecoder().decode(PDFObservedVersionEnvelope.self, from: canonical) } catch { throw ZoteroPDFImportError.invalidResponse }
        guard envelope.key == key, envelope.data.key == key,
            let version = envelope.version ?? envelope.data.version, version >= 0,
            envelope.version == nil || envelope.data.version == nil || envelope.version == envelope.data.version,
            envelope.library.id >= 0
        else { throw ZoteroPDFImportError.invalidResponse }
        switch library {
        case .user:
            guard envelope.library.type == "user" else { throw ZoteroPDFImportError.invalidResponse }
        case .group(let groupID):
            guard envelope.library.type == "group", envelope.library.id == groupID else { throw ZoteroPDFImportError.invalidResponse }
        }
        return PDFObservedEnvelope(version: version, libraryID: envelope.library.id, fingerprint: DocumentFingerprint(data: canonical))
    }

    private static func pdfLocalCopyObservation(
        object: [String: Any], library: ZoteroLibraryMetadata, item: ZoteroItemMetadata, parent: PDFObservedEnvelope
    ) throws -> ZoteroPDFLocalCopyObservation {
        guard let data = object["data"] as? [String: Any], let key = object["key"] as? String,
            data["itemType"] as? String == "attachment", data["contentType"] as? String == "application/pdf",
            data["parentItem"] as? String == item.key,
            let mode = (data["linkMode"] as? String).flatMap(ZoteroPDFSource.LinkMode.init(rawValue:))
        else { throw ZoteroPDFImportError.invalidResponse }
        let attachment = try pdfObservedEnvelope(object: object, library: library.identity, key: key)
        guard attachment.libraryID == parent.libraryID else { throw ZoteroPDFImportError.sourceChanged }
        let filename = try pdfFilename(data: data, mode: mode)
        return try ZoteroPDFLocalCopyObservation(
            library: library, observedLibraryID: parent.libraryID, item: item,
            parentVersion: parent.version, parentMetadataFingerprint: parent.fingerprint,
            attachmentKey: key, attachmentVersion: attachment.version, attachmentMetadataFingerprint: attachment.fingerprint,
            title: data["title"] as? String ?? filename, filename: filename, linkMode: mode)
    }

    private static func pdfSource(
        object: [String: Any], library: ZoteroLibraryMetadata,
        item: ZoteroItemMetadata, serverID: String
    ) throws -> ZoteroPDFSource {
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let versions: PDFVersionEnvelope
        do { versions = try JSONDecoder().decode(PDFVersionEnvelope.self, from: canonical) } catch { throw ZoteroPDFImportError.invalidResponse }
        guard let data = object["data"] as? [String: Any],
            let key = object["key"] as? String, data["key"] as? String == key,
            data["itemType"] as? String == "attachment", data["contentType"] as? String == "application/pdf",
            data["parentItem"] as? String == item.key,
            let version = versions.version ?? versions.data.version,
            let mode = (data["linkMode"] as? String).flatMap(ZoteroPDFSource.LinkMode.init(rawValue:))
        else { throw ZoteroPDFImportError.invalidResponse }
        let filename = try pdfFilename(data: data, mode: mode)
        return try ZoteroPDFSource(
            library: library, item: item, attachmentKey: key, attachmentVersion: version,
            title: data["title"] as? String ?? filename, filename: filename, linkMode: mode,
            serverID: serverID, attachmentMetadataFingerprint: DocumentFingerprint(data: canonical))
    }

    private static func pdfFilename(data: [String: Any], mode: ZoteroPDFSource.LinkMode) throws -> String {
        switch mode {
        case .importedFile, .importedURL:
            guard let value = data["filename"] as? String else { throw ZoteroPDFImportError.invalidResponse }
            return value
        case .linkedFile:
            guard let path = data["path"] as? String, !path.isEmpty else { throw ZoteroPDFImportError.invalidResponse }
            let relative = path.hasPrefix("attachments:") ? String(path.dropFirst("attachments:".count)) : path
            return URL(fileURLWithPath: relative).lastPathComponent
        }
    }

    private struct PDFVersionEnvelope: Decodable {
        struct Payload: Decodable { let version: Int? }
        let version: Int?
        let data: Payload
    }

    private static func pdfOriginalURL(from bytes: Data, filename: String) throws -> URL {
        guard bytes.count <= 16_384, let raw = String(data: bytes, encoding: .utf8),
            raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
            let components = URLComponents(string: raw), components.scheme == "file",
            components.host?.isEmpty != false, components.user == nil, components.password == nil,
            components.port == nil, components.query == nil, components.fragment == nil,
            let url = components.url, url.isFileURL, url.path.hasPrefix("/"),
            !url.path.contains("\0"), url.path == url.standardizedFileURL.path,
            url.lastPathComponent == filename,
            (try? AttachmentRelativePath(String(url.path.dropFirst()))) != nil
        else { throw ZoteroPDFImportError.originalUnavailable }
        return url
    }
}
