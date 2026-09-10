import Foundation
import ScholiumContracts
import SwiftUI

/// A derived description of what the researcher has staged for a request.
/// Runtime usage remains a separate observation; this value never claims that
/// a provider accepted or consumed the staged context.
struct AgentChatContextLedger: Equatable {
  struct Material: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
  }

  struct Quote: Identifiable, Equatable {
    let id: UUID
    let messageID: String
    let text: String

    var preview: String {
      let normalized = text.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return String(normalized.prefix(240))
    }
  }

  let materials: [Material]
  let quotes: [Quote]
  let methods: [AgentChatMethodSelection]
  let modelName: String?
  let effort: String?
  let webSearch: AgentChatPreferences.WebSearch

  init(conversation: AgentChatConversation?, modelName: String? = nil, effort: String? = nil) {
    guard let conversation else {
      materials = []
      quotes = []
      methods = []
      self.modelName = nil
      self.effort = nil
      webSearch = .runtimeDefault
      return
    }
    var materialValues: [Material] = conversation.attachments.map { attachment in
      let title = URL(fileURLWithPath: attachment.relativePath)
        .deletingPathExtension().lastPathComponent
      return Material(
        id: attachment.id.uuidString,
        title: title.isEmpty ? attachment.relativePath : title,
        detail: attachment.extent == .wholeNote
          ? ScholiumL10n.string("Whole Note")
          : ScholiumL10n.string("Attached Passage"),
        symbol: attachment.extent == .wholeNote ? "doc.text" : "text.quote"
      )
    }
    materialValues += conversation.localMaterials.map { material in
      Material(
        id: material.id.uuidString,
        title: material.fileName,
        detail: AgentChatLocalMaterialLabels.summary(material),
        symbol: material.kind == .image ? "photo" : "doc.text"
      )
    }
    materials = materialValues
    quotes = (conversation.draftReplyQuotes ?? []).map { quote in
      Quote(id: quote.id, messageID: quote.messageID, text: quote.text)
    }
    methods = conversation.selectedMethods ?? []
    self.modelName = modelName ?? conversation.preferences.model
    self.effort = effort ?? conversation.preferences.effort
    webSearch = conversation.preferences.webSearch
  }

  var isEmpty: Bool {
    materials.isEmpty && quotes.isEmpty && methods.isEmpty && modelName == nil && effort == nil
      && webSearch == .runtimeDefault
  }
}

/// Compact, scroll-safe presentation of the staged context ledger.
struct AgentChatContextLedgerView: View {
  let ledger: AgentChatContextLedger

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        if !ledger.materials.isEmpty {
          ledgerSection("Materials") {
            ForEach(ledger.materials) { material in
              Label {
                VStack(alignment: .leading, spacing: 1) {
                  Text(material.title).lineLimit(2)
                  Text(material.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
              } icon: {
                Image(systemName: material.symbol).foregroundStyle(.secondary)
              }
            }
          }
        }
        if !ledger.quotes.isEmpty {
          ledgerSection("Quoted replies") {
            ForEach(ledger.quotes) { quote in
              Label {
                Text(verbatim: quote.preview)
                  .lineLimit(4)
                  .textSelection(.enabled)
              } icon: {
                Image(systemName: "text.quote").foregroundStyle(.secondary)
              }
            }
          }
        }
        if !ledger.methods.isEmpty {
          ledgerSection("Skills") {
            ForEach(ledger.methods) { method in
              Label(method.title, systemImage: "square.stack")
                .lineLimit(2).foregroundStyle(.primary)
            }
          }
        }
        if let modelName = ledger.modelName {
          LabeledContent("Model", value: modelName).lineLimit(1)
        }
        if let effort = ledger.effort {
          LabeledContent("Reasoning", value: AgentChatControlLabels.effort(effort)).lineLimit(1)
        }
        if ledger.webSearch != .runtimeDefault {
          LabeledContent("Web Search", value: AgentChatControlLabels.webSearch(ledger.webSearch)).lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Label("Prepared context", systemImage: "text.badge.checkmark")
        .font(.subheadline)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat.contextLedger")
  }

  @ViewBuilder
  private func ledgerSection<Content: View>(_ title: LocalizedStringKey,
                                             @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      content()
    }
  }
}
