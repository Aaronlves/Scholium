import Foundation
import ScholiumContracts

extension AgentChatDelegation.State {
    func label(locale: Locale) -> String {
        let key: String.LocalizationValue
        switch self {
        case .pendingInit: key = "Starting"
        case .running: key = "In Progress"
        case .interrupted: key = "Interrupted"
        case .completed: key = "Completed"
        case .errored: key = "Failed"
        case .shutdown: key = "Closed"
        case .notFound: key = "Agent Not Found"
        }
        return ScholiumL10n.string(key, locale: locale)
    }
}
