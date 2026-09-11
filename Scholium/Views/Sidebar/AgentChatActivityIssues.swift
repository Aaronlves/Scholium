import ScholiumContracts
import SwiftUI

/// Counts are observed outcomes, not a claim that a failure was resolved or
/// that the researcher must intervene. Final prose never clears this evidence.
struct AgentChatActivityIssueCounts: Equatable {
  let failed: Int
  let uncertain: Int
  init(_ messages: [AgentChatMessage]) {
    failed = messages.filter { $0.activity?.status == .failed }.count
    uncertain = messages.filter { $0.activity?.status == .uncertain }.count
  }
}

struct AgentChatActivityIssues: View {
  let messages: [AgentChatMessage]
  var body: some View {
    let counts = AgentChatActivityIssueCounts(messages)
    if counts.failed > 0 || counts.uncertain > 0 {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.circle").accessibilityHidden(true)
        if counts.failed > 0 { Text("\(counts.failed) failed operations", bundle: .module) }
        if counts.uncertain > 0 { Text("\(counts.uncertain) unconfirmed outcomes", bundle: .module) }
      }.font(.caption).foregroundStyle(.secondary)
    }
  }
}
