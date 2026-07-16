import AppKit
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Markdown editor WKWebView integration", .serialized)
@MainActor
struct MarkdownEditorWebViewIntegrationTests {
    @Test("Bridge v2 initializes CodeMirror and reconciles one exact command")
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
