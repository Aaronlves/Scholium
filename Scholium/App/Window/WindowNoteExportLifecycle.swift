import Combine
import Foundation
import ScholiumContracts

struct WindowNoteExportPayload {
    let document: NoteDocument
    let title: String
    let embeddedImages: [String: RenderedMarkdownImage]
    let excludedRoots: [URL]
    let appearance: DocumentAppearanceSettings
    let colorScheme: WindowColorSchemeChoice
}

@MainActor
protocol WindowNoteExportPresentation: AnyObject {
    func close()
}

/// Owns preparation and its auxiliary presentation for one originating window.
/// Committed close is terminal; late acquisition cannot publish or report errors.
@MainActor
final class WindowNoteExportLifecycle: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing(UUID)
        case presented(UUID)
        case closed
    }

    @Published private(set) var phase: Phase = .idle
    private(set) var presentation: (any WindowNoteExportPresentation)?
    private var task: Task<Void, Never>?

    var isPreparing: Bool {
        if case .preparing = phase { return true }
        return false
    }

    @discardableResult
    func prepare(
        acquire: @escaping @MainActor () async throws -> WindowNoteExportPayload,
        isCurrent: @escaping @MainActor () -> Bool,
        publish:
            @escaping @MainActor (
                WindowNoteExportPayload, @escaping @MainActor () -> Void
            ) -> any WindowNoteExportPresentation,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) -> Bool {
        guard phase == .idle, isCurrent() else { return false }
        let id = UUID()
        phase = .preparing(id)
        task = Task { @MainActor [weak self] in
            guard self?.phase == .preparing(id), !Task.isCancelled else { return }
            do {
                let payload = try await acquire()
                guard let self, self.phase == .preparing(id) else { return }
                guard !Task.isCancelled, isCurrent() else {
                    self.finishPreparation(id)
                    return
                }
                let presentation = publish(payload) { [weak self] in
                    self?.presentationDidClose(id)
                }
                guard self.phase == .preparing(id), !Task.isCancelled, isCurrent() else {
                    presentation.close()
                    self.finishPreparation(id)
                    return
                }
                self.task = nil
                self.presentation = presentation
                self.phase = .presented(id)
            } catch {
                guard let self, self.phase == .preparing(id) else { return }
                let shouldReport = !(error is CancellationError) && !Task.isCancelled && isCurrent()
                self.finishPreparation(id)
                if shouldReport { onFailure(error) }
            }
        }
        return true
    }

    /// Invalidates the current request before cancellation/close callbacks run.
    /// A later request gets a different identity and owns its own cleanup.
    func cancel() {
        guard phase != .closed else { return }
        invalidate(to: .idle)
    }

    func close() {
        guard phase != .closed else { return }
        invalidate(to: .closed)
    }

    private func invalidate(to phase: Phase) {
        let task = task
        let presentation = presentation
        self.task = nil
        self.presentation = nil
        self.phase = phase
        task?.cancel()
        presentation?.close()
    }

    private func finishPreparation(_ id: UUID) {
        guard phase == .preparing(id) else { return }
        task = nil
        phase = .idle
    }

    private func presentationDidClose(_ id: UUID) {
        guard phase == .preparing(id) || phase == .presented(id) else { return }
        let task = task
        self.task = nil
        presentation = nil
        phase = .idle
        task?.cancel()
    }

    deinit {
        task?.cancel()
    }
}
