import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Markdown editor protocol")
struct MarkdownEditorProtocolTests {
    @Test("Request envelope and operation round trip with protocol version 2")
    func requestRoundTrip() throws {
        let request = MarkdownEditorRequest(
            requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            documentID: "analyses:Argument.md",
            startingFingerprint: String(repeating: "a", count: 64),
            expectedGeneration: 7,
            operation: .command(.bold, argument: nil)
        )

        let encoded = try JSONEncoder().encode(request)
        #expect(encoded.count < markdownEditorMaximumInboundBytes)
        #expect(try JSONDecoder().decode(MarkdownEditorRequest.self, from: encoded) == request)

        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["protocolVersion"] as? Int == 2)
        let operation = try #require(object["operation"] as? [String: Any])
        #expect(operation["type"] as? String == "command")
        #expect(operation["command"] as? String == "bold")
    }

    @Test("Initialization carries the immutable Contracts dialect")
    func initializationDialect() throws {
        let request = MarkdownEditorRequest(
            sessionID: UUID(),
            documentID: "topics:Scope.md",
            startingFingerprint: "fingerprint",
            expectedGeneration: 0,
            operation: .initialize(
                text: "\u{FEFF}---\r\ntitle: Scope\r\n---\r\nBody\r\n",
                mode: .livePreview,
                dialect: .current
            )
        )

        let decoded = try JSONDecoder().decode(
            MarkdownEditorRequest.self,
            from: JSONEncoder().encode(request)
        )
        #expect(decoded == request)
    }

    @Test("Comment commands require a nonempty editor selection")
    func commentSelectionRequiresNonemptyRange() {
        #expect(!MarkdownEditorSelectionRange(anchor: 4, head: 4).isNonempty)
        #expect(MarkdownEditorSelectionRange(anchor: 4, head: 9).isNonempty)
        #expect(MarkdownEditorSelectionRange(anchor: 9, head: 4).isNonempty)
    }
}
