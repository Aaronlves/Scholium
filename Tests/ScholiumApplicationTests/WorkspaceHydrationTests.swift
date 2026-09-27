import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Workspace demand hydration")
struct WorkspaceHydrationTests {
    @Test("Hydration preserves BOM, CRLF, malformed YAML, Unicode, and missing final newline")
    func exactBytesAndReadOnlyIdentity() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let relativePath = "E\u{301}tude.md"
        let bytes =
            Data([0xEF, 0xBB, 0xBF])
            + Data("---\r\ntitle: Étude\r\ninvalid: [\r\n---\r\n# Étude\r\nExact 😀 source".utf8)
        try bytes.write(to: fixture.analysesURL.appendingPathComponent(relativePath))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let vault = try #require(try await handle.snapshot().vault(id: fixture.analysisNoteID.vaultID))
        let summary = try #require(
            vault.documents.first {
                $0.id.relativePath.utf8.elementsEqual(relativePath.utf8)
            })
        let hydrated = try await handle.documents.hydrate(summary)
        #expect(hydrated.document.sourceBytes == bytes)
        #expect(hydrated.summary.validationWarnings == hydrated.document.validationWarnings)
        #expect(!hydrated.summary.validationWarnings.isEmpty)
        #expect(hydrated.document.relativePath.utf8.elementsEqual(relativePath.utf8))
        await runtime.shutdown()
    }

    @Test("A same-source graph publication during the read returns current metadata")
    func sameSourceDerivedPublication() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        defer { Task { await runtime.shutdown() } }
        let original = try #require(await handle.snapshot().document(id: fixture.analysisNoteID))
        let gate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await gate.hold() }
        let pending = Task { try await handle.documents.hydrate(original) }
        await gate.waitUntilEntered()

        try Data("# New incoming source\n\n[[Agency]]\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Incoming.md"))
        let refreshed = try await handle.discovery.refresh()
        let current = try #require(refreshed.document(id: fixture.analysisNoteID))
        #expect(current.fingerprint == original.fingerprint)
        #expect(current.graphCounts.incoming > original.graphCounts.incoming)
        await gate.release()
        let hydrated = try await pending.value
        #expect(hydrated.summary == current)
        #expect(hydrated.document.fingerprint == original.fingerprint)
        await handle.setHydrationPostReadBarrierForTesting(nil)
        await runtime.shutdown()
    }

    @Test("A changed source or closed runtime cannot publish a suspended read")
    func staleReadAndShutdown() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try #require(await handle.snapshot().document(id: fixture.analysisNoteID))
        let gate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await gate.hold() }
        let pending = Task { try await handle.documents.hydrate(original) }
        await gate.waitUntilEntered()
        try Data("# Agency\n\nExternal changed bytes.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent(fixture.analysisNoteID.relativePath),
            options: .atomic)
        await gate.release()
        await #expect(throws: WorkspaceHydrationError.self) { try await pending.value }
        await handle.setHydrationPostReadBarrierForTesting(nil)

        let fresh = try await handle.discovery.refresh()
        let next = try #require(fresh.document(id: fixture.analysisNoteID))
        let closeGate = HydrationReadGate()
        await handle.setHydrationPostReadBarrierForTesting { await closeGate.hold() }
        let closingRead = Task { try await handle.documents.hydrate(next) }
        await closeGate.waitUntilEntered()
        await runtime.shutdown()
        await closeGate.release()
        await #expect(throws: ScholiumApplicationError.self) { try await closingRead.value }
    }
}

private actor HydrationReadGate {
    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
