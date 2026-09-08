import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Codex capability boundaries")
struct CodexChatCapabilitiesTests {
  @Test("Quota buckets preserve unavailable windows and use the authoritative multi-bucket result")
  func quotas() throws {
    let result: MCPJSONValue = .object([
      "rateLimits": .object(["primary": .object(["usedPercent": .integer(99)])]),
      "rateLimitsByLimitId": .object([
        "research": .object([
          "primary": .object(["usedPercent": .integer(25), "resetsAt": .integer(1000)]),
          "secondary": .null,
        ]),
        "other": .object([:]),
      ]),
    ])
    let quotas = try CodexChatCapabilities.quotas(result)
    #expect(quotas.map(\.id) == ["other", "research"])
    #expect(quotas[0].primary == nil && quotas[0].secondary == nil)
    #expect(quotas[1].primary?.usedPercent == 25)
    #expect(quotas[1].primary?.durationMinutes == nil)
    #expect(quotas[1].primary?.resetsAt == Date(timeIntervalSince1970: 1000))
    #expect(throws: CodexConnectionError.self) {
      try CodexChatCapabilities.quotas(.object([:]))
    }
  }

  @Test("Usage and plan projections never invent missing counts or unknown step states")
  func contextAndPlans() {
    #expect(CodexChatCapabilities.contextUsage([:]) == nil)
    let value = CodexChatCapabilities.contextUsage([
      "tokenUsage": .object([
        "last": .object(["totalTokens": .integer(12)]),
        "total": .object(["totalTokens": .integer(80)]), "modelContextWindow": .null,
      ])
    ])
    #expect(value?.lastTurnTokens == 12 && value?.totalTokens == 80)
    #expect(value?.capacity == nil)
    #expect(CodexChatCapabilities.plan([
      "turnId": .string("turn"), "plan": .array([
        .object(["step": .string("Read"), "status": .string("philosophicallyAccepted")])
      ]),
    ]) == nil)
  }
}
