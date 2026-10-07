import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Source-derived Document citation notices", .serialized)
@MainActor
struct DocumentCitationPresentationTests {
    enum SourceCase: String, CaseIterable, Sendable {
        case stale, reordered, missingField, removedAll, duplicate, malformed, fresh, ordinary

        var integrity: DocumentCitationPresentation.Integrity? {
            switch self {
            case .stale, .reordered, .missingField, .removedAll: .stale
            case .duplicate, .malformed: .unresolved
            case .fresh, .ordinary: nil
            }
        }
    }

    @Test("Cold Review diagnoses committed source without allocating an editor", arguments: SourceCase.allCases)
    func coldReviewUsesCommittedSource(_ sourceCase: SourceCase) throws {
        let source = try source(for: sourceCase)
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: source)
        let session = DocumentSessionModel(key: nil)
        // A retained buffer from another projection must not become Review authority.
        session.editingSource = try self.source(for: .malformed)

        let notice = session.citationPresentation(committedDocument: document, editingIsAvailable: true)

        #expect(notice.integrity == sourceCase.integrity)
        #expect(notice.isVisible == (sourceCase.integrity != nil))
        #expect(!notice.canRefresh)
        #expect(notice.canOpenSource == (sourceCase.integrity != nil))
        #expect(session.presentationMode == .read)
        #expect(!session.retainsEditorSurface)
        #expect(!session.editorSession.hasAttachedWebView)
        #expect(session.editorSession.documentID.isEmpty)
        #expect(document.rawContent.utf8.elementsEqual(source.utf8))
    }

    @Test("Edit uses the exact checked buffer and returning to Review restores committed-source authority")
    func editThenReviewChangesSourceOwner() throws {
        let committedSource = try source(for: .fresh)
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: committedSource)
        let session = DocumentSessionModel(key: nil)
        let editor = session.editorSession
        session.editingSource = committedSource
        editor.loadDocument(committedSource, documentID: editor.bridgeDocumentID, mode: .livePreview)
        session.beginEditing(in: .livePreview)
        let replacement = try source(for: .reordered)
        #expect(
            editor.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: EditorSourceOffsetMap(source: committedSource).editorUTF16Length,
                        insert: replacement.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: replacement)
                ],
                baseGeneration: 0, resultingGeneration: 1))

        #expect(session.editingSource == committedSource)
        #expect(editor.checkedSource.utf8.elementsEqual(replacement.utf8))
        #expect(session.citationPresentation(committedDocument: document, editingIsAvailable: true).integrity == .stale)
        session.finishEditing()
        #expect(session.citationPresentation(committedDocument: document, editingIsAvailable: true).integrity == nil)

        // A newer committed revision remains visible even while the retained
        // editor buffer still contains the earlier ordered field sequence.
        let nextDocument = NoteDocument(relativePath: document.relativePath, rawContent: try source(for: .duplicate))
        #expect(session.citationPresentation(committedDocument: nextDocument, editingIsAvailable: true).integrity == .unresolved)
        #expect(editor.checkedSource.utf8.elementsEqual(replacement.utf8))
        #expect(!editor.hasAttachedWebView)
    }

    @Test("Composition, Review handoff, and unavailable editing revoke notice actions even with retained command availability")
    func workspaceRepairActionsFollowSessionGuards() throws {
        let exact = try source(for: .stale)
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: exact)
        let session = DocumentSessionModel(key: nil)
        let editor = session.editorSession
        editor.loadDocument(exact, documentID: editor.bridgeDocumentID, mode: .livePreview)
        session.beginEditing(in: .livePreview)
        setInteraction(editor, composing: false)
        var notice = session.citationPresentation(committedDocument: document, editingIsAvailable: true)
        #expect(notice.canRefresh && notice.canOpenSource)

        setInteraction(editor, composing: true)
        #expect(editor.interactionAvailability?.availableCommands.contains(.refreshCitations) == true)
        notice = session.citationPresentation(committedDocument: document, editingIsAvailable: true)
        #expect(notice.integrity == .stale && !notice.canRefresh && !notice.canOpenSource)
        setInteraction(editor, composing: false)
        session.returnToReadAfterSave = true
        notice = session.citationPresentation(committedDocument: document, editingIsAvailable: true)
        #expect(!notice.canRefresh && !notice.canOpenSource)
        session.returnToReadAfterSave = false
        notice = session.citationPresentation(committedDocument: document, editingIsAvailable: false)
        #expect(!notice.canRefresh && !notice.canOpenSource)
        session.switchEditorMode(to: .source)
        notice = session.citationPresentation(committedDocument: document, editingIsAvailable: true)
        #expect(notice.canRefresh && !notice.canOpenSource)
        #expect(editor.checkedSource.utf8.elementsEqual(exact.utf8))
    }

    @Test("Cold external Review diagnoses every integrity case without allocating an editor", arguments: SourceCase.allCases)
    func coldExternalReview(_ sourceCase: SourceCase) async throws {
        try await withExternalSource(try source(for: sourceCase)) { url, exact in
            let model = ExternalMarkdownWindowModel(url: url)
            defer { model.close() }
            #expect(model.citationPresentation == nil)
            await model.open()
            let notice = try #require(model.citationPresentation)

            #expect(notice.integrity == sourceCase.integrity)
            #expect(!notice.canRefresh)
            #expect(notice.canOpenSource == (sourceCase.integrity != nil))
            #expect(model.mode == .read)
            #expect(!model.retainsEditor)
            #expect(!model.editorSession.hasAttachedWebView)
            #expect(model.editorSession.documentID.isEmpty)
            #expect(model.snapshot?.source.utf8.elementsEqual(exact.utf8) == true)
            #expect(try Data(contentsOf: url) == Data(exact.utf8))
        }
    }

    @Test("External ownership keeps repair read-only until the existing ownership route permits Source", arguments: [false, true])
    func readonlyExternalRepairAvailability(managed: Bool) async throws {
        try await withExternalSource(try source(for: .duplicate)) { url, exact in
            let model = ExternalMarkdownWindowModel(url: url, needsOwnershipResolution: true)
            defer { model.close() }
            await model.open()
            try await waitUntilIdle(model)
            if managed {
                try #require(model.canRetryOwnership)
                await model.retryOwnership {
                    .managed(
                        .init(vaultID: UUID(), vaultName: "Synthetic Works", vaultRole: .draftProject, relativePath: "Synthetic.md"),
                        triptychID: UUID())
                }
                try await waitUntilIdle(model)
            }
            let readonly = try #require(model.citationPresentation)
            #expect(readonly.integrity == .unresolved && readonly.isVisible)
            #expect(!readonly.canRefresh && !readonly.canOpenSource)
            model.selectMode(.source)
            #expect(model.mode == .read && !model.retainsEditor)
            #expect(!model.editorSession.hasAttachedWebView)
            #expect(model.editorSession.documentID.isEmpty)
            #expect(try Data(contentsOf: url) == Data(exact.utf8))

            if !managed {
                // The explicit existing ownership recovery authorizes editing;
                // merely deriving a citation notice never resolves ownership.
                try #require(model.canRetryOwnership)
                await model.retryOwnership { .external }
                try await waitUntilIdle(model)
                #expect(model.citationPresentation?.canOpenSource == true)
                model.selectMode(.source)
                #expect(model.mode == .source && model.retainsEditor)
                #expect(model.citationPresentation?.canOpenSource == false)
                #expect(try Data(contentsOf: url) == Data(exact.utf8))
            }
        }
    }

    @Test("External Edit uses its exact buffer and composition revokes both repair actions")
    func externalEditActionsAndExactSource() async throws {
        try await withExternalSource(try source(for: .fresh)) { url, exact in
            let model = ExternalMarkdownWindowModel(url: url)
            defer { model.close() }
            await model.open()
            model.selectMode(.livePreview)
            let editor = model.editorSession
            let liveSource = try source(for: .stale)
            editor.loadDocument(liveSource, documentID: model.documentID, mode: .livePreview)
            setInteraction(editor, composing: false)
            var notice = try #require(model.citationPresentation)
            #expect(notice.integrity == .stale && notice.canRefresh && notice.canOpenSource)
            setInteraction(editor, composing: true)
            notice = try #require(model.citationPresentation)
            #expect(notice.integrity == .stale && !notice.canRefresh && !notice.canOpenSource)
            model.selectMode(.source)
            #expect(model.mode == .livePreview)
            setInteraction(editor, composing: false)
            model.selectMode(.source)
            #expect(model.mode == .source)
            #expect(model.citationPresentation?.canOpenSource == false)
            #expect(editor.checkedSource.utf8.elementsEqual(liveSource.utf8))
            #expect(model.snapshot?.source.utf8.elementsEqual(exact.utf8) == true)
            #expect(try Data(contentsOf: url) == Data(exact.utf8))
        }
    }

    @Test(
        "Native citation notices fit the narrow Document stack and retain their repair-action rendering",
        .enabled(if: ScholiumTestEnvironment.providesDisplayEvidence), arguments: [false, true])
    func nativeNoticeRendering(unresolvedReadonly: Bool) async throws {
        _ = NSApplication.shared
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: try source(for: unresolvedReadonly ? .duplicate : .stale))
        let presentation = DocumentCitationPresentation(
            document: document, status: nil, canRefresh: false, canOpenSource: !unresolvedReadonly)
        var noticeFrame = CGRect.zero
        let host = NSHostingView(
            rootView:
                ScholiumDocumentNoticeStack(availableSize: .init(width: 320, height: 480)) {
                    DocumentCitationNotice(presentation: presentation, dismiss: {}, refresh: {}, openSource: {})
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("citationNoticeFixture")) }) {
                            noticeFrame = $0
                        }
                }
                .coordinateSpace(name: "citationNoticeFixture")
                .environment(\.colorScheme, unresolvedReadonly ? .dark : .light))
        host.sizingOptions = []
        host.frame = .init(x: 0, y: 0, width: 320, height: 480)
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        window.orderFront(nil)
        #expect(window.isVisible)
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(noticeFrame.width > 0 && noticeFrame.height >= 40)
        #expect(noticeFrame.height <= 240)
        #expect(host.bounds.insetBy(dx: -1, dy: -1).contains(noticeFrame))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/citation-p2-repairs/notice-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(unresolvedReadonly ? "unresolved-readonly.png" : "stale-editable.png"))
    }

    private let code = #"ITEM CSL_CITATION {"citationItems":[{"id":"http://zotero.org/users/1/items/ABCDEFGH"}],"properties":{"plainCitation":"Synthetic"}}"#

    private func source(for sourceCase: SourceCase) throws -> String {
        let a = try citation(id: "synthetic_a", fallback: "Synthetic A")
        let b = try citation(id: "synthetic_b", fallback: "Synthetic B")
        let marker = try documentState(ids: ["synthetic_a", "synthetic_b"])
        let prefix = "\u{FEFF}---\r\nunknown: 'keep' # fixture\r\n---\r\n\r\n"
        let body: String =
            switch sourceCase {
            case .stale: a
            case .reordered: "\(b) \(a)\r\n\r\n\(marker)"
            case .missingField: "\(a)\r\n\r\n\(marker)"
            case .removedAll: marker
            case .duplicate: "\(a) \(a)\r\n\r\n\(marker)"
            case .malformed: "[Synthetic](scholium-zotero:1:AAAA)"
            case .fresh: "\(a) \(b)\r\n\r\n\(marker)"
            case .ordinary: "An ordinary synthetic document."
            }
        return prefix + body + "\r\n尾 😀 e\u{301} without final newline"
    }

    private func citation(id: String, fallback: String) throws -> String {
        "[\(fallback)](scholium-zotero:1:\(try encoded(["id": id, "kind": "citation", "code": code, "text": fallback])))"
    }

    private func documentState(ids: [String]) throws -> String {
        let payload: [String: Any] = ["data": "<data>synthetic vendor document</data>", "acceptedFields": ids.map { ["id": $0, "code": code] }]
        return "<!--scholium-zotero-document:1:\(try encoded(payload))-->"
    }

    private func encoded(_ value: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]).base64EncodedString()
    }

    private func setInteraction(_ editor: MarkdownEditorSession, composing: Bool) {
        let selections = [MarkdownEditorSelectionRange(anchor: 0, head: 0)]
        editor.updateInteraction(
            selections: selections, line: 1, column: 1, lineCount: 1, documentVersion: editor.generation,
            context: .init(
                selections: selections, activeInlineConstructs: [], activeBlockConstructs: [], tablePosition: nil,
                composing: composing, availableCommands: [.refreshCitations], undoLabel: nil, redoLabel: nil))
    }

    private func withExternalSource(_ source: String, operation: @MainActor (URL, String) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/citation-p2-repairs/notice-fixtures/\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Synthetic.markdown")
        try Data(source.utf8).write(to: url)
        try await operation(url, source)
    }

    private func waitUntilIdle(_ model: ExternalMarkdownWindowModel) async throws {
        try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
            // Opening queues the existing filesystem observation refresh.
            // Let it enter its operation before testing command availability.
            await Task.yield()
            await Task.yield()
            while model.isBusy { await Task.yield() }
        }
    }

}
