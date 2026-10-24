import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Document mode lifecycle", .serialized)
@MainActor
struct ReviewModeTransitionTests {
    @Test("An unmounted Review request completes clean state and preserves dirty state", arguments: [false, true])
    func unmountedReviewPreservesSource(dirty: Bool) throws {
        let snapshot = Self.makeNote()
        let controller = DocumentController()
        controller.rememberPresentationMode(.source)
        controller.installOpenedDocument(snapshot, vaultName: "Analyses", vaultRole: .sourceCorpus)
        let selected = try #require(controller.selectedDocument)
        let session = controller.session(for: selected.editingTarget)
        defer {
            controller.removeAll()
            controller.unbind()
        }
        if dirty { session.editingSource += "Unsaved researcher thought.\r\n" }
        let before = session.editingSource
        controller.requestPresentationMode(
            .read, session: session, target: selected.editingTarget,
            source: snapshot.document.rawContent, revision: snapshot.fingerprint)
        #expect(session.reviewHandoffTask == nil && session.reviewHandoffID == nil)
        #expect(!session.returnToReadAfterSave)
        #expect(session.isEditing == dirty)
        #expect(controller.currentPresentationMode == (dirty ? .source : .read))
        #expect(session.editingSource.utf8.elementsEqual(before.utf8))
        #expect((session.editError != nil) == dirty)
        #expect(!session.editorSession.hasAttachedWebView)
    }

    @Test("Review completes through its retained owner and preserves exact source")
    func reviewOwnerCompletesHandoff() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        try await fixture.waitUntilReady()
        fixture.select(.read)
        let task = try #require(fixture.session.reviewHandoffTask)
        await task.value
        try await waitUntil {
            !fixture.session.isEditing && fixture.session.editorSession.presentedMode == .review
        }
        #expect(fixture.controller.currentPresentationMode == .read)
        #expect(fixture.session.reviewHandoffTask == nil && fixture.session.reviewHandoffID == nil)
        #expect(!fixture.session.returnToReadAfterSave && fixture.session.editError == nil)
        #expect(try await fixture.session.editorSession.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
    }

    enum Interruption: CaseIterable { case source, departure, close, unbind, removeAll }

    @Test("A cancelled Review cannot commit after its lifecycle owner departed", arguments: Interruption.allCases)
    func reviewCancellationRevokesCompletion(interruption: Interruption) async throws {
        let dispatcher = ModeBoundaryDispatcher()
        let fixture = try Fixture(dispatcher: dispatcher)
        defer {
            dispatcher.release()
            fixture.close()
        }
        try await fixture.waitUntilReady()
        dispatcher.holdNextScroll = true
        fixture.select(.read)
        let obsolete = try #require(fixture.session.reviewHandoffTask)
        try await dispatcher.waitUntilHeld()
        #expect(fixture.session.returnToReadAfterSave)
        var departure: Task<Void, Error>?
        switch interruption {
        case .source:
            fixture.select(.source)
        case .departure:
            departure = Task { @MainActor in
                try await fixture.controller.prepareSessionTransfer(fixture.document)
            }
            try await waitUntil { fixture.session.reviewHandoffID == nil }
        case .close:
            fixture.controller.endClosedPresentation(of: fixture.document)
        case .unbind:
            fixture.controller.unbind()
        case .removeAll:
            fixture.controller.removeAll(retainingSessions: true)
        }
        #expect(obsolete.isCancelled)
        #expect(fixture.session.reviewHandoffID == nil && fixture.session.reviewHandoffTask == nil)
        #expect(!fixture.session.returnToReadAfterSave)
        dispatcher.release()
        await obsolete.value
        try await departure?.value
        #expect(fixture.session.isEditing)
        #expect(fixture.controller.currentPresentationMode == .source)
        #expect(fixture.session.editingSource.utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
        #expect(fixture.session.editError == nil)
        if interruption == .source {
            try await fixture.waitUntilReady()
            #expect(try await fixture.session.editorSession.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
        }
    }

    @Test("Readiness consumes an existing mode focus intent once without recreating it")
    func modeReadinessConsumesExistingIntentOnce() async throws {
        let dispatcher = ModeBoundaryDispatcher()
        let fixture = try Fixture(dispatcher: dispatcher, initialMode: .livePreview)
        defer {
            dispatcher.release()
            fixture.close()
        }
        try await fixture.waitUntilReady(mode: .livePreview)
        dispatcher.holdNextMode = true
        fixture.select(.source)
        try await dispatcher.waitUntilHeld()
        let intent = fixture.installFocusIntent(mode: .source)
        #expect(fixture.session.editorFocusIntent?.id == intent.id)
        #expect(fixture.session.editorFocusTask == nil)
        dispatcher.release()
        try await fixture.waitUntilReady()
        try await waitUntil { fixture.session.editorFocusIntent == nil && fixture.session.editorFocusTask == nil }
        let revision = fixture.session.editorSession.focusRequestRevision
        // Readiness may consume an intent even when the test process cannot
        // deliver hardware focus. It must never manufacture its replacement.
        fixture.controller.reconcileEditorFocusIntent(for: fixture.session)
        fixture.controller.reconcileEditorFocusIntent(for: fixture.session)
        #expect(fixture.session.editorSession.focusRequestRevision == revision)
        #expect(fixture.session.editorFocusIntent == nil && fixture.session.editorFocusTask == nil)
        #expect(try await fixture.session.editorSession.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
    }

    @Test("A newer focus revision supersedes the outstanding mode focus intent")
    func modeFocusRespectsNewerFocusRevision() async throws {
        let dispatcher = ModeBoundaryDispatcher()
        let fixture = try Fixture(dispatcher: dispatcher, initialMode: .livePreview)
        defer {
            dispatcher.release()
            fixture.close()
        }
        try await fixture.waitUntilReady(mode: .livePreview)
        dispatcher.holdNextMode = true
        fixture.select(.source)
        try await dispatcher.waitUntilHeld()
        let intent = fixture.installFocusIntent(mode: .source)
        let revocation = Task { @MainActor in await fixture.session.editorSession.resignFocusAndWait() }
        try await waitUntil { fixture.session.editorSession.focusRequestRevision != intent.revision }
        let revision = fixture.session.editorSession.focusRequestRevision
        dispatcher.release()
        await revocation.value
        try await fixture.waitUntilReady()
        try await waitUntil { fixture.session.editorFocusIntent == nil && fixture.session.editorFocusTask == nil }
        #expect(fixture.session.editorSession.focusRequestRevision == revision)
        #expect(try await fixture.session.editorSession.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
    }

    @Test("Retained activation consumes its existing focus intent after input resumes")
    func retainedActivationWakesAfterResume() async throws {
        let dispatcher = ModeBoundaryDispatcher()
        let fixture = try Fixture(dispatcher: dispatcher)
        defer {
            dispatcher.release()
            fixture.close()
        }
        try await fixture.waitUntilReady()
        let editor = fixture.session.editorSession
        let webView = try #require(editor.webView)
        _ = try await editor.send(.selectAll, in: webView)
        try await fixture.controller.prepareSessionTransfer(fixture.document)
        try #require(editor.detachmentSuspensionID != nil)
        try #require(fixture.window.makeFirstResponder(fixture.window))
        dispatcher.holdNextResume = true
        try #require(fixture.controller.selectRetainedDocument(fixture.document))
        try await dispatcher.waitUntilHeld()
        let intent = fixture.installFocusIntent(mode: .source)
        fixture.controller.reconcileEditorFocusIntent(for: fixture.session)
        #expect(fixture.session.editorFocusIntent?.id == intent.id)
        #expect(fixture.session.editorFocusTask == nil)
        dispatcher.release()
        // Resume completion itself must wake the retained intent. No extra
        // Published event or test-driven reconciliation follows the release.
        try await waitUntil { fixture.session.editorFocusIntent == nil && fixture.session.editorFocusTask == nil }
        #expect(editor.detachmentSuspensionID == nil)
        #expect(try await editor.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
    }

    @Test("A failed Review retains the native context captured before its first suspension")
    func failedReviewCannotReviveNativeFocus() async throws {
        let dispatcher = ModeBoundaryDispatcher()
        let fixture = try Fixture(dispatcher: dispatcher)
        defer {
            dispatcher.release()
            fixture.close()
        }
        try await fixture.waitUntilReady()
        try #require(fixture.window.makeFirstResponder(fixture.window))
        fixture.session.beginSaveAttempt(.init(task: Task { @MainActor in throw DocumentControllerError.editorUnavailable }))
        dispatcher.holdNextScroll = true
        let focusRevision = fixture.session.editorSession.focusRequestRevision
        fixture.select(.read)
        let handoff = try #require(fixture.session.reviewHandoffTask)
        try await dispatcher.waitUntilHeld()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        dispatcher.release()
        await handoff.value
        #expect(fixture.session.isEditing && fixture.session.editError != nil)
        #expect(fixture.session.editorFocusIntent == nil && fixture.session.editorFocusTask == nil)
        // Review's blur revokes focus once. The context captured before the
        // scroll await was revoked, so failure must not authorize another turn.
        #expect(fixture.session.editorSession.focusRequestRevision == focusRevision + 1)
        #expect(fixture.window.firstResponder === fixture.window)
        #expect(try await fixture.session.editorSession.currentText().utf8.elementsEqual(fixture.snapshot.document.rawContent.utf8))
    }

    enum NativeFocusSupersession: CaseIterable {
        case responder, reusedFieldEditor, windowReactivation, applicationReactivation
    }

    @Test(
        "Mode focus context rejects a newer native interaction even when the current window is key",
        arguments: NativeFocusSupersession.allCases)
    func modeFocusRetainsNativeRevocation(_ supersession: NativeFocusSupersession) throws {
        _ = NSApplication.shared
        let window = ModeFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let editor = MarkdownEditorSession()
        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
        editor.webView = webView
        defer {
            editor.webView = nil
            window.close()
        }
        let field = FocusOriginField(frame: .zero)
        let newerField = FocusOriginField(frame: .zero)
        let fieldEditor = NSTextView(frame: .zero)
        let newerResponder = NSTextView(frame: .zero)
        fieldEditor.isFieldEditor = true
        fieldEditor.delegate = field
        let host = try #require(window.contentView)
        let views: [NSView] = [webView, field, newerField, fieldEditor, newerResponder]
        for view in views { host.addSubview(view) }
        try #require(window.makeFirstResponder(fieldEditor))
        let context = DocumentModeFocusContext(window: window, responder: window.firstResponder)
        try #require(context.permitsFocus(in: editor))
        switch supersession {
        case .responder:
            try #require(window.makeFirstResponder(newerResponder))
        case .reusedFieldEditor:
            fieldEditor.delegate = newerField
            try #require(window.firstResponder === fieldEditor)
        case .windowReactivation:
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            try #require(window.firstResponder === fieldEditor)
        case .applicationReactivation:
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            try #require(window.firstResponder === fieldEditor)
        }
        // This synthetic native window never changes its current key snapshot;
        // the context must remember the intervening departure independently.
        try #require(window.isKeyWindow)
        #expect(!context.permitsFocus(in: editor))
        #expect(!window.isVisible)
    }

    @MainActor
    private final class FocusOriginField: NSTextField, NSTextViewDelegate {}

    @MainActor
    private final class ModeFocusWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private static func makeNote() -> WorkspaceNoteSnapshot {
        let document = NoteDocument(relativePath: "Lifecycle.md", rawContent: "\u{FEFF}---\r\ntags: [draft]\r\n---\r\n\r\nExact e\u{301} 中文 🦉.\r\n")
        return WorkspaceNoteSnapshot(
            id: .init(vaultID: UUID(), relativePath: "Lifecycle.md"), stableIdentity: .resolved(UUID()),
            document: document,
            fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
            graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
    }

    private static func waitUntil(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(ready())
    }

    private func waitUntil(_ ready: () -> Bool) async throws { try await Self.waitUntil(ready) }

    @MainActor
    private final class Fixture {
        let snapshot: WorkspaceNoteSnapshot
        let document: WindowSelectedDocument
        let controller: DocumentController
        let session: DocumentSessionModel
        let window: NSWindow

        init(dispatcher: (any MarkdownEditorBridgeDispatching)? = nil, initialMode: NotePresentationMode = .source) throws {
            _ = NSApplication.shared
            snapshot = ReviewModeTransitionTests.makeNote()
            let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: try #require(snapshot.stableIdentity.resolvedID))
            document = .workspace(
                .init(
                    sessionKey: key,
                    reference: .init(
                        vaultID: key.vaultID, vaultName: "Analyses", vaultRole: .sourceCorpus,
                        relativePath: snapshot.id.relativePath, stableNoteID: key.noteID.uuidString)))
            controller = DocumentController()
            controller.rememberPresentationMode(initialMode)
            let editor = dispatcher.map { MarkdownEditorSession(bridgeDispatcher: $0) } ?? MarkdownEditorSession()
            session = DocumentSessionModel(key: key, editorSession: editor)
            controller.receiveSessionTransfer(.init(document: document, session: session, snapshot: snapshot, mode: initialMode))
            let host = NSHostingView(rootView: Presentation(controller: controller))
            host.sizingOptions = []
            window = ModeFocusWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        @discardableResult
        func installFocusIntent(mode: MarkdownEditorMode) -> DocumentEditorFocusIntent {
            let editor = session.editorSession
            let intent = DocumentEditorFocusIntent(
                mode: mode, revision: editor.focusRequestRevision,
                openingPresentationID: editor.openingPresentationID,
                context: DocumentModeFocusContext(window: window, responder: window.firstResponder))
            session.editorFocusIntent = intent
            return intent
        }

        func select(_ mode: NotePresentationMode) {
            controller.requestPresentationMode(
                mode, session: session, target: document.editingTarget,
                source: snapshot.document.rawContent, revision: snapshot.fingerprint)
        }

        func waitUntilReady(mode: MarkdownEditorMode = .source) async throws {
            try await ReviewModeTransitionTests.waitUntil {
                session.editorSession.isLoaded && session.editorSession.presentedMode == mode
            }
        }

        func close() {
            session.cancelScheduledWork()
            window.contentView = nil
            window.close()
            controller.removeAll()
            controller.unbind()
        }
    }

    private struct Presentation: View {
        @ObservedObject var controller: DocumentController
        var body: some View {
            let active = controller.activeSnapshot
            let state = DocumentFeatureState(
                activeNote: active, selectedDocumentPath: controller.selectedDocumentPath,
                ordinarySearchScope: .triptych, currentVaultID: active?.id.vaultID,
                vaultRole: .sourceCorpus,
                noteIdentityByPath: active.map { [$0.id.relativePath: $0.stableIdentity.resolvedID!] } ?? [:],
                workspaceCatalog: nil, canEdit: true, documentTextScale: 1, documentAppearance: .defaultSettings,
                appearanceCSS: "", readCSS: "", livePreviewCSS: "", initialScrollFraction: 0,
                requestedPresentationMode: nil, sourceLocationRequest: nil,
                identityAmbiguity: nil, pendingIdentityRebinding: nil, identityMigrationFailureMessage: nil, isResolvingIdentity: false)
            let actions = DocumentFeatureActions(
                requestIdentityResolution: {}, retryIdentityRecovery: {}, beginSearch: { _ in },
                clearRequestedPresentationMode: {}, consumeSourceLocation: { _ in }, navigateToSourceLine: { _, _ in },
                rememberScrollPosition: { _ in }, openInternalLink: { _ in }, openExternalURL: { _ in }, enterCSSSafeMode: { _ in },
                rememberPresentationMode: { controller.rememberPresentationMode($0) },
                setSidebarVisible: { _ in }, setResearchInspectorVisible: { _ in }, openingDocumentPresentationDidComplete: {},
                renameNote: { _, _, title in title }, notify: { _, _ in })
            DocumentFeatureView(controller: controller, state: state, actions: actions, hasShellNotices: false) { EmptyView() }
        }
    }

    private final class ModeBoundaryDispatcher: MarkdownEditorBridgeDispatching {
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()
        var holdNextScroll = false
        var holdNextMode = false
        var holdNextResume = false
        private var continuation: CheckedContinuation<Void, Never>?

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            let holds: Bool
            switch request.operation {
            case .queryScrollAnchor where holdNextScroll:
                holdNextScroll = false
                holds = true
            case .setMode where holdNextMode:
                holdNextMode = false
                holds = true
            case .resumeAfterDetachment where holdNextResume:
                holdNextResume = false
                holds = true
            default: holds = false
            }
            let value = try await production.dispatch(requestJSON: requestJSON, in: webView)
            if holds { await withCheckedContinuation { continuation = $0 } }
            return value
        }

        func waitUntilHeld() async throws {
            try await ReviewModeTransitionTests.waitUntil { continuation != nil }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }
}
