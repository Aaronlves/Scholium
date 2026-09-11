import Foundation
import Synchronization
import Testing

@testable import ScholiumCore

@Suite("Bounded Zotero HTTP responses")
struct ZoteroMCPHTTPClientTests {
    @Test("Declared and undeclared oversized bodies are refused; ordinary bytes remain exact")
    func boundedResponses() async throws {
        for mode in [HTTPFixtureProtocol.Mode.small, .declaredOversize, .streamOversize] {
            let fixture = HTTPFixture(mode: mode)
            defer { fixture.close() }
            if mode == .small {
                let response = try await fixture.transport.send(fixture.request)
                #expect(response.body == Data([0, 13, 10, 255]))
            } else {
                do {
                    _ = try await fixture.transport.send(fixture.request)
                    Issue.record("An oversized response was accepted")
                } catch ZoteroMCPServiceError.responseTooLarge {
                    // The declared-size case sends one chunk but no EOF, so this also
                    // proves refusal occurs before waiting for the download.
                }
            }
        }
    }

    @Test("Cancellation terminates the current response without waiting for EOF")
    func cancelsResponse() async throws {
        let fixture = HTTPFixture(mode: .hang)
        defer { fixture.close() }
        let task = Task { try await fixture.transport.send(fixture.request) }
        var started = fixture.started.makeAsyncIterator()
        _ = await started.next()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled response returned content")
        } catch is CancellationError {
        } catch let error as URLError {
            #expect(error.code == .cancelled)
        }
    }
}

private struct HTTPFixture {
    let id: String
    let session: URLSession
    let transport: ZoteroMCPURLSessionClient
    let request: URLRequest
    let started: AsyncStream<Void>

    init(mode: HTTPFixtureProtocol.Mode) {
        let fixtureID = UUID().uuidString
        id = fixtureID
        let events = AsyncStream<Void>.makeStream()
        started = events.stream
        HTTPFixtureProtocol.fixtures.withLock { $0[fixtureID] = .init(mode: mode, started: events.continuation) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPFixtureProtocol.self]
        configuration.timeoutIntervalForResource = 5
        session = URLSession(configuration: configuration, delegate: ZoteroNoRedirectDelegate(), delegateQueue: nil)
        transport = ZoteroMCPURLSessionClient(session: session)
        request = URLRequest(url: URL(string: "http://127.0.0.1:23119/fixture/\(id)")!)
    }

    func close() {
        session.invalidateAndCancel()
        HTTPFixtureProtocol.fixtures.withLock { $0.removeValue(forKey: id)?.started.finish() }
    }
}

private final class HTTPFixtureProtocol: URLProtocol {
    enum Mode: Sendable { case small, declaredOversize, streamOversize, hang }
    struct Fixture: Sendable {
        let mode: Mode
        let started: AsyncStream<Void>.Continuation
    }
    static let fixtures = Mutex<[String: Fixture]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let fixture = Self.fixtures.withLock({ $0[url.lastPathComponent] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let maximum = 4 * 1_024 * 1_024
        let headers = fixture.mode == .declaredOversize ? ["Content-Length": String(maximum + 1)] : [:]
        client?.urlProtocol(
            self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        fixture.started.yield()
        switch fixture.mode {
        case .small:
            client?.urlProtocol(self, didLoad: Data([0, 13, 10, 255]))
            client?.urlProtocolDidFinishLoading(self)
        case .streamOversize:
            client?.urlProtocol(self, didLoad: Data(repeating: 65, count: maximum + 1))
            client?.urlProtocolDidFinishLoading(self)
        case .declaredOversize:
            client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 65_536))
        case .hang:
            break
        }
    }

    override func stopLoading() {}
}

extension ZoteroMCPHTTPClientTests {
    @Test("The default Zotero transport declines redirects before following them")
    func redirectDelegateDeclinesRedirect() async throws {
        let original = try #require(URL(string: "http://127.0.0.1:23119/api/users/0/items"))
        let remote = try #require(URL(string: "https://example.invalid/items"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: original)
        let response = try #require(
            HTTPURLResponse(
                url: original,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": remote.absoluteString]
            ))
        let decision: URLRequest? = await withCheckedContinuation { continuation in
            ZoteroNoRedirectDelegate().urlSession(
                session,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: remote),
                completionHandler: { continuation.resume(returning: $0) }
            )
        }
        #expect(decision == nil)
    }
}
