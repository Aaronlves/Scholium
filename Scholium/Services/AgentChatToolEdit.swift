import Foundation
import ScholiumContracts

/// An unsaved native form and its immutable runtime configuration revision.
struct AgentChatToolEdit: Identifiable {
  let id = UUID()
  let home: URL
  let originalName: String?
  let revision: String
  let needsAccessConfirmation: @Sendable (AgentChatToolConnection) -> Bool
  var connection: AgentChatToolConnection
  var reuseAccessSettings = false
  var requiresAccessConfirmation: Bool {
    needsAccessConfirmation(connection)
  }
}
