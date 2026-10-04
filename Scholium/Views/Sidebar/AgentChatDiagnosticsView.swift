import ScholiumContracts
import SwiftUI

struct AgentChatDiagnosticsPresentation: Equatable {
    enum Anchor: Equatable {
        case connectionStatus(UUID)
        case conversationOptions
        case activityMessage(String)
    }

    let anchor: Anchor
    var selectedID: String? = nil
    var error: String? = nil

    static func binding(_ presentation: Binding<Self?>, at anchor: Anchor) -> Binding<Bool> {
        Binding(
            get: { presentation.wrappedValue?.anchor == anchor },
            set: { isPresented in
                guard !isPresented, presentation.wrappedValue?.anchor == anchor else { return }
                presentation.wrappedValue = nil
            })
    }

    static func dismiss(_ presentation: Binding<Self?>, at anchor: Anchor) {
        guard presentation.wrappedValue?.anchor == anchor else { return }
        presentation.wrappedValue = nil
    }
}

struct AgentChatDiagnosticsPopover: View {
    @ObservedObject var controller: AgentChatController
    let presentation: AgentChatDiagnosticsPresentation
    let close: () -> Void

    var body: some View {
        AgentChatDiagnosticsView(
            messages: controller.selected?.messages ?? [], selectedID: presentation.selectedID,
            error: presentation.error ?? controller.error, close: close)
    }
}

struct AgentChatDiagnosticsButton: View {
    @ObservedObject var controller: AgentChatController
    @Binding var presentation: AgentChatDiagnosticsPresentation?
    let error: String
    @State private var anchorID = UUID()

    private var anchor: AgentChatDiagnosticsPresentation.Anchor { .connectionStatus(anchorID) }
    private var isPresented: Binding<Bool> { AgentChatDiagnosticsPresentation.binding($presentation, at: anchor) }

    var body: some View {
        Button("Diagnostics…") {
            presentation = .init(anchor: anchor, error: error)
        }
        .popover(isPresented: isPresented) {
            if let request = presentation, request.anchor == anchor {
                AgentChatDiagnosticsPopover(
                    controller: controller, presentation: request,
                    close: { AgentChatDiagnosticsPresentation.dismiss($presentation, at: anchor) })
            }
        }
    }
}

/// Technical evidence stays inspectable without becoming the research transcript.
struct AgentChatDiagnosticsView: View {
    let messages: [AgentChatMessage]
    let selectedID: String?
    let error: String?
    let close: () -> Void
    @State private var expanded: Set<String> = []
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostics").font(.headline)
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let error {
                            Text(verbatim: error).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if error == nil && !messages.contains(where: { $0.activity != nil }) {
                            Text("No diagnostic records").foregroundStyle(.secondary)
                        }
                        ForEach(messages.filter { $0.activity != nil }) { message in
                            if let activity = message.activity {
                                DisclosureGroup(
                                    isExpanded: .init(
                                        get: { expanded.contains(message.id) },
                                        set: { value in
                                            if value { expanded.insert(message.id) } else { expanded.remove(message.id) }
                                        })
                                ) {
                                    AgentChatActivityDetails(activity: activity)
                                } label: {
                                    Text(AgentChatActivityProjection.summary(activity, locale: locale))
                                }
                                .id(message.id)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 348)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
                .onAppear {
                    if let selectedID {
                        expanded.insert(selectedID)
                        proxy.scrollTo(selectedID, anchor: .top)
                    }
                }
            }
        }
        .padding(16).frame(width: 440)
        .font(.callout).tint(nil as Color?)
    }

}
