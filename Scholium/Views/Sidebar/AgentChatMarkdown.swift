import AppKit
import Foundation
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
    var language: String? = nil

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
            let language = components.compactMap { component -> String? in
                if case .codeBlock(let hint) = component.kind { return hint }
                return nil
            }.first
            blocks.append(
                .init(
                    id: id, kind: kind, text: text,
                    isQuoted: components.contains { $0.kind == .blockQuote }, language: language))
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
        AgentChatReadReply(source: text, quote: quoteSelection, openLink: { openURL($0) }, fitsContent: !expandsToFillWidth)
            .font(ScholiumChatAppearance.messageFont)
            .foregroundStyle(ScholiumChatAppearance.messageForeground)
            .frame(maxWidth: expandsToFillWidth ? .infinity : nil, alignment: .leading)
    }

}

struct AgentChatTimelineItem: Identifiable {
    let messages: [AgentChatMessage]
    var id: String { messages[0].id }
    var isProcess: Bool { Self.isProcess(messages[0]) }
    static func activeActivityID(in history: [AgentChatMessage], turnID: String?) -> String? {
        guard let turnID else { return nil }
        return history.last { $0.turnID == turnID && $0.activity?.status == .running }?.id
    }
    func carriesTurnStatus(in history: [AgentChatMessage]) -> Bool {
        guard let turn = messages.first?.turnID else { return false }
        // A turn can stop before producing any Agent item; retain its status below the request.
        let anchor =
            history.first { $0.turnID == turn && $0.role != .user }
            ?? history.last { $0.turnID == turn && $0.role == .user }
        return anchor?.id == id
    }
    static func isProcess(_ message: AgentChatMessage) -> Bool {
        message.role == .operation || message.phase == .commentary || message.plan != nil
    }

    static func group(_ messages: [AgentChatMessage]) -> [Self] {
        var items: [Self] = []
        for message in messages {
            if Self.isProcess(message), items.last?.isProcess == true, items.last?.messages.last?.turnID == message.turnID {
                let previous = items.removeLast()
                items.append(.init(messages: previous.messages + [message]))
            } else {
                items.append(
                    .init(messages: [message]))
            }
        }
        return items
    }
}
