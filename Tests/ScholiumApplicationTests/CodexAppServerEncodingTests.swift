import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Codex transport JSON encoding")
struct CodexAppServerEncodingTests {
    @Test("Requests, notifications and responses preserve the closed JSON graph on the actual wire")
    func closedGraphOnWire() async throws {
        try await withEncodingRuntime { runtime, fixture in
            let payload = encodingPayload()
            let expected = try JSONDecoder().decode(MCPJSONValue.self, from: JSONEncoder().encode(MCPJSONValue.object(payload)))
            #expect(try await runtime.request("echo", params: payload) == expected)
            try await runtime.notify("record", params: payload)
            try await runtime.respond(id: .string("answer"), result: .object(payload)) { true }
            _ = try await runtime.request("barrier")
            let frames = try fixture.frames()
            #expect(frames.count == 4)
            for (index, field) in [(0, "params"), (1, "params"), (2, "result")] {
                let frame = frames[index]
                let object = try JSONDecoder().decode(MCPJSONValue.self, from: frame)
                #expect(object.objectValue?[field] == expected)
                let envelope = try JSONDecoder().decode(EncodingWireEnvelope.self, from: frame)
                let values = try #require(field == "params" ? envelope.params : envelope.result)
                #expect(values.minimum == Int.min && values.maximum == Int.max)
                #expect(values.numericOne == 1 && values.truth && !values.falsehood)
                #expect(values.signedZero == 0 && values.signedZero.sign == .minus)
                #expect(values.positiveZero == 0 && values.positiveZero.sign == .plus)
                #expect(values.largest.bitPattern == Double.greatestFiniteMagnitude.bitPattern)
                #expect(values.smallest.bitPattern == Double.leastNonzeroMagnitude.bitPattern)
                #expect(values.normalMinimum.bitPattern == Double.leastNormalMagnitude.bitPattern)
                #expect(values.precise.bitPattern == Double.pi.bitPattern)
                #expect(values.text.utf8.elementsEqual(encodingExactText.utf8))
                #expect(values.controls.utf8.elementsEqual(encodingControlText.utf8))
            }
        }
    }

    @Test(
        "Nonfinite nested numbers throw before any request, notification or response is written",
        arguments: [
            Double.nan, Double.infinity, -Double.infinity,
        ])
    func nonfiniteIsKnownUnsent(value: Double) async throws {
        try await withEncodingRuntime { runtime, fixture in
            let payload: [String: MCPJSONValue] = ["nested": .array([.null, .object(["invalid": .double(value)])])]
            for channel in EncodingWireChannel.allCases {
                do {
                    try await channel.send(runtime, payload: payload)
                    Issue.record("A nonfinite JSON number must fail synchronously before queue admission")
                } catch EncodingError.invalidValue(let rejected, _) {
                    let number = try #require(rejected as? Double)
                    #expect(!number.isFinite)
                    #expect(number.isNaN == value.isNaN)
                    if !value.isNaN { #expect(number.sign == value.sign) }
                }
            }
            // A successful ordered RPC proves the rejected encodings neither
            // disconnected nor left a pending request waiting for a reply.
            #expect(try await runtime.request("echo", params: ["alive": .bool(true)]) == .object(["alive": .bool(true)]))
            let frames = try fixture.frames()
            #expect(frames.count == 1)
            let only = try JSONDecoder().decode(MCPJSONValue.self, from: try #require(frames.first))
            #expect(only.objectValue?["params"] == .object(["alive": .bool(true)]))
        }
    }

    @Test("Ordinary nested arrays and objects retain every element in order")
    func validNestedGraph() async throws {
        try await withEncodingRuntime { runtime, fixture in
            var nested: MCPJSONValue = .array([.integer(0), .string(encodingExactText), .null, .bool(true)])
            for level in 0..<32 {
                nested = .array([.integer(level), .object(["next": nested]), .string("tail-\(level)")])
            }
            let payload = ["nested": nested]
            #expect(try await runtime.request("echo", params: payload) == .object(payload))
            let frame = try #require(try fixture.frames().first)
            let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: frame)
            #expect(decoded.objectValue?["params"] == .object(payload))
        }
    }

    @Test("A system-invalid deep graph fails as a Swift error and keeps the transport usable")
    func invalidDepthIsKnownUnsent() async throws {
        try await withEncodingRuntime { runtime, fixture in
            var nested = MCPJSONValue.null
            for _ in 0..<520 { nested = .array([nested]) }
            let payload = ["nested": nested]
            do {
                _ = try await runtime.request("echo", params: payload)
                Issue.record("Invalid nesting must not reach the Objective-C JSON writer")
            } catch is EncodingError {}
            _ = try await runtime.request("barrier")
            #expect(try fixture.frames().count == 1)
        }
    }

    @Test("The existing complete-frame byte budget includes exactly one newline", arguments: EncodingWireChannel.allCases)
    func completeFrameBoundary(channel: EncodingWireChannel) async throws {
        let payload: [String: MCPJSONValue] = ["padding": .string(String(repeating: "x", count: 256))]
        let encodedBytes = try JSONEncoder().encode(channel.envelope(payload: payload)).count
        for accepted in [true, false] {
            let limits = CodexTransportLimits(
                incomingCount: 8, incomingBytes: 4_096, outgoingCount: 8,
                outgoingBytes: encodedBytes + (accepted ? 1 : 0), pendingOperations: 8)
            try await withEncodingRuntime(limits: limits) { runtime, fixture in
                if accepted {
                    try await channel.send(runtime, payload: payload)
                    _ = try await runtime.request("barrier")
                    let frame = try #require(try fixture.frames().first)
                    #expect(frame.count == encodedBytes)
                    let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: frame)
                    #expect(decoded == channel.envelope(payload: payload))
                } else {
                    do {
                        try await channel.send(runtime, payload: payload)
                        Issue.record("A frame with no remaining newline byte must be refused before writing")
                    } catch CodexConnectionError.capacityExceeded {}
                    let terminal = try #require(await runtime.events.first { $0["method"]?.stringValue == "scholium/disconnected" })
                    #expect(terminal["params"]?.objectValue?["reason"]?.stringValue == "capacityExceeded")
                    await runtime.close()
                    #expect(try fixture.frames().isEmpty)
                }
            }
        }
    }

    @Test("A four MiB research text retains its exact original UTF-8 bytes")
    func largeExactText() async throws {
        try await withEncodingRuntime { runtime, fixture in
            let text = String(repeating: "x", count: 4 * 1_024 * 1_024) + encodingExactText + encodingControlText
            let reply = try await runtime.request("echo", params: ["text": .string(text)])
            let returned = try #require(reply.objectValue?["text"]?.stringValue)
            #expect(returned.utf8.elementsEqual(text.utf8))
            let frame = try #require(try fixture.frames().first)
            let observed = try JSONDecoder().decode(EncodingTextEnvelope.self, from: frame)
            #expect(observed.params.text.utf8.elementsEqual(text.utf8))
        }
    }
}

private let encodingExactText = "\u{feff}e\u{301} / é 中文 📝 \\\"quote\\\"\r\n\u{2028}\u{2029}"
private let encodingControlText = String(String.UnicodeScalarView((0..<32).map { UnicodeScalar($0)! }))

private func encodingPayload() -> [String: MCPJSONValue] {
    [
        "minimum": .integer(Int.min), "maximum": .integer(Int.max),
        "numericOne": .integer(1), "truth": .bool(true), "falsehood": .bool(false),
        "signedZero": .double(-0.0), "positiveZero": .double(0.0),
        "largest": .double(.greatestFiniteMagnitude), "smallest": .double(.leastNonzeroMagnitude),
        "normalMinimum": .double(.leastNormalMagnitude), "precise": .double(.pi),
        "text": .string(encodingExactText), "controls": .string(encodingControlText),
        "nested": .array([.null, .bool(false), .integer(0), .double(1.5), .object(["e\u{301}/\r\n": .string(encodingExactText)])]),
    ]
}

private struct EncodingWireValues: Decodable {
    let minimum: Int
    let maximum: Int
    let numericOne: Int
    let truth: Bool
    let falsehood: Bool
    let signedZero: Double
    let positiveZero: Double
    let largest: Double
    let smallest: Double
    let normalMinimum: Double
    let precise: Double
    let text: String
    let controls: String
}
private struct EncodingWireEnvelope: Decodable {
    let params: EncodingWireValues?
    let result: EncodingWireValues?
}
private struct EncodingTextEnvelope: Decodable {
    struct Parameters: Decodable { let text: String }
    let params: Parameters
}

enum EncodingWireChannel: String, CaseIterable, Sendable {
    case request, notification, response

    func envelope(payload: [String: MCPJSONValue]) -> MCPJSONValue {
        switch self {
        case .request: .object(["id": .integer(1), "method": .string("echo"), "params": .object(payload)])
        case .notification: .object(["method": .string("record"), "params": .object(payload)])
        case .response: .object(["id": .string("answer"), "result": .object(payload)])
        }
    }

    func send(_ runtime: CodexAppServer, payload: [String: MCPJSONValue]) async throws {
        switch self {
        case .request: _ = try await runtime.request("echo", params: payload)
        case .notification: try await runtime.notify("record", params: payload)
        case .response: try await runtime.respond(id: .string("answer"), result: .object(payload)) { true }
        }
    }
}

private enum EncodingFixtureError: Error { case deadline }

private func withEncodingRuntime(
    limits: CodexTransportLimits = .standard,
    _ operation: @escaping @Sendable (CodexAppServer, EncodingRuntimeFixture) async throws -> Void
) async throws {
    let fixture = try EncodingRuntimeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runtime = CodexAppServer(limits: limits)
    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
                try await operation(runtime, fixture)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(20))
                await runtime.close()
                throw EncodingFixtureError.deadline
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        await runtime.close()
    } catch {
        await runtime.close()
        throw error
    }
}

private struct EncodingRuntimeFixture: Sendable {
    let root: URL
    let executable: URL

    init() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = repository.appendingPathComponent(".build/codex-encoding-tests/\(UUID())")
        executable = root.appendingPathComponent("synthetic-runtime")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            try Self.script.write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func frames() throws -> [Data] {
        let path = root.appendingPathComponent("frames.jsonl")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try Data(contentsOf: path).split(separator: 10).map { Data($0) }
    }

    private static let script = #"""
        #!/usr/bin/python3
        import hashlib, json, os, pathlib, sys
        path = pathlib.Path(os.environ["CODEX_HOME"]) / "frames.jsonl"

        def emit(value):
            remaining = (json.dumps(value, ensure_ascii=False, allow_nan=False) + "\n").encode("utf-8")
            while remaining:
                remaining = remaining[os.write(1, remaining):]

        for line in sys.stdin.buffer:
            with path.open("ab") as capture:
                capture.write(line)
            message = json.loads(line)
            method = message.get("method")
            identifier = message.get("id")
            if method == "echo":
                emit({"id": identifier, "result": message.get("params", {})})
            elif method == "barrier":
                emit({"id": identifier, "result": True})
            elif method == "depthRecord":
                current = message.get("params", {}).get("nested")
                trace = []
                while isinstance(current, (dict, list)):
                    if isinstance(current, dict):
                        if len(current) != 1 or "next" not in current:
                            raise ValueError("Deep wire object width or key changed")
                        trace.append("object")
                        current = current["next"]
                    else:
                        if len(current) != 1:
                            raise ValueError("Deep wire array width changed")
                        trace.append("array")
                        current = current[0]
                if current is not None:
                    raise ValueError("Deep wire leaf is not null")
                emit({"method": "stress/depth", "params": {
                    "depth": len(trace), "trace": trace, "leafNull": True,
                    "frameBytes": len(line), "frameSHA256": hashlib.sha256(line).hexdigest()}})
        """#
}

extension CodexAppServerEncodingTests {
    @Test("Large request, notification and response frames remain distinct and ordered")
    func largeCompleteFrameOrdering() async throws {
        try await withEncodingRuntime { runtime, fixture in
            let unit = "e\u{301}中文📝\\\"\r\n"
            let text = String(repeating: unit, count: 4 * 1_024 * 1_024 / unit.utf8.count) + encodingControlText
            let payload: [String: MCPJSONValue] = ["text": .string(text)]
            for channel in EncodingWireChannel.allCases {
                try await channel.send(runtime, payload: payload)
            }
            _ = try await runtime.request("barrier")
            let frames = try fixture.frames()
            #expect(frames.count == 4)
            for (offset, field) in [(0, "params"), (1, "params"), (2, "result")] {
                let object = try JSONDecoder().decode(MCPJSONValue.self, from: frames[offset]).objectValue
                let observed = try #require(object?[field]?.objectValue?["text"]?.stringValue)
                #expect(observed.utf8.elementsEqual(text.utf8))
            }
            let first = try JSONDecoder().decode(MCPJSONValue.self, from: frames[0]).objectValue
            let second = try JSONDecoder().decode(MCPJSONValue.self, from: frames[1]).objectValue
            let third = try JSONDecoder().decode(MCPJSONValue.self, from: frames[2]).objectValue
            #expect(first?["method"] == .string("echo") && first?["id"] == .integer(1))
            #expect(second?["method"] == .string("record") && second?["id"] == nil)
            #expect(third?["id"] == .string("answer") && third?["method"] == nil)
        }
    }

    @Test("Every queued frame reserves its newline byte before any writer resumes")
    func queuedCompleteFrameByteBudget() async throws {
        let payload: [String: MCPJSONValue] = ["padding": .string(String(repeating: "x", count: 256))]
        let bodyBytes = try JSONEncoder().encode(EncodingWireChannel.notification.envelope(payload: payload)).count
        // Two JSON bodies fit, but their two required newlines do not.
        let limits = CodexTransportLimits(
            incomingCount: 8, incomingBytes: 4_096,
            outgoingCount: 8, outgoingBytes: bodyBytes * 2 + 1, pendingOperations: 8)
        try await withEncodingRuntime(limits: limits) { runtime, fixture in
            let gate = EncodingFramingPause()
            let paused = Task {
                try await runtime.respond(id: .string("paused"), result: .null) { await gate.admit() }
            }
            defer { paused.cancel() }
            #expect(await gate.entered())
            let results = await withTaskGroup(of: String.self) { group in
                for _ in 0..<2 {
                    group.addTask {
                        do {
                            try await runtime.notify("record", params: payload)
                            return "unexpectedly_written"
                        } catch CodexConnectionError.capacityExceeded { return "known_unsent" } catch CodexConnectionError.disconnected {
                            return "accepted_uncertain"
                        } catch { return "unexpected:\(error)" }
                    }
                }
                var outcomes: [String] = []
                for await value in group { outcomes.append(value) }
                return outcomes
            }
            #expect(results.sorted() == ["accepted_uncertain", "known_unsent"])
            do {
                try await paused.value
                Issue.record("The admitted response must fail when its connection exceeds capacity")
            } catch CodexConnectionError.disconnected {}
            await runtime.close()
            #expect(try fixture.frames().isEmpty)
        }
    }
}
private actor EncodingFramingPause {
    private let entry = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let decision = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    func entered() async -> Bool { await entry.stream.first { _ in true } != nil }
    func admit() async -> Bool {
        entry.continuation.yield(())
        entry.continuation.finish()
        // Connection teardown cancels the writer, terminating this iterator.
        return await decision.stream.first { _ in true } ?? false
    }
}

// Deep wire validation intentionally uses
// the child parser plus an iterative exact-shape walk and compact frame digest;
// no native deep decoder or deep echo response participates in the oracle.
extension CodexAppServerEncodingTests {
    @Test(
        "Iterative encoding follows the selected Foundation depth boundary",
        arguments: [256, 508, 509, 510, 511, 512, 520], ["array", "object", "mixed"])
    func iterativeDepthMatchesFoundationGate(depth: Int, shape: String) async throws {
        let input = try iterativeDepthFixture(depth: depth, shape: shape)
        if depth == 256 { #expect(input.isValid) }
        if depth == 520 { #expect(!input.isValid) }
        try await withEncodingRuntime { runtime, fixture in
            if input.isValid {
                var iterator = runtime.events.makeAsyncIterator()
                try await runtime.notify("depthRecord", params: ["nested": input.value])
                let event = try #require(await iterator.next())
                #expect(event["method"] == .string("stress/depth"))
                let summary = try #require(event["params"]?.objectValue)
                let trace = (0..<depth).reversed().map { level in
                    MCPJSONValue.string(iterativeDepthUsesObject(level: level, shape: shape) ? "object" : "array")
                }
                #expect(summary["depth"] == .integer(depth))
                #expect(summary["trace"] == .array(trace))
                #expect(summary["leafNull"] == .bool(true))
                _ = try await runtime.request("barrier")
                let frames = try fixture.frames()
                try #require(frames.count == 2)
                let expectedByteCount = try #require(input.expectedJSONByteCount)
                #expect(frames[0].count == expectedByteCount)
                // frames() strips the single line delimiter. Restore it for
                // an independent comparison with the child's complete frame.
                let raw = frames[0] + Data([10])
                #expect(summary["frameBytes"] == .integer(raw.count))
                #expect(summary["frameSHA256"] == .string(DocumentFingerprint(data: raw).sha256))
            } else {
                do {
                    try await runtime.notify("depthRecord", params: ["nested": input.value])
                    Issue.record("System-invalid depth unexpectedly reached the native encoder/writer")
                } catch is EncodingError {}
                _ = try await runtime.request("barrier")
                let frames = try fixture.frames()
                try #require(frames.count == 1)
                let only = try JSONSerialization.jsonObject(with: frames[0]) as? [String: Any]
                #expect(only?["method"] as? String == "barrier")
            }
        }
    }

    @Test("One-child commits preserve wide shared values, empty containers and exact multilingual wire ordering")
    func iterativeWideSharedAndUnicodeWire() async throws {
        let text = "\u{feff}e\u{301}é 中文📝 / \\\"\r\n\u{0000}\u{0008}\u{000b}\u{001f}\u{2028}\u{2029}"
        let shared: MCPJSONValue = .object([
            "text": .string(text), "empty-key": .object(["": .string("值")]),
            "one": .array([.integer(7)]), "empty-array": .array([]), "empty-object": .object([:]),
        ])
        var values: [MCPJSONValue] = [.string("first"), .object([:]), .array([]), .null, .string("header-end")]
        for index in 0..<1_024 {
            values.append(contentsOf: [.integer(index), shared, .array([.integer(-index)]), .null, .string("tail-\(index)")])
        }
        values.append(.string("last"))
        let payload: [String: MCPJSONValue] = ["wide": .array(values)]
        try await withEncodingRuntime { runtime, fixture in
            for channel in EncodingWireChannel.allCases { try await channel.send(runtime, payload: payload) }
            _ = try await runtime.request("barrier")
            let frames = try fixture.frames()
            try #require(frames.count == 4)
            for (index, field) in [(0, "params"), (1, "params"), (2, "result")] {
                // This independent decoder sees only a shallow graph. It checks
                // every sibling occurrence, including repeated shared values.
                let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: frames[index])
                #expect(decoded.objectValue?[field] == .object(payload))
                let observed = try #require(decoded.objectValue?[field]?.objectValue?["wide"]?.arrayValue)
                try #require(observed.count == 5_126)
                #expect(observed.first == .string("first") && observed.last == .string("last"))
                for offset in 0..<1_024 {
                    let value = try #require(observed[6 + offset * 5].objectValue?["text"]?.stringValue)
                    #expect(value.utf8.elementsEqual(text.utf8))
                }
            }
            let first = try JSONDecoder().decode(MCPJSONValue.self, from: frames[0]).objectValue
            let second = try JSONDecoder().decode(MCPJSONValue.self, from: frames[1]).objectValue
            let third = try JSONDecoder().decode(MCPJSONValue.self, from: frames[2]).objectValue
            #expect(first?["method"] == .string("echo") && first?["id"] == .integer(1))
            #expect(second?["method"] == .string("record") && second?["id"] == nil)
            #expect(third?["id"] == .string("answer") && third?["method"] == nil)
        }
    }
}

private struct IterativeDepthFixture: Sendable {
    let value: MCPJSONValue
    let isValid: Bool
    let expectedJSONByteCount: Int?
}

private func iterativeDepthUsesObject(level: Int, shape: String) -> Bool {
    shape == "object" || (shape == "mixed" && level.isMultiple(of: 2))
}

/// This independent system reference is synchronous: no Node/Any graph crosses
/// into the Sendable test closure. It is not part of the prototype serializer.
private func iterativeDepthFixture(depth: Int, shape: String) throws -> IterativeDepthFixture {
    var value = MCPJSONValue.null
    var reference: Any = NSNull()
    for level in 0..<depth {
        if iterativeDepthUsesObject(level: level, shape: shape) {
            value = .object(["next": value])
            let object = NSMutableDictionary(capacity: 1)
            object.setObject(reference, forKey: "next" as NSString)
            reference = object
        } else {
            value = .array([value])
            let array = NSMutableArray(capacity: 1)
            array.add(reference)
            reference = array
        }
    }
    let envelope: [String: Any] = ["method": "depthRecord", "params": ["nested": reference]]
    let isValid = JSONSerialization.isValidJSONObject(envelope)
    let count: Int?
    if isValid { count = try JSONSerialization.data(withJSONObject: envelope).count } else { count = nil }
    return .init(value: value, isValid: isValid, expectedJSONByteCount: count)
}
