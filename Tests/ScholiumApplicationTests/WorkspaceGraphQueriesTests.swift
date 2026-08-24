import Foundation
import Testing
@testable import ScholiumApplication
@testable import ScholiumContracts

@Suite("Application-owned workspace Graph queries")
struct WorkspaceGraphQueriesTests {
    @Test("Unresolved same-path relationships remain vault-qualified by occurrence")
    func unresolvedSamePathRelationshipsRemainVaultQualified() throws {
        let fixture = Fixture()
        let relationship = RelationshipEdge(
            subjectPath: fixture.samePath,
            predicate: .supports,
            objectPath: "Missing.md",
            locator: fixture.locator(file: fixture.samePath),
            resolution: .broken("Missing.md"),
            isExplicit: true,
            isDirectional: true,
            occurrences: [RelationshipSourceOccurrence(
                sourceNote: fixture.secondSamePath,
                locator: fixture.locator(file: fixture.samePath),
                syntax: .vectorWikilink,
                vectorKind: .supports
            )]
        )
        let queries = fixture.queries(relationships: [relationship])

        #expect(try queries.relationships(for: fixture.firstSamePath).isEmpty)
        #expect(try queries.relationships(for: fixture.secondSamePath) == [relationship])
    }

    @Test("Resolved endpoints and missing notes use exact workspace identity")
    func resolvedEndpointsAndMissingNotesUseExactIdentity() throws {
        let fixture = Fixture()
        let relationship = fixture.relationship(
            from: fixture.firstSamePath,
            to: fixture.target,
            predicate: .supports
        )
        let queries = fixture.queries(relationships: [relationship])

        #expect(try queries.relationships(for: fixture.firstSamePath) == [relationship])
        #expect(try queries.relationships(for: fixture.target) == [relationship])
        #expect(throws: WorkspaceGraphQueryError.noteNotFound(fixture.missing)) {
            try queries.relationships(for: fixture.missing)
        }
    }

    @Test("Link and relationship traces retain bounded multi-hop semantics")
    func tracesRetainBoundedMultiHopSemantics() throws {
        let fixture = Fixture()
        let firstLink = fixture.link(from: fixture.firstSamePath, to: fixture.middle)
        let secondLink = fixture.link(from: fixture.middle, to: fixture.target)
        let firstRelationship = fixture.relationship(
            from: fixture.firstSamePath,
            to: fixture.middle,
            predicate: .supports
        )
        let secondRelationship = fixture.relationship(
            from: fixture.middle,
            to: fixture.target,
            predicate: .refines
        )
        let queries = fixture.queries(
            outgoing: [
                fixture.firstSamePath: [firstLink],
                fixture.middle: [secondLink],
            ],
            relationships: [firstRelationship, secondRelationship]
        )

        let linkPaths = try queries.traceLinks(
            from: fixture.firstSamePath,
            to: fixture.target,
            maximumDepth: 2
        )
        #expect(linkPaths == [[firstLink, secondLink]])

        let relationshipPaths = try queries.traceRelationships(
            from: fixture.firstSamePath,
            to: fixture.target,
            maximumDepth: 2
        )
        #expect(relationshipPaths.count == 1)
        #expect(relationshipPaths.first?.edges == [firstRelationship, secondRelationship])
        #expect(relationshipPaths.first?.classification == .connectionPath)
        #expect(relationshipPaths.first?.assertedPredicate == nil)
        #expect(throws: WorkspaceGraphQueryError.invalidMaximumDepth(11)) {
            try queries.traceLinks(
                from: fixture.firstSamePath,
                to: fixture.target,
                maximumDepth: 11
            )
        }
    }

    @Test("Equal-depth traces use complete path identity for deterministic order")
    func equalDepthTracesHaveDeterministicTotalOrder() throws {
        let fixture = Fixture()
        let commonLink = fixture.link(from: fixture.firstSamePath, to: fixture.middle)
        let linkToA = fixture.link(from: fixture.middle, to: fixture.branchA)
        let linkToB = fixture.link(from: fixture.middle, to: fixture.branchB)
        let aToTarget = fixture.link(from: fixture.branchA, to: fixture.target)
        let bToTarget = fixture.link(from: fixture.branchB, to: fixture.target)
        let commonRelationship = fixture.relationship(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            from: fixture.firstSamePath,
            to: fixture.middle,
            predicate: .supports
        )
        let relationshipToA = fixture.relationship(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            from: fixture.middle,
            to: fixture.branchA,
            predicate: .refines
        )
        let relationshipToB = fixture.relationship(
            id: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            from: fixture.middle,
            to: fixture.branchB,
            predicate: .refines
        )
        let aRelationshipToTarget = fixture.relationship(
            id: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
            from: fixture.branchA,
            to: fixture.target,
            predicate: .supports
        )
        let bRelationshipToTarget = fixture.relationship(
            id: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!,
            from: fixture.branchB,
            to: fixture.target,
            predicate: .supports
        )
        let queries = fixture.queries(
            outgoing: [
                fixture.firstSamePath: [commonLink],
                fixture.middle: [linkToB, linkToA],
                fixture.branchA: [aToTarget],
                fixture.branchB: [bToTarget],
            ],
            relationships: [
                commonRelationship,
                relationshipToB,
                bRelationshipToTarget,
                relationshipToA,
                aRelationshipToTarget,
            ]
        )

        let linkPaths = try queries.traceLinks(
            from: fixture.firstSamePath,
            to: fixture.target,
            maximumDepth: 3
        )
        #expect(linkPaths.count == 2)
        #expect(linkPaths[0][1] == linkToA)
        #expect(linkPaths[1][1] == linkToB)

        let relationshipPaths = try queries.traceRelationships(
            from: fixture.firstSamePath,
            to: fixture.target,
            maximumDepth: 3
        )
        #expect(relationshipPaths.count == 2)
        #expect(relationshipPaths[0].edges[1] == relationshipToA)
        #expect(relationshipPaths[1].edges[1] == relationshipToB)
    }
}

private extension WorkspaceGraphQueriesTests {
    struct Fixture {
        let firstVault = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let secondVault = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let samePath = "Same.md"

        var firstSamePath: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: samePath)
        }

        var secondSamePath: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: secondVault, relativePath: samePath)
        }

        var middle: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Middle.md")
        }

        var target: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Target.md")
        }

        var branchA: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Branch A.md")
        }

        var branchB: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Branch B.md")
        }

        var missing: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Missing.md")
        }

        var noteIDs: Set<VaultQualifiedNoteID> {
            [firstSamePath, secondSamePath, middle, branchA, branchB, target]
        }

        func queries(
            outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]] = [:],
            relationships: [RelationshipEdge]
        ) -> WorkspaceGraphQueries {
            WorkspaceGraphQueries(
                noteIDs: noteIDs,
                graph: GraphSnapshot(
                    contractVersion: GraphSnapshot.currentContractVersion,
                    generation: 1,
                    sourceManifestHash: "fixture",
                    outgoing: outgoing,
                    incoming: [:],
                    diagnostics: [],
                    relationships: relationships
                )
            )
        }

        func relationship(
            id: UUID? = nil,
            from source: VaultQualifiedNoteID,
            to destination: VaultQualifiedNoteID,
            predicate: RelationshipPredicate
        ) -> RelationshipEdge {
            RelationshipEdge(
                id: id,
                subjectNote: source,
                subjectPath: source.relativePath,
                predicate: predicate,
                objectNote: destination,
                objectPath: destination.relativePath,
                locator: locator(file: source.relativePath),
                resolution: .resolved(destination.relativePath),
                isExplicit: true,
                isDirectional: true,
                occurrences: [RelationshipSourceOccurrence(
                    sourceNote: source,
                    locator: locator(file: source.relativePath),
                    syntax: .vectorWikilink,
                    vectorKind: .supports
                )]
            )
        }

        func link(
            from source: VaultQualifiedNoteID,
            to destination: VaultQualifiedNoteID
        ) -> LinkGraphEdge {
            LinkGraphEdge(
                source: source,
                occurrence: LinkOccurrence(
                    syntax: .wikilink,
                    target: destination.relativePath,
                    alias: nil,
                    fragment: nil,
                    relationship: nil,
                    isExternal: false,
                    span: span,
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

        func locator(file: String) -> SourceLocator {
            SourceLocator(file: file, line: 1, column: 1)
        }

        var span: SourceSpan {
            SourceSpan(
                utf8LowerBound: 0,
                utf8UpperBound: 1,
                utf16LowerBound: 0,
                utf16UpperBound: 1,
                start: SourcePosition(line: 1, utf8Column: 1, utf16Column: 1),
                end: SourcePosition(line: 1, utf8Column: 2, utf16Column: 2)
            )
        }
    }
}
