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

        let notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)

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

    @Test("Prepared committed fields preserve every notice state", arguments: SourceCase.allCases)
    func preparedCommittedFields(_ sourceCase: SourceCase) throws {
        let document = NoteDocument(relativePath: "Prepared.md", rawContent: try source(for: sourceCase))
        let fields = MarkdownSemanticDocument(parsing: document).zoteroFields
        let session = DocumentSessionModel(key: nil)
        let notice = session.citationPresentation(committedDocument: document, committedFields: fields, editingIsAvailable: true)
        #expect(notice.integrity == sourceCase.integrity)
        #expect(notice.isVisible == (sourceCase.integrity != nil))
        #expect(!session.retainsEditorSurface && !session.editorSession.hasAttachedWebView)
    }

    @Test("One-entry memo reuses a revision and rejects stale prepared fields and exact-byte source changes")
    func committedFieldsMemo() throws {
        let cache = DocumentCitationFieldsCache()
        let first = NoteDocument(relativePath: "Synthetic.md", rawContent: try source(for: .stale))
        let next = NoteDocument(relativePath: first.relativePath, rawContent: try source(for: .duplicate))
        let prepared = MarkdownSemanticDocument(parsing: first).zoteroFields
        var sourceLoads = 0
        func fields(_ document: NoteDocument, prepared: ZoteroMarkdownFields?) -> ZoteroMarkdownFields {
            cache.fields(
                relativePath: document.relativePath, sourceRevision: .committed(document.fingerprint),
                citationSnapshot: document.citationSnapshot, prepared: prepared
            ) {
                sourceLoads += 1
                return document
            }
        }
        for _ in 0..<20 { #expect(fields(first, prepared: prepared) == prepared) }
        #expect(sourceLoads == 1)
        #expect(!fields(next, prepared: prepared).diagnostics.isEmpty)
        #expect(sourceLoads == 2)

        let decomposed = NoteDocument(relativePath: next.relativePath, rawContent: next.rawContent.replacingOccurrences(of: "e\u{301}", with: "é"))
        #expect(decomposed.rawContent == next.rawContent && decomposed.fingerprint != next.fingerprint)
        #expect(fields(decomposed, prepared: nil).fingerprint == decomposed.fingerprint)
        #expect(sourceLoads == 3)
        cache.removeAll()
        _ = fields(decomposed, prepared: nil)
        #expect(sourceLoads == 4)
    }

    @Test("Companion authority participates independently and cannot admit companion-free prepared fields")
    func companionFieldsMemo() {
        let cache = DocumentCitationFieldsCache()
        let plain = NoteDocument(relativePath: "Companion.md", rawContent: "# Synthetic\nOrdinary text.\n")
        let prepared = MarkdownSemanticDocument(parsing: plain).zoteroFields
        let noteID = UUID()
        let vaultID = UUID()
        let revision = DocumentFingerprint(content: "first companion bytes")
        let nextRevision = DocumentFingerprint(content: "second companion bytes")
        let snapshots: [ZoteroCitationSnapshot?] = [
            nil,
            .init(noteID: noteID, vaultID: vaultID, revision: revision, status: .unresolved),
            .init(noteID: noteID, vaultID: vaultID, revision: nextRevision, status: .unresolved),
            .init(noteID: noteID, vaultID: vaultID, revision: nextRevision, status: .unsupported),
            .init(noteID: noteID, vaultID: vaultID, revision: nextRevision, sourceFingerprint: plain.fingerprint, status: .unsupported),
            .init(noteID: noteID, vaultID: vaultID, revision: nextRevision, data: .init(documentData: "synthetic"), status: .unsupported),
            .init(noteID: UUID(), vaultID: vaultID, revision: nextRevision, status: .unsupported),
            .init(noteID: noteID, vaultID: UUID(), revision: nextRevision, status: .unsupported),
            nil,
        ]
        var sourceLoads = 0
        for (index, snapshot) in snapshots.enumerated() {
            let document = NoteDocument(relativePath: plain.relativePath, rawContent: plain.rawContent, citationSnapshot: snapshot)
            for _ in 0..<2 {
                let fields = cache.fields(
                    relativePath: document.relativePath, sourceRevision: .committed(document.fingerprint),
                    citationSnapshot: snapshot, prepared: prepared
                ) {
                    sourceLoads += 1
                    return document
                }
                #expect(fields == ZoteroMarkdownFields(parsing: document))
                #expect((!fields.diagnostics.isEmpty) == (snapshot != nil))
            }
            #expect(sourceLoads == index + 1)
        }
    }

    @Test("Retained mirror assignments invalidate fields even for canonically equivalent text")
    func retainedMirrorMemo() throws {
        let session = DocumentSessionModel(key: nil)
        let first = try source(for: .stale)
        let next = first.replacingOccurrences(of: "e\u{301}", with: "é")
        #expect(first == next && Data(first.utf8) != Data(next.utf8))
        session.editingSource = first
        let initialRevision = session.retainedCitationSourceRevision
        let document = NoteDocument(relativePath: "Retained.md", rawContent: try source(for: .fresh))
        session.beginEditing(in: .livePreview)
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == .stale)
        var loads = 0
        func fields() -> ZoteroMarkdownFields {
            session.citationFieldsCache.fields(
                relativePath: document.relativePath, sourceRevision: .retained(session.retainedCitationSourceRevision),
                citationSnapshot: nil, prepared: nil
            ) {
                loads += 1
                return NoteDocument(relativePath: document.relativePath, rawContent: session.retainedExactSource)
            }
        }
        // The presentation call already populated this exact retained revision.
        #expect(fields().fingerprint == DocumentFingerprint(content: first))
        #expect(loads == 0)
        session.editingSource = next
        #expect(session.retainedCitationSourceRevision == initialRevision + 1)
        #expect(fields().fingerprint == DocumentFingerprint(content: next))
        #expect(loads == 1)
    }

    @Test("Malformed YAML cannot hide known companion repair in cold Review", arguments: [ZoteroCitationSnapshot.Status.unresolved, .unsupported])
    func malformedFrontmatterCompanionNotice(status: ZoteroCitationSnapshot.Status) {
        let source = "\u{FEFF}---\r\nbroken: [\r\n---\r\nReadable 😀 e\u{301} prose."
        let document = NoteDocument(
            relativePath: "Malformed.md", rawContent: source,
            citationSnapshot: .init(noteID: UUID(), vaultID: UUID(), status: status))
        let session = DocumentSessionModel(key: nil)
        #expect(document.frontmatterState == .malformed)

        let notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)

        #expect(notice.integrity == .unresolved && notice.isVisible)
        #expect(!notice.canRefresh && notice.canOpenSource)
        #expect(!session.retainsEditorSurface && !session.editorSession.hasAttachedWebView)
        #expect(document.sourceBytes == Data(source.utf8))
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
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == nil)
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
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == .stale)
        session.finishEditing()
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == nil)

        // A newer committed revision remains visible even while the retained
        // editor buffer still contains the earlier ordered field sequence.
        let nextDocument = NoteDocument(relativePath: document.relativePath, rawContent: try source(for: .duplicate))
        #expect(session.citationPresentation(committedDocument: nextDocument, committedFields: nil, editingIsAvailable: true).integrity == .unresolved)
        #expect(editor.checkedSource.utf8.elementsEqual(replacement.utf8))
        #expect(!editor.hasAttachedWebView)
    }

    @Test("An uninitialized or foreign editor leaves citation notices with the retained editing source")
    func pendingAndForeignEditorUseRetainedSource() throws {
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: try source(for: .fresh))
        let session = DocumentSessionModel(key: nil)
        session.editingSource = try source(for: .stale)
        session.beginEditing(in: .livePreview)
        let editor = session.editorSession
        #expect(editor.documentID.isEmpty)
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == .stale)

        let foreignID = UUID().uuidString
        editor.loadDocument(try source(for: .duplicate), documentID: foreignID, mode: .source)
        let foreign = try #require(editor.citationFields(forDocumentID: foreignID))
        #expect(!foreign.diagnostics.isEmpty)
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == .stale)
        session.finishEditing()
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).integrity == nil)
        #expect(session.editingSource.utf8.elementsEqual(try source(for: .stale).utf8))
    }

    @Test("Composition, Review handoff, and unavailable editing revoke notice actions even with retained command availability")
    func workspaceRepairActionsFollowSessionGuards() async throws {
        let exact = try source(for: .stale)
        let document = NoteDocument(relativePath: "Synthetic.md", rawContent: exact)
        let session = DocumentSessionModel(key: nil)
        let editor = session.editorSession
        editor.loadDocument(exact, documentID: editor.bridgeDocumentID, mode: .livePreview)
        session.beginEditing(in: .livePreview)
        setInteraction(editor, composing: false)
        var notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)
        #expect(notice.canRefresh && notice.canOpenSource)
        await editor.announceCitationStatus("Synthetic latest status")
        notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)
        #expect(notice.status == "Synthetic latest status")
        editor.dismissCitationStatus()
        #expect(session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true).status == nil)

        setInteraction(editor, composing: true)
        #expect(editor.interactionAvailability?.availableCommands.contains(.refreshCitations) == true)
        notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)
        #expect(notice.integrity == .stale && !notice.canRefresh && !notice.canOpenSource)
        setInteraction(editor, composing: false)
        session.returnToReadAfterSave = true
        notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)
        #expect(!notice.canRefresh && !notice.canOpenSource)
        session.returnToReadAfterSave = false
        notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: false)
        #expect(!notice.canRefresh && !notice.canOpenSource)
        session.switchEditorMode(to: .source)
        notice = session.citationPresentation(committedDocument: document, committedFields: nil, editingIsAvailable: true)
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
            if managed {
                try await retryOwnershipWhenAvailable(model) {
                    .managed(
                        .init(vaultID: UUID(), vaultName: "Synthetic Works", vaultRole: .draftProject, relativePath: "Synthetic.md"),
                        triptychID: UUID())
                }
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
                try await retryOwnershipWhenAvailable(model) { .external }
                try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
                    while model.isBusy {
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                    #expect(model.citationPresentation?.canOpenSource == true)
                    model.selectMode(.source)
                    #expect(model.mode == .source && model.retainsEditor)
                    #expect(model.citationPresentation?.canOpenSource == false)
                }
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
            #expect(editor.citationFields(forDocumentID: model.documentID)?.citationStateStale == true)
            // A cached foreign projection cannot enter the external source;
            // the original file snapshot still owns the unmatched fallback.
            let foreignID = UUID().uuidString
            editor.loadDocument(try source(for: .duplicate), documentID: foreignID, mode: .source)
            #expect(editor.citationFields(forDocumentID: foreignID)?.diagnostics.isEmpty == false)
            #expect(model.citationPresentation?.integrity == nil)
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
            fields: ZoteroMarkdownFields(parsing: document), status: nil, canRefresh: false, canOpenSource: !unresolvedReadonly)
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
            interactionRevision: 0,
            context: .init(
                selections: selections, activeInlineConstructs: [], activeBlockConstructs: [],
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

    private func retryOwnershipWhenAvailable(
        _ model: ExternalMarkdownWindowModel,
        using classify: @escaping @MainActor () async throws -> ExternalMarkdownOwnershipState
    ) async throws {
        try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
            // Filesystem observation may begin after an earlier idle read.
            // Admit the action in the same actor turn as its availability check.
            while !model.canRetryOwnership {
                try Task.checkCancellation()
                await Task.yield()
            }
            await model.retryOwnership(using: classify)
        }
    }

}
