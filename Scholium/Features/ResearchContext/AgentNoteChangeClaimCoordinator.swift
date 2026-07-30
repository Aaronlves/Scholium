import Foundation
import ScholiumContracts

/// One App-wide owner routes each pending Agent request to at most one exact
/// workspace window. It owns presentation claims only; Application remains
/// the owner of validation and durable decisions.
@MainActor
final class AgentNoteChangeClaimCoordinator {
    enum DeliveryIntent {
        case submit
        case showExisting
        case cancel
        case refresh
        case decision
    }

    struct WindowEndpoint {
        let id: UUID
        let triptychID: @MainActor () -> UUID?
        let isKeyWindow: @MainActor () -> Bool
        let canPresent: @MainActor () -> Bool
        let present: @MainActor (AgentNoteChangeRequestRecord) -> Void
        let update: @MainActor (AgentNoteChangeRequestRecord) -> Void
        let dismiss: @MainActor (UUID) -> Void
        let focus: @MainActor (UUID) -> Void
    }

    private var windows: [UUID: WindowEndpoint] = [:]
    private var activationOrder: [UUID: UInt64] = [:]
    private var nextActivation: UInt64 = 0
    private var records: [UUID: AgentNoteChangeRequestRecord] = [:]
    private var claims: [UUID: UUID] = [:]

    func register(_ endpoint: WindowEndpoint) {
        windows[endpoint.id] = endpoint
        noteWindowActivated(endpoint.id)
        presentWaitingRequests()
    }

    func unregister(windowID: UUID) {
        windows[windowID] = nil
        activationOrder[windowID] = nil
        let released = claims.compactMap { requestID, claimedWindowID in
            claimedWindowID == windowID ? requestID : nil
        }
        for requestID in released {
            claims[requestID] = nil
            if records[requestID]?.isUnresolved != true {
                records[requestID] = nil
            }
        }
        presentWaitingRequests()
    }

    func noteWindowActivated(_ windowID: UUID) {
        guard windows[windowID] != nil else { return }
        nextActivation &+= 1
        activationOrder[windowID] = nextActivation
        presentWaitingRequests()
    }

    func receive(
        _ record: AgentNoteChangeRequestRecord,
        intent: DeliveryIntent
    ) {
        let requestID = record.id
        records[requestID] = record

        if let windowID = claims[requestID],
           let endpoint = windows[windowID] {
            endpoint.update(record)
            if intent == .showExisting {
                endpoint.focus(requestID)
            }
            if !record.isUnresolved,
               record.decision.state != .stale,
               record.decision.state != .expired {
                endpoint.dismiss(requestID)
                claims[requestID] = nil
                records[requestID] = nil
            }
            return
        }

        claims[requestID] = nil
        if !record.isUnresolved {
            records[requestID] = nil
            return
        }
        guard intent == .submit || intent == .refresh else { return }
        present(record)
    }

    func presentationBecameAvailable(windowID: UUID) {
        guard windows[windowID] != nil else { return }
        presentWaitingRequests(preferredWindowID: windowID)
    }

    func presentationDidDismiss(requestID: UUID, windowID: UUID) {
        guard claims[requestID] == windowID else { return }
        claims[requestID] = nil
        if records[requestID]?.isUnresolved != true {
            records[requestID] = nil
        }
    }

    func claimedWindowID(for requestID: UUID) -> UUID? {
        claims[requestID]
    }

    private func presentWaitingRequests(preferredWindowID: UUID? = nil) {
        for record in records.values.sorted(by: {
            if $0.receivedAt == $1.receivedAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.receivedAt < $1.receivedAt
        }) where record.isUnresolved && claims[record.id] == nil {
            guard Date() < record.expiresAt else {
                records[record.id] = nil
                continue
            }
            present(record, preferredWindowID: preferredWindowID)
        }
    }

    private func present(
        _ record: AgentNoteChangeRequestRecord,
        preferredWindowID: UUID? = nil
    ) {
        guard Date() < record.expiresAt else {
            records[record.id] = nil
            return
        }
        let matching = windows.values.filter { endpoint in
            endpoint.triptychID() == record.request.triptychID
                && endpoint.canPresent()
        }
        guard let endpoint = matching.max(by: { lhs, rhs in
            priority(of: lhs, preferredWindowID: preferredWindowID)
                < priority(of: rhs, preferredWindowID: preferredWindowID)
        }) else { return }

        claims[record.id] = endpoint.id
        endpoint.present(record)
        endpoint.focus(record.id)
    }

    private func priority(
        of endpoint: WindowEndpoint,
        preferredWindowID: UUID?
    ) -> (Int, Int, UInt64, String) {
        (
            endpoint.isKeyWindow() ? 1 : 0,
            endpoint.id == preferredWindowID ? 1 : 0,
            activationOrder[endpoint.id] ?? 0,
            endpoint.id.uuidString
        )
    }
}
