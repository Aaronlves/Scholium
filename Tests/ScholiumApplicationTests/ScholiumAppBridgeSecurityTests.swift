import Darwin
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Scholium App bridge security", .serialized)
struct ScholiumAppBridgeSecurityTests {
    @Test("Framing keeps connected sockets nonblocking and preserves their other flags")
    func framingPreservesDescriptorFlags() throws {
        let pair = try socketPair()
        defer { close(pair) }
        let writerFlags = Darwin.fcntl(pair.writer, F_GETFL, 0)
        let readerFlags = Darwin.fcntl(pair.reader, F_GETFL, 0)
        let payload = Data([7])
        try AppBridgeIO.writeFrame(payload, to: pair.writer, deadline: AppBridgeDeadline(timeout: 1))
        #expect(Darwin.fcntl(pair.writer, F_GETFL, 0) == writerFlags | O_NONBLOCK)
        #expect(try AppBridgeIO.readFrame(from: pair.reader, deadline: AppBridgeDeadline(timeout: 1)) == payload)
        #expect(Darwin.fcntl(pair.reader, F_GETFL, 0) == readerFlags | O_NONBLOCK)
    }

    @Test("A deadline failure after complete request delivery retains an uncertain outcome")
    func completedWriteThenExpiredDeadlineRemainsUncertain() throws {
        let pair = try socketPair()
        defer { close(pair) }
        let request = ScholiumAppBridgeRequest(mcpRequest: .init(tool: .search))
        let payload = Data(repeating: 7, count: 32) + (try JSONEncoder().encode(request))
        let response = try ScholiumAppBridgeResponse(
            correlationID: request.correlationID, mcpResponse: Self.success(request))
        #expect(throws: ScholiumAppBridgeError.outcomeUnknown) {
            try ScholiumAppBridgeClient.withRequestDeliveryOutcome {
                try AppBridgeIO.writeFrame(payload, to: pair.writer, deadline: AppBridgeDeadline(timeout: 1))
                // Deterministically model a writer resuming after the complete
                // frame was sent and its monotonic deadline expired.
                try AppBridgeDeadline(timeout: 0).check()
                return response
            }
        }
        #expect(try AppBridgeIO.readFrame(from: pair.reader, deadline: AppBridgeDeadline(timeout: 1)) == payload)
    }

    @Test("Intermittent header and body progress cannot renew a frame deadline", arguments: [true, false])
    func tricklingFrameExpires(headerOnly: Bool) async throws {
        let pair = try socketPair()
        defer { close(pair) }
        let bytes = headerOnly ? Data([0, 0, 0, 32]) : frame(Data(repeating: 7, count: 32))
        let writer = Task.detached {
            var written = 0
            if !headerOnly {
                do { try Self.send(Data(bytes.prefix(4)), to: pair.writer) } catch { return written }
            }
            for byte in headerOnly ? bytes : Data(bytes.dropFirst(4)) {
                do { try Task.checkCancellation() } catch { break }
                var byte = byte
                guard Darwin.send(pair.writer, &byte, 1, MSG_DONTWAIT) == 1 else { break }
                written += 1
                do { try await Task.sleep(for: .milliseconds(headerOnly ? 100 : 50)) } catch { break }
            }
            return written
        }
        let started = ContinuousClock.now
        let result = await Task.detached {
            Self.readResult(pair.reader, deadline: AppBridgeDeadline(timeout: 0.25))
        }.value
        let elapsed = started.duration(to: .now)
        writer.cancel()
        let written = await writer.value

        #expect(result == .failure(.timeout))
        #expect(written >= 2, "The fixture must make intermittent progress before expiry.")
        #expect(elapsed < .seconds(2))
    }

    @Test("A frame header and body share one absolute deadline")
    func headerDoesNotRenewBodyDeadline() async throws {
        let pair = try socketPair()
        defer { close(pair) }
        let writer = Task.detached {
            do {
                try await Task.sleep(for: .milliseconds(150))
                try Self.send(Data([0, 0, 0, 1]), to: pair.writer)
                try await Task.sleep(for: .milliseconds(150))
                try Self.send(Data([7]), to: pair.writer)
            } catch {}
        }
        let result = await Task.detached {
            Self.readResult(pair.reader, deadline: AppBridgeDeadline(timeout: 0.25))
        }.value
        writer.cancel()
        await writer.value
        #expect(result == .failure(.timeout))
    }

    @Test("A slow reader cannot renew the write-frame deadline")
    func tricklingReaderExpires() async throws {
        let pair = try socketPair()
        defer { close(pair) }
        var bufferSize: Int32 = 4_096
        #expect(setsockopt(pair.writer, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size)) == 0)
        let reader = Task.detached {
            var received = 0
            var bytes = [UInt8](repeating: 0, count: 1_024)
            while !Task.isCancelled {
                let amount = bytes.withUnsafeMutableBytes {
                    Darwin.recv(pair.reader, $0.baseAddress, $0.count, MSG_DONTWAIT)
                }
                if amount > 0 { received += amount }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
            }
            return received
        }
        let started = ContinuousClock.now
        let error = await Task.detached {
            do {
                try AppBridgeIO.writeFrame(
                    Data(repeating: 7, count: ScholiumAppBridgeLocation.maximumFrameByteCount),
                    to: pair.writer, deadline: AppBridgeDeadline(timeout: 0.25))
                return Optional<ScholiumAppBridgeError>.none
            } catch { return error as? ScholiumAppBridgeError }
        }.value
        let elapsed = started.duration(to: .now)
        reader.cancel()
        let received = await reader.value
        #expect(error == .timeout)
        #expect(received > 0, "The fixture must drain some bytes without completing the frame.")
        #expect(elapsed < .seconds(2))
    }

    @Test("The authentication exchange shares its original deadline after the challenge")
    func handshakeDoesNotRenewDeadline() async throws {
        let root = try makeRoot("authentication-deadline")
        defer { try? FileManager.default.removeItem(at: root) }
        let calls = BridgeSecurityCallCounter()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root, timeout: 0.4) { request in
            await calls.increment()
            return try Self.success(request)
        }
        defer { server.stop() }
        let peer = try connect(root)
        defer { Darwin.close(peer) }
        let started = ContinuousClock.now
        try await Task.sleep(for: .milliseconds(250))
        try AppBridgeIO.writeFrame(Data(repeating: 7, count: 32), to: peer, deadline: AppBridgeDeadline(timeout: 1))
        let challenge = try AppBridgeIO.readFrame(from: peer, deadline: AppBridgeDeadline(timeout: 1))
        #expect(challenge.count == 64)
        // Deliberately incomplete authentication body; every byte arrives faster
        // than the socket timeout, but the complete exchange exceeds its budget.
        try Self.send(Data([0, 0, 0, 64]), to: peer)
        let writer = Task.detached {
            for _ in 0..<64 {
                do {
                    try Task.checkCancellation()
                    try Self.send(Data([7]), to: peer)
                    try await Task.sleep(for: .milliseconds(25))
                } catch { break }
            }
        }
        let response = await Task.detached {
            Self.readResult(peer, deadline: AppBridgeDeadline(timeout: 1.5))
        }.value
        let elapsed = started.duration(to: .now)
        writer.cancel()
        await writer.value
        // Closing with unread authentication bytes can reset TCP instead of returning EOF.
        #expect(
            response == .failure(.invalidFrame) || response == .failure(.systemCall("read", ECONNRESET)),
            "Expired authentication closes the fixture socket.")
        #expect(elapsed < .seconds(1))
        #expect(await calls.count == 0)
        #expect(await server.stopAndWait(timeout: 1))
    }

    @Test("Pending peers cannot occupy any of the 32 authenticated slots")
    func pendingBudgetIsSeparate() {
        var budget = AppBridgePeerAdmission()
        for peer in 0..<AppBridgePeerAdmission.maximumAuthenticatedPeers {
            let admitted = budget.admit(Int32(peer))
            let authenticated = budget.authenticate(Int32(peer))
            #expect(admitted)
            #expect(authenticated)
        }
        for peer in 100..<(100 + AppBridgePeerAdmission.maximumPendingAuthentications) {
            let admitted = budget.admit(Int32(peer))
            #expect(admitted)
        }
        #expect(budget.descriptors.count == 40)
        let pendingOverflowAdmitted = budget.admit(200)
        let promotedWhileFull = budget.authenticate(100)
        #expect(!pendingOverflowAdmitted)
        #expect(!promotedWhileFull)
        budget.release(0)
        let promotedAfterRelease = budget.authenticate(100)
        let replacementPendingAdmitted = budget.admit(200)
        let secondPendingOverflowAdmitted = budget.admit(201)
        #expect(promotedAfterRelease)
        #expect(replacementPendingAdmitted)
        #expect(!secondPendingOverflowAdmitted)
    }

    @Test("Saturated pending authentication leaves an admitted operation able to reply")
    func pendingPeersDoNotDisplaceAuthenticatedWork() async throws {
        let root = try makeRoot("pending-budget")
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = BridgeSecurityGate()
        let server = try ScholiumAppBridgeServer(applicationSupportURL: root) { request in
            await gate.enterAndWait()
            return try Self.success(request)
        }
        defer { server.stop() }
        let operation = Task.detached {
            let client = try ScholiumAppBridgeClient(applicationSupportURL: root)
            return try client.send(.init(mcpRequest: .init(tool: .search)))
        }
        let entryDeadline = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await gate.expire()
        }
        await gate.waitForEntry()
        var peers: [Int32] = []
        defer {
            for peer in peers {
                Darwin.shutdown(peer, SHUT_RDWR)
                Darwin.close(peer)
            }
        }
        do {
            for _ in 0..<AppBridgePeerAdmission.maximumPendingAuthentications {
                let peer = try connect(root)
                peers.append(peer)
                try AppBridgeIO.writeFrame(Data(repeating: 7, count: 32), to: peer, deadline: AppBridgeDeadline(timeout: 1))
                #expect(try AppBridgeIO.readFrame(from: peer, deadline: AppBridgeDeadline(timeout: 1)).count == 64)
            }
            let rejected = try connect(root)
            peers.append(rejected)
            let rejection = await Task.detached {
                Self.readResult(rejected, deadline: AppBridgeDeadline(timeout: 1))
            }.value
            #expect(rejection == .failure(.invalidFrame))
        } catch {
            await gate.release()
            entryDeadline.cancel()
            await entryDeadline.value
            _ = try? await operation.value
            throw error
        }
        await gate.release()
        entryDeadline.cancel()
        await entryDeadline.value
        let response = try await operation.value
        #expect(response.mcpResponse?.result?.objectValue?["status"] == .string("ok"))
        #expect(await gate.didEnter)
        #expect(await !gate.expired, "The pending-peer fixture must finish before its own safety deadline.")
        #expect(await server.stopAndWait(timeout: 1))
    }

    private typealias SocketPair = (reader: Int32, writer: Int32)

    private func socketPair() throws -> SocketPair {
        var descriptors: [Int32] = [-1, -1]
        guard Darwin.socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw ScholiumAppBridgeError.systemCall("create fixture sockets", errno)
        }
        let pair = (reader: descriptors[0], writer: descriptors[1])
        do {
            try AppBridgeIO.configure(pair.reader, timeout: 2)
            try AppBridgeIO.configure(pair.writer, timeout: 2)
        } catch {
            close(pair)
            throw error
        }
        return pair
    }

    private func close(_ pair: SocketPair) {
        Darwin.close(pair.reader)
        Darwin.close(pair.writer)
    }

    private static func readResult(_ descriptor: Int32, deadline: AppBridgeDeadline) -> Result<Data, ScholiumAppBridgeError> {
        do { return .success(try AppBridgeIO.readFrame(from: descriptor, deadline: deadline)) } catch {
            return .failure((error as? ScholiumAppBridgeError) ?? .invalidResponse)
        }
    }

    private static func send(_ data: Data, to descriptor: Int32) throws {
        let amount = data.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress, $0.count, MSG_DONTWAIT) }
        guard amount == data.count else { throw ScholiumAppBridgeError.systemCall("send fixture bytes", errno) }
    }

    private func frame(_ data: Data) -> Data {
        let count = UInt32(data.count)
        return Data([UInt8((count >> 24) & 0xff), UInt8((count >> 16) & 0xff), UInt8((count >> 8) & 0xff), UInt8(count & 0xff)]) + data
    }

    private func connect(_ root: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ScholiumAppBridgeError.systemCall("create fixture socket", errno) }
        do {
            try AppBridgeIO.configure(descriptor, timeout: 2)
            var address = AppBridgeIO.address(port: ScholiumAppBridgeLocation.port(applicationSupportURL: root))
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw ScholiumAppBridgeError.systemCall("connect fixture socket", errno) }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func success(_ request: ScholiumAppBridgeRequest) throws -> ScholiumMCPBridgeResponse {
        try .init(requestID: request.mcpRequest.requestID, result: .object(["status": .string("ok")]))
    }

    private func makeRoot(_ name: String) throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/app-bridge-security-tests/\(name)-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return root
    }
}

private actor BridgeSecurityCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor BridgeSecurityGate {
    private(set) var didEnter = false
    private(set) var expired = false
    private var released = false
    private var entry: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    func waitForEntry() async {
        guard !didEnter, !released else { return }
        await withCheckedContinuation { entry = $0 }
    }

    func enterAndWait() async {
        didEnter = true
        entry?.resume()
        entry = nil
        guard !released else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func release() {
        released = true
        entry?.resume()
        entry = nil
        waiting?.resume()
        waiting = nil
    }

    func expire() {
        expired = true
        release()
    }
}
