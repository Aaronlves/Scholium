import Foundation
import Testing
@testable import ScholiumApplication
@testable import ScholiumContracts

@Suite("Application-owned workspace Graph queries")
struct WorkspaceGraphQueriesTests {
    @Test("Incoming and outgoing queries preserve the exact authored occurrence")
    func exactOccurrences() throws {
        let fixture = Fixture()
        let edge = fixture.link(from: fixture.source, to: fixture.target, annotated: true)
        let queries = fixture.queries(edges: [edge])

        #expect(try queries.links(for: fixture.source, direction: .outgoing) == [edge])
        #expect(try queries.links(for: fixture.target, direction: .incoming) == [edge])
        #expect(try #require(queries.links(for: fixture.target, direction: .incoming).first)
            .occurrence.annotation?.markdown == "Authored reason.")
        #expect(throws: WorkspaceGraphQueryError.noteNotFound(fixture.missing)) {
            try queries.links(for: fixture.missing, direction: .outgoing)
        }
    }

}

private extension WorkspaceGraphQueriesTests {
    struct Fixture {
        let vaultID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        var source: VaultQualifiedNoteID { .init(vaultID: vaultID, relativePath: "Source.md") }
        var target: VaultQualifiedNoteID { .init(vaultID: vaultID, relativePath: "Target.md") }
        var missing: VaultQualifiedNoteID { .init(vaultID: vaultID, relativePath: "Missing.md") }

        func queries(edges: [LinkGraphEdge]) -> WorkspaceGraphQueries {
            let notes = Set(edges.flatMap { edge in
                [edge.source] + (edge.destination.map { [$0.note] } ?? [])
            })
            return WorkspaceGraphQueries(
                noteIDs: notes,
                graph: GraphSnapshot(
                    contractVersion: GraphSnapshot.currentContractVersion,
                    generation: 1,
                    sourceManifestHash: "fixture",
                    outgoing: Dictionary(grouping: edges, by: \.source),
                    incoming: Dictionary(grouping: edges.compactMap { edge in
                        edge.destination == nil ? nil : edge
                    }, by: { $0.destination!.note }),
                    diagnostics: []
                )
            )
        }

        func link(
            from source: VaultQualifiedNoteID,
            to destination: VaultQualifiedNoteID,
            annotated: Bool = false
        ) -> LinkGraphEdge {
            let annotation = annotated ? LinkAnnotation(
                markdown: "Authored reason.",
                text: "Authored reason.",
                span: span(utf16LowerBound: 10, utf16UpperBound: 30),
                contentSpan: span(utf16LowerBound: 12, utf16UpperBound: 28)
            ) : nil
            return LinkGraphEdge(
                source: source,
                occurrence: LinkOccurrence(
                    syntax: .wikilink,
                    target: destination.relativePath,
                    alias: nil,
                    fragment: nil,
                    annotation: annotation,
                    localContext: "Context around the authored link.",
                    isExternal: false,
                    span: span(utf16LowerBound: 0, utf16UpperBound: annotated ? 30 : 10),
                    linkSpan: span(utf16LowerBound: 0, utf16UpperBound: 10),
                    resolution: .resolved(destination)
                ),
                destination: LinkDestination(
                    note: destination,
                    kind: .note,
                    fragment: nil,
                    span: nil
                )
            )
        }

        func span(utf16LowerBound: Int, utf16UpperBound: Int) -> SourceSpan {
            SourceSpan(
                utf8LowerBound: utf16LowerBound,
                utf8UpperBound: utf16UpperBound,
                utf16LowerBound: utf16LowerBound,
                utf16UpperBound: utf16UpperBound,
                start: SourcePosition(
                    line: 1,
                    utf8Column: utf16LowerBound + 1,
                    utf16Column: utf16LowerBound + 1
                ),
                end: SourcePosition(
                    line: 1,
                    utf8Column: utf16UpperBound + 1,
                    utf16Column: utf16UpperBound + 1
                )
            )
        }
    }
}
