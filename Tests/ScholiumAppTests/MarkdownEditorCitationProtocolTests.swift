import Foundation
import ScholiumApplication
import Testing

@testable import ScholiumApp

@Suite("Citation editor protocol")
struct MarkdownEditorCitationProtocolTests {
    private var intent: [String: Any] {
        [
            "type": "requestCitationInsertion", "protocolVersion": markdownEditorProtocolVersion,
            "sessionID": UUID().uuidString, "documentID": "synthetic-note", "startingFingerprint": "base",
            "documentVersion": 4, "actionID": "insertCitation", "requestID": UUID().uuidString,
            "query": "Author e\u{301}", "fromUTF16": 10, "toUTF16": 20, "caretUTF16Offset": 20,
            "editorCaretUTF16Offset": 19, "interactionRevision": 8,
        ]
    }

    @Test("Citation intent retains exact-source and normalized-editor coordinates separately")
    func exactIntent() throws {
        guard case .requestCitationInsertion(let message) = try #require(EditorBridgeMessageDecoder.decode(intent)) else {
            Issue.record("Citation intent was not decoded")
            return
        }
        #expect(message.reference.fromUTF16 == 10)
        #expect(message.reference.toUTF16 == 20)
        #expect(message.reference.editorCaretUTF16Offset == 19)
        #expect(message.reference.interactionRevision == 8)
        #expect(message.envelope.documentVersion == 4)
    }

    @Test("Malformed, unknown-action and stale-version citation intents are refused")
    func invalidIntents() {
        for (key, value) in [
            ("actionID", "openURL" as Any), ("requestID", "bad"), ("toUTF16", 21),
            ("fromUTF16", -1), ("interactionRevision", true), ("editorCaretUTF16Offset", -2),
            ("protocolVersion", markdownEditorProtocolVersion - 1), ("unowned", "file:///private"),
        ] {
            #expect(EditorBridgeMessageDecoder.decode(intent.merging([key: value]) { _, next in next }) == nil)
        }
    }

    @Test("Typed citation callback and response wire values preserve opaque field strings")
    func callbackRoundTrip() throws {
        let code = "ITEM CSL_CITATION {\"citationID\":\"synthetic\",\"citationItems\":[] }"
        let operation = MarkdownEditorOperation.citationCallback(
            transactionID: "citation_fixture", value: try .init(.setFieldCode(id: "host_fixture", code: code)))
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(operation)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: encoded) == operation)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["transactionID"] as? String == "citation_fixture")
        #expect((object["value"] as? [String: Any])?["code"] as? String == code)
        let reply = MarkdownEditorCitationReply.field(.init(id: "host_fixture", code: code, text: "(Author, 2020)", noteIndex: 0, adjacent: false))
        #expect(try JSONDecoder().decode(MarkdownEditorCitationReply.self, from: encoder.encode(reply)) == reply)
        #expect(reply.protocolReply == .field(.init(id: "host_fixture", code: code, text: "(Author, 2020)")))
    }

    @Test("Only final citation acceptance serializes authoritative source mutation")
    func transactionOrdering() throws {
        #expect(!MarkdownEditorOperation.beginCitation(transactionID: "citation_fixture", command: "addEditCitation", reference: nil).serializesSourceMutation)
        #expect(!MarkdownEditorOperation.citationCallback(transactionID: "citation_fixture", value: try .init(.getFields)).serializesSourceMutation)
        #expect(MarkdownEditorOperation.finishCitation(transactionID: "citation_fixture").serializesSourceMutation)
        #expect(!MarkdownEditorOperation.cancelCitation(transactionID: "citation_fixture").serializesSourceMutation)
    }

    @Test("Citation feedback does not invalidate a healthy source editor")
    @MainActor
    func citationFeedbackIsSeparate() async {
        let session = MarkdownEditorSession()
        await session.announceCitationStatus("Synthetic citation issue")
        #expect(session.citationStatus == "Synthetic citation issue")
        #expect(session.errorMessage == nil)
        session.dismissCitationStatus()
        #expect(session.citationStatus == nil)
    }

    @Test("Source citation freshness publishes independently of caret coordinates")
    func citationFreshnessAvailability() {
        var context = MarkdownEditorContext(
            selections: [.init(anchor: 0, head: 0)], activeInlineConstructs: [],
            activeBlockConstructs: [], tablePosition: nil, composing: false,
            availableCommands: [.refreshCitations], undoLabel: nil, redoLabel: nil, citationState: .current)
        let current = EditorInteractionAvailability(context: context)
        context.citationState = .stale
        let stale = EditorInteractionAvailability(context: context)
        #expect(current != stale)
        #expect(stale.context(selections: [.init(anchor: 5, head: 5)]).citationState == .stale)
    }
}
