import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Transaction recovery presentation")
struct TransactionRecoveryPresentationTests {
    @Test("Created-note recovery names the exact control-state consequence")
    func creationActionsAreConsequential() {
        let present = TransactionRecoveryActionPresentation(record: record(
            operation: .noteCreation,
            role: .createdNote,
            state: .intendedBytesRemain
        ))
        #expect(present.buttonTitle == "Reconcile Created Note")
        #expect(present.message.contains("Zotero binding"))
        #expect(present.message.contains("Markdown source is never created, replaced, or removed"))

        let absent = TransactionRecoveryActionPresentation(record: record(
            operation: .noteCreation,
            role: .createdNote,
            state: .missing
        ))
        #expect(absent == present)

        let uncertain = TransactionRecoveryActionPresentation(record: record(
            operation: .noteCreation,
            role: .createdNote,
            state: .unreadable
        ))
        #expect(uncertain == present)
    }

    @Test("Save recovery uses generic researcher-confirmed completion")
    func saveRecoveryUsesGenericCompletion() {
        let save = TransactionRecoveryActionPresentation(record: record(
            operation: .noteSave,
            role: .savedNote,
            state: .intendedBytesRemain
        ))
        #expect(save == .generic)
        #expect(!save.message.contains("Run"))
    }

    @Test("Researcher managed creation presents real reconciliation without claiming an Agent Run")
    func managedCreationUsesConsequentialPresentation() {
        let vaultID = UUID()
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: .noteCreation,
            failure: "Fixture",
            files: [TriptychMutationRecoveryFile(
                vaultID: vaultID,
                path: "New.md",
                role: .createdNote,
                beforeRevision: nil,
                intendedRevision: DocumentFingerprint(content: "after"),
                observedRevision: nil,
                state: .missing,
                detail: "Fixture"
            )],
            managedCreation: ManagedCreationRecoveryReference(
                target: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "New.md"),
                reservedIdentityID: UUID()
            )
        )

        let presentation = TransactionRecoveryActionPresentation(record: record)
        #expect(presentation.buttonTitle == "Reconcile Created Note")
        #expect(!presentation.message.contains("Run"))
        #expect(presentation.message.contains("no other portable identity is changed"))
    }

    @Test("A committed reconciliation reports stale projections as a warning")
    func committedRefreshFailureUsesCommittedTruth() {
        #expect(TransactionRecoveryActionPresentation.committedRefreshMessage
            .contains("Reconciliation completed"))
        #expect(TransactionRecoveryActionPresentation.committedRefreshMessage
            .contains("recovery list has been reloaded"))
    }

    private func record(
        operation: TriptychMutationOperation,
        role: TriptychMutationFileRole,
        state: TriptychMutationRecoveryState
    ) -> TriptychMutationRecoveryRecord {
        let vaultID = UUID()
        return TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: operation,
            failure: "Fixture",
            files: [TriptychMutationRecoveryFile(
                vaultID: vaultID,
                path: "Fixture.md",
                role: role,
                beforeRevision: operation == .noteSave
                    ? DocumentFingerprint(content: "before")
                    : nil,
                intendedRevision: DocumentFingerprint(content: "after"),
                observedRevision: nil,
                state: state,
                detail: "Fixture"
            )],
            managedCreation: operation == .noteCreation
                ? ManagedCreationRecoveryReference(
                    target: VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: "Fixture.md"
                    ),
                    reservedIdentityID: UUID()
                )
                : nil
        )
    }
}
