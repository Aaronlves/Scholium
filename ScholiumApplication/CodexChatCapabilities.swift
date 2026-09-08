import Foundation
import ScholiumContracts

extension CodexAppServer {
  /// A runtime-wide check: a completed parent does not imply its children or commands are idle.
  public func chatIsIdleForSettingsRenewal() async throws -> Bool {
    func loadedThreads() async throws -> Set<String> {
      var ids: Set<String> = [], cursors: Set<String> = []
      var cursor: String?
      repeat {
        var params: [String: MCPJSONValue] = ["limit": .integer(100)]
        if let cursor { params["cursor"] = .string(cursor) }
        let result = try await request("thread/loaded/list", params: params)
        guard let data = result.objectValue?["data"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
        for value in data {
          guard let id = value.stringValue, !id.isEmpty, ids.insert(id).inserted else { throw CodexConnectionError.invalidMessage }
        }
        cursor = nil
        if let value = result.objectValue?["nextCursor"], value != .null {
          guard let next = value.stringValue, !next.isEmpty else { throw CodexConnectionError.invalidMessage }
          cursor = next
        }
        if let cursor, !cursors.insert(cursor).inserted { throw CodexConnectionError.invalidMessage }
      } while cursor != nil
      return ids
    }
    let initial = try await loadedThreads()
    for id in initial.sorted() {
      let result = try await request("thread/read", params: ["threadId": .string(id), "includeTurns": .bool(false)])
      guard result.objectValue?["thread"]?.objectValue?["id"] == .string(id),
        let status = result.objectValue?["thread"]?.objectValue?["status"]?.objectValue?["type"]?.stringValue else {
        throw CodexConnectionError.invalidMessage
      }
      if status == "notLoaded" { continue }
      guard status == "idle" else { return false }
      let terminals = try await request("thread/backgroundTerminals/list", params: ["threadId": .string(id), "limit": .integer(1)])
      guard let data = terminals.objectValue?["data"]?.arrayValue else { throw CodexConnectionError.invalidMessage }
      // Any command or further page prevents renewal; no command is terminated here.
      guard data.isEmpty else { return false }
      if let cursor = terminals.objectValue?["nextCursor"], cursor != .null {
        guard let value = cursor.stringValue, !value.isEmpty else { throw CodexConnectionError.invalidMessage }
        return false
      }
    }
    return try await loadedThreads() == initial
  }

  /// Follow the official catalog cursor; never offer a silently truncated model list.
  public func chatModels() async throws -> [AgentChatModel] {
    var models: [AgentChatModel] = []
    var cursor: String?
    var visited: Set<String> = []
    repeat {
      var params: [String: MCPJSONValue] = ["limit": .integer(100)]
      if let cursor { params["cursor"] = .string(cursor) }
      let result = try await request("model/list", params: params)
      let page = try CodexChatCapabilities.models(result)
      models.append(contentsOf: page)
      cursor = result.objectValue?["nextCursor"]?.stringValue
      if let cursor, !visited.insert(cursor).inserted { throw CodexConnectionError.invalidMessage }
    } while cursor != nil
    guard Set(models.map(\.id)).count == models.count else {
      throw CodexConnectionError.invalidMessage
    }
    return models
  }

  public func chatQuotas() async throws -> [AgentChatQuota] {
    try CodexChatCapabilities.quotas(await request("account/rateLimits/read"))
  }

  public func chatDefaults() async throws -> AgentChatPreferences {
    let result = try await request("config/read", params: ["includeLayers": .bool(false)])
    guard let config = result.objectValue?["config"]?.objectValue else {
      throw CodexConnectionError.invalidMessage
    }
    return .init(model: config["model"]?.stringValue,
      effort: config["model_reasoning_effort"]?.stringValue,
      webSearch: config["web_search"]?.stringValue.flatMap(AgentChatPreferences.WebSearch.init(rawValue:))
        ?? .runtimeDefault)
  }
}

/// Provider-wire translation. Views consume Contracts values, never JSON payloads.
public enum CodexChatCapabilities {
  public static func models(_ result: MCPJSONValue) throws -> [AgentChatModel] {
    guard let values = result.objectValue?["data"]?.arrayValue else {
      throw CodexConnectionError.invalidMessage
    }
    return try values.compactMap { value in
      guard let item = value.objectValue,
        let id = item["id"]?.stringValue, !id.isEmpty,
        let model = item["model"]?.stringValue, !model.isEmpty,
        let name = item["displayName"]?.stringValue,
        let isDefault = item["isDefault"]?.boolValue,
        let defaultEffort = item["defaultReasoningEffort"]?.stringValue,
        let options = item["supportedReasoningEfforts"]?.arrayValue
      else { throw CodexConnectionError.invalidMessage }
      if item["hidden"]?.boolValue == true { return nil }
      let efforts = try options.map { option in
        guard let effort = option.objectValue?["reasoningEffort"]?.stringValue,
          !effort.isEmpty else { throw CodexConnectionError.invalidMessage }
        return effort
      }
      return .init(id: id, model: model, name: name, efforts: efforts,
        defaultEffort: defaultEffort, isDefault: isDefault,
        inputModalities: item["inputModalities"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    }
  }

  public static func contextUsage(_ params: [String: MCPJSONValue]) -> AgentChatContextUsage? {
    guard let usage = params["tokenUsage"]?.objectValue,
      let last = usage["last"]?.objectValue?["totalTokens"]?.intValue, last >= 0,
      let total = usage["total"]?.objectValue?["totalTokens"]?.intValue, total >= 0
    else { return nil }
    let capacity = usage["modelContextWindow"]?.intValue.flatMap { $0 > 0 ? $0 : nil }
    return .init(lastTurnTokens: last, totalTokens: total, capacity: capacity)
  }

  public static func plan(_ params: [String: MCPJSONValue]) -> AgentChatPlan? {
    guard let turn = params["turnId"]?.stringValue,
      let values = params["plan"]?.arrayValue else { return nil }
    var steps: [AgentChatPlan.Step] = []
    for value in values {
      guard let item = value.objectValue, let text = item["step"]?.stringValue,
        let raw = item["status"]?.stringValue,
        let status = AgentChatPlan.Step.Status(rawValue: raw) else { return nil }
      steps.append(.init(step: text, status: status))
    }
    return .init(turnID: turn, explanation: params["explanation"]?.stringValue, steps: steps)
  }

  public static func quotas(_ result: MCPJSONValue) throws -> [AgentChatQuota] {
    guard let object = result.objectValue else { throw CodexConnectionError.invalidMessage }
    let buckets: [String: MCPJSONValue]
    if let map = object["rateLimitsByLimitId"]?.objectValue { buckets = map }
    else if let single = object["rateLimits"], let value = single.objectValue {
      // Both shapes are published in the current official protocol.
      buckets = [value["limitId"]?.stringValue ?? "codex": single]
    } else { throw CodexConnectionError.invalidMessage }
    func window(_ value: MCPJSONValue?) throws -> AgentChatQuota.Window? {
      guard let value, value != .null else { return nil }
      guard let item = value.objectValue, let used = item["usedPercent"]?.intValue,
        used >= 0 else { throw CodexConnectionError.invalidMessage }
      return .init(usedPercent: used, durationMinutes: item["windowDurationMins"]?.intValue,
        resetsAt: item["resetsAt"]?.intValue.map { Date(timeIntervalSince1970: Double($0)) })
    }
    return try buckets.sorted { $0.key < $1.key }.map { key, value in
      guard let item = value.objectValue else { throw CodexConnectionError.invalidMessage }
      return try .init(id: key, name: item["limitName"]?.stringValue ?? key,
        primary: window(item["primary"]), secondary: window(item["secondary"]))
    }
  }
}
