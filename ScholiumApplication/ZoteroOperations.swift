import ScholiumContracts
import Foundation
import ScholiumCore

final class ZoteroNoRedirectDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Runtime-owned, delivery-neutral access to Scholium's first-party Zotero
/// transport. Delivery targets may parse frames and format reports, but Core
/// locator and server authorities are composed only behind this boundary.
public actor ZoteroOperations: ZoteroUseCases {
    typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public nonisolated let descriptor: ZoteroMCPTransportDescriptor

    private let server: ZoteroMCPServer
    private let loadRequest: RequestLoader
    private var lastSuccessfulConnection: Date?

    struct ResolvedAttachment: Hashable, Sendable {
        let itemKey: String
        let attachmentKey: String
        let displayName: String
        let fileURL: URL
    }

    private struct AttachmentEnvelope: Decodable {
        struct Payload: Decodable {
            let key: String?
            let itemType: String
            let parentItem: String?
            let title: String?
            let filename: String?
        }

        let key: String
        let data: Payload
    }

    init(
        descriptor: ZoteroMCPTransportDescriptor = .supportedLocal,
        server: ZoteroMCPServer = ZoteroMCPServer(),
        requestLoader: RequestLoader? = nil
    ) {
        self.descriptor = descriptor
        self.server = server
        if let requestLoader {
            loadRequest = requestLoader
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 3
            configuration.timeoutIntervalForResource = 15
            configuration.waitsForConnectivity = false
            let session = URLSession(
                configuration: configuration,
                delegate: ZoteroNoRedirectDelegate(),
                delegateQueue: nil
            )
            loadRequest = { request in try await session.data(for: request) }
        }
    }

    /// Locates the configured transport without launching it or reading
    /// Zotero data.
    public nonisolated func report(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ZoteroMCPTransportReport {
        ZoteroMCPTransportLocator.report(
            descriptor: descriptor,
            environment: environment
        )
    }

    /// Performs only the bounded initialize lifecycle probe defined by Core.
    public func probe(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 5
    ) async -> ZoteroMCPTransportReport {
        await ZoteroMCPTransportLocator.probe(
            descriptor: descriptor,
            environment: environment,
            timeout: timeout
        )
    }

    /// Handles one unframed JSON-RPC body. Notifications intentionally return
    /// nil; framing remains a delivery concern for stdio callers.
    public func handle(requestData: Data) async -> Data? {
        await server.handle(requestData: requestData)
    }

    public func libraryInfo() async -> ZoteroLibraryInfo {
        do {
            _ = try await request(path: "items", query: [
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "itemType", value: "-attachment"),
            ])
            return ZoteroLibraryInfo(
                status: .available,
                lastSuccessfulConnection: lastSuccessfulConnection
            )
        } catch ZoteroUseCaseError.apiDisabled {
            return ZoteroLibraryInfo(
                status: .apiDisabled,
                lastSuccessfulConnection: lastSuccessfulConnection
            )
        } catch {
            return ZoteroLibraryInfo(
                status: .appUnavailable,
                lastSuccessfulConnection: lastSuccessfulConnection
            )
        }
    }

    public func refreshLibraryInfo() async throws -> ZoteroLibraryInfo {
        _ = try await request(path: "items", query: [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "itemType", value: "-attachment"),
        ])
        return ZoteroLibraryInfo(
            status: .available,
            lastSuccessfulConnection: lastSuccessfulConnection
        )
    }

    public func clearConnectionHistory() async throws {
        lastSuccessfulConnection = nil
    }

    public func resolve(source: ZoteroSourceIdentity) async throws -> ZoteroMatchResult {
        if let itemKey = normalizedItemKey(source.itemKey) {
            do {
                let data = try await request(
                    path: "items/\(itemKey)",
                    query: [URLQueryItem(name: "format", value: "json")]
                )
                let candidates = try decodedParentItems(data)
                return try await enrichingCollections(
                    in: ZoteroMetadataMatcher.match(source: source, candidates: candidates)
                )
            } catch let error as ZoteroUseCaseError {
                if case .itemMissing = error { return .notFound }
                throw error
            } catch is DecodingError {
                throw ZoteroUseCaseError.invalidResponse
            }
        }

        guard source.hasFallbackIdentity else { return .insufficientMetadata }

        if source.doi != nil || source.isbn != nil {
            let identity = ZoteroSourceIdentity(doi: source.doi, isbn: source.isbn)
            let terms = [source.doi, source.isbn].compactMap(nonempty)
            let result = try await match(identity, searchTerms: terms, mode: "everything")
            if case .notFound = result {} else { return result }
        }

        if let citationKey = nonempty(source.citationKey) {
            let result = try await match(
                ZoteroSourceIdentity(citationKey: citationKey),
                searchTerms: [citationKey],
                mode: "everything"
            )
            if case .notFound = result {} else { return result }
        }

        if let title = nonempty(source.title), source.year != nil, !source.authors.isEmpty {
            return try await match(
                ZoteroSourceIdentity(title: title, authors: source.authors, year: source.year),
                searchTerms: [title],
                mode: "titleCreatorYear"
            )
        }
        return .notFound
    }

    /// Resolves one exact portable Analysis binding without searching another
    /// library that happens to contain the same item key.
    func resolve(binding: AnalysisZoteroBinding) async throws -> ZoteroMatchResult {
        do {
            let data = try await request(
                library: binding.library,
                path: "items/\(binding.itemKey)",
                query: [URLQueryItem(name: "format", value: "json")]
            )
            let candidates = try decodedParentItems(data)
            return try await enrichingCollections(
                in: ZoteroMetadataMatcher.match(
                    source: ZoteroSourceIdentity(itemKey: binding.itemKey),
                    candidates: candidates
                ),
                library: binding.library
            )
        } catch let error as ZoteroUseCaseError {
            if case .itemMissing = error { return .notFound }
            throw error
        } catch is DecodingError {
            throw ZoteroUseCaseError.invalidResponse
        }
    }

    func resolveAttachment(
        itemKey rawItemKey: String,
        attachmentKey rawAttachmentKey: String
    ) async throws -> ResolvedAttachment {
        guard let itemKey = normalizedItemKey(rawItemKey),
              let attachmentKey = normalizedItemKey(rawAttachmentKey),
              itemKey != attachmentKey else {
            throw ZoteroUseCaseError.attachmentIdentityMismatch
        }
        let envelopeData: Data
        do {
            envelopeData = try await request(
                path: "items/\(attachmentKey)",
                query: [URLQueryItem(name: "format", value: "json")]
            )
        } catch ZoteroUseCaseError.itemMissing {
            throw ZoteroUseCaseError.attachmentMissing(attachmentKey)
        }
        let envelope: AttachmentEnvelope
        do {
            envelope = try JSONDecoder().decode(AttachmentEnvelope.self, from: envelopeData)
        } catch {
            throw ZoteroUseCaseError.invalidResponse
        }
        guard normalizedItemKey(envelope.key) == attachmentKey,
              normalizedItemKey(envelope.data.key ?? envelope.key) == attachmentKey,
              envelope.data.itemType.lowercased() == "attachment",
              normalizedItemKey(envelope.data.parentItem) == itemKey else {
            throw ZoteroUseCaseError.attachmentIdentityMismatch
        }

        let urlData: Data
        do {
            urlData = try await request(
                path: "items/\(attachmentKey)/file/view/url",
                query: []
            )
        } catch ZoteroUseCaseError.itemMissing {
            throw ZoteroUseCaseError.attachmentMissing(attachmentKey)
        }
        guard let rawURL = String(data: urlData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let fileURL = URL(string: rawURL),
              fileURL.isFileURL,
              fileURL.host == nil,
              fileURL.path.hasPrefix("/"),
              let components = URLComponents(
                  url: fileURL,
                  resolvingAgainstBaseURL: false
              ),
              components.query == nil,
              components.fragment == nil else {
            throw ZoteroUseCaseError.invalidAttachmentURL
        }
        let displayName = nonempty(envelope.data.filename)
            ?? nonempty(envelope.data.title)
            ?? fileURL.lastPathComponent
        guard !displayName.isEmpty else {
            throw ZoteroUseCaseError.invalidAttachmentURL
        }
        return ResolvedAttachment(
            itemKey: itemKey,
            attachmentKey: attachmentKey,
            displayName: displayName,
            fileURL: fileURL.standardizedFileURL
        )
    }

    private func match(
        _ identity: ZoteroSourceIdentity,
        searchTerms: [String],
        mode: String
    ) async throws -> ZoteroMatchResult {
        var candidates: [ZoteroItemMetadata] = []
        var searched: Set<String> = []
        do {
            for term in searchTerms where searched.insert(term).inserted {
                let data = try await request(path: "items", query: [
                    URLQueryItem(name: "format", value: "json"),
                    URLQueryItem(name: "itemType", value: "-attachment"),
                    URLQueryItem(name: "q", value: term),
                    URLQueryItem(name: "qmode", value: mode),
                    URLQueryItem(name: "limit", value: "50"),
                ])
                candidates.append(contentsOf: try decodedParentItems(data))
            }
        } catch is DecodingError {
            throw ZoteroUseCaseError.invalidResponse
        }
        return try await enrichingCollections(
            in: ZoteroMetadataMatcher.match(source: identity, candidates: candidates)
        )
    }

    private func decodedParentItems(_ data: Data) throws -> [ZoteroItemMetadata] {
        try ZoteroMetadataDecoder.decodeItems(from: data).filter { item in
            guard let type = item.itemType?.lowercased() else { return true }
            return !["attachment", "annotation", "note"].contains(type)
        }
    }

    private func enrichingCollections(
        in result: ZoteroMatchResult,
        library: ZoteroLibraryIdentity = .user
    ) async throws -> ZoteroMatchResult {
        guard case .matched(let item, let basis) = result,
              !item.collectionKeys.isEmpty else { return result }
        var names: [String] = []
        for key in item.collectionKeys {
            do {
                let data = try await request(
                    library: library,
                    path: "collections/\(key)",
                    query: [URLQueryItem(name: "format", value: "json")]
                )
                if let name = try ZoteroMetadataDecoder.decodeCollectionName(from: data) {
                    names.append(name)
                }
            } catch {
                continue
            }
        }
        return .matched(item.replacingCollectionNames(names), basis: basis)
    }

    private func request(
        library: ZoteroLibraryIdentity = .user,
        path: String,
        query: [URLQueryItem]
    ) async throws -> Data {
        guard let request = ZoteroLocalRequestPolicy.makeReadRequest(
            library: library,
            path: path,
            query: query
        ) else {
            throw ZoteroUseCaseError.invalidResponse
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loadRequest(request)
        } catch {
            throw ZoteroUseCaseError.appUnavailable
        }
        guard let http = response as? HTTPURLResponse,
              http.url == request.url else {
            throw ZoteroUseCaseError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            lastSuccessfulConnection = Date()
            return data
        case 401, 403:
            throw ZoteroUseCaseError.apiDisabled
        case 404:
            throw ZoteroUseCaseError.itemMissing(path)
        default:
            throw ZoteroUseCaseError.invalidResponse
        }
    }

    private func normalizedItemKey(_ key: String?) -> String? {
        nonempty(key)?.uppercased()
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
