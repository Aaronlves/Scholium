import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp
@testable import ScholiumApplication

@Suite("Chat Note mutation source admission")
@MainActor
struct AgentChatMutationAdmissionTests {
    @Test(
        "A token-scoped mutation requires both its live callback and runtime context",
        arguments: [false, true])
    func tokenMutationRejectsMissingAdmission(missingRuntimeContext: Bool) async throws {
        let fixture = try await MCPAppBridgeRequestRouterTests.Fixture.make(name: "Missing Chat admission fixture")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
            let file = fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
            let before = try Data(contentsOf: file)
            let beforeChanges = try await handle.agentCollaboration.agentChanges()
            var flushes = 0
            var admissionChecks = 0
            let router = MCPAppBridgeRequestRouter(
                runtime: fixture.runtime, flushEditors: { _ in flushes += 1 }, openTriptychs: { [fixture.assignment] })
            let checker: AgentMutationAdmission = { admissionChecks += 1 }
            let admission: AgentMutationAdmission? = missingRuntimeContext ? checker : nil
            let response = await router.handle(
                .init(
                    tool: .updateNote,
                    arguments: [
                        "triptych_id": .string(fixture.assignment.id.uuidString),
                        "note_id": .string(fixture.analysisNoteID.uuidString),
                        "expected_fingerprint": .object([
                            "sha256": .string(fixture.analysisFingerprint.sha256),
                            "byte_count": .integer(fixture.analysisFingerprint.byteCount),
                        ]),
                        "mode": .string("source"), "content": .string("# Missing admission cannot authorize this source.\n"),
                    ],
                    conversationToken: UUID(),
                    runtimeContext: missingRuntimeContext ? nil : .init(threadID: "fixture-thread", turnID: "fixture-turn")
                ), mutationAdmission: admission)
            #expect(response.error?.code == .invalidRequest && response.result == nil)
            #expect(flushes == 0 && admissionChecks == 0)
            #expect(try Data(contentsOf: file) == before)
            #expect(try await handle.agentCollaboration.agentChanges() == beforeChanges)
            await fixture.runtime.shutdown()
        } catch {
            await fixture.runtime.shutdown()
            throw error
        }
    }

    @Test(
        "Revocation during editor reconciliation prevents a new Chat Note mutation",
        arguments: FlushScenario.allCases)
    func revocationDuringEditorFlushRejectsMutation(scenario: FlushScenario) async throws {
        let pause = MutationAdmissionPause()
        defer { pause.release() }
        try await withController(flushEditors: { _ in await pause.wait() }) { context in
            let original = try Data(contentsOf: context.analysisURL)
            let beforeChanges = try await context.handle.agentCollaboration.agentChanges()
            let request = context.request(scenario == .stopCreate ? .createNote : .updateNote)
            let pending = Task { await context.controller.handle(request) }
            do {
                try await wait(for: pause.objectWillChange) { pause.isPaused }
                #expect(!(await context.handle.sourceOperationGate.sourceMutationIsActive))
                var replacementContext: ScholiumMCPRuntimeContext?
                switch scenario {
                case .stopUpdate, .stopCreate:
                    context.controller.stop()
                case .disconnectUpdate:
                    await context.controller.disconnect()
                case .completedUpdate:
                    // The existing runtime fixture emits a matching normal
                    // completion; no controller execution state is fabricated.
                    try Data().write(to: context.controller.runtimeHome.appendingPathComponent("complete-on-interrupt"))
                    let runtime = try #require(context.controller.runtime)
                    _ = try await runtime.request(
                        "turn/interrupt",
                        params: [
                            "threadId": .string(context.runtimeContext.threadID),
                            "turnId": .string(context.runtimeContext.turnID),
                        ])
                    try await wait(for: context.controller.objectWillChange) { context.controller.state == .ready }
                case .replacementTurnUpdate:
                    context.controller.stop()
                    try await wait(for: context.controller.objectWillChange) {
                        context.controller.state == .ready && !context.controller.isBusy
                    }
                    context.controller.editDraft("hold the replacement turn")
                    context.controller.send()
                    try await wait(for: context.controller.objectWillChange) {
                        context.controller.state == .working && context.controller.selected?.pendingMessageID == nil
                    }
                    let replacementToken = try #require(context.controller.token)
                    replacementContext = try #require(context.controller.runtimeContext(for: replacementToken))
                    #expect(replacementContext != context.runtimeContext)
                }
                if replacementContext == nil { #expect(context.controller.token == nil) }
                pause.release()
                let response = await pending.value
                #expect(response.error?.code == .invalidRequest)
                #expect(response.result == nil)
                #expect(try Data(contentsOf: context.analysisURL) == original)
                #expect(!FileManager.default.fileExists(atPath: context.createdURL.path))
                #expect(try await context.handle.agentCollaboration.agentChanges() == beforeChanges)
                if let replacementContext, let token = context.controller.token {
                    #expect(context.controller.runtimeContext(for: token) == replacementContext)
                }
            } catch {
                pending.cancel()
                pause.release()
                _ = await pending.value
                throw error
            }
        }
    }

    @Test("Stopping an Agent proposal during editor flush still saves the researcher's native draft")
    func revokedAgentDoesNotBlockNativeEditorFlush() async throws {
        let pause = MutationAdmissionPause()
        defer { pause.release() }
        let researcherSource = "\u{FEFF}# Researcher's draft\r\n\r\nNative editor changes remain owned by the researcher.\r\n"
        var saveResearcherDraft: (@MainActor () async throws -> Void)?
        try await withController(flushEditors: { _ in
            await pause.wait()
            try await saveResearcherDraft?()
        }) { context in
            let vaultID = try #require(context.fixture.assignment.vault(for: .paperAnalysis)?.id)
            saveResearcherDraft = {
                _ = try await context.handle.documents.save(
                    .init(vaultID: vaultID, relativePath: "Alpha.md"),
                    changeSet: .source(researcherSource), expectedRevision: context.fixture.analysisFingerprint)
            }
            let pending = Task { await context.controller.handle(context.request(.updateNote)) }
            do {
                try await wait(for: pause.objectWillChange) { pause.isPaused }
                context.controller.stop()
                #expect(context.controller.token == nil)
                pause.release()
                let response = await pending.value
                #expect(response.error?.code == .invalidRequest || response.error?.code == .staleRevision)
                #expect(response.result == nil)
                #expect(try Data(contentsOf: context.analysisURL) == Data(researcherSource.utf8))
                #expect(try await context.handle.agentCollaboration.agentChanges().isEmpty)
            } catch {
                pending.cancel()
                pause.release()
                _ = await pending.value
                throw error
            }
        }
    }

    @Test(
        "Stop while an update or Undo waits for source observation leaves its Note and receipt unchanged",
        arguments: [ScholiumMCPToolName.updateNote, .undoChange])
    func stopWhileSourceObservationQueuedRejectsMutation(tool: ScholiumMCPToolName) async throws {
        try await withController { context in
            let request: ScholiumMCPBridgeRequest
            if tool == .undoChange {
                let update = try await context.handle.agentCollaboration.updateNote(
                    noteID: context.fixture.analysisNoteID, expectedFingerprint: context.fixture.analysisFingerprint,
                    update: .source("# Exact ending before a revoked Undo\n"))
                request = .init(
                    tool: .undoChange,
                    arguments: [
                        "triptych_id": .string(context.fixture.assignment.id.uuidString),
                        "note_id": .string(context.fixture.analysisNoteID.uuidString),
                        "change_id": .string(update.change.id.uuidString),
                        "expected_fingerprint": .object([
                            "sha256": .string(update.afterFingerprint.sha256),
                            "byte_count": .integer(update.afterFingerprint.byteCount),
                        ]),
                    ], conversationToken: context.token, runtimeContext: context.runtimeContext)
            } else {
                request = context.request(.updateNote)
            }
            let before = try Data(contentsOf: context.analysisURL)
            let beforeChanges = try await context.handle.agentCollaboration.agentChanges()
            let holder = try await context.handle.acquireWorkspaceSourceOperation(.sourceMutation)
            var holdsLease = true
            let pending = Task { await context.controller.handle(request) }
            do {
                // Here the router's source-observation refresh queues first;
                // an observation lease must not consume mutation admission.
                try #require(await waitUntilSourceWaiter(context.handle), "The router never queued source observation.")
                context.controller.stop()
                #expect(context.controller.token == nil)
                await context.handle.releaseWorkspaceSourceOperation(holder)
                holdsLease = false
                let response = await pending.value
                #expect(response.error?.code == .invalidRequest)
                #expect(response.result == nil)
                #expect(try Data(contentsOf: context.analysisURL) == before)
                #expect(try await context.handle.agentCollaboration.agentChanges() == beforeChanges)
                #expect(await context.handle.sourceOperationGate.waitingCount == 0)
            } catch {
                pending.cancel()
                if holdsLease { await context.handle.releaseWorkspaceSourceOperation(holder) }
                _ = await pending.value
                throw error
            }
        }
    }

    @Test("Stop while a Chat creation waits for the source lease prevents bytes and mutation evidence")
    func stopWhileSourceLeaseQueuedRejectsCreation() async throws {
        let pause = MutationAdmissionPause()
        defer { pause.release() }
        try await withController { context in
            await context.handle.setManagedCreationPreLeaseBarrierForTesting { await pause.wait() }
            let original = try Data(contentsOf: context.analysisURL)
            let pending = Task { await context.controller.handle(context.request(.createNote)) }
            var holder: WorkspaceSourceOperationLease?
            do {
                try await wait(for: pause.objectWillChange) { pause.isPaused }
                holder = try await context.handle.acquireWorkspaceSourceOperation(.sourceMutation)
                pause.release()
                try #require(await waitUntilSourceWaiter(context.handle), "The creation never reached the source-lease queue.")
                #expect(!FileManager.default.fileExists(atPath: context.createdURL.path))
                context.controller.stop()
                #expect(context.controller.token == nil)
                if let lease = holder {
                    await context.handle.releaseWorkspaceSourceOperation(lease)
                    holder = nil
                }
                let response = await pending.value
                #expect(response.error?.code == .invalidRequest)
                #expect(response.result == nil)
                #expect(try Data(contentsOf: context.analysisURL) == original)
                #expect(!FileManager.default.fileExists(atPath: context.createdURL.path))
                #expect(try await context.handle.agentCollaboration.agentChanges().isEmpty)
                #expect(await context.handle.sourceOperationGate.waitingCount == 0)
                await context.handle.setManagedCreationPreLeaseBarrierForTesting(nil)
            } catch {
                pending.cancel()
                pause.release()
                if let holder { await context.handle.releaseWorkspaceSourceOperation(holder) }
                _ = await pending.value
                await context.handle.setManagedCreationPreLeaseBarrierForTesting(nil)
                throw error
            }
        }
    }

    @Test("Stop after source admission lets a committed Chat creation finish exact identity and evidence")
    func stopAfterSourceCommitPreservesCreation() async throws {
        let pause = MutationAdmissionPause()
        defer { pause.release() }
        try await withController { context in
            await context.handle.setManagedCreationPostSourceBarrierForTesting { await pause.wait() }
            let original = try Data(contentsOf: context.analysisURL)
            let pending = Task { await context.controller.handle(context.request(.createNote)) }
            do {
                try await wait(for: pause.objectWillChange) { pause.isPaused }
                #expect(await context.handle.sourceOperationGate.sourceMutationIsActive)
                #expect(try Data(contentsOf: context.createdURL) == Data(Context.createdSource.utf8))
                let prepared = try await context.handle.agentCollaboration.agentChanges()
                #expect(prepared.count == 1 && prepared.first?.state == .prepared)
                context.controller.stop()
                #expect(context.controller.token == nil)
                pause.release()
                let response = await pending.value
                // Delivery can be refused after revocation; the admitted source
                // transaction must still finish rather than losing its receipt.
                #expect(response.error == nil || response.error?.code == .operationUncertain)
                let changes = try await context.handle.agentCollaboration.agentChanges()
                let change = try #require(changes.first)
                #expect(changes.count == 1 && change.state == .confirmed)
                #expect(change.id == prepared.first?.id && change.operation == .create)
                let source = try await context.handle.agentCollaboration.currentNoteSource(noteID: change.noteID)
                #expect(source.source == Data(Context.createdSource.utf8))
                #expect(source.fingerprint == change.afterFingerprint)
                #expect(try Data(contentsOf: context.analysisURL) == original)
                #expect(try Data(contentsOf: context.createdURL) == Data(Context.createdSource.utf8))
                await context.handle.setManagedCreationPostSourceBarrierForTesting(nil)
            } catch {
                pending.cancel()
                pause.release()
                _ = await pending.value
                await context.handle.setManagedCreationPostSourceBarrierForTesting(nil)
                throw error
            }
        }
    }

    private struct Context {
        static let createdSource = "\u{FEFF}# Created through Chat\r\n\r\nExact admitted source.\r\n"
        let fixture: MCPAppBridgeRequestRouterTests.Fixture
        let handle: WorkspaceHandle
        let controller: AgentChatController
        let token: UUID
        let runtimeContext: ScholiumMCPRuntimeContext

        var analysisURL: URL {
            fixture.topicsURL.deletingLastPathComponent().appendingPathComponent("Analyses/Alpha.md")
        }
        var createdURL: URL { fixture.topicsURL.appendingPathComponent("AdmissionCreated.md") }

        func request(_ tool: ScholiumMCPToolName) -> ScholiumMCPBridgeRequest {
            var arguments: [String: MCPJSONValue] = ["triptych_id": .string(fixture.assignment.id.uuidString)]
            if tool == .createNote {
                arguments.merge([
                    "role": .string("topics"), "relative_path": .string("AdmissionCreated.md"),
                    "content": .string(Self.createdSource),
                ]) { _, new in new }
            } else {
                arguments.merge([
                    "note_id": .string(fixture.analysisNoteID.uuidString),
                    "expected_fingerprint": .object([
                        "sha256": .string(fixture.analysisFingerprint.sha256),
                        "byte_count": .integer(fixture.analysisFingerprint.byteCount),
                    ]),
                    "mode": .string("source"), "content": .string("# A stopped update must not be written.\n"),
                ]) { _, new in new }
            }
            return .init(tool: tool, arguments: arguments, conversationToken: token, runtimeContext: runtimeContext)
        }
    }

    enum FlushScenario: String, CaseIterable, Sendable {
        case stopUpdate, stopCreate, disconnectUpdate, completedUpdate, replacementTurnUpdate
    }

    private func withController(
        flushEditors: @escaping MCPAppBridgeRequestRouter.EditorFlusher = { _ in },
        body: (Context) async throws -> Void
    ) async throws {
        let fixture = try await MCPAppBridgeRequestRouterTests.Fixture.make(name: "Chat admission fixture")
        let suite = "scholium.chat-mutation-admission.\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: fixture.root)
        }
        var controller: AgentChatController?
        do {
            let defaults = try #require(UserDefaults(suiteName: suite))
            let handle = try await fixture.runtime.openWorkspace(id: fixture.assignment.id)
            let router = MCPAppBridgeRequestRouter(
                runtime: fixture.runtime, flushEditors: flushEditors, openTriptychs: { [fixture.assignment] })
            let chatRoot = fixture.root.appendingPathComponent("Chat")
            let active = AgentChatController(
                triptychID: fixture.assignment.id, root: chatRoot,
                workspaceDirectory: { try agentChatFixtureWorkspace(root: chatRoot, triptychID: fixture.assignment.id) },
                methodDefaults: defaults, previewUpdate: { try await router.previewUpdate($0) },
                toolHandler: { request, admission in await router.handle(request, mutationAdmission: admission) })
            controller = active
            try #require(await active.waitUntilLoaded(), "Chat history did not finish loading.")
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let executable = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
            active.connect(executable: executable, home: active.runtimeHome, helper: executable)
            try #require(await active.waitUntilReady(), "The fixture runtime did not become ready.")
            active.setPermission(.fullAccess)
            active.editDraft("hold while checking source admission")
            active.send()
            try await wait(for: active.objectWillChange) {
                active.state == .working && active.selected?.pendingMessageID == nil
            }
            let token = try #require(active.token)
            let runtimeContext = try #require(active.runtimeContext(for: token))
            try await body(.init(fixture: fixture, handle: handle, controller: active, token: token, runtimeContext: runtimeContext))
            await active.disconnect()
            await fixture.runtime.shutdown()
        } catch {
            await controller?.disconnect()
            await fixture.runtime.shutdown()
            throw error
        }
    }

    private func waitUntilSourceWaiter(_ handle: WorkspaceHandle) async -> Bool {
        for _ in 0..<1_000 {
            if await handle.sourceOperationGate.waitingCount == 1 { return true }
            await Task.yield()
        }
        return await handle.sourceOperationGate.waitingCount == 1
    }

    private func wait(
        for changes: ObservableObjectPublisher,
        until condition: () -> Bool
    ) async throws {
        let events = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observation = changes.sink { events.continuation.yield(()) }
        let deadline = Task {
            do {
                try await Task.sleep(for: .seconds(10))
                events.continuation.finish()
            } catch {}
        }
        defer {
            observation.cancel()
            deadline.cancel()
            events.continuation.finish()
        }
        if condition() { return }
        for await _ in events.stream {
            try Task.checkCancellation()
            if condition() { return }
        }
        try #require(condition(), "The controlled admission fixture did not reach its expected boundary.")
    }
}

@MainActor
private final class MutationAdmissionPause: ObservableObject {
    @Published private(set) var isPaused = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isPaused = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
