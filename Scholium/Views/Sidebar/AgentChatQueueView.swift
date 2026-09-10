import ScholiumContracts
import SwiftUI

/// A compact, persistent list of researcher-authored input waiting for the
/// next turn. Runtime admission remains with AgentChatController.
struct AgentChatQueueView: View {
  let messages: [AgentChatMessage]
  let canSend: (AgentChatMessage) -> Bool
  let send: (String) -> Void
  let remove: (String) -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(messages) { message in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
            Text(verbatim: message.text)
              .lineLimit(3)
              .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
              Button("Send Next") { send(message.id) }
                .disabled(!canSend(message))
              Button("Remove from Queue", role: .destructive) { remove(message.id) }
            } label: {
              Image(systemName: "ellipsis.circle")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Queued message actions")
            .help("Queued message actions")
          }
          .padding(.vertical, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      HStack(spacing: 6) {
        Label("Next turn", systemImage: "text.badge.plus")
        Spacer(minLength: 8)
        Text(String(messages.count)).monospacedDigit().foregroundStyle(.secondary)
      }
      .font(.callout)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.queue")
  }
}
