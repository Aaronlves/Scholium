import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Zotero presentation bridge")
struct ZoteroBridgeTests {
    @Test("Chat Sources retains valid Zotero locators without claiming content was read")
    func chatZoteroReferences() throws {
        let reference = try ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01", page: 12, annotationKey: "ANNO0001")
        let reply = AgentChatMessage(role: .assistant, text: "[Selected annotation](\(reference.url.absoluteString))")
        let sources = AgentChatReplySource.collect(reply.text)
        let source = try #require(sources.first)
        #expect(source.isZotero && !source.isWeb && !source.isNote)
        #expect(AgentChatReplySource.externalURL(source.url) == reference.url)
        let context = AgentChatReplySourceContext(reply: reply, history: [reply])
        if case .unrecorded = context.evidence(for: source.url) {} else { Issue.record("A locator was promoted to read evidence") }
        for raw in ["zotero://debug/", "zotero://open-pdf/library/items/ATTACH01?page=0", "file:///private/test.pdf"] {
            let url = try #require(URL(string: raw))
            #expect(AgentChatReplySource.externalURL(url) == nil)
        }
    }

}
