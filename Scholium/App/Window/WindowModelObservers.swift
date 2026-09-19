import Foundation
import ScholiumContracts

/// Observation plumbing for `WindowModel`. Combine may synchronously replay a
/// current value while a subscription is installed, so the transforms and the
/// deliveries a subscription installs stay outside the @MainActor model.

final class WindowModelObserverRelay: @unchecked Sendable {
    weak var model: WindowModel?

    init(model: WindowModel) {
        self.model = model
    }
}

// Combine may synchronously replay the current @Published value while a
// subscription is installed. Keep this transform outside the @MainActor
// WindowModel method so that replay does not perform an invalid executor
// check before the window has finished constructing.
func nonisolatedWorkspaceActivation(
    _ activation: WorkspaceActivation?
) -> WorkspaceActivation? {
    activation
}

func nonisolatedWorkspaceAssignmentID(
    _ state: WindowWorkspaceSessionState
) -> UUID? {
    state.assignment?.id
}

func nonisolatedDiscardPublisherValue<Value>(_ _: Value) {}

func deliverWorkspaceActivation(
    _ activation: WorkspaceActivation,
    to model: WindowModel?
) {
    Task { @MainActor in
        model?.adoptWorkspaceActivation(activation)
    }
}

func deliverWorkspaceEvents(
    _ events: [UUID: WorkspaceEvent],
    to model: WindowModel?
) {
    Task { @MainActor in
        model?.receiveWorkspaceEvents(events)
    }
}

func deliverConfirmedAgentChange(
    _ change: AgentChange,
    to model: WindowModel?
) {
    Task { @MainActor in
        guard model?.workspaceAssignment?.id == change.triptychID else { return }
        model?.researchController.scheduleAgentChangesRefresh()
    }
}

func deliverWindowSessionPersistence(to model: WindowModel?) {
    Task { @MainActor in
        model?.persistWindowSessionNow()
    }
}
