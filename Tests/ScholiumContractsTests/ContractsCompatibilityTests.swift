import Foundation
import ScholiumContracts
import Testing

@Suite("Compiler boundary contracts")
struct ContractsCompatibilityTests {
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
    func codableCompatibility() throws {
        let id = VaultQualifiedNoteID(
            vaultID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            relativePath: "Unicode/理由.md"
        )
        let fingerprint = DocumentFingerprint(sha256: "abc123", byteCount: 42)
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
    }

    @Test("Delivery errors retain committed-mutation evidence")
    func structuredErrors() {
        let revision = DocumentFingerprint(sha256: "revision", byteCount: 8)
        let error = ScholiumApplicationError.committedButRefreshFailed(
            revision,
            "index unavailable"
        )

        #expect(error.durableMutationWasCommitted)
        #expect(error.mustNotRetryMutation)
        #expect(error.committedDocumentRevision == revision)
        #expect(error.refreshFailureReason == "index unavailable")
    }

    @Test("Contract capability values remain delivery neutral")
    func requestAndResultValues() throws {
        let id = VaultQualifiedNoteID(vaultID: UUID(), relativePath: "New.md")
        let request = DocumentCreationRequest(
            id: id,
            title: "New",
            researchUnitScope: "One source",
            researchUnitLimitations: ["No comparative claim"]
        )

        #expect(request.id == id)
        #expect(request.researchUnitLimitations == ["No comparative claim"])
        #expect(WorkspaceRegistryError.incompleteWorkspace.localizedDescription.contains("incomplete"))
    }
}
