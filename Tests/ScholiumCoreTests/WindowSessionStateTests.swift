import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("External window-session persistence")
struct WindowSessionStateTests {
    @Test("New window sessions select Analyses without inventing open documents")
    func canonicalDefault() {
        let snapshot = WindowSessionSnapshot()
        #expect(snapshot.selectedWorkspace == .paperAnalysis)
        #expect(snapshot.workspaceSessions.isEmpty)
    }

    @Test("Role-partitioned tabs and modes round-trip outside research vaults")
    func roundTrip() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let id = UUID()
        let triptychID = UUID()
        let analysesVaultID = UUID()
        let topicsVaultID = UUID()
        let analysis = VaultQualifiedNoteID(
            vaultID: analysesVaultID,
            relativePath: "A.md"
        )
        let topic = VaultQualifiedNoteID(
            vaultID: topicsVaultID,
            relativePath: "B.md"
        )
        let snapshot = WindowSessionSnapshot(
            id: id,
            triptychID: triptychID,
            selectedWorkspace: .topicKnowledge,
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: analysesVaultID,
                    openDocuments: [analysis],
                    selectedDocument: analysis,
                    scrollPositions: ["A.md": 0.25],
                    inspectorMode: "connect",
                    documentMode: "source"
                ),
                WindowWorkspaceSessionSnapshot(
                    workspace: .topicKnowledge,
                    vaultID: topicsVaultID,
                    openDocuments: [topic],
                    selectedDocument: topic,
                    location: "setAside",
                    inspectorMode: "actions",
                    documentMode: "livePreview"
                ),
            ],
            libraryVisible: false,
            inspectorVisible: true,
            searchState: SearchWorkspaceState(scope: .triptych),
            documentTextScale: 2
        )

        try await store.save(snapshot)
        #expect(try await store.load(id: id) == snapshot)
    }

    @Test("Normalization never invents replacement tabs or selections")
    func normalization() throws {
        let vaultID = UUID()
        let present = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Present.md")
        let missing = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Missing.md")
        let snapshot = WindowSessionSnapshot(
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: vaultID,
                    openDocuments: [present, missing],
                    selectedDocument: missing,
                    scrollPositions: ["Present.md": 0.8, "Missing.md": 0.2]
                ),
            ]
        )

        let normalized = snapshot.normalized(
            availablePathsByVault: [vaultID: ["Present.md"]]
        )
        let session = try #require(
            normalized.workspaceSession(for: .paperAnalysis)
        )
        #expect(session.openDocuments == [present])
        #expect(session.selectedDocument == nil)
        #expect(session.scrollPositions == ["Present.md": 0.8])
    }

    @Test("A late older lifecycle generation cannot replace newer window state")
    func staleWriteGenerationIsRejected() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let id = UUID()
        let newer = WindowSessionSnapshot(
            id: id,
            selectedWorkspace: .output
        )
        let older = WindowSessionSnapshot(
            id: id,
            selectedWorkspace: .paperAnalysis
        )

        try await store.save(newer, generation: 2)
        try await store.save(older, generation: 1)

        #expect(try await store.load(id: id) == newer)
    }

    @Test("A confirmed move migrates only matching vault-qualified workspace state")
    func pathMigration() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let vaultID = UUID()
        let peerVaultID = UUID()
        let matchingDocument = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: "Old.md"
        )
        let peerDocument = VaultQualifiedNoteID(
            vaultID: peerVaultID,
            relativePath: "Old.md"
        )
        let snapshot = WindowSessionSnapshot(
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: vaultID,
                    openDocuments: [matchingDocument],
                    selectedDocument: matchingDocument,
                    scrollPositions: ["Old.md": 0.6]
                ),
                WindowWorkspaceSessionSnapshot(
                    workspace: .topicKnowledge,
                    vaultID: peerVaultID,
                    openDocuments: [peerDocument],
                    selectedDocument: peerDocument
                ),
            ]
        )
        try await store.save(snapshot)

        try await store.migratePath(
            vaultID: vaultID,
            from: "Old.md",
            to: "New.md"
        )

        let migrated = try #require(try await store.load(id: snapshot.id))
        let analyses = try #require(
            migrated.workspaceSession(for: .paperAnalysis)
        )
        let topics = try #require(
            migrated.workspaceSession(for: .topicKnowledge)
        )
        #expect(analyses.selectedDocument?.relativePath == "New.md")
        #expect(analyses.scrollPositions == ["New.md": 0.6])
        #expect(topics.selectedDocument == peerDocument)
    }

    @Test("Removing a session is idempotent")
    func remove() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let snapshot = WindowSessionSnapshot()
        try await store.save(snapshot)
        try await store.remove(id: snapshot.id)
        try await store.remove(id: snapshot.id)
        #expect(try await store.load(id: snapshot.id) == nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("scholium-session-\(UUID().uuidString)", isDirectory: true)
    }
}
