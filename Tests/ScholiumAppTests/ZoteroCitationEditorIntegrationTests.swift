import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Synthetic Zotero citation editor integration", .serialized)
@MainActor
struct ZoteroCitationEditorIntegrationTests {
    @Test("A synthetic HTTP transcript accepts the canonical @ receipt and one Undo restores exact source")
    func syntheticCitationAcceptsQueryAndUndoesExactSource() async throws {
        let prefix = "\u{FEFF}---\r\nunknown: 'keep' # literal\r\n---\r\n"
        let suffix = "\r\nFinal 中文 e\u{301} without newline"
        let source = prefix + "\r\nArgument 😀 @Synthetic tail." + suffix
        let queryRange = (source as NSString).range(of: "@Synthetic")
        let sourceHead = queryRange.location + queryRange.length
        let editorHead = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: sourceHead))
        let text = "(Synthetic, 2026, p. 4)"
        let html = "<i>" + text + "</i>"
        let code =
            "ITEM CSL_CITATION {\"citationID\":\"synthetic-citation\",\"citationItems\":[{\"id\":1,\"locator\":\"4\",\"label\":\"page\"}],\"properties\":{\"plainCitation\":\""
            + text + "\"}}"
        let data =
            "<data data-version=\"3\" zotero-version=\"10.0.5\"><session id=\"synthetic\"/><style id=\"synthetic-author-date\"/><prefs><pref name=\"fieldType\" value=\"Http\"/><pref name=\"noteType\" value=\"0\"/></prefs></data>"
        let transcript = SyntheticTranscript(documentData: data, code: code, html: html)
        let dispatcher = RecordingProductionDispatcher()
        let integration = ZoteroDocumentIntegration(transport: { try await transcript.send($0) })
        let session = MarkdownEditorSession(bridgeDispatcher: dispatcher, citationIntegration: integration)
        dispatcher.session = session
        await transcript.setDocumentID(session.bridgeDocumentID)
        let host = OffscreenEditor(session: session, source: source, sourceHead: sourceHead)
        defer { host.close() }
        try await waitUntil("editor loaded with captured caret", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            session.isReady && session.isLoaded && session.hasAttachedWebView
                && session.context?.selections.first?.head == editorHead
        }
        let web = try #require(session.webView)

        try await acceptCitationCompletion(in: web, diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) })
        try await waitUntil("accepted citation source after finish", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            dispatcher.citationOperations.contains {
                if case .finishCitation = $0 { return true }
                return false
            }
                && !session.checkedSource.contains("@Synthetic")
        }
        let committed = try await session.currentText(for: session.bridgeDocumentID)
        #expect(committed.utf8.elementsEqual(session.checkedSource.utf8))
        #expect(committed.hasPrefix(prefix) && committed.hasSuffix(suffix))
        let catalog = ZoteroMarkdownFields(parsing: NoteDocument(relativePath: "Synthetic.md", rawContent: committed))
        #expect(catalog.diagnostics.isEmpty)
        #expect(catalog.fields.count == 1)
        let field = try #require(catalog.fields.first)
        #expect(field.isCompleted && field.code == code && field.text == html && field.plainText == text)
        #expect(catalog.documentState?.data == data)
        #expect(!catalog.citationStateStale)
        #expect(catalog.documentState?.acceptedFields == [.init(id: field.id, code: code)])
        let reference = try #require(
            dispatcher.citationOperations.compactMap { operation -> MarkdownEditorCitationReference? in
                if case .beginCitation(_, "addEditCitation", let reference) = operation { return reference }
                return nil
            }.first)
        #expect(reference.actionID == "insertCitation" && reference.query == "Synthetic")
        #expect(reference.fromUTF16 == queryRange.location && reference.toUTF16 == sourceHead)
        #expect(reference.editorCaretUTF16Offset == editorHead)
        #expect(dispatcher.sourcesBeforeCitationOperations.allSatisfy { $0.utf8.elementsEqual(source.utf8) })
        #expect(await transcript.requestCount == 8)
        #expect(session.citationStatus == nil && session.errorMessage == nil)

        let undoHandled =
            try await web.callAsyncJavaScript(
                """
                const event = new KeyboardEvent('keydown', {key: 'z', code: 'KeyZ', keyCode: 90,
                    which: 90, metaKey: true, bubbles: true, cancelable: true});
                document.querySelector('.cm-content').dispatchEvent(event);
                return event.defaultPrevented;
                """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        #expect(undoHandled == true)
        let restored = try await session.currentText(for: session.bridgeDocumentID)
        #expect(restored.utf8.elementsEqual(source.utf8))
        #expect(session.checkedSource.utf8.elementsEqual(source.utf8))
        #expect(!ZoteroMarkdownFields(parsing: NoteDocument(relativePath: "Synthetic.md", rawContent: restored)).citationStateStale)
        await host.closeAndDrain()
    }

    @Test("Cancel revokes a completed citation while its native acceptance waits behind another command")
    func cancellationRevokesQueuedCitationAcceptance() async throws {
        let source = "\u{FEFF}Argument 😀 @Synthetic tail.\r\nFinal e\u{301}"
        let sourceHead = (source as NSString).range(of: "@Synthetic").upperBound
        let editorHead = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: sourceHead))
        let transcript = SyntheticTranscript(
            documentData: "<data><prefs><pref name=\"noteType\" value=\"0\"/></prefs></data>",
            code: "ITEM CSL_CITATION {\"citationItems\":[{\"id\":1}]}", html: "(Synthetic, 2026)")
        let dispatcher = RecordingProductionDispatcher()
        let integration = ZoteroDocumentIntegration(transport: { try await transcript.send($0) })
        let session = MarkdownEditorSession(bridgeDispatcher: dispatcher, citationIntegration: integration)
        dispatcher.session = session
        await transcript.setDocumentID(session.bridgeDocumentID)
        let host = OffscreenEditor(session: session, source: source, sourceHead: sourceHead)
        defer {
            dispatcher.releaseHeldCommand()
            host.close()
        }
        try await waitUntil("quiescent editor with captured caret", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            session.canRecycleWebView && session.context?.selections.first?.head == editorHead
        }
        let web = try #require(session.webView)
        dispatcher.holdNextEmptyPaste = true
        let unrelatedCommand = Task { try await session.perform(.pastePlain, argument: "") }
        try await waitUntil("unrelated command held", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) { dispatcher.commandIsHeld }
        try await acceptCitationCompletion(in: web, diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) })

        // No production accessor is added. With a quiescent start, exactly two
        // admitted native requests after all HTTP callbacks mean this held
        // command and the finish waiting on its sourceMutationBarrier. All
        // citation callbacks are already acknowledged, and finish has not
        // reached the production dispatcher.
        try await waitUntil("HTTP complete with native finish queued", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            await transcript.requestCount == 8 && inFlightRequestCount(session) == 2
        }
        #expect(
            !dispatcher.citationOperations.contains {
                if case .finishCitation = $0 { return true }
                return false
            })
        #expect(session.checkedSource.utf8.elementsEqual(source.utf8))
        try await session.perform(.cancelCitation)
        #expect(
            dispatcher.citationOperations.contains {
                if case .cancelCitation = $0 { return true }
                return false
            })
        let cancelNotice = ScholiumL10n.dynamicString("Citation cancelled. Finish or cancel any open Zotero dialog.")
        #expect(session.citationStatus == cancelNotice)
        dispatcher.releaseHeldCommand()
        try await unrelatedCommand.value
        try await waitUntil("native request queue drained after cancel", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            session.canRecycleWebView
        }
        #expect(
            !dispatcher.citationOperations.contains {
                if case .finishCitation = $0 { return true }
                return false
            })
        #expect(session.checkedSource.utf8.elementsEqual(source.utf8))
        #expect(try await session.currentText().utf8.elementsEqual(source.utf8))
        #expect(session.citationStatus == cancelNotice && session.errorMessage == nil)
        await host.closeAndDrain()
    }

    @Test("Late citation callbacks cannot follow a closed, moved Note into a new session at its former path")
    func departureRetargetAndFormerPathReuseRejectLateCitation() async throws {
        let vaultID = UUID()
        let noteID = UUID()
        let replacementID = UUID()
        let oldPath = "Nested/Synthetic.md"
        let movedPath = "Moved/Synthetic.md"
        let source = "\u{FEFF}Argument 😀 @Synthetic tail.\r\nExact e\u{301} without newline"
        let lateHTML = "<b>(Late callback, 2099)</b>"
        let transcript = SyntheticTranscript(
            documentData: "<data><prefs><pref name=\"noteType\" value=\"0\"/></prefs></data>",
            code: "ITEM CSL_CITATION {\"citationItems\":[{\"id\":1}]}", html: "(Synthetic, 2026)",
            holdAtRequests: [6, 7], lateHTML: lateHTML)
        let integration = ZoteroDocumentIntegration(transport: { try await transcript.send($0) })
        let dispatcher = RecordingProductionDispatcher()
        let session = MarkdownEditorSession(bridgeDispatcher: dispatcher, citationIntegration: integration)
        dispatcher.session = session
        await transcript.setDocumentID(session.bridgeDocumentID)
        let controller = DocumentController()
        let snapshot = syntheticSnapshot(vaultID: vaultID, noteID: noteID, path: oldPath, source: source)
        let original = adoptSyntheticDocument(snapshot, editor: session, into: controller)
        let documentSession = controller.session(for: original.editingTarget)
        let sourceHead = (source as NSString).range(of: "@Synthetic").upperBound
        let editorHead = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: sourceHead))
        let host = OffscreenEditor(session: session, source: source, sourceHead: sourceHead)

        // A second independent window owns a different editor but shares the
        // injected protocol client. Its busy/cancel path must not revoke the
        // first window's admitted operation.
        let foreignDispatcher = RecordingProductionDispatcher()
        let foreignBusyReply = HeldBusyReply(integration: integration)
        let foreignSession = MarkdownEditorSession(bridgeDispatcher: foreignDispatcher, citationIntegration: foreignBusyReply)
        foreignDispatcher.session = foreignSession
        let foreignController = DocumentController()
        let foreignSource = "Independent synthetic manuscript.\r\n"
        _ = adoptSyntheticDocument(
            syntheticSnapshot(
                vaultID: vaultID, noteID: UUID(),
                path: "Independent.md", source: foreignSource), editor: foreignSession, into: foreignController)
        let foreignHost = OffscreenEditor(session: foreignSession, source: foreignSource, sourceHead: foreignSource.utf16.count)
        var reopenedHost: OffscreenEditor?
        defer {
            Task {
                await transcript.releaseAllHeldResponses()
                await foreignBusyReply.release()
            }
            host.close()
            foreignHost.close()
            reopenedHost?.close()
            controller.removeAll()
            foreignController.removeAll()
        }
        try await waitUntil("independent production editors loaded", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            session.canRecycleWebView && foreignSession.canRecycleWebView
                && session.context?.selections.first?.head == editorHead
        }
        try await acceptCitationCompletion(in: try #require(session.webView), diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) })
        try await waitUntil("first remote field response held", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }) {
            await transcript.heldRequest == 6
        }
        let competingCitation = Task { try await foreignSession.perform(.insertCitation) }
        try await waitUntil(
            "second session awaits its real local busy reply", diagnostics: { await foreignHost.diagnostics(foreignDispatcher, transcript: transcript) }
        ) {
            await foreignBusyReply.isHeld
        }
        try await foreignSession.perform(.cancelCitation)
        let foreignTransactionID = try #require(
            foreignDispatcher.citationOperations.compactMap { operation -> String? in
                if case .beginCitation(let transactionID, _, _) = operation { return transactionID }
                return nil
            }.first)
        #expect(await foreignBusyReply.cancelledTransactionIDs == [foreignTransactionID])
        #expect(foreignSession.citationStatus == ScholiumL10n.dynamicString("Citation cancelled. Finish or cancel any open Zotero dialog."))
        await foreignBusyReply.release()
        do {
            try await competingCitation.value
            Issue.record("The independent session should receive local busy while the first operation is held")
        } catch {
            #expect(
                foreignSession.citationStatus
                    == ScholiumL10n.dynamicString("Zotero is handling another citation operation. Finish or cancel its open dialog, then try again."))
        }
        #expect(await transcript.requestCount == 7)
        #expect(foreignSession.checkedSource.utf8.elementsEqual(foreignSource.utf8))
        await transcript.releaseHeldResponse()
        try await waitUntil(
            "active citation survives foreign cancellation before departure", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }
        ) {
            await transcript.heldRequest == 7
        }
        #expect(
            dispatcher.citationOperations.contains {
                if case .citationCallback(_, let value) = $0 { return value.type == .setFieldText && value.html == "(Synthetic, 2026)" }
                return false
            })
        #expect(session.citationStatus == nil)
        #expect(session.checkedSource.utf8.elementsEqual(source.utf8))

        // These are the same production owners used for tab departure and
        // Note-move projection. No source, session ID or recovery state is
        // fabricated to make a late callback appear stale.
        try await controller.prepareSessionTransfer(original)
        #expect(session.detachmentSuspensionID != nil)
        let key = try #require(original.sessionKey)
        controller.migratePresentationPath(from: oldPath, to: movedPath, noteID: noteID, vaultID: vaultID)
        let moved = WindowSelectedDocument.workspace(
            WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                    relativePath: movedPath, stableNoteID: noteID.uuidString)))
        controller.updateDocumentProjection(try #require(moved.workspaceDescriptor))
        #expect(controller.selectedDocument == moved)
        #expect(controller.session(for: key) === documentSession)
        #expect(controller.relativePath(for: original.editingTarget) == movedPath)
        controller.endClosedPresentation(of: moved)
        controller.clearSelectionAfterClosingLastTab()
        await host.closeAndDrain()

        let replacementSource = "\u{FEFF}Former path reused by another Note 😀.\r\nExact e\u{301}."
        let replacement = syntheticSnapshot(vaultID: vaultID, noteID: replacementID, path: oldPath, source: replacementSource)
        controller.installOpenedDocument(replacement, vaultName: "Topics", vaultRole: .topicKnowledge)
        let reopened = try #require(controller.selectedDocument)
        let replacementSession = controller.session(for: reopened.editingTarget)
        #expect(reopened.sessionKey?.noteID == replacementID && reopened.relativePath == oldPath)
        #expect(replacementSession !== documentSession)
        #expect(replacementSession.editorSession.bridgeDocumentID != session.bridgeDocumentID)
        let replacementHost = OffscreenEditor(
            session: replacementSession.editorSession,
            source: replacementSource, sourceHead: replacementSource.utf16.count)
        reopenedHost = replacementHost
        try await waitUntil(
            "former path loaded under its new stable identity", diagnostics: { await replacementHost.diagnostics(dispatcher, transcript: transcript) }
        ) {
            replacementSession.editorSession.canRecycleWebView
        }

        await transcript.releaseHeldResponse()
        try await waitUntil(
            "late callback error-drained through remote completion", diagnostics: { await host.diagnostics(dispatcher, transcript: transcript) }
        ) {
            await transcript.requestCount == 9 && session.citationStatus != nil
        }
        #expect(await transcript.lateCallbackRejected)
        #expect(
            !dispatcher.citationOperations.contains {
                if case .finishCitation = $0 { return true }
                return false
            })
        #expect(
            !dispatcher.citationOperations.contains {
                if case .citationCallback(_, let value) = $0 { return value.type == .setFieldText && value.html == lateHTML }
                return false
            })
        #expect(session.checkedSource.utf8.elementsEqual(source.utf8))
        #expect(documentSession.editingSource.utf8.elementsEqual(source.utf8))
        #expect(replacementSession.editorSession.checkedSource.utf8.elementsEqual(replacementSource.utf8))
        #expect(try await replacementSession.editorSession.currentText().utf8.elementsEqual(replacementSource.utf8))
        #expect(foreignSession.checkedSource.utf8.elementsEqual(foreignSource.utf8))
        #expect(
            session.citationStatus
                == ScholiumL10n.dynamicString("The document changed during the citation operation. Your text was preserved; try again at the current position.")
        )
        await replacementHost.closeAndDrain()
        await foreignHost.closeAndDrain()
    }

    private func syntheticSnapshot(vaultID: UUID, noteID: UUID, path: String, source: String) -> WorkspaceNoteSnapshot {
        let document = NoteDocument(relativePath: path, rawContent: source)
        return WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
            stableIdentity: .resolved(noteID), document: document,
            fileMetadata: WorkspaceFileMetadata(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
    }

    private func adoptSyntheticDocument(
        _ snapshot: WorkspaceNoteSnapshot, editor: MarkdownEditorSession,
        into controller: DocumentController
    ) -> WindowSelectedDocument {
        let noteID = snapshot.stableIdentity.resolvedID!
        let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: noteID)
        let document = WindowSelectedDocument.workspace(
            WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: snapshot.id.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                    relativePath: snapshot.id.relativePath, stableNoteID: noteID.uuidString)))
        let session = DocumentSessionModel(key: key, editorSession: editor)
        controller.receiveSessionTransfer(
            DocumentSessionTransfer(
                document: document, session: session,
                snapshot: snapshot, mode: .livePreview))
        controller.beginEditing(
            session: session, target: document.editingTarget,
            source: snapshot.document.rawContent, revision: snapshot.fingerprint, mode: .livePreview)
        return document
    }

    private func inFlightRequestCount(_ session: MarkdownEditorSession) -> Int {
        let requests = Mirror(reflecting: session).children.first { $0.label == "inFlightRequestTasks" }?.value
        return (requests as? [UUID: Task<MarkdownEditorCommandResult, Error>])?.count ?? -1
    }

    private func acceptCitationCompletion(in web: WKWebView, diagnostics: @MainActor () async -> String) async throws {
        // Supply DOM focus without activating a native window. This proves the
        // canonical receipt and bridge/source causality, not native focus or
        // the real Zotero picker, which require separate QA.
        _ = try await web.callAsyncJavaScript(
            """
            Object.defineProperty(document, 'hasFocus', {value: () => true, configurable: true});
            const content = document.querySelector('.cm-content');
            content.focus();
            content.dispatchEvent(new KeyboardEvent('keydown', {
                key: ' ', code: 'Space', keyCode: 32, ctrlKey: true, bubbles: true, cancelable: true
            }));
            """, arguments: [:], in: nil, contentWorld: .page)
        try await waitUntil("canonical Insert Citation completion", diagnostics: diagnostics) {
            try await web.callAsyncJavaScript(
                "return Array.from(document.querySelectorAll('.cm-tooltip-autocomplete [role=option]')).some(row => row.textContent.includes('Zotero') && row.getAttribute('aria-selected') === 'true');",
                arguments: [:], in: nil, contentWorld: .page) as? Bool == true
        }
        // The installed CodeMirror autocomplete owner deliberately ignores
        // acceptance during its default 75 ms interactionDelay after opening.
        // Pace this synthetic input after a selected row, as a person would.
        try await Task.sleep(for: .milliseconds(100))
        _ = try await web.callAsyncJavaScript(
            """
            document.querySelector('.cm-content').dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true, cancelable: true
            }));
            """, arguments: [:], in: nil, contentWorld: .page)
    }

    private func waitUntil(
        _ phase: String, diagnostics: @MainActor () async -> String,
        _ condition: @MainActor () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(try await condition()) {
            guard ContinuousClock.now < deadline else {
                Issue.record(Comment(rawValue: "Synthetic citation fixture timed out at \(phase): \(await diagnostics())"))
                throw FixtureFailure.timedOut
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private enum FixtureFailure: Error { case timedOut, unexpectedRequest }

    /// The real representable owns page loading and message delivery. No window
    /// ordering, app activation, filesystem fixture or private vault is involved.
    @MainActor
    private final class OffscreenEditor {
        let session: MarkdownEditorSession
        private let window: NSWindow
        private var hostingController: NSViewController?
        private var closed = false

        init(session: MarkdownEditorSession, source: String, sourceHead: Int) {
            self.session = session
            _ = NSApplication.shared
            session.revealSourceRange(fromUTF16: sourceHead, toUTF16: sourceHead)
            let editor = MarkdownEditorWebView(
                session: session, documentID: session.bridgeDocumentID, documentTitle: "Synthetic",
                performanceDocumentID: "synthetic-citation-test", source: source, mode: .livePreview,
                presentationCSS: "", userCSS: "", requiresMathRuntime: false,
                linkCompletionQuery: { _, _ in [] }, linkPreviews: [], initialScrollFraction: 0, initialScrollAnchor: nil,
                onDocumentActivity: {}, onRequestSave: {}, onRequestFind: { _ in },
                onRequestDocumentTitleRename: { _, requested in requested }, onPasteImage: { _ in false },
                onLinkActivation: { _ in }, onScrollFractionChange: { _ in }, onScrollAnchorChange: { _ in })
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(rootView: editor)
            hosting.sizingOptions = []
            hostingController = hosting
            window.contentViewController = hosting
            window.setContentSize(NSSize(width: 720, height: 520))
            hosting.view.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
            hosting.view.autoresizingMask = [.width, .height]
            hosting.view.layoutSubtreeIfNeeded()
        }

        func close() {
            guard !closed else { return }
            closed = true
            window.contentViewController = nil
            hostingController = nil
            window.close()
        }

        func diagnostics(_ dispatcher: RecordingProductionDispatcher, transcript: SyntheticTranscript) async -> String {
            let web = session.webView
            let requestCount = await transcript.requestCount
            let domSnapshot: String
            if let web, session.isLoaded {
                domSnapshot =
                    (try? await web.callAsyncJavaScript(
                        """
                        const content = document.querySelector('.cm-content');
                        const selection = document.getSelection();
                        return JSON.stringify({hasFocus: document.hasFocus(),
                            activeTag: document.activeElement?.tagName,
                            activeClass: document.activeElement?.className,
                            contentActive: document.activeElement === content,
                            selection: {anchorOffset: selection?.anchorOffset, focusOffset: selection?.focusOffset},
                            contentRect: content?.getBoundingClientRect().toJSON(),
                            options: Array.from(document.querySelectorAll('.cm-tooltip-autocomplete [role=option]'))
                                .map(row => ({label: row.textContent, selected: row.getAttribute('aria-selected')}))});
                        """, arguments: [:], in: nil, contentWorld: .page) as? String) ?? "unavailable"
            } else {
                domSnapshot = "not loaded"
            }
            return "ready=\(session.isReady) loaded=\(session.isLoaded) attached=\(session.hasAttachedWebView) "
                + "quiescent=\(session.canRecycleWebView) composing=\(session.isComposing) generation=\(session.generation) "
                + "heads=\(session.context?.selections.map { $0.head } ?? []) error=\(session.errorMessage ?? "none") "
                + "citation=\(session.citationStatus ?? "none") hostFrame=\(hostingController?.view.frame ?? .zero) "
                + "webFrame=\(web?.frame ?? .zero) attachedWindow=\(web?.window === window) visible=\(window.isVisible) "
                + "loading=\(web?.isLoading ?? false) nativeInFlight=\(Mirror(reflecting: session).children.first { $0.label == "inFlightRequestTasks" }.map { Mirror(reflecting: $0.value).children.count } ?? -1) "
                + "bridge=\(dispatcher.operationTags.suffix(12).joined(separator: ",")) "
                + "citationOperations=\(dispatcher.citationOperations.count):\(dispatcher.citationOperations.map { String(String(describing: $0).split(separator: "(", maxSplits: 1).first ?? "unknown") }.joined(separator: ",")) "
                + "transcriptRequests=\(requestCount) DOM=\(domSnapshot)"
        }

        func closeAndDrain() async {
            close()
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while session.hasAttachedWebView, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(!session.hasAttachedWebView)
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    @MainActor
    private final class RecordingProductionDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        weak var session: MarkdownEditorSession?
        var citationOperations: [MarkdownEditorOperation] = []
        var sourcesBeforeCitationOperations: [String] = []
        var operationTags: [String] = []
        var holdNextEmptyPaste = false
        private var commandContinuation: CheckedContinuation<Void, Never>?
        var commandIsHeld: Bool { commandContinuation != nil }

        func releaseHeldCommand() {
            commandContinuation?.resume()
            commandContinuation = nil
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            operationTags.append(String(String(describing: request.operation).split(separator: "(", maxSplits: 1).first ?? "unknown"))
            if holdNextEmptyPaste, case .command(.pastePlain, .some("")) = request.operation {
                holdNextEmptyPaste = false
                await withCheckedContinuation { commandContinuation = $0 }
            }
            switch request.operation {
            case .beginCitation, .citationCallback, .finishCitation, .cancelCitation:
                citationOperations.append(request.operation)
                if let session { sourcesBeforeCitationOperations.append(session.checkedSource) }
            default: break
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }
    }

    /// Keeps only the second session's real busy reply pending so its Cancel
    /// carries a live host transaction ID into the shared production client.
    /// The HTTP protocol and busy decision still belong to that client.
    private actor HeldBusyReply: ZoteroDocumentIntegrating {
        let integration: ZoteroDocumentIntegration
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var isHeld = false
        private(set) var cancelledTransactionIDs: [String] = []

        init(integration: ZoteroDocumentIntegration) { self.integration = integration }

        func run(
            transactionID: String, command: ZoteroDocumentCommand, documentID: String,
            authority: @escaping @Sendable () async -> ZoteroDocumentAuthority,
            handler: @escaping @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
        ) async -> ZoteroDocumentIntegrationResult {
            let result = await integration.run(
                transactionID: transactionID, command: command, documentID: documentID,
                authority: authority, handler: handler)
            if result.status == .busy {
                await withCheckedContinuation {
                    isHeld = true
                    continuation = $0
                }
            }
            return result
        }

        func cancelCurrentTransaction(transactionID: String) async {
            cancelledTransactionIDs.append(transactionID)
            await integration.cancelCurrentTransaction(transactionID: transactionID)
        }

        func release() {
            continuation?.resume()
            continuation = nil
            isHeld = false
        }
    }

    /// Deterministic engine transcript: this transport cannot open a socket and
    /// does not assert behavior of Zotero's formatter or picker.
    private actor SyntheticTranscript {
        let documentData: String
        let code: String
        let html: String
        private var documentID = ""
        private var fieldID: String?
        private(set) var requestCount = 0
        private var remainingHolds: Set<Int>
        private var heldResponse: CheckedContinuation<Void, Never>?
        private(set) var heldRequest: Int?
        private let lateHTML: String?
        private(set) var lateCallbackRejected = false

        init(documentData: String, code: String, html: String, holdAtRequests: Set<Int> = [], lateHTML: String? = nil) {
            self.documentData = documentData
            self.code = code
            self.html = html
            remainingHolds = holdAtRequests
            self.lateHTML = lateHTML
        }

        func setDocumentID(_ id: String) { documentID = id }

        func releaseHeldResponse() {
            heldResponse?.resume()
            heldResponse = nil
            heldRequest = nil
        }

        func releaseAllHeldResponses() {
            remainingHolds.removeAll()
            releaseHeldResponse()
        }

        func send(_ request: URLRequest) async throws -> ZoteroDocumentHTTPResponse {
            let index = requestCount
            requestCount += 1
            let endpoint = index == 0 ? "execCommand" : "respond"
            guard request.httpMethod == "POST",
                request.url?.absoluteString == "http://127.0.0.1:23119/connector/document/\(endpoint)",
                let body = request.httpBody
            else { throw FixtureFailure.unexpectedRequest }
            let reply = try JSONDecoder().decode(MCPJSONValue.self, from: body)
            let command: String
            let arguments: [MCPJSONValue]
            switch index {
            case 0:
                guard reply == .object(["command": .string("addEditCitation"), "docId": .string(documentID)]) else { throw FixtureFailure.unexpectedRequest }
                command = "Document.canInsertField"
                arguments = [.string("Http")]
            case 1:
                guard reply == .bool(true) else { throw FixtureFailure.unexpectedRequest }
                command = "Document.setDocumentData"
                arguments = [.string(documentData)]
            case 2:
                guard reply == .null else { throw FixtureFailure.unexpectedRequest }
                command = "Document.cursorInField"
                arguments = [.string("Http")]
            case 3:
                guard reply == .null else { throw FixtureFailure.unexpectedRequest }
                command = "Document.insertField"
                arguments = [.string("Http"), .integer(0)]
            case 4:
                guard let object = reply.objectValue, let id = object["id"]?.stringValue,
                    id.hasPrefix("host_"), object["code"] == .string(""),
                    object["text"] == .string("{Citation}"), object["noteIndex"] == .integer(0)
                else { throw FixtureFailure.unexpectedRequest }
                fieldID = id
                command = "Field.setCode"
                arguments = [.string(id), .string("TEMP")]
            case 5:
                guard reply == .null, let fieldID else { throw FixtureFailure.unexpectedRequest }
                command = "Field.setCode"
                arguments = [.string(fieldID), .string(code)]
            case 6:
                guard reply == .null, let fieldID else { throw FixtureFailure.unexpectedRequest }
                command = "Field.setText"
                arguments = [.string(fieldID), .string(html), .bool(true)]
            case 7:
                guard reply == .null else { throw FixtureFailure.unexpectedRequest }
                if let lateHTML, let fieldID {
                    command = "Field.setText"
                    arguments = [.string(fieldID), .string(lateHTML), .bool(true)]
                } else {
                    command = "Document.complete"
                    arguments = []
                }
            case 8:
                guard lateHTML != nil, reply.objectValue?["error"] == .string("Tab Not Available Error") else { throw FixtureFailure.unexpectedRequest }
                lateCallbackRejected = true
                command = "Document.complete"
                arguments = []
            default: throw FixtureFailure.unexpectedRequest
            }
            let callback: MCPJSONValue = .object(["command": .string(command), "arguments": .array([.string(documentID)] + arguments)])
            if remainingHolds.remove(index) != nil {
                await withCheckedContinuation {
                    heldRequest = index
                    heldResponse = $0
                }
            }
            return .init(statusCode: 200, body: try JSONEncoder().encode(callback))
        }
    }
}
