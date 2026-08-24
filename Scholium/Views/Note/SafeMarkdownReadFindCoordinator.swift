import Foundation
import WebKit

/// Owns one Review find request, its applied identity, and the cancellable
/// WebKit query. Page load identity remains supplied by the parent coordinator.
@MainActor
final class SafeMarkdownReadFindCoordinator {
    private var request: DocumentFindPresentationRequest?
    private var report: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?
    private var appliedRequestID: UInt64?
    private var task: Task<Void, Never>?

    func update(
        request: DocumentFindPresentationRequest?,
        report: ((UInt64, Result<DocumentFindResult, any Error>) -> Void)?
    ) {
        self.request = request
        self.report = report
    }

    func resetForDocumentChange() {
        appliedRequestID = nil
        cancel()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func applyIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard pageIsReady,
              let request,
              request.id != appliedRequestID else { return }
        appliedRequestID = request.id
        let arguments: [String: Any]
        switch request.operation {
        case .clear:
            arguments = ["operation": "clear"]
        case .execute(let action):
            arguments = [
                "operation": "execute",
                "action": action.rawValue,
                "query": request.query,
                "replacement": request.replacement,
                "caseSensitive": request.caseSensitive,
                "wholeWord": request.wholeWord,
            ]
        }
        task?.cancel()
        task = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let raw = try await webView.callAsyncJavaScript(
                    "return window.scholiumReviewFind?.perform(request)",
                    arguments: ["request": arguments],
                    in: nil,
                    contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
                )
                guard !Task.isCancelled,
                      isCurrent(),
                      self.request?.id == request.id,
                      let payload = raw as? [String: Any],
                      let current = (payload["current"] as? NSNumber)?.intValue,
                      let total = (payload["total"] as? NSNumber)?.intValue,
                      current >= 0,
                      total >= 0,
                      current <= total else { return }
                self.report?(
                    request.id,
                    .success(DocumentFindResult(current: current, total: total))
                )
            } catch {
                guard !Task.isCancelled,
                      isCurrent(),
                      self.request?.id == request.id else { return }
                self.report?(request.id, .failure(error))
            }
        }
    }
}
