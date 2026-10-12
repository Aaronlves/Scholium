import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Editor writing continuation request ownership")
@MainActor
struct EditorWritingContinuationControllerTests {
    @Test(
        "Retained or preparing editor cancellation releases its request and rejects late output",
        arguments: [DocumentSurfaceVisibility.retained, .preparing])
    func inactiveCoordinatorCancelsRequest(visibility: DocumentSurfaceVisibility) async {
        let session = MarkdownEditorSession(
            bridgeDispatcher: WKWebViewMarkdownEditorBridgeDispatcher(),
            citationIntegration: UnavailableContinuationCitationPort()
        )
        let coordinator = MarkdownEditorWebView.Coordinator(
            session: session, performanceDocumentID: "continuation-fixture",
            onDocumentActivity: {}, onRequestSave: {}, onRequestFind: { _ in },
            onRequestDocumentTitleRename: { _, title in title },
            linkCompletionQuery: { _, _ in .current([]) }, onLinkActivation: { _ in },
            onImagePreview: { _ in }, onScrollFractionChange: { _ in }, onScrollAnchorChange: { _ in }
        )
        let query = SuspendedContinuationQuery()
        var publications: [EditorWritingContinuationController.Publication] = []
        let task = coordinator.writingContinuation.start(
            requestID: "hidden-editor", sourceCaret: 2, editorCaret: 2,
            query: { _, status in await query.run(status: status) },
            isCurrent: { true }, publish: { publications.append($0) }
        )
        await query.waitUntilStarted()
        coordinator.surfaceVisibility = visibility
        #expect(coordinator.writingContinuation.requestID == nil)
        #expect(coordinator.writingContinuation.editorCaret == nil)
        coordinator.surfaceVisibility = .active
        query.finish(.suggestion("late output"))
        await task.value
        #expect(task.isCancelled)
        #expect(publications.isEmpty)
        #expect(coordinator.writingContinuation.requestID == nil)
    }

    @Test("A replaced request cannot publish or clear its successor, even with a reused request ID")
    func replacedRequestCannotAffectSuccessor() async {
        let controller = EditorWritingContinuationController()
        let first = SuspendedContinuationQuery()
        let second = SuspendedContinuationQuery()
        var publications: [EditorWritingContinuationController.Publication] = []
        let firstTask = controller.start(
            requestID: "request", sourceCaret: 2, editorCaret: 2,
            query: { _, status in await first.run(status: status) },
            isCurrent: { true },
            publish: { publications.append($0) }
        )
        await first.waitUntilStarted()
        let secondTask = controller.start(
            requestID: "request", sourceCaret: 4, editorCaret: 4,
            query: { _, status in await second.run(status: status) },
            isCurrent: { true },
            publish: { publications.append($0) }
        )
        await second.waitUntilStarted()

        // Deliberately ignore task cancellation, as an external provider can.
        first.finish(.suggestion("obsolete"))
        await firstTask.value
        #expect(publications.isEmpty)
        #expect(controller.requestID == "request")
        #expect(controller.editorCaret == 4)

        second.finish(.suggestion("current"))
        await secondTask.value
        #expect(publications == [.result(.suggestion("current"))])
        #expect(controller.requestID == nil)
        #expect(controller.editorCaret == nil)
    }

    @Test("A current request delivers progress and its result through the same publication boundary")
    func currentRequestPublishesStatusAndResult() async {
        let controller = EditorWritingContinuationController()
        let query = SuspendedContinuationQuery()
        var publications: [EditorWritingContinuationController.Publication] = []
        var statusContinuation: CheckedContinuation<Void, Never>?
        var statusDelivered = false
        let task = controller.start(
            requestID: "current-request", sourceCaret: 2, editorCaret: 2,
            query: { _, status in await query.run(status: status, reportsProgress: true) },
            isCurrent: { true },
            publish: { publication in
                publications.append(publication)
                if publication == .status(.generating) {
                    statusDelivered = true
                    statusContinuation?.resume()
                    statusContinuation = nil
                }
            }
        )
        await query.waitUntilStarted()
        if !statusDelivered {
            await withCheckedContinuation { statusContinuation = $0 }
        }
        #expect(publications == [.status(.generating)])
        query.finish(.suggestion("current"))
        await task.value
        #expect(publications == [.status(.generating), .result(.suggestion("current"))])
    }

    @Test("Page admission can reject a late result without transferring document authority")
    func obsoletePageCannotPublish() async {
        let controller = EditorWritingContinuationController()
        let query = SuspendedContinuationQuery()
        let page = PageAdmission()
        var publications: [EditorWritingContinuationController.Publication] = []
        let task = controller.start(
            requestID: "page-request", sourceCaret: 2, editorCaret: 2,
            query: { _, status in await query.run(status: status) },
            isCurrent: { page.isCurrent },
            publish: { publications.append($0) }
        )
        await query.waitUntilStarted()
        page.isCurrent = false
        query.finish(.suggestion("obsolete page"))
        await task.value
        #expect(publications.isEmpty)
        #expect(controller.requestID == nil)
    }

    @Test("Explicit cancellation clears transient state and rejects a provider that finishes later")
    func cancelledRequestCannotPublish() async {
        let controller = EditorWritingContinuationController()
        let query = SuspendedContinuationQuery()
        var publications: [EditorWritingContinuationController.Publication] = []
        let task = controller.start(
            requestID: "cancelled-request", sourceCaret: 2, editorCaret: 2,
            query: { _, status in await query.run(status: status) },
            isCurrent: { true },
            publish: { publications.append($0) }
        )
        await query.waitUntilStarted()
        controller.cancel()
        #expect(controller.requestID == nil)
        #expect(controller.editorCaret == nil)
        query.finish(.suggestion("cancelled result"))
        await task.value
        #expect(publications.isEmpty)
    }
}

@MainActor
private final class SuspendedContinuationQuery {
    private var resultContinuation: CheckedContinuation<EditorWritingContinuationResult, Never>?
    private var startedContinuation: CheckedContinuation<Void, Never>?

    func run(
        status: EditorWritingContinuationStatusHandler,
        reportsProgress: Bool = false
    ) async -> EditorWritingContinuationResult {
        if reportsProgress { status(.generating) }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            startedContinuation?.resume()
            startedContinuation = nil
        }
    }

    func waitUntilStarted() async {
        if resultContinuation != nil { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func finish(_ result: EditorWritingContinuationResult) {
        let continuation = resultContinuation
        resultContinuation = nil
        continuation?.resume(returning: result)
    }
}

@MainActor
private final class PageAdmission {
    var isCurrent = true
}

private actor UnavailableContinuationCitationPort: ZoteroDocumentIntegrating {
    func run(
        transactionID: String, command: ZoteroDocumentCommand, documentID: String,
        authority: @escaping @Sendable () async -> ZoteroDocumentAuthority,
        handler: @escaping @Sendable (ZoteroDocumentCallback) async throws -> ZoteroDocumentReply
    ) async -> ZoteroDocumentIntegrationResult {
        Issue.record("A continuation ownership test must not request Zotero.")
        return .init(status: .unavailable, remoteCleanupConfirmed: false, callbackCount: 0, message: nil)
    }
    func cancelCurrentTransaction(transactionID: String) async {}
}
