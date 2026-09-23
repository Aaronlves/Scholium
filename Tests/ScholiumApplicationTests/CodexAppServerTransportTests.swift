import Darwin
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Codex subprocess transport")
struct CodexAppServerTransportTests {
    @Test("Large UTF-8 frames survive fragmented output and stderr pressure")
    func fragmentedRoundTrip() async throws {
        try await withTransportFixture { runtime, _ in
            let text = String(repeating: "合成研究段落📝\n", count: 20_000)
            let response = try await runtime.request("fragment", params: ["text": .string(text)])
            #expect(response.objectValue?["text"]?.stringValue == text)
        }
    }

    @Test("Awaited notifications retain order before a request reads their effects")
    func notificationOrdering() async throws {
        try await withTransportFixture { runtime, _ in
            for index in 0..<40 {
                try await runtime.notify("record", params: ["index": .integer(index)])
            }
            let response = try await runtime.request("recorded")
            #expect(response == .array((0..<40).map { .integer($0) }))

            try await runtime.notify("askClient")
            let event = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/question" })
            let id = try #require(event["id"])
            try await runtime.respond(id: id, result: .string("synthetic answer")) { true }
            #expect(try await runtime.request("clientResponse") == .string("synthetic answer"))

            try await runtime.notify("askClient")
            let rejected = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/question" })
            try await runtime.reject(id: try #require(rejected["id"]))
            let rejection = try await runtime.request("clientResponse")
            #expect(rejection.objectValue?["code"]?.intValue == -32601)
        }
    }

    @Test("A queued response is refused when its owner revokes admission before I/O")
    func responseAdmission() async throws {
        try await withTransportFixture { runtime, _ in
            let firstAdmission = TransportAdmissionGate()
            let secondAdmission = TransportAdmissionToken()
            let first = Task {
                try await runtime.respond(id: .string("first"), result: .string("admitted")) {
                    await firstAdmission.admit()
                }
            }
            defer { first.cancel() }
            #expect(await firstAdmission.waitForEntry())
            let second = Task {
                try await runtime.respond(id: .string("second"), result: .string("revoked")) {
                    await secondAdmission.admit()
                }
            }
            defer { second.cancel() }
            await secondAdmission.revoke()
            await firstAdmission.release(allowed: true)
            try await first.value
            do {
                try await second.value
                Issue.record("A revoked queued response must be cancelled before it reaches stdin")
            } catch is CancellationError {}
            #expect(await secondAdmission.callCount == 1)
            #expect(
                try await runtime.request("clientResponses")
                    == .array([
                        .object(["id": .string("first"), "result": .string("admitted")])
                    ]))
        }
    }

    @Test("Closing during asynchronous admission rejects the old response before restart")
    func closeDuringResponseAdmission() async throws {
        try await withTransportFixture { runtime, fixture in
            // Return true even when cancelled: the transport must still recheck its connection.
            let admission = TransportAdmissionGate(allowOnCancellation: true)
            let response = Task {
                try await runtime.respond(id: .string("old-session"), result: .string("stale")) {
                    await admission.admit()
                }
            }
            defer { response.cancel() }
            #expect(await admission.waitForEntry())
            let closing = Task { await runtime.close() }
            do {
                try await response.value
                Issue.record("Closing must reject a response whose admission is suspended")
            } catch CodexConnectionError.disconnected {}
            await admission.release(allowed: true)
            await closing.value

            try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
            #expect(try await runtime.request("clientResponses") == .array([]))
            try await runtime.respond(id: .string("new-session"), result: .string("fresh")) { true }
            #expect(
                try await runtime.request("clientResponses")
                    == .array([
                        .object(["id": .string("new-session"), "result": .string("fresh")])
                    ]))
        }
    }

    @Test("Unexpected process death fails the pending request and emits disconnection")
    func unexpectedExit() async throws {
        try await withTransportFixture { runtime, _ in
            do {
                _ = try await runtime.request("exit")
                Issue.record("A request whose process exited must fail")
            } catch CodexConnectionError.disconnected {
                // Process exit, rather than the request's 90-second timeout, completes it.
            }
            let event = await runtime.events.first { $0["method"]?.stringValue == "scholium/disconnected" }
            #expect(event != nil)
        }
    }

    @Test("Closing stdout disconnects and reaps a process that otherwise stays alive")
    func stdoutEOFReapsChild() async throws {
        try await withTransportFixture { runtime, _ in
            let pending = Task { try await runtime.request("closeStdout") }
            defer { pending.cancel() }
            let event = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/stdoutClosing" })
            let pid = pid_t(try #require(event["pid"]?.intValue))
            do {
                _ = try await pending.value
                Issue.record("Stdout EOF must fail the pending request even while the child is alive")
            } catch CodexConnectionError.disconnected {}
            await runtime.close()
            expectProcessReaped(pid)
        }
    }

    @Test("Close escalates when the child ignores SIGTERM and returns only after reaping")
    func closeEscalatesAndReaps() async throws {
        try await withTransportFixture { runtime, _ in
            let pending = Task { try await runtime.request("ignoreTermination") }
            defer { pending.cancel() }
            let event = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/ignoringTermination" })
            let pid = pid_t(try #require(event["pid"]?.intValue))
            #expect(kill(pid, 0) == 0)
            await runtime.close()
            expectProcessReaped(pid)
            do {
                _ = try await pending.value
                Issue.record("Close must fail the request held by the unresponsive child")
            } catch CodexConnectionError.disconnected {}
        }
    }

    @Test("Invalid frames disconnect, reap the child, and allow a fresh session", arguments: ["malformed", "oversized"])
    func invalidFrameRecovery(method: String) async throws {
        try await withTransportFixture { runtime, fixture in
            let pidValue = try await runtime.request("pid")
            let pid = pid_t(try #require(pidValue.intValue))
            do {
                _ = try await runtime.request(method)
                Issue.record("An invalid frame must terminate its connection")
            } catch CodexConnectionError.disconnected {}
            _ = try #require(await runtime.events.first { $0["method"]?.stringValue == "scholium/disconnected" })
            await runtime.close()
            expectProcessReaped(pid)
            try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
            #expect(try await runtime.request("echo", params: ["fresh": .bool(true)]) == .object(["fresh": .bool(true)]))
        }
    }

    @Test("Cancelling one pending request leaves the process available")
    func requestCancellation() async throws {
        try await withTransportFixture { runtime, _ in
            let pending = Task { try await runtime.request("hold") }
            defer { pending.cancel() }
            _ = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/holding" })
            pending.cancel()
            do {
                _ = try await pending.value
                Issue.record("The cancelled request must fail with cancellation")
            } catch is CancellationError {}

            // A late reply to the cancelled request must not affect the next request.
            try await runtime.notify("release")
            #expect(try await runtime.request("echo", params: ["alive": .bool(true)]) == .object(["alive": .bool(true)]))
        }
    }

    @Test("Close fails pending work and restart uses an independent process")
    func closeAndRestart() async throws {
        try await withTransportFixture { runtime, fixture in
            let originalPID = try await runtime.request("pid")
            let pending = Task { try await runtime.request("hold") }
            defer { pending.cancel() }
            _ = try #require(await runtime.events.first { $0["method"]?.stringValue == "fixture/holding" })
            await runtime.close()
            do {
                _ = try await pending.value
                Issue.record("Closing a session must fail its pending request")
            } catch CodexConnectionError.disconnected {}

            try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
            let replacementPID = try await runtime.request("pid")
            #expect(originalPID != replacementPID)
            #expect(try await runtime.request("echo", params: ["generation": .integer(2)]) == .object(["generation": .integer(2)]))
            await runtime.close()
            await runtime.close()
        }
    }

    @Test("Failed executable launch does not leave the session connected")
    func failedLaunchRecovery() async throws {
        try await withTransportFixture(start: false) { runtime, fixture in
            do {
                try await runtime.start(
                    executable: fixture.root.appendingPathComponent("missing-executable"),
                    home: fixture.root, workingDirectory: fixture.root)
                Issue.record("A missing executable must fail during start")
            } catch {
                // The concrete launch error belongs to the subprocess library.
            }
            do {
                try await runtime.notify("unavailable")
                Issue.record("A failed launch must not accept a notification")
            } catch CodexConnectionError.disconnected {}
            try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
            #expect(try await runtime.request("echo") == .object([:]))
        }
    }
}

private enum TransportFixtureFailure: Error { case deadlineExceeded }

private actor TransportAdmissionToken {
    private var allowed = true
    private(set) var callCount = 0

    func revoke() { allowed = false }

    func admit() -> Bool {
        callCount += 1
        return allowed
    }
}

private actor TransportAdmissionGate {
    private let entry = AsyncStream<Void>.makeStream()
    private let allowOnCancellation: Bool
    private var outcome: Bool?
    private var waiter: CheckedContinuation<Bool, Never>?

    init(allowOnCancellation: Bool = false) {
        self.allowOnCancellation = allowOnCancellation
    }

    func waitForEntry() async -> Bool {
        await entry.stream.first { _ in true } != nil
    }

    func admit() async -> Bool {
        entry.continuation.yield(())
        let onCancellation = allowOnCancellation
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let outcome {
                    continuation.resume(returning: outcome)
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { await self.release(allowed: onCancellation) }
        }
    }

    func release(allowed: Bool) {
        guard outcome == nil else { return }
        outcome = allowed
        waiter?.resume(returning: allowed)
        waiter = nil
    }
}

private func expectProcessReaped(_ pid: pid_t) {
    let result = kill(pid, 0)
    let error = errno
    #expect(result == -1)
    #expect(error == ESRCH)
}

private func withTransportFixture(
    start: Bool = true,
    _ operation: @escaping @Sendable (CodexAppServer, TransportFixture) async throws -> Void
) async throws {
    let fixture = try TransportFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let runtime = CodexAppServer()
    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                if start {
                    try await runtime.start(executable: fixture.executable, home: fixture.root, workingDirectory: fixture.root)
                }
                try await operation(runtime, fixture)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                Issue.record("The transport fixture exceeded its 15-second deadline")
                // Closing also releases pending work if the regression broke cancellation.
                await runtime.close()
                throw TransportFixtureFailure.deadlineExceeded
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

private struct TransportFixture: Sendable {
    let root: URL
    let executable: URL

    init() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = repository.appendingPathComponent(".build/codex-transport-tests/\(UUID())")
        executable = root.appendingPathComponent("fixture-runtime")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    private static let script = #"""
        #!/usr/bin/python3
        import json, os, signal, sys

        def emit(value, fragmented=False):
            data = (json.dumps(value, ensure_ascii=False) + "\n").encode("utf-8")
            step = 997 if fragmented else len(data)
            for offset in range(0, len(data), step):
                remaining = data[offset:offset + step]
                while remaining:
                    remaining = remaining[os.write(1, remaining):]

        recorded = []
        held = None
        client_response = None
        client_responses = []
        for line in sys.stdin.buffer:
            message = json.loads(line)
            method = message.get("method")
            identifier = message.get("id")
            params = message.get("params", {})
            if method is None:
                client_response = message.get("result", message.get("error"))
                client_responses.append(message)
                continue
            if method == "exit":
                os._exit(17)
            if method == "closeStdout":
                emit({"method": "fixture/stdoutClosing", "pid": os.getpid()})
                os.close(1)
                while True:
                    signal.pause()
            if method == "ignoreTermination":
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                emit({"method": "fixture/ignoringTermination", "pid": os.getpid()})
                while True:
                    signal.pause()
            if method in ("malformed", "oversized"):
                data = b"{not json}\n" if method == "malformed" else b"x" * (8 * 1024 * 1024 + 1)
                while data:
                    data = data[os.write(1, data):]
                while True:
                    signal.pause()
            if method == "record":
                recorded.append(params["index"])
            elif method == "askClient":
                emit({"id": "fixture-question", "method": "fixture/question"})
            elif method == "release":
                if held is not None:
                    emit({"id": held, "result": "released"})
                    held = None
            elif method == "hold":
                held = identifier
                emit({"method": "fixture/holding"})
            elif identifier is not None:
                result = params
                if method == "recorded":
                    result = recorded
                elif method == "clientResponse":
                    result = client_response
                elif method == "clientResponses":
                    result = client_responses
                elif method == "pid":
                    result = os.getpid()
                elif method == "fragment":
                    sys.stderr.buffer.write(b"synthetic diagnostic\n" * 16384)
                    sys.stderr.buffer.flush()
                emit({"id": identifier, "result": result}, fragmented=method == "fragment")
        """#
}
