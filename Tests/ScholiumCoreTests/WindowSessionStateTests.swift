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
        #expect(snapshot.documentMode == "livePreview")
    }

    @Test("Window-wide tabs and Document mode round-trip outside research vaults")
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
            openDocuments: [analysis, topic],
            selectedDocument: topic,
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: analysesVaultID,

                    documentPresentations: [
                        "A.md": WindowDocumentPresentationSnapshot(
                            scrollFraction: 0.25,
                            sourceFingerprint: "fingerprint",
                            selections: [WindowDocumentSelectionRange(anchor: 4, head: 9)],
                            focusTarget: .editor
                        )
                    ],
                    inspectorMode: "links"
                ),
                WindowWorkspaceSessionSnapshot(
                    workspace: .topicKnowledge,
                    vaultID: topicsVaultID,

                    inspectorMode: "related"
                ),
            ],
            documentMode: "source",
            libraryVisible: false,
            inspectorVisible: true,
            searchState: SearchWorkspaceState(scope: .triptych),
            documentTextScale: 2
        )

        try await store.save(snapshot)
        #expect(try await store.load(id: id) == snapshot)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        #expect(encoded?["documentMode"] as? String == "source")
        let workspaces = try #require(encoded?["workspaceSessions"] as? [[String: Any]])
        #expect(workspaces.allSatisfy { $0["documentMode"] == nil })
    }

    @Test("Unsupported window layouts neither authorize restoration nor get replaced")
    func unsupportedLayoutIsPreserved() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let snapshot = WindowSessionSnapshot()
        let directory = root.appendingPathComponent("Window Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(snapshot.id.uuidString + ".json")
        var unsupported = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        unsupported.removeValue(forKey: "documentMode")
        let bytes = try JSONSerialization.data(withJSONObject: unsupported, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: url)
        do {
            _ = try await store.load(id: snapshot.id)
            Issue.record("An unsupported layout cannot restore the window.")
        } catch is DecodingError {}
        do {
            try await store.save(snapshot)
            Issue.record("An unsupported layout cannot be replaced by a new snapshot.")
        } catch is DecodingError {}
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test("Normalization never invents replacement tabs or selections")
    func normalization() throws {
        let vaultID = UUID()
        let present = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Present.md")
        let missing = VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Missing.md")
        let snapshot = WindowSessionSnapshot(
            openDocuments: [present, missing],
            selectedDocument: missing,
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: vaultID,

                    documentPresentations: [
                        "Present.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.8),
                        "Missing.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.2),
                    ]
                )
            ]
        )

        let normalized = snapshot.normalized(
            availablePathsByVault: [vaultID: ["Present.md"]]
        )
        let session = try #require(
            normalized.workspaceSession(for: .paperAnalysis)
        )
        #expect(normalized.openDocuments == [present])
        #expect(normalized.selectedDocument == nil)
        #expect(
            session.documentPresentations == [
                "Present.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.8)
            ])
    }

    @Test("Wrongly typed and unreadable window records still block path migration", arguments: RecordFailure.allCases)
    func migrationDoesNotIgnoreRecordFailures(_ failure: RecordFailure) async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WindowSessionSnapshotStore(applicationSupportURL: root)
        let vaultID = UUID()
        let snapshot = WindowSessionSnapshot(openDocuments: [.init(vaultID: vaultID, relativePath: "Old.md")])
        try await store.save(snapshot)
        let directory = root.appendingPathComponent("Window Sessions", isDirectory: true)
        let healthyURL = directory.appendingPathComponent(snapshot.id.uuidString + ".json")
        let healthyBytes = try Data(contentsOf: healthyURL)
        let invalidURL = directory.appendingPathComponent(UUID().uuidString + ".json")
        switch failure {
        case .wrongType:
            var invalid = try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(WindowSessionSnapshot())) as? [String: Any])
            invalid["openDocuments"] = 7
            try JSONSerialization.data(withJSONObject: invalid).write(to: invalidURL)
        case .unreadable:
            try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: false)
        }
        do {
            try await store.migratePath(vaultID: vaultID, from: "Old.md", to: "New.md")
            Issue.record("A malformed or unreadable record must retain migration recovery.")
        } catch DecodingError.typeMismatch {
            #expect(failure == .wrongType)
        } catch {
            #expect(failure == .unreadable)
        }
        #expect(try Data(contentsOf: healthyURL) == healthyBytes)
        #expect(try await store.load(id: snapshot.id) == snapshot)
    }

    enum RecordFailure: CaseIterable, Sendable {
        case wrongType
        case unreadable
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
            openDocuments: [matchingDocument, peerDocument],
            selectedDocument: peerDocument,
            workspaceSessions: [
                WindowWorkspaceSessionSnapshot(
                    workspace: .paperAnalysis,
                    vaultID: vaultID,

                    documentPresentations: [
                        "Old.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.6)
                    ]
                ),
                WindowWorkspaceSessionSnapshot(
                    workspace: .topicKnowledge,
                    vaultID: peerVaultID,

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
        _ = try #require(
            migrated.workspaceSession(for: .topicKnowledge)
        )
        #expect(migrated.openDocuments.first?.relativePath == "New.md")
        #expect(
            analyses.documentPresentations == [
                "New.md": WindowDocumentPresentationSnapshot(scrollFraction: 0.6)
            ])
        #expect(migrated.selectedDocument == peerDocument)
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
