import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Session-scoped MCP Note display", .serialized) @MainActor
struct MCPNoteDisplayTests {
    @Test("Display activates only its exact eligible window and source, retaining tabs and dirty buffers")
    func exactWindowNavigation() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-display-tests/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let triptych = root.appendingPathComponent("Triptych")
        try FileManager.default.copyItem(at: repository.appendingPathComponent("TestVaults"), to: triptych)
        let analyses = triptych.appendingPathComponent("01-analyses")
        let topics = triptych.appendingPathComponent("02-topics")
        let works = triptych.appendingPathComponent("03-works")
        let source = Data("\u{feff}# 原文\r\n\r\nExact **text** 😀.\r\n".utf8)
        let file = analyses.appendingPathComponent("Source.md")
        try source.write(to: file)
        try Data("# Peer\n".utf8).write(to: analyses.appendingPathComponent("Peer.md"))
        let draftBytes = Data("# Draft destination\n".utf8)
        try draftBytes.write(to: works.appendingPathComponent("Destination.md"))
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses,
                topicKnowledgeURL: topics, outputURL: works, portableContainerURL: triptych, triptychName: "Display fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let id = try #require(note.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            let peer = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Peer.md" })
            let peerID = try #require(peer.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            #expect(window.openChatReference(AgentChatReference.url(noteID: peerID)))
            await window.waitForPendingDocumentTransitionsForTesting()
            var visible = true
            var didDispatch = false
            func wait(_ predicate: () -> Bool) async throws {
                let deadline = ContinuousClock.now.advanced(by: .seconds(10))
                while !predicate() {
                    try #require(ContinuousClock.now < deadline, "Display fixture did not reach its expected state")
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            store.registerNoteDisplayWindow(
                id: window.nativeWindowID,
                window: .init(
                    state: {
                        .init(triptychID: configured.id, canDisplay: visible, visibleConversationID: nil)
                    },
                    display: { target, admitted in
                        didDispatch = true
                        try await window.displayAgentNote(target, admitted: admitted)
                    }))
            var flushes = 0
            let router = MCPAppBridgeRequestRouter(
                runtime: store.applicationRuntime, flushEditors: { _ in flushes += 1 }, openTriptychs: { [configured.assignment] },
                displayWindows: { store.displayWindowValues(triptychID: $0) },
                displayNote: { try await store.displayAgentNote(windowID: $0, target: $1, request: $2) })
            let range = try #require(source.range(of: Data("text".utf8)))
            let args: [String: MCPJSONValue] = [
                "triptych_id": .string(configured.id.uuidString), "window_id": .string(window.nativeWindowID.uuidString),
                "note_id": .string(id.uuidString),
                "expected_fingerprint": .object(["sha256": .string(DocumentFingerprint(data: source).sha256), "byte_count": .integer(source.count)]),
                "start_utf8": .integer(range.lowerBound), "end_utf8": .integer(range.upperBound), "expected_text": .string("text"),
            ]
            visible = false
            #expect(await router.handle(.init(tool: .showNote, arguments: args)).error?.code == .workspaceNotReady)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == peerID)
            visible = true
            var wrong = args
            wrong["expected_text"] = .string("invented")
            #expect(await router.handle(.init(tool: .showNote, arguments: wrong)).error?.code == .invalidRequest)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == peerID)
            for cancel in [false, true] {
                var release: CheckedContinuation<Void, Never>?
                window.enqueueDocumentTransition({ await withCheckedContinuation { release = $0 } })
                try await wait { release != nil }
                didDispatch = false
                let pending = Task { await router.handle(.init(tool: .showNote, arguments: args)) }
                try await wait { didDispatch }
                if cancel { pending.cancel() } else { window.enqueueDocumentTransition({}) }
                release?.resume()
                #expect(await pending.value.error?.code == .workspaceNotReady)
                await window.waitForPendingDocumentTransitionsForTesting()
                #expect(window.currentDocumentDescriptor?.sessionKey.noteID == peerID)
            }
            let shown = await router.handle(.init(tool: .showNote, arguments: args))
            #expect(shown.error == nil && shown.result?.objectValue?["location_requested"]?.boolValue == true)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == id && window.documentController.sourceLocationRequest?.range?.line == 3)
            #expect(window.documentTabController.allTabs.count == 2 && flushes == 0)
            let draft = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Destination.md" })
            let draftID = try #require(draft.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            var draftArgs = args
            draftArgs["note_id"] = .string(draftID.uuidString)
            draftArgs["expected_fingerprint"] = .object([
                "sha256": .string(DocumentFingerprint(data: draftBytes).sha256), "byte_count": .integer(draftBytes.count),
            ])
            for key in ["start_utf8", "end_utf8", "expected_text"] { draftArgs[key] = nil }
            #expect(await router.handle(.init(tool: .showNote, arguments: draftArgs)).error == nil)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == draftID && window.documentTabController.allTabs.count == 3)
            #expect(await router.handle(.init(tool: .showNote, arguments: args)).error == nil)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == id && window.documentTabController.allTabs.count == 3)
            let current = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: current)
            session.suppressAutosave = true
            session.editingSource = "Unsaved source"
            #expect(await router.handle(.init(tool: .showNote, arguments: args)).error != nil)
            #expect(session.editingSource == "Unsaved source" && session.hasUnsavedChanges)
            #expect(try Data(contentsOf: file) == source)
            store.unregisterNoteDisplayWindow(id: window.nativeWindowID)
            #expect(await router.handle(.init(tool: .showNote, arguments: args)).error?.code == .workspaceNotReady)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
