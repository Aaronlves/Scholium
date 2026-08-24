import Foundation
import WebKit

/// Owns native-to-Reader selection-surface commands and their one-shot
/// identities. Selection content and Comment authorization remain native.
@MainActor
final class SafeMarkdownReadSelectionCoordinator {
    private var desiredComposerRequestID: UUID?
    private var appliedComposerRequestID: UUID?
    private var desiredResolution: PassageCommentResolution?
    private var appliedResolution: PassageCommentResolution?
    private(set) var isActive: Bool
    private var appliedIsActive: Bool?
    private var composerTask: Task<Void, Never>?
    private var composerTaskID: UUID?
    private var resolutionTask: Task<Void, Never>?
    private var resolutionTaskID: UUID?
    private var activityTask: Task<Void, Never>?
    private var activityTaskID: UUID?

    init(
        composerRequestID: UUID?,
        resolution: PassageCommentResolution?,
        isActive: Bool
    ) {
        if composerRequestID != desiredComposerRequestID {
            composerTask?.cancel()
            composerTask = nil
            composerTaskID = nil
        }
        if resolution != desiredResolution {
            resolutionTask?.cancel()
            resolutionTask = nil
            resolutionTaskID = nil
        }
        desiredComposerRequestID = composerRequestID
        desiredResolution = resolution
        self.isActive = isActive
    }

    func update(
        composerRequestID: UUID?,
        resolution: PassageCommentResolution?,
        isActive: Bool
    ) {
        desiredComposerRequestID = composerRequestID
        desiredResolution = resolution
        self.isActive = isActive
    }

    func resetForDocumentChange() {
        appliedComposerRequestID = nil
        appliedResolution = nil
        appliedIsActive = nil
        cancel()
    }

    func cancel() {
        composerTask?.cancel()
        composerTask = nil
        composerTaskID = nil
        resolutionTask?.cancel()
        resolutionTask = nil
        resolutionTaskID = nil
        activityTask?.cancel()
        activityTask = nil
        activityTaskID = nil
    }

    func applyIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        applyComposerIfNeeded(
            pageIsReady: pageIsReady,
            in: webView,
            isCurrent: isCurrent
        )
        applyResolutionIfNeeded(
            pageIsReady: pageIsReady,
            in: webView,
            isCurrent: isCurrent
        )
        applyActivityIfNeeded(
            pageIsReady: pageIsReady,
            in: webView,
            isCurrent: isCurrent
        )
    }

    func updateResolution(_ resolution: PassageCommentResolution) {
        if resolution != desiredResolution {
            resolutionTask?.cancel()
            resolutionTask = nil
            resolutionTaskID = nil
        }
        desiredResolution = resolution
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

    private func applyComposerIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard pageIsReady,
              let requestID = desiredComposerRequestID,
              requestID != appliedComposerRequestID,
              composerTask == nil else { return }
        let taskID = UUID()
        composerTaskID = taskID
        composerTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.composerTaskID == taskID {
                    self.composerTask = nil
                    self.composerTaskID = nil
                }
            }
            guard !Task.isCancelled, isCurrent() else { return }
            let result = try? await webView.callAsyncJavaScript(
                "return window.scholiumShowCommentComposer?.() === true",
                arguments: [:],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard !Task.isCancelled,
                  result as? Bool == true,
                  isCurrent(),
                  self.desiredComposerRequestID == requestID else { return }
            self.appliedComposerRequestID = requestID
        }
    }

    private func applyResolutionIfNeeded(
        pageIsReady: Bool,
        in webView: WKWebView,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        guard pageIsReady,
              let resolution = desiredResolution,
              resolution != appliedResolution,
              resolutionTask == nil else { return }
        let taskID = UUID()
        resolutionTaskID = taskID
        resolutionTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.resolutionTaskID == taskID {
                    self.resolutionTask = nil
                    self.resolutionTaskID = nil
                }
            }
            guard !Task.isCancelled, isCurrent() else { return }
            let result = try? await webView.callAsyncJavaScript(
                "return window.scholiumResolveCommentSubmission?.(requestID, succeeded) === true",
                arguments: [
                    "requestID": resolution.requestID,
                    "succeeded": resolution.succeeded,
                ],
                in: nil,
                contentWorld: SafeMarkdownReadWebView.bridgeContentWorld
            )
            guard !Task.isCancelled,
                  result as? Bool == true,
                  isCurrent(),
                  self.desiredResolution == resolution else { return }
            self.appliedResolution = resolution
        }
    }
}
