import Combine
import Foundation
import ScholiumContracts
import Testing
import WebKit
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

    @Test("Document title round trips as a source-neutral projection")
    func documentTitleOperationRoundTrip() throws {
        let operation = MarkdownEditorOperation.setDocumentTitle("Reasons and Emotion")
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "setDocumentTitle")
        #expect(object["value"] as? String == "Reasons and Emotion")
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

    @Test("Title focus round trips as a nonmutating bridge operation")
    func titleFocusOperationRoundTrip() throws {
        let data = try JSONEncoder().encode(MarkdownEditorOperation.focusTitle)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "focusTitle")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == .focusTitle)
    }

    @Test("Performance samples use the typed non-source diagnostic path")
    func performanceOperationRoundTrip() throws {
        let data = try JSONEncoder().encode(MarkdownEditorOperation.queryPerformance)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "queryPerformance")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == .queryPerformance)
    }

    @Test("Request envelope and operation round trip with protocol version 20")
    func requestRoundTrip() throws {
        let request = MarkdownEditorRequest(
            requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sessionID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            documentID: "analyses:Argument.md",
            startingFingerprint: String(repeating: "a", count: 64),
            knownGeneration: 7,
            operation: .command(.bold, argument: nil)
        )

        let encoded = try JSONEncoder().encode(request)
        #expect(encoded.count < markdownEditorMaximumInboundBytes)
        #expect(try JSONDecoder().decode(MarkdownEditorRequest.self, from: encoded) == request)

        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["protocolVersion"] as? Int == 20)
        let operation = try #require(object["operation"] as? [String: Any])
        #expect(operation["type"] as? String == "command")
        #expect(operation["command"] as? String == "bold")
    }

    @Test("Document find round trips and only replacements serialize source mutation")
    func documentFindRoundTrip() throws {
        let update = MarkdownEditorOperation.documentFind(DocumentFindQuery(
            query: "value",
            replacement: "replacement",
            caseSensitive: false,
            wholeWord: true,
            action: .update
        ))
        let replacement = MarkdownEditorOperation.documentFind(DocumentFindQuery(
            query: "value",
            replacement: "replacement",
            caseSensitive: false,
            wholeWord: true,
            action: .replaceAll
        ))
        let encoded = try JSONEncoder().encode(update)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: encoded) == update)
        #expect(!update.serializesSourceMutation)
        #expect(replacement.serializesSourceMutation)
    }

    @Test("Markdown comment is a typed formatting command")
    func markdownCommentCommandRoundTrip() throws {
        let operation = MarkdownEditorOperation.command(.markdownComment, argument: nil)
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "command")
        #expect(object["command"] as? String == "markdownComment")
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
    }

    @Test("Named and inline footnotes are distinct typed insertion commands")
    func footnoteInsertionCommandsRoundTrip() throws {
        for command in [
            MarkdownEditorCommand.insertFootnote,
            MarkdownEditorCommand.insertInlineFootnote,
        ] {
            let operation = MarkdownEditorOperation.command(command, argument: nil)
            let data = try JSONEncoder().encode(operation)
            let object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            #expect(object["type"] as? String == "command")
            #expect(object["command"] as? String == command.rawValue)
            #expect(
                try JSONDecoder().decode(
                    MarkdownEditorOperation.self,
                    from: data
                ) == operation
            )
        }
    }

    @Test("Image insertion is a typed, argument-bearing editor command")
    func imageInsertionCommandRoundTrip() throws {
        let argument = #"{"alt":"Figure","destination":"../Attachments/id/Figure.png"}"#
        let operation = MarkdownEditorOperation.command(.insertImage, argument: argument)
        let data = try JSONEncoder().encode(operation)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["type"] as? String == "command")
        #expect(object["command"] as? String == "insertImage")
        #expect(object["argument"] as? String == argument)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
    }

    @Test("Context-menu message carries finalized selection, mode, and viewport anchor")
    func contextMenuMessageDecoding() throws {
        let data = try #require(
            """
            {
              "type": "contextMenuRequested",
              "protocolVersion": 20,
              "sessionID": "11111111-2222-3333-4444-555555555555",
              "documentID": "topics:Scope.md",
              "startingFingerprint": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "documentVersion": 3,
              "clientX": 120.5,
              "clientY": 88,
              "mode": "livePreview",
              "context": {
                "selections": [{"anchor": 4, "head": 12}],
                "activeInlineConstructs": [],
                "activeBlockConstructs": [],
                "composing": false,
                "availableCommands": ["toggleTask"]
              }
            }
            """.data(using: .utf8)
        )
        let object = try JSONSerialization.jsonObject(with: data)
        let decoded = try #require(EditorBridgeMessageDecoder.decode(object))
        guard case .contextMenuRequested(let message) = decoded else {
            Issue.record("The typed bridge did not decode a context-menu request.")
            return
        }
        #expect(message.clientX == 120.5)
        #expect(message.clientY == 88)
        #expect(message.mode == .livePreview)
        #expect(message.context.selections == [
            MarkdownEditorSelectionRange(anchor: 4, head: 12)
        ])
        #expect(message.context.availableCommands == [.toggleTask])
    }

    @Test("Document title rename request is typed and bounded")
    func documentTitleRenameMessageDecoding() throws {
        let object: [String: Any] = [
            "type": "requestDocumentTitleRename",
            "protocolVersion": 20,
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "documentID": "topics:Scope.md",
            "startingFingerprint": String(repeating: "a", count: 64),
            "documentVersion": 3,
            "requestID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "expectedTitle": "Scope",
            "requestedTitle": "Normative Scope",
        ]
        let decoded = try #require(EditorBridgeMessageDecoder.decode(object))
        guard case .requestDocumentTitleRename(let message) = decoded else {
            Issue.record("The typed bridge did not decode a title rename request.")
            return
        }
        #expect(message.expectedTitle == "Scope")
        #expect(message.requestedTitle == "Normative Scope")

        var malformed = object
        malformed["requestedTitle"] = String(repeating: "x", count: 1_025)
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
        malformed = object
        malformed["requestID"] = "not-a-uuid"
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
        malformed = object
        malformed["legacyPath"] = "Topics/Scope.md"
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
    }

    @Test("Inbound bridge rejects unknown, stale-version, and extra-field messages")
    func inboundBridgeRejectsUnrecognizedContracts() {
        let envelope: [String: Any] = [
            "protocolVersion": 20,
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "documentID": "session-document",
            "startingFingerprint": String(repeating: "a", count: 64),
            "documentVersion": 3,
        ]
        #expect(EditorBridgeMessageDecoder.decode(envelope.merging([
            "type": "unknown",
        ]) { _, next in next }) == nil)
        #expect(EditorBridgeMessageDecoder.decode(envelope.merging([
            "type": "requestSave",
            "protocolVersion": 14,
        ]) { _, next in next }) == nil)
        #expect(EditorBridgeMessageDecoder.decode(envelope.merging([
            "type": "requestSave",
            "legacyDirty": true,
        ]) { _, next in next }) == nil)
        #expect(EditorBridgeMessageDecoder.decode([
            "type": "editorError",
            "message": "unbound",
        ]) == nil)
        #expect(EditorBridgeMessageDecoder.decode(envelope.merging([
            "type": "editorError",
            "message": "invalid",
            "legacyFailure": true,
        ]) { _, next in next }) == nil)
    }

    @Test("Interaction messages carry only a typed document focus target")
    func interactionFocusTargetDecoding() throws {
        let envelope: [String: Any] = [
            "type": "interactionChanged",
            "protocolVersion": 20,
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "documentID": "session-document",
            "startingFingerprint": String(repeating: "a", count: 64),
            "documentVersion": 3,
            "selections": [["anchor": 4, "head": 4]],
            "line": 1,
            "column": 5,
            "lineCount": 1,
            "focusTarget": "title",
        ]
        let decoded = try #require(EditorBridgeMessageDecoder.decode(envelope))
        guard case .interactionChanged(let message) = decoded else {
            Issue.record("The typed bridge did not decode an interaction message.")
            return
        }
        #expect(message.focusTarget == .title)

        var malformed = envelope
        malformed["focusTarget"] = "sidebar"
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
    }

    @Test("High-frequency deltas use the shared typed envelope and bounds")
    func inboundDeltaUsesTypedDirectDecoder() throws {
        let object: [String: Any] = [
            "type": "documentChanged",
            "protocolVersion": 20,
            "sessionID": "11111111-2222-3333-4444-555555555555",
            "documentID": "session-document",
            "startingFingerprint": String(repeating: "a", count: 64),
            "documentVersion": 4,
            "baseGeneration": 3,
            "resultingGeneration": 4,
            "changes": [["from": 1, "to": 2, "insert": "价值"]],
        ]
        let decoded = try #require(EditorBridgeMessageDecoder.decode(object))
        guard case .documentChanged(let message) = decoded else {
            Issue.record("The typed bridge did not decode a document delta.")
            return
        }
        #expect(message.envelope.documentVersion == 4)
        #expect(message.baseGeneration == 3)
        #expect(message.changes == [EditorBridgeChange(from: 1, to: 2, insert: "价值")])

        var malformed = object
        malformed["resultingGeneration"] = 5
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
        malformed = object
        malformed["changes"] = [["from": 2, "to": 1, "insert": "x"]]
        #expect(EditorBridgeMessageDecoder.decode(malformed) == nil)
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
            knownGeneration: 0,
            operation: .initialize(
                text: "\u{FEFF}---\r\ntitle: Scope\r\n---\r\nBody\r\n",
                mode: .livePreview,
                dialect: .current,
                initialSelection: MarkdownEditorSelectionRange(
                    anchor: 27,
                    head: 27
                )
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
    @Test("Editor teardown defers presentation publication until after detach")
    func editorTeardownDefersPresentationPublication() async {
        let session = MarkdownEditorSession()
        let webView = WKWebView()
        session.attach(webView)
        session.reportError("Editor teardown test")

        var invalidationCount = 0
        let observation = session.objectWillChange.sink {
            invalidationCount += 1
        }
        invalidationCount = 0

        session.detach(webView)

        #expect(!session.hasAttachedWebView)
        #expect(session.errorMessage == "Editor teardown test")
        #expect(invalidationCount == 0)

        for _ in 0..<100 {
            if session.errorMessage == nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(session.errorMessage == nil)
        #expect(invalidationCount == 1)
        _ = observation
    }

    @MainActor
    @Test("A fast editor reattach prevents the old deferred reset")
    func editorTeardownResetDoesNotCrossReattach() async {
        let session = MarkdownEditorSession()
        let firstWebView = WKWebView()
        session.attach(firstWebView)
        session.reportError("Editor reattach test")

        var invalidationCount = 0
        let observation = session.objectWillChange.sink {
            invalidationCount += 1
        }
        invalidationCount = 0

        session.detach(firstWebView)
        let replacementWebView = WKWebView()
        session.attach(replacementWebView)

        #expect(session.webView === replacementWebView)
        #expect(session.errorMessage == nil)
        #expect(invalidationCount == 1)

        // This test does not exercise startup timeout handling. Mark the
        // replacement as ready so a contended full-suite main actor cannot
        // add an unrelated six-second startup failure to the assertion.
        session.editorBecameReady()
        invalidationCount = 0
        for _ in 0..<4 { await Task.yield() }

        #expect(session.webView === replacementWebView)
        #expect(session.errorMessage == nil)
        #expect(invalidationCount == 0)

        session.detach(replacementWebView)
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

    @MainActor
    @Test("One valid source-sized insertion is accepted by the native mirror")
    func sourceSizedInsertionUsesTheSharedEightMegabyteBoundary() {
        let session = MarkdownEditorSession()
        session.loadDocument("", documentID: "large-insertion", mode: .livePreview)
        let insertion = String(repeating: "a", count: 2_000_001)

        #expect(session.acceptEditorChanges(
            [EditorBridgeChange(from: 0, to: 0, insert: insertion)],
            baseGeneration: 0,
            resultingGeneration: 1
        ))
        #expect(session.generation == 1)
        #expect(session.checkedSource.utf8.count == insertion.utf8.count)
        #expect(session.isDirty)
    }

    @MainActor
    @Test("Context-menu selections use the unsaved checked editor generation")
    func contextMenuSelectionUsesLiveCheckedLength() {
        let session = MarkdownEditorSession()
        session.loadDocument("abc", documentID: "context-menu-live-source", mode: .livePreview)

        #expect(session.acceptEditorChanges(
            [EditorBridgeChange(from: 3, to: 3, insert: " value")],
            baseGeneration: 0,
            resultingGeneration: 1
        ))
        #expect(session.acceptsInteractionRanges(
            [MarkdownEditorSelectionRange(anchor: 9, head: 9)],
            documentVersion: 1
        ))
        #expect(!session.acceptsInteractionRanges(
            [MarkdownEditorSelectionRange(anchor: 9, head: 9)],
            documentVersion: 0
        ))
        #expect(!session.acceptsInteractionRanges(
            [MarkdownEditorSelectionRange(anchor: 10, head: 10)],
            documentVersion: 1
        ))
    }

    @MainActor
    @Test("Editor navigation allows only the main in-memory document")
    func editorNavigationRemainsLocal() {
        #expect(MarkdownEditorWebView.Coordinator.navigationPolicy(
            url: URL(string: "about:blank"),
            isMainFrame: true
        ) == .allow)
        #expect(MarkdownEditorWebView.Coordinator.navigationPolicy(
            url: URL(string: "https://example.test/redirect"),
            isMainFrame: true
        ) == .cancel)
        #expect(MarkdownEditorWebView.Coordinator.navigationPolicy(
            url: URL(string: "about:blank"),
            isMainFrame: false
        ) == .cancel)
    }

    @MainActor
    @Test("Editor statistics follow the unsaved selection without publishing cursor movement")
    func editorStatistics() async throws {
        let session = MarkdownEditorSession()
        let source = "Hello world 价值"
        session.loadDocument(source, documentID: "statistics-test", mode: .livePreview)
        let bodyStatistics = DocumentStatistics(
            englishWords: 2,
            chineseCharacters: 2,
            characters: 14,
            scope: .body
        )
        await waitForDocumentStatistics(session, matching: bodyStatistics)
        #expect(session.documentStatistics.englishWords == 2)
        #expect(session.documentStatistics.chineseCharacters == 2)
        #expect(session.documentStatistics.scope == .body)

        session.updateInteraction(
            selections: [MarkdownEditorSelectionRange(anchor: 12, head: 14)],
            line: 1,
            column: 15,
            lineCount: 1,
            documentVersion: 0,
            context: nil
        )
        let selectionStatistics = DocumentStatistics(
            englishWords: 0,
            chineseCharacters: 2,
            characters: 2,
            scope: .selection
        )
        await waitForDocumentStatistics(session, matching: selectionStatistics)
        #expect(session.documentStatistics == selectionStatistics)
    }

    @MainActor
    private func waitForDocumentStatistics(
        _ session: MarkdownEditorSession,
        matching expected: DocumentStatistics
    ) async {
        guard session.documentStatistics != expected else { return }
        for await statistics in session.$documentStatistics.values {
            if statistics == expected { return }
        }
    }

    @MainActor
    @Test("Detaching cancels pending editor statistics without publication")
    func editorStatisticsAreCancelledByDetach() async {
        let session = MarkdownEditorSession()
        let webView = WKWebView()
        session.attach(webView)
        session.loadDocument(
            "Hello world 价值",
            documentID: "statistics-detach-test",
            mode: .livePreview
        )

        var invalidationCount = 0
        let observation = session.objectWillChange.sink {
            invalidationCount += 1
        }
        invalidationCount = 0

        session.detach(webView)

        #expect(session.documentStatistics == .emptyBody)
        #expect(invalidationCount == 0)

        try? await Task.sleep(for: .milliseconds(180))

        #expect(session.documentStatistics == .emptyBody)
        #expect(invalidationCount == 0)
        _ = observation
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
