import Foundation
import ScholiumContracts

/// Read-only projection of a runtime request and its supported, explicit decision scopes.
public struct CodexChatRuntimeApproval: Sendable {
  public let presentation: AgentChatRuntimeApproval
  private let requestedPermissions: MCPJSONValue?

  public func response(for decision: AgentChatRuntimeApproval.Decision) throws -> MCPJSONValue {
    guard presentation.grants.contains(decision) || presentation.rejection == decision else {
      throw CodexConnectionError.invalidMessage
    }
    if presentation.kind == .tool {
      return .object(["action": .string(decision == .once ? "accept" : "decline"), "content": .object([:])])
    }
    if presentation.kind == .permissions {
      return .object([
        "permissions": decision == .decline ? .object([:]) : (requestedPermissions ?? .object([:])),
        "scope": .string(decision == .session ? "session" : "turn"),
      ])
    }
    let value: String =
      switch decision {
      case .once: "accept"
      case .session: "acceptForSession"
      case .decline: "decline"
      case .cancel: "cancel"
      case .turn: throw CodexConnectionError.invalidMessage
      }
    return .object(["decision": .string(value)])
  }

  public static func parse(method: String, params: [String: MCPJSONValue], item: CodexChatOperationContext?) throws -> Self {
    let item = item?.value
    let common: Set<String> = ["threadId", "turnId", "itemId", "startedAtMs", "reason"]
    var reason = try string(params["reason"])
    var kind: AgentChatRuntimeApproval.Kind
    var command: String?
    var cwd: String?
    var environment: String?
    var host: String?
    var networkProtocol: String?
    var permissions: AgentChatRuntimeApproval.Permissions?
    var files: [AgentChatRuntimeApproval.File] = []
    var grantRoot: String?
    var grants: [AgentChatRuntimeApproval.Decision] = []
    var rejection = AgentChatRuntimeApproval.Decision.decline
    var requestedPermissions: MCPJSONValue?
    var toolServer: String?
    switch method {
    case "mcpServer/elicitation/request":
      try keys(params, ["threadId", "turnId", "serverName", "mode", "_meta", "message", "requestedSchema"])
      guard params["mode"]?.stringValue == "form",
        params["_meta"]?.objectValue?["codex_approval_kind"]?.stringValue == "mcp_tool_call",
        let schema = params["requestedSchema"]?.objectValue,
        schema["type"]?.stringValue == "object", schema["properties"]?.objectValue?.isEmpty == true,
        schema["required"] == nil || schema["required"] == .null || schema["required"]?.arrayValue?.isEmpty == true
      else { throw CodexConnectionError.invalidMessage }
      try keys(schema, ["$schema", "type", "properties", "required"])
      kind = .tool
      toolServer = try requiredString(params["serverName"])
      reason = try requiredString(params["message"])
      grants = [.once]
    case "item/commandExecution/requestApproval":
      try keys(
        params,
        common.union([
          "command", "cwd", "environmentId", "kind", "approvalId", "commandActions",
          "additionalPermissions", "availableDecisions", "networkApprovalContext", "proposedExecpolicyAmendment",
          "proposedNetworkPolicyAmendments",
        ]))
      switch try string(params["kind"]) ?? "command" {
      case "command": kind = .command
      case "writeStdin": kind = .terminalInput
      default: throw CodexConnectionError.invalidMessage
      }
      command = try string(params["command"])
      cwd = try string(params["cwd"])
      environment = try string(params["environmentId"])
      if let network = try object(params["networkApprovalContext"]) {
        try keys(network, ["host", "protocol"])
        host = try requiredString(network["host"])
        let protocolName = try requiredString(network["protocol"])
        guard ["http", "https", "socks5Tcp", "socks5Udp"].contains(protocolName) else {
          throw CodexConnectionError.invalidMessage
        }
        networkProtocol = protocolName
        kind = .network
      }
      guard command?.isEmpty == false || host != nil else { throw CodexConnectionError.invalidMessage }
      if kind == .terminalInput && command == nil { throw CodexConnectionError.invalidMessage }
      permissions = try permissionProfile(params["additionalPermissions"])
      if let choices = try array(params["availableDecisions"]) {
        for choice in choices {
          if let label = choice.stringValue {
            guard ["accept", "acceptForSession", "decline", "cancel"].contains(label) else {
              throw CodexConnectionError.invalidMessage
            }
          } else if let policy = choice.objectValue {
            guard policy.count == 1,
              policy["acceptWithExecpolicyAmendment"]?.objectValue != nil
                || policy["applyNetworkPolicyAmendment"]?.objectValue != nil
            else { throw CodexConnectionError.invalidMessage }
          } else {
            throw CodexConnectionError.invalidMessage
          }
        }
        let labels = choices.compactMap(\.stringValue)
        if labels.contains("accept") { grants.append(.once) }
        if labels.contains("acceptForSession") { grants.append(.session) }
        if labels.contains("decline") {
          rejection = .decline
        } else if labels.contains("cancel") {
          rejection = .cancel
        } else {
          throw CodexConnectionError.invalidMessage
        }
      } else {
        grants = [.once]
      }
    case "item/fileChange/requestApproval":
      try keys(params, common.union(["grantRoot"]))
      kind = .files
      grantRoot = try string(params["grantRoot"])
      if grantRoot?.isEmpty == true { throw CodexConnectionError.invalidMessage }
      if let operation = item?.objectValue {
        guard operation["type"]?.stringValue == "fileChange" else { throw CodexConnectionError.invalidMessage }
        let changes = try array(operation["changes"]) ?? []
        files = try changes.map { value in
          guard let change = value.objectValue, let type = change["kind"]?.objectValue,
            let fileKind = type["type"]?.stringValue.flatMap(AgentChatRuntimeApproval.File.Kind.init(rawValue:))
          else { throw CodexConnectionError.invalidMessage }
          try keys(change, ["path", "kind", "diff"])
          try keys(type, fileKind == .update ? ["type", "move_path"] : ["type"])
          return AgentChatRuntimeApproval.File(
            path: try requiredString(change["path"]), kind: fileKind,
            destination: try string(type["move_path"]), diff: try requiredString(change["diff"], allowsEmpty: true))
        }
      }
      guard !files.isEmpty || grantRoot?.isEmpty == false else { throw CodexConnectionError.invalidMessage }
      grants = grantRoot == nil ? [.once, .session] : [.session]
    case "item/permissions/requestApproval":
      try keys(params, common.union(["cwd", "environmentId", "permissions"]))
      kind = .permissions
      cwd = try requiredString(params["cwd"])
      environment = try string(params["environmentId"])
      requestedPermissions = params["permissions"]
      guard let profile = try permissionProfile(requestedPermissions) else { throw CodexConnectionError.invalidMessage }
      permissions = profile
      grants = [.turn, .session]
    default: throw CodexConnectionError.invalidMessage
    }
    return Self(
      presentation: .init(
        kind: kind, command: command, cwd: cwd, environmentID: environment, reason: reason,
        networkHost: host, networkProtocol: networkProtocol, permissions: permissions, files: files,
        grantRoot: grantRoot, grants: grants, rejection: rejection, toolServer: toolServer), requestedPermissions: requestedPermissions)
  }

  private static func permissionProfile(_ value: MCPJSONValue?) throws -> AgentChatRuntimeApproval.Permissions? {
    guard let profile = try object(value) else { return nil }
    try keys(profile, ["network", "fileSystem"])
    var network: Bool?
    var rules: [AgentChatRuntimeApproval.Rule] = []
    var depth: Int?
    if let scope = try object(profile["network"]) {
      try keys(scope, ["enabled"])
      if let value = scope["enabled"], value != .null {
        guard let enabled = value.boolValue else { throw CodexConnectionError.invalidMessage }
        network = enabled
      }
    }
    if let scope = try object(profile["fileSystem"]) {
      try keys(scope, ["read", "write", "entries", "globScanMaxDepth"])
      for access in [AgentChatRuntimeApproval.Access.read, .write] {
        for path in try array(scope[access.rawValue]) ?? [] {
          rules.append(.init(access: access, path: .literal(try requiredString(path))))
        }
      }
      for entry in try array(scope["entries"]) ?? [] {
        guard let object = entry.objectValue,
          let access = object["access"]?.stringValue.flatMap(AgentChatRuntimeApproval.Access.init(rawValue:)),
          let path = object["path"]?.objectValue
        else { throw CodexConnectionError.invalidMessage }
        try keys(object, ["access", "path"])
        let parsed: AgentChatRuntimeApproval.Path
        switch path["type"]?.stringValue {
        case "path":
          try keys(path, ["type", "path"])
          parsed = .literal(try requiredString(path["path"]))
        case "glob_pattern":
          try keys(path, ["type", "pattern"])
          parsed = .pattern(try requiredString(path["pattern"]))
        case "special":
          try keys(path, ["type", "value"])
          guard let special = path["value"]?.objectValue,
            let root = special["kind"]?.stringValue.flatMap(AgentChatRuntimeApproval.Root.init(rawValue:))
          else { throw CodexConnectionError.invalidMessage }
          try keys(special, root == .projectRoots ? ["kind", "subpath"] : ["kind"])
          parsed = .special(root, subpath: try string(special["subpath"]))
        default: throw CodexConnectionError.invalidMessage
        }
        rules.append(.init(access: access, path: parsed))
      }
      if let raw = scope["globScanMaxDepth"], raw != .null {
        guard let value = raw.intValue, value >= 1 else { throw CodexConnectionError.invalidMessage }
        depth = value
      }
    }
    return .init(network: network, rules: rules, globScanMaxDepth: depth)
  }

  private static func keys(_ value: [String: MCPJSONValue], _ allowed: Set<String>) throws {
    guard Set(value.keys).isSubset(of: allowed) else { throw CodexConnectionError.invalidMessage }
  }
  private static func string(_ value: MCPJSONValue?) throws -> String? {
    guard let value, value != .null else { return nil }
    guard let text = value.stringValue else { throw CodexConnectionError.invalidMessage }
    return text
  }
  private static func requiredString(_ value: MCPJSONValue?, allowsEmpty: Bool = false) throws -> String {
    guard let value = try string(value), allowsEmpty || !value.isEmpty else {
      throw CodexConnectionError.invalidMessage
    }
    return value
  }
  private static func object(_ value: MCPJSONValue?) throws -> [String: MCPJSONValue]? {
    guard let value, value != .null else { return nil }
    guard let object = value.objectValue else { throw CodexConnectionError.invalidMessage }
    return object
  }
  private static func array(_ value: MCPJSONValue?) throws -> [MCPJSONValue]? {
    guard let value, value != .null else { return nil }
    guard let array = value.arrayValue else { throw CodexConnectionError.invalidMessage }
    return array
  }
}
