import ScholiumContracts
import Foundation
import ScholiumCore

/// Runtime-owned, delivery-neutral access to Scholium's first-party Zotero
/// transport. Delivery targets may parse frames and format reports, but Core
/// locator and server authorities are composed only behind this boundary.
public actor ZoteroOperations: ZoteroUseCases {
    typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public nonisolated let descriptor: ZoteroMCPTransportDescriptor

    private let server: ZoteroMCPServer
    private let loadRequest: RequestLoader
    private var lastSuccessfulConnection: Date?

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
            let session = URLSession(configuration: configuration)
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

    public func resolveCitation(zoteroKey: String) async throws -> ZoteroItemMetadata? {
        switch try await resolve(source: ZoteroSourceIdentity(itemKey: zoteroKey)) {
        case .matched(let item, _): item
        case .ambiguous, .notFound, .insufficientMetadata: nil
        }
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
        in result: ZoteroMatchResult
    ) async throws -> ZoteroMatchResult {
        guard case .matched(let item, let basis) = result,
              !item.collectionKeys.isEmpty else { return result }
        var names: [String] = []
        for key in item.collectionKeys {
            do {
                let data = try await request(
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

    private func request(path: String, query: [URLQueryItem]) async throws -> Data {
        guard let request = ZoteroLocalRequestPolicy.makeReadRequest(path: path, query: query) else {
            throw ZoteroUseCaseError.invalidResponse
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await loadRequest(request)
        } catch {
            throw ZoteroUseCaseError.appUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
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
