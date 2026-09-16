import Observation
import ScholiumContracts
import SwiftUI

/// Retained only for the selected conversation, including a visit to its list.
/// Native editor state and cancellable picker tasks stay with the mounted detail.
@MainActor @Observable
final class AgentChatDetailPresentation {
    enum ContextAnchor { case composer, conversation }
    var queueEditTarget: AgentChatQueueEditTarget?
    var showsTurns = false
    var transcriptIsScrolling = false
    var arrivalBaseline: Set<String>?
    var showsFiles = false
    var showsAgents = false
    var contextAnchor: ContextAnchor?
    var completion = AgentChatComposerCompletion()
    var notePickerTarget: AgentChatNotePicker.Target?
    var pdfPagesTarget: AgentChatPDFPagesView.Target?
    var comparisonRequest: AgentChatApproval?
    var inspectedAgent: AgentChatChildController?
    var showsFind = false
    var find = AgentChatFindState()
    var findFocusRequest: UUID?
    var messageIsFocused = false
}

/// Resolve identity before mounting the page, so its first appearance never
/// initializes presentation belonging to the previous conversation.
@MainActor
final class AgentChatDetailPresentationStore {
    private var conversationID: UUID?
    private var current = AgentChatDetailPresentation()

    func presentation(for id: UUID?) -> AgentChatDetailPresentation {
        if conversationID != id {
            conversationID = id
            current = AgentChatDetailPresentation()
        }
        return current
    }
}
