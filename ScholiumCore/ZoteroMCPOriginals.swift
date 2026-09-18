import Foundation
import ScholiumContracts
import UniformTypeIdentifiers

extension ZoteroMCPServer {
    func readOriginal(_ arguments: [String: ZoteroMCPJSONValue]) async throws -> ZoteroMCPJSONValue {
        guard Set(arguments.keys).isSubset(of: ["library", "attachment_key", "mode", "page", "start_utf8", "maximum_utf8", "expected_fingerprint"]),
            let mode = arguments["mode"]?.stringValue.flatMap(AgentAttachmentRead.Mode.init(rawValue:))
        else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let (route, key) = try materialScope(arguments)
        let start = try boundedInteger(arguments["start_utf8"], default: 0, range: 0...20 * 1_024 * 1_024)
        let maximum = try boundedInteger(arguments["maximum_utf8"], default: 16 * 1_024, range: 1...65_536)
        let expected = try expectedFingerprint(arguments["expected_fingerprint"])
        let page: Int?
        if let value = arguments["page"] {
            guard let number = value.intValue, number > 0 else { throw ZoteroMCPServiceError.invalidArguments }
            page = number
        } else {
            page = nil
        }
        guard start == 0 || expected != nil,
            mode != .image || (start == 0 && arguments["maximum_utf8"] == nil)
        else {
            throw ZoteroMCPServiceError.invalidArguments
        }
        let attachment = try await fileAttachment(key, route: route)
        let url = try await originalURL(key: key, route: route, attachment: attachment)
        let filename = url.lastPathComponent
        let type = try originalType(filename: filename, attachment: attachment)
        guard (type == .pdf) == (page != nil) else { throw ZoteroMCPServiceError.invalidArguments }
        guard type == .pdf || (mode == .text ? type.conforms(to: .text) : type.conforms(to: .image)) else {
            throw ZoteroMCPServiceError.originalUnavailable
        }

        let bytes = try await originalBytes(url)
        let fingerprint = DocumentFingerprint(data: bytes)
        if let expected, fingerprint.sha256 != expected { throw ZoteroMCPServiceError.materialChanged }
        try await revalidateAttachment(attachment, key: key, route: route)
        let currentURL = try await originalURL(key: key, route: route, attachment: attachment)
        guard currentURL == url else { throw ZoteroMCPServiceError.materialChanged }
        // Reuse the same bounded coordinated read to detect replacements during
        // the API revalidation; no independent file watcher or material cache.
        let currentFingerprint = DocumentFingerprint(data: try await originalBytes(url))
        guard currentFingerprint == fingerprint else { throw ZoteroMCPServiceError.materialChanged }
        try Task.checkCancellation()
        let request = AgentAttachmentRead(
            mode: mode, page: page, startUTF8: start, maximumUTF8: maximum,
            expectedFingerprint: expected == nil ? nil : fingerprint)
        let content: AgentAttachmentContent
        do {
            content = try AgentAttachmentContentReader.read(bytes, filename: filename, request: request)
        } catch let failure as ScholiumMCPFailure {
            throw ZoteroMCPServiceError.originalReadFailed(failure.message)
        } catch is AgentCollaborationError {
            throw ZoteroMCPServiceError.materialChanged
        }
        try Task.checkCancellation()
        var result: [String: ZoteroMCPJSONValue] = [
            "source_kind": .string("zotero_original"), "attachment_key": .string(key),
            "original_file_read": .bool(true), "original_fingerprint": .string(fingerprint.sha256),
            "original_byte_count": .integer(bytes.count), "filename": .string(filename),
            "reference": try referenceValue(route: route, itemKey: key, kind: type == .pdf ? .pdf : .item, page: page),
            "kind": .string(content.kind), "page": content.page.map(ZoteroMCPJSONValue.integer) ?? .null,
            "total_pages": content.totalPages.map(ZoteroMCPJSONValue.integer) ?? .null,
        ]
        if let parent = attachment.value.objectValue?["data"]?.objectValue?["parentItem"]?.stringValue {
            result["parent_reference"] = try referenceValue(route: route, itemKey: parent)
        }
        if let text = content.text {
            result["text"] = .string(text)
            result["text_available"] = .bool(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            result["start_utf8"] = .integer(content.startUTF8)
            result["end_utf8"] = .integer(content.endUTF8)
            result["total_utf8"] = .integer(content.totalUTF8)
            result["next_start_utf8"] = content.endUTF8 < content.totalUTF8 ? .integer(content.endUTF8) : .null
        }
        if let png = content.imagePNG {
            result["image"] = .object([
                "mime_type": .string("image/png"), "data": .string(png.base64EncodedString()),
                "pixel_width": content.pixelWidth.map(ZoteroMCPJSONValue.integer) ?? .null,
                "pixel_height": content.pixelHeight.map(ZoteroMCPJSONValue.integer) ?? .null,
            ])
        }
        return .object(result)
    }

    private func originalURL(key: String, route: LibraryRoute, attachment: AttachmentObservation) async throws -> URL {
        guard var request = ZoteroMCPRequestFactory.api(route: route, resource: .fileURL(itemKey: key)) else {
            throw ZoteroMCPServiceError.invalidRequest
        }
        if let serverID = attachment.response.header(named: "Zotero-Server-ID") {
            request.setValue(serverID, forHTTPHeaderField: "Zotero-Server-ID")
        }
        let response = try await sendAPI(request)
        try sameServer(attachment.response, response)
        guard response.body.count <= 16_384, let text = String(data: response.body, encoding: .utf8),
            text == text.trimmingCharacters(in: .whitespacesAndNewlines),
            let parts = URLComponents(string: text), parts.scheme == "file", parts.host?.isEmpty != false,
            parts.user == nil, parts.password == nil, parts.port == nil, parts.query == nil, parts.fragment == nil,
            let url = parts.url, url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0),
            url.path == url.standardizedFileURL.path,
            (try? AttachmentRelativePath(String(url.path.dropFirst()))) != nil
        else {
            throw ZoteroMCPServiceError.originalUnavailable
        }
        return url
    }

    private func originalType(filename: String, attachment: AttachmentObservation) throws -> UTType {
        guard let data = attachment.value.objectValue?["data"]?.objectValue,
            let contentType = data["contentType"]?.stringValue,
            let declaredType = UTType(mimeType: contentType),
            let type = UTType(filenameExtension: URL(fileURLWithPath: filename).pathExtension),
            type == .pdf || type.conforms(to: .text) || type.conforms(to: .image),
            (type == .pdf && declaredType == .pdf)
                || (type.conforms(to: .text) && declaredType.conforms(to: .text))
                || (type.conforms(to: .image) && declaredType.conforms(to: .image))
        else {
            throw ZoteroMCPServiceError.originalUnavailable
        }
        let namedFile: String?
        if data["linkMode"]?.stringValue == "linked_file" {
            namedFile = data["path"]?.stringValue.map { path in
                // Zotero resolves its current linked-attachment base directory.
                // This comparison never derives or opens a path from metadata.
                let relative = path.hasPrefix("attachments:") ? String(path.dropFirst("attachments:".count)) : path
                return URL(fileURLWithPath: relative).lastPathComponent
            }
        } else {
            namedFile = data["filename"]?.stringValue
        }
        guard namedFile == filename else { throw ZoteroMCPServiceError.originalUnavailable }
        return type
    }

    private func originalBytes(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        do {
            return try await VaultAttachmentStore(vaultURL: URL(fileURLWithPath: "/")).readContent(
                relativePath: AttachmentRelativePath(String(url.path.dropFirst())), maximumByteCount: 20 * 1_024 * 1_024)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ZoteroMCPServiceError.originalUnavailable
        }
    }

    static let originalReadTool = tool(
        name: "zotero_read_original",
        description:
            "Read an exact local attachment snapshot (at most 20 MiB): one physical PDF page, a bounded UTF-8 slice, or a bounded PNG. No arbitrary file path, index substitution, OCR or Zotero writes.",
        properties: [
            "library": .object(["type": .string("string"), "pattern": .string("^(user|group:[1-9][0-9]*)$")]),
            "attachment_key": .object(["type": .string("string"), "maxLength": .integer(128)]),
            "mode": .object(["type": .string("string"), "enum": .array([.string("text"), .string("image")])]),
            "page": .object([
                "type": .string("integer"), "minimum": .integer(1),
                "description": .string("Required one-based physical page for PDF; absent for text/image files."),
            ]),
            "start_utf8": .object(["type": .string("integer"), "minimum": .integer(0), "maximum": .integer(20 * 1_024 * 1_024), "default": .integer(0)]),
            "maximum_utf8": .object([
                "type": .string("integer"), "minimum": .integer(1), "maximum": .integer(65_536), "default": .integer(16_384),
                "description": .string("Text mode only."),
            ]),
            "expected_fingerprint": .object([
                "type": .string("string"), "pattern": .string("^[0-9a-f]{64}$"),
                "description": .string("Original file fingerprint; required for nonzero text offsets."),
            ]),
        ], required: ["library", "attachment_key", "mode"])
}
