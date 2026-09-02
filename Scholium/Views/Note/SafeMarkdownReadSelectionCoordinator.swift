import Foundation
import WebKit

/// Owns the native-to-Reader selection-surface activity state.
@MainActor
final class SafeMarkdownReadSelectionCoordinator {
    private(set) var isActive: Bool
    private var appliedIsActive: Bool?
    private var activityTask: Task<Void, Never>?
    private var activityTaskID: UUID?

    init(isActive: Bool) {
        self.isActive = isActive
    }

    func update(isActive: Bool) {
        self.isActive = isActive
    }

    func resetForDocumentChange() {
        appliedIsActive = nil
        cancel()
    }

    func cancel() {
        activityTask?.cancel()
        activityTask = nil
        activityTaskID = nil
    }

    func applyIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        applyActivityIfNeeded(
            pageIsReady: pageIsReady,
            in: webView,
            isCurrent: isCurrent
        )
    }

    private func applyActivityIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard pageIsReady, appliedIsActive != isActive else { return }
        let requestedActive = isActive
        activityTask?.cancel()
        let taskID = UUID()
        activityTaskID = taskID
        activityTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.activityTaskID == taskID {
                    self.activityTask = nil
                    self.activityTaskID = nil
                }
            }
            let result = try? await webView.callAsyncJavaScript(
                """
                if (window.scholiumReadReady) await window.scholiumReadReady;
                return window.scholiumSetReviewSelectionSurfaceActive?.(active) === true;
                """,
                arguments: ["active": requestedActive],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard !Task.isCancelled,
                  result as? Bool == true,
                  isCurrent(),
                  self.isActive == requestedActive else { return }
            self.appliedIsActive = requestedActive
        }
    }

}
