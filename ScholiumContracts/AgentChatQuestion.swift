import Foundation

public struct AgentChatQuestion: Identifiable, Codable, Equatable, Sendable {
  public struct Option: Codable, Equatable, Sendable {
    public let label: String
    public let description: String
    public init(label: String, description: String) {
      self.label = label
      self.description = description
    }
  }
  public let id: String
  public let prompt: String
  public let options: [Option]
  public let allowsOther: Bool
  public let isSecret: Bool
  public var allowsText: Bool { options.isEmpty || allowsOther }
  public init(id: String, prompt: String, options: [Option], allowsOther: Bool, isSecret: Bool) {
    self.id = id
    self.prompt = prompt
    self.options = options
    self.allowsOther = allowsOther
    self.isSecret = isSecret
  }

}
