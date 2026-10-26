import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Document autosave scheduling", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct DocumentAutosaveSchedulingTests {
    @Test("Idle input still saves after the existing 850 millisecond debounce")
    func idleInputKeepsExistingDelay() async throws {
        let fixture = try await Fixture.make()
        do {
            try fixture.insert("Idle input 中文 😀 e\u{301}.\r\n")
            await fixture.clock.waitForSleepCalls(1)
            let timer = try #require(fixture.session.autosaveTask)
            fixture.clock.advance(by: .milliseconds(849))
            #expect(fixture.clock.resumeDue() == 0)
            #expect(fixture.commits.documents.isEmpty)
            fixture.clock.advance(by: .milliseconds(1))
            #expect(fixture.clock.resumeDue() == 1)
            await timer.value
            #expect(fixture.commits.documents.count == 1)
            #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
            #expect(!fixture.session.hasUnsavedChanges)
            #expect(fixture.session.autosavePendingSince == nil && fixture.session.autosaveLastActivity == nil)
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test("Continuous accepted input admits one guarded save within five seconds")
    func continuousInputCannotPostponeSaveBeyondFiveSeconds() async throws {
        let fixture = try await Fixture.make()
        do {
            try fixture.insert("First accepted input.\r\n")
            await fixture.clock.waitForSleepCalls(1)
            // A finite main-actor workload accepts input every 50 virtual ms.
            // The already sleeping timer may run after this batch, as it may
            // after a busy native delivery turn; no wall-clock sleep is used.
            for ordinal in 1...100 {
                fixture.clock.advance(by: .milliseconds(50))
                try fixture.insert("Input \(ordinal) 中文 😀 e\u{301}.\r\n")
            }
            #expect(fixture.clock.resumeDue() == 1)
            await fixture.clock.waitForSleepCalls(2)
            // OLD idle-only behavior parks again until virtual 5.85s and has
            // no admitted source attempt here. The authorized cap must admit
            // the ordinary save owner at virtual 5s despite the final input.
            let admitted = fixture.session.activeSaveAttempt
            try #require(admitted != nil || fixture.commits.documents.count == 1)
            _ = try await admitted?.task.value
            #expect(fixture.commits.documents.count == 1)
            #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
            #expect(fixture.clock.maximumPendingSleeperCount == 1)
            print(
                "AUTOSAVE_VIRTUAL inputs=101 elapsed_ms=5000 commits=\(fixture.commits.documents.count) max_pending_timers=\(fixture.clock.maximumPendingSleeperCount)"
            )
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test("An overdue composing buffer resumes once on composition end without a text delta")
    func compositionEndResumesParkedEpoch() async throws {
        let fixture = try await Fixture.make()
        do {
            let original = try Data(contentsOf: fixture.sourceURL)
            try fixture.insert("Retained marked input.\r\n")
            await fixture.clock.waitForSleepCalls(1)
            let timer = try #require(fixture.session.autosaveTask)
            try fixture.setComposing(true)
            fixture.clock.advance(by: .seconds(5))
            #expect(fixture.clock.resumeDue() == 1)
            await timer.value
            #expect(fixture.session.autosaveDeferredForComposition)
            #expect(fixture.commits.documents.isEmpty && fixture.bridge.queryCount == 0)
            #expect(fixture.session.editError == nil && fixture.session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.sourceURL) == original)
            // Only the interaction envelope changes; no source activity is sent.
            try fixture.setComposing(false)
            await fixture.clock.waitForSleepCalls(2)
            let admitted = fixture.session.activeSaveAttempt
            try #require(admitted != nil || fixture.commits.documents.count == 1)
            _ = try await admitted?.task.value
            #expect(fixture.commits.documents.count == 1)
            #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
            #expect(!fixture.session.autosaveDeferredForComposition)
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test("Input accepted during a held acknowledgement retains its original successor age")
    func newerInputDuringAcknowledgementKeepsItsAge() async throws {
        let fixture = try await Fixture.make()
        let acknowledgement = AutosaveGate()
        var held = false
        fixture.bridge.beforeAcknowledgement = {
            guard !held else { return }
            held = true
            await acknowledgement.hold()
        }
        do {
            try fixture.insert("First saved candidate.\r\n")
            await fixture.clock.waitForSleepCalls(1)
            let firstTimer = try #require(fixture.session.autosaveTask)
            fixture.clock.advance(by: .milliseconds(850))
            #expect(fixture.clock.resumeDue() == 1)
            await acknowledgement.waitUntilEntered()
            try #require(fixture.commits.documents.count == 1)
            let firstCommit = try #require(fixture.commits.documents.first)
            try fixture.insert("Newer exact input 中文 😀 e\u{301}.\r\n")
            let pendingSince = try #require(fixture.session.autosavePendingSince)
            fixture.clock.advance(by: .seconds(6))
            #expect(fixture.clock.resumeDue() == 0)
            #expect(fixture.session.autosavePendingSince == pendingSince)
            #expect(fixture.commits.documents.count == 1)
            #expect(try Data(contentsOf: fixture.sourceURL) == firstCommit.sourceBytes)
            acknowledgement.release()
            await firstTimer.value
            await fixture.commits.waitForCount(2)
            _ = try await fixture.session.activeSaveAttempt?.task.value
            try #require(fixture.commits.documents.count == 2)
            #expect(fixture.bridge.queryCount == 2)
            #expect(fixture.commits.documents[0].sourceBytes != fixture.commits.documents[1].sourceBytes)
            #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
            #expect(fixture.session.autosavePendingSince == nil)
            #expect(fixture.session.pendingEditorCommit == nil && !fixture.session.hasUnsavedChanges)
            await fixture.close()
        } catch {
            acknowledgement.release()
            await fixture.close()
            throw error
        }
    }

    enum FailureBoundary: CaseIterable, Equatable, Sendable { case query, acknowledgement, conflict }

    @Test("A failed or conflicting autosave disarms its clock and preserves explicit Retry authority", arguments: FailureBoundary.allCases)
    func failureDoesNotBecomeATimedRetry(boundary: FailureBoundary) async throws {
        let fixture = try await Fixture.make()
        do {
            let original = try Data(contentsOf: fixture.sourceURL)
            try fixture.insert("Unsaved exact researcher input.\r\n")
            switch boundary {
            case .query: fixture.bridge.failNextQuery = true
            case .acknowledgement: fixture.bridge.failNextAcknowledgement = true
            case .conflict: try Data("# External source must remain\r\n".utf8).write(to: fixture.sourceURL)
            }
            await fixture.clock.waitForSleepCalls(1)
            let timer = try #require(fixture.session.autosaveTask)
            fixture.clock.advance(by: .milliseconds(850))
            #expect(fixture.clock.resumeDue() == 1)
            await timer.value
            #expect(fixture.session.hasUnsavedChanges && fixture.session.editError != nil)
            #expect(fixture.session.autosavePendingSince == nil && fixture.session.autosaveTask == nil)
            let retained = Data(fixture.editor.checkedSource.utf8)
            let disk = try Data(contentsOf: fixture.sourceURL)
            let committed = fixture.commits.documents.count
            #expect(committed == (boundary == .acknowledgement ? 1 : 0))
            fixture.clock.advance(by: .seconds(60))
            #expect(fixture.clock.resumeDue() == 0 && fixture.commits.documents.count == committed)
            #expect(Data(fixture.editor.checkedSource.utf8) == retained)
            #expect(try Data(contentsOf: fixture.sourceURL) == disk)
            if boundary == .conflict {
                #expect(fixture.session.conflict != nil && !fixture.session.canRetrySave)
                #expect(disk != original && disk != retained)
            } else {
                #expect(fixture.session.canRetrySave)
                if boundary == .query { #expect(disk == original) } else { #expect(fixture.session.pendingEditorCommit != nil) }
                await fixture.controller.persistEditingSource(session: fixture.session, target: fixture.target)
                #expect(fixture.commits.documents.count == 1, "Retry must acknowledge a proved commit without writing it again")
                #expect(fixture.session.pendingEditorCommit == nil && !fixture.session.hasUnsavedChanges)
                #expect(fixture.session.editError == nil)
                #expect(try Data(contentsOf: fixture.sourceURL) == retained)
            }
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test("A cancelled timer cannot clear or execute its successor")
    func cancelledTimerCannotConsumeSuccessor() async throws {
        let fixture = try await Fixture.make()
        do {
            try fixture.insert("First retained input.\r\n")
            await fixture.clock.waitForSleepCalls(1)
            let predecessor = try #require(fixture.session.autosaveTask)
            fixture.session.cancelAutosave()
            try fixture.insert("Successor input.\r\n")
            let successor = try #require(fixture.session.autosaveTask)
            let token = try #require(fixture.session.autosaveToken)
            await fixture.clock.waitForSleepCalls(2)
            await predecessor.value
            #expect(fixture.session.autosaveToken == token)
            #expect(fixture.commits.documents.isEmpty)
            fixture.clock.advance(by: .milliseconds(850))
            #expect(fixture.clock.resumeDue() == 1)
            await successor.value
            #expect(fixture.commits.documents.count == 1)
            #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @Test("Finite continuous input coalesces into four exact five-second saves")
    func finiteContinuousInputCoalescesWork() async throws {
        let fixture = try await Fixture.make()
        do {
            for epoch in 1...4 {
                let calls = fixture.clock.sleepCalls
                try fixture.insert("Epoch \(epoch).\r\n")
                await fixture.clock.waitForSleepCalls(calls + 1)
                let timer = try #require(fixture.session.autosaveTask)
                for ordinal in 1...100 {
                    fixture.clock.advance(by: .milliseconds(50))
                    try fixture.insert("Input \(epoch):\(ordinal) 中文 😀 e\u{301}.\r\n")
                }
                #expect(fixture.clock.resumeDue() == 1)
                await timer.value
                #expect(fixture.commits.documents.count == epoch)
                #expect(try Data(contentsOf: fixture.sourceURL) == Data(fixture.bridge.source.utf8))
                #expect(!fixture.session.hasUnsavedChanges && fixture.session.autosavePendingSince == nil)
            }
            #expect(fixture.bridge.queryCount == 4 && fixture.clock.maximumPendingSleeperCount == 1)
            print(
                "AUTOSAVE_VIRTUAL_STRESS inputs=404 elapsed_ms=20000 commits=4 full_queries=\(fixture.bridge.queryCount) max_pending_timers=\(fixture.clock.maximumPendingSleeperCount)"
            )
            await fixture.close()
        } catch {
            await fixture.close()
            throw error
        }
    }

    @MainActor
    private final class CommitReceipts {
        var documents: [NoteDocument] = []
        private let changes = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))

        func receive(_ document: NoteDocument) {
            documents.append(document)
            changes.continuation.yield(documents.count)
        }

        func waitForCount(_ count: Int) async {
            guard documents.count < count else { return }
            for await current in changes.stream where current >= count { return }
        }

        func close() { changes.continuation.finish() }
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let sourceURL: URL
        let store: WorkspaceStore
        let controller: DocumentController
        let session: DocumentSessionModel
        let target: DocumentEditingTarget
        let editor: MarkdownEditorSession
        let webView: WKWebView
        let bridge: SnapshotBridge
        let clock: ManualAutosaveClock
        let commits: CommitReceipts

        init(
            root: URL, sourceURL: URL, store: WorkspaceStore, controller: DocumentController,
            session: DocumentSessionModel, target: DocumentEditingTarget, editor: MarkdownEditorSession,
            webView: WKWebView, bridge: SnapshotBridge, clock: ManualAutosaveClock, commits: CommitReceipts
        ) {
            self.root = root
            self.sourceURL = sourceURL
            self.store = store
            self.controller = controller
            self.session = session
            self.target = target
            self.editor = editor
            self.webView = webView
            self.bridge = bridge
            self.clock = clock
            self.commits = commits
        }

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/autosave-scheduling/\(UUID())", isDirectory: true)
            let triptych = root.appendingPathComponent("Triptych", isDirectory: true)
            let vaults = ["Analyses", "Topics", "Works"].map { triptych.appendingPathComponent($0, isDirectory: true) }
            for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
            let sourceURL = vaults[1].appendingPathComponent("Source.md", isDirectory: false)
            let original = "\u{FEFF}# Exact source\r\n\r\nResearcher e\u{301} 中文 😀.\r\n"
            try Data(original.utf8).write(to: sourceURL)
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support", isDirectory: true))
            let bridge = SnapshotBridge()
            let editor = MarkdownEditorSession(bridgeDispatcher: bridge)
            let webView = WKWebView()
            do {
                let capabilities = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                    portableContainerURL: triptych, triptychName: "Autosave scheduling fixture")
                let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
                let summary = try #require(vault.documents.first { $0.id.relativePath == "Source.md" })
                let snapshot = try await capabilities.documents.hydrate(summary)
                let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: try #require(snapshot.stableIdentity.resolvedID))
                let target = DocumentEditingTarget.workspace(key)
                editor.attach(webView)
                editor.loadDocument(original, documentID: editor.bridgeDocumentID, mode: .source, citationSnapshot: snapshot.document.citationSnapshot)
                editor.editorBecameReady()
                try #require(try await editor.waitUntilLoadedForSave())
                let clock = ManualAutosaveClock()
                let commits = CommitReceipts()
                let controller = DocumentController(autosaveClock: clock.port)
                controller.bind(to: capabilities.documents, documentDidCommit: { commits.receive($0.document) })
                let session = DocumentSessionModel(key: key, editorSession: editor)
                controller.beginEditing(session: session, target: target, source: original, revision: snapshot.fingerprint, mode: .source)
                let document = WindowSelectedDocument.workspace(
                    .init(
                        sessionKey: key,
                        reference: .init(
                            vaultID: key.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                            relativePath: "Source.md", stableNoteID: key.noteID.uuidString)))
                controller.receiveSessionTransfer(.init(document: document, session: session, snapshot: snapshot, mode: .source), selecting: false)
                session.suppressAutosave = false
                return Fixture(
                    root: root, sourceURL: sourceURL, store: store, controller: controller, session: session,
                    target: target, editor: editor, webView: webView, bridge: bridge, clock: clock, commits: commits)
            } catch {
                editor.detach(webView)
                await store.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func insert(_ exact: String) throws {
            let end = EditorSourceOffsetMap(source: editor.checkedSource).editorUTF16Length
            let generation = editor.generation
            bridge.source += exact
            bridge.generation = generation + 1
            bridge.interactionRevision = max(bridge.interactionRevision, bridge.generation)
            bridge.dirty = true
            try #require(
                editor.acceptEditorChanges(
                    [.init(from: end, to: end, insert: exact.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: exact)],
                    baseGeneration: generation, resultingGeneration: generation + 1,
                    citationManaged: bridge.citationSnapshot != nil, citationData: bridge.citationData))
            try #require(editor.checkedSource.utf8.elementsEqual(bridge.source.utf8))
            controller.editorSourceDidChange(session: session, target: target)
        }

        func setComposing(_ composing: Bool) throws {
            bridge.interactionRevision += 1
            try #require(
                editor.updateInteraction(
                    selections: bridge.selections, line: 1, column: 0, lineCount: 1,
                    documentVersion: editor.generation, interactionRevision: bridge.interactionRevision,
                    context: .init(
                        selections: bridge.selections, activeInlineConstructs: [], activeBlockConstructs: [],
                        composing: composing, availableCommands: [], undoLabel: nil, redoLabel: nil)))
        }

        func close() async {
            let timer = session.autosaveTask
            let save = session.activeSaveAttempt?.task
            session.cancelScheduledWork()
            clock.cancelAll()
            commits.close()
            await timer?.value
            _ = await save?.result
            controller.unbind()
            editor.detach(webView)
            await store.shutdownApplicationRuntime()
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// The existing typed bridge is substituted, not native input or paint.
    @MainActor
    private final class SnapshotBridge: MarkdownEditorBridgeDispatching {
        var source = ""
        var generation = 0
        var interactionRevision = 0
        var dirty = false
        var queryCount = 0
        var failNextQuery = false
        var failNextAcknowledgement = false
        var beforeAcknowledgement: @MainActor () async -> Void = {}
        var citationSnapshot: ZoteroCitationSnapshot?
        var citationData: ZoteroCitationData?
        var selections = [MarkdownEditorSelectionRange(anchor: 0, head: 0)]

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            var text: String?
            var superseded: Bool?
            var recovery: [String: Any]?
            switch request.operation {
            case .initialize(let source, _, _, let initialSelection, let citationSnapshot, let restored, _):
                self.source = source
                self.citationSnapshot = citationSnapshot
                citationData = restored?.citationData ?? citationSnapshot?.data
                generation = restored?.generation ?? 0
                dirty = restored?.dirty ?? false
                selections = restored?.ranges ?? initialSelection.map { [$0] } ?? [.init(anchor: 0, head: 0)]
            case .queryText:
                queryCount += 1
                if failNextQuery {
                    failNextQuery = false
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                text = source
            case .acknowledgeCommittedSnapshot(let expected, let committed, _, let expectedCitations, let citations):
                await beforeAcknowledgement()
                if failNextAcknowledgement {
                    failNextAcknowledgement = false
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                let newer = !source.utf8.elementsEqual(expected.utf8) || citationData != expectedCitations
                citationSnapshot = citations
                if !newer {
                    source = committed
                    citationData = citations?.data
                }
                dirty = newer
                text = source
                superseded = newer
            case .captureRecovery:
                recovery = [
                    "documentID": request.documentID, "fingerprint": request.startingFingerprint,
                    "generation": generation, "ranges": selections.map { ["anchor": $0.anchor, "head": $0.head] },
                    "source": source, "undoHistoryPreserved": false, "hasHistory": generation > 0,
                    "dirty": dirty, "focusTarget": "editor",
                ]
                if let citationSnapshot { recovery?["citationSnapshot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationSnapshot)) }
                if let citationData { recovery?["citationData"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationData)) }
            default: break
            }
            var result: [String: Any] = [
                "requestID": request.requestID.uuidString, "resultingGeneration": generation,
                "interactionRevision": interactionRevision, "sourceChanged": false,
                "selections": selections.map { ["anchor": $0.anchor, "head": $0.head] },
                "accepted": true, "citationManaged": citationSnapshot != nil,
            ]
            if let text { result["text"] = text }
            if let superseded { result["commitSuperseded"] = superseded }
            if let citationData { result["citationData"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationData)) }
            if let recovery { result["recovery"] = recovery }
            return result
        }
    }
}

@MainActor
private final class ManualAutosaveClock {
    private struct Sleeper {
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, Error>
    }
    private var now = ContinuousClock.now
    private var sleepers: [UUID: Sleeper] = [:]
    private let sleepEvents = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var closed = false
    private(set) var sleepCalls = 0
    private(set) var maximumPendingSleeperCount = 0
    var port: DocumentAutosaveClock {
        .init(now: { self.now }, sleepUntil: { try await self.sleep(until: $0) })
    }

    func advance(by duration: Duration) { now = now.advanced(by: duration) }

    @discardableResult
    func resumeDue() -> Int {
        let due = sleepers.filter { $0.value.deadline <= now }
        for (id, sleeper) in due {
            sleepers[id] = nil
            sleeper.continuation.resume()
        }
        return due.count
    }

    func waitForSleepCalls(_ minimum: Int) async {
        guard sleepCalls < minimum, !closed else { return }
        for await count in sleepEvents.stream where count >= minimum { return }
    }

    func cancelAll() {
        closed = true
        let pending = sleepers.values
        sleepers.removeAll()
        for sleeper in pending { sleeper.continuation.resume(throwing: CancellationError()) }
        sleepEvents.continuation.finish()
    }

    private func sleep(until deadline: ContinuousClock.Instant) async throws {
        sleepCalls += 1
        sleepEvents.continuation.yield(sleepCalls)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard deadline > now else { return }
        let id = UUID()
        try await withTaskCancellationHandler(
            operation: { () async throws -> Void in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    if Task.isCancelled || closed {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                        maximumPendingSleeperCount = max(maximumPendingSleeperCount, sleepers.count)
                    }
                }
            },
            onCancel: {
                Task { @MainActor in self.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError()) }
            }
        )
    }
}

@MainActor
private final class AutosaveGate {
    private let arrival = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func hold() async {
        guard !released else { return }
        await withCheckedContinuation {
            continuation = $0
            arrival.continuation.yield(())
        }
    }

    func waitUntilEntered() async { for await _ in arrival.stream { return } }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
        arrival.continuation.finish()
    }
}
