import Foundation
import AppKit
import ScholiumContracts
import SwiftUI

/// Foundation parses Markdown; this projection only supplies native block layout.
struct AgentChatMarkdownBlock: Identifiable {
  enum Kind: Equatable {
    case prose, heading, code, quote
    case list(String)
    case tableRow(Bool)
  }
  let id: Int
  let kind: Kind
  var text: AttributedString
  var cells: [AttributedString] = []
  var isQuoted = false

  static func parse(_ source: String) -> [Self] {
    guard let parsed = try? AttributedString(markdown: source) else {
      return [.init(id: 0, kind: .prose, text: AttributedString(source))]
    }
    var blocks: [Self] = []
    for (intent, range) in parsed.runs[\.presentationIntent] {
      let components = intent?.components ?? []
      var text = AttributedString(parsed[range])
      text.presentationIntent = nil
      let id = components.first?.identity ?? blocks.count
      if let row = components.first(where: {
        if case .tableRow = $0.kind { return true }
        return $0.kind == .tableHeaderRow
      }), let cell = components.first, case .tableCell(let column) = cell.kind {
        if blocks.last?.id != row.identity {
          blocks.append(
            .init(
              id: row.identity, kind: .tableRow(row.kind == .tableHeaderRow),
              text: AttributedString()))
        }
        while blocks[blocks.count - 1].cells.count <= column {
          blocks[blocks.count - 1].cells.append(AttributedString())
        }
        blocks[blocks.count - 1].cells[column] += text
        continue
      }
      let kind: Kind
      if components.contains(where: {
        if case .header = $0.kind { return true }
        return false
      }) {
        kind = .heading
      } else if components.contains(where: {
        if case .codeBlock = $0.kind { return true }
        return false
      }) {
        kind = .code
      } else if let list = components.first(where: {
        if case .listItem = $0.kind { return true }
        return false
      }),
        case .listItem(let ordinal) = list.kind
      {
        let ordered =
          components.drop(while: { $0.identity != list.identity }).dropFirst().first?.kind
          == .orderedList
        kind = .list(ordered ? "\(ordinal)." : "•")
      } else if components.contains(where: { $0.kind == .blockQuote }) {
        kind = .quote
      } else {
        kind = .prose
      }
      blocks.append(
        .init(
          id: id, kind: kind, text: text, isQuoted: components.contains { $0.kind == .blockQuote }))
    }
    if blocks.isEmpty, !source.isEmpty {
      return [.init(id: 0, kind: .prose, text: AttributedString(source))]
    }
    return blocks
  }
}

struct AgentChatMarkdown: View {
  let text: String
  var expandsToFillWidth = true
  var quoteSelection: ((AgentChatReplySelection) -> Void)? = nil
  @Environment(\.openURL) private var openURL

  var body: some View {
    Group {
      if let quoteSelection {
        AgentChatSelectableText(source: text,
          quote: { range, rendered in
            quoteSelection(.init(range: range, renderedText: rendered))
          }, openLink: { openURL($0) })
      } else {
        let blocks = AgentChatMarkdownBlock.parse(text)
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            blockView(block).padding(.bottom, spacing(after: index, in: blocks))
          }
        }
        .font(.body)
        .textSelection(.enabled)
      }
    }
    .frame(maxWidth: expandsToFillWidth ? .infinity : nil, alignment: .leading)
  }

  private func spacing(after index: Int, in blocks: [AgentChatMarkdownBlock]) -> CGFloat {
    guard index + 1 < blocks.count else { return 0 }
    switch (blocks[index].kind, blocks[index + 1].kind) {
    case (.list(_), .list(_)), (.tableRow(_), .tableRow(_)): return 4
    default: return 12
    }
  }

  @ViewBuilder
  private func blockView(_ block: AgentChatMarkdownBlock) -> some View {
    switch block.kind {
    case .prose:
      Text(block.text)
    case .heading:
      Text(block.text).font(.headline).accessibilityAddTraits(.isHeader)
    case .code:
      ScrollView(.horizontal) {
        Text(block.text).monospaced().fixedSize(horizontal: true, vertical: false)
      }
    case .quote:
      Text(block.text).padding(.leading)
    case .list(let marker):
      HStack(alignment: .firstTextBaseline) {
        Text(marker)
        Text(block.text)
      }.padding(.leading, block.isQuoted ? nil : 0)
    case .tableRow(let header):
      HStack(alignment: .top) {
        ForEach(block.cells.indices, id: \.self) { index in
          Text(block.cells[index]).frame(maxWidth: .infinity, alignment: .leading)
        }
      }.font(header ? .headline : .body)
    }
  }
}

struct AgentChatTimelineItem: Identifiable {
  let messages: [AgentChatMessage]
  let showsSpeaker: Bool
  var id: String { messages[0].id }
  var isProcess: Bool { Self.isProcess(messages[0]) }
  static func isProcess(_ message: AgentChatMessage) -> Bool {
    message.role == .operation || message.phase == .commentary || message.plan != nil
  }

  static func group(_ messages: [AgentChatMessage]) -> [Self] {
    var items: [Self] = []
    for message in messages {
      if Self.isProcess(message), items.last?.isProcess == true, items.last?.messages.last?.turnID == message.turnID {
        let previous = items.removeLast()
        items.append(.init(messages: previous.messages + [message], showsSpeaker: false))
      } else {
        items.append(
          .init(
            messages: [message],
            showsSpeaker: message.role != .assistant
              || items.last?.messages.last?.role != .assistant))
      }
    }
    return items
  }
}
