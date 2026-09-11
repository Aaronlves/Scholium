import ScholiumContracts
import SwiftUI

/// A compact, persistent list of researcher-authored input waiting for the
/// next turn. Runtime admission remains with AgentChatController.
struct AgentChatQueueView: View {
  let messages: [AgentChatMessage]
  let canSend: (AgentChatMessage) -> Bool
  let send: (String) -> Void
  let canSteer: (AgentChatMessage) -> Bool
  let steer: (String) -> Void
  let remove: (String) -> Void

  @State private var inspectedMessage: AgentChatMessage?

  var body: some View {
    AgentChatContentScroll(maximumHeight: 144) {
      VStack(spacing: 6) {
        ForEach(messages) { message in
          HStack(spacing: 8) {
            Button {
              inspectedMessage = message
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "text.badge.plus").foregroundStyle(.secondary)
                Text(message.text.isEmpty ? String(localized: "Materials", bundle: .module) : message.text)
                  .lineLimit(1).truncationMode(.tail)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .help(Text("Queued message", bundle: .module))
            deliveryButton(message)
            Menu {
              Button("Remove from Queue", role: .destructive) { remove(message.id) }
            } label: { Image(systemName: "ellipsis") }
              .menuStyle(.borderlessButton).menuIndicator(.hidden)
              .accessibilityLabel("Queued message actions")
          }.frame(minHeight: 24)
        }
      }
    }
    .font(.callout)
    .buttonStyle(.borderless)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    // The front input surface overlaps only this empty glass margin.
    .padding(.bottom, 16)
    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 16))
    .padding(.horizontal, ScholiumSidebarLayout.edgeInset + 8)
    .padding(.top, ScholiumSidebarLayout.edgeInset)
    .tint(nil as Color?)
    .popover(item: $inspectedMessage) { message in
      AgentChatContentScroll {
        AgentChatQueuedMessageContents(message: message).padding(8)
      }.frame(width: 300).tint(nil as Color?)
    }
    .onChange(of: messages.map(\.id)) { _, ids in
      if let inspectedMessage, !ids.contains(inspectedMessage.id) { self.inspectedMessage = nil }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.queue")
  }

  @ViewBuilder
  private func deliveryButton(_ message: AgentChatMessage) -> some View {
    if canSend(message) {
      Button("Send Next") { send(message.id) }
        .fixedSize().help(Text("Send Next", bundle: .module))
    } else {
      Button { steer(message.id) } label: {
        Label { Text("Steer", bundle: .module) } icon: { Image(systemName: "arrow.turn.down.right") }
      }
      .fixedSize()
      .disabled(!canSteer(message))
      .help(Text("Add to Current Turn", bundle: .module))
      .accessibilityLabel(Text("Add to Current Turn", bundle: .module))
    }
  }

}

/// Read-only queue contents; each message appears once.
struct AgentChatQueuedMessageContents: View {
  let message: AgentChatMessage

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: message.text).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      if !message.attachments.isEmpty || !message.localMaterials.isEmpty
        || !(message.replyQuotes ?? []).isEmpty || !(message.methods ?? []).isEmpty {
        DisclosureGroup("Materials") {
          ForEach(message.attachments) { attachment in
            DisclosureGroup(URL(fileURLWithPath: attachment.relativePath).lastPathComponent) {
              Text(attachment.source == .editorSnapshot
                ? String(localized: "Editor Snapshot", bundle: .module)
                : String(localized: "Saved Source", bundle: .module)).foregroundStyle(.secondary)
              Text(attachment.extent == .wholeNote
                ? String(localized: "Whole Note", bundle: .module)
                : String(localized: "Attached Passage", bundle: .module)).foregroundStyle(.secondary)
              Text(verbatim: attachment.text).textSelection(.enabled)
            }
          }
          ForEach(message.localMaterials) { material in
            Label(AgentChatLocalMaterialLabels.title(material), systemImage: material.kind == .image ? "photo" : "doc.text")
            Text(AgentChatLocalMaterialLabels.summary(material)).foregroundStyle(.secondary)
          }
          ForEach(message.replyQuotes ?? []) { quote in
            Text(verbatim: quote.text).textSelection(.enabled)
              .accessibilityLabel(Text("Quoted reply: \(quote.text)"))
          }
          ForEach(message.methods ?? []) { method in
            Label(method.title, systemImage: "square.stack")
              .accessibilityLabel("Requested Skill: \(method.title)")
          }
        }
      }
    }
    .accessibilityIdentifier("scholium.chat.queuedMessage.\(message.id)")
  }
}
