import ScholiumContracts
import SwiftUI

/// Consecutive tool calls share one compact row; all records remain inspectable.
struct AgentChatProcessSlice: Identifiable {
  let messages: [AgentChatMessage]
  var id: String { messages[0].id }
  var isTools: Bool { messages[0].activity != nil }

  static func collect(_ messages: [AgentChatMessage]) -> [Self] {
    var result: [Self] = []
    for message in messages {
      if message.activity != nil, result.last?.isTools == true {
        let previous = result.removeLast()
        result.append(.init(messages: previous.messages + [message]))
      } else { result.append(.init(messages: [message])) }
    }
    return result
  }
}

struct AgentChatActivityGroup<Row: View>: View {
  let messages: [AgentChatMessage]
  let isActive: Bool
  let forceExpanded: Bool
  let inspect: () -> Void
  @ViewBuilder let row: (AgentChatMessage) -> Row
  @State private var expanded = false
  @Environment(\.locale) private var locale

  private var current: AgentChatMessage? {
    messages.last(where: { $0.activity?.status.isActive == true })
      ?? messages.last(where: { $0.activity?.status == .uncertain }) ?? messages.last
  }

  var body: some View {
    DisclosureGroup(isExpanded: Binding(get: { expanded }, set: { value in
      expanded = value
      if value { inspect() }
    })) {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(messages) { row($0) }
      }
    } label: {
      if let activity = current?.activity {
        HStack(spacing: 6) {
          Image(systemName: activity.status.isActive || activity.status == .completed ? activity.kind.symbol : activity.status.symbol)
            .chatAccessory().accessibilityHidden(true)
          AgentChatActivityText(text: AgentChatActivityProjection.summary(activity, locale: locale),
            isCurrent: isActive && activity.status == .running)
            .lineLimit(1)
          if messages.count > 1 {
            Text(verbatim: String(messages.count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
          }
          if activity.status != .running && activity.status != .completed {
            Text(activity.status.label(locale: locale)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .disclosureGroupStyle(AgentChatDisclosureStyle())
    .onChange(of: forceExpanded, initial: true) { _, force in if force { expanded = true } }
    .accessibilityIdentifier("scholium.chat.toolGroup.\(messages.first?.id ?? "")")
  }
}
