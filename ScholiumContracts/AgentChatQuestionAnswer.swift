import Foundation

/// Ephemeral researcher input; secret values never enter the public activity projection.
public enum AgentChatQuestionAnswer: Codable, Equatable, Sendable {
    case option(String)
    case text(String)

    public func value(for question: AgentChatQuestion) -> String? {
        switch self {
        case .option(let label): question.options.contains { $0.label == label } ? label : nil
        case .text(let text): question.allowsText && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : nil
        }
    }
}
