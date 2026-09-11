import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Runtime research questions")
struct CodexChatQuestionsTests {
    @Test("Question sets retain option descriptions and reject partial or ambiguous forms")
    func parsing() throws {
        let question: MCPJSONValue = .object([
            "id": .string("scope"), "question": .string("Which source?"),
            "isOther": .bool(true), "isSecret": .bool(false),
            "options": .array([
                .object(["label": .string("Primary text"), "description": .string("Use the supplied passage.")])
            ]),
        ])
        let parsed = try CodexChatQuestions.parse(["questions": .array([question])])
        #expect(parsed.count == 1 && parsed[0].allowsText && !parsed[0].isSecret)
        #expect(parsed[0].options.first?.description == "Use the supplied passage.")
        for values: [MCPJSONValue] in [[], [question, question], [question, .object([:])]] {
            #expect(throws: CodexConnectionError.self) { try CodexChatQuestions.parse(["questions": .array(values)]) }
        }
        var malformed = try #require(question.objectValue)
        malformed["options"] = .array([.object(["label": .string("Missing description")])])
        #expect(throws: CodexConnectionError.self) { try CodexChatQuestions.parse(["questions": .array([.object(malformed)])]) }
        malformed["options"] = .null
        #expect(try CodexChatQuestions.parse(["questions": .array([.object(malformed)])])[0].allowsText)
        malformed["isSecret"] = .string("yes")
        #expect(throws: CodexConnectionError.self) { try CodexChatQuestions.parse(["questions": .array([.object(malformed)])]) }
    }
}
