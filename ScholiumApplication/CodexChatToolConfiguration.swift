import Foundation
import ScholiumContracts

public struct CodexChatToolConfiguration: Sendable {
  public let file: String
  public let version: String
  public let connections: [AgentChatToolConnection]
  private let rawConnections: [String: MCPJSONValue]

  public init(_ result: MCPJSONValue, home: URL) throws {
    let expectedFile = home.appendingPathComponent("config.toml").standardizedFileURL.path
    guard let result = result.objectValue,
      let layers = result["layers"]?.arrayValue,
      let layer = layers.first(where: {
        $0.objectValue?["name"]?.objectValue?["type"]?.stringValue == "user"
          && $0.objectValue?["name"]?.objectValue?["profile"]?.stringValue == nil
          && $0.objectValue?["name"]?.objectValue?["file"]?.stringValue == expectedFile
      })?.objectValue, let version = layer["version"]?.stringValue, !version.isEmpty,
      let raw = layer["config"]?.objectValue, let effective = result["config"]?.objectValue
    else { throw CodexConnectionError.invalidMessage }
    self.file = expectedFile; self.version = version
    let own = raw["mcp_servers"]?.objectValue ?? [:]
    rawConnections = own
    let servers = effective["mcp_servers"]?.objectValue ?? [:]
    connections = try servers.keys.sorted().map { name in
      guard let value = servers[name]?.objectValue else { throw CodexConnectionError.invalidMessage }
      let local = value["command"]?.stringValue != nil
      let address = value[local ? "command" : "url"]?.stringValue ?? ""
      let arguments = value["args"]?.arrayValue?.compactMap(\.stringValue) ?? []
      let base = own[name]?.objectValue
      let editable = name.lowercased() != "scholium" && base != nil
        && base?[local ? "command" : "url"]?.stringValue == address
        && (base?["args"]?.arrayValue?.compactMap(\.stringValue) ?? []) == arguments
        && (base?["enabled"]?.boolValue ?? true) == (value["enabled"]?.boolValue ?? true)
        && ["http_headers", "env_http_headers", "http_headers_helper", "bearer_token_env_var", "env", "env_vars"].allSatisfy { base?[$0] == value[$0] }
      let environment = value["env_vars"]?.arrayValue ?? []
      return .init(name: name, kind: local ? .local : .remote, address: address,
        arguments: arguments, enabled: value["enabled"]?.boolValue ?? true,
        bearerTokenVariable: value["bearer_token_env_var"]?.stringValue ?? "",
        environmentVariables: environment.compactMap(\.stringValue),
        canEditEnvironmentVariables: environment.allSatisfy { $0.stringValue != nil }, isEditable: editable)
    }
  }

  public func requiresAccessConfirmation(_ connection: AgentChatToolConnection, originalName: String?) -> Bool {
    guard let name = originalName, let old = connections.first(where: { $0.name == name }),
      let raw = rawConnections[name]?.objectValue else { return false }
    if old.kind != connection.kind { return true }
    if connection.kind == .local {
      return old.address != connection.address && (raw["env"]?.objectValue?.isEmpty == false || raw["env_vars"]?.arrayValue?.isEmpty == false)
    }
    func origin(_ address: String) -> String? {
      guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host?.lowercased() else { return nil }
      let scheme = url.scheme?.lowercased() ?? ""
      return "\(scheme)://\(host):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
    return origin(old.address) != origin(connection.address)
      && (raw["http_headers"]?.objectValue?.isEmpty == false || raw["env_http_headers"]?.objectValue?.isEmpty == false
        || raw["http_headers_helper"] != nil
        || (!connection.bearerTokenVariable.isEmpty && connection.bearerTokenVariable == old.bearerTokenVariable))
  }

  public func writeParameters(_ connection: AgentChatToolConnection, originalName: String?, removing: Bool = false,
    reuseAccessSettings: Bool = false) throws -> [String: MCPJSONValue] {
    let name = originalName ?? connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue.map { $0 < 32 } == true })
    else { throw CodexChatToolConfigurationError.invalidName }
    guard name.lowercased() != "scholium" else { throw CodexChatToolConfigurationError.managedConnection }
    if originalName == nil {
      guard connections.allSatisfy({ $0.name != name }) else { throw CodexChatToolConfigurationError.duplicateName }
    } else {
      guard connections.contains(where: { $0.name == name && $0.isEditable }) else { throw CodexChatToolConfigurationError.managedConnection }
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
    let key = "mcp_servers." + String(decoding: try encoder.encode(name), as: UTF8.self)
    var edits: [MCPJSONValue] = []
    func edit(_ path: String, _ value: MCPJSONValue) {
      edits.append(.object(["keyPath": .string(path), "mergeStrategy": .string("replace"), "value": value]))
    }
    var fields: [String: MCPJSONValue] = [:]
    if !removing {
      guard reuseAccessSettings || !requiresAccessConfirmation(connection, originalName: originalName)
      else { throw CodexChatToolConfigurationError.accessConfirmationRequired }
      let address = connection.kind == .remote ? connection.address.trimmingCharacters(in: .whitespacesAndNewlines) : connection.address
      guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CodexChatToolConfigurationError.invalidAddress }
      if connection.kind == .remote {
        guard let url = URL(string: address), let host = url.host?.lowercased(), !host.isEmpty,
          url.user == nil, url.password == nil,
          url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http"
            && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
        else { throw CodexChatToolConfigurationError.invalidAddress }
        fields["url"] = .string(address)
      } else {
        fields["command"] = .string(address); fields["args"] = .array(connection.arguments.map(MCPJSONValue.string))
      }
      fields["enabled"] = .bool(connection.enabled)
      if let originalName {
        guard let original = connections.first(where: { $0.name == originalName }), original.kind == connection.kind
        else { throw CodexConnectionError.invalidMessage }
        let previous: [String: MCPJSONValue] = ["url": .string(original.address), "command": .string(original.address),
          "args": .array(original.arguments.map(MCPJSONValue.string)), "enabled": .bool(original.enabled)]
        for field in fields.keys.sorted() {
          if previous[field] != fields[field] { edit(key + "." + field, fields[field]!) }
        }
        if connection.kind == .remote, connection.bearerTokenVariable != original.bearerTokenVariable {
          try validateVariable(connection.bearerTokenVariable, allowsEmpty: true)
          edit(key + ".bearer_token_env_var", connection.bearerTokenVariable.isEmpty ? .null : .string(connection.bearerTokenVariable))
        }
        if connection.kind == .local, connection.environmentVariables != original.environmentVariables {
          guard original.canEditEnvironmentVariables else { throw CodexChatToolConfigurationError.managedConnection }
          try connection.environmentVariables.forEach { try validateVariable($0) }
          edit(key + ".env_vars", connection.environmentVariables.isEmpty ? .null : .array(connection.environmentVariables.map(MCPJSONValue.string)))
        }
      } else {
        if connection.kind == .remote, !connection.bearerTokenVariable.isEmpty {
          try validateVariable(connection.bearerTokenVariable)
          fields["bearer_token_env_var"] = .string(connection.bearerTokenVariable)
        }
        if connection.kind == .local, !connection.environmentVariables.isEmpty {
          try connection.environmentVariables.forEach { try validateVariable($0) }
          fields["env_vars"] = .array(connection.environmentVariables.map(MCPJSONValue.string))
        }
        edit(key, .object(fields))
      }
    } else {
      edit(key, .null)
    }
    return ["filePath": .string(file), "expectedVersion": .string(version), "reloadUserConfig": .bool(true),
      "edits": .array(edits)]
  }

  private func validateVariable(_ name: String, allowsEmpty: Bool = false) throws {
    if allowsEmpty && name.isEmpty { return }
    guard !name.isEmpty, !name.contains(where: { $0 == "=" || $0.isWhitespace || $0.isNewline
      || $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) })
    else { throw CodexChatToolConfigurationError.invalidVariable }
  }
}

extension CodexAppServer {
  public func chatToolConfiguration(home: URL) async throws -> CodexChatToolConfiguration {
    try CodexChatToolConfiguration(await request("config/read", params: ["includeLayers": .bool(true)]), home: home)
  }

  /// Return whether a higher-priority layer overrides the confirmed write.
  public func writeChatTool(_ connection: AgentChatToolConnection, originalName: String?,
    snapshot: CodexChatToolConfiguration, removing: Bool = false, reuseAccessSettings: Bool = false) async throws -> Bool {
    let result = try await request("config/batchWrite", params: snapshot.writeParameters(connection, originalName: originalName,
      removing: removing, reuseAccessSettings: reuseAccessSettings))
    guard let reply = result.objectValue, reply["filePath"]?.stringValue == snapshot.file,
      reply["version"]?.stringValue != nil, let status = reply["status"]?.stringValue,
      ["ok", "okOverridden"].contains(status) else { throw CodexConnectionError.invalidMessage }
    return status == "okOverridden"
  }
}

public enum CodexChatToolConfigurationError: LocalizedError {
  case accessConfirmationRequired
  case invalidName, duplicateName, managedConnection, invalidAddress, invalidVariable
  public var errorDescription: String? {
    switch self {
    case .accessConfirmationRequired: String(localized: "Confirm whether existing access settings may be used with the new destination.")
    case .invalidName: String(localized: "Enter a connection name without line breaks or control characters.")
    case .duplicateName: String(localized: "A tool connection already uses this name.")
    case .managedConnection: String(localized: "This connection is managed by another configuration or by Scholium.")
    case .invalidAddress: String(localized: "Enter a program or a valid HTTPS server address. Local servers may use HTTP on the loopback address.")
    case .invalidVariable: String(localized: "Enter environment variable names only, without values, spaces or equals signs.")
    }
  }
}
