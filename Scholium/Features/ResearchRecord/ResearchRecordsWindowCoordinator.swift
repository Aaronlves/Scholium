import Foundation
import ScholiumContracts

enum ResearchRecordsViewKind: String, CaseIterable, Codable, Hashable, Sendable {
    case records
    case recommendations
}

enum ResearchRecordsScope: String, CaseIterable, Hashable, Sendable {
    case thisNote
    case triptych
}

/// A one-shot presentation request for the one Research Records window owned
/// by a Triptych. Records remain owned by the portable Research Record store;
/// this value carries only transient routing state.
struct ResearchRecordsWindowRequest: Hashable, Sendable {
    let triptychID: UUID
    let noteID: UUID?
    let initialView: ResearchRecordsViewKind
    let recordID: UUID?
    let expectedRecordFingerprint: DocumentFingerprint?
    let statementID: UUID?

    init(
        triptychID: UUID,
        noteID: UUID? = nil,
        initialView: ResearchRecordsViewKind = .records,
        recordID: UUID? = nil,
        expectedRecordFingerprint: DocumentFingerprint? = nil,
        statementID: UUID? = nil
    ) {
        self.triptychID = triptychID
        self.noteID = noteID
        self.initialView = initialView
        self.recordID = recordID
        self.expectedRecordFingerprint = expectedRecordFingerprint
        self.statementID = statementID
    }
}

/// Routes transient requests to a Triptych-identified Research Records window
/// and to an already-open workspace. It retains no Research Record data.
@MainActor
final class ResearchRecordsWindowCoordinator {
    private struct RecordsEndpoint {
        let token: UUID
        let receive: @MainActor (ResearchRecordsWindowRequest) -> Void
    }

    private struct WorkspaceEndpoint {
        let token: UUID
        let windowID: UUID
        var activationOrdinal: UInt64
        let openNote: @MainActor (
            UUID,
            VaultQualifiedNoteID,
            Int?
        ) -> Void
    }

    private var recordsEndpoints: [UUID: RecordsEndpoint] = [:]
    private var pendingRequests: [UUID: ResearchRecordsWindowRequest] = [:]
    private var workspaceEndpoints: [UUID: [UUID: WorkspaceEndpoint]] = [:]
    private var nextActivationOrdinal: UInt64 = 0

    func submit(_ request: ResearchRecordsWindowRequest) {
        if let endpoint = recordsEndpoints[request.triptychID] {
            endpoint.receive(request)
        } else {
            pendingRequests[request.triptychID] = request
        }
    }

    @discardableResult
    func registerRecordsWindow(
        triptychID: UUID,
        receive: @escaping @MainActor (ResearchRecordsWindowRequest) -> Void
    ) -> UUID {
        let token = UUID()
        recordsEndpoints[triptychID] = RecordsEndpoint(token: token, receive: receive)
        if let pending = pendingRequests.removeValue(forKey: triptychID) {
            receive(pending)
        }
        return token
    }

    func unregisterRecordsWindow(triptychID: UUID, token: UUID) {
        guard recordsEndpoints[triptychID]?.token == token else { return }
        recordsEndpoints[triptychID] = nil
    }

    @discardableResult
    func registerWorkspace(
        triptychID: UUID,
        windowID: UUID,
        openNote: @escaping @MainActor (
            UUID,
            VaultQualifiedNoteID,
            Int?
        ) -> Void
    ) -> UUID {
        let token = UUID()
        nextActivationOrdinal &+= 1
        workspaceEndpoints[triptychID, default: [:]][token] = WorkspaceEndpoint(
            token: token,
            windowID: windowID,
            activationOrdinal: nextActivationOrdinal,
            openNote: openNote
        )
        return token
    }

    func unregisterWorkspace(triptychID: UUID, token: UUID) {
        workspaceEndpoints[triptychID]?[token] = nil
        if workspaceEndpoints[triptychID]?.isEmpty == true {
            workspaceEndpoints[triptychID] = nil
        }
    }

    func workspaceDidActivate(triptychID: UUID, token: UUID) {
        guard var endpoint = workspaceEndpoints[triptychID]?[token] else { return }
        nextActivationOrdinal &+= 1
        endpoint.activationOrdinal = nextActivationOrdinal
        workspaceEndpoints[triptychID]?[token] = endpoint
    }

    /// Returns `true` only after routing to an existing workspace for the same
    /// Triptych. The caller opens a new `TriptychWindowRoute` when this fails.
    func openInExistingWorkspace(
        triptychID: UUID,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        sourceLine: Int? = nil
    ) -> Bool {
        guard let endpoint = workspaceEndpoints[triptychID]?.values.max(by: {
            if $0.activationOrdinal != $1.activationOrdinal {
                return $0.activationOrdinal < $1.activationOrdinal
            }
            return $0.windowID.uuidString > $1.windowID.uuidString
        }) else { return false }
        endpoint.openNote(noteID, note, sourceLine)
        return true
    }
}
