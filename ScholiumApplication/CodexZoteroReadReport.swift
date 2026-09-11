import Foundation
import ImageIO
import ScholiumContracts

/// Decodes public tool reports, not first-party authorization or verified filesystem receipts.
enum CodexZoteroReadReport {
    static func failureMessage(_ item: [String: MCPJSONValue]) -> String? {
        guard item["type"]?.stringValue == "mcpToolCall",
            ["zotero_read_original", "zotero_read_annotation"].contains(item["tool"]?.stringValue ?? ""),
            let value = item["result"]?.objectValue?["structuredContent"]?.objectValue,
            value["status"]?.stringValue == "failed", let message = value["error"]?.stringValue,
            !message.isEmpty, message.utf8.count <= 8_192
        else { return nil }
        return message
    }

    static func parse(_ item: [String: MCPJSONValue]) -> ZoteroReadReport? {
        guard item["type"]?.stringValue == "mcpToolCall", item["status"]?.stringValue == "completed",
            item["error"] == nil || item["error"] == .null,
            let server = item["server"]?.stringValue, let tool = item["tool"]?.stringValue,
            ["zotero_read_original", "zotero_read_annotation"].contains(tool),
            let args = item["arguments"]?.objectValue, let result = item["result"]?.objectValue,
            result["isError"] == nil || result["isError"] == .bool(false),
            let value = result["structuredContent"]?.objectValue,
            let locator = value["reference"]?.objectValue,
            let rawURL = locator["url"]?.stringValue, rawURL.utf8.count <= 1_024,
            let url = URL(string: rawURL), let reference = try? ZoteroReference(url: url),
            let library = locator["library"]?.objectValue,
            library["type"]?.stringValue == (reference.library == .user ? "user" : "group"),
            integer(library["id"]) == libraryID(reference.library),
            locator["kind"]?.stringValue == reference.kind.rawValue,
            locator["item_key"]?.stringValue == reference.itemKey,
            let locatorPage = optionalInteger(locator["page"]), locatorPage == reference.page,
            let locatorAnnotation = optionalText(locator["annotation_key"]), locatorAnnotation == reference.annotationKey,
            args["library"]?.stringValue == selector(reference.library),
            args["attachment_key"]?.stringValue.flatMap(ZoteroReference.normalizedKey) == reference.itemKey,
            value["attachment_key"]?.stringValue == reference.itemKey
        else { return nil }

        let report: ZoteroReadReport
        if tool == "zotero_read_annotation" {
            guard Set(args.keys).isSubset(of: ["library", "attachment_key", "annotation_key", "expected_fingerprint"]),
                value["source_kind"]?.stringValue == "zotero_annotation", value["original_file_read"] == .bool(false),
                value["annotation_key"]?.stringValue == reference.annotationKey,
                args["annotation_key"]?.stringValue.flatMap(ZoteroReference.normalizedKey) == reference.annotationKey,
                let fingerprint = value["annotation_fingerprint"]?.stringValue,
                expected(args["expected_fingerprint"], matches: fingerprint),
                let text = optionalText(value["selected_text"]), let comment = optionalText(value["comment"]),
                let textCount = optionalInteger(value["selected_text_utf8_count"]), textCount == text?.utf8.count,
                let commentCount = optionalInteger(value["comment_utf8_count"]), commentCount == comment?.utf8.count,
                annotationPage(value["position"]) == reference.page,
                let label = optionalText(value["page_label"]), (label?.utf8.count ?? 0) <= 256
            else { return nil }
            let excerpt = prefix(text ?? "")
            let commentExcerpt = comment.map(prefix)
            report = .init(
                server: server, tool: tool, reference: reference, representation: .annotation, fingerprint: fingerprint,
                excerpt: excerpt, excerptIsTruncated: excerpt.utf8.count < (text?.utf8.count ?? 0),
                comment: commentExcerpt, commentIsTruncated: (commentExcerpt?.utf8.count ?? 0) < (comment?.utf8.count ?? 0), pageLabel: label)
        } else {
            guard Set(args.keys).isSubset(of: ["library", "attachment_key", "mode", "page", "start_utf8", "maximum_utf8", "expected_fingerprint"]),
                value["source_kind"]?.stringValue == "zotero_original", value["original_file_read"] == .bool(true),
                let fingerprint = value["original_fingerprint"]?.stringValue,
                expected(args["expected_fingerprint"], matches: fingerprint),
                let count = integer(value["original_byte_count"]), (0...20 * 1_024 * 1_024).contains(count),
                let kind = value["kind"]?.stringValue.flatMap(ZoteroReadReport.Representation.init(rawValue:)), kind != .annotation,
                let requestedPage = optionalInteger(args["page"], allowsNull: false), requestedPage == reference.page,
                let returnedPage = optionalInteger(value["page"]), returnedPage == reference.page,
                let requestedStart = optionalInteger(args["start_utf8"], allowsNull: false),
                let requestedMaximum = optionalInteger(args["maximum_utf8"], allowsNull: false),
                (1...65_536).contains(requestedMaximum ?? 16_384)
            else { return nil }
            if let page = reference.page {
                guard let totalPages = integer(value["total_pages"]), totalPages >= page else { return nil }
            }
            if kind == .text || kind == .pdfText {
                guard args["mode"]?.stringValue == "text", let text = value["text"]?.stringValue,
                    let start = integer(value["start_utf8"]), let end = integer(value["end_utf8"]), let total = integer(value["total_utf8"]),
                    start >= 0, end >= start, end <= total, total <= 20 * 1_024 * 1_024,
                    end - start == text.utf8.count, text.utf8.count <= 65_536,
                    (requestedStart ?? 0) == start,
                    start == 0 || args["expected_fingerprint"]?.stringValue == fingerprint,
                    text.utf8.count <= (requestedMaximum ?? 16_384),
                    value["text_available"]?.boolValue == !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    (end < total && integer(value["next_start_utf8"]) == end) || (end == total && value["next_start_utf8"] == .null)
                else { return nil }
                let excerpt = prefix(text)
                if kind == .text {
                    guard total == count else { return nil }
                    if start == 0, end == total, DocumentFingerprint(content: text).sha256 != fingerprint { return nil }
                }
                report = .init(
                    server: server, tool: tool, reference: reference, representation: kind, fingerprint: fingerprint,
                    range: .init(start: start, end: end, total: total), excerpt: excerpt, excerptIsTruncated: excerpt.utf8.count < text.utf8.count)
            } else {
                guard args["mode"]?.stringValue == "image", (requestedStart ?? 0) == 0, requestedMaximum == nil,
                    let image = value["image"]?.objectValue,
                    image["mime_type"]?.stringValue == "image/png", let encoded = image["data"]?.stringValue,
                    encoded.utf8.count <= 700_000, let bytes = Data(base64Encoded: encoded), bytes.count <= 512 * 1_024,
                    bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                    let width = integer(image["pixel_width"]), (1...1_024).contains(width),
                    let height = integer(image["pixel_height"]), (1...1_024).contains(height),
                    let source = CGImageSourceCreateWithData(bytes as CFData, nil), CGImageSourceGetCount(source) == 1,
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                    (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == width,
                    (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == height,
                    CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
                else { return nil }
                report = .init(server: server, tool: tool, reference: reference, representation: kind, fingerprint: fingerprint)
            }
        }
        return report.isValid ? report : nil
    }

    private static func integer(_ value: MCPJSONValue?) -> Int? {
        value?.intValue
    }
    private static func annotationPage(_ value: MCPJSONValue?) -> Int? {
        guard let text = value?.stringValue, text.utf8.count <= 65_536,
            let position = try? JSONDecoder().decode(MCPJSONValue.self, from: Data(text.utf8)),
            let index = integer(position.objectValue?["pageIndex"]), index >= 0, index < Int.max
        else { return nil }
        return index + 1
    }
    private static func optionalInteger(_ value: MCPJSONValue?, allowsNull: Bool = true) -> Int?? {
        if value == nil || (allowsNull && value == .null) { return .some(nil) }
        guard let number = integer(value) else { return nil }
        return .some(number)
    }
    private static func expected(_ value: MCPJSONValue?, matches fingerprint: String) -> Bool {
        value == nil || value?.stringValue == fingerprint
    }
    /// Double optional distinguishes absent/null text from an invalid field type.
    private static func optionalText(_ value: MCPJSONValue?) -> String?? {
        if value == nil || value == .null { return .some(nil) }
        guard let text = value?.stringValue, text.utf8.count <= 4 * 1_024 * 1_024 else { return nil }
        return .some(text)
    }
    private static func prefix(_ value: String) -> String {
        var bytes = Array(value.utf8.prefix(1_600))
        while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
    private static func libraryID(_ value: ZoteroLibraryIdentity) -> Int {
        switch value {
        case .user: 0
        case .group(let id): id
        }
    }
    private static func selector(_ value: ZoteroLibraryIdentity) -> String {
        switch value {
        case .user: "user"
        case .group(let id): "group:\(id)"
        }
    }
}
