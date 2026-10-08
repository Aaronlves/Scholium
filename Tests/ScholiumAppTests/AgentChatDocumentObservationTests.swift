import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat document observation", .serialized)
@MainActor
struct AgentChatDocumentObservationTests {
    private let source = "\u{FEFF}# A\r\n😀 e\u{301} 原文\r\ntail"

    @Test("Editor selections map normalized offsets to exact UTF-8 extents without returning source text")
    func exactSourceExtents() throws {
        let expected = AgentChatDocumentObservation.Selection.range(
            .init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3))
        for selection in [MarkdownEditorSelectionRange(anchor: 5, head: 14), .init(anchor: 14, head: 5)] {
            #expect(AgentChatDocumentObservation.Selection.editor(source: source, selections: [selection]) == expected)
        }
        #expect(AgentChatDocumentObservation.Selection.exactSourceRange(6..<16, in: source) == expected)
        #expect(AgentChatDocumentObservation.Selection.editor(source: source, selections: [.init(anchor: 5, head: 5)]) == .none)
        #expect(AgentChatDocumentObservation.Selection.editor(source: source, selections: []) == .unavailable(.sourceMappingUnavailable))
        #expect(
            AgentChatDocumentObservation.Selection.editor(
                source: source, selections: [.init(anchor: 0, head: 0), .init(anchor: 5, head: 14)]) == .unavailable(.multipleSelections))
        #expect(
            AgentChatDocumentObservation.Selection.editor(
                source: source, selections: [.init(anchor: 6, head: 7)]) == .unavailable(.sourceMappingUnavailable))
        #expect(AgentChatDocumentObservation.Selection.exactSourceRange(-1..<0, in: source) == .unavailable(.sourceMappingUnavailable))
        #expect(AgentChatDocumentObservation.Selection.exactSourceRange(0..<100, in: source) == .unavailable(.sourceMappingUnavailable))

        let vaultID = UUID()
        let noteID = UUID()
        let fingerprint = DocumentFingerprint(content: source)
        let observation = AgentChatDocumentObservation(
            surface: .triptychNote,
            activeNote: .init(
                vaultID: vaultID, noteID: noteID, role: .sourceCorpus, relativePath: "Source.md", mode: .source,
                revision: .editorSnapshot(fingerprint), dirty: true, saving: false, conflict: true, selection: expected),
            hasSaveError: true)
        let json = try #require(observation.jsonValue.objectValue)
        let note = try #require(json["active_note"]?.objectValue)
        #expect(Set(json.keys) == ["document_surface", "active_note"])
        #expect(Set(note.keys) == ["vault_id", "note_id", "role", "relative_path", "mode", "revision", "dirty", "saving", "conflict", "selection"])
        #expect(note["vault_id"] == .string(vaultID.uuidString.lowercased()))
        #expect(note["note_id"] == .string(noteID.uuidString.lowercased()))
        #expect(
            note["revision"]?.objectValue?["fingerprint"]
                == .object([
                    "sha256": .string(fingerprint.sha256), "byte_count": .integer(source.utf8.count),
                ]))
        #expect(
            note["selection"]
                == .object([
                    "state": .string("range"), "start_utf8": .integer(8), "end_utf8": .integer(25),
                    "byte_count": .integer(17), "start_line": .integer(2), "end_line": .integer(3),
                ]))
        #expect(observation.errorCodes == ["document_save", "document_conflict"])
        let encoded = try JSONEncoder().encode(observation.jsonValue)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("原文") && !text.contains("tail") && !text.contains("excerpt") && !text.contains("source_text"))
        #expect(AgentChatDocumentObservation(surface: .none).jsonValue.objectValue?["active_note"] == .null)
    }

    @Test("Departure revokes synchronously across leave-and-return and belongs to one request")
    func requestLocalDeparture() {
        let owner = PublishedScope()
        let first = AgentChatObservationDeparture()
        let firstSubscription = first.observing(owner.$selection)
        owner.selection = "origin"
        #expect(first.isCurrent)
        owner.selection = "other"
        owner.selection = "origin"
        #expect(!first.isCurrent)
        firstSubscription.cancel()

        let second = AgentChatObservationDeparture()
        let secondSubscription = second.observing(owner.$selection)
        #expect(second.isCurrent)
        owner.selection = "origin"
        #expect(second.isCurrent && !first.isCurrent)
        owner.selection = "another"
        #expect(!second.isCurrent)
        secondSubscription.cancel()
    }

    @Test("Window observation is bound to exact registration, Triptych, conversation and current admission")
    func registeredWindowBinding() async throws {
        try await withStore { store, _ in
            let triptych = UUID()
            let conversation = UUID()
            let windowID = UUID()
            var state = AgentNoteDisplayWindow.State(triptychID: triptych, canDisplay: true, visibleConversationID: conversation)
            var calls = 0
            let registration = AgentNoteDisplayWindow(
                state: { state }, display: { _, _ in },
                observe: { admitted in
                    #expect(admitted())
                    calls += 1
                    return .init(surface: .none)
                })
            store.registerNoteDisplayWindow(id: windowID, window: registration)
            let scope = try #require(store.chatDisplayWindow(triptychID: triptych, conversationID: conversation))
            let value = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: scope, admitted: { true })
            #expect(value.jsonValue.objectValue?["document_surface"] == .string("none") && calls == 1)
            await expectFailure(.workspaceNotReady) {
                _ = try await store.observeAgentCurrentState(triptychID: UUID(), conversationID: conversation, scope: scope, admitted: { true })
            }
            await expectFailure(.workspaceNotReady) {
                _ = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: UUID(), scope: scope, admitted: { true })
            }
            await expectFailure(.workspaceNotReady) {
                _ = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: scope, admitted: { false })
            }
            state = .init(triptychID: triptych, canDisplay: false, visibleConversationID: conversation)
            await expectFailure(.workspaceNotReady) {
                _ = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: scope, admitted: { true })
            }
            #expect(calls == 1)
            store.unregisterNoteDisplayWindow(id: windowID)
            state = .init(triptychID: triptych, canDisplay: true, visibleConversationID: conversation)
            store.registerNoteDisplayWindow(
                id: windowID,
                window: .init(
                    state: { state }, display: { _, _ in },
                    observe: { _ in
                        calls += 1
                        return .init(surface: .none)
                    }))
            await expectFailure(.workspaceNotReady) {
                _ = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: scope, admitted: { true })
            }
            #expect(calls == 1)
            let replacementScope = try #require(store.chatDisplayWindow(triptychID: triptych, conversationID: conversation))
            #expect(replacementScope.registrationID != scope.registrationID)
            _ = try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: replacementScope, admitted: { true })
            #expect(calls == 2)
            store.unregisterNoteDisplayWindow(id: windowID)
        }
    }

    @Test("Closing and re-registering the same window revokes a suspended observation")
    func pendingWindowRegistrationReplacement() async throws {
        try await withStore { store, _ in
            let triptych = UUID()
            let conversation = UUID()
            let windowID = UUID()
            let state = AgentNoteDisplayWindow.State(triptychID: triptych, canDisplay: true, visibleConversationID: conversation)
            var release: CheckedContinuation<Void, Never>?
            defer { release?.resume() }
            store.registerNoteDisplayWindow(
                id: windowID,
                window: .init(
                    state: { state }, display: { _, _ in },
                    observe: { admitted in
                        await withCheckedContinuation { release = $0 }
                        #expect(!admitted())
                        return .init(surface: .none)
                    }))
            let scope = try #require(store.chatDisplayWindow(triptychID: triptych, conversationID: conversation))
            let pending = Task {
                try await store.observeAgentCurrentState(triptychID: triptych, conversationID: conversation, scope: scope, admitted: { true })
            }
            defer { pending.cancel() }
            try await wait { release != nil }
            store.unregisterNoteDisplayWindow(id: windowID)
            store.registerNoteDisplayWindow(
                id: windowID,
                window: .init(state: { state }, display: { _, _ in }, observe: { _ in .init(surface: .none) }))
            release?.resume()
            release = nil
            await expectFailure(.workspaceNotReady) { _ = try await pending.value }
            store.unregisterNoteDisplayWindow(id: windowID)
        }
    }

    @Test("Metadata queries leave the checked source, dirty state, selection, focus, Undo and callbacks unchanged")
    func editorQueryIsReadOnly() async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        fixture.select([.init(anchor: 14, head: 5)], focusTarget: .editor)
        var sourceChanges = 0
        var commits = 0
        fixture.editor.installSourceChangeHandler { sourceChanges += 1 }
        fixture.editor.installCommittedTextSynchronizer { _, _ in commits += 1 }
        let context = fixture.editor.context
        let selection = fixture.editor.windowPresentationSnapshot(scrollFraction: 0.4)
        let generation = fixture.editor.generation
        fixture.dispatcher.operations = []
        fixture.dispatcher.queryMutation = { result in
            var context = result["context"] as! [String: Any]
            context["undoLabel"] = "Untrusted query Undo"
            result["context"] = context
        }
        let (revision, extent) = try await fixture.editor.currentChatMetadata()
        #expect(revision == .editorSnapshot(DocumentFingerprint(content: source)))
        #expect(extent == .range(.init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3)))
        #expect(fixture.dispatcher.operations == [.queryText])
        #expect(fixture.editor.checkedSource.utf8.elementsEqual(source.utf8))
        #expect(!fixture.editor.isDirty && fixture.editor.generation == generation)
        #expect(fixture.editor.context == context)
        #expect(fixture.editor.windowPresentationSnapshot(scrollFraction: 0.4) == selection)
        #expect(fixture.editor.preferredDocumentFocusTarget == .editor)
        #expect(sourceChanges == 0 && commits == 0)

        fixture.dispatcher.queryMutation = nil
        fixture.select([.init(anchor: 0, head: 0), .init(anchor: 5, head: 14)])
        let multiple = try await fixture.editor.currentChatMetadata()
        #expect(multiple.0 == revision && multiple.1 == .unavailable(.multipleSelections))
        let beforeInvalidDispatch = fixture.dispatcher.operations.count
        do {
            _ = try await fixture.editor.send(.selectAll, in: fixture.webView, observingOnly: true)
            Issue.record("Observation-only dispatch admitted a selection mutation")
        } catch MarkdownEditorSession.SessionError.invalidResult {
            // The invalid operation must be rejected before bridge dispatch.
        } catch { Issue.record("Observation-only dispatch rejected with an unexpected error type") }
        #expect(fixture.dispatcher.operations.count == beforeInvalidDispatch)
    }

    @Test("Loading, composition and opaque bridge failure disclose only fixed unavailable reasons")
    func editorUnavailableReasons() async throws {
        let unloaded = MarkdownEditorSession(bridgeDispatcher: FakeBridge())
        let loading = try await unloaded.currentChatMetadata()
        #expect(loading.0 == .unavailable(.loading) && loading.1 == .unavailable(.loading))
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        fixture.select([.init(anchor: 5, head: 14)], composing: true)
        fixture.dispatcher.operations = []
        let composing = try await fixture.editor.currentChatMetadata()
        #expect(composing.0 == .unavailable(.composing) && composing.1 == .unavailable(.composing))
        #expect(fixture.dispatcher.operations.isEmpty)
        fixture.select([.init(anchor: 5, head: 14)])
        fixture.dispatcher.queryFailure = NSError(
            domain: "synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE SOURCE /private/synthetic/path secret-token"])
        let failed = try await fixture.editor.currentChatMetadata()
        #expect(failed.0 == .unavailable(.sourceSnapshotUnavailable))
        #expect(failed.1 == .unavailable(.sourceMappingUnavailable))
        let json = String(decoding: try JSONEncoder().encode([failed.0.jsonValue, failed.1.jsonValue]), as: UTF8.self)
        #expect(!json.contains("PRIVATE") && !json.contains("/private") && !json.contains("secret-token"))
        #expect(!fixture.editor.isDirty && fixture.editor.errorMessage == nil)
    }

    @Test("Title focus does not expose the retained body selection as the current selection")
    func titleFocusWithholdsBodySelection() async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        let ranges = [MarkdownEditorSelectionRange(anchor: 5, head: 14)]
        fixture.select(ranges, focusTarget: .title)
        let retainedContext = fixture.editor.context
        let title = try await fixture.editor.currentChatMetadata()
        #expect(title.0 == .editorSnapshot(DocumentFingerprint(content: source)))
        #expect(title.1 == .unavailable(.sourceMappingUnavailable))
        #expect(fixture.editor.context == retainedContext && !fixture.editor.hasNonemptySelection)
        fixture.select(ranges, focusTarget: .editor)
        let body = try await fixture.editor.currentChatMetadata()
        #expect(body.0 == title.0 && body.1 == .range(.init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3)))
    }

    @Test(
        "Observation rejects mismatching source, generation and source-change claims without reconciling the editor",
        arguments: ["source", "generation", "sourceChanged", "selection"])
    func rejectsInconsistentQuery(kind: String) async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        fixture.select([.init(anchor: 5, head: 14)])
        var callbacks = 0
        fixture.editor.installSourceChangeHandler { callbacks += 1 }
        let context = fixture.editor.context
        fixture.dispatcher.queryMutation = { result in
            switch kind {
            case "source": result["text"] = "Different private source"
            case "generation": result["resultingGeneration"] = 1
            case "sourceChanged": result["sourceChanged"] = true
            default:
                result["selections"] = [["anchor": 0, "head": 0]]
                result["context"] = nil
            }
        }
        await expectFailure(.staleRevision) { _ = try await fixture.editor.currentChatMetadata() }
        #expect(fixture.editor.checkedSource.utf8.elementsEqual(source.utf8))
        #expect(fixture.editor.generation == 0 && !fixture.editor.isDirty && callbacks == 0)
        #expect(fixture.editor.context == context)
    }

    @Test("Source changes and selection or focus leave-and-return revoke an in-flight metadata query", arguments: ["source", "selection", "focus"])
    func editorDepartureDuringQuery(change: String) async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        let originalSelection = [MarkdownEditorSelectionRange(anchor: 5, head: 14)]
        fixture.select(originalSelection, focusTarget: .editor)
        fixture.dispatcher.holdQuery = true
        let pending = Task { try await fixture.editor.currentChatMetadata() }
        defer { pending.cancel() }
        try await wait { fixture.dispatcher.hasPendingQuery }
        if change == "source" {
            let end = EditorSourceOffsetMap(source: source).editorUTF16Length
            #expect(
                fixture.editor.acceptEditorChanges(
                    [.init(from: end, to: end, insert: "!", exactInsert: "!")], baseGeneration: 0, resultingGeneration: 1))
        } else if change == "selection" {
            fixture.select([.init(anchor: 0, head: 0)])
            fixture.select(originalSelection)
        } else {
            fixture.select(originalSelection, focusTarget: .title)
            fixture.select(originalSelection, focusTarget: .editor)
        }
        fixture.dispatcher.releaseQuery()
        await expectFailure(.staleRevision) { _ = try await pending.value }
        #expect(fixture.editor.checkedSource.utf8.elementsEqual((source + (change == "source" ? "!" : "")).utf8))
    }

    @Test("Native focus authorization revokes a held query with or without returning to its origin", arguments: [false, true])
    func nativeFocusDepartureDuringQuery(returnsToOrigin: Bool) async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        fixture.select([.init(anchor: 5, head: 14)], focusTarget: .title)
        let context = fixture.editor.context
        let rendererRevision = fixture.dispatcher.interactionRevision
        fixture.dispatcher.operations = []
        fixture.dispatcher.holdQuery = true
        let pending = Task { try await fixture.editor.currentChatMetadata() }
        defer { pending.cancel() }
        try await wait { fixture.dispatcher.hasPendingQuery }

        fixture.editor.authorizeAutomaticFocus(target: .editor)
        if returnsToOrigin { fixture.editor.authorizeAutomaticFocus(target: .title) }
        #expect(fixture.editor.preferredDocumentFocusTarget == (returnsToOrigin ? .title : .editor))
        #expect(fixture.dispatcher.interactionRevision == rendererRevision)
        #expect(fixture.editor.context == context && fixture.editor.generation == 0)
        fixture.dispatcher.releaseQuery()
        await expectFailure(.staleRevision) { _ = try await pending.value }
        #expect(fixture.dispatcher.operations == [.queryText])
        #expect(!fixture.editor.isDirty && fixture.editor.checkedSource.utf8.elementsEqual(source.utf8))

        let fresh = try await fixture.editor.currentChatMetadata()
        #expect(fresh.0 == .editorSnapshot(DocumentFingerprint(content: source)))
        let freshSelection: AgentChatDocumentObservation.Selection =
            returnsToOrigin ? .unavailable(.sourceMappingUnavailable) : .range(.init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3))
        #expect(fresh.1 == freshSelection)
    }

    @Test("A renderer revision departure in a held reply revokes identical final source and selection")
    func rendererRevisionDepartureDuringQuery() async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        let ranges = [MarkdownEditorSelectionRange(anchor: 5, head: 14)]
        fixture.select(ranges, focusTarget: .editor)
        let context = fixture.editor.context
        let capturedRevision = fixture.dispatcher.interactionRevision
        fixture.dispatcher.operations = []
        fixture.dispatcher.holdQuery = true
        let pending = Task { try await fixture.editor.currentChatMetadata() }
        defer { pending.cancel() }
        try await wait { fixture.dispatcher.hasPendingQuery }

        // The renderer has left and returned within one frame. Native selection
        // has not changed, but the reply must carry its advanced interaction token.
        fixture.dispatcher.interactionRevision += 2
        let returnedRevision = fixture.dispatcher.interactionRevision
        fixture.dispatcher.queryMutation = { $0["interactionRevision"] = returnedRevision }
        #expect(fixture.editor.rendererInteractionRevision == capturedRevision)
        #expect(fixture.editor.context == context && fixture.editor.generation == 0)
        fixture.dispatcher.releaseQuery()
        await expectFailure(.staleRevision) { _ = try await pending.value }
        #expect(fixture.dispatcher.operations == [.queryText])
        #expect(fixture.editor.rendererInteractionRevision == capturedRevision)
        #expect(!fixture.editor.isDirty && fixture.editor.checkedSource.utf8.elementsEqual(source.utf8))

        fixture.dispatcher.queryMutation = nil
        fixture.select(ranges, focusTarget: .editor)
        let fresh = try await fixture.editor.currentChatMetadata()
        #expect(fresh.0 == .editorSnapshot(DocumentFingerprint(content: source)))
        #expect(fresh.1 == .range(.init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3)))
    }

    @Test(
        "Held metadata replies reject missing or invalid renderer revisions without changing native state",
        arguments: ["missing", "negative", "boolean", "fractional", "tooLarge"])
    func invalidRendererRevisionInHeldQuery(kind: String) async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        fixture.select([.init(anchor: 5, head: 14)], focusTarget: .editor)
        let context = fixture.editor.context
        let capturedRevision = fixture.editor.rendererInteractionRevision
        fixture.dispatcher.holdQuery = true
        let pending = Task { try await fixture.editor.currentChatMetadata() }
        defer { pending.cancel() }
        try await wait { fixture.dispatcher.hasPendingQuery }
        fixture.dispatcher.queryMutation = { result in
            switch kind {
            case "missing": result.removeValue(forKey: "interactionRevision")
            case "negative": result["interactionRevision"] = -1
            case "boolean": result["interactionRevision"] = true
            case "fractional": result["interactionRevision"] = 1.5
            default: result["interactionRevision"] = 9_007_199_254_740_992
            }
        }
        fixture.dispatcher.releaseQuery()
        await expectFailure(.staleRevision) { _ = try await pending.value }
        #expect(fixture.editor.rendererInteractionRevision == capturedRevision)
        #expect(fixture.editor.context == context && fixture.editor.generation == 0)
        #expect(!fixture.editor.isDirty && fixture.editor.checkedSource.utf8.elementsEqual(source.utf8))
        fixture.dispatcher.queryMutation = nil
        let fresh = try await fixture.editor.currentChatMetadata()
        #expect(fresh.0 == .editorSnapshot(DocumentFingerprint(content: source)))
    }

    @Test("Clean commit preserves the latest renderer revision for immediate metadata", arguments: [false, true])
    func cleanCommitRetainsRendererRevision(reportBeforeRebase: Bool) async throws {
        let fixture = try await EditorFixture.make(source: source)
        defer { fixture.close() }
        let ranges = [MarkdownEditorSelectionRange(anchor: 5, head: 14)]
        let committedSource = source + "!"
        let fingerprint = DocumentFingerprint(content: committedSource)
        let previousFingerprint = fixture.editor.startingFingerprint
        let end = EditorSourceOffsetMap(source: source).editorUTF16Length
        try #require(
            fixture.editor.acceptEditorChanges(
                [.init(from: end, to: end, insert: "!", exactInsert: "!")], baseGeneration: 0, resultingGeneration: 1))
        fixture.dispatcher.source = committedSource
        fixture.dispatcher.generation = 1
        fixture.select(ranges, focusTarget: .editor)
        let initialRevision = fixture.dispatcher.interactionRevision
        let context = fixture.editor.context
        #expect(fixture.editor.isDirty && previousFingerprint != fingerprint.sha256)
        if reportBeforeRebase {
            fixture.dispatcher.commitResponseWillReturn = {
                #expect(fixture.editor.startingFingerprint == previousFingerprint)
                // A newer renderer report arrives after the reply was captured
                // but before native acknowledgement rebases its fingerprint.
                fixture.select(ranges, focusTarget: .editor)
            }
        }
        let acknowledgement = try await fixture.editor.acknowledgeCommittedSnapshot(
            expectedText: committedSource, committedText: committedSource, fingerprint: fingerprint,
            documentID: fixture.editor.documentID)
        let admittedRevision = initialRevision + (reportBeforeRebase ? 1 : 0)
        #expect(acknowledgement == .clean && !fixture.editor.isDirty)
        #expect(fixture.editor.startingFingerprint == fingerprint.sha256)
        #expect(fixture.editor.rendererInteractionRevision == admittedRevision)
        #expect(fixture.editor.context == context && fixture.editor.generation == 1)
        let fresh = try await fixture.editor.currentChatMetadata()
        #expect(fresh.0 == .editorSnapshot(fingerprint))
        #expect(fresh.1 == .range(.init(startUTF8: 8, endUTF8: 25, startLine: 2, endLine: 3)))

        // Even an acknowledgement with identical source, base fingerprint,
        // generation and interaction must revoke an older request lifetime.
        fixture.dispatcher.holdQuery = true
        let pending = Task { try await fixture.editor.currentChatMetadata() }
        defer { pending.cancel() }
        try await wait { fixture.dispatcher.hasPendingQuery }
        let repeated = try await fixture.editor.acknowledgeCommittedSnapshot(
            expectedText: committedSource, committedText: committedSource, fingerprint: fingerprint,
            documentID: fixture.editor.documentID)
        #expect(repeated == .clean && fixture.editor.rendererInteractionRevision == admittedRevision)
        fixture.dispatcher.releaseQuery()
        await expectFailure(.staleRevision) { _ = try await pending.value }
        let afterRevocation = try await fixture.editor.currentChatMetadata()
        #expect(afterRevocation.0 == fresh.0 && afterRevocation.1 == fresh.1)
        #expect(fixture.editor.checkedSource.utf8.elementsEqual(committedSource.utf8))
        #expect(fixture.editor.context == context && !fixture.editor.isDirty)
    }

    @Test("Review reports saved-source selection only for its displayed revision and never borrows a dirty editor fingerprint")
    func reviewSourceCurrentness() async throws {
        try await withStore { store, root in
            let suite = "Scholium.ChatObservation.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = ChatSidebarPreferences(defaults: defaults)
            preferences.isEnabled = true
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let file = analyses.appendingPathComponent("Source.md")
            try Data(source.utf8).write(to: file)
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: triptych, triptychName: "Observation Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id, chatSidebarPreferences: preferences)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            window.documentController.rememberPresentationMode(.read)
            try await window.openNote("Source.md")
            _ = window.shellState.activateSidebar(.chat)
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            defer { session.cancelScheduledWork() }
            session.suppressAutosave = true
            session.originalEditingSource = source
            session.editingSource = source
            session.preparePresentationMode(.read)
            window.rememberPresentationMode(.read)
            try await wait { window.presentedDocumentMode == .read }
            session.renderedReadFingerprint = DocumentFingerprint(content: source).sha256
            session.readSelection = .init(startLine: 2, endLine: 2, excerpt: "原文", utf16LowerBound: 12, utf16UpperBound: 14)
            let current = try await window.observeChatDocument(admitted: { true })
            #expect(current.activeNote?.revision == .savedSource(DocumentFingerprint(content: source)))
            #expect(current.activeNote?.selection == .range(.init(startUTF8: 17, endUTF8: 23, startLine: 2, endLine: 2)))
            #expect(current.activeNote?.dirty == false)
            session.renderedReadFingerprint = "older-rendered-revision"
            let stale = try await window.observeChatDocument(admitted: { true })
            #expect(stale.activeNote?.revision == .savedSource(DocumentFingerprint(content: source)))
            #expect(stale.activeNote?.selection == .unavailable(.staleRenderer))
            session.renderedReadFingerprint = DocumentFingerprint(content: source).sha256
            let dirty = source + "PRIVATE UNSAVED SOURCE"
            session.editingSource = dirty
            session.editError = "PRIVATE SAVE ERROR /private/fixture"
            let retained = try await window.observeChatDocument(admitted: { true })
            #expect(retained.activeNote?.revision == .unavailable(.sourceSnapshotUnavailable))
            #expect(retained.activeNote?.selection == .unavailable(.staleRenderer) && retained.activeNote?.dirty == true)
            #expect(retained.errorCodes == ["document_save"])
            let json = String(decoding: try JSONEncoder().encode(retained.jsonValue), as: UTF8.self)
            #expect(!json.contains("PRIVATE") && !json.contains("/private"))
            #expect(session.editingSource.utf8.elementsEqual(dirty.utf8))
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            preferences.isEnabled = false
            await expectFailure(.workspaceNotReady) { _ = try await window.observeChatDocument(admitted: { true }) }
        }
    }

    @Test(
        "A failed close or window-context leave-and-return revokes the pending observation",
        arguments: ["failedClose", "transfer", "sidebar", "chatDisabled", "vault", "document", "mode"])
    func windowDepartureDuringQuery(change: String) async throws {
        try await withStore { store, root in
            let suite = "Scholium.ChatObservation.WindowDeparture.\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = ChatSidebarPreferences(defaults: defaults)
            preferences.isEnabled = true
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            let file = analyses.appendingPathComponent("Source.md")
            try Data(source.utf8).write(to: file)
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: triptych, triptychName: "Observation Departure Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id, chatSidebarPreferences: preferences)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            window.rememberPresentationMode(.read)
            try await window.openNote("Source.md")
            _ = window.shellState.activateSidebar(.chat)

            let document = try #require(window.documentController.selectedDocument)
            let descriptor = try #require(document.workspaceDescriptor)
            let editor = try await EditorFixture.make(source: source)
            defer { editor.close() }
            let session = DocumentSessionModel(key: descriptor.sessionKey, editorSession: editor.editor)
            session.suppressAutosave = true
            session.originalEditingSource = source
            session.editingSource = source
            session.editingRevision = DocumentFingerprint(content: source)
            defer { session.cancelScheduledWork() }
            window.rememberPresentationMode(.source)
            window.documentController.receiveSessionTransfer(
                .init(document: document, session: session, snapshot: window.documentController.snapshots[descriptor.sessionKey], mode: .source))
            session.beginEditing(in: .source)
            try await wait { window.presentedDocumentMode == .source }
            editor.select([.init(anchor: 5, head: 14)])
            let context = editor.editor.context
            // The injected close flusher fails before changing the editor. The
            // close-attempt sequence itself must revoke this observation.
            window.windowCloseCoordinator = WindowCloseCoordinator(
                lifecyclePolicy: ScholiumLifecyclePolicy(), persistenceCoordinator: window.windowSessionPersistenceCoordinator,
                flushContent: { _ in throw SyntheticSaveFailure.failed }, presentationSnapshot: { nil },
                recordPersistenceFailure: { _ in }, finalizeDependencies: {})
            let closeAttempt = window.windowCloseCoordinator.closeAttemptSequence
            editor.dispatcher.holdQuery = true
            let pending = Task { try await window.observeChatDocument(admitted: { true }) }
            defer { pending.cancel() }
            try await wait { editor.dispatcher.hasPendingQuery }
            switch change {
            case "failedClose":
                do {
                    _ = try await window.windowCloseCoordinator.prepare()
                    Issue.record("Synthetic close unexpectedly succeeded")
                } catch SyntheticSaveFailure.failed {
                    #expect(!window.windowCloseCoordinator.isPreparingOrFinalized)
                    #expect(window.windowCloseCoordinator.closeAttemptSequence > closeAttempt)
                }
            case "transfer":
                window.transferInProgress = true
                window.transferInProgress = false
            case "sidebar":
                window.shellState.recordLibraryVisibility(false)
                window.shellState.recordLibraryVisibility(true)
            case "chatDisabled":
                preferences.isEnabled = false
                preferences.isEnabled = true
                #expect(window.shellState.sidebarContent == .library)
                // Enabling Chat does not navigate. Explicitly return before
                // releasing the old request, which must remain revoked.
                _ = window.shellState.activateSidebar(.chat)
            case "vault":
                window.shellState.selectLibraryWorkspace(.topicKnowledge)
                window.shellState.selectLibraryWorkspace(.paperAnalysis)
            case "document":
                window.documentController.selectUnavailableDocument(vaultID: descriptor.reference.vaultID, relativePath: "Missing.md")
                window.documentController.selectDocument(document)
            default:
                window.rememberPresentationMode(.read)
                window.rememberPresentationMode(.source)
            }
            #expect(editor.editor.context == context && editor.editor.generation == 0)
            editor.dispatcher.releaseQuery()
            await expectFailure(.workspaceNotReady) { _ = try await pending.value }
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            #expect(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
            _ = window.shellState.activateSidebar(.chat)
            window.shellState.recordLibraryVisibility(true)
            let fresh = try await window.observeChatDocument(admitted: { true })
            #expect(fresh.activeNote?.revision == .editorSnapshot(DocumentFingerprint(content: source)))
        }
    }

    private func expectFailure(_ code: ScholiumMCPFailureCode, operation: () async throws -> Void) async {
        do {
            try await operation()
            Issue.record("Observation unexpectedly succeeded instead of \(code.rawValue)")
        } catch let failure as ScholiumMCPFailure {
            #expect(failure == ScholiumMCPFailure.chatObservation(code))
        } catch { Issue.record("Observation exposed an unexpected error type: \(type(of: error))") }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() {
            try #require(ContinuousClock.now < deadline, "Synthetic observation did not reach its expected boundary")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func withStore(_ body: (WorkspaceStore, URL) async throws -> Void) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/chat-document-observation/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            try await body(store, root)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    @MainActor private final class PublishedScope: ObservableObject {
        @Published var selection = "origin"
    }

    private enum SyntheticSaveFailure: Error { case failed }

    @MainActor private struct EditorFixture {
        let editor: MarkdownEditorSession
        let webView: WKWebView
        let dispatcher: FakeBridge

        static func make(source: String) async throws -> Self {
            let dispatcher = FakeBridge()
            let editor = MarkdownEditorSession(bridgeDispatcher: dispatcher)
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let webView = WKWebView(frame: .zero, configuration: configuration)
            editor.attach(webView)
            editor.loadDocument(source, documentID: editor.bridgeDocumentID, mode: .source)
            editor.editorBecameReady()
            let loaded = try await editor.waitUntilLoadedForSave()
            try #require(loaded)
            return .init(editor: editor, webView: webView, dispatcher: dispatcher)
        }

        func select(_ selections: [MarkdownEditorSelectionRange], composing: Bool = false, focusTarget: WindowDocumentFocusTarget? = nil) {
            dispatcher.interactionRevision += 1
            dispatcher.selections = selections
            dispatcher.composing = composing
            editor.updateInteraction(
                selections: selections, line: 2, column: 1, lineCount: 3,
                documentVersion: editor.generation, interactionRevision: dispatcher.interactionRevision,
                focusTarget: focusTarget, context: dispatcher.context)
        }

        func close() {
            dispatcher.releaseQuery()
            dispatcher.commitResponseWillReturn = nil
            editor.removeSourceChangeHandler()
            editor.removeCommittedTextSynchronizer()
            editor.detach(webView)
        }
    }

    @MainActor private final class FakeBridge: MarkdownEditorBridgeDispatching {
        var source = ""
        var generation = 0
        var interactionRevision = 0
        var selections = [MarkdownEditorSelectionRange(anchor: 0, head: 0)]
        var composing = false
        var operations: [MarkdownEditorOperation] = []
        var queryMutation: ((inout [String: Any]) -> Void)?
        var queryFailure: Error?
        var commitResponseWillReturn: (() -> Void)?
        var holdQuery = false
        private var pendingQuery: CheckedContinuation<Void, Never>?
        var hasPendingQuery: Bool { pendingQuery != nil }
        var context: MarkdownEditorContext {
            .init(
                selections: selections, activeInlineConstructs: [], activeBlockConstructs: [], tablePosition: nil,
                composing: composing, availableCommands: [], undoLabel: "Original Undo", redoLabel: "Original Redo")
        }

        func releaseQuery() {
            let continuation = pendingQuery
            pendingQuery = nil
            continuation?.resume()
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            operations.append(request.operation)
            if case .initialize(let source, _, _, let selection, _) = request.operation {
                self.source = source
                generation = 0
                selections = selection.map { [$0] } ?? [.init(anchor: 0, head: 0)]
            }
            var result: [String: Any] = [
                "requestID": request.requestID.uuidString, "resultingGeneration": generation,
                "interactionRevision": interactionRevision,
                "sourceChanged": false, "accepted": true,
                "selections": selections.map { ["anchor": $0.anchor, "head": $0.head] },
                "context": try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)),
            ]
            if case .queryText = request.operation {
                if let queryFailure { throw queryFailure }
                result["text"] = source
                if holdQuery {
                    holdQuery = false
                    await withCheckedContinuation { pendingQuery = $0 }
                }
                queryMutation?(&result)
            }
            if case .acknowledgeCommittedSnapshot(let expected, let committed, _, _, _) = request.operation {
                let superseded = !source.utf8.elementsEqual(expected.utf8)
                if !superseded { source = committed }
                result["text"] = source
                result["commitSuperseded"] = superseded
                let beforeReturn = commitResponseWillReturn
                commitResponseWillReturn = nil
                beforeReturn?()
            }
            return result
        }
    }
}
