import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Research Record Search projection")
struct ResearchRecordSearchIndexTests {
    @Test("Record fields are ANDed and note aliases resolve to stable historical identities")
    func fieldFiltersAndStableNoteIdentity() throws {
        let fixture = try Fixture()
        let execution = try fixture.search(
            "kind:record note:\"Current Akrasia\" action:synthesize skill:Synthesize participant:researcher date:7d"
        )

        #expect(execution.results.map(\.recordID) == [fixture.pinnedRecordID])
        let result = try #require(execution.results.first)
        #expect(result.actionID == "synthesize")
        #expect(result.methodName == "Synthesize")
        #expect(result.matchedFields.contains(.participant))
    }

    @Test("This Note, This Vault, and Triptych scopes apply before Record clauses")
    func scopeFirstAcrossAllScopes() throws {
        let fixture = try Fixture()
        let thisNote = SearchExecutionScope.currentNote(SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: fixture.analysisVaultID,
                relativePath: "New Akrasia.md"
            ),
            editorSessionID: UUID(),
            source: "# Current Akrasia\n",
            editorRevision: 4
        ))

        let currentNote = try fixture.search(
            "kind:record dialectical",
            scope: thisNote
        )
        let currentVault = try fixture.search(
            "kind:record tombstone-token",
            scope: .currentVault(fixture.analysisVaultID)
        )
        let triptych = try fixture.search(
            "kind:record other-vault-token",
            scope: .triptych
        )

        #expect(currentNote.results.map(\.recordID) == [fixture.pinnedRecordID])
        #expect(currentVault.results.map(\.recordID) == [fixture.tombstoneRecordID])
        #expect(triptych.results.map(\.recordID) == [fixture.otherVaultRecordID])
    }

    @Test("Unfielded clauses search attribution, source, and actually-used material without duplicating a Record")
    func unfieldedAttributionMaterialsAndOneRow() throws {
        let fixture = try Fixture()

        let andQuery = try fixture.search(
            "kind:record dialectical \"Aristotle Source\""
        )
        let attribution = try fixture.search(
            "kind:record \"Professor Imna\""
        )
        let used = try fixture.search("kind:record \"Used Treatise\"")
        let selectedOnly = try fixture.search("kind:record \"Selected Appendix\"")
        let repeated = try fixture.search("kind:record shared-token")

        #expect(andQuery.results.map(\.recordID) == [fixture.pinnedRecordID])
        #expect(andQuery.results[0].matchedFields.contains(.sourceReference))
        #expect(attribution.results[0].statementAuthor == .researcher)
        #expect(attribution.results[0].statementID == fixture.researcherStatementID)
        #expect(used.results[0].matchedFields.contains(.material))
        #expect(!selectedOnly.results[0].matchedFields.contains(.material))
        #expect(repeated.results.map(\.recordID) == [fixture.pinnedRecordID])
    }

    @Test("Local calendar windows, pinned ordering, manifest generation, and exact fingerprints are deterministic")
    func dateOrderingAndFreshness() throws {
        let fixture = try Fixture()
        let execution = try fixture.search("kind:record date:7d sortable")

        #expect(execution.results.map(\.recordID) == [
            fixture.pinnedRecordID,
            fixture.todayRecordID,
        ])
        #expect(execution.generation.sourceManifestHash == fixture.manifestHash)
        #expect(execution.results[0].fingerprint == fixture.fingerprints[
            fixture.pinnedRecordID
        ])
        #expect(execution.results.allSatisfy {
            $0.freshnessToken == .record(execution.generation)
        })
        #expect(execution.availability == .current(execution.generation))
    }

    @Test("Ambiguous Note identities and incomplete Record corpora fail closed")
    func ambiguityAndIncompleteCorpus() throws {
        let fixture = try Fixture()
        let ambiguous = try fixture.search("kind:record note:\"Shared\"")
        let incomplete = ResearchRecordSearchIndex(
            triptychID: fixture.triptychID,
            research: fixture.researchSnapshot(
                records: fixture.records,
                fingerprints: fixture.fingerprints,
                isComplete: false
            ),
            catalogNotes: fixture.catalogNotes
        )
        let unavailable = try incomplete.search(
            ast: try fixture.ast("kind:record"),
            scope: .triptych,
            limit: 100,
            now: fixture.now,
            calendar: fixture.calendar
        )

        #expect(ambiguous.results.isEmpty)
        #expect(ambiguous.diagnostics.map(\.code) == [.ambiguousIdentity])
        #expect(unavailable.results.isEmpty)
        #expect(unavailable.diagnostics.map(\.code) == [.notApplicable])
        if case .failed(let lastGood, _) = unavailable.availability {
            #expect(lastGood == nil)
        } else {
            Issue.record("An incomplete portable Record corpus did not fail closed.")
        }
    }
}

private extension ResearchRecordSearchIndexTests {
    struct Fixture {
        let triptychID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let analysisVaultID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let topicVaultID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let alphaNoteID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let pinnedRecordID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let todayRecordID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
        let tombstoneRecordID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
        let otherVaultRecordID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let researcherStatementID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
        let manifestHash = "exact-record-manifest-v1"
        let calendar: Calendar
        let now: Date
        let records: [PortableResearchRecord]
        let fingerprints: [UUID: DocumentFingerprint]
        let catalogNotes: [WorkspaceCatalogNote]

        init() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            self.calendar = calendar
            now = calendar.date(from: DateComponents(
                year: 2026,
                month: 8,
                day: 4,
                hour: 12
            ))!

            let alpha = try Self.note(
                id: alphaNoteID,
                vaultID: analysisVaultID,
                path: "Old Akrasia.md",
                role: .analysis,
                title: "Historical Akrasia"
            )
            let used = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                vaultID: topicVaultID,
                path: "Used Treatise.md",
                role: .topic,
                title: "Used Treatise"
            )
            let selectedOnly = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                vaultID: topicVaultID,
                path: "Selected Appendix.md",
                role: .topic,
                title: "Selected Appendix"
            )
            let pinnedFinished = calendar.date(byAdding: .day, value: -2, to: now)!
            let researcherStatement = try PortableResearchStatement(
                id: researcherStatementID,
                author: .researcher,
                kind: .researcherResponse,
                attribution: "Professor Imna",
                text: "A shared-token premise remains contested and sortable.",
                createdAt: pinnedFinished.addingTimeInterval(-60)
            )
            let agentStatement = try PortableResearchStatement(
                author: .agent,
                kind: .agentFeedback,
                attribution: "Research Agent",
                text: "A shared-token dialectical objection remains sortable.",
                createdAt: pinnedFinished
            )
            let method = try Self.method(displayName: "Synthesize")
            let pinned = try PortableResearchRecord(
                id: pinnedRecordID,
                triptychID: triptychID,
                kind: .action,
                action: ResearchActionRecordIdentity(actionID: .synthesize),
                method: method,
                sourceReference: try ResearchSourceReference(
                    identity: .localFile(id: pinnedRecordID),
                    displayName: "Aristotle Source.pdf",
                    fingerprint: DocumentFingerprint(content: "source-v1")
                ),
                primaryNoteID: alpha.noteID,
                participatingNotes: [alpha, used, selectedOnly],
                statements: [researcherStatement, agentStatement],
                actuallyUsedMaterials: [try PortableResearchMaterialUse(
                    noteID: used.noteID,
                    note: used.note,
                    role: used.role,
                    title: used.title,
                    revision: used.startingRevision
                )],
                fidelityCompletion: .notRequired,
                startedAt: pinnedFinished.addingTimeInterval(-120),
                finishedAt: pinnedFinished,
                isPinned: true
            )

            let today = try Self.actionRecord(
                id: todayRecordID,
                triptychID: triptychID,
                note: alpha,
                method: method,
                text: "A newer sortable response.",
                finishedAt: now.addingTimeInterval(-60)
            )
            let tombstone = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000004")!,
                vaultID: analysisVaultID,
                path: "Deleted Position.md",
                role: .analysis,
                title: "Deleted Position",
                tombstone: true
            )
            let tombstoneRecord = try Self.actionRecord(
                id: tombstoneRecordID,
                triptychID: triptychID,
                note: tombstone,
                method: method,
                text: "tombstone-token remains historical.",
                finishedAt: calendar.date(byAdding: .day, value: -40, to: now)!
            )
            let other = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000005")!,
                vaultID: topicVaultID,
                path: "Other.md",
                role: .topic,
                title: "Other"
            )
            let otherVaultRecord = try Self.actionRecord(
                id: otherVaultRecordID,
                triptychID: triptychID,
                note: other,
                method: method,
                text: "other-vault-token",
                finishedAt: calendar.date(byAdding: .day, value: -50, to: now)!
            )
            let sharedOne = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000006")!,
                vaultID: analysisVaultID,
                path: "Shared One.md",
                role: .analysis,
                title: "Shared"
            )
            let sharedTwo = try Self.note(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000007")!,
                vaultID: topicVaultID,
                path: "Shared Two.md",
                role: .topic,
                title: "Shared"
            )
            let ambiguousOne = try Self.actionRecord(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000005")!,
                triptychID: triptychID,
                note: sharedOne,
                method: method,
                text: "first ambiguous identity",
                finishedAt: calendar.date(byAdding: .day, value: -60, to: now)!
            )
            let ambiguousTwo = try Self.actionRecord(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000006")!,
                triptychID: triptychID,
                note: sharedTwo,
                method: method,
                text: "second ambiguous identity",
                finishedAt: calendar.date(byAdding: .day, value: -61, to: now)!
            )
            let future = try Self.actionRecord(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000007")!,
                triptychID: triptychID,
                note: other,
                method: method,
                text: "sortable future",
                finishedAt: calendar.date(byAdding: .day, value: 1, to: now)!
            )

            records = [
                pinned, today, tombstoneRecord, otherVaultRecord,
                ambiguousOne, ambiguousTwo, future,
            ]
            fingerprints = Dictionary(uniqueKeysWithValues: records.map {
                ($0.id, DocumentFingerprint(data: Data("exact-\($0.id.uuidString) \n".utf8)))
            })
            catalogNotes = [WorkspaceCatalogNote(
                reference: VaultNoteReference(
                    vaultID: analysisVaultID,
                    vaultName: "Analyses",
                    vaultRole: .sourceCorpus,
                    relativePath: "New Akrasia.md",
                    stableNoteID: alphaNoteID.uuidString.lowercased()
                ),
                title: "Current Akrasia",
                aliases: ["Akrasia Alias"],
                zoteroItemKey: nil,
                zoteroSourceIdentity: nil,
                fingerprint: DocumentFingerprint(content: "current-alpha"),
                validationWarnings: []
            )]
        }

        func search(
            _ query: String,
            scope: SearchExecutionScope = .triptych
        ) throws -> ResearchRecordSearchIndex.Execution {
            let index = ResearchRecordSearchIndex(
                triptychID: triptychID,
                research: researchSnapshot(
                    records: records,
                    fingerprints: fingerprints,
                    isComplete: true
                ),
                catalogNotes: catalogNotes
            )
            return try index.search(
                ast: try ast(query),
                scope: scope,
                limit: 100,
                now: now,
                calendar: calendar
            )
        }

        func ast(_ query: String) throws -> SearchQueryAST {
            let parsed = SearchQueryParser.parse(query)
            #expect(parsed.diagnostics.isEmpty)
            return try #require(parsed.ast)
        }

        func researchSnapshot(
            records: [PortableResearchRecord],
            fingerprints: [UUID: DocumentFingerprint],
            isComplete: Bool
        ) -> WorkspaceResearchSnapshot {
            WorkspaceResearchSnapshot(
                finishedResearchRecords: records,
                finishedResearchRecordFingerprints: fingerprints,
                finishedResearchRecordSourceManifestHash: manifestHash,
                finishedResearchRecordProjectionIsComplete: isComplete,
                critiques: [],
                checkpointListing: TriptychCheckpointListing(
                    checkpoints: [],
                    unreadableEntries: []
                ),
                healthIssues: []
            )
        }

        private static func note(
            id: UUID,
            vaultID: UUID,
            path: String,
            role: ResearchActionTargetRole,
            title: String,
            tombstone: Bool = false
        ) throws -> PortableResearchNoteRevision {
            let fingerprint = DocumentFingerprint(content: "# \(title)\n")
            return try PortableResearchNoteRevision(
                noteID: id,
                note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                role: role,
                title: title,
                startingRevision: fingerprint,
                endingRevision: tombstone ? nil : fingerprint,
                isTombstone: tombstone
            )
        }

        private static func actionRecord(
            id: UUID,
            triptychID: UUID,
            note: PortableResearchNoteRevision,
            method: PortableResearchMethodReference,
            text: String,
            finishedAt: Date
        ) throws -> PortableResearchRecord {
            try PortableResearchRecord(
                id: id,
                triptychID: triptychID,
                kind: .action,
                action: ResearchActionRecordIdentity(actionID: .synthesize),
                method: method,
                primaryNoteID: note.noteID,
                participatingNotes: [note],
                statements: [try PortableResearchStatement(
                    author: .agent,
                    kind: .agentFeedback,
                    attribution: "Research Agent",
                    text: text,
                    createdAt: finishedAt
                )],
                fidelityCompletion: .notRequired,
                startedAt: finishedAt.addingTimeInterval(-60),
                finishedAt: finishedAt
            )
        }

        private static func method(
            displayName: String
        ) throws -> PortableResearchMethodReference {
            let profileRevision = DocumentFingerprint(content: "profile")
            return try PortableResearchMethodReference(
                registrationKey: ResearchSkillRegistrationKey(),
                displayName: displayName,
                profileRevision: profileRevision
            )
        }
    }
}
