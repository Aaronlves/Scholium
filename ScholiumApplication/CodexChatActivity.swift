import Foundation
import ScholiumContracts

/// Public runtime item projection. Localized presentation belongs to the client.
public enum CodexChatActivity {
    public static func parse(
        _ item: [String: MCPJSONValue], completed: Bool, threadID: String? = nil,
        includesManagedTools: Bool = false
    ) -> AgentChatActivity? {
        let type = item["type"]?.stringValue ?? ""
        if ["collabAgentToolCall", "subAgentActivity"].contains(type) {
            var activity = AgentChatActivity(kind: .delegation, status: .uncertain, source: .runtime)
            guard let threadID, let report = try? CodexChatDelegation.parse(item, senderThreadID: threadID) else {
                return activity
            }
            activity.delegation = report
            switch item["status"]?.stringValue {
            case "failed": activity.status = .failed
            case "interrupted": activity.status = .interrupted
            case "inProgress": activity.status = completed ? .uncertain : .running
            default: activity.status = completed ? .completed : .running
            }
            return activity
        }
        let managedTool =
            type == "mcpToolCall" && item["server"]?.stringValue == "scholium"
            ? ScholiumMCPToolName(rawValue: item["tool"]?.stringValue ?? "") : nil
        // The parent App bridge records these exact calls, including approval and receipt.
        // Child inspection keeps the runtime invocation without manufacturing that receipt.
        if !includesManagedTools, managedTool != nil { return nil }
        let kind: AgentChatActivity.Kind
        switch type {
        case "mcpToolCall": kind = managedTool.map(AgentChatActivity.Kind.forTool) ?? .tool
        case "commandExecution": kind = .command
        case "fileChange": kind = .files
        case "webSearch": kind = .webSearch
        case "contextCompaction": kind = .compaction
        default: return nil
        }
        var status: AgentChatActivity.Status = completed ? .completed : .running
        switch item["status"]?.stringValue {
        case "failed": status = .failed
        case "declined": status = .declined
        case "inProgress": status = completed ? .uncertain : .running
        default: break
        }
        if item["error"]?.objectValue != nil { status = .failed }
        if completed, let exitCode = item["exitCode"]?.intValue, exitCode != 0 { status = .failed }
        var subject =
            item["tool"]?.stringValue ?? item["command"]?.stringValue
            ?? item["query"]?.stringValue ?? ""
        var detail =
            item["error"]?.objectValue?["message"]?.stringValue
            ?? item["aggregatedOutput"]?.stringValue ?? ""
        if type == "mcpToolCall", let result = item["result"]?.objectValue {
            if result["isError"]?.boolValue == true { status = .failed }
            if item["server"]?.stringValue == "scholium-zotero",
                item["tool"]?.stringValue == "zotero_update_item",
                let outcome = result["structuredContent"]?.objectValue,
                outcome["status"] == .string("outcome_uncertain"),
                outcome["error_code"] == .string("write_outcome_uncertain")
            {
                status = .uncertain
            }
            // Retention keeps the latest output; keep the runtime diagnostic at
            // that ending so a large result cannot erase the failure reason.
            detail = [mcpOutput(result), detail].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        if let managedTool {
            subject = item["arguments"]?.objectValue?["relative_path"]?.stringValue ?? ""
            detail = [managedTool.rawValue, detail].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        let files: [AgentChatActivity.File] = (item["changes"]?.arrayValue ?? []).compactMap { value in
            guard let file = value.objectValue, let path = file["path"]?.stringValue else { return nil }
            let effect: AgentChatActivity.File.Effect
            switch file["kind"]?.objectValue?["type"]?.stringValue {
            case "add": effect = .created
            case "delete": effect = .trashed
            default: effect = .edited
            }
            if let diff = file["diff"]?.stringValue { detail += "\n" + path + "\n" + diff }
            return .init(path: path, effect: status == .completed ? effect : nil)
        }
        var activity = AgentChatActivity(
            kind: kind, status: status, source: .runtime, subject: subject,
            detail: String(detail.suffix(16_000)), files: files)
        if detail.count > 16_000 { activity.outputTruncated = true }
        if kind == .command {
            activity.commandExecution = .init(
                workingDirectory: item["cwd"]?.stringValue,
                exitCode: item["exitCode"]?.intValue,
                durationMilliseconds: item["durationMs"]?.intValue.flatMap { $0 >= 0 ? $0 : nil })
        }
        if kind == .command, let actions = item["commandActions"]?.arrayValue, actions.count == 1,
            let action = actions.first?.objectValue,
            let raw = action["type"]?.stringValue, let kind = AgentChatActivity.CommandAction.Kind(rawValue: raw)
        {
            let target = (kind == .search ? action["query"]?.stringValue : action["path"]?.stringValue) ?? ""
            if target.utf8.count <= 8_192 { activity.commandAction = .init(kind: kind, target: target) }
        }
        if kind == .webSearch, completed, status == .completed,
            let action = item["action"]?.objectValue,
            let raw = action["type"]?.stringValue,
            let operation = AgentChatSourceObservation.WebAccess.Action(rawValue: raw),
            let destination = action["url"]?.stringValue, destination.utf8.count <= 8_192,
            let url = URL(string: destination), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            url.host != nil, url.user == nil, url.password == nil
        {
            activity.sourceObservation = .webAccess(.init(action: operation, url: url))
            activity.subject = destination
        }
        return activity
    }

    /// Public MCP output has its own result envelope; command aggregates are
    /// unrelated. Keep diagnostics and source coverage, without retaining binary
    /// derivatives or provider-private metadata in the transcript.
    private static func mcpOutput(_ result: [String: MCPJSONValue]) -> String {
        let structured = result["structuredContent"].flatMap { $0 == .null ? nil : publicMCPValue($0) }
        var parts: [String] = []
        var includesStructured = false
        for block in result["content"]?.arrayValue ?? [] {
            guard let content = block.objectValue else { continue }
            switch content["type"]?.stringValue {
            case "text":
                guard let text = content["text"]?.stringValue else { continue }
                if let json = try? JSONDecoder().decode(MCPJSONValue.self, from: Data(text.utf8)) {
                    let value = publicMCPValue(json)
                    includesStructured = includesStructured || value == structured
                    parts.append(value == json ? text : jsonText(value))
                } else {
                    parts.append(text)
                }
            case "image", "audio":
                let kind = content["type"]?.stringValue ?? ""
                parts.append("[\(content["mimeType"]?.stringValue ?? kind) \(kind)]")
            case "resource":
                if let resource = content["resource"]?.objectValue {
                    if let text = resource["text"]?.stringValue { parts.append(text) } else if let uri = resource["uri"]?.stringValue { parts.append(uri) }
                }
            case "resource_link":
                if let uri = content["uri"]?.stringValue { parts.append(uri) }
            default: break
            }
        }
        if let structured, !includesStructured { parts.append(jsonText(structured)) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func publicMCPValue(_ value: MCPJSONValue) -> MCPJSONValue {
        switch value {
        case .object(var object):
            object["_meta"] = nil
            if object["mime_type"]?.stringValue != nil || object["mimeType"]?.stringValue != nil
                || ["image", "audio"].contains(object["type"]?.stringValue ?? "")
            {
                object["data"] = nil
                object["blob"] = nil
            }
            return .object(object.mapValues(publicMCPValue))
        case .array(let values): return .array(values.map(publicMCPValue))
        default: return value
        }
    }

    private static func jsonText(_ value: MCPJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
