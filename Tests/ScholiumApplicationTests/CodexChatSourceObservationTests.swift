import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Public runtime source observations")
struct CodexChatSourceObservationTests {
    @Test("Only completed structured page actions record access; a search is not a full read")
    func webActions() {
        var item: [String: MCPJSONValue] = [
            "id": .string("web"), "type": .string("webSearch"),
            "query": .string("a query"), "action": .object(["type": .string("openPage"), "url": .string("https://example.org/paper")]),
        ]
        #expect(CodexChatActivity.parse(item, completed: false)?.sourceObservation == nil)
        let completed = CodexChatActivity.parse(item, completed: true)
        guard case .webAccess(let access) = completed?.sourceObservation else {
            Issue.record("Page action lost")
            return
        }
        #expect(access.action == .openPage && access.url.absoluteString == "https://example.org/paper")
        item["status"] = .string("failed")
        #expect(CodexChatActivity.parse(item, completed: true)?.sourceObservation == nil)
        item.removeValue(forKey: "status")
        item["action"] = .object(["type": .string("search"), "query": .string("a query")])
        item["results"] = .array([.object(["url": .string("https://example.org/paper")])])
        #expect(CodexChatActivity.parse(item, completed: true)?.sourceObservation == nil)
        item["action"] = .object(["type": .string("openPage"), "url": .string("file:///private/source")])
        #expect(CodexChatActivity.parse(item, completed: true)?.sourceObservation == nil)
    }
}
