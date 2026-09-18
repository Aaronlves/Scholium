import CryptoKit
import Foundation
import ScholiumContracts

extension ZoteroMCPServer {
    func referenceValue(
        route: LibraryRoute, itemKey: String, kind: ZoteroReference.Kind = .item,
        page: Int? = nil, annotationKey: String? = nil
    ) throws -> ZoteroMCPJSONValue {
        let library: ZoteroLibraryIdentity = route.groupID.map(ZoteroLibraryIdentity.group) ?? .user
        let reference = try ZoteroReference(
            library: library, kind: kind, itemKey: itemKey,
            page: page, annotationKey: annotationKey)
        return .object([
            "library": route.value, "kind": .string(reference.kind.rawValue),
            "item_key": .string(reference.itemKey),
            "page": reference.page.map(ZoteroMCPJSONValue.integer) ?? .null,
            "annotation_key": reference.annotationKey.map(ZoteroMCPJSONValue.string) ?? .null,
            "url": .string(reference.url.absoluteString),
        ])
    }

    func listAnnotations(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard Set(arguments.keys).isSubset(of: ["library", "attachment_key", "offset", "limit", "expected_listing_fingerprint"]) else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let (route, attachmentKey) = try materialScope(arguments)
        let offset = try boundedInteger(arguments["offset"], default: 0, range: 0...1_000)
        let limit = try boundedInteger(arguments["limit"], default: 25, range: 1...50)
        let expected = try expectedFingerprint(arguments["expected_listing_fingerprint"])
        guard offset == 0 || expected != nil else { throw ZoteroMCPServiceError.invalidArguments }

        let attachment = try await pdfAttachment(attachmentKey, route: route)
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .annotationChildren(itemKey: attachmentKey)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        let decoded = try JSONDecoder().decode(ZoteroMCPJSONValue.self, from: response.body)
        guard let records = decoded.arrayValue else { throw ZoteroMCPServiceError.invalidResponse }
        guard records.count <= 1_000 else { throw ZoteroMCPServiceError.responseTooLarge }
        if let total = response.header(named: "Total-Results") {
            guard let count = Int(total), count == records.count else { throw ZoteroMCPServiceError.responseTooLarge }
        }
        try sameServer(attachment.response, response)
        let annotations = try records.map { try AnnotationRecord($0, attachmentKey: attachmentKey) }.sorted { $0.key < $1.key }
        guard Set(annotations.map(\.key)).count == annotations.count else { throw ZoteroMCPServiceError.invalidResponse }
        let fingerprint = try materialFingerprint(
            .object([
                "attachment": attachment.value,
                "annotations": .array(annotations.map(\.raw)),
            ]), route: route, response: response)
        if let expected, expected != fingerprint { throw ZoteroMCPServiceError.materialChanged }
        guard offset <= annotations.count else { throw ZoteroMCPServiceError.invalidArguments }
        let end = min(annotations.count, offset + limit)
        let pointers = try annotations[offset..<end].map { record in
            try annotationValue(record, route: route, response: response, includeContent: false)
        }
        try await revalidateAttachment(attachment, key: attachmentKey, route: route)
        try Task.checkCancellation()
        return .object([
            "attachment_reference": try referenceValue(route: route, itemKey: attachmentKey, kind: .pdf),
            "listing_fingerprint": .string(fingerprint), "offset": .integer(offset),
            "total_count": .integer(annotations.count), "annotations": .array(pointers),
            "next_offset": end < annotations.count ? .integer(end) : .null,
        ])
    }

    func readAnnotation(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard Set(arguments.keys).isSubset(of: ["library", "attachment_key", "annotation_key", "expected_fingerprint"]),
            let value = arguments["annotation_key"]?.stringValue,
            let key = ZoteroReference.normalizedKey(value)
        else { throw ZoteroMCPServiceError.invalidArguments }
        let (route, attachmentKey) = try materialScope(arguments)
        let expected = try expectedFingerprint(arguments["expected_fingerprint"])
        let attachment = try await pdfAttachment(attachmentKey, route: route)
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .item(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        try sameServer(attachment.response, response)
        let record = try AnnotationRecord(JSONDecoder().decode(ZoteroMCPJSONValue.self, from: response.body), attachmentKey: attachmentKey)
        guard record.key == key else { throw ZoteroMCPServiceError.invalidResponse }
        let result = try annotationValue(record, route: route, response: response, includeContent: true)
        if let expected, result.objectValue?["annotation_fingerprint"]?.stringValue != expected {
            throw ZoteroMCPServiceError.materialChanged
        }
        try await revalidateAttachment(attachment, key: attachmentKey, route: route)
        try Task.checkCancellation()
        return result
    }

    func materialScope(_ arguments: [String: ZoteroMCPJSONValue]) throws -> (LibraryRoute, String) {
        guard let selector = arguments["library"]?.stringValue,
            let value = arguments["attachment_key"]?.stringValue,
            let key = ZoteroReference.normalizedKey(value)
        else { throw ZoteroMCPServiceError.invalidArguments }
        if selector == "user" { return (.user, key) }
        guard selector.hasPrefix("group:"), let id = Int(selector.dropFirst(6)), id > 0,
            selector == "group:\(id)"
        else { throw ZoteroMCPServiceError.invalidArguments }
        return (.group(id: id, name: ""), key)
    }

    func boundedInteger(_ value: ZoteroMCPJSONValue?, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value else { return fallback }
        guard let number = value.intValue, range.contains(number) else { throw ZoteroMCPServiceError.invalidArguments }
        return number
    }

    func expectedFingerprint(_ value: ZoteroMCPJSONValue?) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue, text.utf8.count == 64,
            text.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        return text
    }

    struct AttachmentObservation {
        let value: ZoteroMCPJSONValue
        let response: ZoteroMCPHTTPResponse
    }

    private func pdfAttachment(_ key: String, route: LibraryRoute) async throws -> AttachmentObservation {
        let observation = try await fileAttachment(key, route: route)
        guard observation.value.objectValue?["data"]?.objectValue?["contentType"]?.stringValue == "application/pdf" else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        return observation
    }

    func fileAttachment(_ key: String, route: LibraryRoute) async throws -> AttachmentObservation {
        guard let request = ZoteroMCPRequestFactory.api(route: route, resource: .item(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        let response = try await sendAPI(request)
        let value = try JSONDecoder().decode(ZoteroMCPJSONValue.self, from: response.body)
        guard let object = value.objectValue, object["key"]?.stringValue == key,
            let data = object["data"]?.objectValue,
            data["key"]?.stringValue == key, data["itemType"]?.stringValue == "attachment",
            ["imported_file", "imported_url", "linked_file"].contains(data["linkMode"]?.stringValue ?? "")
        else {
            throw ZoteroMCPServiceError.invalidResponse
        }
        return AttachmentObservation(value: value, response: response)
    }

    func revalidateAttachment(_ initial: AttachmentObservation, key: String, route: LibraryRoute) async throws {
        let current = try await fileAttachment(key, route: route)
        try sameServer(initial.response, current.response)
        guard initial.value == current.value else { throw ZoteroMCPServiceError.materialChanged }
    }

    func sameServer(_ first: ZoteroMCPHTTPResponse, _ second: ZoteroMCPHTTPResponse) throws {
        guard first.header(named: "Zotero-Server-ID") == second.header(named: "Zotero-Server-ID") else {
            throw ZoteroMCPServiceError.materialChanged
        }
    }

    private func materialFingerprint(_ value: ZoteroMCPJSONValue, route: LibraryRoute, response: ZoteroMCPHTTPResponse) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(
            ZoteroMCPJSONValue.object([
                "library": .string(route.identity), "server_id": response.header(named: "Zotero-Server-ID").map(ZoteroMCPJSONValue.string) ?? .null,
                "records": value,
            ]))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func annotationValue(
        _ record: AnnotationRecord, route: LibraryRoute, response: ZoteroMCPHTTPResponse,
        includeContent: Bool
    ) throws -> ZoteroMCPJSONValue {
        var value: [String: ZoteroMCPJSONValue] = [
            "source_kind": .string("zotero_annotation"), "annotation_key": .string(record.key),
            "attachment_key": .string(record.attachmentKey),
            "annotation_type": record.data["annotationType"] ?? .null,
            "page_label": record.data["annotationPageLabel"] ?? .null,
            "annotation_fingerprint": .string(try materialFingerprint(record.raw, route: route, response: response)),
            "reference": try referenceValue(
                route: route, itemKey: record.attachmentKey, kind: .pdf,
                page: record.page, annotationKey: record.key),
        ]
        if includeContent {
            value["selected_text"] = record.data["annotationText"] ?? .null
            value["comment"] = record.data["annotationComment"] ?? .null
            value["selected_text_utf8_count"] = record.data["annotationText"]?.stringValue.map { .integer($0.utf8.count) } ?? .null
            value["comment_utf8_count"] = record.data["annotationComment"]?.stringValue.map { .integer($0.utf8.count) } ?? .null
            value["position"] = record.data["annotationPosition"] ?? .null
            value["original_file_read"] = .bool(false)
        }
        return .object(value)
    }

    static let annotationListTool = tool(
        name: "zotero_list_annotations",
        description:
            "List bounded annotation locators for one exact PDF attachment; no selected text or comments. Continuation requires the listing fingerprint.",
        properties: annotationScopeProperties.merging(
            [
                "offset": .object(["type": .string("integer"), "minimum": .integer(0), "maximum": .integer(1_000), "default": .integer(0)]),
                "limit": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(50), "default": .integer(25)]),
                "expected_listing_fingerprint": fingerprintSchema,
            ], uniquingKeysWith: { _, new in new }), required: ["library", "attachment_key"])

    static let annotationReadTool = tool(
        name: "zotero_read_annotation",
        description: "Read one exact annotation, keeping selected text, comment, printed label and physical page separate. Does not read or verify PDF bytes.",
        properties: annotationScopeProperties.merging(
            [
                "annotation_key": .object(["type": .string("string"), "maxLength": .integer(128)]),
                "expected_fingerprint": fingerprintSchema,
            ], uniquingKeysWith: { _, new in new }), required: ["library", "attachment_key", "annotation_key"])

    private static let annotationScopeProperties: [String: ZoteroMCPJSONValue] = [
        "library": .object(["type": .string("string"), "pattern": .string("^(user|group:[1-9][0-9]*)$")]),
        "attachment_key": .object(["type": .string("string"), "maxLength": .integer(128)]),
    ]
    private static let fingerprintSchema: ZoteroMCPJSONValue = .object(["type": .string("string"), "pattern": .string("^[0-9a-f]{64}$")])
}

private struct AnnotationRecord {
    let key: String
    let attachmentKey: String
    let raw: ZoteroMCPJSONValue
    let data: [String: ZoteroMCPJSONValue]

    init(_ raw: ZoteroMCPJSONValue, attachmentKey: String) throws {
        guard let object = raw.objectValue, let key = object["key"]?.stringValue,
            ZoteroReference.normalizedKey(key) == key,
            let data = object["data"]?.objectValue, data["key"]?.stringValue == key,
            data["itemType"]?.stringValue == "annotation", data["parentItem"]?.stringValue == attachmentKey,
            ["annotationType", "annotationText", "annotationComment", "annotationPosition", "annotationPageLabel"].allSatisfy({
                data[$0] == nil || data[$0] == .null || data[$0]?.stringValue != nil
            })
        else { throw ZoteroMCPServiceError.invalidResponse }
        self.key = key
        self.attachmentKey = attachmentKey
        self.raw = raw
        self.data = data
    }

    var page: Int? {
        guard let position = data["annotationPosition"]?.stringValue,
            let decoded = try? JSONDecoder().decode(ZoteroMCPJSONValue.self, from: Data(position.utf8)),
            let index = decoded.objectValue?["pageIndex"]?.intValue, index >= 0, index < Int.max
        else { return nil }
        return index + 1
    }
}
