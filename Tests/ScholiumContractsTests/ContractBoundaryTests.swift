import Foundation
import ScholiumContracts
import Testing

@Suite("Compiler boundary contracts")
struct ContractBoundaryTests {
    @Test("Exact source preserves BOM, CRLF, YAML spelling, and final newline")
    func exactSourceFidelity() throws {
        let source = "\u{FEFF}---\r\ntitle: 'Exact'\r\nunknown: >-\r\n  keep me\r\n---\r\n# Body 😀\r\n"
        let document = NoteDocument(relativePath: "Exact.md", rawContent: source)

        #expect(document.sourceBytes == Data(source.utf8))
        #expect(document.rawContent == source)
        #expect(document.newlineStyle == .crlf)
        #expect(document.fingerprint == DocumentFingerprint(data: Data(source.utf8)))
        #expect(try document.applying(.exactContent(source), timestampKey: nil) == source)
    }

    @Test("Stable identifiers and fingerprints retain their Codable representation")
    func codableRoundTrip() throws {
        let id = VaultQualifiedNoteID(
            vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            relativePath: "Unicode/理由.md"
        )
        let fingerprint = DocumentFingerprint(sha256: "abc123", byteCount: 42)
        let recoveryID = InterruptedSaveRecoveryID(
            vaultID: id.vaultID,
            transactionID: UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(try JSONDecoder().decode(
            VaultQualifiedNoteID.self,
            from: encoder.encode(id)
        ) == id)
        #expect(try JSONDecoder().decode(
            DocumentFingerprint.self,
            from: encoder.encode(fingerprint)
        ) == fingerprint)
        #expect(try JSONDecoder().decode(
            InterruptedSaveRecoveryID.self,
            from: encoder.encode(recoveryID)
        ) == recoveryID)
    }

    @Test("Agent recovery links preserve the Run, target, and source transaction")
    func researchRecoveryLinkRoundTrip() throws {
        let runID = UUID()
        let noteID = UUID()
        let vaultID = UUID()
        let sourceRecoveryID = InterruptedSaveRecoveryID(
            vaultID: vaultID,
            transactionID: UUID()
        )
        let link = ResearchWriteRecoveryReference(
            runID: runID,
            operationID: UUID(),
            target: ResearchWriteTargetHandle(runID: runID, noteID: noteID),
            sourceRecoveryID: sourceRecoveryID
        )
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: .noteSave,
            failure: "Unknown exact save result",
            files: [TriptychMutationRecoveryFile(
                vaultID: vaultID,
                path: "topics/Note.md",
                role: .savedNote,
                beforeRevision: DocumentFingerprint(content: "before"),
                intendedRevision: DocumentFingerprint(content: "after"),
                observedRevision: nil,
                state: .unreadable,
                detail: "Fixture"
            )],
            researchWrite: link
        )

        let decoded = try JSONDecoder().decode(
            TriptychMutationRecoveryRecord.self,
            from: JSONEncoder().encode(record)
        )
        #expect(decoded == record)
        #expect(decoded.researchWrite == link)
        #expect(decoded.researchWrite?.sourceRecoveryID == sourceRecoveryID)
    }

    @Test("Committed source outcomes remain distinct from post-commit warnings")
    func structuredErrors() {
        let revision = DocumentFingerprint(sha256: "revision", byteCount: 8)
        let outcome = WorkspaceMutationOutcome(
            committedValue: revision,
            derivedRefreshWarning: "index unavailable",
            identityRecoveryWarning: "identity unavailable",
            cleanupWarnings: [SaveCleanupWarning(
                kind: .displacedSourceCopy,
                message: "old source copy pending"
            )]
        )
        let researchError = ScholiumApplicationError.operationCommittedButRefreshFailed(
            operation: "research completion",
            reason: "index unavailable"
        )
        let uncertainError = ScholiumApplicationError.operationCommitUncertain(
            operation: "Researcher Evaluation save",
            reason: "replacement durability unavailable"
        )

        #expect(outcome.committedValue == revision)
        #expect(outcome.derivedRefreshWarning == "index unavailable")
        #expect(outcome.identityRecoveryWarning == "identity unavailable")
        #expect(outcome.cleanupWarnings.map(\.message) == ["old source copy pending"])
        #expect(researchError.durableMutationWasCommitted)
        #expect(researchError.mustNotRetryMutation)
        #expect(researchError.mutationRequiresReconciliation)
        #expect(researchError.refreshFailureReason == "index unavailable")
        #expect(!uncertainError.durableMutationWasCommitted)
        #expect(uncertainError.mustNotRetryMutation)
        #expect(uncertainError.mutationRequiresReconciliation)
        #expect(uncertainError.refreshFailureReason == nil)
    }

    @Test("Contract capability values remain delivery neutral")
    func requestAndResultValues() throws {
        let id = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "New.md")
        let request = DocumentCreationRequest(
            id: id,
            title: "New"
        )

        #expect(request.id == id)
        #expect(request.title == "New")
        #expect(WorkspaceRegistryError.incompleteWorkspace.localizedDescription.contains("incomplete"))
    }

    @Test("Interrupted save presentation never authorizes a changed source")
    func interruptedSaveSourceState() {
        #expect(InterruptedSaveRecoverySourceState.expectedRevision.permitsRecovery)
        #expect(InterruptedSaveRecoverySourceState.candidateRevision.permitsRecovery)
        #expect(!InterruptedSaveRecoverySourceState.changed(
            DocumentFingerprint(content: "external")
        ).permitsRecovery)
        #expect(!InterruptedSaveRecoverySourceState.missing.permitsRecovery)
        #expect(!InterruptedSaveRecoverySourceState.unavailable("permission").permitsRecovery)
    }

    @Test("Folder paths are relative locations rather than Markdown identities")
    func folderPathContract() throws {
        let path = try VaultRelativeFolderPath("Sources/现象学")
        #expect(path.rawValue == "Sources/现象学")
        #expect(path.components.map(String.init) == ["Sources", "现象学"])
        #expect(throws: VaultRelativeFolderPathError.self) {
            try VaultRelativeFolderPath("../Outside")
        }
        #expect(throws: VaultRelativeFolderPathError.self) {
            try VaultRelativeFolderPath("Sources/")
        }
    }
}
