import SwiftUI

/// Owns inspection navigation only; conversations retain every adjustment draft.
struct AgentChatChildInspector: View {
  let child: AgentChatChildController
  let openReference: (URL) -> Bool
  @Environment(\.dismiss) private var dismiss
  @State private var path: [Destination] = []

  private struct Destination: Hashable {
    let id: UUID
    let child: AgentChatChildController
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
  }

  var body: some View {
    NavigationStack(path: $path) {
      detail(child)
        .navigationDestination(for: Destination.self) { detail($0.child) }
    }
    .tint(nil as Color?)
    .onChange(of: path) { previous, current in
      for destination in previous where !current.contains(destination) { destination.child.cancel() }
    }
    .onDisappear {
      child.cancel()
      for destination in path { destination.child.cancel() }
    }
  }

  private func detail(_ current: AgentChatChildController) -> some View {
    AgentChatChildView(child: current, openReference: openReference,
      openAgent: { target, message in
        guard let next = current.reportedAgent(targetID: target, messageID: message) else { return }
        if target == current.parentID {
          next.cancel()
          current.openParent()
          dismiss()
        } else if target == child.childID {
          next.cancel()
          path.removeAll()
          child.refresh()
        } else if let index = path.firstIndex(where: { $0.child.childID == target }) {
          next.cancel()
          path = Array(path.prefix(through: index))
          path[index].child.refresh()
        } else {
          path.append(.init(id: next.id, child: next))
        }
      }, close: { dismiss() })
  }
}
