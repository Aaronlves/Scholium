import Foundation
import ScholiumApplication
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Application citation termination", .serialized)
struct ApplicationCitationTerminationTests {
    private static let documentID = "scholium-quit-fixture"

    @Test("Quit refuses before flushing a window with an active citation callback")
    func activeCitationPreservesWindowAndCallback() async {
        let transport = HeldCompletion()
        let integration = ZoteroDocumentIntegration(transport: { await transport.send($0) })
        let pending = Task {
            await integration.run(
                transactionID: "pending-picker", command: .addEditCitation, documentID: Self.documentID,
                authority: { .current }, handler: { _ in .none })
        }
        await transport.waitForRequest()
        let delegate = ScholiumApplicationDelegate()
        var flushed = false
        delegate.windowLifecycleRegistry.register(id: UUID()) { flushed = true }
        delegate.windowLifecycleRegistry.beginTerminationAttempt()

        let outcome = await delegate.prepareApplicationTermination(citations: Self.terminationCapabilities(for: integration))

        #expect(outcome == .citationPending)
        #expect(!flushed)
        #expect(!delegate.windowLifecycleRegistry.isTerminationAttemptInProgress)
        #expect(await transport.requestCount == 1)
        await transport.release()
        let completion = await pending.value
        #expect(completion.status == .cleanedUp && completion.remoteCleanupConfirmed)
    }

    @Test("Windowless quit also closes citation admission")
    func windowlessQuitClosesAdmission() async {
        let integration = ZoteroDocumentIntegration(transport: { _ in
            Issue.record("A quitting process must not start a Zotero request")
            return Self.completeResponse
        })
        let delegate = ScholiumApplicationDelegate()
        delegate.windowLifecycleRegistry.beginTerminationAttempt()
        #expect(await delegate.prepareApplicationTermination(citations: Self.terminationCapabilities(for: integration)) == .ready)
        #expect(delegate.windowLifecycleRegistry.isTerminationAttemptInProgress)
        let late = await integration.run(
            transactionID: "late-windowless", command: .refresh, documentID: Self.documentID,
            authority: { .current }, handler: { _ in .none })
        #expect(late.status == .unavailable && late.callbackCount == 0)
    }

    @Test("Save failure reopens citation admission after guarding the flush")
    func failedSaveReopensAdmission() async {
        let integration = ZoteroDocumentIntegration(transport: { _ in Self.completeResponse })
        let delegate = ScholiumApplicationDelegate()
        delegate.windowLifecycleRegistry.register(id: UUID()) {
            let duringFlush = await integration.run(
                transactionID: "during-flush", command: .refresh, documentID: Self.documentID,
                authority: { .current }, handler: { _ in .none })
            #expect(duringFlush.status == .unavailable && duringFlush.callbackCount == 0)
            throw SaveFailure.refused
        }
        delegate.windowLifecycleRegistry.beginTerminationAttempt()
        #expect(await delegate.prepareApplicationTermination(citations: Self.terminationCapabilities(for: integration)) == .failed)
        #expect(!delegate.windowLifecycleRegistry.isTerminationAttemptInProgress)
        let resumed = await integration.run(
            transactionID: "after-save-failure", command: .refresh, documentID: Self.documentID,
            authority: { .current }, handler: { _ in .none })
        #expect(resumed.status == .cleanedUp && resumed.remoteCleanupConfirmed)
    }

    private enum SaveFailure: Error { case refused }

    private static func terminationCapabilities(for integration: ZoteroDocumentIntegration) -> CitationTerminationCapabilities {
        CitationTerminationCapabilities(
            begin: { await integration.beginApplicationTermination() },
            cancel: { await integration.cancelApplicationTermination() })
    }

    private nonisolated static var completeResponse: ZoteroDocumentHTTPResponse {
        .init(statusCode: 200, body: Data(#"{"command":"Document.complete","arguments":["scholium-quit-fixture"]}"#.utf8))
    }

    private actor HeldCompletion {
        private(set) var requestCount = 0
        private var entered: CheckedContinuation<Void, Never>?
        private var response: CheckedContinuation<ZoteroDocumentHTTPResponse, Never>?

        func send(_ request: URLRequest) async -> ZoteroDocumentHTTPResponse {
            requestCount += 1
            entered?.resume()
            entered = nil
            return await withCheckedContinuation { response = $0 }
        }

        func waitForRequest() async {
            if requestCount > 0 { return }
            await withCheckedContinuation { entered = $0 }
        }

        func release() {
            response?.resume(returning: ApplicationCitationTerminationTests.completeResponse)
            response = nil
        }
    }
}
