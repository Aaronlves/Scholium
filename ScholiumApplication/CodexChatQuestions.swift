import Foundation
import ScholiumContracts

public enum CodexChatQuestions {
    public static func parse(_ params: [String: MCPJSONValue]) throws -> [AgentChatQuestion] {
        guard let values = params["questions"]?.arrayValue, (1...16).contains(values.count) else {
            throw CodexConnectionError.invalidMessage
        }
        var ids: Set<String> = []
        return try values.map { value in
            guard let object = value.objectValue, let id = object["id"]?.stringValue, !id.isEmpty,
                ids.insert(id).inserted, let prompt = object["question"]?.stringValue,
                !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw CodexConnectionError.invalidMessage }
            let optionValues: [MCPJSONValue]
            if object["options"] == nil || object["options"] == .null {
                optionValues = []
            } else if let array = object["options"]?.arrayValue, array.count <= 64 {
                optionValues = array
            } else {
                throw CodexConnectionError.invalidMessage
            }
            var labels: Set<String> = []
            let options = try optionValues.map { value -> AgentChatQuestion.Option in
                guard let item = value.objectValue, let label = item["label"]?.stringValue,
                    !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, labels.insert(label).inserted,
                    let description = item["description"]?.stringValue
                else { throw CodexConnectionError.invalidMessage }
                return .init(label: label, description: description)
            }
            for key in ["isOther", "isSecret"] where object[key] != nil && object[key]?.boolValue == nil {
                throw CodexConnectionError.invalidMessage
            }
            return .init(
                id: id, prompt: prompt, options: options,
                allowsOther: object["isOther"]?.boolValue ?? false, isSecret: object["isSecret"]?.boolValue ?? false)
        }
    }
}
