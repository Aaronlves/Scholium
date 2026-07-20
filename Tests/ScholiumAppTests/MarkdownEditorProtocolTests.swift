import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Markdown editor protocol")
struct MarkdownEditorProtocolTests {
    @Test("Preview request round trips as a nonmutating bridge operation")
    func previewOperationRoundTrip() throws {
        let data = try JSONEncoder().encode(MarkdownEditorOperation.showPreview)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "showPreview")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == .showPreview)
    }

    @Test("Point-anchored preview request round trips as a nonmutating bridge operation")
    func pointAnchoredPreviewOperationRoundTrip() throws {
        let operation = MarkdownEditorOperation.showPreviewAt(x: 120.5, y: 80.25)
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "showPreviewAt")
        #expect(object["x"] as? Double == 120.5)
        #expect(object["y"] as? Double == 80.25)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
    }

    @Test("Blur request round trips as a nonmutating bridge operation")
    func blurOperationRoundTrip() throws {
        let data = try JSONEncoder().encode(MarkdownEditorOperation.blur)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "blur")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == .blur)
    }

    @Test("Performance samples use the typed non-source diagnostic path")
    func performanceOperationRoundTrip() throws {
        let data = try JSONEncoder().encode(MarkdownEditorOperation.queryPerformance)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "queryPerformance")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == .queryPerformance)
    }

    @Test("Request envelope and operation round trip with protocol version 3")
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
        #expect(object["protocolVersion"] as? Int == 3)
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

    @Test("Semantic scroll anchors are revision-bound and bounded")
    func scrollAnchorValidationAndRoundTrip() throws {
        let anchor = EditorScrollAnchor(
            sourceFingerprint: "fingerprint",
            sourceUTF16Offset: 12,
            blockUTF16LowerBound: 10,
            blockUTF16UpperBound: 20,
            relativeBlockPosition: 0.25,
            fallbackFraction: 0.6
        )
        #expect(anchor.isValid(forUTF16Length: 40))
        #expect(!EditorScrollAnchor(
            sourceFingerprint: "fingerprint",
            sourceUTF16Offset: 12,
            blockUTF16LowerBound: 10,
            blockUTF16UpperBound: 20,
            relativeBlockPosition: 1.25,
            fallbackFraction: 0.6
        ).isValid(forUTF16Length: 40))

        let wire = MarkdownEditorWireScrollAnchor(
            sourceUTF16Offset: 12,
            blockUTF16LowerBound: 10,
            blockUTF16UpperBound: 20,
            relativeBlockPosition: 0.25,
            fallbackFraction: 0.6
        )
        let operation = MarkdownEditorOperation.setScrollAnchor(wire)
        #expect(try JSONDecoder().decode(
            MarkdownEditorOperation.self,
            from: JSONEncoder().encode(operation)
        ) == operation)
    }
}
