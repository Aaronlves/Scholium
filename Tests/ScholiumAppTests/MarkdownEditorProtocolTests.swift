import Combine
import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Markdown editor protocol")
struct MarkdownEditorProtocolTests {
    @Test("Presentation CSS round trips independently from user CSS")
    func presentationCSSOperationRoundTrip() throws {
        let operation = MarkdownEditorOperation.setPresentationCSS(":root { --scale: 1.2; }")
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "setPresentationCSS")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
    }

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

    @Test("Request envelope and operation round trip with protocol version 7")
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
        #expect(object["protocolVersion"] as? Int == 7)
        let operation = try #require(object["operation"] as? [String: Any])
        #expect(operation["type"] as? String == "command")
        #expect(operation["command"] as? String == "bold")
    }

    @Test("Exact source-range reveal round trips as a nonmutating bridge operation")
    func sourceRangeRevealRoundTrip() throws {
        let operation = MarkdownEditorOperation.revealSourceRange(fromUTF16: 12, toUTF16: 19)
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "revealSourceRange")
        #expect(object["fromUTF16"] as? Int == 12)
        #expect(object["toUTF16"] as? Int == 19)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
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

    @Test("The CodeMirror protocol cannot represent Review as an editor mode")
    func reviewIsNotAnEditorMode() throws {
        let invalid = try #require(
            #"{"type":"setMode","mode":"read"}"#.data(using: .utf8)
        )
        do {
            _ = try JSONDecoder().decode(MarkdownEditorOperation.self, from: invalid)
            Issue.record("Review crossed the editor-only mode boundary.")
        } catch {
            #expect(error is DecodingError)
        }
    }

    @Test("Comment commands require a nonempty editor selection")
    func commentSelectionRequiresNonemptyRange() {
        #expect(!MarkdownEditorSelectionRange(anchor: 4, head: 4).isNonempty)
        #expect(MarkdownEditorSelectionRange(anchor: 4, head: 9).isNonempty)
        #expect(MarkdownEditorSelectionRange(anchor: 9, head: 4).isNonempty)
    }

    @Test("Selection snapshots require a nonempty bounded range set and exact identity")
    func selectionSnapshotValidation() {
        let range = MarkdownEditorSelectionRange(anchor: 2, head: 5)
        #expect(range.isValid(forEditorUTF16Length: 5))
        #expect(!MarkdownEditorSelectionRange(anchor: -1, head: 0).isValid(forEditorUTF16Length: 5))
        #expect(!MarkdownEditorSelectionRange(anchor: 0, head: 6).isValid(forEditorUTF16Length: 5))
        #expect(!markdownEditorSelectionRangesAreValid([], forEditorUTF16Length: 5))
        #expect(markdownEditorSelectionRangesAreValid([range], forEditorUTF16Length: 5))

        let snapshot = MarkdownEditorSelectionSnapshot(
            documentID: "document",
            fingerprint: "fingerprint",
            generation: 3,
            ranges: [range]
        )
        #expect(snapshot.isValid(
            documentID: "document",
            fingerprint: "fingerprint",
            generation: 3,
            editorUTF16Length: 5
        ))
        #expect(!snapshot.isValid(
            documentID: "other",
            fingerprint: "fingerprint",
            generation: 3,
            editorUTF16Length: 5
        ))
        #expect(!snapshot.isValid(
            documentID: "document",
            fingerprint: "fingerprint",
            generation: 2,
            editorUTF16Length: 5
        ))
    }

    @MainActor
    @Test("Exact cursor movement stays nonobservable until semantic availability changes")
    func cursorMovementDoesNotInvalidateSwiftUI() {
        let session = MarkdownEditorSession()
        session.loadDocument(
            String(repeating: "x", count: 2_000),
            documentID: "cursor-test",
            mode: .livePreview
        )
        let collapsed = MarkdownEditorContext(
            selections: [MarkdownEditorSelectionRange(anchor: 4, head: 4)],
            activeInlineConstructs: [],
            activeBlockConstructs: [],
            tablePosition: nil,
            composing: false,
            availableCommands: [.bold],
            undoLabel: nil,
            redoLabel: nil
        )

        var invalidationCount = 0
        let observation = session.objectWillChange.sink {
            invalidationCount += 1
        }
        session.updateInteraction(
            selections: collapsed.selections,
            line: 1,
            column: 5,
            lineCount: 20,
            documentVersion: 0,
            context: collapsed
        )
        #expect(invalidationCount == 1)

        invalidationCount = 0
        for offset in 5..<1_005 {
            session.updateInteraction(
                selections: [MarkdownEditorSelectionRange(anchor: offset, head: offset)],
                line: 2,
                column: offset,
                lineCount: 20,
                documentVersion: 0,
                context: nil
            )
        }
        let moved = [MarkdownEditorSelectionRange(anchor: 1_004, head: 1_004)]
        #expect(invalidationCount == 0)
        #expect(session.context?.selections == moved)
        #expect(session.line == 2)
        #expect(session.column == 1_004)

        let selected = MarkdownEditorContext(
            selections: [MarkdownEditorSelectionRange(anchor: 8, head: 12)],
            activeInlineConstructs: [],
            activeBlockConstructs: [],
            tablePosition: nil,
            composing: false,
            availableCommands: [.bold],
            undoLabel: nil,
            redoLabel: nil
        )
        session.updateInteraction(
            selections: selected.selections,
            line: 2,
            column: 7,
            lineCount: 20,
            documentVersion: 0,
            context: selected
        )
        #expect(invalidationCount == 1)
        #expect(session.interactionAvailability?.hasNonemptySelection == true)
        _ = observation
    }

    @MainActor
    @Test("Interaction updates reject stale generations, empty ranges, and out-of-bounds offsets")
    func interactionSelectionValidation() {
        let session = MarkdownEditorSession()
        session.loadDocument("ab\r\ncd", documentID: "selection-test", mode: .livePreview)
        let initialRange = [MarkdownEditorSelectionRange(anchor: 2, head: 2)]
        let initialContext = MarkdownEditorContext(
            selections: initialRange,
            activeInlineConstructs: [],
            activeBlockConstructs: [],
            tablePosition: nil,
            composing: false,
            availableCommands: [.bold],
            undoLabel: nil,
            redoLabel: nil
        )
        session.updateInteraction(
            selections: initialRange,
            line: 1,
            column: 3,
            lineCount: 1,
            documentVersion: 0,
            context: initialContext
        )

        session.updateInteraction(
            selections: [MarkdownEditorSelectionRange(anchor: 3, head: 3)],
            line: 1,
            column: 4,
            lineCount: 1,
            documentVersion: 1,
            context: nil
        )
        session.updateInteraction(
            selections: [],
            line: 1,
            column: 1,
            lineCount: 1,
            documentVersion: 0,
            context: nil
        )
        session.updateInteraction(
            selections: [MarkdownEditorSelectionRange(anchor: 6, head: 6)],
            line: 1,
            column: 8,
            lineCount: 1,
            documentVersion: 0,
            context: nil
        )

        #expect(session.context?.selections == initialRange)
        #expect(session.line == 1)
        #expect(session.column == 3)
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
