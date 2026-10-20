import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Markdown editor initialization protocol")
struct MarkdownEditorInitializationProtocolTests {
    private let source = "\u{FEFF}# Synthetic 中文 🦉 e\u{301}\r\n\r\n[(Author, 2020)](cite:cfixture)\r\nstandalone\rline\n"

    @Test("Initialization round-trips exact recovery and managed companion bytes in one request")
    func exactRecoveryRoundTrip() throws {
        let code = "ITEM CSL_CITATION {\"citationID\":\"synthetic-e\u{301}\",\"citationItems\":[{\"id\":1}],\"opaque\":\"é/e\u{301}/🦉\"}"
        let data = ZoteroCitationData(
            fields: [.init(id: "cfixture", kind: .citation, code: code, text: "(Author, 2020)")],
            documentData: "<data data-version=\"4\"><prefs/><opaque>e\u{301}</opaque></data>",
            acceptedFields: [.init(id: "cfixture", code: code)])
        let companion = ZoteroCitationSnapshot(
            noteID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            vaultID: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            revision: DocumentFingerprint(content: "synthetic companion preimage e\u{301}"),
            sourceFingerprint: DocumentFingerprint(content: source), data: data, status: .available)
        let stateJSON = "{\"opaque\":\"é/e\u{301}/🦉\",\"newlines\":\"\\r\\n\"}"
        let recovery = MarkdownEditorRecoverySnapshot(
            documentID: "synthetic-restoration", fingerprint: DocumentFingerprint(content: source).sha256,
            generation: 7, ranges: [.init(anchor: 0, head: 0), .init(anchor: 4, head: 9)], source: source,
            stateJSON: stateJSON, undoHistoryPreserved: true, dirty: true, focusTarget: .editor,
            undoLabel: "Undo e\u{301}", redoLabel: "Redo 中文", citationSnapshot: companion, citationData: data)
        let request = MarkdownEditorRequest(
            sessionID: UUID(), documentID: recovery.documentID, startingFingerprint: recovery.fingerprint,
            knownGeneration: 0, expiresAt: 2_000_000_000_000,
            operation: .initialize(
                text: source, mode: .livePreview, dialect: .current, initialSelection: recovery.ranges.first,
                citationSnapshot: companion, recovery: recovery, presentation: .init()))

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(MarkdownEditorRequest.self, from: encoded)
        #expect(decoded == request)
        #expect(decoded.protocolVersion == 55)
        guard case .initialize(let text, _, _, _, let baseline, let restored, _) = decoded.operation else {
            Issue.record("The recovery request did not decode as initialization.")
            return
        }
        let restoredSnapshot = try #require(restored)
        #expect(Data(text.utf8) == Data(source.utf8))
        #expect(Data(restoredSnapshot.source.utf8) == Data(source.utf8))
        #expect(Data(try #require(restoredSnapshot.stateJSON).utf8) == Data(stateJSON.utf8))
        #expect(restoredSnapshot.ranges == recovery.ranges && restoredSnapshot.generation == 7)
        #expect(baseline == companion && restoredSnapshot.citationSnapshot == companion)
        #expect(Data(try #require(restoredSnapshot.citationData?.fields.first?.code).utf8) == Data(code.utf8))
        #expect(Data(try #require(restoredSnapshot.citationData?.documentData).utf8) == Data(try #require(data.documentData).utf8))
    }

    @Test("Ordinary initialization omits recovery and keeps its bounded source-only result")
    func ordinaryInitializationAndEnvelopeBounds() throws {
        let operation = MarkdownEditorOperation.initialize(
            text: source, mode: .source, dialect: .current, initialSelection: nil, presentation: .init())
        let encoded = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["recovery"] == nil)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: encoded) == operation)
        #expect(operation.serializesSourceMutation)
        #expect(
            operation.maximumRequestEnvelopeBytes
                == markdownEditorMaximumSourceEnvelopeBytes + markdownEditorMaximumPresentationEnvelopeBytes + markdownEditorMaximumRecoveryEnvelopeBytes)
        #expect(operation.maximumResultEnvelopeBytes == markdownEditorMaximumSourceEnvelopeBytes)
        #expect(MarkdownEditorOperation.captureRecovery.maximumResultEnvelopeBytes == markdownEditorMaximumRecoveryEnvelopeBytes)
        #expect(
            MarkdownEditorOperation.suspendForDetachment(suspensionID: "synthetic").maximumResultEnvelopeBytes
                == markdownEditorMaximumRecoveryEnvelopeBytes)
    }

    @Test("The small initialization history receipt distinguishes absence, loss and preservation", arguments: [nil, false, true] as [Bool?])
    func historyReceiptRoundTrip(preserved: Bool?) throws {
        var object: [String: Any] = [
            "requestID": UUID().uuidString, "resultingGeneration": 7, "interactionRevision": 0,
            "sourceChanged": false, "selections": [["anchor": 0, "head": 0]], "text": source, "accepted": true,
        ]
        if let preserved { object["recoveryHistoryPreserved"] = preserved }
        let result = try JSONDecoder().decode(
            MarkdownEditorCommandResult.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(result.recoveryHistoryPreserved == preserved)
        #expect(result.recovery == nil)
        #expect(Data(try #require(result.text).utf8) == Data(source.utf8))
        let encoded = try JSONEncoder().encode(result)
        let roundTripped = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(roundTripped["recoveryHistoryPreserved"] as? Bool == preserved)
        #expect(roundTripped["recovery"] == nil)
        #expect(try JSONDecoder().decode(MarkdownEditorCommandResult.self, from: encoded) == result)
    }

}
