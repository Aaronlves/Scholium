import AppKit
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Editor context menu lifecycle", .serialized)
@MainActor
struct EditorContextMenuLifecycleTests {
    @Test(
        "A context command remains bound to the document and selection that created its menu",
        arguments: ["session", "rebind", "document", "generation", "selection", "mode", "composition", "hidden", "inactive", "detached"])
    func staleContextCommandIsDiscarded(change: String) async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.load()
        let item = try fixture.commandItem()
        switch change {
        case "session":
            fixture.session.attach(fixture.webView)
            fixture.session.loadDocument(fixture.source, documentID: "Tasks.md", mode: .livePreview)
            fixture.session.editorBecameReady()
            try await fixture.waitUntilLoaded()
            fixture.updateContext()
        case "rebind":
            let replacement = MarkdownEditorSession(bridgeDispatcher: fixture.dispatcher)
            fixture.replacementSession = replacement
            fixture.webView.editorSession = replacement
            replacement.attach(fixture.webView)
            replacement.loadDocument(fixture.source, documentID: "Replacement.md", mode: .livePreview)
            replacement.editorBecameReady()
            try await fixture.waitUntil { replacement.isLoaded }
            fixture.updateContext(in: replacement)
        case "document":
            fixture.session.loadDocument(fixture.source, documentID: "Replacement.md", mode: .livePreview)
            try await fixture.waitUntilLoaded()
            fixture.updateContext()
        case "generation":
            #expect(
                fixture.session.acceptEditorChanges(
                    [.init(from: 0, to: 0, insert: "x", exactInsert: "x")],
                    baseGeneration: 0, resultingGeneration: 1))
            fixture.updateContext()
        case "selection": fixture.updateContext(head: 7)
        case "mode":
            fixture.session.setMode(.source)
            try await fixture.waitUntil { fixture.session.presentedMode == .source }
        case "composition": fixture.updateContext(composing: true)
        case "hidden": fixture.webView.isHidden = true
        case "inactive": fixture.container.setSurfaceVisibility(.preparing)
        case "detached": fixture.session.detach(fixture.webView)
        default: Issue.record("Unknown context-command invalidation")
        }

        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        try await fixture.drainMenuTask()
        #expect(fixture.dispatcher.commands.isEmpty)
        #expect(fixture.session.errorMessage == nil)
        #expect(fixture.replacementSession?.errorMessage == nil)
    }

    @Test("Changing the selection before a menu task begins cannot execute its command")
    func changedSelectionBeforeTaskStartsIsDiscarded() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.load()
        let item = try fixture.commandItem()
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        fixture.updateContext(head: 7)
        try await fixture.drainMenuTask()
        #expect(fixture.dispatcher.commands.isEmpty)
        #expect(fixture.session.errorMessage == nil)
    }

    @Test("A current context command reaches the existing editor bridge")
    func currentContextCommandExecutes() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.load()
        let item = try fixture.commandItem()
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        try await fixture.waitUntil { fixture.dispatcher.commands == [.toggleTask] }
        #expect(fixture.session.errorMessage == nil)
    }

    @Test("A late context-command failure cannot make a changed selection unavailable")
    func lateContextCommandFailureIsDiscarded() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.load()
        fixture.dispatcher.suspendsCommand = true
        let item = try fixture.commandItem()
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        try await fixture.waitUntil { fixture.dispatcher.isSuspended }
        fixture.updateContext(head: 7)
        fixture.dispatcher.resumeCommand(failing: true)
        try await fixture.drainMenuTask()
        #expect(fixture.session.context?.selections == [.init(anchor: 7, head: 7)])
        #expect(fixture.session.isLoaded)
        #expect(fixture.session.errorMessage == nil)
    }

    @Test("Selection changes while a context command waits for the mutation lane revoke it")
    func queuedContextCommandRechecksSelection() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.load()
        fixture.dispatcher.suspendsCommand = true
        let barrier = Task { try await fixture.session.perform(.bold) }
        defer { barrier.cancel() }
        try await fixture.waitUntil { fixture.dispatcher.isSuspended }
        let item = try fixture.commandItem()
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        await Task.yield()
        fixture.updateContext(head: 7)
        fixture.dispatcher.resumeCommand()
        try await barrier.value
        try await fixture.drainMenuTask()
        #expect(fixture.dispatcher.commands == [.bold])
        #expect(fixture.session.errorMessage == nil)
    }

    @MainActor
    private final class Fixture {
        let source = "- [ ] First task\r\n- [ ] Second task\r\n"
        let dispatcher = Dispatcher()
        let session: MarkdownEditorSession
        var replacementSession: MarkdownEditorSession?
        let webView = WindowAttachedWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let container: DocumentWebViewContainer
        let window: NSWindow
        private var interactionRevision = 0

        init() {
            session = MarkdownEditorSession(bridgeDispatcher: dispatcher)
            container = DocumentWebViewContainer(webView: webView)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = container
            webView.editorSession = session
            session.attach(webView)
        }

        func load() async throws {
            session.loadDocument(source, documentID: "Tasks.md", mode: .livePreview)
            session.editorBecameReady()
            try await waitUntilLoaded()
            updateContext()
        }

        func updateContext(head: Int = 4, composing: Bool = false, in target: MarkdownEditorSession? = nil) {
            let session = target ?? session
            interactionRevision += 1
            let selections = [MarkdownEditorSelectionRange(anchor: head, head: head)]
            let context = MarkdownEditorContext(
                selections: selections, activeInlineConstructs: [], activeBlockConstructs: [],
                composing: composing, availableCommands: [.toggleTask, .bold], undoLabel: nil, redoLabel: nil)
            #expect(
                session.updateInteraction(
                    selections: selections, line: 1, column: head + 1, lineCount: 2,
                    documentVersion: session.generation, interactionRevision: interactionRevision, context: context))
            dispatcher.selections = selections
            dispatcher.interactionRevision = interactionRevision
        }

        func commandItem() throws -> NSMenuItem {
            let menu = webView.makeEditorContextMenu(
                context: try #require(session.context), mode: .livePreview, canPaste: false)
            return try #require(menu.item(withTitle: ScholiumL10n.string("Toggle Task")))
        }

        func waitUntilLoaded() async throws { try await waitUntil { self.session.isLoaded } }

        func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !condition() {
                try #require(ContinuousClock.now < deadline)
                try await Task.sleep(for: .milliseconds(1))
            }
        }

        func drainMenuTask() async throws {
            // Menu actions enqueue a MainActor task. Join a marker submitted
            // after that action, then the editor's ordered mutation lane.
            await Task { @MainActor in await Task.yield() }.value
            let session = webView.editorSession ?? session
            if session.webView === webView {
                _ = try await session.send(
                    .acknowledgeCommittedSnapshot(
                        expected: session.checkedSource, committed: session.checkedSource,
                        fingerprint: session.startingFingerprint), in: webView)
            }
            await Task { @MainActor in await Task.yield() }.value
        }

        func close() {
            dispatcher.resumeCommand()
            if replacementSession?.webView === webView { replacementSession?.detach(webView) }
            if session.webView === webView { session.detach(webView) }
            webView.editorSession = nil
            window.contentView = nil
            window.close()
        }
    }

    @MainActor
    private final class Dispatcher: MarkdownEditorBridgeDispatching {
        var commands: [MarkdownEditorCommand] = []
        var selections = [MarkdownEditorSelectionRange(anchor: 0, head: 0)]
        var interactionRevision = 0
        var suspendsCommand = false
        var isSuspended: Bool { continuation != nil }
        private var continuation: CheckedContinuation<Void, Never>?
        private var failsCommand = false

        func resumeCommand(failing: Bool = false) {
            failsCommand = failing
            let continuation = continuation
            self.continuation = nil
            continuation?.resume()
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            if case .command(let command, _) = request.operation {
                commands.append(command)
                if suspendsCommand {
                    suspendsCommand = false
                    await withCheckedContinuation { continuation = $0 }
                    if failsCommand { throw NSError(domain: "ContextMenuFixture", code: 1) }
                }
            }
            if case .initialize(_, _, _, let initial, _, _, _) = request.operation {
                selections = [initial ?? .init(anchor: 0, head: 0)]
            }
            return [
                "requestID": request.requestID.uuidString,
                "resultingGeneration": request.knownGeneration,
                "interactionRevision": interactionRevision,
                "sourceChanged": false,
                "selections": selections.map { ["anchor": $0.anchor, "head": $0.head] },
                "accepted": true,
            ] as [String: Any]
        }
    }
}
