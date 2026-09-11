import ScholiumContracts
import SwiftUI

struct AgentChatUpdateComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var controller: AgentChatController
    let requestID: UUID
    let preview: AgentNoteUpdatePreview

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: .init("Review Changes", locale: locale, bundle: .module),
            detail: preview.operation.isRecordMutation
                ? AgentChangePresentation.operationTitle(for: preview.operation) : .init("Saved Source → Proposed Source", locale: locale, bundle: .module),
            identifier: "scholium.chat.updateComparison"
        ) {
            Button {
                dismiss()
            } label: {
                Text("Done", bundle: .module)
            }.keyboardShortcut(.cancelAction)
        } content: {
            ScrollView {
                VStack(alignment: .leading) {
                    if let move = preview.movePreview {
                        Text(move.source.relativePath + " → " + move.destination.relativePath).textSelection(.enabled)
                    }
                    ForEach(preview.linkedComparisons, id: \.effect.noteID) { linked in
                        DisclosureGroup(linked.effect.source.relativePath) {
                            ExactSourceComparisonView(
                                comparison: linked.comparison,
                                startingLabel: .init("Saved Source", locale: locale, bundle: .module),
                                endingLabel: .init("Proposed Source", locale: locale, bundle: .module),
                                startingOnlyLabel: .init("Removed", locale: locale, bundle: .module),
                                endingOnlyLabel: .init("Proposed insertion", locale: locale, bundle: .module),
                                identifierPrefix: "scholium.chat.moveComparison.linked")
                        }
                    }
                    ExactSourceComparisonView(
                        comparison: preview.comparison,
                        startingLabel: .init(preview.operation.isRecordMutation ? "Before" : "Saved Source", locale: locale, bundle: .module),
                        endingLabel: .init(preview.operation.isRecordMutation ? "After" : "Proposed Source", locale: locale, bundle: .module),
                        startingOnlyLabel: .init("Removed", locale: locale, bundle: .module),
                        endingOnlyLabel: .init("Proposed insertion", locale: locale, bundle: .module),
                        identifierPrefix: "scholium.chat.updateComparison")
                }
            }
        } footer: {
            HStack {
                Text(preview.relativePath).textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    controller.answer(requestID, allow: false)
                } label: {
                    Text("Decline", bundle: .module)
                }
                Button {
                    controller.answer(requestID, allow: true)
                } label: {
                    Text("Allow Once", bundle: .module)
                }
            }.padding().disabled(!controller.isAwaitingDecision(requestID))
        }
        .onChange(of: controller.isAwaitingDecision(requestID)) { _, pending in
            if !pending { dismiss() }
        }
    }
}
