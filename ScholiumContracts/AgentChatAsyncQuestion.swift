import Foundation

/// Public, nonsecret questions delivered independently of a running turn.
public struct AgentChatAsyncQuestion: Codable, Equatable, Sendable {
  public let questions: [AgentChatQuestion]
  public var answers: [String: AgentChatQuestionAnswer] = [:]
  public var responses: [String: String] = [:]
  public var pendingMessageID: String?
  /// Researcher chose to continue after uncertain delivery; this is not a receipt.
  public var continuedAfterUncertainty = false
  public var remaining: [AgentChatQuestion] { questions.filter { responses[$0.id] == nil } }
  public var isPending: Bool { !continuedAfterUncertainty && !remaining.isEmpty }
  public init(questions: [AgentChatQuestion]) { self.questions = questions }
}

public struct AgentChatQuestionReply: Codable, Equatable, Sendable {
  public let questionItemId: String
  public let question: String
  public let answer: String
  public init(questionItemId: String, question: String, answer: String) {
    self.questionItemId = questionItemId; self.question = question; self.answer = answer
  }
}
