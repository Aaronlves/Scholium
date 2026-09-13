import CryptoKit
import Foundation
import ScholiumContracts

public struct ZoteroMCPHTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
public protocol ZoteroMCPHTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse
}

public struct ZoteroMCPURLSessionClient: ZoteroMCPHTTPClient, Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: ZoteroNoRedirectDelegate(), delegateQueue: nil)
    }

    init(session: URLSession) { self.session = session }

    public func send(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        let maximum = 4 * 1_024 * 1_024
        guard response.expectedContentLength <= maximum else {
            throw ZoteroMCPServiceError.responseTooLarge
        }
        let body = try await withTaskCancellationHandler {
            var body = Data()
            for try await byte in bytes {
                guard body.count < maximum else { throw ZoteroMCPServiceError.responseTooLarge }
                if body.count.isMultiple(of: 8_192) { try Task.checkCancellation() }
                body.append(byte)
            }
            try Task.checkCancellation()
            return body
        } onCancel: {
            bytes.task.cancel()
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        return ZoteroMCPHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body
        )
    }
}

/// A first-party stdio MCP implementation for bounded Zotero operations.
/// Original reads open only an exact API-resolved attachment; never SQLite.
/// Metadata reads use the localhost API; guarded imports use the localhost
/// Connector only after a one-shot, target-bound dry run.
public actor ZoteroMCPServer {
    public static let protocolVersion = "2025-11-25"
    public static let serverName = "scholium-zotero"
    public static let serverVersion = ScholiumProductIdentity.marketingVersion

    private let client: any ZoteroMCPHTTPClient

    public init(
        client: any ZoteroMCPHTTPClient = ZoteroMCPURLSessionClient()
    ) {
        self.client = client
    }

    /// Handles one JSON-RPC message body. Notifications intentionally return
    /// nil. Diagnostics and errors never echo search text or import content.
    public func handle(requestData: Data, access: ZoteroMCPAccess) async -> Data? {
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: requestData)
        } catch {
            return encode(responseError(id: .null, code: -32700, message: "Invalid JSON-RPC payload."))
        }

        guard let id = request.id else {
            return nil
        }
        guard request.jsonrpc == "2.0", !request.method.isEmpty else {
            return encode(responseError(id: id, code: -32600, message: "Invalid JSON-RPC request."))
        }

        switch request.method {
        case "initialize":
            let requestedVersion = request.params?.objectValue?["protocolVersion"]?.stringValue
            let selectedVersion =
                [Self.protocolVersion, "2024-11-05"].contains(requestedVersion)
                ? requestedVersion!
                : Self.protocolVersion
            return encode(
                responseResult(
                    id: id,
                    result: .object([
                        "protocolVersion": .string(selectedVersion),
                        "capabilities": .object(["tools": .object([:])]),
                        "serverInfo": .object([
                            "name": .string(Self.serverName),
                            "version": .string(Self.serverVersion),
                        ]),
                    ])))

        case "ping":
            return encode(responseResult(id: id, result: .object([:])))

        case "tools/list":
            return encode(
                responseResult(
                    id: id,
                    result: .object([
                        "tools": .array(Self.toolDefinitions(for: access))
                    ])))

        case "tools/call":
            let result = await callTool(params: request.params, access: access)
            return encode(responseResult(id: id, result: result))

        default:
            return encode(responseError(id: id, code: -32601, message: "Unsupported MCP method."))
        }
    }

    private func callTool(params: ZoteroMCPJSONValue?, access: ZoteroMCPAccess) async -> ZoteroMCPJSONValue {
        do {
            guard let params = params?.objectValue,
                let name = params["name"]?.stringValue
            else {
                throw ZoteroMCPServiceError.invalidArguments
            }
            guard Self.toolDefinitions(for: access).contains(where: { $0.objectValue?["name"]?.stringValue == name }) else {
                throw ZoteroMCPServiceError.unknownTool
            }
            let arguments: [String: ZoteroMCPJSONValue]
            if let value = params["arguments"] {
                guard let object = value.objectValue else {
                    throw ZoteroMCPServiceError.invalidArguments
                }
                arguments = object
            } else {
                arguments = [:]
            }

            let execution: ToolExecution
            switch name {
            case "zotero_status":
                execution = .success(await status(access: access))
            case "zotero_search":
                execution = .success(try await search(arguments))
            case "zotero_item":
                execution = .success(try await inspectItem(arguments))
            case "zotero_list_annotations":
                execution = .success(try await listAnnotations(arguments))
            case "zotero_read_annotation":
                execution = .success(try await readAnnotation(arguments))
            case "zotero_read_original":
                execution = .success(try await readOriginal(arguments))
            case "zotero_selected_target":
                execution = .success(try await selectedTarget().value)
            default:
                throw ZoteroMCPServiceError.unknownTool
            }
            return toolResult(execution.value, isError: execution.isError, includesImage: name == "zotero_read_original")
        } catch let error as ZoteroMCPServiceError {
            return toolResult(
                .object([
                    "status": .string("failed"),
                    "error": .string(error.errorDescription ?? "Zotero operation failed."),
                ]), isError: true)
        } catch {
            return toolResult(
                .object([
                    "status": .string("failed"),
                    "error": .string("Zotero operation failed at the local transport boundary."),
                ]), isError: true)
        }
    }

    private func status(access: ZoteroMCPAccess) async -> ZoteroMCPJSONValue {
        let apiRequest = ZoteroMCPRequestFactory.api(
            route: .user,
            resource: .items(query: [
                URLQueryItem(name: "itemType", value: "-attachment"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        )
        let connectorRequest = ZoteroMCPRequestFactory.connector(endpoint: .ping)

        let apiState = await availability(of: apiRequest, disabledStatus: 403)
        let connectorState = await availability(of: connectorRequest, disabledStatus: nil)
        return .object([
            "local_api": .string(apiState),
            "connector": .string(connectorState),
            "retrieval_mode": .string("localhost-read-only"),
            "guarded_imports": .bool(false),
            "access_mode": .string(access.rawValue),
            "direct_database_access": .bool(false),
        ])
    }

    private func availability(of request: URLRequest?, disabledStatus: Int?) async -> String {
        guard let request else { return "invalid-request" }
        do {
            let response = try await client.send(request)
            if (200..<300).contains(response.statusCode) { return "available" }
            if response.statusCode == disabledStatus { return "disabled" }
            return "http-\(response.statusCode)"
        } catch {
            return "unavailable"
        }
    }

    private func search(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard let rawQuery = arguments["query"]?.stringValue else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 512 else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let limit = arguments["limit"]?.intValue ?? 10
        guard (1...25).contains(limit) else {
            throw ZoteroMCPServiceError.invalidArguments
        }

        let routes = try await libraryRoutes()
        var hits: [ItemHit] = []
        for route in routes {
            guard
                let request = ZoteroMCPRequestFactory.api(
                    route: route,
                    resource: .items(query: [
                        URLQueryItem(name: "format", value: "json"),
                        URLQueryItem(name: "itemType", value: "-attachment"),
                        URLQueryItem(name: "q", value: query),
                        URLQueryItem(name: "qmode", value: "everything"),
                        URLQueryItem(name: "limit", value: String(limit)),
                    ])
                )
            else {
                throw ZoteroMCPServiceError.invalidRequest
            }
            let response = try await sendAPI(request)
            let items = try decodedParentItems(response.body)
            hits.append(contentsOf: items.map { ItemHit(route: route, item: $0) })
        }

        hits.sort { lhs, rhs in
            let titleOrder = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            if lhs.item.year != rhs.item.year {
                return (lhs.item.year ?? Int.min) < (rhs.item.year ?? Int.min)
            }
            if lhs.route.identity != rhs.route.identity {
                return lhs.route.identity < rhs.route.identity
            }
            return lhs.item.key < rhs.item.key
        }
        if hits.count > limit { hits.removeLast(hits.count - limit) }

        return .object([
            "query_scope": .string("local-user-and-group-libraries"),
            "count": .integer(hits.count),
            "results": .array(try hits.map { try metadataValue($0.item, route: $0.route) }),
        ])
    }

    private func inspectItem(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard let itemKey = normalizedKey(arguments["item_key"]?.stringValue) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let includeAttachments: Bool
        if let value = arguments["include_attachments"] {
            guard let bool = value.boolValue else { throw ZoteroMCPServiceError.invalidArguments }
            includeAttachments = bool
        } else {
            includeAttachments = false
        }

        let routes = try await selectedLibraryRoutes(arguments["library"]?.stringValue)
        var matches: [(route: LibraryRoute, response: ZoteroMCPHTTPResponse, item: ZoteroItemMetadata)] = []
        for route in routes {
            if let match = try await fetchItem(itemKey, route: route) {
                matches.append((route, match.response, match.item))
            }
        }
        guard !matches.isEmpty else { throw ZoteroMCPServiceError.itemMissing }
        guard matches.count == 1, let match = matches.first else {
            throw ZoteroMCPServiceError.ambiguousItem
        }

        var result = try metadataValue(match.item, route: match.route).objectValue ?? [:]
        if includeAttachments {
            guard
                let request = ZoteroMCPRequestFactory.api(
                    route: match.route,
                    resource: .children(itemKey: itemKey)
                )
            else { throw ZoteroMCPServiceError.invalidRequest }
            let response = try await sendAPI(request)
            let attachments = try JSONDecoder().decode([AttachmentEnvelope].self, from: response.body)
                .filter { $0.data.itemType.lowercased() == "attachment" }
                .prefix(50)
                .map { try attachmentValue($0, parentItem: itemKey, route: match.route) }
            result["attachments"] = .array(Array(attachments))
        }
        return .object(result)
    }

    private func selectedLibraryRoutes(_ selector: String?) async throws -> [LibraryRoute] {
        let routes = try await libraryRoutes()
        guard let selector else { return routes }
        if selector == "user" { return [.user] }
        guard selector.hasPrefix("group:"),
            let id = Int(selector.dropFirst("group:".count)),
            let route = routes.first(where: { $0.groupID == id })
        else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        return [route]
    }

    private func selectedTarget() async throws -> SelectedTarget {
        guard let request = ZoteroMCPRequestFactory.connector(endpoint: .selectedTarget) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendConnector(request)
        guard let value = try? JSONDecoder().decode(ZoteroMCPJSONValue.self, from: response.body),
            let object = value.objectValue,
            let libraryID = object["libraryID"]?.intValue,
            let libraryName = object["libraryName"]?.stringValue,
            let libraryEditable = object["libraryEditable"]?.boolValue,
            let editable = object["editable"]?.boolValue,
            let name = object["name"]?.stringValue
        else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        let selectedID: String?
        if let integer = object["id"]?.intValue {
            selectedID = String(integer)
        } else {
            selectedID = object["id"]?.stringValue
        }
        return SelectedTarget(
            libraryID: libraryID,
            libraryName: libraryName,
            libraryEditable: libraryEditable,
            editable: editable,
            selectedID: selectedID,
            selectedName: name
        )
    }

    private func libraryRoutes() async throws -> [LibraryRoute] {
        guard let request = ZoteroMCPRequestFactory.api(route: .user, resource: .groups) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        let groups = try JSONDecoder().decode([APILibrary].self, from: response.body)
            .filter { $0.type == "group" }
            .sorted { $0.id < $1.id }
        guard groups.count <= 50 else { throw ZoteroMCPServiceError.responseTooLarge }
        return [.user] + groups.map { .group(id: $0.id, name: $0.name) }
    }

    private func fetchItem(
        _ itemKey: String,
        route: LibraryRoute
    ) async throws -> (response: ZoteroMCPHTTPResponse, item: ZoteroItemMetadata)? {
        guard
            let request = ZoteroMCPRequestFactory.api(
                route: route,
                resource: .item(itemKey: itemKey)
            )
        else { throw ZoteroMCPServiceError.invalidRequest }
        let response: ZoteroMCPHTTPResponse
        do {
            response = try await client.send(request)
        } catch let error as ZoteroMCPServiceError {
            throw error
        } catch {
            throw ZoteroMCPServiceError.zoteroUnavailable
        }
        guard response.body.count <= 4 * 1_024 * 1_024 else {
            throw ZoteroMCPServiceError.responseTooLarge
        }
        if response.statusCode == 404 { return nil }
        try validateAPI(response)
        guard let item = try decodedParentItems(response.body).first else {
            throw ZoteroMCPServiceError.itemMissing
        }
        guard item.key == itemKey else { throw ZoteroMCPServiceError.invalidResponse }
        return (response, item)
    }

    func sendAPI(_ request: URLRequest) async throws -> ZoteroMCPHTTPResponse {
        try Task.checkCancellation()
        let response: ZoteroMCPHTTPResponse
        do {
            response = try await client.send(request)
        } catch let error as ZoteroMCPServiceError {
            throw error
        } catch {
            throw ZoteroMCPServiceError.zoteroUnavailable
        }
        guard response.body.count <= 4 * 1_024 * 1_024 else {
            throw ZoteroMCPServiceError.responseTooLarge
        }
        try Task.checkCancellation()
        try validateAPI(response)
        return response
    }

    private func validateAPI(_ response: ZoteroMCPHTTPResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 403: throw ZoteroMCPServiceError.localAPIDisabled
        case 404: throw ZoteroMCPServiceError.itemMissing
        default: throw ZoteroMCPServiceError.invalidResponse
        }
    }

    private func sendConnector(
        _ request: URLRequest
    ) async throws -> ZoteroMCPHTTPResponse {
        let response: ZoteroMCPHTTPResponse
        do {
            response = try await client.send(request)
        } catch let error as ZoteroMCPServiceError {
            throw error
        } catch {
            throw ZoteroMCPServiceError.connectorUnavailable
        }
        guard response.body.count <= 4 * 1_024 * 1_024 else {
            throw ZoteroMCPServiceError.responseTooLarge
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ZoteroMCPServiceError.connectorRejected
        }
        return response
    }

    private func decodedParentItems(_ data: Data) throws -> [ZoteroItemMetadata] {
        do {
            return try ZoteroMetadataDecoder.decodeItems(from: data).filter { item in
                guard let type = item.itemType?.lowercased() else { return true }
                return !["attachment", "annotation", "note"].contains(type)
            }
        } catch {
            throw ZoteroMCPServiceError.invalidResponse
        }
    }

    private func metadataValue(
        _ item: ZoteroItemMetadata,
        route: LibraryRoute
    ) throws -> ZoteroMCPJSONValue {
        var object: [String: ZoteroMCPJSONValue] = [
            "library": route.value,
            "reference": try referenceValue(route: route, itemKey: item.key),
            "item_key": .string(item.key),
            "title": .string(item.title),
            "authors": .array(item.authors.map(ZoteroMCPJSONValue.string)),
            "collections": .array(item.collections.map(ZoteroMCPJSONValue.string)),
            "collection_keys": .array(item.collectionKeys.map(ZoteroMCPJSONValue.string)),
        ]
        set(item.itemType, key: "item_type", in: &object)
        set(item.year, key: "year", in: &object)
        set(item.containerTitle, key: "container_title", in: &object)
        set(item.volume, key: "volume", in: &object)
        set(item.issue, key: "issue", in: &object)
        set(item.pages, key: "pages", in: &object)
        set(item.doi, key: "doi", in: &object)
        set(item.isbn, key: "isbn", in: &object)
        set(item.citationKey, key: "citation_key", in: &object)
        set(item.abstract, key: "abstract", in: &object)
        set(item.publisher, key: "publisher", in: &object)
        set(item.edition, key: "edition", in: &object)
        set(item.url, key: "url", in: &object)
        set(item.dateModified?.ISO8601Format(), key: "date_modified", in: &object)
        return .object(object)
    }

    private func attachmentValue(_ attachment: AttachmentEnvelope, parentItem: String, route: LibraryRoute) throws -> ZoteroMCPJSONValue {
        guard attachment.data.key == attachment.key, attachment.data.parentItem == parentItem else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        var object: [String: ZoteroMCPJSONValue] = [
            "item_key": .string(attachment.key),
            "title": .string(attachment.data.title ?? ""),
            "reference": try referenceValue(
                route: route, itemKey: attachment.key,
                kind: attachment.data.contentType == "application/pdf" ? .pdf : .item),
        ]
        set(attachment.data.contentType, key: "content_type", in: &object)
        set(attachment.data.linkMode, key: "link_mode", in: &object)
        set(attachment.data.filename, key: "filename", in: &object)
        if attachment.data.linkMode == "linked_file" {
            set(attachment.data.path, key: "path", in: &object)
        }
        return .object(object)
    }

    private func set(
        _ value: String?,
        key: String,
        in object: inout [String: ZoteroMCPJSONValue]
    ) {
        guard let value, !value.isEmpty else { return }
        object[key] = .string(value)
    }

    private func set(
        _ value: Int?,
        key: String,
        in object: inout [String: ZoteroMCPJSONValue]
    ) {
        guard let value else { return }
        object[key] = .integer(value)
    }

    private func normalizedKey(_ value: String?) -> String? {
        value.flatMap(ZoteroReference.normalizedKey)
    }

    private func responseResult(
        id: ZoteroMCPJSONValue,
        result: ZoteroMCPJSONValue
    ) -> ZoteroMCPJSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    private func responseError(
        id: ZoteroMCPJSONValue,
        code: Int,
        message: String
    ) -> ZoteroMCPJSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .integer(code), "message": .string(message)]),
        ])
    }

    private func toolResult(
        _ value: ZoteroMCPJSONValue,
        isError: Bool,
        includesImage: Bool = false
    ) -> ZoteroMCPJSONValue {
        var textValue = value
        var imageBlock: ZoteroMCPJSONValue?
        if includesImage, !isError, let image = value.objectValue?["image"]?.objectValue,
            image["mime_type"]?.stringValue == "image/png", let data = image["data"]?.stringValue
        {
            imageBlock = .object(["type": .string("image"), "mimeType": .string("image/png"), "data": .string(data)])
            var object = value.objectValue ?? [:]
            var metadata = image
            metadata["data"] = nil
            object["image"] = .object(metadata)
            textValue = .object(object)
        }
        let text: String
        if let data = try? JSONEncoder.pretty.encode(textValue) {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = "{\"status\":\"failed\"}"
        }
        var content: [ZoteroMCPJSONValue] = [.object(["type": .string("text"), "text": .string(text)])]
        if let imageBlock { content.append(imageBlock) }
        return .object([
            "content": .array(content),
            "structuredContent": value,
            "isError": .bool(isError),
        ])
    }

    private func encode(_ value: ZoteroMCPJSONValue) -> Data? {
        try? JSONEncoder.sorted.encode(value)
    }

    private static func toolDefinitions(for access: ZoteroMCPAccess) -> [ZoteroMCPJSONValue] {
        toolDefinitions
    }

    private static let toolDefinitions: [ZoteroMCPJSONValue] = [
        tool(
            name: "zotero_status",
            description: "Report Zotero localhost API and Connector readiness without reading the Zotero database.",
            properties: [:]
        ),
        tool(
            name: "zotero_search",
            description: "Search parent bibliographic records in local user and group libraries while preserving ambiguity.",
            properties: [
                "query": .object(["type": .string("string"), "maxLength": .integer(512)]),
                "limit": .object([
                    "type": .string("integer"), "minimum": .integer(1),
                    "maximum": .integer(25), "default": .integer(10),
                ]),
            ],
            required: ["query"]
        ),
        tool(
            name: "zotero_item",
            description: "Inspect one exact item key; attachment pointers are returned only when explicitly requested.",
            properties: [
                "item_key": .object(["type": .string("string")]),
                "library": .object([
                    "type": .string("string"),
                    "description": .string("Optional user or group:<numeric-group-id> selector."),
                ]),
                "include_attachments": .object([
                    "type": .string("boolean"), "default": .bool(false),
                ]),
            ],
            required: ["item_key"]
        ),
        tool(
            name: "zotero_selected_target",
            description: "Report only the currently selected library or collection and its editability.",
            properties: [:]
        ),
        annotationListTool,
        annotationReadTool,
        originalReadTool,
    ]

    static func tool(
        name: String,
        description: String,
        properties: [String: ZoteroMCPJSONValue],
        required: [String] = [],
        readOnly: Bool = true
    ) -> ZoteroMCPJSONValue {
        var schema: [String: ZoteroMCPJSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
            "additionalProperties": .bool(false),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map(ZoteroMCPJSONValue.string))
        }
        return .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object(schema),
            "annotations": .object([
                "readOnlyHint": .bool(readOnly), "destructiveHint": .bool(!readOnly), "idempotentHint": .bool(readOnly), "openWorldHint": .bool(false),
            ]),
        ])
    }

}

enum ZoteroMCPServiceError: LocalizedError, Sendable {
    case invalidArguments
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case unknownTool
    case zoteroUnavailable
    case localAPIDisabled
    case connectorUnavailable
    case connectorRejected
    case itemMissing
    case ambiguousItem
    case materialChanged
    case originalUnavailable
    case originalReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "The MCP tool arguments are invalid or incomplete."
        case .invalidRequest: "Scholium refused to construct an unsafe Zotero request."
        case .invalidResponse: "Zotero returned a response Scholium could not verify."
        case .responseTooLarge: "Zotero returned more data than this bounded operation permits."
        case .unknownTool: "The requested Zotero MCP tool is unavailable."
        case .zoteroUnavailable: "Zotero is not responding on this Mac. Open Zotero and try again."
        case .localAPIDisabled: "Zotero local API access is disabled."
        case .connectorUnavailable: "Zotero Connector is not responding on this Mac."
        case .connectorRejected: "Zotero Connector rejected the guarded operation."
        case .itemMissing: "No exact Zotero item was found in the requested library scope."
        case .ambiguousItem: "The item key exists in more than one library; specify the library."
        case .materialChanged: "The selected Zotero material changed. Refresh the selection before reading it."
        case .originalUnavailable:
            "The selected local original is missing, unsafe, unsupported or exceeds 20 MiB. Restore the attachment in Zotero and select it again."
        case .originalReadFailed(let message): message
        }
    }
}

private struct RPCRequest: Decodable, Sendable {
    let jsonrpc: String
    let id: ZoteroMCPJSONValue?
    let method: String
    let params: ZoteroMCPJSONValue?
}

enum ZoteroMCPJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case object([String: ZoteroMCPJSONValue])
    case array([ZoteroMCPJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var intValue: Int? {
        switch self {
        case .integer(let value): value
        case .number(let value): Int(exactly: value)
        default: nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    var objectValue: [String: Self]? {
        if case .object(let value) = self { value } else { nil }
    }

    var arrayValue: [Self]? {
        if case .array(let value) = self { value } else { nil }
    }
}

private struct ToolExecution: Sendable {
    let value: ZoteroMCPJSONValue
    let isError: Bool

    static func success(_ value: ZoteroMCPJSONValue) -> Self {
        Self(value: value, isError: false)
    }

    static func failure(_ value: ZoteroMCPJSONValue) -> Self {
        Self(value: value, isError: true)
    }
}

private struct SelectedTarget: Sendable {
    let libraryID: Int
    let libraryName: String
    let libraryEditable: Bool
    let editable: Bool
    let selectedID: String?
    let selectedName: String

    var isCollection: Bool { selectedID != nil }
    var isWritable: Bool { libraryEditable && editable }
    var fingerprint: String {
        let source = [
            String(libraryID), libraryName, String(libraryEditable), String(editable),
            selectedID ?? "library-root", selectedName,
        ].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var value: ZoteroMCPJSONValue {
        .object([
            "kind": .string(isCollection ? "collection" : "library"),
            "library_id": .integer(libraryID),
            "library_name": .string(libraryName),
            "library_editable": .bool(libraryEditable),
            "target_id": selectedID.map(ZoteroMCPJSONValue.string) ?? .null,
            "target_name": .string(selectedName),
            "target_editable": .bool(editable),
        ])
    }
}

enum LibraryRoute: Hashable, Sendable {
    case user
    case group(id: Int, name: String)

    var groupID: Int? {
        if case .group(let id, _) = self { id } else { nil }
    }
    var name: String? {
        if case .group(_, let name) = self { name } else { nil }
    }
    var identity: String {
        switch self {
        case .user: "user:0"
        case .group(let id, _): "group:\(id)"
        }
    }
    var apiPrefix: String {
        switch self {
        case .user: "/api/users/0"
        case .group(let id, _): "/api/groups/\(id)"
        }
    }
    var value: ZoteroMCPJSONValue {
        switch self {
        case .user:
            .object(["type": .string("user"), "id": .integer(0)])
        case .group(let id, let name):
            .object(["type": .string("group"), "id": .integer(id), "name": .string(name)])
        }
    }
}

private struct ItemHit: Sendable {
    let route: LibraryRoute
    let item: ZoteroItemMetadata
}

private struct APILibrary: Decodable, Sendable {
    let type: String
    let id: Int
    let name: String

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case data
    }

    private struct Payload: Decodable {
        let id: Int
        let name: String
        let type: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.decodeIfPresent(Payload.self, forKey: .data)
        id =
            try container.decodeIfPresent(Int.self, forKey: .id)
            ?? payload?.id
            ?? {
                throw DecodingError.keyNotFound(
                    CodingKeys.id,
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "A Zotero group did not include its numeric identifier."
                    )
                )
            }()
        name =
            try container.decodeIfPresent(String.self, forKey: .name)
            ?? payload?.name
            ?? {
                throw DecodingError.keyNotFound(
                    CodingKeys.name,
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "A Zotero group did not include its name."
                    )
                )
            }()
        // Zotero 9's localhost groups route omits `type` because every
        // returned record is already a group. Older fixtures and API shapes
        // may retain it at either level.
        type =
            try container.decodeIfPresent(String.self, forKey: .type)
            ?? payload?.type
            ?? "group"
    }
}

struct AttachmentEnvelope: Decodable, Sendable {
    let key: String
    let data: AttachmentData

    struct AttachmentData: Decodable, Sendable {
        let key: String
        let parentItem: String?
        let itemType: String
        let title: String?
        let contentType: String?
        let linkMode: String?
        let filename: String?
        let path: String?
    }
}

enum ZoteroMCPRequestFactory {
    enum APIResource {
        case groups
        case collections(query: [URLQueryItem])
        case items(query: [URLQueryItem])
        case item(itemKey: String)
        case children(itemKey: String)
        case annotationChildren(itemKey: String)
        case fileURL(itemKey: String)
    }

    enum ConnectorEndpoint {
        case ping
        case selectedTarget
    }

    static func api(route: LibraryRoute, resource: APIResource) -> URLRequest? {
        let suffix: String
        let query: [URLQueryItem]
        switch resource {
        case .groups:
            guard route == .user else { return nil }
            suffix = "/groups"
            query = []
        case .collections(let items):
            suffix = "/collections"
            query = items
        case .items(let items):
            suffix = "/items"
            query = items
        case .item(let key):
            guard validKey(key) else { return nil }
            suffix = "/items/\(key)"
            query = [URLQueryItem(name: "format", value: "json")]
        case .children(let key):
            guard validKey(key) else { return nil }
            suffix = "/items/\(key)/children"
            query = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "limit", value: "50"),
            ]
        case .annotationChildren(let key):
            guard validKey(key) else { return nil }
            suffix = "/items/\(key)/children"
            query = [
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "itemType", value: "annotation"),
                URLQueryItem(name: "limit", value: "1001"),
            ]
        case .fileURL(let key):
            guard validKey(key) else { return nil }
            suffix = "/items/\(key)/file/view/url"
            query = []
        }
        guard query.allSatisfy({ allowedQueryNames.contains($0.name) }) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 23119
        components.path = route.apiPrefix + suffix
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .fileURL = resource { request.setValue("text/plain", forHTTPHeaderField: "Accept") }
        request.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        return request
    }

    static func connector(endpoint: ConnectorEndpoint) -> URLRequest? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 23119
        var method = "POST"
        var body = Data("{}".utf8)
        let contentType = "application/json"
        switch endpoint {
        case .ping:
            components.path = "/connector/ping"
            method = "GET"
            body = Data()
        case .selectedTarget:
            components.path = "/connector/getSelectedCollection"

        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body.isEmpty ? nil : body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("3", forHTTPHeaderField: "X-Zotero-Connector-API-Version")
        return request
    }

    private static let allowedQueryNames: Set<String> = [
        "format", "itemType", "q", "qmode", "limit",
    ]

    private static func validKey(_ key: String) -> Bool {
        ZoteroReference.normalizedKey(key) == key
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
