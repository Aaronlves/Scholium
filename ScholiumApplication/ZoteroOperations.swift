import Foundation
import ScholiumContracts
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

    private struct LocalReadResponse: Sendable {
        let data: Data
        let serverID: String?
    }

    private struct GroupEnvelope: Decodable {
        struct Payload: Decodable {
            let id: Int?
            let name: String?
        }

        let id: Int
        let name: String

        private enum CodingKeys: String, CodingKey {
            case id, name, data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let payload = try container.decodeIfPresent(Payload.self, forKey: .data)
            guard
                let id = try container.decodeIfPresent(Int.self, forKey: .id)
                    ?? payload?.id,
                let name = try container.decodeIfPresent(String.self, forKey: .name)
                    ?? payload?.name,
                id > 0,
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "A Zotero group must include a positive ID and name."
                    )
                )
            }
            self.id = id
            self.name = name
        }
    }

    init(
        descriptor: ZoteroMCPTransportDescriptor = .supportedLocal,
        requestLoader: RequestLoader? = nil
    ) {
        self.descriptor = descriptor
        if let requestLoader {
            loadRequest = requestLoader
            server = ZoteroMCPServer(client: ZoteroRequestLoaderClient(load: requestLoader))
        } else {
            let client = ZoteroMCPURLSessionClient()
            server = ZoteroMCPServer(client: client)
            loadRequest = { request in
                let result = try await client.send(request)
                guard let url = request.url,
                    let response = HTTPURLResponse(
                        url: url, statusCode: result.statusCode,
                        httpVersion: "HTTP/1.1", headerFields: result.headers)
                else { throw ZoteroUseCaseError.invalidResponse }
                return (result.body, response)
            }
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
    public func handle(requestData: Data, access: ZoteroMCPAccess) async -> Data? {
        await server.handle(requestData: requestData, access: access)
    }

    public func libraryInfo() async -> ZoteroLibraryInfo {
        do {
            _ = try await request(
                path: "items",
                query: [
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
        _ = try await request(
            path: "items",
            query: [
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

    private func libraries() async throws -> [ZoteroLibraryMetadata] {
        let data = try await request(path: "groups", query: [])
        let groups: [GroupEnvelope]
        do {
            groups = try JSONDecoder().decode([GroupEnvelope].self, from: data)
        } catch {
            throw ZoteroUseCaseError.invalidResponse
        }
        guard groups.count <= 50,
            Set(groups.map(\.id)).count == groups.count
        else {
            throw ZoteroUseCaseError.invalidResponse
        }
        return [ZoteroLibraryMetadata(identity: .user, name: "My Library")]
            + groups.sorted { $0.id < $1.id }.map {
                ZoteroLibraryMetadata(identity: .group($0.id), name: $0.name)
            }
    }

    public func searchLibrary(
        query rawQuery: String,
        limit: Int = 25
    ) async throws -> [ZoteroSearchHit] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 512,
            (1...25).contains(limit)
        else {
            throw ZoteroUseCaseError.invalidResponse
        }
        let libraries = try await libraries()
        var hits: [ZoteroSearchHit] = []
        if let exactKey = normalizedSearchItemKey(query) {
            for library in libraries {
                do {
                    let response = try await requestResponse(
                        library: library.identity,
                        path: "items/\(exactKey)",
                        query: [URLQueryItem(name: "format", value: "json")]
                    )
                    let items = try decodedParentItems(response.data).filter {
                        normalizedItemKey($0.key) == exactKey
                    }
                    hits.append(
                        contentsOf: items.map {
                            ZoteroSearchHit(library: library, item: $0)
                        })
                } catch ZoteroUseCaseError.itemMissing {
                    continue
                } catch is DecodingError {
                    throw ZoteroUseCaseError.invalidResponse
                }
            }
            return sortedSearchHits(hits, limit: limit)
        }
        for library in libraries {
            let data = try await request(
                library: library.identity,
                path: "items",
                query: [
                    URLQueryItem(name: "format", value: "json"),
                    URLQueryItem(name: "itemType", value: "-attachment"),
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "qmode", value: "everything"),
                    URLQueryItem(name: "limit", value: String(limit)),
                ]
            )
            let items: [ZoteroItemMetadata]
            do {
                items = try decodedParentItems(data)
            } catch {
                throw ZoteroUseCaseError.invalidResponse
            }
            hits.append(
                contentsOf: items.map {
                    ZoteroSearchHit(library: library, item: $0)
                })
        }
        return sortedSearchHits(hits, limit: limit)
    }

    func exactItem(
        library: ZoteroLibraryMetadata,
        itemKey rawItemKey: String,
        expectedServerID: String? = nil
    ) async throws -> ZoteroExactItemRead {
        guard let itemKey = normalizedObjectKey(rawItemKey) else {
            throw ZoteroUseCaseError.invalidItemKey
        }
        let response = try await requestResponse(
            library: library.identity,
            path: "items/\(itemKey)",
            query: [URLQueryItem(name: "format", value: "json")]
        )
        guard let serverID = response.serverID else {
            throw ZoteroMetadataOperationError.serverIdentityUnavailable
        }
        if let expectedServerID, expectedServerID != serverID {
            throw ZoteroMetadataOperationError.serverIdentityChanged
        }
        let items: [ZoteroItemMetadata]
        do {
            items = try decodedParentItems(response.data).filter {
                normalizedItemKey($0.key) == itemKey
            }
        } catch {
            throw ZoteroUseCaseError.invalidResponse
        }
        guard items.count == 1, let item = items.first else {
            throw ZoteroUseCaseError.invalidResponse
        }
        return ZoteroExactItemRead(
            library: library,
            item: item,
            serverID: serverID
        )
    }

    private func sortedSearchHits(
        _ hits: [ZoteroSearchHit],
        limit: Int
    ) -> [ZoteroSearchHit] {
        hits.sorted { lhs, rhs in
            let titleOrder = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if lhs.library.name != rhs.library.name {
                return lhs.library.name.localizedStandardCompare(rhs.library.name)
                    == .orderedAscending
            }
            return lhs.item.key < rhs.item.key
        }
        .prefix(limit)
        .map { $0 }
    }

    private func decodedParentItems(_ data: Data) throws -> [ZoteroItemMetadata] {
        try ZoteroMetadataDecoder.decodeItems(from: data).filter { item in
            guard let type = item.itemType?.lowercased() else { return true }
            return !["attachment", "annotation", "note"].contains(type)
        }
    }

    private func request(
        library: ZoteroLibraryIdentity = .user,
        path: String,
        query: [URLQueryItem]
    ) async throws -> Data {
        try await requestResponse(
            library: library,
            path: path,
            query: query
        ).data
    }

    private func requestResponse(
        library: ZoteroLibraryIdentity = .user,
        path: String,
        query: [URLQueryItem]
    ) async throws -> LocalReadResponse {
        guard
            let request = ZoteroLocalRequestPolicy.makeReadRequest(
                library: library,
                path: path,
                query: query
            )
        else {
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
            http.url == request.url
        else {
            throw ZoteroUseCaseError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            lastSuccessfulConnection = Date()
            return LocalReadResponse(
                data: data,
                serverID: normalizedServerID(
                    http.value(forHTTPHeaderField: "Zotero-Server-ID")
                )
            )
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

    private func normalizedObjectKey(_ key: String?) -> String? {
        guard let key = normalizedItemKey(key),
            key.utf8.count <= 128,
            key.unicodeScalars.allSatisfy({ scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-" || scalar == "_"
            })
        else { return nil }
        return key
    }

    private func normalizedSearchItemKey(_ key: String?) -> String? {
        guard let key = normalizedObjectKey(key), key.utf8.count == 8 else {
            return nil
        }
        return key
    }

    private func normalizedServerID(_ value: String?) -> String? {
        guard let value = nonempty(value), value.utf8.count <= 256,
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        else { return nil }
        return value
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}

/// Foundation-only injection stays at Application; Core transport types never
/// cross into delivery or boundary-test construction.
private struct ZoteroRequestLoaderClient: ZoteroMCPHTTPClient {
    let load: ZoteroOperations.RequestLoader
    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        let (body, response) = try await load(request)
        guard let expectedURL = request.url, let response = response as? HTTPURLResponse,
            response.url == expectedURL
        else { throw ZoteroUseCaseError.invalidResponse }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        return .init(statusCode: response.statusCode, headers: headers, body: body)
    }
}
