import Foundation
import ScholiumContracts

enum ResearchAgentPermissionClaim: Identifiable, Hashable {
    case writeSetExtension(ResearchWriteSetExtensionRecord)
    case continuation(ResearchContinuationRequestRecord)

    var id: UUID {
        switch self {
        case .writeSetExtension(let record): record.id
        case .continuation(let record): record.id
        }
    }

    var triptychID: UUID {
        switch self {
        case .writeSetExtension(let record): record.triptychID
        case .continuation(let record): record.triptychID
        }
    }

    var receivedAt: Date {
        switch self {
        case .writeSetExtension(let record): record.receivedAt
        case .continuation(let record): record.receivedAt
        }
    }

    var expiresAt: Date {
        switch self {
        case .writeSetExtension(let record): record.expiresAt
        case .continuation(let record): record.expiresAt
        }
    }

    var isUnresolved: Bool {
        switch self {
        case .writeSetExtension(let record): record.isUnresolved
        case .continuation(let record): record.state == .pending
        }
    }
}

/// Routes one pending Agent permission decision to at most one matching
/// workspace window. Application remains the validation and durable-decision
/// owner; this object owns only App presentation claims.
@MainActor
final class ResearchAgentPermissionClaimCoordinator {
    enum DeliveryIntent {
        case submit
        case refresh
        case decision
    }

    struct WindowEndpoint {
        let id: UUID
        let triptychID: @MainActor () -> UUID?
        let isKeyWindow: @MainActor () -> Bool
        let canPresent: @MainActor () -> Bool
        let present: @MainActor (ResearchAgentPermissionClaim) -> Void
        let update: @MainActor (ResearchAgentPermissionClaim) -> Void
        let dismiss: @MainActor (UUID) -> Void
        let focus: @MainActor (UUID) -> Void
    }

    private var windows: [UUID: WindowEndpoint] = [:]
    private var activationOrder: [UUID: UInt64] = [:]
    private var nextActivation: UInt64 = 0
    private var records: [UUID: ResearchAgentPermissionClaim] = [:]
    private var claims: [UUID: UUID] = [:]

    func register(_ endpoint: WindowEndpoint) {
        windows[endpoint.id] = endpoint
        noteWindowActivated(endpoint.id)
        presentWaitingRequests()
    }

    func unregister(windowID: UUID) {
        windows[windowID] = nil
        activationOrder[windowID] = nil
        for requestID in claims.compactMap({ key, value in
            value == windowID ? key : nil
        }) {
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
        _ record: ResearchAgentPermissionClaim,
        intent: DeliveryIntent
    ) {
        records[record.id] = record
        if let windowID = claims[record.id], let endpoint = windows[windowID] {
            endpoint.update(record)
            if !record.isUnresolved {
                endpoint.dismiss(record.id)
                claims[record.id] = nil
                records[record.id] = nil
            }
            return
        }
        claims[record.id] = nil
        guard record.isUnresolved else {
            records[record.id] = nil
            return
        }
        guard intent == .submit || intent == .refresh else { return }
        present(record)
    }

    func presentationBecameAvailable(windowID: UUID) {
        presentWaitingRequests(preferredWindowID: windowID)
    }

    func presentationDidDismiss(requestID: UUID, windowID: UUID) {
        guard claims[requestID] == windowID else { return }
        claims[requestID] = nil
        if records[requestID]?.isUnresolved != true {
            records[requestID] = nil
        }
    }

    private func presentWaitingRequests(preferredWindowID: UUID? = nil) {
        for record in records.values.sorted(by: {
            $0.receivedAt == $1.receivedAt
                ? $0.id.uuidString < $1.id.uuidString
                : $0.receivedAt < $1.receivedAt
        }) where record.isUnresolved && claims[record.id] == nil {
            guard Date() < record.expiresAt else {
                records[record.id] = nil
                continue
            }
            present(record, preferredWindowID: preferredWindowID)
        }
    }

    private func present(
        _ record: ResearchAgentPermissionClaim,
        preferredWindowID: UUID? = nil
    ) {
        let matching = windows.values.filter {
            $0.triptychID() == record.triptychID && $0.canPresent()
        }
        guard let endpoint = matching.max(by: { lhs, rhs in
            priority(lhs, preferredWindowID) < priority(rhs, preferredWindowID)
        }) else { return }
        claims[record.id] = endpoint.id
        endpoint.present(record)
        endpoint.focus(record.id)
    }

    private func priority(
        _ endpoint: WindowEndpoint,
        _ preferredWindowID: UUID?
    ) -> (Int, Int, UInt64, String) {
        (
            endpoint.isKeyWindow() ? 1 : 0,
            endpoint.id == preferredWindowID ? 1 : 0,
            activationOrder[endpoint.id] ?? 0,
            endpoint.id.uuidString
        )
    }
}
