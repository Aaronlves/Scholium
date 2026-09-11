import ScholiumContracts
import SwiftUI

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
  let messages: [AgentChatMessage]
  let isActive: Bool
  let forceExpanded: Bool
  var status: AgentChatTurnPresentation? = nil
  var preservesReading = false
  var hasInspectedActivity = false
  var animates = true
  var inspect: () -> Void = {}
  @ViewBuilder let row: (AgentChatMessage) -> Row
  @State private var isExpanded = false
  @State private var userExpansion: Bool?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var needsAttention: Bool {
    messages.contains {
      $0.activity?.status == .uncertain || $0.activity?.status == .interrupted || $0.activity?.status == .waitingForApproval
        || $0.activity?.status == .waitingForInput
        || $0.activity?.status == .failed
    }
  }

  var body: some View {
    DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: {
      inspect()
      userExpansion = $0; isExpanded = $0
    })) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(messages) { row($0) }
      }.padding(.top, 6)
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        if let status {
          AgentChatTurnStatus(presentation: status, animates: animates)
        } else {
          Text("Process", bundle: .module).font(.callout).foregroundStyle(.secondary)
        }
        AgentChatActivityIssues(messages: messages)
      }
    }
    .disclosureGroupStyle(AgentChatDisclosureStyle())
    .animation(reduceMotion || preservesReading ? nil : .default, value: isExpanded)
    .onChange(of: isActive, initial: true) { _, active in
      if needsAttention || forceExpanded { isExpanded = true }
      else if active { isExpanded = userExpansion ?? true }
      else if !preservesReading && !hasInspectedActivity && userExpansion != true { isExpanded = false }
    }
    .onChange(of: forceExpanded) { _, force in if force { isExpanded = true } }
    .onChange(of: needsAttention) { _, needed in if needed { isExpanded = true } }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.process.\(messages.first?.id ?? "")")
  }
}
