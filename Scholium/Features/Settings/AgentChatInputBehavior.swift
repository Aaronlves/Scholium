import SwiftUI

enum AgentChatInputBehavior: String, CaseIterable {
  case steer, queue
  static let key = "scholium.chat.activeTurnInput"
}

struct AgentChatInputSettingsView: View {
  @AppStorage(AgentChatInputBehavior.key) private var behavior = AgentChatInputBehavior.steer

  var body: some View {
    Form {
      Picker(selection: $behavior) {
        Text("Add to Current Turn", bundle: .module).tag(AgentChatInputBehavior.steer)
        Text("Queue for Next Turn", bundle: .module).tag(AgentChatInputBehavior.queue)
      } label: {
        Text("Return while Agent is working", bundle: .module)
      }
      .accessibilityIdentifier("scholium.settings.chat.returnBehavior")
      Text("Return and the send button use this choice. Shift-Return inserts a newline. When idle, Return sends normally.", bundle: .module)
        .font(.callout).foregroundStyle(.secondary)
    }.formStyle(.grouped)
  }
}
