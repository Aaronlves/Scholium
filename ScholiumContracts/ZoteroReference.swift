import Foundation

/// A locator, not proof that Zotero opened a resource or that its content was read.
public struct ZoteroReference: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case item, pdf }
    public enum InvalidReference: Error { case invalid }

    public let library: ZoteroLibraryIdentity
    public let kind: Kind
    /// For PDF references this is the attachment key, never its bibliographic parent.
    public let itemKey: String
    public let page: Int?
    public let annotationKey: String?

    public init(library: ZoteroLibraryIdentity, kind: Kind = .item, itemKey: String,
                page: Int? = nil, annotationKey: String? = nil) throws {
        if case .group(let id) = library, id <= 0 { throw InvalidReference.invalid }
        guard let key = Self.normalizedKey(itemKey),
              page == nil || page! > 0,
              kind == .pdf || (page == nil && annotationKey == nil) else { throw InvalidReference.invalid }
        let annotation = annotationKey.flatMap(Self.normalizedKey)
        guard annotationKey == nil || annotation != nil else { throw InvalidReference.invalid }
        self.library = library
        self.kind = kind
        self.itemKey = key
        self.page = page
        self.annotationKey = annotation
    }

    public static func normalizedKey(_ value: String) -> String? {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty, key.utf8.count <= 128,
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }) else { return nil }
        return key
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "zotero"
        components.host = kind == .item ? "select" : "open-pdf"
        switch library {
        case .user: components.path = "/library/items/\(itemKey)"
        case .group(let id): components.path = "/groups/\(id)/items/\(itemKey)"
        }
        var query: [URLQueryItem] = []
        if let page { query.append(.init(name: "page", value: String(page))) }
        if let annotationKey { query.append(.init(name: "annotation", value: annotationKey)) }
        if !query.isEmpty { components.queryItems = query }
        // Every component is constructed from validated, URL-safe values.
        return components.url!
    }

    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "zotero", components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              components.host == "select" || components.host == "open-pdf" else { throw InvalidReference.invalid }
        let path = components.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let library: ZoteroLibraryIdentity
        let key: String
        if path.count == 4, path[0].isEmpty, path[1] == "library", path[2] == "items" {
            library = .user
            key = path[3]
        } else if path.count == 5, path[0].isEmpty, path[1] == "groups", path[3] == "items",
                  let id = Self.positiveInteger(path[2]) {
            library = .group(id)
            key = path[4]
        } else { throw InvalidReference.invalid }
        let query = components.queryItems ?? []
        guard key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              Set(query.map(\.name)).count == query.count,
              query.allSatisfy({ ["page", "annotation"].contains($0.name) && $0.value?.isEmpty == false }) else { throw InvalidReference.invalid }
        let pageValue = query.first { $0.name == "page" }?.value
        let page = pageValue.flatMap(Self.positiveInteger)
        let annotation = query.first { $0.name == "annotation" }?.value
        guard pageValue == nil || page != nil,
              annotation == annotation?.trimmingCharacters(in: .whitespacesAndNewlines) else { throw InvalidReference.invalid }
        try self.init(library: library, kind: components.host == "select" ? .item : .pdf,
                      itemKey: key, page: page, annotationKey: annotation)
    }

    private static func positiveInteger(_ value: String) -> Int? {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = Int(value), number > 0 else { return nil }
        return number
    }

    private enum CodingKeys: String, CodingKey {
        case library, kind, page
        case itemKey = "item_key", annotationKey = "annotation_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(library: container.decode(ZoteroLibraryIdentity.self, forKey: .library),
                      kind: container.decode(Kind.self, forKey: .kind),
                      itemKey: container.decode(String.self, forKey: .itemKey),
                      page: container.decodeIfPresent(Int.self, forKey: .page),
                      annotationKey: container.decodeIfPresent(String.self, forKey: .annotationKey))
    }
}
