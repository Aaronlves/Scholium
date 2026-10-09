import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat current-state observation", .serialized)
@MainActor
struct AgentChatCurrentStateObservationTests {
    @Test("Native state access disables the existing Chat observation and off/on revokes pending capture")
    func nativeStateAccessRevocation() async throws {
        try await withFixture { fixture in
            let preferences = fixture.controller.contextAccessPreferences
            preferences.chatStateAccess = false
            #expect(await fixture.registry.handle(fixture.request()).error?.code == .permissionDenied)
            #expect(fixture.capture.calls == 0)
            preferences.chatStateAccess = true
            fixture.capture.pauses = true
            let pending = Task { await fixture.registry.handle(fixture.request()) }
            do {
                try await wait { fixture.capture.isWaiting }
                preferences.chatStateAccess = false
                preferences.chatStateAccess = true
                fixture.capture.release()
                try expectSafeFailure(await pending.value)
                #expect(fixture.capture.calls == 1)
            } catch {
                pending.cancel()
                fixture.capture.release()
                _ = await pending.value
                throw error
            }
        }
    }
    @Test("Observation returns closed metadata and counts without drafts, content or raw diagnostics")
    func metadataOnly() async throws {
        try await withFixture { fixture in
            let controller = fixture.controller
            let secret = "PRIVATE-CONTENT-MUST-NOT-LEAVE-THIS-FIXTURE"
            controller.editDraft(secret)
            controller.update {
                $0.messages.append(.init(role: .assistant, text: secret))
                $0.queuedMessages = [.init(role: .user, text: secret)]
                $0.pendingMessageID = secret
            }
            controller.connectionError = secret
            controller.historySaveError = secret
            controller.materialCleanupError = secret
            controller.materialErrors[fixture.owner] = secret
            controller.executions[fixture.owner]?.report(.historyRefreshFailed, detail: secret)
            controller.executions[fixture.owner]?.approvals = [
                .init(id: UUID(), title: secret, detail: secret, questions: [], updatePreview: nil)
            ]
            fixture.capture.document = .init(surface: .none, hasSaveError: true)
            let response = await fixture.registry.handle(fixture.request())
            let result = try #require(response.result?.objectValue)
            #expect(response.error == nil && fixture.capture.calls == 1 && fixture.capture.otherToolCalls == 0)
            #expect(fixture.capture.receivedTriptych == controller.triptychID && fixture.capture.receivedConversation == fixture.owner)
            #expect(fixture.capture.receivedScope == fixture.capture.scope && fixture.capture.admittedAtEntry && fixture.capture.admittedAtReturn)
            #expect(
                Set(result.keys) == [
                    "schema_version", "status", "triptych_id", "window_id", "conversation_id", "observed_at", "document_surface", "active_note", "chat",
                ])
            #expect(result["schema_version"]?.intValue == ScholiumMCPContract.currentToolSchemaVersion)
            #expect(result["triptych_id"]?.stringValue == controller.triptychID.uuidString.lowercased())
            #expect(result["window_id"]?.stringValue == fixture.capture.scope.windowID.uuidString.lowercased())
            #expect(result["conversation_id"]?.stringValue == fixture.owner.uuidString.lowercased())
            #expect(result["document_surface"] == .string("none") && result["active_note"] == .null)
            #expect(result["observed_at"]?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) } != nil)
            let chat = try #require(result["chat"]?.objectValue)
            #expect(
                Set(chat.keys) == ["thread_id", "turn_id", "state", "pending_delivery", "queued_message_count", "approval_count", "question_count", "errors"])
            #expect(chat["thread_id"] == .string("fixture-thread") && chat["turn_id"] == .string("fixture-turn"))
            #expect(chat["state"] == .string("working") && chat["pending_delivery"] == .bool(true))
            #expect(chat["queued_message_count"] == .integer(1) && chat["approval_count"] == .integer(1) && chat["question_count"] == .integer(0))
            #expect(
                Set(chat["errors"]?.arrayValue?.compactMap(\.stringValue) ?? []) == [
                    "connection", "history_save", "material_cleanup", "history_refresh", "execution", "document_save",
                ])
            let encoded = try JSONEncoder().encode(try #require(response.result))
            #expect(encoded.count <= ScholiumMCPContract.maximumChatObservationUTF8ByteCount)
            #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
            #expect(controller.selected?.draft == secret && controller.selected?.queuedMessages.first?.text == secret)
            #expect(controller.executions[fixture.owner]?.admissionID != nil)
        }
    }

    @Test(
        "Foreign or unbound observations are rejected before capture",
        arguments: ["triptych", "window", "conversation", "extra", "missing", "malformed", "token", "turn", "hidden", "registration", "unselected"])
    func rejectsForeignBinding(scenario: String) async throws {
        try await withFixture { fixture in
            var arguments = fixture.arguments
            var token: UUID? = fixture.token
            var context = fixture.context
            switch scenario {
            case "triptych": arguments["triptych_id"] = .string(UUID().uuidString)
            case "window": arguments["window_id"] = .string(UUID().uuidString)
            case "conversation": arguments["conversation_id"] = .string(UUID().uuidString)
            case "extra": arguments["include_source"] = .bool(true)
            case "missing": arguments.removeValue(forKey: "window_id")
            case "malformed": arguments["conversation_id"] = .string("not-a-uuid")
            case "token": token = UUID()
            case "turn": context = .init(threadID: context.threadID, turnID: "foreign-turn")
            case "hidden": fixture.capture.visible = false
            case "registration": fixture.capture.scope = .init(windowID: fixture.capture.scope.windowID, registrationID: UUID())
            default: fixture.controller.newConversation()
            }
            let response = await fixture.registry.handle(
                .init(
                    tool: .observeCurrentState, arguments: arguments, conversationToken: token, runtimeContext: context))
            try expectSafeFailure(response)
            #expect(fixture.capture.calls == 0 && fixture.capture.otherToolCalls == 0)
            #expect(fixture.controller.conversation(fixture.owner)?.messages.isEmpty == true)
        }
    }

    @Test(
        "A suspended observation cannot survive cancellation or a departed admission",
        arguments: ["cancel", "stop", "switch-away-back", "connection", "admission", "turn", "hidden", "registration"])
    func rejectsLateCapture(scenario: String) async throws {
        try await withFixture { fixture in
            fixture.capture.pauses = true
            let pending = Task { await fixture.registry.handle(fixture.request()) }
            do {
                try await wait { fixture.capture.isWaiting }
                switch scenario {
                case "cancel": pending.cancel()
                case "stop": fixture.controller.stop()
                case "switch-away-back":
                    fixture.controller.newConversation()
                    fixture.controller.select(fixture.owner)
                case "connection": fixture.controller.connectionID = UUID()
                case "admission": fixture.controller.executions[fixture.owner]?.admissionID = UUID()
                case "turn": fixture.controller.executions[fixture.owner]?.turnID = "replacement-turn"
                case "hidden": fixture.capture.visible = false
                default: fixture.capture.scope = .init(windowID: fixture.capture.scope.windowID, registrationID: UUID())
                }
                fixture.capture.release()
                let response = await pending.value
                try expectSafeFailure(response)
                #expect(!fixture.capture.admittedAtReturn && fixture.capture.otherToolCalls == 0)
                #expect(fixture.controller.conversation(fixture.owner)?.messages.last?.activity?.status == .interrupted)
            } catch {
                pending.cancel()
                fixture.capture.release()
                _ = await pending.value
                throw error
            }
        }
    }

    @Test("Unknown and structured callback errors cannot disclose diagnostics or recovery payloads", arguments: [false, true])
    func sanitizesCaptureFailure(structured: Bool) async throws {
        try await withFixture { fixture in
            let secret = String(repeating: "PRIVATE-SOURCE-AND-PATH", count: 300)
            fixture.capture.failure =
                structured
                ? ScholiumMCPFailure(code: .conflict, message: secret, recovery: secret)
                : NSError(domain: secret, code: 1, userInfo: [NSLocalizedDescriptionKey: secret])
            let response = await fixture.registry.handle(fixture.request())
            try expectSafeFailure(response)
            #expect(response.error?.code == .internalError)
            #expect(!String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains("PRIVATE-SOURCE"))
            #expect(fixture.controller.selected?.messages.last?.activity?.detail == "")
        }
    }

    @Test(
        "Oversized metadata fails as a whole and oversized runtime identity never reaches capture",
        arguments: ["document", "thread", "turn"])
    func boundsObservation(scenario: String) async throws {
        try await withFixture { fixture in
            if scenario == "document" {
                fixture.capture.document = .init(
                    surface: .triptychNote,
                    activeNote: .init(
                        vaultID: UUID(), noteID: UUID(), role: .topicKnowledge,
                        relativePath: String(repeating: "a", count: 20_000), mode: .source,
                        revision: .savedSource(.init(content: "Fixture source never returned")),
                        dirty: false, saving: false, conflict: false, selection: .none))
            } else if scenario == "thread" {
                fixture.controller.update { $0.threadID = String(repeating: "t", count: 513) }
            } else {
                fixture.controller.executions[fixture.owner]?.turnID = String(repeating: "t", count: 513)
            }
            let context = try #require(fixture.controller.runtimeContext(for: fixture.token))
            let response = await fixture.registry.handle(
                .init(
                    tool: .observeCurrentState, arguments: fixture.arguments, conversationToken: fixture.token, runtimeContext: context))
            try expectSafeFailure(response)
            #expect(response.error?.code == .internalError)
            #expect(fixture.capture.calls == (scenario == "document" ? 1 : 0))
        }
    }

    @Test("A newer valid observation after selection departure succeeds without reviving its old capture")
    func freshObservationAfterDeparture() async throws {
        try await withFixture { fixture in
            fixture.capture.pauses = true
            let pending = Task { await fixture.registry.handle(fixture.request()) }
            do {
                try await wait { fixture.capture.isWaiting }
                fixture.controller.newConversation()
                fixture.controller.select(fixture.owner)
                fixture.capture.release()
                try expectSafeFailure(await pending.value)
                fixture.capture.pauses = false
                fixture.capture.document = .init(surface: .externalDocument)
                let fresh = await fixture.registry.handle(fixture.request())
                #expect(fresh.error == nil)
                #expect(fresh.result?.objectValue?["document_surface"] == .string("external_document"))
                #expect(fresh.result?.objectValue?["active_note"] == .null)
                #expect(fixture.capture.calls == 2)
            } catch {
                pending.cancel()
                fixture.capture.release()
                _ = await pending.value
                throw error
            }
        }
    }

    private func expectSafeFailure(_ response: ScholiumMCPBridgeResponse) throws {
        #expect(response.result == nil)
        let failure = try #require(response.error)
        #expect(failure.recoveryDetails == nil)
        #expect(failure == .chatObservation(failure.code))
        #expect(try JSONEncoder().encode(failure).count <= 1_024)
    }

    private func withFixture(_ operation: @MainActor (Fixture) async throws -> Void) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/observation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let preferenceSuite = "Scholium.ChatObservation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: preferenceSuite))
        defer { defaults.removePersistentDomain(forName: preferenceSuite) }
        let preferences = AgentContextAccessPreferences(defaults: defaults)
        let capture = ObservationCapture()
        let registry = AgentChatRegistry(
            root: root, contextAccessPreferences: preferences, workspaceDirectory: { _ in root },
            displayWindow: { _, _ in capture.visible ? capture.scope : nil },
            observeCurrentState: { triptych, scope, conversation, admitted in
                try await capture.observe(triptych: triptych, scope: scope, conversation: conversation, admitted: admitted)
            },
            previewUpdate: { _ in throw ScholiumMCPFailure.chatObservation(.internalError) },
            handler: { request, _ in
                capture.otherToolCalls += 1
                return try! .init(requestID: request.requestID, error: .chatObservation(.internalError))
            })
        let controller = registry.controller(for: UUID())
        try #require(await controller.waitUntilLoaded())
        let owner = try #require(controller.selectedID)
        let token = UUID()
        controller.connectionState = .ready
        controller.connectionID = UUID()
        controller.update { $0.threadID = "fixture-thread" }
        controller.executions[owner]?.state = .working
        controller.executions[owner]?.turnID = "fixture-turn"
        controller.executions[owner]?.routeToken = token
        controller.executions[owner]?.admissionID = UUID()
        controller.executions[owner]?.displayScope = capture.scope
        let fixture = Fixture(registry: registry, controller: controller, capture: capture, owner: owner, token: token)
        do {
            try await operation(fixture)
            await registry.shutdown()
        } catch {
            capture.release()
            await registry.shutdown()
            throw error
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Synthetic observation did not reach capture")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @MainActor
    private struct Fixture {
        let registry: AgentChatRegistry
        let controller: AgentChatController
        let capture: ObservationCapture
        let owner: UUID
        let token: UUID
        var context: ScholiumMCPRuntimeContext { .init(threadID: "fixture-thread", turnID: "fixture-turn") }
        var arguments: [String: MCPJSONValue] {
            [
                "triptych_id": .string(controller.triptychID.uuidString), "window_id": .string(capture.scope.windowID.uuidString),
                "conversation_id": .string(owner.uuidString),
            ]
        }
        func request() -> ScholiumMCPBridgeRequest {
            .init(tool: .observeCurrentState, arguments: arguments, conversationToken: token, runtimeContext: context)
        }
    }
}

@MainActor
private final class ObservationCapture {
    var scope = AgentChatDisplayScope(windowID: UUID(), registrationID: UUID())
    var visible = true
    var document = AgentChatDocumentObservation(surface: .none)
    var failure: Error?
    var pauses = false
    var isWaiting = false
    var calls = 0
    var otherToolCalls = 0
    var receivedTriptych: UUID?
    var receivedScope: AgentChatDisplayScope?
    var receivedConversation: UUID?
    var admittedAtEntry = false
    var admittedAtReturn = false
    private var continuation: CheckedContinuation<Void, Never>?

    func observe(triptych: UUID, scope: AgentChatDisplayScope, conversation: UUID, admitted: @escaping @MainActor () -> Bool) async throws
        -> AgentChatDocumentObservation
    {
        calls += 1
        receivedTriptych = triptych
        receivedScope = scope
        receivedConversation = conversation
        admittedAtEntry = admitted()
        if pauses {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isWaiting = true
            }
        }
        admittedAtReturn = admitted()
        if let failure { throw failure }
        return document
    }

    func release() {
        continuation?.resume()
        continuation = nil
        isWaiting = false
    }
}
