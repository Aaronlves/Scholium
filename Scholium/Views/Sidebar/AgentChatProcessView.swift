import ScholiumContracts
import SwiftUI

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
  let messages: [AgentChatMessage]
  let isActive: Bool
  let hasFinalAnswer: Bool
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
        || ($0.activity?.status == .failed && !hasFinalAnswer)
    }
  }

  var body: some View {
    DisclosureGroup(isExpanded: Binding(get: { isExpanded }, set: {
      inspect()
      userExpansion = $0; isExpanded = $0
    })) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(AgentChatProcessSlice.collect(messages)) { slice in
          if slice.isTools {
            AgentChatActivityGroup(messages: slice.messages,
              isActive: isActive && animates && slice.messages.contains { $0.id == messages.last(where: { $0.activity?.status == .running })?.id },
              forceExpanded: forceExpanded, inspect: { inspect(); userExpansion = true }, row: row)
          } else if let message = slice.messages.first { row(message) }
        }
      }.padding(.top, 6)
    } label: {
      if let status {
        AgentChatTurnStatus(presentation: status, animates: animates)
      } else {
        Label("Process", systemImage: "ellipsis")
          .font(.callout).foregroundStyle(.secondary)
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
