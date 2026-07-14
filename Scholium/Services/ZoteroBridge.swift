import Foundation
import ScholiumCore
#if canImport(AppKit)
import AppKit
#endif

typealias ZoteroCitation = ZoteroItemMetadata

enum ZoteroAvailability: Equatable {
    case available
    case appUnavailable
    case apiDisabled
    case itemMissing
}

struct ZoteroLibraryInfo: Equatable {
    let status: ZoteroAvailability
    let lastSuccessfulConnection: Date?
}

enum ZoteroBridgeError: LocalizedError {
    case appUnavailable
    case apiDisabled
    case itemMissing(String)
    case invalidResponse
    case invalidItemKey
    case invalidAnalysisReference

    var errorDescription: String? {
        switch self {
        case .appUnavailable:
            "Zotero is not responding on this Mac. Open Zotero and try again."
        case .apiDisabled:
            "Zotero local API access is disabled. In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’."
        case .itemMissing(let key):
            "Zotero item \(key) was not found."
        case .invalidResponse:
            "Zotero returned metadata Scholium could not read."
        case .invalidItemKey:
            "The selected Zotero item has an invalid item key. Refresh Zotero and choose the item again."
        case .invalidAnalysisReference:
            "The Zotero source can be confirmed only for an Analysis in this Triptych."
        }
    }
}

/// Read-only access to Zotero Desktop through its loopback API. Every request
/// is an HTTP GET to 127.0.0.1. Scholium never requests attachments, opens the
/// live SQLite database, or sends a Zotero write request.
actor ZoteroBridge {
    private let session: URLSession
    private var lastSuccessfulConnection: Date?

    init(applicationSupportURL _: URL? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func connectionInfo() async -> ZoteroLibraryInfo {
        do {
            _ = try await request(path: "items", query: [
                URLQueryItem(name: "limit", value: "1"),
                URLQueryItem(name: "itemType", value: "-attachment"),
            ])
            return ZoteroLibraryInfo(status: .available, lastSuccessfulConnection: lastSuccessfulConnection)
        } catch ZoteroBridgeError.apiDisabled {
            return ZoteroLibraryInfo(status: .apiDisabled, lastSuccessfulConnection: lastSuccessfulConnection)
        } catch {
            return ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: lastSuccessfulConnection)
        }
    }

    func refreshLibraryInfo() async throws -> ZoteroLibraryInfo {
        _ = try await request(path: "items", query: [
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "itemType", value: "-attachment"),
        ])
        return ZoteroLibraryInfo(status: .available, lastSuccessfulConnection: lastSuccessfulConnection)
    }

    func forgetCache() throws {
        lastSuccessfulConnection = nil
    }

    func openZotero() {
        #if canImport(AppKit)
        if let url = URL(string: "zotero://select/library") { NSWorkspace.shared.open(url) }
        #endif
    }

    /// Resolves one Analysis identity in the Product Guide's fixed order:
    /// item key, DOI/ISBN, citation key, then exact title + author + year.
    func resolve(source: ZoteroSourceIdentity) async throws -> ZoteroMatchResult {
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
            } catch let error as ZoteroBridgeError {
                if case .itemMissing = error { return .notFound }
                throw error
            } catch is DecodingError {
                throw ZoteroBridgeError.invalidResponse
            }
        }

        guard source.hasFallbackIdentity else { return .insufficientMetadata }

        if source.doi != nil || source.isbn != nil {
            let identity = ZoteroSourceIdentity(doi: source.doi, isbn: source.isbn)
            let terms = [source.doi, source.isbn].compactMap(nonempty)
            let result = try await match(
                identity,
                searchTerms: terms,
                mode: "everything"
            )
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
                ZoteroSourceIdentity(
                    title: title,
                    authors: source.authors,
                    year: source.year
                ),
                searchTerms: [title],
                mode: "titleCreatorYear"
            )
        }

        return .notFound
    }

    /// Compatibility helper for the Properties editor's exact-key preview.
    func resolveCitation(zoteroKey: String) async throws -> ZoteroCitation? {
        switch try await resolve(source: ZoteroSourceIdentity(itemKey: zoteroKey)) {
        case .matched(let item, _): item
        case .ambiguous, .notFound, .insufficientMetadata: nil
        }
    }

    func openInZotero(zoteroKey: String) {
        guard let key = normalizedItemKey(zoteroKey),
              let url = URL(string: "zotero://select/library/items/\(key)") else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
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
            throw ZoteroBridgeError.invalidResponse
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

    private func enrichingCollections(in result: ZoteroMatchResult) async throws -> ZoteroMatchResult {
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
                // Collection labels are optional expanded metadata. A failed
                // label lookup must not hide an already verified item match.
                continue
            }
        }
        return .matched(item.replacingCollectionNames(names), basis: basis)
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data {
        guard let request = ZoteroLocalRequestPolicy.makeReadRequest(
            path: path,
            query: query
        ) else {
            throw ZoteroBridgeError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZoteroBridgeError.appUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ZoteroBridgeError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            lastSuccessfulConnection = Date()
            return data
        case 401, 403:
            throw ZoteroBridgeError.apiDisabled
        case 404:
            throw ZoteroBridgeError.itemMissing(path)
        default:
            throw ZoteroBridgeError.invalidResponse
        }
    }

    private func normalizedItemKey(_ key: String?) -> String? {
        guard let key = nonempty(key) else { return nil }
        return key.uppercased()
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}
