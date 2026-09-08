import ScholiumContracts
import SwiftUI

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
  let messages: [AgentChatMessage]
  let isActive: Bool
  let hasFinalAnswer: Bool
  let forceExpanded: Bool
  @ViewBuilder let row: (AgentChatMessage) -> Row
  @State private var isExpanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var needsAttention: Bool {
    messages.contains {
      $0.activity?.status == .uncertain || $0.activity?.status == .interrupted || $0.activity?.status == .waitingForApproval
        || $0.activity?.status == .waitingForInput
        || ($0.activity?.status == .failed && !hasFinalAnswer)
    }
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(messages) { message in row(message) }
      }.padding(.top, 6)
    } label: {
      Label("Process", systemImage: "ellipsis")
        .font(.callout).foregroundStyle(.secondary)
    }
    .animation(reduceMotion ? nil : .default, value: isExpanded)
    .onChange(of: isActive, initial: true) { _, active in
      isExpanded = active || needsAttention || forceExpanded
    }
    .onChange(of: forceExpanded) { _, force in if force { isExpanded = true } }
    .onChange(of: needsAttention) { _, needed in if needed { isExpanded = true } }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.process.\(messages.first?.id ?? "")")
  }
}
