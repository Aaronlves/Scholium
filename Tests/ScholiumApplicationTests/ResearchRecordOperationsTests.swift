import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

@Suite("Application Research Record operations")
struct ResearchRecordOperationsTests {
    @Test("Agent progress preserves validated Note references across restart")
    func progressPreservesValidatedReferencesAcrossRestart() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        let submitter = try ResearchRecordSubmitter(displayName: "Research Agent")
        let reference = try ResearchRecordNoteReference(
            noteID: noteID,
            relation: .basis,
            revision: note.fingerprint
        )

        let created = try await handle.agentCollaboration.recordProgress(.init(
            target: .new(question: "How should agency be understood?"),
            submittedBy: submitter,
            bodyMarkdown: "The first pass treats **freedom** as a basis.",
            noteReferences: [reference]
        ))
        #expect(created.kind == .created)
        #expect(created.revision.record.steps[0].noteReferences == [reference])

        let appended = try await handle.agentCollaboration.recordProgress(.init(
            target: .existing(
                recordID: created.revision.id,
                expectedFingerprint: created.revision.fingerprint,
                replacementQuestion: nil
            ),
            submittedBy: submitter,
            bodyMarkdown: "A second pass narrows the claim.",
            revisesStepIDs: [created.stepID]
        ))
        #expect(appended.kind == .appended)
        #expect(appended.revision.record.steps.count == 2)
        await runtime.shutdown()

        let reopenedRuntime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        let listing = try await reopened.agentCollaboration.researchRecords()
        #expect(listing.issues.isEmpty)
        #expect(listing.records.map(\.id) == [created.revision.id])
        #expect(listing.records[0].record.steps[0].noteReferences == [reference])
        #expect(listing.records[0].record.steps[1].revisesStepIDs == [created.stepID])
        await reopenedRuntime.shutdown()
    }

    @Test("Agent progress rejects stale Note references without creating a Record")
    func progressRejectsStaleReferencesWithoutCreation() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        defer { Task { await runtime.shutdown() } }
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let note = try #require(
            try await handle.snapshot().document(id: fixture.analysisNoteID)
        )
        let noteID = try #require(note.stableIdentity.resolvedID)
        let stale = DocumentFingerprint(
            sha256: String(repeating: "0", count: 64),
            byteCount: note.fingerprint.byteCount
        )
        let reference = try ResearchRecordNoteReference(
            noteID: noteID,
            relation: .basis,
            revision: stale
        )

        await #expect(throws: AgentCollaborationError.self) {
            _ = try await handle.agentCollaboration.recordProgress(.init(
                target: .new(question: "Should this fail?"),
                submittedBy: try ResearchRecordSubmitter(displayName: "Research Agent"),
                bodyMarkdown: "This step cites a stale Note revision.",
                noteReferences: [reference]
            ))
        }
        let listing = try await handle.agentCollaboration.researchRecords()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.isEmpty)
    }

    @Test("A correction preserves the original step and appends attributed history")
    func correctionAppendsHistory() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        defer { Task { await runtime.shutdown() } }
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let submitter = try ResearchRecordSubmitter(displayName: "Research Agent")
        let created = try await handle.agentCollaboration.recordProgress(.init(
            target: .new(question: "What changed?"),
            submittedBy: submitter,
            bodyMarkdown: "The original wording."
        ))

        let corrected = try await handle.agentCollaboration.correctRecordStep(.init(
            recordID: created.revision.id,
            stepID: created.stepID,
            expectedFingerprint: created.revision.fingerprint,
            submittedBy: submitter,
            bodyMarkdown: "The corrected wording.",
            revisesStepIDs: [],
            noteReferences: []
        ))

        let step = try #require(corrected.record.steps.first)
        #expect(step.bodyMarkdown == "The original wording.")
        #expect(step.currentBodyMarkdown == "The corrected wording.")
        #expect(step.corrections.count == 1)
    }
}
