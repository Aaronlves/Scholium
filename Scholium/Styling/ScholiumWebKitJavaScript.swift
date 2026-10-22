import WebKit

/// Waiting for a JavaScript promise belongs to the calling page task. WebKit's
/// physical invocation can finish later; it must not keep that task and its
/// page alive after cancellation. No JavaScript value crosses the main actor.
/// The public Objective-C SDK refinements preserve undefined (nil) separately
/// from null (NSNull), which the Swift Result<Any, Error> callback erases.
@MainActor
extension WKWebView {
    func callCancellableJavaScript(
        _ body: String, arguments: [String: Any] = [:],
        in frame: WKFrameInfo? = nil, contentWorld: WKContentWorld
    ) async throws -> Any? {
        let receipt = ScholiumJavaScriptReceipt()
        return try await receipt.wait { completion in
            __callAsyncJavaScript(body, arguments: arguments, inFrame: frame, in: contentWorld, completionHandler: completion)
        }
    }

    func evaluateCancellableJavaScript(
        _ script: String, in frame: WKFrameInfo? = nil, contentWorld: WKContentWorld
    ) async throws -> Any? {
        let receipt = ScholiumJavaScriptReceipt()
        return try await receipt.wait { completion in
            __evaluateJavaScript(script, inFrame: frame, in: contentWorld, completionHandler: completion)
        }
    }
}

@MainActor
private final class ScholiumJavaScriptReceipt {
    typealias Completion = @MainActor @Sendable (Any?, (any Error)?) -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private var result: Result<Any?, any Error>?

    func wait(_ start: (@escaping Completion) -> Void) async throws -> Any? {
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if result != nil {
                    continuation.resume()
                    return
                }
                self.continuation = continuation
                guard !Task.isCancelled else {
                    finish(.failure(CancellationError()))
                    return
                }
                start { [weak self] value, error in
                    if let error { self?.finish(.failure(error)) } else { self?.finish(.success(value)) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        // Every continuation resume installs its outcome first.
        return try result!.get()
    }

    private func finish(_ outcome: Result<Any?, any Error>) {
        guard result == nil else { return }
        result = outcome
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
