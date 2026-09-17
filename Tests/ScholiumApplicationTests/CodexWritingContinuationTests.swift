import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Isolated writing continuation")
@MainActor
struct CodexWritingContinuationTests {
    private let model = AgentChatModel(
        id: "picker", model: "inexpensive", name: "Small model", efforts: ["low", "medium"],
        defaultEffort: "medium", isDefault: false, inputModalities: ["text"])
    private let cwd = URL(fileURLWithPath: "/disposable/continuation")
    private var context: CodexWritingContinuationRequest {
        .init(before: "Responsibility depends on", after: "", background: ["Topic: quoted background."], model: "inexpensive")
    }

    @Test("Selected model, low effort and tool restrictions are independent of Chat defaults")
    func parameters() throws {
        let params = try CodexWritingContinuation.threadParameters(
            context, effort: "low", cwd: cwd,
            configuration: .object([
                "config": .object([
                    "mcp_servers": .object([
                        "custom.server": .object(["env": .object(["SECRET": .string("never transmit")])])
                    ])
                ])
            ]))
        #expect(params["model"] == .string("inexpensive"))
        #expect(params["allowProviderModelFallback"] == .bool(false))
        #expect(params["ephemeral"] == .bool(true))
        #expect(params["environments"] == .array([]))
        #expect(params["dynamicTools"] == .array([]))
        #expect(params["sandbox"] == .string("read-only"))
        #expect(params["config"]?.objectValue?["mcp_servers.\"custom.server\".enabled"] == .bool(false))
        #expect(params["config"]?.objectValue?["features.shell_tool"] == .bool(false))
        #expect(params["config"]?.objectValue?["project_doc_max_bytes"] == .integer(0))
        #expect(!String(describing: params).contains("never transmit"))
        #expect(CodexWritingContinuation.lowestEffort(model) == "low")
        #expect(CodexWritingContinuation.supports(model))
        let costlyOnly = AgentChatModel(
            id: "costly", model: "expensive", name: "Heavy model", efforts: ["medium", "high"],
            defaultEffort: "medium", isDefault: false, inputModalities: ["text"])
        #expect(CodexWritingContinuation.lowestEffort(costlyOnly) == nil)
        #expect(!CodexWritingContinuation.supports(costlyOnly))
        #expect(try CodexWritingContinuation.prompt(context).contains("retrievedBackground"))
    }

    @Test("A checked final suffix is returned without history reads and unloads its ephemeral thread")
    func success() async throws {
        let fixture = ContinuationFixture()
        let execution = fixture.execution()
        let result = Task { try await execution.run(context, model: model, cwd: cwd) }
        await fixture.waitForTurn()
        await fixture.finish(execution, text: #"{"continuation":" the available options."}"#)
        #expect(try await result.value == " the available options.")
        await fixture.waitForCleanup()
        #expect(fixture.calls.map(\.0) == ["config/read", "thread/start", "mcpServerStatus/list", "turn/start", "thread/unsubscribe"])
        let turn = try #require(fixture.calls.first { $0.0 == "turn/start" }?.1)
        #expect(turn["model"] == .string("inexpensive"))
        #expect(turn["effort"] == .string("low"))
        #expect(turn["serviceTierForTurn"] == .string("default"))
        #expect(turn["outputSchema"] != nil)
        #expect(execution.isActive == false)
    }

    @Test("Exposed MCP tools or substituted models fail before any inference is requested")
    func unsafePreflight() async {
        for substituted in [false, true] {
            let fixture = ContinuationFixture()
            fixture.exposesTool = !substituted
            fixture.substitutesModel = substituted
            let execution = fixture.execution()
            await #expect(throws: CodexWritingContinuationError.self) {
                try await execution.run(context, model: model, cwd: cwd)
            }
            await fixture.waitForCleanup()
            #expect(!fixture.calls.contains { $0.0 == "turn/start" })
            #expect(fixture.calls.contains { $0.0 == "thread/unsubscribe" })
        }
    }

    @Test("An unexpected tool request is rejected and interrupts only the exact continuation turn")
    func toolRequest() async {
        let fixture = ContinuationFixture()
        let execution = fixture.execution()
        let result = Task { try await execution.run(context, model: model, cwd: cwd) }
        await fixture.waitForTurn()
        let handled = await execution.receive([
            "id": .integer(7), "method": .string("item/tool/call"),
            "params": .object(["threadId": .string("ephemeral"), "turnId": .string("turn")]),
        ])
        #expect(handled)
        await #expect(throws: CodexWritingContinuationError.self) { try await result.value }
        await fixture.waitForCleanup()
        #expect(fixture.rejections == [.integer(7)])
        #expect(fixture.calls.first { $0.0 == "turn/interrupt" }?.1 == ["threadId": .string("ephemeral"), "turnId": .string("turn")])
        #expect(fixture.calls.last?.0 == "thread/unsubscribe")
    }

    @Test("Cancellation rejects late text and cannot act on another thread")
    func cancellation() async {
        let fixture = ContinuationFixture()
        let execution = fixture.execution()
        let result = Task { try await execution.run(context, model: model, cwd: cwd) }
        await fixture.waitForTurn()
        let handled = await execution.receive([
            "method": .string("item/tool/call"), "id": .integer(9),
            "params": .object(["threadId": .string("other")]),
        ])
        #expect(!handled && fixture.rejections.isEmpty)
        result.cancel()
        await #expect(throws: CancellationError.self) { try await result.value }
        await fixture.finish(execution, text: #"{"continuation":" late text."}"#)
        await fixture.waitForCleanup()
        #expect(fixture.calls.filter { $0.0 == "turn/interrupt" }.count == 1)
    }

    @Test("Cancellation during thread creation still unloads its eventual identified thread")
    func pendingCreationCancellation() async {
        let fixture = ContinuationFixture()
        fixture.holdsThreadStart = true
        let execution = fixture.execution()
        let result = Task { try await execution.run(context, model: model, cwd: cwd) }
        await fixture.waitForThreadStart()
        result.cancel()
        await #expect(throws: CancellationError.self) { try await result.value }
        fixture.releaseThreadStart()
        await fixture.waitForCleanup()
        #expect(!fixture.calls.contains { $0.0 == "turn/start" })
        #expect(fixture.calls.last?.0 == "thread/unsubscribe")
    }

    @Test("Timeout terminates the exact turn without accepting a later reply")
    func timeout() async {
        let fixture = ContinuationFixture()
        let execution = fixture.execution(timeout: .zero)
        // The zero deadline deterministically exercises timeout without a real wait.
        await #expect(throws: CodexWritingContinuationError.self) {
            try await execution.run(context, model: model, cwd: cwd)
        }
    }

    @Test("Output bounds preserve spacing, reject multi-sentence/prose/fenced results and bound context")
    func outputAndContext() throws {
        #expect(try CodexWritingContinuation.suffix(#"{"continuation":" the available options."}"#) == " the available options.")
        for value in [
            "plain prose", #"{"continuation":""}"#, #"{"continuation":" First. Second."}"#,
            #"{"continuation":"Text\nparagraph"}"#, #"{"continuation":"```text```"}"#,
            #"{"continuation":"[^^invented]"}"#, #"{"continuation":"Text","explanation":"extra"}"#,
        ] {
            #expect(throws: CodexWritingContinuationError.self) { try CodexWritingContinuation.suffix(value) }
        }
        #expect(throws: CodexWritingContinuationError.self) {
            try CodexWritingContinuation.prompt(.init(before: String(repeating: "字", count: 4_001), after: "", model: "inexpensive"))
        }
    }

    @Test("Literal suffix bounds match editor UTF-16 units rather than Swift grapheme counts")
    func literalSuffixBoundary() throws {
        func encoded(_ suffix: String) throws -> String {
            String(decoding: try JSONEncoder().encode(MCPJSONValue.object(["continuation": .string(suffix)])), as: UTF8.self)
        }
        for suffix in [String(repeating: "a", count: 512), String(repeating: "🙂", count: 256)] {
            #expect(try CodexWritingContinuation.suffix(encoded(suffix)) == suffix)
        }
        for suffix in [
            String(repeating: "a", count: 513), String(repeating: "🙂", count: 257),
            String(repeating: "e\u{301}", count: 257),
        ] {
            #expect(throws: CodexWritingContinuationError.self) { try CodexWritingContinuation.suffix(encoded(suffix)) }
        }
        for scalar in "\\`*_{}[]<>|\u{1}\t\u{7f}\u{85}\u{2028}\u{2029}\u{202a}\u{202b}\u{202c}\u{202d}\u{202e}\u{2066}\u{2067}\u{2068}\u{2069}".unicodeScalars {
            #expect(throws: CodexWritingContinuationError.self) {
                try CodexWritingContinuation.suffix(encoded(" literal \(scalar)."))
            }
        }
        let joinedEmoji = " A family 👨‍👩‍👧‍👦 remains together."
        #expect(try CodexWritingContinuation.suffix(encoded(joinedEmoji)) == joinedEmoji)
        #expect(CodexWritingContinuation.outputSchema.objectValue?["properties"]?.objectValue?["continuation"]?.objectValue?["maxLength"] == .integer(512))
    }

    @Test("Context budgets match editor packing for Chinese and supplementary scalars")
    func contextBoundary() throws {
        let chinese = CodexWritingContinuationRequest(
            before: String(repeating: "字", count: 2_400), after: String(repeating: "文", count: 800),
            background: Array(repeating: String(repeating: "题", count: 800), count: 3), model: "inexpensive")
        #expect(!((try CodexWritingContinuation.prompt(chinese)).isEmpty))
        let emoji = CodexWritingContinuationRequest(
            before: String(repeating: "🙂", count: 1_200), after: String(repeating: "🙂", count: 400),
            background: [String(repeating: "🙂", count: 1_200)], model: "inexpensive")
        #expect(!((try CodexWritingContinuation.prompt(emoji)).isEmpty))
        for oversized in [
            CodexWritingContinuationRequest(before: chinese.before + "字", after: "", model: "inexpensive"),
            CodexWritingContinuationRequest(before: "词", after: chinese.after + "文", model: "inexpensive"),
            CodexWritingContinuationRequest(before: "词", after: "", background: chinese.background + ["多"], model: "inexpensive"),
            CodexWritingContinuationRequest(before: "词", after: "", background: [String(repeating: "题", count: 2_401)], model: "inexpensive"),
        ] {
            #expect(throws: CodexWritingContinuationError.self) { try CodexWritingContinuation.prompt(oversized) }
        }
    }
}

@MainActor
private final class ContinuationFixture {
    var calls: [(String, [String: MCPJSONValue])] = []
    var rejections: [MCPJSONValue] = []
    var exposesTool = false
    var substitutesModel = false
    var holdsThreadStart = false
    private var turnReady = false
    private var cleaned = false
    private var creationReady = false
    private var turnWaiter: CheckedContinuation<Void, Never>?
    private var cleanupWaiter: CheckedContinuation<Void, Never>?
    private var creationWaiter: CheckedContinuation<Void, Never>?
    private var heldCreation: CheckedContinuation<Void, Never>?

    func execution(timeout: Duration = .seconds(12)) -> CodexWritingContinuation {
        .init(
            request: { [self] method, params in
                calls.append((method, params))
                switch method {
                case "config/read": return .object(["config": .object([:])])
                case "thread/start":
                    creationReady = true
                    if holdsThreadStart {
                        await withCheckedContinuation { continuation in
                            heldCreation = continuation
                            creationWaiter?.resume()
                            creationWaiter = nil
                        }
                    }
                    return .object([
                        "thread": .object(["id": .string("ephemeral"), "ephemeral": .bool(true)]),
                        "model": .string(substitutesModel ? "expensive" : "inexpensive"),
                        "approvalPolicy": .string("never"), "sandbox": .object(["type": .string("readOnly")]),
                        "reasoningEffort": .string("low"), "instructionSources": .array([]),
                    ])
                case "mcpServerStatus/list":
                    return .object(["data": .array(exposesTool ? [.object(["tools": .object(["write": .object([:])])])] : []), "nextCursor": .null])
                case "turn/start":
                    turnReady = true
                    turnWaiter?.resume()
                    turnWaiter = nil
                    return .object(["turn": .object(["id": .string("turn"), "status": .string("inProgress")])])
                case "thread/unsubscribe":
                    return .object([:])
                case "turn/interrupt": return .object([:])
                default: throw CodexConnectionError.invalidMessage
                }
            }, reject: { [self] id in rejections.append(id) }, timeout: timeout,
            finished: { [self] in
                cleaned = true
                cleanupWaiter?.resume()
                cleanupWaiter = nil
            })
    }

    func waitForTurn() async {
        if turnReady { return }
        await withCheckedContinuation { turnWaiter = $0 }
    }
    func waitForCleanup() async {
        if cleaned { return }
        await withCheckedContinuation { cleanupWaiter = $0 }
    }
    func waitForThreadStart() async {
        if creationReady { return }
        await withCheckedContinuation { creationWaiter = $0 }
    }
    func releaseThreadStart() {
        heldCreation?.resume()
        heldCreation = nil
    }
    func finish(_ execution: CodexWritingContinuation, text: String) async {
        _ = await execution.receive([
            "method": .string("item/completed"),
            "params": .object([
                "threadId": .string("ephemeral"), "turnId": .string("turn"),
                "item": .object(["type": .string("agentMessage"), "phase": .string("final_answer"), "text": .string(text)]),
            ]),
        ])
        _ = await execution.receive([
            "method": .string("turn/completed"),
            "params": .object([
                "threadId": .string("ephemeral"), "turn": .object(["id": .string("turn"), "status": .string("completed")]),
            ]),
        ])
    }
}
