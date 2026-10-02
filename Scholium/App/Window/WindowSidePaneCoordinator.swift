import Combine
import Foundation

/// Coordinates intents; visibility and persistence remain with the existing
/// PDF and shell owners. A single departure transaction admits the latest click.
@MainActor
final class WindowSidePaneCoordinator: ObservableObject {
    enum Pane: Equatable { case none, pdf, inspector }

    @Published private(set) var isTransitioning = false
    private weak var model: WindowModel?
    private var observations: Set<AnyCancellable> = []
    private var operationID: UUID?
    private var pendingPane: Pane?
    private var pendingIsExplicit = false
    private var lastExplicitChoice: Pane?
    private var task: Task<Void, Never>?
    private var departure: (reader: PDFReaderController, token: UUID)?
    private var isClosed = false

    init(model: WindowModel) {
        self.model = model
        Publishers.Merge(
            model.pdfReaderController.$isVisible.dropFirst().map { _ in () },
            model.shellState.$inspector.dropFirst().map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.reconcileVisibility() }
        .store(in: &observations)
    }

    var pane: Pane {
        guard let model else { return .none }
        if model.pdfReaderController.isVisible { return .pdf }
        return model.shellState.inspector.isVisible ? .inspector : .none
    }

    func setPDFVisible(_ visible: Bool) {
        guard let model, visible || model.pdfReaderController.isVisible else { return }
        request(visible ? .pdf : .none)
    }

    func setInspectorVisible(_ visible: Bool) {
        guard let model, visible || model.shellState.inspector.isVisible else { return }
        request(visible ? .inspector : .none)
    }

    func request(_ requested: Pane) {
        enqueue(requested, explicit: true)
    }

    /// Restoration can deliver the two owners independently. An accepted user
    /// choice wins; otherwise PDF deterministically wins an old both-open pair.
    func reconcileVisibility() {
        guard let model, model.pdfReaderController.isVisible, model.shellState.inspector.isVisible,
            !model.shellState.isFocusLayoutActive
        else { return }
        // A native Focus Layout restoration may reveal Inspector before queued
        // model delivery. Restore the admissible PDF state before attempting a
        // preferred Inspector transition, so a draft/save barrier keeps one pane.
        if let coordinator = model.nativeWindowCoordinator {
            coordinator.applySidePaneInspectorVisibility(false, revealsPane: false)
        } else {
            model.recordResearchInspectorVisibility(false)
        }
        enqueue(lastExplicitChoice ?? .pdf, explicit: false)
    }

    private func enqueue(_ requested: Pane, explicit: Bool) {
        guard let model, allowsRequests(in: model) else { return }
        guard explicit || operationID == nil else { return }
        if explicit {
            guard requested != .pdf || model.currentNote != nil || model.pdfReaderController.isVisible else { return }
            guard requested != .inspector || model.canToggleResearchInspector else { return }
        }
        pendingPane = requested
        pendingIsExplicit = explicit
        if operationID != nil { return }
        let reader = model.pdfReaderController
        guard !reader.isDeparting else {
            pendingPane = nil
            return
        }
        if !reader.isVisible || requested == .pdf {
            pendingPane = nil
            if commit(requested, in: model), explicit { lastExplicitChoice = requested }
            return
        }
        let id = UUID()
        operationID = id
        isTransitioning = true
        departure = (reader, reader.beginDeparture())
        let context = reader.context
        let documentKey = model.currentDocumentDescriptor?.sessionKey
        let windowSessionID = model.windowSessionID
        task = Task { @MainActor [weak self, weak model] in
            guard let self else { return }
            defer {
                if self.operationID == id {
                    self.releaseDeparture()
                    self.operationID = nil
                    self.pendingPane = nil
                    self.task = nil
                    self.isTransitioning = false
                }
            }
            do {
                try Task.checkCancellation()
                guard self.operationID == id, let startingModel = model, self.allowsRequests(in: startingModel),
                    startingModel.pdfReaderController === reader, reader.context == context,
                    startingModel.currentDocumentDescriptor?.sessionKey == documentKey,
                    startingModel.windowSessionID == windowSessionID
                else { return }
                try await reader.flushPersistence()
                try Task.checkCancellation()
                guard self.operationID == id, let model, self.allowsRequests(in: model),
                    model.pdfReaderController === reader, reader.context == context,
                    model.currentDocumentDescriptor?.sessionKey == documentKey,
                    model.windowSessionID == windowSessionID, let latest = self.pendingPane
                else { return }
                // End only our token, then commit without another await. The
                // reader rejects commit if another close/navigation owns a token.
                self.releaseDeparture()
                if self.commit(latest, in: model), self.pendingIsExplicit { self.lastExplicitChoice = latest }
            } catch is CancellationError {
            } catch {
                guard self.operationID == id, let model, reader.context == context else { return }
                if reader.error == nil {
                    model.reportOperationIssue(PDFReaderPresentationError.message(error), kind: .error)
                }
            }
        }
    }

    private func commit(_ requested: Pane, in model: WindowModel) -> Bool {
        guard allowsRequests(in: model),
            !model.shellState.isFocusLayoutActive || requested == .none || model.nativeWindowCoordinator != nil,
            model.pdfReaderController.setVisible(requested == .pdf)
        else { return false }
        if let coordinator = model.nativeWindowCoordinator {
            coordinator.applySidePaneInspectorVisibility(requested == .inspector, revealsPane: requested != .none)
        } else {
            model.recordResearchInspectorVisibility(requested == .inspector)
        }
        model.shellState.recordInspectorVisibilityChoice()
        return true
    }

    private func allowsRequests(in model: WindowModel) -> Bool {
        !isClosed && !model.transferInProgress && !model.windowCloseCoordinator.isPreparingOrFinalized
            && model.nativeWindowCoordinator?.isNativeCloseInProgress != true
            && model.nativeWindowCoordinator?.registry.isTerminationAttemptInProgress != true
            && !model.shellState.isFocusLayoutLockedByFullScreen
    }

    func documentContextWillChange(to context: PDFReaderNoteContext?) {
        if model?.pdfReaderController.context != context { cancelPending() }
    }

    func cancelPending() {
        operationID = nil
        pendingPane = nil
        task?.cancel()
        task = nil
        releaseDeparture()
        isTransitioning = false
    }

    func shutdown() {
        guard !isClosed else { return }
        isClosed = true
        observations.removeAll()
        cancelPending()
    }

    private func releaseDeparture() {
        guard let departure else { return }
        self.departure = nil
        departure.reader.endDeparture(departure.token)
    }
}
