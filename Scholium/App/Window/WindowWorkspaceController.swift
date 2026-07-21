import Foundation
import ScholiumApplication
import ScholiumContracts

enum WindowWorkspaceResolution {
    case unavailable(assignments: [TriptychAssignment], message: String?)
    case selected(
        assignments: [TriptychAssignment],
        assignment: TriptychAssignment,
        identityRepairFailure: String?
    )
}

/// Resolves one window's requested Triptych and stable vault identities. The
/// WindowModel remains the composition root that installs the returned
/// Application capabilities and routes presentation effects.
@MainActor
final class WindowWorkspaceController {
    private let workspaceStore: WorkspaceStore
    private let requestedTriptychID: UUID?

    init(workspaceStore: WorkspaceStore, requestedTriptychID: UUID?) {
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
    }

    func resolveAssignment(
        preferredTriptychID: UUID?,
        currentTriptychID: UUID?
    ) async -> WindowWorkspaceResolution {
        let assignments: [TriptychAssignment]
        do {
            assignments = try await workspaceStore.registeredTriptychs()
        } catch {
            return .unavailable(assignments: [], message: error.localizedDescription)
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
