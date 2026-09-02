import Foundation
import ScholiumContracts

/// Application-owned read-only graph query semantics shared by delivery
/// adapters. The immutable graph remains derived state; these queries grant no
/// source authority.
struct WorkspaceGraphQueries: Sendable {
    let noteIDs: Set<VaultQualifiedNoteID>
    let graph: GraphSnapshot?

    init(catalog: WorkspaceCatalogSnapshot) {
        noteIDs = Set(catalog.notes.map {
            VaultQualifiedNoteID(
                vaultID: $0.reference.vaultID,
                relativePath: $0.reference.relativePath
            )
        })
        graph = catalog.graph
    }

    init(noteIDs: Set<VaultQualifiedNoteID>, graph: GraphSnapshot?) {
        self.noteIDs = noteIDs
        self.graph = graph
    }

    func links(
        for note: VaultQualifiedNoteID,
        direction: WorkspaceLinkDirection
    ) throws -> [LinkGraphEdge] {
        let graph = try requiredGraph(containing: [note])
        return switch direction {
        case .incoming: graph.incoming[note] ?? []
        case .outgoing: graph.outgoing[note] ?? []
        }
    }

    func diagnostics() throws -> [LinkGraphDiagnostic] {
        guard let graph else { throw WorkspaceGraphQueryError.graphUnavailable }
        return graph.diagnostics
    }

    private func requiredGraph(
        containing requiredNotes: Set<VaultQualifiedNoteID>
    ) throws -> GraphSnapshot {
        for note in requiredNotes where !noteIDs.contains(note) {
            throw WorkspaceGraphQueryError.noteNotFound(note)
        }
        guard let graph else { throw WorkspaceGraphQueryError.graphUnavailable }
        return graph
    }
}
