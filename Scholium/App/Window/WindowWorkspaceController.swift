import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

enum WindowWorkspaceResolution {
    case unavailable(assignments: [TriptychAssignment], message: String?)
    case unavailablePreserving(
        assignments: [TriptychAssignment],
        assignment: TriptychAssignment,
        message: String?
    )
    case selected(
        assignments: [TriptychAssignment],
        assignment: TriptychAssignment,
        identityRepairFailure: String?
    )
}

struct WindowWorkspaceSessionState {
    var assignment: TriptychAssignment?
    var registeredTriptychs: [TriptychAssignment] = []
    var recoveryMessage: String?
    var accessRecovery: WorkspaceAccessRecovery?
    var activeServicesID: UUID?
}

/// Owns one window's Triptych assignment and capability-session state.
/// `WindowModel` remains the composition root that installs capabilities into
/// feature controllers and routes cross-feature presentation effects.
@MainActor
final class WindowWorkspaceController: ObservableObject {
    @Published private(set) var state = WindowWorkspaceSessionState()

    private let workspaceStore: WorkspaceStore
    let requestedTriptychID: UUID?
    private(set) var activeCapabilities: WindowWorkspaceCapabilities?

    init(workspaceStore: WorkspaceStore, requestedTriptychID: UUID?) {
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
    }

    func setAssignment(_ assignment: TriptychAssignment?) {
        state.assignment = assignment
    }

    func setRegisteredTriptychs(_ assignments: [TriptychAssignment]) {
        state.registeredTriptychs = assignments
    }

    func setRecoveryMessage(_ message: String?) {
        state.recoveryMessage = message
    }

    func setAccessRecovery(_ recovery: WorkspaceAccessRecovery?) {
        state.accessRecovery = recovery
    }

    func setActiveServicesID(_ id: UUID?) {
        state.activeServicesID = id
    }

    func setActiveCapabilities(_ capabilities: WindowWorkspaceCapabilities?) {
        activeCapabilities = capabilities
    }

    func resolveAssignment(
        preferredTriptychID: UUID?,
        currentTriptychID: UUID?
    ) async -> WindowWorkspaceResolution {
        let assignments: [TriptychAssignment]
        do {
            assignments = try await workspaceStore.registeredTriptychs()
        } catch {
            if let assignment = state.assignment {
                return .unavailablePreserving(
                    assignments: state.registeredTriptychs,
                    assignment: assignment,
                    message: error.localizedDescription
                )
            }
            return .unavailable(
                assignments: state.registeredTriptychs,
                message: error.localizedDescription
            )
        }

        let selectedID = preferredTriptychID ?? currentTriptychID ?? requestedTriptychID
        let stored: TriptychAssignment?
        if let selectedID {
            stored = assignments.first { $0.id == selectedID }
            guard stored != nil else {
                return .unavailable(
                    assignments: assignments,
                    message: "This Triptych is no longer registered on this Mac. Open an existing Triptych or choose its three folders again."
                )
            }
        } else {
            stored = try? await workspaceStore.defaultTriptych()
        }
        guard let stored else {
            return .unavailable(assignments: assignments, message: nil)
        }

        do {
            let repaired = try await workspaceStore.reconcileTriptychIdentity(id: stored.id)
            let refreshed = repaired == stored
                ? assignments
                : ((try? await workspaceStore.registeredTriptychs()) ?? assignments)
            return .selected(
                assignments: refreshed,
                assignment: repaired,
                identityRepairFailure: nil
            )
        } catch {
            return .selected(
                assignments: assignments,
                assignment: stored,
                identityRepairFailure: error.localizedDescription
            )
        }
    }
}
