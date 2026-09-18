import Foundation
import ScholiumContracts

/// The broader Zotero Desktop API/Connector surface exposed by the bundled
/// MCP. This file deliberately deals in verified JSON values rather than a
/// second metadata model: Zotero owns the item schema and remains authoritative.
extension ZoteroMCPServer {
    static let additionalToolDefinitions: [ZoteroMCPJSONValue] = [
        tool(
            name: "zotero_inventory",
            description: "List Zotero items from a user or group library. Child notes and attachments require an explicit flag.",
            properties: [
                "library": libraryProperty,
                "include_children": .object(["type": .string("boolean"), "default": .bool(false)]),
                "limit": boundedLimitProperty,
                "start": .object(["type": .string("integer"), "minimum": .integer(0), "maximum": .integer(10_000), "default": .integer(0)]),
            ]
        ),
        tool(
            name: "zotero_collections",
            description: "List Zotero collections, including collection keys, parent relationships and versions.",
            properties: [
                "library": libraryProperty,
                "top_level_only": .object(["type": .string("boolean"), "default": .bool(false)]),
                "limit": boundedLimitProperty,
                "start": startProperty,
            ]
        ),
        tool(
            name: "zotero_tags",
            description: "List Zotero tags and their local item counts.",
            properties: ["library": libraryProperty, "limit": boundedLimitProperty, "start": startProperty]
        ),
        tool(
            name: "zotero_groups",
            description: "List synced Zotero group libraries visible through the local API.",
            properties: [:]
        ),
        tool(
            name: "zotero_children",
            description: "List notes, attachments and other child records for one exact Zotero item.",
            properties: ["library": libraryProperty, "item_key": keyProperty],
            required: ["item_key"]
        ),
        tool(
            name: "zotero_fulltext",
            description: "Read Zotero's indexed attachment text for one exact attachment key. The response is bounded by the local MCP transport limit.",
            properties: ["library": libraryProperty, "attachment_key": keyProperty],
            required: ["attachment_key"]
        ),
        tool(
            name: "zotero_file_url",
            description: "Return Zotero's API-resolved local file URL for one exact attachment without opening an arbitrary path.",
            properties: ["library": libraryProperty, "attachment_key": keyProperty],
            required: ["attachment_key"]
        ),
        tool(
            name: "zotero_export_bibtex",
            description: "Export one item or a bounded library page as Zotero-generated BibTeX.",
            properties: [
                "library": libraryProperty,
                "item_key": keyProperty,
                "include_children": .object(["type": .string("boolean"), "default": .bool(false)]),
                "limit": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(100), "default": .integer(100)]),
            ]
        ),
        tool(
            name: "zotero_citations",
            description: "Return Zotero-rendered citations for top-level items in the requested CSL style.",
            properties: [
                "library": libraryProperty,
                "style": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(128), "default": .string("apa")]),
                "limit": boundedLimitProperty,
            ]
        ),
        tool(
            name: "zotero_probe",
            description: "Probe the documented Zotero local API surfaces and report status and bounded response shapes without importing or modifying data.",
            properties: [:]
        ),
        tool(
            name: "zotero_import_bibtex",
            description: "Import BibTeX text through Zotero Connector into the currently selected editable library or collection. Requires explicit confirmation.",
            properties: importProperties,
            required: ["text", "confirm", "target_fingerprint"],
            readOnly: false
        ),
        tool(
            name: "zotero_import_ris",
            description: "Import RIS text through Zotero Connector into the currently selected editable library or collection. Requires explicit confirmation.",
            properties: importProperties,
            required: ["text", "confirm", "target_fingerprint"],
            readOnly: false
        ),
        tool(
            name: "zotero_update_item",
            description: "Modify one Zotero item through the local API. Requires explicit confirmation, the exact library and the item's current version; omitted fields are preserved.",
            properties: [
                "library": libraryProperty,
                "item_key": keyProperty,
                "data": .object([
                    "type": .string("object"),
                    "description": .string("Zotero data fields to replace. key, version and itemType cannot be changed."),
                    "additionalProperties": .bool(true),
                ]),
                "expected_version": .object(["type": .string("integer"), "minimum": .integer(1)]),
                "confirm": .object(["type": .string("boolean"), "const": .bool(true)]),
            ],
            required: ["library", "item_key", "data", "expected_version", "confirm"],
            readOnly: false
        ),
    ]

    private static let libraryProperty: ZoteroMCPJSONValue = .object([
        "type": .string("string"),
        "pattern": .string("^(user|group:[1-9][0-9]*)$"),
        "description": .string("Use user or group:<numeric-group-id>. Specify it when a key may exist in more than one library."),
    ])

    private static let keyProperty: ZoteroMCPJSONValue = .object([
        "type": .string("string"), "minLength": .integer(1), "maxLength": .integer(128),
    ])

    private static let boundedLimitProperty: ZoteroMCPJSONValue = .object([
        "type": .string("integer"), "minimum": .integer(1), "maximum": .integer(100), "default": .integer(25),
    ])

    private static let startProperty: ZoteroMCPJSONValue = .object([
        "type": .string("integer"), "minimum": .integer(0), "maximum": .integer(10_000), "default": .integer(0),
    ])

    private static let importProperties: [String: ZoteroMCPJSONValue] = [
        "text": .object(["type": .string("string"), "minLength": .integer(1), "maxLength": .integer(1_048_576)]),
        "confirm": .object(["type": .string("boolean"), "const": .bool(true)]),
        "target_fingerprint": .object([
            "type": .string("string"), "pattern": .string("^[0-9a-f]{64}$"),
            "description": .string("Fingerprint returned by zotero_selected_target; it binds the import to the inspected target."),
        ]),
        "session": .object(["type": .string("string"), "maxLength": .integer(128)]),
    ]

    func inventory(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "include_children", "limit", "start"].contains),
            let routes = try? await selectedLibraryRoutes(arguments["library"]?.stringValue)
        else { throw ZoteroMCPServiceError.invalidArguments }
        let includeChildren = try boolean(arguments["include_children"], default: false)
        let limit = try integer(arguments["limit"], default: 25, range: 1...100)
        let start = try integer(arguments["start"], default: 0, range: 0...10_000)
        var libraries: [ZoteroMCPJSONValue] = []
        for route in routes {
            let query = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start)),
                URLQueryItem(name: "sort", value: "title"),
                URLQueryItem(name: "direction", value: "asc"),
            ]
            guard let request = ZoteroMCPRequestFactory.api(
                route: route, resource: includeChildren ? .items(query: query) : .topItems(query: query))
            else { throw ZoteroMCPServiceError.invalidRequest }
            let response = try await sendAPI(request)
            let items = try decodeArray(response.body, maximum: 100)
            libraries.append(.object([
                "library": route.value,
                "count": .integer(items.count),
                "items": .array(items),
            ]))
        }
        return .object(["start": .integer(start), "limit": .integer(limit), "libraries": .array(libraries)])
    }

    func collections(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "top_level_only", "limit", "start"].contains) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        let topOnly = try boolean(arguments["top_level_only"], default: false)
        let limit = try integer(arguments["limit"], default: 25, range: 1...100)
        let start = try integer(arguments["start"], default: 0, range: 0...10_000)
        let resource: ZoteroMCPRequestFactory.APIResource = topOnly
            ? .topCollections(query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start)),
            ])
            : .collections(query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start)),
            ])
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: resource) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        let values = try decodeArray(response.body, maximum: 100)
        return .object([
            "library": route.value, "top_level_only": .bool(topOnly),
            "count": .integer(values.count), "collections": .array(values),
        ])
    }

    func tags(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "limit", "start"].contains) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        let limit = try integer(arguments["limit"], default: 25, range: 1...100)
        let start = try integer(arguments["start"], default: 0, range: 0...10_000)
        guard let request = ZoteroMCPRequestFactory.api(
            route: route,
            resource: .tags(query: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "start", value: String(start)),
            ]))
        else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        let all = try decodeArray(response.body, maximum: 1_000)
        let values = Array(all.prefix(limit))
        return .object([
            "library": route.value, "start": .integer(start), "limit": .integer(limit),
            "count": .integer(values.count), "tags": .array(values),
        ])
    }

    func groups() async throws -> ZoteroMCPJSONValue {
        let routes = try await libraryRoutes()
        return .object([
            "count": .integer(routes.count - 1),
            "libraries": .array(routes.map { route in
                switch route {
                case .user:
                    return .object(["type": .string("user"), "id": .integer(0), "name": .string("My Library")])
                case .group(let id, let name):
                    return .object(["type": .string("group"), "id": .integer(id), "name": .string(name)])
                }
            }),
        ])
    }

    func children(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "item_key"].contains),
            let key = normalizedKey(arguments["item_key"]?.stringValue)
        else { throw ZoteroMCPServiceError.invalidArguments }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .children(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let values = try decodeArray((try await sendAPI(request)).body, maximum: 50)
        return .object(["library": route.value, "item_key": .string(key), "count": .integer(values.count), "children": .array(values)])
    }

    func fullText(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "attachment_key"].contains),
            let key = normalizedKey(arguments["attachment_key"]?.stringValue)
        else { throw ZoteroMCPServiceError.invalidArguments }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .fullText(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let value = try decodeJSON((try await sendAPI(request)).body)
        guard case .object = value else { throw ZoteroMCPServiceError.invalidResponse }
        return .object(["library": route.value, "attachment_key": .string(key), "fulltext": value])
    }

    func fileURL(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "attachment_key"].contains),
            let key = normalizedKey(arguments["attachment_key"]?.stringValue)
        else { throw ZoteroMCPServiceError.invalidArguments }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .fileURL(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        guard response.body.count <= 16_384,
            let raw = String(data: response.body, encoding: .utf8),
            raw == raw.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: raw),
            url.isFileURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "file", components.host == nil,
            components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil,
            url.path.hasPrefix("/"), url.path == url.standardizedFileURL.path
        else { throw ZoteroMCPServiceError.originalUnavailable }
        return .object([
            "library": route.value, "attachment_key": .string(key),
            "url": .string(url.absoluteString), "path": .string(url.path),
        ])
    }

    func exportBibtex(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "item_key", "include_children", "limit"].contains) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        let itemKey = arguments["item_key"].flatMap(\.stringValue).flatMap(normalizedKey)
        if arguments["item_key"] != nil, itemKey == nil { throw ZoteroMCPServiceError.invalidArguments }
        let includeChildren = try boolean(arguments["include_children"], default: false)
        let limit = try integer(arguments["limit"], default: 100, range: 1...100)
        var chunks: [String] = []
        var start = 0
        var total: Int?
        repeat {
            var query = [
                URLQueryItem(name: "format", value: "bibtex"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
            if let itemKey { query.append(URLQueryItem(name: "itemKey", value: itemKey)) }
            if itemKey == nil {
                query.append(URLQueryItem(name: "sort", value: "title"))
                query.append(URLQueryItem(name: "direction", value: "asc"))
                query.append(URLQueryItem(name: "start", value: String(start)))
            }
            let resource: ZoteroMCPRequestFactory.APIResource = includeChildren
                ? .items(query: query) : .topItems(query: query)
            guard let request = ZoteroMCPRequestFactory.api(route: route, resource: resource) else {
                throw ZoteroMCPServiceError.invalidRequest
            }
            let response = try await sendAPI(request)
            guard let text = String(data: response.body, encoding: .utf8) else {
                throw ZoteroMCPServiceError.invalidResponse
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            total = response.header(named: "Total-Results").flatMap(Int.init)
            if itemKey != nil { break }
            start += limit
            if start >= (total ?? start + (bibtexEntryCount(text) < limit ? 0 : limit)) || start >= 1_000 { break }
        } while true
        let text = chunks.joined(separator: "\n\n")
        return .object([
            "library": route.value, "item_key": itemKey.map(ZoteroMCPJSONValue.string) ?? .null,
            "include_children": .bool(includeChildren), "bibtex": .string(text + (text.isEmpty ? "" : "\n")),
            "bytes": .integer(text.utf8.count), "entries": .integer(bibtexEntryCount(text)),
        ])
    }

    func citations(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "style", "limit"].contains),
            let style = arguments["style"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !style.isEmpty, style.utf8.count <= 128,
            style.unicodeScalars.allSatisfy({
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.controlCharacters.contains($0)
            })
        else { throw ZoteroMCPServiceError.invalidArguments }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        let limit = try integer(arguments["limit"], default: 25, range: 1...100)
        guard let request = ZoteroMCPRequestFactory.api(
            route: route,
            resource: .topItems(query: [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "include", value: "data,citation"),
                URLQueryItem(name: "style", value: style),
                URLQueryItem(name: "limit", value: String(limit)),
            ]))
        else { throw ZoteroMCPServiceError.invalidRequest }
        let values = try decodeArray((try await sendAPI(request)).body, maximum: 100)
        return .object(["library": route.value, "style": .string(style), "count": .integer(values.count), "items": .array(values)])
    }

    func probe() async throws -> ZoteroMCPJSONValue {
        let endpoints: [(String, URLRequest?)] = [
            ("root", ZoteroMCPRequestFactory.globalAPI(path: .root)),
            ("schema", ZoteroMCPRequestFactory.globalAPI(path: .schema)),
            ("item_types", ZoteroMCPRequestFactory.globalAPI(path: .itemTypes)),
            ("item_fields", ZoteroMCPRequestFactory.globalAPI(path: .itemFields)),
            ("creator_fields", ZoteroMCPRequestFactory.globalAPI(path: .creatorFields)),
            ("collections", ZoteroMCPRequestFactory.api(route: .user, resource: .collections(query: []))),
            ("top_collections", ZoteroMCPRequestFactory.api(route: .user, resource: .topCollections(query: []))),
            ("top_items", ZoteroMCPRequestFactory.api(route: .user, resource: .topItems(query: [URLQueryItem(name: "limit", value: "1")]))) ,
            ("tags", ZoteroMCPRequestFactory.api(route: .user, resource: .tags(query: []))),
            ("searches", ZoteroMCPRequestFactory.api(route: .user, resource: .searches)),
            ("fulltext_versions", ZoteroMCPRequestFactory.api(route: .user, resource: .fullTextVersions)),
            ("connector_ping", ZoteroMCPRequestFactory.connector(endpoint: .ping)),
        ]
        var rows: [ZoteroMCPJSONValue] = []
        for (label, request) in endpoints {
            guard let request else { throw ZoteroMCPServiceError.invalidRequest }
            let response: ZoteroMCPHTTPResponse
            do { response = try await clientSend(request) } catch { rows.append(.object(["label": .string(label), "status": .string("unavailable")])) ; continue }
            var row: [String: ZoteroMCPJSONValue] = ["label": .string(label), "status": .integer(response.statusCode)]
            if let value = try? decodeJSON(response.body) {
                switch value {
                case .array(let values): row["shape"] = .object(["type": .string("array"), "count": .integer(values.count)])
                case .object(let object): row["shape"] = .object(["type": .string("object"), "keys": .array(object.keys.sorted().prefix(12).map(ZoteroMCPJSONValue.string))])
                default: row["shape"] = .object(["type": .string("scalar")])
                }
            }
            rows.append(.object(row))
        }
        return .object(["endpoints": .array(rows)])
    }

    func importRecords(_ arguments: [String: ZoteroMCPJSONValue], kind: String) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["text", "confirm", "target_fingerprint", "session"].contains),
            arguments["confirm"]?.boolValue == true,
            let text = arguments["text"]?.stringValue,
            let expectedTarget = arguments["target_fingerprint"]?.stringValue,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.utf8.count <= 1 * 1_024 * 1_024
        else { throw ZoteroMCPServiceError.confirmationRequired }
        let target = try await selectedTarget()
        guard target.isWritable else { throw ZoteroMCPServiceError.targetNotWritable }
        if expectedTarget != target.fingerprint {
            throw ZoteroMCPServiceError.materialChanged
        }
        let session = arguments["session"]?.stringValue ?? "scholium-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        guard let request = ZoteroMCPRequestFactory.connectorImport(session: session, text: text) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendConnector(request)
        let result = (try? decodeJSON(response.body)) ?? .string(String(decoding: response.body, as: UTF8.self))
        return .object([
            "status": .string("imported"), "format": .string(kind), "session": .string(session),
            "target": target.value, "response": result,
        ])
    }

    func updateItem(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard arguments.keys.allSatisfy(["library", "item_key", "data", "expected_version", "confirm"].contains),
            arguments["confirm"]?.boolValue == true,
            let key = normalizedKey(arguments["item_key"]?.stringValue),
            let patch = arguments["data"]?.objectValue,
            !patch.isEmpty,
            let expectedVersion = arguments["expected_version"]?.intValue,
            expectedVersion > 0
        else { throw ZoteroMCPServiceError.confirmationRequired }
        let route = try await singleLibraryRoute(arguments["library"]?.stringValue)
        guard let currentRequest = ZoteroMCPRequestFactory.api(route: route, resource: .item(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let currentResponse = try await sendAPI(currentRequest)
        let current = try decodeObject(currentResponse.body)
        let currentData = try decodeObjectValue(current["data"] ?? .object(current))
        guard let currentKey = currentData["key"]?.stringValue, currentKey == key else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        guard let currentVersion = current["version"]?.intValue ?? currentResponse.header(named: "Last-Modified-Version").flatMap(Int.init),
            currentVersion == expectedVersion
        else { throw ZoteroMCPServiceError.materialChanged }
        if let patchKey = patch["key"]?.stringValue, normalizedKey(patchKey) != key { throw ZoteroMCPServiceError.invalidArguments }
        if patch["version"] != nil { throw ZoteroMCPServiceError.invalidArguments }
        if let itemType = patch["itemType"]?.stringValue, itemType != currentData["itemType"]?.stringValue { throw ZoteroMCPServiceError.invalidArguments }
        var merged = currentData
        for (field, value) in patch { merged[field] = value }
        merged["key"] = .string(key)
        if let itemType = currentData["itemType"] { merged["itemType"] = itemType }
        let body = try encodeJSON(.object(merged), maximum: 256 * 1_024)
        guard let request = ZoteroMCPRequestFactory.apiWrite(route: route, itemKey: key, body: body, expectedVersion: expectedVersion) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        _ = try await sendAPI(request)
        guard let verificationRequest = ZoteroMCPRequestFactory.api(route: route, resource: .item(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let verifiedResponse = try await sendAPI(verificationRequest)
        let verified = try decodeObject(verifiedResponse.body)
        let verifiedData = try decodeObjectValue(verified["data"] ?? .object(verified))
        for (field, value) in patch {
            guard verifiedData[field] == value else { throw ZoteroMCPServiceError.invalidResponse }
        }
        return .object([
            "status": .string("updated"), "library": route.value, "item_key": .string(key),
            "previous_version": .integer(expectedVersion),
            "version": verified["version"] ?? verifiedResponse.header(named: "Last-Modified-Version").flatMap { .integer(Int($0) ?? expectedVersion) } ?? .null,
        ])
    }

    private func singleLibraryRoute(_ selector: String?) async throws -> LibraryRoute {
        guard let selector else { return .user }
        if selector == "user" { return .user }
        guard selector.hasPrefix("group:"), let id = Int(selector.dropFirst("group:".count)), id > 0 else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        guard let route = try await libraryRoutes().first(where: { $0.groupID == id }) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        return route
    }

    private func clientSend(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        do { return try await client.send(request) } catch { throw ZoteroMCPServiceError.zoteroUnavailable }
    }

    private func decodeJSON(_ data: Data) throws -> ZoteroMCPJSONValue {
        guard data.count <= 4 * 1_024 * 1_024 else { throw ZoteroMCPServiceError.responseTooLarge }
        do { return try JSONDecoder().decode(ZoteroMCPJSONValue.self, from: data) }
        catch { throw ZoteroMCPServiceError.invalidResponse }
    }

    private func decodeObject(_ data: Data) throws -> [String: ZoteroMCPJSONValue] {
        try decodeObjectValue(decodeJSON(data))
    }

    private func decodeObjectValue(_ value: ZoteroMCPJSONValue) throws -> [String: ZoteroMCPJSONValue] {
        guard let object = value.objectValue else { throw ZoteroMCPServiceError.invalidResponse }
        return object
    }

    private func decodeArray(_ data: Data, maximum: Int) throws -> [ZoteroMCPJSONValue] {
        guard case .array(let values) = try decodeJSON(data), values.count <= maximum else {
            throw ZoteroMCPServiceError.responseTooLarge
        }
        return values
    }

    private func encodeJSON(_ value: ZoteroMCPJSONValue, maximum: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maximum else { throw ZoteroMCPServiceError.responseTooLarge }
        return data
    }

    private func boolean(_ value: ZoteroMCPJSONValue?, default fallback: Bool) throws -> Bool {
        guard let value else { return fallback }
        guard let boolean = value.boolValue else { throw ZoteroMCPServiceError.invalidArguments }
        return boolean
    }

    private func integer(_ value: ZoteroMCPJSONValue?, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value else { return fallback }
        guard let integer = value.intValue, range.contains(integer) else { throw ZoteroMCPServiceError.invalidArguments }
        return integer
    }

    private func normalizedKey(_ value: String?) -> String? {
        value.flatMap(ZoteroReference.normalizedKey)
    }

    private func bibtexEntryCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("@") }.count
    }
}
