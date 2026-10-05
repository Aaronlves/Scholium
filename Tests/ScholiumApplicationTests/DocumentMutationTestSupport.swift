import ScholiumContracts
import Testing

@testable import ScholiumApplication

func capturedSaveTarget(
    _ handle: WorkspaceHandle,
    _ id: VaultQualifiedNoteID,
    revision: DocumentFingerprint
) async throws -> NoteMutationTarget {
    let snapshot = try await handle.snapshot()
    let identity = try #require(snapshot.document(id: id)?.stableIdentity.resolvedID)
    return NoteMutationTarget(documentID: id, stableNoteID: identity, revision: revision)
}
