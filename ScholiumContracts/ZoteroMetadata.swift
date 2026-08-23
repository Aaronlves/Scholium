import Foundation

public enum ZoteroAvailability: String, Codable, Hashable, Sendable {
    case available
    case appUnavailable
    case apiDisabled
    case itemMissing
}

public struct ZoteroLibraryInfo: Codable, Hashable, Sendable {
    public let status: ZoteroAvailability
    public let lastSuccessfulConnection: Date?

    public init(status: ZoteroAvailability, lastSuccessfulConnection: Date?) {
        self.status = status
        self.lastSuccessfulConnection = lastSuccessfulConnection
    }
}

/// One immutable, task-scoped Zotero read attached to an Analysis Research
/// Function. It is durable only with that function record: a later function
/// performs a fresh read, while resuming this function reuses this snapshot.
public struct ZoteroBibliographicContext: Codable, Hashable, Sendable {
    public enum RetrievalState: String, Codable, Hashable, Sendable {
        case resolved
        case unavailable
        case notFound
        case invalidResponse
    }

    public static let evidentialLabel = "Zotero bibliographic metadata"

    public let itemKey: String
    public let state: RetrievalState
    public let metadata: ZoteroItemMetadata?
    public let warning: String?
    public let capturedAt: Date

    public init(
        itemKey: String,
        state: RetrievalState,
        metadata: ZoteroItemMetadata? = nil,
        warning: String? = nil,
        capturedAt: Date = Date()
    ) {
        self.itemKey = itemKey
        self.state = state
        self.metadata = metadata
        self.warning = warning
        self.capturedAt = capturedAt
    }
}

public enum ZoteroUseCaseError: LocalizedError, Sendable {
    case appUnavailable
    case apiDisabled
    case itemMissing(String)
    case invalidResponse
    case invalidItemKey
    case invalidAnalysisReference
    case attachmentMissing(String)
    case attachmentIdentityMismatch
    case invalidAttachmentURL

    public var errorDescription: String? {
        switch self {
        case .appUnavailable:
            "Zotero is not responding on this Mac. Open Zotero and try again."
        case .apiDisabled:
            "Zotero local API access is disabled. In Zotero Advanced settings, enable Allow other applications on this computer to communicate with Zotero."
        case .itemMissing(let key):
            "Zotero item \(key) was not found."
        case .invalidResponse:
            "Zotero returned metadata Scholium could not read."
        case .invalidItemKey:
            "The selected Zotero item has an invalid item key. Refresh Zotero and choose the item again."
        case .invalidAnalysisReference:
            "The Zotero source can be confirmed only for an Analysis in this Triptych."
        case .attachmentMissing(let key):
            "Zotero attachment \(key) was not found."
        case .attachmentIdentityMismatch:
            "The selected Zotero attachment does not belong to the expected item."
        case .invalidAttachmentURL:
            "Zotero did not return a readable local file URL for the attachment."
        }
    }
}

/// The complete network boundary for Zotero reads. The generated request is
/// always a bodyless GET to Zotero Desktop's loopback API and can address only
/// the current user's group list, item searches, one exact item, one exact
/// collection label, or one exact attachment's local `/file/view/url` endpoint.
public enum ZoteroLocalRequestPolicy {
    public static func makeReadRequest(
        library: ZoteroLibraryIdentity = .user,
        path: String,
        query: [URLQueryItem] = []
    ) -> URLRequest? {
        guard allowed(path: path, library: library),
              (!isAttachmentFileURL(path) || query.isEmpty),
              Set(query.map(\.name)).isSubset(of: [
                "format", "itemType", "q", "qmode", "limit",
              ]),
              let baseURL = baseURL(for: library) else {
            return nil
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url,
              url.scheme == "http",
              url.host == "127.0.0.1",
              url.port == 23119 else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.setValue(
            isAttachmentFileURL(path) ? "text/plain" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        return request
    }

    private static func baseURL(for library: ZoteroLibraryIdentity) -> URL? {
        switch library {
        case .user:
            URL(string: "http://127.0.0.1:23119/api/users/0/")
        case .group(let groupID):
            groupID > 0
                ? URL(string: "http://127.0.0.1:23119/api/groups/\(groupID)/")
                : nil
        }
    }

    private static func allowed(
        path: String,
        library: ZoteroLibraryIdentity
    ) -> Bool {
        if path == "groups" {
            if case .user = library { return true }
            return false
        }
        if path == "items" { return true }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.count == 2,
           components[0] == "items" || components[0] == "collections" {
            return validObjectKey(String(components[1]))
        }
        if components.count == 5,
           components[0] == "items",
           components[2] == "file",
           components[3] == "view",
           components[4] == "url" {
            return validObjectKey(String(components[1]))
        }
        return false
    }

    private static func isAttachmentFileURL(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 5
            && components[0] == "items"
            && components[2] == "file"
            && components[3] == "view"
            && components[4] == "url"
    }

    private static func validObjectKey(_ key: String) -> Bool {
        return !key.isEmpty
            && key.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
    }
}

/// Bibliographic identity projected from one Analysis note. This value never
/// authorizes a Zotero write; it is only a deterministic lookup request.
public struct ZoteroSourceIdentity: Codable, Hashable, Sendable {
    public let itemKey: String?
    public let doi: String?
    public let isbn: String?
    public let citationKey: String?
    public let title: String?
    public let authors: [String]
    public let year: Int?

    public init(
        itemKey: String? = nil,
        doi: String? = nil,
        isbn: String? = nil,
        citationKey: String? = nil,
        title: String? = nil,
        authors: [String] = [],
        year: Int? = nil
    ) {
        self.itemKey = Self.nonempty(itemKey)
        self.doi = Self.nonempty(doi)
        self.isbn = Self.nonempty(isbn)
        self.citationKey = Self.nonempty(citationKey)
        self.title = Self.nonempty(title)
        self.authors = authors.compactMap(Self.nonempty)
        self.year = year
    }

    public var stableIdentity: String {
        [
            itemKey ?? "",
            doi ?? "",
            isbn ?? "",
            citationKey ?? "",
            title ?? "",
            authors.joined(separator: "\u{1f}"),
            year.map(String.init) ?? "",
        ].joined(separator: "\u{1e}")
    }

    public var hasFallbackIdentity: Bool {
        doi != nil
            || isbn != nil
            || citationKey != nil
            || (title != nil && !authors.isEmpty && year != nil)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

/// Read-only metadata returned by Zotero's localhost API.
public struct ZoteroCreatorMetadata: Codable, Hashable, Sendable {
    public let role: String
    public let name: String
    public let givenName: String?
    public let familyName: String?
    public let literalName: String?

    public init(
        role: String,
        name: String,
        givenName: String? = nil,
        familyName: String? = nil,
        literalName: String? = nil
    ) {
        self.role = role
        self.name = name
        self.givenName = givenName
        self.familyName = familyName
        self.literalName = literalName
    }
}

public struct ZoteroItemMetadata: Codable, Hashable, Sendable, Identifiable {
    public var id: String { key }

    public let key: String
    public let itemType: String?
    public let title: String
    public let creators: [ZoteroCreatorMetadata]
    public let authors: [String]
    public let date: String?
    public let year: Int?
    public let language: String?
    public let containerTitle: String?
    public let volume: String?
    public let issue: String?
    public let pages: String?
    public let series: String?
    public let doi: String?
    public let isbn: String?
    public let issn: String?
    public let citationKey: String?
    public let abstract: String?
    public let tags: [String]
    public let publisher: String?
    public let place: String?
    public let edition: String?
    public let url: String?
    public let collectionKeys: [String]
    public let collections: [String]
    public let dateModified: Date?

    public init(
        key: String,
        itemType: String? = nil,
        title: String,
        creators: [ZoteroCreatorMetadata] = [],
        authors: [String] = [],
        date: String? = nil,
        year: Int? = nil,
        language: String? = nil,
        containerTitle: String? = nil,
        volume: String? = nil,
        issue: String? = nil,
        pages: String? = nil,
        series: String? = nil,
        doi: String? = nil,
        isbn: String? = nil,
        issn: String? = nil,
        citationKey: String? = nil,
        abstract: String? = nil,
        tags: [String] = [],
        publisher: String? = nil,
        place: String? = nil,
        edition: String? = nil,
        url: String? = nil,
        collectionKeys: [String] = [],
        collections: [String] = [],
        dateModified: Date? = nil
    ) {
        self.key = key
        self.itemType = itemType
        self.title = title
        self.creators = creators
        self.authors = authors
        self.date = date
        self.year = year
        self.language = language
        self.containerTitle = containerTitle
        self.volume = volume
        self.issue = issue
        self.pages = pages
        self.series = series
        self.doi = doi
        self.isbn = isbn
        self.issn = issn
        self.citationKey = citationKey
        self.abstract = abstract
        self.tags = tags
        self.publisher = publisher
        self.place = place
        self.edition = edition
        self.url = url
        self.collectionKeys = collectionKeys
        self.collections = collections
        self.dateModified = dateModified
    }

    public var formattedAuthors: String {
        guard !authors.isEmpty else { return "" }
        if authors.count == 1 { return authors[0] }
        if authors.count == 2 { return "\(authors[0]) & \(authors[1])" }
        return "\(authors[0]) et al."
    }

    public var inlineCitation: String {
        year.map { "\(formattedAuthors) (\($0))" } ?? formattedAuthors
    }

    public func replacingCollectionNames(_ names: [String]) -> Self {
        Self(
            key: key,
            itemType: itemType,
            title: title,
            creators: creators,
            authors: authors,
            date: date,
            year: year,
            language: language,
            containerTitle: containerTitle,
            volume: volume,
            issue: issue,
            pages: pages,
            series: series,
            doi: doi,
            isbn: isbn,
            issn: issn,
            citationKey: citationKey,
            abstract: abstract,
            tags: tags,
            publisher: publisher,
            place: place,
            edition: edition,
            url: url,
            collectionKeys: collectionKeys,
            collections: names,
            dateModified: dateModified
        )
    }
}

/// One local Zotero library available to the first-party read-only adapter.
/// The stable identity, rather than the display name, is persisted in a
/// portable Analysis binding.
public struct ZoteroLibraryMetadata: Codable, Hashable, Sendable, Identifiable {
    public var id: ZoteroLibraryIdentity { identity }

    public let identity: ZoteroLibraryIdentity
    public let name: String

    public init(identity: ZoteroLibraryIdentity, name: String) {
        self.identity = identity
        self.name = name
    }
}

/// A bounded search projection retains the exact library identity beside the
/// Zotero item so choosing a same-key item in another library cannot silently
/// create the wrong portable relationship.
public struct ZoteroSearchHit: Codable, Hashable, Sendable, Identifiable {
    public var id: String {
        switch library.identity {
        case .user: "user:\(item.key)"
        case .group(let groupID): "group:\(groupID):\(item.key)"
        }
    }

    public let library: ZoteroLibraryMetadata
    public let item: ZoteroItemMetadata

    public init(library: ZoteroLibraryMetadata, item: ZoteroItemMetadata) {
        self.library = library
        self.item = item
    }
}

public enum ZoteroMatchBasis: String, Codable, Hashable, Sendable {
    case itemKey
    case doiOrISBN
    case citationKey
    case titleAuthorYear
}

public enum ZoteroMatchResult: Hashable, Sendable {
    case matched(ZoteroItemMetadata, basis: ZoteroMatchBasis)
    case ambiguous([ZoteroItemMetadata], basis: ZoteroMatchBasis)
    case notFound
    case insufficientMetadata
}

/// Deterministic Zotero matching. No branch fuzzy-selects or prefers an
/// arbitrary candidate; every non-unique tier is returned as ambiguity.
public enum ZoteroMetadataMatcher {
    public static func match(
        source: ZoteroSourceIdentity,
        candidates: [ZoteroItemMetadata]
    ) -> ZoteroMatchResult {
        let candidates = uniqueCandidates(candidates)

        if let key = normalizedItemKey(source.itemKey) {
            return result(
                candidates.filter { normalizedItemKey($0.key) == key },
                basis: .itemKey
            )
        }

        let expectedDOI = normalizedDOI(source.doi)
        let expectedISBN = normalizedISBN(source.isbn)
        if expectedDOI != nil || expectedISBN != nil {
            let matches = candidates.filter { candidate in
                (expectedDOI != nil && normalizedDOI(candidate.doi) == expectedDOI)
                    || (expectedISBN != nil && normalizedISBN(candidate.isbn) == expectedISBN)
            }
            if !matches.isEmpty { return result(matches, basis: .doiOrISBN) }
        }

        if let citationKey = normalizedText(source.citationKey) {
            let matches = candidates.filter {
                normalizedText($0.citationKey) == citationKey
            }
            if !matches.isEmpty { return result(matches, basis: .citationKey) }
        }

        if let title = normalizedText(source.title),
           let year = source.year,
           !source.authors.isEmpty {
            let sourceAuthors = source.authors.compactMap(normalizedAuthor)
            let matches = candidates.filter { candidate in
                guard normalizedText(candidate.title) == title,
                      candidate.year == year else { return false }
                let candidateAuthors = candidate.authors.compactMap(normalizedAuthor)
                return !sourceAuthors.isEmpty && sourceAuthors == candidateAuthors
            }
            if !matches.isEmpty { return result(matches, basis: .titleAuthorYear) }
        }

        return source.hasFallbackIdentity ? .notFound : .insufficientMetadata
    }

    private static func result(
        _ candidates: [ZoteroItemMetadata],
        basis: ZoteroMatchBasis
    ) -> ZoteroMatchResult {
        let candidates = uniqueCandidates(candidates)
        if candidates.count == 1, let candidate = candidates.first {
            return .matched(candidate, basis: basis)
        }
        if candidates.isEmpty { return .notFound }
        return .ambiguous(candidates, basis: basis)
    }

    private static func uniqueCandidates(_ candidates: [ZoteroItemMetadata]) -> [ZoteroItemMetadata] {
        var seen: Set<String> = []
        return candidates
            .sorted { lhs, rhs in
                let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                if lhs.year != rhs.year { return (lhs.year ?? Int.min) < (rhs.year ?? Int.min) }
                return lhs.key < rhs.key
            }
            .filter { seen.insert(normalizedItemKey($0.key) ?? $0.key).inserted }
    }

    private static func normalizedItemKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value.uppercased()
    }

    private static func normalizedDOI(_ value: String?) -> String? {
        guard var value = normalizedText(value) else { return nil }
        for prefix in ["https://doi.org/", "http://doi.org/", "doi:"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.isEmpty ? nil : compact
    }

    private static func normalizedISBN(_ value: String?) -> String? {
        guard let value = normalizedText(value) else { return nil }
        let compact = value.filter { $0.isNumber || $0 == "x" }
        return [10, 13].contains(compact.count) ? compact : nil
    }

    private static func normalizedAuthor(_ value: String) -> String? {
        guard let value = normalizedText(value) else { return nil }
        let tokens = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()
        return tokens.isEmpty ? nil : tokens.joined(separator: " ")
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}

/// Pure decoder for Zotero API v3 JSON. The caller remains responsible for
/// loopback transport and for rejecting child objects as lookup candidates.
public enum ZoteroMetadataDecoder {
    public static func decodeItems(from data: Data) throws -> [ZoteroItemMetadata] {
        let object = try jsonObject(from: data)
        let objects: [[String: Any]]
        if let array = object as? [[String: Any]] {
            objects = array
        } else if let dictionary = object as? [String: Any] {
            objects = [dictionary]
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Zotero returned a non-object JSON response."
            ))
        }
        return try objects.map(decodeItem)
    }

    public static func decodeCollectionName(from data: Data) throws -> String? {
        guard let object = try jsonObject(from: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Zotero returned a non-object collection response."
            ))
        }
        let values = object["data"] as? [String: Any] ?? object
        return nonempty(values["name"] as? String)
    }

    private static func jsonObject(from data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Zotero returned invalid JSON.",
                underlyingError: error
            ))
        }
    }

    private static func decodeItem(_ object: [String: Any]) throws -> ZoteroItemMetadata {
        let item = object["data"] as? [String: Any] ?? object
        guard let key = nonempty(item["key"] as? String) ?? nonempty(object["key"] as? String) else {
            throw DecodingError.keyNotFound(
                DynamicCodingKey("key"),
                .init(codingPath: [], debugDescription: "A Zotero item did not include its key.")
            )
        }

        let creatorObjects = item["creators"] as? [[String: Any]] ?? []
        let creators = creatorObjects.compactMap { creator -> ZoteroCreatorMetadata? in
            let role = nonempty(creator["creatorType"] as? String) ?? "creator"
            if let literalName = nonempty(creator["name"] as? String) {
                return ZoteroCreatorMetadata(
                    role: role,
                    name: literalName,
                    literalName: literalName
                )
            }
            let first = nonempty(creator["firstName"] as? String)
            let last = nonempty(creator["lastName"] as? String)
            let name = nonempty([first, last].compactMap { $0 }.joined(separator: " "))
            guard let name else { return nil }
            return ZoteroCreatorMetadata(
                role: role,
                name: name,
                givenName: first,
                familyName: last
            )
        }
        let authors = creators.compactMap { creator -> String? in
            let creatorType = creator.role.lowercased()
            guard creatorType == "author" || creatorType == "bookauthor" else {
                return nil
            }
            return creator.name
        }
        let date = nonempty(item["date"] as? String)
        let year = date?.range(of: #"\b(?:1[5-9]|20)\d{2}\b"#, options: .regularExpression)
            .flatMap { range in date.flatMap { Int($0[range]) } }
        let tags = (item["tags"] as? [Any] ?? []).compactMap { value -> String? in
            if let value = value as? String { return nonempty(value) }
            return (value as? [String: Any]).flatMap { nonempty($0["tag"] as? String) }
        }
        let containerTitle = [
            "publicationTitle", "bookTitle", "proceedingsTitle", "encyclopediaTitle",
            "dictionaryTitle", "conferenceName",
        ].compactMap { nonempty(item[$0] as? String) }.first
        let citationKey = nonempty(item["citationKey"] as? String)
            ?? citationKeyFromExtra(item["extra"] as? String)
        let collectionKeys = (item["collections"] as? [String] ?? [])
            .compactMap(nonempty)

        return ZoteroItemMetadata(
            key: key,
            itemType: nonempty(item["itemType"] as? String),
            title: nonempty(item["title"] as? String) ?? "",
            creators: creators,
            authors: authors,
            date: date,
            year: year,
            language: nonempty(item["language"] as? String),
            containerTitle: containerTitle,
            volume: nonempty(item["volume"] as? String),
            issue: nonempty(item["issue"] as? String),
            pages: nonempty(item["pages"] as? String),
            series: nonempty(item["series"] as? String)
                ?? nonempty(item["seriesTitle"] as? String),
            doi: nonempty(item["DOI"] as? String) ?? nonempty(item["doi"] as? String),
            isbn: nonempty(item["ISBN"] as? String) ?? nonempty(item["isbn"] as? String),
            issn: nonempty(item["ISSN"] as? String) ?? nonempty(item["issn"] as? String),
            citationKey: citationKey,
            abstract: nonempty(item["abstractNote"] as? String),
            tags: tags,
            publisher: nonempty(item["publisher"] as? String),
            place: nonempty(item["place"] as? String),
            edition: nonempty(item["edition"] as? String),
            url: nonempty(item["url"] as? String),
            collectionKeys: collectionKeys,
            dateModified: parseDate(item["dateModified"] as? String)
        )
    }

    private static func citationKeyFromExtra(_ extra: String?) -> String? {
        guard let extra else { return nil }
        for line in extra.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("Citation Key") == .orderedSame else { continue }
            return nonempty(parts[1])
        }
        return nil
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value = nonempty(value) else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
