import Darwin
import Foundation
@testable import ScholiumApplication
import ScholiumContracts
import Testing

@Suite("Local Agent bridge", .serialized)
struct LocalAgentBridgeTests {
    @Test("The bridge wire rejects unknown fields, unknown operations, and old versions")
    func strictCurrentWire() throws {
        let request = try pairRequest()
        let encoded = try LocalAgentBridgeWireCoding.encode(request)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["pairing_code"] as? String == request.pairingCode?.rawValue)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("rawValue"))
        #expect(!String(reflecting: request).contains(
            try #require(request.pairingCode).rawValue
        ))
        object["unexpected_secret"] = String(repeating: "x", count: 73)
        #expect(throws: (any Error).self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object.removeValue(forKey: "unexpected_secret")
        object["operation"] = "status"
        #expect(throws: (any Error).self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        object["operation"] = "pair"
        object["schema_version"] = LocalAgentBridgeRequest.currentSchemaVersion - 1
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeWireCoding.decode(
                LocalAgentBridgeRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let credential = try testCredential()
        let response = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            credential: credential
        )
        let responseObject = try #require(
            JSONSerialization.jsonObject(
                with: LocalAgentBridgeWireCoding.encode(response)
            ) as? [String: Any]
        )
        let wireCredential = try #require(
            responseObject["credential"] as? [String: Any]
        )
        #expect(UUID(uuidString: wireCredential["session_id"] as? String ?? "")
            == credential.sessionID)
        #expect(wireCredential["secret"] as? String == credential.secret)
        #expect(wireCredential["sessionID"] == nil)
        #expect(!String(reflecting: response).contains(credential.secret))
    }

    @Test("A current-UID peer is accepted and bridge state persists no credential")
    func currentUIDAndSecretBoundary() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let reached = LockedFlag()
        let credential = try testCredential()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.2
        ) { request in
            guard request.operation == .pair else { throw TestFailure.expected }
            reached.set()
            return .credential(credential)
        }
        defer { server.stop() }

        let socketURL = try LocalAgentBridgeLocation.socketURL(
            applicationSupportURL: fixture.support
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.deletingLastPathComponent().path
        )
        let socketAttributes = try FileManager.default.attributesOfItem(
            atPath: socketURL.path
        )
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect((socketAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let response = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 0.5
        ).send(try pairRequest())
        #expect(response.credential == credential)
        #expect(reached.value)

        let enumerator = FileManager.default.enumerator(
            at: fixture.support,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey]))
                .isRegularFile == true else { continue }
            #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self)
                .contains(credential.secret))
        }
    }

    @Test("Malformed, oversized, and idle connections fail closed")
    func boundedFramesAndTimeout() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.1
        ) { _ in throw TestFailure.expected }
        defer { server.stop() }
        let socketURL = try LocalAgentBridgeLocation.socketURL(
            applicationSupportURL: fixture.support
        )
        #expect(try sendRawFrame(Data("{}".utf8), to: socketURL).error?.code
            == .invalidRequest)
        #expect(try sendRawPrefix(
            UInt32(LocalAgentBridgeLocation.maximumFrameByteCount + 1),
            to: socketURL
        ).error?.code == .invalidFrame)
        #expect(try sendNothing(to: socketURL).error?.code == .timeout)
    }

    @Test("A timed-out handler is cancelled without a late mutation")
    func handlerTimeoutOwnsCancellation() async throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let entered = LockedFlag()
        let cancellationObserved = LockedFlag()
        let committed = LockedFlag()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 0.1
        ) { _ in
            entered.set()
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                cancellationObserved.set()
                throw error
            }
            committed.set()
            return .credential(try testCredential())
        }
        defer { server.stop() }
        let client = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 1
        )
        do {
            _ = try client.send(try pairRequest())
            Issue.record("Expected a bounded timeout.")
        } catch let error as LocalAgentBridgeError {
            guard case .remote(let payload) = error else {
                Issue.record("Unexpected bridge error: \(error)")
                return
            }
            #expect(payload.code == .outcomeUnknown)
        }
        #expect(entered.value)
        #expect(cancellationObserved.value)
        #expect(!committed.value)
    }

    @Test("Shutdown awaits the active handler before releasing ownership")
    func shutdownOwnsActiveHandler() async throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        let entered = LockedFlag()
        let cancelled = LockedFlag()
        let gate = AsyncGate()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support,
            timeout: 1
        ) { _ in
            entered.set()
            await gate.wait()
            do { try Task.checkCancellation() }
            catch {
                cancelled.set()
                throw error
            }
            return .credential(try testCredential())
        }
        let client = try LocalAgentBridgeClient(
            applicationSupportURL: fixture.support,
            timeout: 2
        )
        let response = Task.detached { try? client.send(try pairRequest()) }
        for _ in 0..<100 where !entered.value {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(entered.value)
        let stopped = Task { await server.stopAndWait() }
        try await Task.sleep(for: .milliseconds(25))
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeServer(
                applicationSupportURL: fixture.support
            ) { _ in throw TestFailure.expected }
        }
        await gate.open()
        #expect(await stopped.value)
        _ = await response.value
        #expect(cancelled.value)
        let replacement = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support
        ) { _ in throw TestFailure.expected }
        #expect(await replacement.stopAndWait())
    }

    @Test("Bounded write results round-trip without a retired coordination payload")
    func boundedWriteResultRoundTrip() throws {
        let entry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(runID: UUID(), noteID: UUID()),
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Agency.md"),
            role: .topic,
            title: "Agency",
            allowedOperations: [.modifyMarkdown],
            expectedRevision: DocumentFingerprint(content: "before"),
            checkpointID: UUID(),
            authorizationBasis: .initialAction,
            expiresAt: Date().addingTimeInterval(60)
        )
        let result = ResearchDocumentWriteResult(
            operationID: UUID(),
            state: .committed,
            target: ResearchBoundedWriteSetViewEntry(entry),
            message: "Committed and read back."
        )
        let response = try LocalAgentBridgeResponse(
            correlationID: UUID(),
            documentWriteResult: result
        )
        let decoded = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(response)
        )
        #expect(decoded.documentWriteResult == result)
    }

    @Test("Method improvement context and one-file submission round-trip without exposing a capability")
    func methodImprovementRoundTrip() throws {
        let locator = try #require(ResearchRunLocator(
            rawValue: "methodimprovementrunabcd"
        ))
        let credential = try testCredential()
        let registration = try ResearchSkillRegistration(
            actionID: .write,
            displayName: "Write Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Write Method\n",
            practices: []
        )
        let improvement = try ResearchMethodImprovementRun(
            id: UUID(),
            parentRecordID: UUID(),
            triptychID: UUID(),
            registrationKey: registration.key,
            actionID: .write,
            method: method,
            feedbackRevision: UUID(),
            feedbackText: "Clarify one preservation boundary.",
            expectedResultFingerprint: DocumentFingerprint(content: "result")
        )
        let context = try ResearchMethodImprovementContext(
            run: locator,
            improvement: improvement
        )
        let contextRequest = try LocalAgentBridgeRequest(
            operation: .methodImprovementContext,
            run: locator,
            credential: credential
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: LocalAgentBridgeWireCoding.encode(contextRequest)
        ).operation == .methodImprovementContext)
        let submission = try ResearchMethodImprovementSubmission(
            requestID: UUID(),
            feedbackRevision: improvement.feedbackRevision,
            expectedResultFingerprint: improvement.expectedResultFingerprint,
            targetID: "primary-method",
            expectedTargetRevision: method.primaryMarkdownRevision,
            disposition: .diagnosedNoChange,
            diagnosis: "The issue concerns execution rather than the Method."
        )
        let submitRequest = try LocalAgentBridgeRequest(
            operation: .submitMethodImprovement,
            run: locator,
            credential: credential,
            methodImprovementSubmission: submission
        )
        let decodedRequest = try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeRequest.self,
            from: LocalAgentBridgeWireCoding.encode(submitRequest)
        )
        #expect(decodedRequest.methodImprovementSubmission == submission)
        #expect(!String(reflecting: decodedRequest).contains(credential.secret))

        let contextResponse = try LocalAgentBridgeResponse(
            correlationID: contextRequest.correlationID,
            methodImprovementContext: context
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(contextResponse)
        ).methodImprovementContext == context)
        let receipt = try ResearchMethodImprovementReceipt(
            runID: improvement.id,
            requestID: submission.requestID,
            disposition: submission.disposition,
            targetID: submission.targetID,
            startingRevision: submission.expectedTargetRevision,
            endingRevision: submission.expectedTargetRevision,
            feedbackCleared: true,
            diagnosis: submission.diagnosis
        )
        let receiptResponse = try LocalAgentBridgeResponse(
            correlationID: submitRequest.correlationID,
            methodImprovementReceipt: receipt
        )
        #expect(try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: LocalAgentBridgeWireCoding.encode(receiptResponse)
        ).methodImprovementReceipt == receipt)
    }

    @Test("A closed App remains unavailable and unsafe ownership is rejected")
    func absenceAndOwnership() throws {
        let fixture = try BridgeFixture()
        defer { fixture.remove() }
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeClient(
                applicationSupportURL: fixture.support,
                timeout: 0.1
            ).send(try pairRequest())
        }
        let first = try LocalAgentBridgeServer(
            applicationSupportURL: fixture.support
        ) { _ in throw TestFailure.expected }
        defer { first.stop() }
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeServer(
                applicationSupportURL: fixture.support
            ) { _ in throw TestFailure.expected }
        }

        let unsafe = try BridgeFixture()
        defer { unsafe.remove() }
        let target = unsafe.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: unsafe.support.appendingPathComponent("b"),
            withDestinationURL: target
        )
        #expect(throws: LocalAgentBridgeError.self) {
            _ = try LocalAgentBridgeServer(
                applicationSupportURL: unsafe.support
            ) { _ in throw TestFailure.expected }
        }
    }

    private func sendRawFrame(
        _ data: Data,
        to socketURL: URL
    ) throws -> LocalAgentBridgeResponse {
        let length = UInt32(data.count)
        let header = Data([
            UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
        ])
        return try withConnectedSocket(to: socketURL) { descriptor in
            try writeAll(header + data, to: descriptor)
            return try readResponse(from: descriptor)
        }
    }

    private func sendRawPrefix(
        _ length: UInt32,
        to socketURL: URL
    ) throws -> LocalAgentBridgeResponse {
        try withConnectedSocket(to: socketURL) { descriptor in
            try writeAll(Data([
                UInt8((length >> 24) & 0xff), UInt8((length >> 16) & 0xff),
                UInt8((length >> 8) & 0xff), UInt8(length & 0xff),
            ]), to: descriptor)
            return try readResponse(from: descriptor)
        }
    }

    private func sendNothing(to socketURL: URL) throws -> LocalAgentBridgeResponse {
        try withConnectedSocket(to: socketURL) { try readResponse(from: $0) }
    }

    private func withConnectedSocket<T>(
        to url: URL,
        _ body: (Int32) throws -> T
    ) throws -> T {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw TestFailure.socket }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8) + [0]
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let length = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + bytes.count
        address.sun_len = UInt8(length)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(length))
            }
        }
        guard connected == 0 else { throw TestFailure.socket }
        return try body(descriptor)
    }

    private func readResponse(from descriptor: Int32) throws -> LocalAgentBridgeResponse {
        let header = try readExactly(4, from: descriptor)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let data = try readExactly(Int(length), from: descriptor)
        return try LocalAgentBridgeWireCoding.decode(
            LocalAgentBridgeResponse.self,
            from: data
        )
    }

    private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let amount = result.withUnsafeMutableBytes {
                read(descriptor, $0.baseAddress!.advanced(by: offset), count - offset)
            }
            guard amount > 0 else { throw TestFailure.socket }
            offset += amount
        }
        return result
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let amount = data.withUnsafeBytes {
                write(descriptor, $0.baseAddress!.advanced(by: offset), data.count - offset)
            }
            guard amount > 0 else { throw TestFailure.socket }
            offset += amount
        }
    }
}

private func pairRequest() throws -> LocalAgentBridgeRequest {
    try LocalAgentBridgeRequest(
        operation: .pair,
        run: ResearchRunLocator(rawValue: "abcdefghijklmnopqrstuvwx")!,
        pairingCode: ResearchPairingCode(rawValue: "23456789ABCDEFGHJKLMNPQR")!
    )
}

private func testCredential() throws -> ResearchConnectionCredential {
    try ResearchConnectionCredential(
        sessionID: UUID(),
        secret: String(repeating: "s", count: 48)
    )
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private struct BridgeFixture {
    let root: URL
    let support: URL

    init() throws {
        root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(".build/b/\(String(UUID().uuidString.prefix(8)))")
        support = root.appendingPathComponent("a", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private enum TestFailure: Error {
    case expected
    case socket
}
