import AppKit
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Native document title popover", .serialized)
struct NativeDocumentTitlePopoverTests {
    init() { _ = NSApplication.shared }

    private func settle(_ controller: DocumentTitlePopoverController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !controller.nameField.isEditable, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(controller.nameField.isEditable, "Rename did not settle")
    }

    @Test("A rejected draft retains its text and freezes a fresh CAS baseline for each retry")
    func concurrentRenameRetry() async throws {
        var authoritative = "Original"
        var attemptedNames: [String] = []
        var requestedNames: [String] = []
        var dismissals = 0
        let controller = DocumentTitlePopoverController(
            name: authoritative, location: "Topics/Original.md",
            rename: { expected, requested in
                attemptedNames.append(expected)
                requestedNames.append(requested)
                guard expected == authoritative else { throw DocumentTitleRenameError.titleChangedElsewhere }
                authoritative = requested
                return requested
            },
            latestName: { authoritative }, dismiss: { dismissals += 1 })
        _ = controller.view
        controller.nameField.stringValue = "My draft"
        authoritative = "External first"
        controller.updateAuthoritativeName(authoritative)
        controller.submit(nil)
        controller.submit(nil)  // A second activation cannot dispatch a duplicate transaction.
        try await settle(controller)
        #expect(attemptedNames == ["Original"])
        #expect(controller.nameField.stringValue == "My draft")
        #expect(dismissals == 0)
        #expect(authoritative == "External first")

        // The visible previous error must not let a new external update silently
        // rebase an in-progress retry and overwrite that newer filename.
        authoritative = "External second"
        controller.updateAuthoritativeName(authoritative)
        controller.submit(nil)
        try await settle(controller)
        #expect(attemptedNames == ["Original", "External first"])
        #expect(controller.nameField.stringValue == "My draft")
        #expect(dismissals == 0)
        #expect(authoritative == "External second")

        controller.submit(nil)
        try await settle(controller)
        #expect(attemptedNames == ["Original", "External first", "External second"])
        #expect(requestedNames == ["My draft", "My draft", "My draft"])
        #expect(authoritative == "My draft")
        #expect(dismissals == 1)
    }

    @Test("Focusing and leaving the actual native name field never submit a rename")
    func focusDoesNotSubmit() {
        var renameCalls = 0
        var dismissals = 0
        let controller = DocumentTitlePopoverController(
            name: "Original", location: "Topics/Original.md",
            rename: { _, requested in
                renameCalls += 1
                return requested
            },
            latestName: { "Original" }, dismiss: { dismissals += 1 })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        defer { window.close() }

        controller.focusName()
        controller.focusName()
        #expect(!window.isVisible)
        #expect(dismissals == 0)
        #expect(renameCalls == 0)
        #expect(controller.nameField.currentEditor()?.selectedRange == NSRange(location: 0, length: 8))

        controller.nameField.stringValue = "Unsubmitted draft"
        #expect(window.makeFirstResponder(nil))
        #expect(controller.nameField.stringValue == "Unsubmitted draft")
        #expect(dismissals == 0)
        #expect(renameCalls == 0)
    }

    @Test("Cancel and unchanged-name submission dismiss without invoking a mutation")
    func cancelAndUnchangedAreSourceNeutral() async throws {
        var renameCalls = 0
        var dismissals = 0
        let controller = DocumentTitlePopoverController(
            name: "Original", location: "Topics/Original.md",
            rename: { _, requested in
                renameCalls += 1
                return requested
            },
            latestName: { "Original" }, dismiss: { dismissals += 1 })
        _ = controller.view
        controller.submit(nil)
        #expect(dismissals == 1)
        controller.nameField.stringValue = "Unsubmitted draft"
        controller.cancelOperation(nil)
        await Task.yield()
        #expect(dismissals == 2)
        #expect(renameCalls == 0)
        #expect(controller.nameField.stringValue == "Unsubmitted draft")
    }
}
