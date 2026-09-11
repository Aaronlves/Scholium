import CoreGraphics
import Foundation
import ImageIO
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Public Zotero material reports")
struct CodexZoteroReadReportTests {
    @Test("Live and restored reports retain bounded material and the actual reporting server")
    func reportHistoryParity() throws {
        let text = String(repeating: "原文 😀\r\n", count: 300)
        let item = original(text: text, server: "custom-zotero")
        let activity = try #require(CodexChatActivity.parse(item, completed: true))
        guard case .zoteroReadReport(let report) = activity.sourceObservation else {
            Issue.record("Missing report")
            return
        }
        #expect(activity.source == .runtime && report.server == "custom-zotero")
        #expect(report.excerpt.utf8.count <= 1_600 && report.excerptIsTruncated)
        #expect(text.hasPrefix(report.excerpt) && report.range?.total == text.utf8.count)
        #expect(try JSONDecoder().decode(AgentChatActivity.self, from: JSONEncoder().encode(activity)) == activity)
        let event = try #require(
            try CodexChatTranscript.event([
                "method": .string("item/completed"),
                "params": .object(["threadId": .string("thread"), "turnId": .string("turn"), "item": .object(item)]),
            ]))
        let turn: MCPJSONValue = .object(["id": .string("turn"), "status": .string("completed"), "items": .array([.object(item)])])
        let thread: MCPJSONValue = .object(["id": .string("thread"), "turns": .array([turn])])
        let history = try CodexChatTranscript.history(.object(["thread": thread]), threadID: "thread")
        guard case .item(let live, _, _) = event.content else {
            Issue.record("Missing live item")
            return
        }
        #expect(live == history.first?.items.first)
        guard case .activity(let restored) = live.content else {
            Issue.record("Missing restored report")
            return
        }
        #expect(restored.sourceObservation == activity.sourceObservation)
    }

    @Test("Failed, truncated, inconsistent and malformed reports cannot claim observed material")
    func invalidReports() {
        let good = original(text: "Complete source")
        var failures: [[String: MCPJSONValue]] = []
        var pending = good
        pending["status"] = .string("inProgress")
        failures.append(pending)
        var failed = good
        failed["error"] = .object(["message": .string("failed")])
        failures.append(failed)
        var tool = good
        tool["tool"] = .string("other_tool")
        failures.append(tool)
        var absent = good
        absent["result"] = .null
        failures.append(absent)
        var args = good
        var wrong = args["arguments"]!.objectValue!
        wrong["library"] = .string("group:42")
        args["arguments"] = .object(wrong)
        failures.append(args)
        for patch: [String: MCPJSONValue] in [
            ["text": .string("Truncated")], ["end_utf8": .integer(-1)], ["total_utf8": .double(1e100)],
            ["original_fingerprint": .string(String(repeating: "0", count: 64))],
            ["source_kind": .string("zotero_annotation")], ["original_file_read": .bool(false)],
            ["attachment_key": .string("OTHER001")], ["page": .string("malformed")], ["next_start_utf8": .integer(0)],
        ] {
            var copy = good
            var result = copy["result"]!.objectValue!
            var value = result["structuredContent"]!.objectValue!
            value.merge(patch, uniquingKeysWith: { _, new in new })
            result["structuredContent"] = .object(value)
            copy["result"] = .object(result)
            failures.append(copy)
        }
        for item in failures { #expect(CodexChatActivity.parse(item, completed: true)?.sourceObservation == nil) }
        #expect(CodexChatActivity.parse(good, completed: false)?.sourceObservation == nil)
        var semanticFailure = good
        semanticFailure["result"] = .object([
            "content": .array([]),
            "structuredContent": .object([
                "status": .string("failed"), "error": .string("The selected material changed."),
            ]),
        ])
        let outcome = CodexChatActivity.parse(semanticFailure, completed: true)
        #expect(outcome?.status == .failed && outcome?.sourceObservation == nil)
        #expect(outcome?.detail == "The selected material changed.")
    }

    @Test("Image reports validate bounded returned PNGs without retaining their payload")
    func imageReports() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        let encoded = (data as Data).base64EncodedString()
        var item = original(text: "Source")
        item["arguments"] = .object(["library": .string("user"), "attachment_key": .string("ATTACH01"), "mode": .string("image")])
        var result = item["result"]!.objectValue!
        var value = result["structuredContent"]!.objectValue!
        value["kind"] = .string("image")
        value["image"] = .object(["mime_type": .string("image/png"), "data": .string(encoded), "pixel_width": .integer(2), "pixel_height": .integer(2)])
        result["structuredContent"] = .object(value)
        item["result"] = .object(result)
        let activity = try #require(CodexChatActivity.parse(item, completed: true))
        guard case .zoteroReadReport(let report) = activity.sourceObservation else {
            Issue.record("Missing image report")
            return
        }
        #expect(report.representation == .image && report.range == nil && report.excerpt.isEmpty)
        let retained = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(retained.contains(encoded) == false)
        value["image"] = .object(["mime_type": .string("image/png"), "data": .string("iVBORw0KGgo="), "pixel_width": .integer(2), "pixel_height": .integer(2)])
        result["structuredContent"] = .object(value)
        item["result"] = .object(result)
        #expect(CodexChatActivity.parse(item, completed: true)?.sourceObservation == nil)
    }

    @Test("A complete original's BOM and source version survive public result decoding")
    func exactReportBytes() throws {
        let text = "\u{FEFF}原文\r\n"
        let item = original(text: text)
        let decoded = try JSONDecoder().decode([String: MCPJSONValue].self, from: JSONEncoder().encode(item))
        let activity = try #require(CodexChatActivity.parse(decoded, completed: true))
        guard case .zoteroReadReport(let report) = activity.sourceObservation else {
            Issue.record("Missing exact report")
            return
        }
        #expect(Data(report.excerpt.utf8) == Data(text.utf8))
        #expect(report.fingerprint == DocumentFingerprint(content: text).sha256)
    }

    private func original(text: String, server: String = "scholium-zotero") -> [String: MCPJSONValue] {
        let fingerprint = DocumentFingerprint(content: text)
        let reference: MCPJSONValue = .object([
            "library": .object(["type": .string("user"), "id": .integer(0)]), "kind": .string("item"),
            "item_key": .string("ATTACH01"), "page": .null, "annotation_key": .null,
            "url": .string("zotero://select/library/items/ATTACH01"),
        ])
        let value: MCPJSONValue = .object([
            "source_kind": .string("zotero_original"), "original_file_read": .bool(true),
            "original_fingerprint": .string(fingerprint.sha256), "original_byte_count": .integer(fingerprint.byteCount),
            "attachment_key": .string("ATTACH01"), "kind": .string("utf8_text"), "reference": reference, "page": .null,
            "text": .string(text), "text_available": .bool(!text.isEmpty), "start_utf8": .integer(0), "end_utf8": .integer(text.utf8.count),
            "total_utf8": .integer(text.utf8.count), "next_start_utf8": .null,
        ])
        return [
            "id": .string("call"), "type": .string("mcpToolCall"), "server": .string(server), "tool": .string("zotero_read_original"),
            "status": .string("completed"), "arguments": .object(["library": .string("user"), "attachment_key": .string("ATTACH01"), "mode": .string("text")]),
            "result": .object(["content": .array([]), "structuredContent": value]),
        ]
    }
}
