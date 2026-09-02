import ScholiumContracts
import Foundation
import ScholiumCore

/// A bounded, cancellation-aware stream of typed workspace generations.
public actor WorkspaceEventSource {
    private var currentSnapshot: WorkspaceSnapshot
    private var generation: UInt64 = 0
    private var continuations: [UUID: AsyncStream<WorkspaceEvent>.Continuation] = [:]
    private var vaultAccessInvalidation: WorkspaceVaultAccessInvalidatedEvent?
    private var isFinished = false

    init(initialSnapshot: WorkspaceSnapshot) {
        currentSnapshot = initialSnapshot
    }

    /// The first element is always the latest snapshot. During progressive
    /// live opening that may be one explicitly phased usable-vault snapshot;
    /// slow subscribers still retain only the newest generation.
    public func events() -> AsyncStream<WorkspaceEvent> {
        let pair = AsyncStream<WorkspaceEvent>.makeStream(
            // Every event carries the resulting latest snapshot. A slow
            // subscriber therefore needs only the newest generation and can
            // resynchronize without replaying obsolete intermediate work.
            bufferingPolicy: .bufferingNewest(1)
        )
        if let vaultAccessInvalidation {
            pair.continuation.yield(.vaultAccessInvalidated(vaultAccessInvalidation))
        } else {
            pair.continuation.yield(.snapshot(WorkspaceSnapshotEvent(
                generation: generation,
                snapshot: currentSnapshot
            )))
        }
        guard !isFinished else {
            pair.continuation.finish()
            return pair.stream
        }

        let id = UUID()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }
        return pair.stream
    }

    func publishSourceCommitted(
        snapshot: WorkspaceSnapshot,
        note: WorkspaceNoteSnapshot,
        kind: WorkspaceSourceCommitKind
    ) {
        publish(.sourceCommitted(WorkspaceSourceCommittedEvent(
            generation: nextGeneration(),
            note: note,
            kind: kind,
            snapshot: snapshot
        )), snapshot: snapshot)
    }

    func publishInventoryChanged(
        snapshot: WorkspaceSnapshot,
        added: Set<VaultQualifiedNoteID>,
        removed: Set<VaultQualifiedNoteID>,
        changed: Set<VaultQualifiedNoteID>,
        moved: [WorkspaceNoteMove]
    ) {
        publish(.inventoryChanged(WorkspaceInventoryChangedEvent(
            generation: nextGeneration(),
            added: added,
            removed: removed,
            changed: changed,
            moved: moved,
            snapshot: snapshot
        )), snapshot: snapshot)
    }

    func publishDerivedStateChanged(
        snapshot: WorkspaceSnapshot,
        status: WorkspaceDerivedRefreshStatus? = nil
    ) {
        let resolvedStatus = status ?? (snapshot.phase.isComplete
            ? .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot))
            : .opening(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)))
        publish(.derivedStateChanged(WorkspaceDerivedStateChangedEvent(
            generation: nextGeneration(),
            status: resolvedStatus,
            discovery: snapshot.discovery,
            snapshot: snapshot
        )), snapshot: snapshot)
    }

    func publishResearchStateChanged(snapshot: WorkspaceSnapshot) {
        publish(.researchStateChanged(WorkspaceResearchStateChangedEvent(
            generation: nextGeneration(),
            research: snapshot.research,
            snapshot: snapshot
        )), snapshot: snapshot)
    }

    func publishResearchConfigurationInvalidated(snapshot: WorkspaceSnapshot) {
        publish(.researchConfigurationInvalidated(
            WorkspaceResearchConfigurationInvalidatedEvent(
                generation: nextGeneration(),
                snapshot: snapshot
            )
        ), snapshot: snapshot)
    }

    func publishVaultAccessInvalidated(
        snapshot: WorkspaceSnapshot,
        unavailableVaultPaths: [UUID: String]
    ) {
        let event = WorkspaceVaultAccessInvalidatedEvent(
            generation: nextGeneration(),
            unavailableVaultPaths: unavailableVaultPaths,
            snapshot: snapshot
        )
        vaultAccessInvalidation = event
        publish(
            .vaultAccessInvalidated(event),
            snapshot: snapshot,
            allowedDuringVaultAccessInvalidation: true
        )
    }

    func publishRuntimeReloaded(
        runtimeIdentity: TriptychRuntimeIdentity,
        snapshot: WorkspaceSnapshot
    ) {
        publish(.runtimeReloaded(WorkspaceRuntimeReloadedEvent(
            generation: nextGeneration(),
            runtimeIdentity: runtimeIdentity,
            snapshot: snapshot
        )), snapshot: snapshot, allowedDuringVaultAccessInvalidation: true)
    }

    func finish(finalSnapshot: WorkspaceSnapshot) {
        guard !isFinished else { return }
        isFinished = true
        currentSnapshot = finalSnapshot
        let active = continuations.values
        continuations.removeAll()
        for continuation in active {
            continuation.finish()
        }
    }

    private func nextGeneration() -> UInt64 {
        precondition(generation < .max, "Workspace event generation exhausted")
        generation += 1
        return generation
    }

    private func publish(
        _ event: WorkspaceEvent,
        snapshot: WorkspaceSnapshot,
        allowedDuringVaultAccessInvalidation: Bool = false
    ) {
        guard !isFinished,
              allowedDuringVaultAccessInvalidation || vaultAccessInvalidation == nil else {
            return
        }
        currentSnapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // Internal test evidence for cancellation cleanup; not application API.
    var subscriberCount: Int { continuations.count }
    var publishedGeneration: UInt64 { generation }
}
