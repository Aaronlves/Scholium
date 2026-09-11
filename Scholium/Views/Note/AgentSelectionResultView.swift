import SwiftUI

struct AgentSelectionResultView: View {
    let result: AgentSelectionResult
    let close: () -> Void
    @ObservedObject private var chat: AgentChatController
    @State private var adoptionError: String?
    @State private var adopting = false
    @State private var adopted = false
    @State private var copied = false
    init(result: AgentSelectionResult, close: @escaping () -> Void) {
        self.result = result
        self.close = close
        self.chat = result.chat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.title).font(.headline)
                Spacer()
                if chat.isBusy(in: result.conversationID) {
                    Button("Stop", systemImage: "stop") { chat.stop(in: result.conversationID) }
                        .labelStyle(.iconOnly)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let reply = result.finalReply {
                        if result.adopt != nil {
                            DisclosureGroup("Original") { Text(result.original).textSelection(.enabled) }
                            Text(reply).textSelection(.enabled)
                        } else {
                            Text(.init(reply)).textSelection(.enabled)
                        }
                    } else if chat.approvalCount(in: result.conversationID) + chat.questionCount(in: result.conversationID) > 0 {
                        Text("Continue in Chat to respond.")
                    } else if let error = chat.selectionResultError(in: result.conversationID) {
                        Text(error).textSelection(.enabled)
                    } else if chat.isBusy(in: result.conversationID) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Preparing reply…")
                        }
                    } else {
                        Text("No completed reply. Continue in Chat to review or retry.")
                    }
                    if let adoptionError { Text(adoptionError).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 300)
            HStack {
                if let reply = result.finalReply {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reply, forType: .string)
                        copied = true
                    }.labelStyle(.iconOnly)
                        .help(copied ? "Copied" : "Copy")
                    if let adopt = result.adopt {
                        Button(ScholiumL10n.string(adopted ? "Adopted" : "Adopt")) {
                            adopting = true
                            Task { @MainActor in
                                defer { adopting = false }
                                do {
                                    try await adopt(reply)
                                    adopted = true
                                    adoptionError = nil
                                } catch { adoptionError = error.localizedDescription }
                            }
                        }.disabled(adopted || adopting)
                            .accessibilityIdentifier("scholium.selectionResult.adopt")
                    }
                }
                Spacer()
                Button("Continue in Chat") {
                    close()
                    result.continueInChat()
                }
                .accessibilityIdentifier("scholium.selectionResult.continue")
            }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "scholium-note" { return result.openReference(url) ? .handled : .discarded }
                return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            }
        )
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.selectionResult")
    }
}
