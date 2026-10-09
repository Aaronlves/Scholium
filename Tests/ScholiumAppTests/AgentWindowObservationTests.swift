import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent window context", .serialized)
@MainActor
struct AgentWindowObservationTests {
    private let source = "\u{FEFF}# A\r\n😀 e\u{301} 原文\r\ntail"

    @Test("Byte pages preserve exact source and reject scalar-interior starts")
    func exactUTF8Pages() throws {
        var offset = 0
        var collected = ""
        while offset < source.utf8.count {
            let page = try AgentWindowObservation.exactSlice(source, start: offset, maximum: 7)
            #expect(page.end > offset && page.end - offset <= 7)
            collected += page.text
            offset = page.end
        }
        #expect(collected.utf8.elementsEqual(source.utf8))
        #expect(try AgentWindowObservation.exactSlice(source, start: source.utf8.count, maximum: 7).text == "")
        expectFailure(.invalidRequest) { _ = try AgentWindowObservation.exactSlice(source, start: 1, maximum: 7) }
        expectFailure(.invalidRequest) { _ = try AgentWindowObservation.exactSlice("😀", start: 0, maximum: 1) }
        let longLine = String(repeating: "😀", count: 40_000)
        let bounded = try AgentWindowObservation.exactSlice(longLine, start: 0, maximum: 65_536)
        #expect(bounded.text.utf8.count == 65_536 && bounded.end < longLine.utf8.count)
    }

    @Test("Pagination binds ordered inventories and rejects unbound or changed continuation")
    func boundPagination() throws {
        let first: MCPJSONValue = .array([.string("a"), .string("b")])
        let initial = try AgentWindowObservation.admitPage(["limit": .integer(1)], inventory: first)
        let expected = AgentWindowObservation.fingerprintValue(initial.2)
        let continuation = ["offset": MCPJSONValue.integer(1), "limit": .integer(1), "expected_listing_fingerprint": expected]
        let next = try AgentWindowObservation.admitPage(continuation, inventory: first)
        #expect(next.0 == 1 && next.1 == 1)
        let page = try #require(AgentWindowObservation.page([.string("a"), .string("b")], offset: 1, limit: 1).objectValue)
        #expect(page["items"] == .array([.string("b")]) && page["has_more"] == .bool(false) && page["next_offset"] == .null)
        expectFailure(.invalidRequest) { _ = try AgentWindowObservation.admitPage(["offset": .integer(1)], inventory: first) }
        expectFailure(.staleRevision) { _ = try AgentWindowObservation.admitPage(continuation, inventory: .array([.string("b"), .string("a")])) }
        expectFailure(.invalidRequest) { _ = try AgentWindowObservation.admitPage(["limit": .integer(101)], inventory: first) }
        expectFailure(.invalidRequest) {
            _ = try AgentWindowObservation.admitPage(["offset": .integer(3), "expected_listing_fingerprint": expected], inventory: first)
        }
    }

    @Test("Passive workspace and research metadata work without Chat and retain drafts, sessions and saved bytes")
    func passiveMetadata() async throws {
        try await withWindow { window, file in
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            session.originalEditingSource = source
            session.editingSource = source + " PRIVATE UNSAVED SOURCE"
            session.editError = "PRIVATE ERROR /private/fixture"
            let before = try Data(contentsOf: file)
            let sessionCount = window.documentController.retainedSessionCount
            let state = try await window.observeAgentState(request(.observeWorkspace, window: window), admitted: { true })
            let tabs = try #require(state.objectValue?["tabs"]?.objectValue?["items"]?.arrayValue)
            #expect(tabs.count == 1)
            #expect(tabs[0].objectValue?["note"]?.objectValue?["dirty"] == .bool(true))
            let recovery = try #require(state.objectValue?["window"]?.objectValue?["recovery"]?.objectValue)
            #expect(recovery["pending_changes_count"] == (window.researchController.pendingChanges.map { MCPJSONValue.integer($0.count) } ?? .null))
            #expect(recovery["attention_count"] == (window.workspaceProjectionController.catalog.map { MCPJSONValue.integer($0.attention.count) } ?? .null))
            let research = try await window.observeAgentState(request(.observeResearchContext, window: window), admitted: { true })
            #expect(research.objectValue?["active_note"]?.objectValue?["revision"]?.objectValue?["origin"] == .string("unavailable"))
            let serialized = String(decoding: try JSONEncoder().encode([state, research]), as: UTF8.self)
            #expect(!serialized.contains("PRIVATE") && !serialized.contains("/private/fixture") && !serialized.contains("原文"))
            #expect(window.documentController.retainedSessionCount == sessionCount)
            #expect(session.editingSource.utf8.elementsEqual((source + " PRIVATE UNSAVED SOURCE").utf8))
            #expect(try Data(contentsOf: file) == before)
            #expect(!window.isChatSidebarEnabled || window.shellState.sidebarContent != .chat)
            await expectFailure(.workspaceNotReady) {
                _ = try await window.observeAgentState(request(.observeWorkspace, window: window), admitted: { false })
            }
        }
    }

    @Test("Exact active and selected text reads bind Note identity, revision and the captured selection")
    func explicitReads() async throws {
        try await withWindow { window, file in
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            session.originalEditingSource = source
            session.editingSource = source
            session.renderedReadFingerprint = DocumentFingerprint(content: source).sha256
            session.readSelection = .init(startLine: 2, endLine: 2, excerpt: "原文", utf16LowerBound: 12, utf16UpperBound: 14)
            let expected = AgentWindowObservation.fingerprintValue(DocumentFingerprint(content: source))
            let identity = MCPJSONValue.string(descriptor.sessionKey.noteID.uuidString.lowercased())
            let selected = try await window.observeAgentState(
                request(
                    .readContext, window: window,
                    extra: [
                        "kind": .string("selection"), "note_id": identity, "expected_fingerprint": expected,
                        "expected_start_utf8": .integer(17), "expected_end_utf8": .integer(23), "max_utf8": .integer(3),
                    ]), admitted: { true })
            #expect(selected.objectValue?["text"] == .string("原"))
            #expect(selected.objectValue?["origin"] == .string("saved_source"))
            #expect(selected.objectValue?["coverage"]?.objectValue?["next_start_utf8"] == .integer(3))
            #expect(selected.objectValue?["source_locator"]?.objectValue?["start_utf8"] == .integer(17))
            await expectFailure(.staleRevision) {
                _ = try await window.observeAgentState(
                    request(
                        .readContext, window: window,
                        extra: ["kind": .string("active_note"), "note_id": .string(UUID().uuidString), "expected_fingerprint": expected]),
                    admitted: { true })
            }
            await expectFailure(.staleRevision) {
                _ = try await window.observeAgentState(
                    request(
                        .readContext, window: window,
                        extra: [
                            "kind": .string("selection"), "note_id": identity, "expected_fingerprint": expected,
                            "expected_start_utf8": .integer(0), "expected_end_utf8": .integer(1),
                        ]), admitted: { true })
            }
            let full = try await window.observeAgentState(
                request(.readContext, window: window, extra: ["kind": .string("active_note"), "note_id": identity, "expected_fingerprint": expected]),
                admitted: { true })
            #expect(full.objectValue?["text"]?.stringValue?.utf8.elementsEqual(source.utf8) == true)
            #expect(full.objectValue?["text_fingerprint"] == expected)
            #expect(try Data(contentsOf: file) == Data(source.utf8))
        }
    }

    @Test("A pure session peek never creates an inactive editor")
    func pureSessionPeek() {
        let controller = DocumentController()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let before = controller.retainedSessionCount
        #expect(controller.peekRetainedSession(for: .workspace(key)) == nil)
        #expect(controller.retainedSessionCount == before)
    }

    @Test("Unloaded recovery and attention state remain unavailable rather than claiming zero")
    func unavailableRecoveryCounts() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-window-observation/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        let window = WindowModel(workspaceStore: store)
        defer { window.windowSessionPersistenceCoordinator.close() }
        let recovery = try #require(window.agentWindowRecoverySummary().objectValue)
        #expect(recovery["snapshot_available"] == .bool(false))
        for key in [
            "pending_changes_count", "agent_changes_count", "transaction_recovery_count", "interrupted_save_recovery_count", "attention_count",
            "identity_ambiguity_count",
        ] {
            #expect(recovery[key] == .null)
        }
        await store.shutdownApplicationRuntime()
    }

    @Test("Missing active session stays unknown in new research observations and preserves the existing Chat contract")
    func missingActiveSessionFlags() throws {
        let document = AgentChatDocumentObservation(
            surface: .triptychNote,
            activeNote: .init(
                vaultID: UUID(), noteID: UUID(), role: .sourceCorpus, relativePath: "Source.md", mode: .read,
                revision: .unavailable(.loading), dirty: false, saving: false, conflict: false,
                selection: .unavailable(.loading)))
        let absent = try #require(AgentWindowObservation.researchDocumentValue(document, hasRetainedSession: false).objectValue?["active_note"]?.objectValue)
        let present = try #require(AgentWindowObservation.researchDocumentValue(document, hasRetainedSession: true).objectValue?["active_note"]?.objectValue)
        for flag in ["dirty", "saving", "conflict"] {
            #expect(absent[flag] == .null)
            #expect(present[flag] == .bool(false))
            #expect(document.jsonValue.objectValue?["active_note"]?.objectValue?[flag] == .bool(false))
        }
        #expect(absent["revision"] == present["revision"] && absent["selection"] == present["selection"])
    }

    @Test("Kept reads use immutable original bytes and source revisions; removal and re-addition revoke pagination")
    func keptSnapshotsAndLifetimes() async throws {
        try await withWindow { window, file in
            let descriptor = try #require(window.currentDocumentDescriptor)
            let capturedSource = DocumentFingerprint(content: source)
            let range = SearchSourceRange(utf16LowerBound: 12, utf16UpperBound: 16, line: 2, column: 7, endLine: 3, endColumn: 1)
            let candidate = RelatedContentCandidate(
                note: .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath),
                vaultRole: descriptor.reference.vaultRole, title: "PRIVATE TITLE", fingerprint: capturedSource,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
            let passage = RelatedContentPassage(
                candidate: candidate, range: range, source: "原文\r\n", displayText: "DIFFERENT DISPLAY TEXT", excerpt: "PRIVATE EXCERPT",
                excerptMatches: [], matches: [])
            let entry = KeptPassage(card: .init(passage: passage, reference: descriptor.reference))
            let kept = window.researchController.keptPassages
            kept.retain(entry)
            let firstLifetime = try #require(kept.entryLifetime(for: entry))
            let initialLifetimes = kept.observedEntryLifetimes
            #expect(initialLifetimes[entry.id] == firstLifetime && initialLifetimes.count == 1)
            kept.retain(entry)
            #expect(kept.observedEntryLifetimes == initialLifetimes)
            let initial = try await window.observeAgentState(request(.observeResearchContext, window: window), admitted: { true })
            let expectedListing = try #require(initial.objectValue?["listing_fingerprint"])
            let serialized = String(decoding: try JSONEncoder().encode(initial), as: UTF8.self)
            #expect(!serialized.contains("PRIVATE TITLE") && !serialized.contains("PRIVATE EXCERPT") && !serialized.contains("DIFFERENT DISPLAY TEXT"))
            try Data("New saved source".utf8).write(to: file)
            let read = try await window.observeAgentState(
                request(
                    .readContext, window: window,
                    extra: [
                        "kind": .string("kept_passage"), "kept_passage_id": .string(entry.id),
                        "expected_fingerprint": AgentWindowObservation.fingerprintValue(capturedSource),
                    ]), admitted: { true })
            #expect(read.objectValue?["origin"] == .string("kept_snapshot"))
            #expect(read.objectValue?["text"] == .string("原文\r\n"))
            #expect(read.objectValue?["fingerprint"] == AgentWindowObservation.fingerprintValue(capturedSource))
            #expect(read.objectValue?["text_fingerprint"] == AgentWindowObservation.fingerprintValue(DocumentFingerprint(content: "原文\r\n")))
            kept.remove(entry.id)
            #expect(kept.observedEntryLifetimes.isEmpty && kept.entryLifetime(for: entry) == nil)
            kept.retain(entry)
            #expect(kept.observedEntryLifetimes[entry.id] != firstLifetime)
            #expect(initialLifetimes[entry.id] == firstLifetime)
            await expectFailure(.staleRevision) {
                _ = try await window.observeAgentState(
                    request(.observeResearchContext, window: window, extra: ["expected_listing_fingerprint": expectedListing]), admitted: { true })
            }
            kept.remove(entry.id)
            await expectFailure(.notFound) {
                _ = try await window.observeAgentState(
                    request(
                        .readContext, window: window,
                        extra: [
                            "kind": .string("kept_passage"), "kept_passage_id": .string(entry.id),
                            "expected_fingerprint": AgentWindowObservation.fingerprintValue(capturedSource),
                        ]), admitted: { true })
            }
        }
    }

    private func request(_ tool: ScholiumMCPToolName, window: WindowModel, extra: [String: MCPJSONValue] = [:]) -> ScholiumMCPBridgeRequest {
        var arguments = extra
        arguments["triptych_id"] = .string(window.workspaceAssignment!.id.uuidString.lowercased())
        arguments["window_id"] = .string(window.nativeWindowID.uuidString.lowercased())
        return .init(tool: tool, arguments: arguments)
    }

    private func withWindow(_ body: (WindowModel, URL) async throws -> Void) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-window-observation/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let file = analyses.appendingPathComponent("Source.md")
            try Data(source.utf8).write(to: file)
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works, portableContainerURL: triptych, triptychName: "Context Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            defer { window.windowSessionPersistenceCoordinator.close() }
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            window.documentController.rememberPresentationMode(.read)
            try await window.openNote("Source.md")
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            defer { session.cancelScheduledWork() }
            session.preparePresentationMode(.read)
            window.rememberPresentationMode(.read)
            try await body(window, file)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    private func expectFailure(_ expected: ScholiumMCPFailureCode, operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("Expected context failure")
        } catch let failure as ScholiumMCPFailure { #expect(failure.code == expected) } catch { Issue.record("Unexpected error: \(error)") }
    }

    private func expectFailure(_ expected: ScholiumMCPFailureCode, operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Expected context failure")
        } catch let failure as ScholiumMCPFailure { #expect(failure.code == expected) } catch { Issue.record("Unexpected error: \(error)") }
    }
}
