import AppKit
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Markdown editor WKWebView integration", .serialized)
@MainActor
struct MarkdownEditorWebViewIntegrationTests {
    @Test("Bridge v2 preserves exact commands, mode chrome, and reconstruction state")
    func bridgeCommandRoundTrip() async throws {
        let harness = EditorHarness(source: "Thesis\r\nSecond\r\n")
        defer { harness.close() }

        try await harness.waitUntilReady()
        #expect(harness.session.isReady)
        #expect(harness.session.isLoaded)
        #expect(harness.session.documentID == harness.documentID)
        #expect(harness.session.hasAttachedWebView)
        let initial: String
        do {
            initial = try await harness.session.currentText(for: harness.documentID)
        } catch {
            Issue.record(Comment(rawValue: "Initial bridge query failed: \(error.localizedDescription)"))
            return
        }
        #expect(initial == "Thesis\r\nSecond\r\n")

        let accessibility = try await harness.session.testingAccessibilitySnapshot()
        #expect(accessibility.contentEditableCount == 1)
        #expect(accessibility.textboxCount == 1)
        #expect(accessibility.label == "Markdown live preview editor")
        #expect(accessibility.multiline == "true")
        #expect(!accessibility.hasValueText)
        #expect(accessibility.spellcheck == "true")

        let initialSelection = try #require(harness.session.context?.selections)
        let expectedPadding = "\(Int(ScholiumMetrics.ContextSurface.initialOverlayClearance))px"
        harness.session.setUserCSS("""
        .scholium-live-mode .cm-content { padding-top: 0; }
        .scholium-live-mode .cm-content,
        .scholium-source-mode .cm-content {
          padding-top: \(ScholiumMetrics.ContextSurface.initialOverlayClearance)px;
        }
        """)

        let live = try await harness.waitUntilPresentation {
            $0.label == "Markdown live preview editor"
                && $0.contentPaddingTop == expectedPadding
        }
        #expect(live.gutterCount == 0)
        #expect(live.lineNumberCount == 0)
        #expect(live.activeLineCount == 0)
        #expect(["24px", "54px"].contains(live.contentPaddingInlineStart))
        #expect(live.isFocused)

        harness.session.setMode(.source)
        let sourceMode = try await harness.waitUntilPresentation {
            $0.label == "Markdown source editor"
                && $0.gutterCount > 0
                && $0.lineNumberCount > 0
        }
        #expect(sourceMode.activeLineCount > 0)
        #expect(sourceMode.contentPaddingTop == expectedPadding)
        #expect(sourceMode.isFocused)

        harness.session.setMode(.livePreview)
        let restoredLive = try await harness.waitUntilPresentation {
            $0.label == "Markdown live preview editor" && $0.gutterCount == 0
        }
        #expect(restoredLive.lineNumberCount == 0)
        #expect(restoredLive.activeLineCount == 0)
        #expect(restoredLive.contentPaddingTop == expectedPadding)
        #expect(restoredLive.isFocused)
        #expect(try await harness.session.currentText(for: harness.documentID) == initial)
        #expect(harness.session.context?.selections == initialSelection)

        do {
            try await harness.session.perform(.bold)
        } catch {
            Issue.record(Comment(rawValue: "Formatting command failed: \(error.localizedDescription)"))
            return
        }

        let updated = try await harness.session.currentText(for: harness.documentID)
        #expect(updated == "****Thesis\r\nSecond\r\n")
        #expect(harness.latestSource == "****Thesis\r\nSecond\r\n")
        #expect(harness.session.generation == 1)

        let pastePayload = #"{"plainText":"Reason","html":"<strong>Reason</strong>"}"#
        try await harness.session.perform(.pasteMarkdown, argument: pastePayload)
        let pasted = try await harness.session.currentText(for: harness.documentID)
        #expect(pasted == "****Reason****Thesis\r\nSecond\r\n")
        #expect(harness.session.generation == 2)

        let unicode = "e\u{301} | é | 👩🏽‍💻️ | العربية، Markdown | עברית (LTR)"
        let unicodeInsertionOffset = try #require(harness.session.context?.selections.first?.head)
        try await harness.session.perform(.pastePlain, argument: unicode)
        let beforeTermination = try await harness.session.currentText(for: harness.documentID)
        let expectedBeforeTermination = try inserting(
            unicode,
            atUTF16: unicodeInsertionOffset,
            in: pasted
        )
        #expect(Data(beforeTermination.utf8) == Data(expectedBeforeTermination.utf8))
        #expect(Array(beforeTermination.utf16) == Array(expectedBeforeTermination.utf16))
        #expect(harness.session.isDirty)
        let insertionOffset = try #require(harness.session.context?.selections.first?.head)

        // Terminate before the bounded EditorState capture can replace the
        // delta-checked mirror fallback. Recovery must retain the last context
        // selection so the next insertion remains at the end of the source.
        #expect(harness.session.testingSimulateWebContentProcessTermination())
        try await harness.waitUntilReady()
        let recovered = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(recovered.utf8) == Data(beforeTermination.utf8))
        #expect(Array(recovered.utf16) == Array(beforeTermination.utf16))
        #expect(harness.session.isDirty)

        try await harness.session.perform(.pastePlain, argument: "!")
        let afterSelectionRestore = try await harness.session.currentText(for: harness.documentID)
        let expectedAfterSelectionRestore = try inserting("!", atUTF16: insertionOffset, in: recovered)
        #expect(Data(afterSelectionRestore.utf8) == Data(expectedAfterSelectionRestore.utf8))
        #expect(Array(afterSelectionRestore.utf16) == Array(expectedAfterSelectionRestore.utf16))

        // Collapse/reopen uses the same explicit recovery capture before
        // SwiftUI dismantles the WKWebView. The retained session must restore
        // exact bytes, selection, bounded undo history, focus, and scroll.
        let selectionBeforeReconstruction = try #require(harness.session.context?.selections.first)
        _ = try #require(harness.session.context?.undoLabel)
        harness.session.setScrollFraction(0.65)
        #expect(harness.session.testingRetainedScrollFraction == 0.65)

        try await harness.session.captureStateForViewReconstruction()
        try await harness.reconstructEditorView()
        try await harness.waitUntilReady()

        let afterReopen = try await harness.session.currentText(for: harness.documentID)
        #expect(Data(afterReopen.utf8) == Data(afterSelectionRestore.utf8))
        #expect(harness.session.context?.selections.first == selectionBeforeReconstruction)
        #expect(harness.session.context?.undoLabel != nil)
        try await harness.waitUntilFocused()
        #expect(harness.session.testingRetainedScrollFraction == 0.65)
        let restoredAccessibility = try await harness.session.testingAccessibilitySnapshot()
        #expect(restoredAccessibility.isFocused)

        try await harness.session.perform(.pastePlain, argument: "?")
        let afterInsertion = try await harness.session.currentText(for: harness.documentID)
        let expectedAfterInsertion = try inserting(
            "?",
            atUTF16: selectionBeforeReconstruction.head,
            in: afterSelectionRestore
        )
        #expect(afterInsertion == expectedAfterInsertion)
    }

    private func inserting(_ insertion: String, atUTF16 offset: Int, in source: String) throws -> String {
        let units = source.utf16
        let position = try #require(units.index(units.startIndex, offsetBy: offset, limitedBy: units.endIndex))
        let index = try #require(String.Index(position, within: source))
        return String(source[..<index]) + insertion + source[index...]
    }

    @MainActor
    private final class EditorHarness {
        let session = MarkdownEditorSession()
        let documentID: String
        private let sourceBox: SourceBox
        var latestSource: String { sourceBox.source }
        private let window: NSWindow
        private var hostingController: NSViewController?

        init(documentID: String = "Argument.md", source: String) {
            _ = NSApplication.shared
            self.documentID = documentID
            sourceBox = SourceBox(source)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            let editor = EditorHarnessRoot(
                session: session,
                documentID: documentID,
                sourceBox: sourceBox
            )
            let hostingController = NSHostingController(rootView: editor)
            self.hostingController = hostingController
            window.contentViewController = hostingController
            window.orderFrontRegardless()
        }

        func waitUntilReady() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            while !session.isReady || !session.isLoaded {
                if clock.now >= deadline {
                    Issue.record(Comment(rawValue: session.errorMessage ?? "The WKWebView editor did not become ready."))
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        func reconstructEditorView() async throws {
            sourceBox.showsEditor = false
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while session.hasAttachedWebView {
                if clock.now >= deadline {
                    Issue.record("SwiftUI did not dismantle the editor view during reconstruction.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            sourceBox.showsEditor = true
        }

        func waitUntilFocused() async throws {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while true {
                if try await session.testingAccessibilitySnapshot().isFocused { return }
                if clock.now >= deadline {
                    Issue.record("The reconstructed editor did not regain focus.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func waitUntilPresentation(
            _ predicate: (MarkdownEditorSession.TestingAccessibilitySnapshot) -> Bool
        ) async throws -> MarkdownEditorSession.TestingAccessibilitySnapshot {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while true {
                let snapshot = try await session.testingAccessibilitySnapshot()
                if predicate(snapshot) { return snapshot }
                if clock.now >= deadline {
                    Issue.record("The editor did not apply the requested presentation mode.")
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        }

        func close() {
            window.orderOut(nil)
            window.contentViewController = nil
            hostingController = nil
            window.close()
        }
    }

    @MainActor
    private final class SourceBox: ObservableObject {
        @Published var source: String
        @Published var showsEditor = true
        init(_ source: String) { self.source = source }
    }

    private struct EditorHarnessRoot: View {
        @ObservedObject var sourceBox: SourceBox
        let session: MarkdownEditorSession
        let documentID: String

        init(session: MarkdownEditorSession, documentID: String, sourceBox: SourceBox) {
            self.session = session
            self.documentID = documentID
            self.sourceBox = sourceBox
        }

        var body: some View {
            if sourceBox.showsEditor {
                MarkdownEditorWebView(
                    session: session,
                    documentID: documentID,
                    source: sourceBox.source,
                    mode: .livePreview,
                    userCSS: "",
                    linkCompletions: [],
                    researcherComments: [],
                    initialScrollFraction: 0,
                    onDocumentChange: { sourceBox.source = $0 },
                    onRequestSave: {},
                    onRequestSearch: {},
                    onRequestComment: {},
                    onLinkActivation: { _ in },
                    onCommentActivation: nil,
                    onScrollFractionChange: { _ in }
                )
            }
        }
    }
}
