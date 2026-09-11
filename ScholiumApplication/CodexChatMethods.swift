import Foundation
import ScholiumContracts

extension CodexAppServer {
    public func chatToolSignIn(name: String, threadID: String?) async throws -> URL {
        var params: [String: MCPJSONValue] = ["name": .string(name), "timeoutSecs": .integer(300)]
        if let threadID { params["threadId"] = .string(threadID) }
        return try CodexChatMethods.authorizationURL(await request("mcpServer/oauth/login", params: params))
    }
    public func setChatMethodFolders(_ folders: [String]) async throws {
        guard folders.allSatisfy({ $0.hasPrefix("/") }) else { throw CodexConnectionError.invalidMessage }
        let paths = try folders.map { try AgentChatMethodFolders.directory(URL(fileURLWithPath: $0)).path }
        guard Set(paths).count == paths.count else { throw CodexConnectionError.invalidMessage }
        _ = try await request("skills/extraRoots/set", params: ["extraRoots": .array(paths.map(MCPJSONValue.string))])
    }

    public func chatMethods(cwd: URL) async throws -> AgentChatMethodInventory {
        try CodexChatMethods.methods(
            await request(
                "skills/list",
                params: [
                    "cwds": .array([.string(cwd.path)]), "forceReload": .bool(true),
                ]), cwd: cwd.path)
    }

    public func setChatMethod(_ method: AgentChatMethod, enabled: Bool) async throws -> Bool {
        guard !method.isProtected else { throw CodexConnectionError.invalidMessage }
        let result = try await request(
            "skills/config/write",
            params: [
                "path": .string(method.selection.path), "enabled": .bool(enabled),
            ])
        guard let effective = result.objectValue?["effectiveEnabled"]?.boolValue
        else { throw CodexConnectionError.invalidMessage }
        return effective
    }

    public func chatConnectedTools(threadID: String?) async throws -> [AgentChatConnectedTool] {
        var cursor: String?
        var visited: Set<String> = []
        var tools: [AgentChatConnectedTool] = []
        repeat {
            var params: [String: MCPJSONValue] = ["limit": .integer(100)]
            if let threadID { params["threadId"] = .string(threadID) }
            if let cursor { params["cursor"] = .string(cursor) }
            let result = try await request("mcpServerStatus/list", params: params)
            tools += try CodexChatMethods.tools(result)
            cursor = result.objectValue?["nextCursor"]?.stringValue
            if let cursor, !visited.insert(cursor).inserted { throw CodexConnectionError.invalidMessage }
        } while cursor != nil
        guard Set(tools.map(\.id)).count == tools.count else { throw CodexConnectionError.invalidMessage }
        return tools
    }
}

public enum CodexChatMethods {
    public static func authorizationURL(_ result: MCPJSONValue) throws -> URL {
        guard let raw = result.objectValue?["authorizationUrl"]?.stringValue,
            let url = URL(string: raw), url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
        else { throw CodexConnectionError.invalidMessage }
        return url
    }
    public static func methods(_ result: MCPJSONValue, cwd: String) throws -> AgentChatMethodInventory {
        guard let data = result.objectValue?["data"]?.arrayValue,
            data.count == 1, let entry = data.first?.objectValue,
            entry["cwd"]?.stringValue == cwd, let skills = entry["skills"]?.arrayValue,
            let failures = entry["errors"]?.arrayValue
        else { throw CodexConnectionError.invalidMessage }
        let methods = try skills.map { value -> AgentChatMethod in
            guard let skill = value.objectValue, let name = skill["name"]?.stringValue, !name.isEmpty,
                let path = skill["path"]?.stringValue, path.hasPrefix("/"),
                let enabled = skill["enabled"]?.boolValue, let scope = skill["scope"]?.stringValue,
                let description = skill["description"]?.stringValue
            else { throw CodexConnectionError.invalidMessage }
            return .init(
                selection: .init(
                    name: name,
                    title: skill["interface"]?.objectValue?["displayName"]?.stringValue ?? name, path: path),
                description: description, enabled: enabled, scope: scope,
                dependencies: skill["dependencies"]?.objectValue?["tools"]?.arrayValue?.compactMap {
                    $0.objectValue?["value"]?.stringValue
                } ?? [])
        }
        let errors = try failures.map { value -> String in
            guard let error = value.objectValue, let path = error["path"]?.stringValue,
                let message = error["message"]?.stringValue
            else { throw CodexConnectionError.invalidMessage }
            return "\(path): \(message)"
        }
        guard Set(methods.map(\.id)).count == methods.count else { throw CodexConnectionError.invalidMessage }
        return .init(methods: methods.sorted { $0.selection.title.localizedStandardCompare($1.selection.title) == .orderedAscending }, errors: errors)
    }

    public static func tools(_ result: MCPJSONValue) throws -> [AgentChatConnectedTool] {
        guard let data = result.objectValue?["data"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
        return try data.map { value in
            guard let item = value.objectValue, let name = item["name"]?.stringValue, !name.isEmpty,
                let auth = item["authStatus"]?.stringValue, let tools = item["tools"]?.objectValue
            else { throw CodexConnectionError.invalidMessage }
            return .init(
                name: name, title: item["serverInfo"]?.objectValue?["title"]?.stringValue ?? name,
                connectionStatus: item["runtimeStatus"]?.stringValue, authStatus: auth, tools: tools.keys.sorted())
        }
    }
}
