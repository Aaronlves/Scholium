import Foundation
import ScholiumContracts

/// The runtime's structured async delivery and exact user-message reply envelope.
public enum CodexChatAsyncQuestions {
  public static func parse(_ object: [String: MCPJSONValue], id: String, text: String) throws -> [AgentChatQuestion] {
    let values: [MCPJSONValue]
    if object["questions"] == nil || object["questions"] == .null { values = [] }
    else if let array = object["questions"]?.arrayValue, array.count <= 16 { values = array }
    else { throw CodexConnectionError.invalidMessage }
    if values.isEmpty {
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CodexConnectionError.invalidMessage }
      return [.init(id: id, prompt: text, options: [], allowsOther: true, isSecret: false)]
    }
    return try values.enumerated().map { index, value in
      guard let question = value.objectValue, let title = question["title"]?.stringValue,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CodexConnectionError.invalidMessage }
      let options: [MCPJSONValue]
      if question["options"] == nil || question["options"] == .null { options = [] }
      else if let array = question["options"]?.arrayValue, array.count <= 64 { options = array }
      else { throw CodexConnectionError.invalidMessage }
      var labels = Set<String>()
      let parsed = try options.map { value -> AgentChatQuestion.Option in
        guard let label = value.stringValue, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          labels.insert(label).inserted else { throw CodexConnectionError.invalidMessage }
        return .init(label: label, description: "")
      }
      let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
      let identity: [MCPJSONValue] = [.string("request_user_input_async"), .string(id), .integer(index)]
      let key = String(decoding: try encoder.encode(identity), as: UTF8.self)
      return .init(id: key, prompt: title, options: parsed, allowsOther: true, isSecret: false)
    }
  }

  private static let opening = "<send_user_message_question_reply>\n"
  private static let closing = "\n</send_user_message_question_reply>"

  public static func encode(_ replies: [AgentChatQuestionReply]) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return opening + String(decoding: try encoder.encode(replies), as: UTF8.self) + closing
  }

  public static func decode(_ text: String) -> [AgentChatQuestionReply]? {
    guard text.hasPrefix(opening), text.hasSuffix(closing) else { return nil }
    let data = Data(text.dropFirst(opening.count).dropLast(closing.count).utf8)
    let decoder = JSONDecoder()
    return (try? decoder.decode([AgentChatQuestionReply].self, from: data))
      ?? (try? decoder.decode(AgentChatQuestionReply.self, from: data)).map { [$0] }
  }
}
