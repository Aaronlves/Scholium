import Foundation
import ScholiumContracts

/// Application-owned read-only graph query semantics shared by delivery
/// adapters. The immutable graph remains derived state; these queries grant no
/// source or relationship authority.
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

    func relationships(for note: VaultQualifiedNoteID) throws -> [RelationshipEdge] {
        let graph = try requiredGraph(containing: [note])
        return graph.relationships.filter { relationship in
            relationship.subjectNote == note
                || relationship.objectNote == note
                || relationship.occurrences.contains { $0.sourceNote == note }
        }
    }

    func diagnostics() throws -> [LinkGraphDiagnostic] {
        guard let graph else { throw WorkspaceGraphQueryError.graphUnavailable }
        return graph.diagnostics
    }

    func traceLinks(
        from source: VaultQualifiedNoteID,
        to target: VaultQualifiedNoteID,
        maximumDepth: Int
    ) throws -> [[LinkGraphEdge]] {
        let graph = try requiredGraph(
            containing: [source, target],
            maximumDepth: maximumDepth
        )
        var results: [[LinkGraphEdge]] = []
        var queue: [(VaultQualifiedNoteID, [LinkGraphEdge], Set<VaultQualifiedNoteID>)] = [
            (source, [], [source]),
        ]
        var cursor = 0
        while cursor < queue.count {
            let (current, path, visited) = queue[cursor]
            cursor += 1
            guard path.count < maximumDepth else { continue }
            for edge in graph.outgoing[current] ?? [] {
                guard let next = edge.destination?.note,
                      !visited.contains(next) else { continue }
                let nextPath = path + [edge]
                if next == target {
                    results.append(nextPath)
                } else {
                    queue.append((next, nextPath, visited.union([next])))
                }
            }
        }
        return try results.map { path in
            (path: path, key: try encodedSortKey(path))
        }.sorted {
            if $0.path.count != $1.path.count {
                return $0.path.count < $1.path.count
            }
            return $0.key.lexicographicallyPrecedes($1.key)
        }.map(\.path)
    }

    func traceRelationships(
        from source: VaultQualifiedNoteID,
        to target: VaultQualifiedNoteID,
        maximumDepth: Int
    ) throws -> [RelationshipTrace] {
        let graph = try requiredGraph(
            containing: [source, target],
            maximumDepth: maximumDepth
        )
        var results: [RelationshipTrace] = []
        var queue: [(VaultQualifiedNoteID, [RelationshipEdge], Set<VaultQualifiedNoteID>)] = [
            (source, [], [source]),
        ]
        var cursor = 0
        while cursor < queue.count {
            let (current, path, visited) = queue[cursor]
            cursor += 1
            if current == target, !path.isEmpty {
                results.append(RelationshipTrace(edges: path))
                continue
            }
            guard path.count < maximumDepth else { continue }
            let next = graph.relationships.compactMap {
                relationship -> (VaultQualifiedNoteID, RelationshipEdge)? in
                guard case .resolved = relationship.resolution else { return nil }
                if relationship.subjectNote == current,
                   let destination = relationship.objectNote {
                    return (destination, relationship)
                }
                if !relationship.isDirectional,
                   relationship.objectNote == current,
                   let destination = relationship.subjectNote {
                    return (destination, relationship)
                }
                return nil
            }.sorted {
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            for (destination, relationship) in next
                where !visited.contains(destination) {
                queue.append((
                    destination,
                    path + [relationship],
                    visited.union([destination])
                ))
            }
        }
        return try results.map { trace in
            (trace: trace, key: try encodedSortKey(trace.edges))
        }.sorted {
            if $0.trace.edges.count != $1.trace.edges.count {
                return $0.trace.edges.count < $1.trace.edges.count
            }
            return $0.key.lexicographicallyPrecedes($1.key)
        }.map(\.trace)
    }

    private func requiredGraph(
        containing requiredNotes: Set<VaultQualifiedNoteID>,
        maximumDepth: Int? = nil
    ) throws -> GraphSnapshot {
        if let maximumDepth, !(1 ... 10).contains(maximumDepth) {
            throw WorkspaceGraphQueryError.invalidMaximumDepth(maximumDepth)
        }
        for note in requiredNotes where !noteIDs.contains(note) {
            throw WorkspaceGraphQueryError.noteNotFound(note)
        }
        guard let graph else { throw WorkspaceGraphQueryError.graphUnavailable }
        return graph
    }

    private func encodedSortKey(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
