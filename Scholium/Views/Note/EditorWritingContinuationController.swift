import Foundation

/// Owns one transient continuation request, never the editor's source or identity.
/// The page bridge supplies admission again at every asynchronous publication.
@MainActor
final class EditorWritingContinuationController {
    enum Publication: Equatable {
        case status(EditorWritingContinuationStatus)
        case result(EditorWritingContinuationResult)
    }

    private(set) var requestID: String?
    private(set) var editorCaret: Int?
    private var operationID: UUID?
    private var task: Task<Void, Never>?

    @discardableResult
    func start(
        requestID: String,
        sourceCaret: Int,
        editorCaret: Int,
        query: @escaping EditorWritingContinuationQuery,
        isCurrent: @escaping @MainActor () -> Bool,
        publish: @escaping @MainActor (Publication) async -> Void
    ) -> Task<Void, Never> {
        cancel()
        let operationID = UUID()
        self.operationID = operationID
        self.requestID = requestID
        self.editorCaret = editorCaret
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.operationID == operationID {
                    self.task = nil
                    self.operationID = nil
                    self.requestID = nil
                    self.editorCaret = nil
                }
            }
            let result = await query(sourceCaret) { [weak self] status in
                guard !Task.isCancelled,
                    self?.operationID == operationID, isCurrent()
                else { return }
                Task { @MainActor [weak self] in
                    guard !Task.isCancelled,
                        self?.operationID == operationID, isCurrent()
                    else { return }
                    await publish(.status(status))
                }
            }
            guard !Task.isCancelled,
                self.operationID == operationID, isCurrent()
            else { return }
            await publish(.result(result))
        }
        self.task = task
        return task
    }

    func cancel() {
        task?.cancel()
        task = nil
        operationID = nil
        requestID = nil
        editorCaret = nil
    }
}
