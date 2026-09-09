import ScholiumContracts
import SwiftUI

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
            if let error { Text(verbatim: error).textSelection(.enabled) }
            if error == nil && !messages.contains(where: { $0.activity != nil }) {
              Text("No diagnostic records").foregroundStyle(.secondary)
            }
            ForEach(messages.filter { $0.activity != nil }) { message in
              if let activity = message.activity {
                DisclosureGroup(isExpanded: .init(get: { expanded.contains(message.id) }, set: { value in
                  if value { expanded.insert(message.id) } else { expanded.remove(message.id) }
                })) {
                  AgentChatActivityDetails(activity: activity)
                } label: {
                  Text(AgentChatActivityProjection.summary(activity, locale: locale))
                }
                .id(message.id)
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { if let selectedID { expanded.insert(selectedID); proxy.scrollTo(selectedID, anchor: .top) } }
      }
    }
    .padding(16).frame(width: 440, height: 420)
    .font(.callout).tint(nil as Color?)
  }

}
