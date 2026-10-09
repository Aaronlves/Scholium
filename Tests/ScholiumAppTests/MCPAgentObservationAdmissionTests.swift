import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("MCP Agent observation admission")
@MainActor
struct MCPAgentObservationAdmissionTests {
    @Test("Passive Triptych discovery uses registered IDs without capture, source flush or runtime lookup")
    func passiveScopeDiscovery() async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            let response = await fixture.router().handle(.init(tool: .observeWorkspace, arguments: [:]))
            let result = try #require(response.result?.objectValue)
            let page = try #require(result["triptychs"]?.objectValue)
            #expect(page["total"] == .integer(1))
            #expect(page["items"]?.arrayValue?.first?.objectValue?["triptych_id"] == .string(fixture.triptychID.uuidString.lowercased()))
            #expect(result["triptych_id"] == nil && result["window_id"] == nil)
            #expect(fixture.capture.calls == 0 && fixture.capture.summaryCalls == 0)
            #expect(fixture.capture.flushes == 0 && fixture.capture.runtimeLookups == 0)
            #expect(fixture.store.workspaceSnapshots.isEmpty && fixture.store.workspaceActivations.isEmpty)
        }
    }
    @Test("External context is denied by default before any window callback")
    func defaultExternalDenial() async throws {
        try await withFixture { fixture in
            let router = fixture.router()
            for tool in [ScholiumMCPToolName.observeWorkspace, .observeResearchContext, .readContext] {
                let response = await router.handle(fixture.request(tool))
                try expectFailure(response, code: .permissionDenied)
                #expect(response.error == .contextAccessDenied())
            }
            #expect(fixture.capture.calls == 0 && fixture.capture.summaryCalls == 0)
            #expect(fixture.capture.flushes == 0 && fixture.capture.runtimeLookups == 0)
        }
    }

    @Test("Metadata and exact working-text grants work independently through the real router")
    func independentReadGrants() async throws {
        try await withFixture { fixture in
            let router = fixture.router()
            fixture.preferences.externalStateAccess = true
            fixture.capture.canDisplay = false
            let metadata = await router.handle(fixture.request(.observeWorkspace))
            let state = try #require(metadata.result?.objectValue)
            #expect(metadata.error == nil)
            #expect(Set(state.keys) == ["window", "listing_fingerprint", "tabs", "schema_version", "status", "triptych_id", "window_id", "observed_at"])
            #expect(state["triptych_id"] == .string(fixture.triptychID.uuidString.lowercased()))
            #expect(state["window_id"] == .string(fixture.windowID.uuidString.lowercased()))
            #expect(state["observed_at"]?.stringValue.flatMap { ISO8601DateFormatter().date(from: $0) } != nil)
            #expect(!String(decoding: try JSONEncoder().encode(state), as: UTF8.self).contains(fixture.capture.source))
            try expectFailure(await router.handle(fixture.request(.readContext)), code: .permissionDenied)
            fixture.preferences.externalStateAccess = false
            fixture.preferences.externalWorkingTextAccess = true
            try expectFailure(await router.handle(fixture.request(.observeResearchContext)), code: .permissionDenied)
            let response = await router.handle(fixture.request(.readContext))
            let read = try #require(response.result?.objectValue)
            #expect(response.error == nil && read["text"] == .string(fixture.capture.source))
            #expect(read["origin"] == .string("editor_snapshot"))
            #expect(read["fingerprint"] == AgentWindowObservation.fingerprintValue(fixture.capture.fingerprint))
            #expect(read["text_fingerprint"] == read["fingerprint"])
            #expect(read["coverage"]?.objectValue?["end_utf8"]?.intValue == fixture.capture.source.utf8.count)
            #expect(fixture.capture.calls == 2 && fixture.capture.admittedAtEntry && fixture.capture.admittedAtReturn)
            #expect(fixture.capture.flushes == 0 && fixture.capture.runtimeLookups == 0)
            #expect(fixture.store.workspaceSnapshots.isEmpty && fixture.store.workspaceActivations.isEmpty)
        }
    }

    @Test(
        "Foreign Triptych, window and unbound Chat identities never reach capture",
        arguments: ["triptych", "window", "chat", "missing_window", "unavailable_window"])
    func rejectsForeignContext(scenario: String) async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            var arguments = fixture.arguments
            var token: UUID? = nil
            switch scenario {
            case "triptych": arguments["triptych_id"] = .string(UUID().uuidString)
            case "window": arguments["window_id"] = .string(UUID().uuidString)
            case "chat": token = UUID()
            case "missing_window": arguments["window_id"] = nil
            default: fixture.capture.canObserve = false
            }
            let response = await fixture.router().handle(
                .init(
                    tool: .observeResearchContext, arguments: arguments, conversationToken: token,
                    runtimeContext: token == nil ? nil : .init(threadID: "foreign-thread", turnID: "foreign-turn")))
            try expectFailure(response, code: .workspaceNotReady)
            #expect(fixture.capture.calls == 0)
        }
    }

    @Test("Chat observation requires its registered visible window and exact admitted turn")
    func chatScopeAdmission() async throws {
        try await withFixture { fixture in
            let controller = fixture.store.chatRegistry.controller(for: fixture.triptychID)
            try #require(await controller.waitUntilLoaded())
            let owner = try #require(controller.selectedID)
            let token = UUID()
            fixture.capture.visibleConversationID = owner
            let scope = try #require(fixture.store.chatDisplayWindow(triptychID: fixture.triptychID, conversationID: owner))
            controller.connectionState = .ready
            controller.connectionID = UUID()
            controller.update { $0.threadID = "fixture-thread" }
            controller.executions[owner]?.state = .working
            controller.executions[owner]?.turnID = "fixture-turn"
            controller.executions[owner]?.routeToken = token
            controller.executions[owner]?.admissionID = UUID()
            controller.executions[owner]?.displayScope = scope
            let context = ScholiumMCPRuntimeContext(threadID: "fixture-thread", turnID: "fixture-turn")
            let router = fixture.router()
            let valid = await router.handle(.init(tool: .observeWorkspace, arguments: fixture.arguments, conversationToken: token, runtimeContext: context))
            #expect(valid.error == nil && fixture.capture.calls == 1)
            let discovered = await fixture.store.chatRegistry.handle(
                .init(tool: .observeWorkspace, arguments: [:], conversationToken: token, runtimeContext: context))
            #expect(discovered.error == nil)
            #expect(discovered.result?.objectValue?["window_id"] == .string(fixture.windowID.uuidString.lowercased()))
            #expect(fixture.capture.calls == 2 && fixture.capture.flushes == 0 && fixture.capture.runtimeLookups == 0)
            fixture.capture.failure = ScholiumMCPFailure(code: .staleRevision, message: "PRIVATE", recovery: "PRIVATE")
            let stale = await fixture.store.chatRegistry.handle(
                .init(tool: .observeWorkspace, arguments: [:], conversationToken: token, runtimeContext: context))
            #expect(stale.error?.code == .staleRevision)
            #expect(controller.selected?.messages.last?.activity?.detail.contains("edit") == false)
            fixture.capture.failure = nil
            let admittedCalls = fixture.capture.calls
            for scenario in ["turn", "window", "triptych", "missing_window", "token", "hidden"] {
                var arguments = fixture.arguments
                var requestToken = token
                var requestContext = context
                switch scenario {
                case "turn": requestContext = .init(threadID: "fixture-thread", turnID: "foreign-turn")
                case "window": arguments["window_id"] = .string(UUID().uuidString)
                case "triptych": arguments["triptych_id"] = .string(UUID().uuidString)
                case "missing_window": arguments["window_id"] = nil
                case "token": requestToken = UUID()
                default: fixture.capture.canDisplay = false
                }
                try expectFailure(
                    await router.handle(
                        .init(tool: .observeWorkspace, arguments: arguments, conversationToken: requestToken, runtimeContext: requestContext)),
                    code: .workspaceNotReady)
                #expect(fixture.capture.calls == admittedCalls)
            }
        }
    }

    @Test("Revocation followed by re-enabling during capture rejects the old reply", arguments: [ScholiumMCPToolName.observeWorkspace, .readContext])
    func permissionRevisionRejectsLateReply(tool: ScholiumMCPToolName) async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            fixture.preferences.externalWorkingTextAccess = true
            fixture.capture.pauses = true
            let router = fixture.router()
            let pending = Task { await router.handle(fixture.request(tool)) }
            do {
                try await fixture.capture.waitUntilEntered()
                if tool == .readContext {
                    fixture.preferences.externalWorkingTextAccess = false
                    fixture.preferences.externalWorkingTextAccess = true
                } else {
                    fixture.preferences.externalStateAccess = false
                    fixture.preferences.externalStateAccess = true
                }
                fixture.capture.release()
                try expectFailure(await pending.value, code: .permissionDenied)
                #expect(!fixture.capture.admittedAtReturn && fixture.capture.calls == 1)
                fixture.capture.pauses = false
                #expect(await router.handle(fixture.request(tool)).error == nil)
            } catch {
                pending.cancel()
                fixture.capture.release()
                _ = await pending.value
                throw error
            }
        }
    }

    @Test("Replacing the registered window during capture cannot deliver the old reply")
    func registrationReplacementRejectsLateReply() async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            fixture.capture.pauses = true
            let router = fixture.router()
            let pending = Task { await router.handle(fixture.request(.observeWorkspace)) }
            do {
                try await fixture.capture.waitUntilEntered()
                fixture.registerWindow(id: fixture.windowID)
                fixture.capture.release()
                try expectFailure(await pending.value, code: .workspaceNotReady)
                #expect(!fixture.capture.admittedAtReturn)
            } catch {
                pending.cancel()
                fixture.capture.release()
                _ = await pending.value
                throw error
            }
        }
    }

    @Test("Window listing is fingerprint-bound and never implicitly selects a capture target")
    func windowListingPagination() async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            let otherWindow = UUID()
            fixture.registerWindow(id: otherWindow)
            fixture.registerWindow(id: UUID(), triptych: UUID())
            let router = fixture.router()
            var arguments: [String: MCPJSONValue] = ["triptych_id": .string(fixture.triptychID.uuidString), "limit": .integer(1)]
            let first = await router.handle(.init(tool: .observeWorkspace, arguments: arguments))
            let result = try #require(first.result?.objectValue)
            let windows = try #require(result["windows"]?.objectValue)
            let fingerprint = try #require(windows["listing_fingerprint"])
            let firstItem = try #require(windows["items"]?.arrayValue?.first)
            #expect(windows["total"] == .integer(2) && windows["next_offset"] == .integer(1))
            #expect(result["window_id"] == nil && fixture.capture.calls == 0)
            arguments["offset"] = .integer(1)
            try expectFailure(await router.handle(.init(tool: .observeWorkspace, arguments: arguments)), code: .invalidRequest)
            arguments["expected_listing_fingerprint"] = fingerprint
            let next = await router.handle(.init(tool: .observeWorkspace, arguments: arguments))
            let secondPage = try #require(next.result?.objectValue?["windows"]?.objectValue)
            let secondItem = try #require(secondPage["items"]?.arrayValue?.first)
            #expect(firstItem != secondItem && secondPage["has_more"] == .bool(false))
            #expect(secondPage["listing_fingerprint"] == fingerprint)
            fixture.registerWindow(id: otherWindow)
            try expectFailure(await router.handle(.init(tool: .observeWorkspace, arguments: arguments)), code: .staleRevision)
            arguments["offset"] = nil
            arguments["expected_listing_fingerprint"] = nil
            try expectFailure(await router.handle(.init(tool: .observeResearchContext, arguments: arguments)), code: .workspaceNotReady)
            #expect(fixture.capture.calls == 0 && fixture.capture.flushes == 0 && fixture.capture.runtimeLookups == 0)
        }
    }

    @Test(
        "Unknown arguments and callback payloads fail without diagnostic disclosure",
        arguments: ["arguments", "payload", "capacity", "typed_error", "unknown_error"])
    func safeClosedFailures(scenario: String) async throws {
        try await withFixture { fixture in
            fixture.preferences.externalStateAccess = true
            let secret = "PRIVATE-DIAGNOSTIC-AND-ABSOLUTE-PATH"
            var arguments = fixture.arguments
            switch scenario {
            case "arguments": arguments["include_private_content"] = .string(secret)
            case "payload":
                var payload = fixture.capture.workspacePayload.objectValue!
                payload["unknown"] = .string(secret)
                fixture.capture.payloadOverride = .object(payload)
            case "capacity":
                var payload = fixture.capture.workspacePayload.objectValue!
                payload["window"] = .string(
                    String(repeating: secret, count: ScholiumMCPContract.maximumContextObservationUTF8ByteCount / secret.utf8.count + 1))
                fixture.capture.payloadOverride = .object(payload)
            case "typed_error": fixture.capture.failure = ScholiumMCPFailure(code: .conflict, message: secret, recovery: secret)
            default: fixture.capture.failure = NSError(domain: secret, code: 1, userInfo: [NSLocalizedDescriptionKey: secret])
            }
            let response = await fixture.router().handle(.init(tool: .observeWorkspace, arguments: arguments))
            let code: ScholiumMCPFailureCode = scenario == "typed_error" ? .conflict : scenario == "unknown_error" ? .workspaceNotReady : .invalidRequest
            try expectFailure(response, code: code)
            #expect(!String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains(secret))
            #expect(fixture.capture.calls == (scenario == "arguments" ? 0 : 1))
        }
    }

    private func expectFailure(_ response: ScholiumMCPBridgeResponse, code: ScholiumMCPFailureCode) throws {
        #expect(response.result == nil)
        let failure = try #require(response.error)
        #expect(failure.code == code && failure.recoveryDetails == nil)
        #expect(try JSONEncoder().encode(failure).count <= 1_024)
    }

    private func withFixture(_ operation: @MainActor (ObservationAdmissionFixture) async throws -> Void) async throws {
        let fixture = try ObservationAdmissionFixture()
        do {
            try await operation(fixture)
            await fixture.cleanup()
        } catch {
            fixture.capture.release()
            await fixture.cleanup()
            throw error
        }
    }
}

@MainActor
private struct ObservationAdmissionFixture {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: WorkspaceStore
    let preferences: AgentContextAccessPreferences
    let triptychID = UUID()
    let windowID = UUID()
    let capture = ObservationAdmissionCapture()

    init() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/mcp-observation-admission-tests/\(UUID())")
        let suiteName = "Scholium.MCPObservationAdmission.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        self.root = root
        self.suiteName = suiteName
        self.defaults = defaults
        preferences = AgentContextAccessPreferences(defaults: defaults)
        do { store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport")) } catch {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        registerWindow(id: windowID)
    }

    var arguments: [String: MCPJSONValue] {
        ["triptych_id": .string(triptychID.uuidString), "window_id": .string(windowID.uuidString)]
    }

    func request(_ tool: ScholiumMCPToolName) -> ScholiumMCPBridgeRequest {
        var arguments = self.arguments
        if tool == .readContext {
            arguments["kind"] = .string("active_note")
            arguments["note_id"] = .string(capture.noteID.uuidString)
            arguments["expected_fingerprint"] = AgentWindowObservation.fingerprintValue(capture.fingerprint)
        }
        return .init(tool: tool, arguments: arguments)
    }

    func registerWindow(id: UUID, triptych: UUID? = nil) {
        let triptych = triptych ?? triptychID
        var registration = AgentNoteDisplayWindow(
            state: { [capture] in
                .init(
                    triptychID: triptych, canDisplay: capture.canDisplay,
                    visibleConversationID: capture.visibleConversationID, canObserve: capture.canObserve)
            },
            display: { _, _ in throw ObservationAdmissionError.unexpectedDisplay })
        registration.observeAgentState = { [capture] request, admitted in try await capture.observe(request, admitted: admitted) }
        registration.stateSummary = { [capture] in
            capture.summaryCalls += 1
            return .object(["kind": .string("main"), "tab_count": .integer(1), "selected_tab_id": .null])
        }
        store.registerNoteDisplayWindow(id: id, window: registration)
    }

    func router() -> MCPAppBridgeRequestRouter {
        MCPAppBridgeRequestRouter(
            runtime: store.applicationRuntime,
            flushEditors: { [capture] _ in capture.flushes += 1 },
            openTriptychs: { [capture] in
                capture.runtimeLookups += 1
                return []
            },
            observeAgentState: { [store, preferences] in try await store.observeAgentState($0, preferences: preferences) })
    }

    func cleanup() async {
        capture.release()
        await store.shutdownApplicationRuntime()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ObservationAdmissionError: Error {
    case unexpectedDisplay
    case timedOut
}

@MainActor
private final class ObservationAdmissionCapture {
    let noteID = UUID()
    let vaultID = UUID()
    let source = "\u{feff}# Philosophical fixture\r\n\r\nExact working text: 哲学.\r\n"
    var fingerprint: DocumentFingerprint { .init(content: source) }
    var calls = 0
    var summaryCalls = 0
    var flushes = 0
    var runtimeLookups = 0
    var canDisplay = true
    var canObserve = true
    var visibleConversationID: UUID?
    var admittedAtEntry = false
    var admittedAtReturn = false
    var pauses = false
    var payloadOverride: MCPJSONValue?
    var failure: Error?
    private let entered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var continuation: CheckedContinuation<Void, Never>?

    var workspacePayload: MCPJSONValue {
        .object([
            "window": .object(["kind": .string("main"), "tab_count": .integer(0)]),
            "listing_fingerprint": AgentWindowObservation.fingerprintValue(.init(content: "fixture-tab-listing")),
            "tabs": .object([
                "offset": .integer(0), "limit": .integer(20), "total": .integer(0), "has_more": .bool(false), "next_offset": .null, "items": .array([]),
            ]),
        ])
    }

    var textPayload: MCPJSONValue {
        .object([
            "kind": .string("active_note"), "origin": .string("editor_snapshot"),
            "note": .object([
                "note_id": .string(noteID.uuidString.lowercased()), "vault_id": .string(vaultID.uuidString.lowercased()),
                "role": .string("works"), "relative_path": .string("Question.md"),
            ]),
            "fingerprint": AgentWindowObservation.fingerprintValue(fingerprint),
            "source_locator": .object(["state": .string("whole_note"), "start_utf8": .integer(0), "end_utf8": .integer(source.utf8.count)]),
            "text_fingerprint": AgentWindowObservation.fingerprintValue(fingerprint), "kept_passage_id": .null,
            "text": .string(source),
            "coverage": .object([
                "basis": .string("context"), "total_utf8": .integer(source.utf8.count), "start_utf8": .integer(0),
                "end_utf8": .integer(source.utf8.count), "has_more": .bool(false), "next_start_utf8": .null,
            ]),
        ])
    }

    func observe(_ request: ScholiumMCPBridgeRequest, admitted: @escaping @MainActor () -> Bool) async throws -> MCPJSONValue {
        calls += 1
        admittedAtEntry = admitted()
        if pauses {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.continuation.yield()
            }
        }
        admittedAtReturn = admitted()
        if let failure { throw failure }
        return payloadOverride ?? (request.tool == .readContext ? textPayload : workspacePayload)
    }

    func waitUntilEntered() async throws {
        let stream = entered.stream
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                guard await iterator.next() != nil else { throw CancellationError() }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw ObservationAdmissionError.timedOut
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
