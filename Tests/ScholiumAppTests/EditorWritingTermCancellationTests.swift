import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Local writing completion request cancellation")
@MainActor
struct EditorWritingTermCancellationTests {
    @Test("Cancellation stops a suspended corpus read before its next source and prevents publication", arguments: ["abort", "retained", "preparing"])
    func cancelledReadStops(reason: String) async {
        let read = SuspendedWritingRead()
        let coordinator = makeCoordinator { _, _ in await read.run() }
        var published = false
        let task = coordinator.startLinkCompletionQuery(
            requestID: "current", kind: .term, query: "Term", isCurrent: { true }, publish: { _ in published = true })
        await read.waitUntilStarted()
        coordinator.cancelWritingTermQuery(requestID: "unrelated")
        #expect(!task.isCancelled)
        switch reason {
        case "retained": coordinator.surfaceVisibility = .retained
        case "preparing": coordinator.surfaceVisibility = .preparing
        default: coordinator.cancelWritingTermQuery(requestID: "current")
        }
        #expect(task.isCancelled)
        read.resume()
        await task.value
        #expect(read.sawCancellation)
        #expect(read.sourceReads == 1)
        #expect(!published)
    }

    @Test("A late cancellation or old task cannot cancel or clear a newer request")
    func predecessorCannotAffectSuccessor() async {
        let first = SuspendedWritingRead()
        let second = SuspendedWritingRead()
        let coordinator = makeCoordinator { _, query in await (query == "first" ? first : second).run() }
        var publications: [String] = []
        let old = coordinator.startLinkCompletionQuery(
            requestID: "first", kind: .term, query: "first", isCurrent: { true }, publish: { _ in publications.append("first") })
        await first.waitUntilStarted()
        let current = coordinator.startLinkCompletionQuery(
            requestID: "second", kind: .term, query: "second", isCurrent: { true }, publish: { _ in publications.append("second") })
        await second.waitUntilStarted()
        coordinator.cancelWritingTermQuery(requestID: "first")
        #expect(!current.isCancelled)
        first.resume()
        await old.value
        coordinator.cancelWritingTermQuery(requestID: "second")
        #expect(current.isCancelled)
        second.resume()
        await current.value
        #expect(publications.isEmpty)
        #expect(first.sourceReads == 1 && second.sourceReads == 1)
    }

    @Test("Confirmed empty and unavailable local results remain distinct through coordinator publication")
    func freshnessPublication() async {
        for current in [true, false] {
            let coordinator = makeCoordinator { _, _ in current ? .current([]) : .unavailable }
            var response: EditorLinkCompletionResponse?
            let task = coordinator.startLinkCompletionQuery(
                requestID: "freshness", kind: .term, query: "res", isCurrent: { true }, publish: { response = $0 })
            await task.value
            #expect(response?.isCurrent == current)
            #expect(response?.candidates.isEmpty == true)
        }
    }

    private func makeCoordinator(query: @escaping @MainActor (EditorLinkCompletionKind, String) async -> EditorLinkCompletionResponse)
        -> MarkdownEditorWebView.Coordinator
    {
        let session = MarkdownEditorSession(
            bridgeDispatcher: WKWebViewMarkdownEditorBridgeDispatcher(), citationIntegration: UnavailableLocalCompletionCitationPort())
        return MarkdownEditorWebView.Coordinator(
            session: session, performanceDocumentID: "synthetic-local-completion",
            onDocumentActivity: {}, onRequestSave: {}, onRequestFind: { _ in },
            onRequestDocumentTitleRename: { _, title in title }, linkCompletionQuery: query,
            onLinkActivation: { _ in }, onImagePreview: { _ in },
            onScrollFractionChange: { _ in }, onScrollAnchorChange: { _ in }
        )
    }
}

@MainActor
private final class SuspendedWritingRead {
    private var started = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var sourceReads = 0
    private(set) var sawCancellation = false
    func run() async -> EditorLinkCompletionResponse {
        sourceReads += 1
        await withCheckedContinuation { continuation in
            pending = continuation
            started = true
            startedWaiter?.resume()
            startedWaiter = nil
        }
        do { try Task.checkCancellation() } catch {
            sawCancellation = true
            return .unavailable
        }
        sourceReads += 1
        return .current([])
    }
    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { startedWaiter = $0 } }
    }
    func resume() {
        pending?.resume()
        pending = nil
    }
}

private actor UnavailableLocalCompletionCitationPort: ZoteroDocumentIntegrating {
    func run(
        transactionID: String, command: ZoteroDocumentCommand, documentID: String,
        authority: @escaping @Sendable () async -> ZoteroDocumentAuthority,
        handler: @escaping @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
    ) async -> ZoteroDocumentIntegrationResult {
        Issue.record("Local completion must not request Zotero.")
        return .init(status: .unavailable, remoteCleanupConfirmed: false, callbackCount: 0, message: nil)
    }
    func cancelCurrentTransaction(transactionID: String) async {}
}
