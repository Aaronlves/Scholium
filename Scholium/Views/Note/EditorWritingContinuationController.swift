import Foundation
import OSLog

/// Owns one transient continuation request, never the editor's source or identity.
/// The page bridge supplies admission again at every asynchronous publication.
@MainActor
final class EditorWritingContinuationController {
    enum Publication: Equatable {
        case status(EditorWritingContinuationStatus)
        case result(EditorWritingContinuationResult)
    }

    enum CancellationReason: String {
        case superseded, configuration, document, mode, detached, inactive, interaction, source, bridge, citation, renderer
    }

    private static let logger = Logger(subsystem: "com.scholium.app", category: "WritingContinuation")

    // Only opaque UUIDs and code-owned stages/reasons cross this diagnostic
    // boundary. Never log source, suggestions, note identity or raw errors.
    static func trace(_ stage: String, requestID: String?, detail: String = "") {
        let identity = requestID.flatMap(UUID.init(uuidString:))?.uuidString ?? "unidentified"
        logger.notice("Continuation stage=\(stage, privacy: .public) request=\(identity, privacy: .public) detail=\(detail, privacy: .public)")
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
        Self.trace("admitted", requestID: requestID)
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
                    Self.trace("progress", requestID: requestID, detail: status.rawValue)
                    await publish(.status(status))
                }
            }
            let outcome: String
            switch result {
            case .suggestion: outcome = "suggestion"
            case .unavailable(let reason): outcome = reason?.rawValue ?? "noCandidate"
            }
            Self.trace("queryResult", requestID: requestID, detail: outcome)
            guard !Task.isCancelled, self.operationID == operationID else {
                Self.trace("discarded", requestID: requestID, detail: "cancelledOrSuperseded")
                return
            }
            guard isCurrent() else {
                Self.trace("discarded", requestID: requestID, detail: "publicationGate")
                return
            }
            await publish(.result(result))
        }
        self.task = task
        return task
    }

    func cancel(reason: CancellationReason = .superseded) {
        if requestID != nil { Self.trace("cancelled", requestID: requestID, detail: reason.rawValue) }
        task?.cancel()
        task = nil
        operationID = nil
        requestID = nil
        editorCaret = nil
    }
}
